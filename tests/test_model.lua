-- Pure behavior tests. The tiny registry makes all expected timing independent
-- of the production spell catalog and requires no client API doubles.
local ns = {}
ns.Data = {
    categories = { {key="stun"}, {key="root"}, {key="fear"}, {key="interrupt"} },
    categoryByKey = {stun={},root={},fear={},interrupt={}},
    spells = {
        [100] = {id=100,name="Stun",category="stun",cdMin=45,cdMax=60},
        [200] = {id=200,name="Fear",category="fear",cdMin=0,cdMax=0},
        [300] = {id=300,name="Kick",category="interrupt",cdMin=12,cdMax=12,interrupt=true},
        [400] = {id=400,name="Root",category="root",cdMin=8,cdMax=8},
    },
    castToSpell = {[100]=100,[101]=100,[200]=200,[300]=300,[400]=400},
    resets = {[9000]={100,400}},
}
assert(loadfile(ADDON_DIR .. "/Model.lua"))("bjarkiCC", ns)

local cases = {}
local function test(name, fn) cases[#cases+1] = {name=name, fn=fn} end
local function eq(actual, expected, context)
    assert(actual == expected, (context or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function new()
    assert(ns.Model and type(ns.Model.New) == "function", "Model.New is not implemented")
    return ns.Model.New(20)
end
local function effect(category, spellID, expires, appliedAt)
    return {category=category or "stun", spellID=spellID or 100, expires=expires, appliedAt=appliedAt}
end
local function baseline(model, guid)
    model:Observe(guid, {}, 0, true)
    model:Observe(guid, {}, 20, true)
end
local function only(rows)
    eq(#rows, 1, "row count")
    return rows[1]
end

test("first observed application keeps unknown earlier history", function()
    local m = new()
    m:Observe("a", {a=effect("stun",100,8)}, 0, true)
    local r = only(m:GetDR("a",0))
    eq(r.stage,1); eq(r.uncertain,true); eq(r.active,true); eq(r.started,0)
    m:Observe("a", {a=effect("stun",100,8)}, 19, true)
    eq(only(m:GetDR("a",19)).uncertain,true,"active history must not become confident")
    eq(#m:GetDR("a",20),0,"uncertain application still has a bounded timer")
end)

test("full observed quiet reset permits a definite first stage", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    local r = only(m:GetDR("a",21))
    eq(r.stage,1); eq(r.uncertain,false); eq(r.duration,20)
    eq(r.active,true); eq(r.remaining,20); eq(r.started,21)
    r=only(m:GetDR("a",24)); eq(r.active,true); eq(r.remaining,17); eq(r.started,21)
end)

test("polling stable aura key does not count more applications", function()
    local m = new(); baseline(m,"a")
    for now=21,25 do m:Observe("a", {key=effect("stun",100,30)}, now, true) end
    local r = only(m:GetDR("a",25))
    eq(r.stage,1); eq(r.uncertain,false); eq(r.started,21); eq(r.remaining,16)
end)

test("same spell on a new stable key increments and caps stage", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {b=effect()}, 22, true)
    local r=only(m:GetDR("a",22)); eq(r.stage,2); eq(r.started,22)
    m:Observe("a", {c=effect()}, 23, true)
    eq(only(m:GetDR("a",23)).stage,3)
    m:Observe("a", {d=effect()}, 24, true)
    r=only(m:GetDR("a",24)); eq(r.stage,3); eq(r.started,24)
end)

test("overlapping applications refresh on the last application only", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,24)}, 21, true)
    m:Observe("a", {a=effect("stun",100,24),b=effect("stun",101,30)}, 22, true)
    m:Observe("a", {b=effect("stun",101,30)}, 24, true)
    local r=only(m:GetDR("a",29)); eq(r.active,true); eq(r.stage,2); eq(r.started,22); eq(r.remaining,13)
    m:Observe("a", {}, 30, true)
    r=only(m:GetDR("a",35)); eq(r.active,false); eq(r.started,22); eq(r.remaining,7)
    eq(#m:GetDR("a",41.99),1); eq(#m:GetDR("a",42),0)
    m:Observe("a", {c=effect()}, 43, true)
    r=only(m:GetDR("a",43)); eq(r.stage,1); eq(r.uncertain,false)
end)

test("instant break and natural removal never restart the application timer", function()
    local m = new(); baseline(m,"a"); baseline(m,"b")
    m:Observe("a", {a=effect("stun",100,30)}, 21, true)
    m:Observe("a", {}, 21, true)
    local r=only(m:GetDR("a",22)); eq(r.active,false); eq(r.started,21); eq(r.remaining,19)
    m:Observe("b", {b=effect("stun",100,30)}, 21, true)
    m:Observe("b", {}, 30, true)
    r=only(m:GetDR("b",31)); eq(r.active,false); eq(r.started,21); eq(r.remaining,10)
    eq(#m:GetDR("a",41),0); eq(#m:GetDR("b",41),0)
end)

test("reported expiration has no influence on the application timer", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,25)}, 21, true)
    local r=only(m:GetDR("a",26)); eq(r.active,true); eq(r.started,21); eq(r.remaining,15)
    eq(#m:GetDR("a",41),0)
    m:Observe("a", {}, 42, true)
    eq(#m:GetDR("a",42),0,"late removal cannot create a new timer")
end)

test("timer expires while aura remains and stable polling never recreates it", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,100)}, 21, true)
    eq(#m:GetDR("a",41),0)
    m:Observe("a", {a=effect("stun",100,100)}, 42, true)
    m:Observe("a", {a=effect("stun",100,101)}, 43, true)
    eq(#m:GetDR("a",43),0,"unchanged identity must remain remembered after timer expiry")
    m:Observe("a", {a=effect("stun",100,101),b=effect("stun",101,105)}, 44, true)
    local r=only(m:GetDR("a",44)); eq(r.stage,1); eq(r.started,44); eq(r.remaining,20)
    m:Observe("a", {a=effect("stun",100,101)}, 45, true)
    r=only(m:GetDR("a",45)); eq(r.stage,1); eq(r.started,44); eq(r.remaining,19)
end)

test("reapplication at the timer boundary starts the first stage", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {b=effect()}, 41, true)
    local r=only(m:GetDR("a",41)); eq(r.stage,1); eq(r.started,41); eq(r.remaining,20)
end)

test("different categories keep independent application deadlines", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {a=effect(),b=effect("root",400)}, 25, true)
    local rows=m:GetDR("a",26)
    eq(#rows,2); eq(rows[1].started,21); eq(rows[1].remaining,15)
    eq(rows[2].started,25); eq(rows[2].remaining,19)
    local r=only(m:GetDR("a",41)); eq(r.category,"root"); eq(r.remaining,4)
end)

test("expiration extension marks refresh ambiguity without counting a poll", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,25)}, 21, true)
    m:Observe("a", {a=effect("stun",100,29)}, 22, true)
    local r=only(m:GetDR("a",22)); eq(r.stage,1); eq(r.uncertain,true); eq(r.started,21); eq(r.remaining,19)
    m:Observe("a", {a=effect("stun",100,29)}, 50, true)
    eq(#m:GetDR("a",50),0)
end)

test("incomplete snapshot invalidates stage continuity until quiet reset", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {}, 22, false)
    local r=only(m:GetDR("a",22)); eq(r.uncertain,true); eq(r.active,true); eq(r.started,21); eq(r.remaining,19)
    m:Observe("a", {b=effect()}, 23, true)
    eq(only(m:GetDR("a",23)).uncertain,true)
    m:Observe("a", {}, 24, true)
    m:Observe("a", {c=effect()}, 45, true)
    r=only(m:GetDR("a",45)); eq(r.stage,1); eq(r.uncertain,false)
end)

test("partial snapshots cannot restart or invent an application timer", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {}, 22, true)
    m:Observe("a", {}, 30, false)
    local r=only(m:GetDR("a",30)); eq(r.started,21); eq(r.remaining,11); eq(r.uncertain,true)
    m:Observe("a", {}, 41, false)
    m:Observe("a", {}, 42, true)
    eq(#m:GetDR("a",42),0)
    m:Observe("a", {b=effect()}, 43, true)
    r=only(m:GetDR("a",43)); eq(r.stage,1); eq(r.started,43); eq(r.uncertain,true)
end)

test("expired aura identities survive unreadable snapshots", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {}, 42, false)
    m:Observe("a", {a=effect()}, 43, true)
    eq(#m:GetDR("a",43),0)
    m:Observe("a", {}, 44, true)
    m:Observe("a", {a=effect()}, 45, true)
    local r=only(m:GetDR("a",45)); eq(r.stage,1); eq(r.started,45); eq(r.uncertain,true)
end)

test("new readable application in a partial snapshot starts an uncertain timer", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, false)
    local r=only(m:GetDR("a",22)); eq(r.stage,1); eq(r.started,21); eq(r.remaining,19); eq(r.uncertain,true)
    m:Observe("a", {}, 23, false)
    r=only(m:GetDR("a",23)); eq(r.started,21); eq(r.remaining,18); eq(r.active,true)
end)

test("gap during quiet reset restarts confidence window", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {}, 22, true)
    m:Observe("a", {}, 30, false)
    m:Observe("a", {}, 40, true)
    m:Observe("a", {b=effect()}, 50, true)
    eq(only(m:GetDR("a",50)).uncertain,true)
end)

test("target identities never share DR history and forgetting loses confidence", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("b", {a=effect()}, 22, true)
    eq(only(m:GetDR("b",22)).stage,1); eq(only(m:GetDR("b",22)).uncertain,true)
    eq(only(m:GetDR("a",22)).uncertain,false)
    m:Forget("a"); eq(#m:GetDR("a",22),0)
    m:Observe("a", {a=effect()}, 23, true)
    eq(only(m:GetDR("a",23)).uncertain,true)
end)

test("rows follow category order and caller mutation cannot alter stored observations", function()
    local m = new(); baseline(m,"a")
    local effects={root=effect("root",400),stun=effect()}
    m:Observe("a",effects,21,true)
    effects.stun.category="fear"
    local rows=m:GetDR("a",21)
    eq(#rows,2); eq(rows[1].category,"stun"); eq(rows[2].category,"root")
    rows[1].stage=99
    eq(m:GetDR("a",21)[1].stage,1)
end)

test("rank cast IDs normalize and preserve reduced cooldown range", function()
    local m = new()
    m:Cast("a","Alice",101,10,"cast1",false)
    local r=only(m:GetCooldowns(20))
    eq(r.guid,"a"); eq(r.name,"Alice"); eq(r.spellID,100); eq(r.category,"stun")
    eq(r.started,10); eq(r.duration,60); eq(r.remaining,50); eq(r.earlyRemaining,35)
    eq(r.manual,false); eq(r.interrupt,false)
    r=only(m:GetCooldowns(60)); eq(r.earlyRemaining,0); eq(r.remaining,10)
    eq(#m:GetCooldowns(70),0)
end)

test("cast ID dedup survives dual unit events and does not delay cooldown", function()
    local m = new()
    m:Cast("a","Alice",100,10,"same",false)
    m:Cast("a","Alice",101,10.4,"same",false)
    eq(only(m:GetCooldowns(11)).started,10)
    m:Cast("a","Alice",100,12,"new",false)
    eq(only(m:GetCooldowns(12)).started,12)
end)

test("nil cast IDs deduplicate only a very short time window", function()
    local m = new()
    m:Cast("a","Alice",100,10,nil,false)
    m:Cast("a","Alice",101,10.05,nil,false)
    eq(only(m:GetCooldowns(11)).started,10)
    m:Cast("a","Alice",100,11,nil,false)
    eq(only(m:GetCooldowns(11)).started,11)
end)

test("mixed missing and present cast IDs deduplicate in both event orders", function()
    local m = new()
    m:Cast("a","Alice",100,10,nil,false)
    m:Cast("a","Alice",101,10.05,"real1",false)
    eq(only(m:GetCooldowns(11)).started,10,"ID after missing ID")
    m:Cast("a","Alice",100,12,"real2",false)
    m:Cast("a","Alice",101,12.05,nil,false)
    eq(only(m:GetCooldowns(13)).started,12,"missing ID after ID")
    m:Cast("a","Alice",100,14,"real3",false)
    m:Cast("a","Alice",100,14.05,"real4",false)
    eq(only(m:GetCooldowns(15)).started,14.05,"distinct known casts must remain distinct")
end)

test("distinct casters and same cast IDs keep independent records", function()
    local m = new()
    m:Cast("b","Bob",100,10,"same",false)
    m:Cast("a","Alice",100,12,"same",false)
    local rows=m:GetCooldowns(15)
    eq(#rows,2); eq(rows[1].guid,"a"); eq(rows[2].guid,"b")
    eq(only(m:GetCooldowns(15,"b")).started,10)
end)

test("canonical overrides and manual observations label actual timer", function()
    local m = new()
    m:Cast("a","Alice",101,10,"1",true,{[100]=50})
    local r=only(m:GetCooldowns(20))
    eq(r.duration,50); eq(r.remaining,40); eq(r.earlyRemaining,40); eq(r.manual,true)
    m:Cast("a","Alice",300,11,"2",false)
    local rows=m:GetCooldowns(20)
    eq(#rows,2); eq(rows[2].interrupt,true)
end)

test("spammable and unknown abilities never create cooldown rows", function()
    local m = new()
    m:Cast("a","Alice",200,10,"fear",false,{[200]=30})
    m:Cast("a","Alice",123456,10,"unknown",false)
    eq(#m:GetCooldowns(10),0)
    eq(#m:GetDR("a",10),0,"a cast is not proof that a DR effect applied")
end)

test("visible reset clears only related spells of its caster", function()
    local m = new()
    m:Cast("a","Alice",100,10,"1",false)
    m:Cast("a","Alice",300,10,"2",false)
    m:Cast("a","Alice",400,10,"3",false)
    m:Cast("b","Bob",100,10,"1",false)
    m:Cast("a","Alice",9000,11,"reset",false)
    eq(only(m:GetCooldowns(11,"a")).spellID,300)
    eq(only(m:GetCooldowns(11,"b")).spellID,100)
    m:Cast("a","Alice",100,11.1,"new",false)
    m:Cast("a","Alice",9000,11.2,"reset",false)
    eq(#m:GetCooldowns(12,"a"),2,"duplicate reset event cannot clear a new cast")
end)

test("expired cooldowns disappear and returned rows are isolated copies", function()
    local m = new()
    m:Cast("a","Alice",300,10,"1",false)
    only(m:GetCooldowns(11)).duration=999
    eq(only(m:GetCooldowns(11)).duration,12)
    eq(#m:GetCooldowns(22),0)
    m:Cast("a","Alice",300,10000,"1",false)
    eq(only(m:GetCooldowns(10000)).started,10000,"old dedup memory must expire")
end)

test("forgetting target observation preserves independently observed cooldowns", function()
    local m = new()
    m:Cast("a","Alice",100,10,"1",false)
    m:Observe("a",{a=effect()},10,true)
    m:Forget("a")
    eq(#m:GetDR("a",11),0)
    eq(only(m:GetCooldowns(11)).remaining,59)
end)

test("long running visible caster churn keeps retained timers bounded", function()
    local m = new()
    for i=1,300 do m:Cast("unit"..i,"Caster "..i,100,10,"1",false) end
    local rows=m:GetCooldowns(11)
    assert(#rows>0 and #rows<300,"caster memory must have a finite cap")
    eq(#m:GetCooldowns(1000),0)
end)

test("cast estimates are separate uncertain predictions and can be hidden", function()
    local m = new()
    eq(m:EstimateDR("a",100,"stun",10,"Cast-1"),true)
    local r = only(m:GetDR("a",11))
    eq(r.stage,1); eq(r.started,10); eq(r.remaining,19)
    eq(r.uncertain,true); eq(r.estimated,true); eq(r.active,false)
    eq(m.units.a,nil,"an estimate must not create observed history")
    eq(#m:GetDR("a",11,false),0,"the toggle immediately excludes predictions")
    eq(#m:GetDR("a",30),0,"application clock expires regardless of outcome")
end)

test("cast estimate stage overlays old observations without mutating them", function()
    local m = new(); baseline(m,"a")
    m:Observe("a",{a=effect()},21,true)
    m:EstimateDR("a",100,"stun",25,"Cast-1")
    eq(only(m:GetDR("a",25)).stage,2)
    local actual=only(m:GetDR("a",25,false))
    eq(actual.stage,1); eq(actual.started,21); eq(actual.uncertain,false)
    m:Observe("a",{a=effect()},26,true)
    eq(only(m:GetDR("a",26)).estimated,true,"polling an old aura is not a new application")
    m:EstimateDR("a",100,"stun",27,"Cast-2")
    eq(only(m:GetDR("a",27)).stage,3)
    m:Observe("a",{b=effect("stun",100,48,28)},28,true)
    local r=only(m:GetDR("a",28))
    eq(r.stage,2,"observed stage ignores every prediction")
    eq(r.estimated,false); eq(r.started,28)
end)

test("actual observation on either side of cast success avoids double counting", function()
    local m = new(); baseline(m,"a")
    m:EstimateDR("a",100,"stun",21,"Cast-1",20)
    m:Observe("a",{a=effect()},21.05,true)
    eq(only(m:GetDR("a",21.05)).stage,1)
    eq(only(m:GetDR("a",21.05)).estimated,false)
    m:Observe("a",{b=effect()},25,true)
    eq(m:EstimateDR("a",100,"stun",25.05,"Cast-2",24),false)
    eq(only(m:GetDR("a",25.05)).stage,2)
    eq(only(m:GetDR("a",25.05)).estimated,false)
end)

test("cast estimates deduplicate, bound memory, and forget alongside DR", function()
    local m = new()
    m:EstimateDR("a",100,"stun",10,"Cast-1")
    eq(m:EstimateDR("a",100,"stun",11,"Cast-1"),false)
    eq(only(m:GetDR("a",11)).stage,1)
    m:Forget("a"); eq(#m:GetDR("a",11),0)
    for i=1,300 do m:EstimateDR("u"..i,100,"stun",i,"Cast-"..i) end
    local count=0; for _ in pairs(m.estimates) do count=count+1 end
    assert(count<=128,"prediction GUID memory must be bounded")
    m:PruneEstimates(1000); eq(next(m.estimates),nil)
end)

test("late readable application uses its original clock", function()
    local m = new(); baseline(m,"a")
    m:Observe("a",{a=effect("stun",100,41,21)},30,true)
    local r=only(m:GetDR("a",30)); eq(r.started,21); eq(r.remaining,11); eq(r.stage,1)
    m:Observe("a",{},31,true)
    eq(only(m:GetDR("a",31)).remaining,10,"removal cannot restart the original clock")
end)

test("an already expired late witness is remembered without a new timer", function()
    local m = new()
    m:Observe("a",{a=effect("stun",100,80,10)},31,true)
    eq(#m:GetDR("a",31),0)
    m:Observe("a",{a=effect("stun",100,80)},32,true)
    eq(#m:GetDR("a",32),0,"losing readable timing cannot resurrect the known identity")
end)

test("an older late witness never rewinds a newer application", function()
    local m = new(); baseline(m,"a")
    m:Observe("a",{b=effect("stun",100,50,25)},25,true)
    m:Observe("a",{a=effect("stun",100,45,21),b=effect("stun",100,50,25)},30,true)
    local r=only(m:GetDR("a",30)); eq(r.started,25); eq(r.remaining,15); eq(r.uncertain,true)
end)

test("timed confirmation replaces a prediction without restarting at arrival", function()
    local m = new(); baseline(m,"a")
    m:EstimateDR("a",100,"stun",21,"Cast-1",20.9)
    m:Observe("a",{a=effect("stun",100,41,21)},30,true)
    local r=only(m:GetDR("a",30)); eq(r.started,21); eq(r.remaining,11); eq(r.stage,1); eq(r.estimated,false)
end)

test("untimed confirmation retains an earlier same-spell prediction clock", function()
    local m = new(); baseline(m,"a")
    m:EstimateDR("a",100,"stun",21,"Cast-1",20.9)
    m:Observe("a",{a=effect()},30,true)
    local r=only(m:GetDR("a",30)); eq(r.started,21); eq(r.remaining,11)
    eq(r.stage,1); eq(r.estimated,false); eq(r.uncertain,true); eq(r.timeEstimated,true)
end)

test("fresh history at arrival cannot make a late application confident", function()
    local m = new(); m:Observe("a",{},10,true)
    m:Observe("a",{a=effect("stun",100,40,21)},31,true)
    eq(only(m:GetDR("a",31)).uncertain,true,"history proof is measured before application")
end)

test("stable aura identity with a new LoC application timestamp advances once", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="loc"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,45,25); b.applicationSource="loc"
    m:Observe("a",{a=b},25,true)
    local r=only(m:GetDR("a",25)); eq(r.stage,2); eq(r.started,25)
    m:Observe("a",{a=b},26,true)
    eq(only(m:GetDR("a",26)).stage,2); eq(only(m:GetDR("a",26)).started,25)
    b=effect("stun",100,45.0001,25.0001); b.applicationSource="loc"
    m:Observe("a",{a=b},27,true); eq(only(m:GetDR("a",27)).stage,2,"rounding drift is not a reapplication")
end)

test("aura-derived refresh requires a newer start and a changed expiration", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,41,23); b.applicationSource="aura"
    m:Observe("a",{a=b},24,true)
    eq(only(m:GetDR("a",24)).stage,1,"duration adjustment alone is not a new application")
    b=effect("stun",100,45,25); b.applicationSource="aura"
    m:Observe("a",{a=b},25,true)
    local r=only(m:GetDR("a",25)); eq(r.stage,2); eq(r.started,25)
    m:Observe("a",{a=b},26,true); eq(only(m:GetDR("a",26)).stage,2)
end)

test("temporarily missing timing cannot turn a stable poll into reapplication", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="loc"
    m:Observe("a",{a=a},21,true)
    m:Observe("a",{a=effect("stun",100,41)},22,false)
    m:Observe("a",{a=a},23,true)
    eq(only(m:GetDR("a",23)).stage,1); eq(only(m:GetDR("a",23)).started,21)
end)

test("newly readable timing corrects the current identity without another stage", function()
    local m = new(); baseline(m,"a")
    m:Observe("a",{a=effect()},30,true)
    local a=effect("stun",100,41,21); a.applicationSource="loc"
    m:Observe("a",{a=a},31,true)
    local r=only(m:GetDR("a",31)); eq(r.started,21); eq(r.remaining,10); eq(r.stage,1)
end)

test("newly readable expired timing clears but cannot resurrect an identity", function()
    local m = new()
    m:Observe("a",{a=effect()},30,true)
    local a=effect("stun",100,60,10); a.applicationSource="loc"
    m:Observe("a",{a=a},31,true)
    eq(#m:GetDR("a",31),0)
    m:Observe("a",{a=a},32,true); eq(#m:GetDR("a",32),0)
    m = new(); m:Observe("a",{a=effect()},0,true); eq(#m:GetDR("a",20),0)
    a=effect("stun",100,60,0); a.applicationSource="loc"
    m:Observe("a",{a=a},21,true); eq(#m:GetDR("a",21),0)
end)

test("derived refresh advances observed stage while preserving ambiguity", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,45,25); b.applicationSource="aura"
    m:Observe("a",{a=b},25,true)
    local r=only(m:GetDR("a",25)); eq(r.stage,2); eq(r.uncertain,true)
end)

test("a new readable start after an untimed observation identifies reapplication", function()
    for _,source in ipairs({"loc","aura"}) do
        local m = new(); baseline(m,"a")
        m:Observe("a",{a=effect("stun",100,41)},21,true)
        local a=effect("stun",100,45,25); a.applicationSource=source
        m:Observe("a",{a=a},26,true)
        local r=only(m:GetDR("a",26)); eq(r.stage,2); eq(r.started,25); eq(r.remaining,19)
        m:Observe("a",{a=a},27,true); eq(only(m:GetDR("a",27)).stage,2)
    end
end)

test("explicit LoC timing corrects the same application derived from aura duration", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41.3,21.3); a.applicationSource="aura"
    m:Observe("a",{a=a},22,true)
    local b=effect("stun",100,41,21); b.applicationSource="loc"
    m:Observe("a",{a=b},23,true)
    local r=only(m:GetDR("a",23)); eq(r.stage,1); eq(r.started,21); eq(r.remaining,18)
end)

test("a shorter diminished refresh advances the same aura identity once", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,120,100); a.applicationSource="aura"
    m:Observe("a",{a=a},100,true)
    local b=effect("stun",100,115,105); b.applicationSource="aura"
    m:Observe("a",{a=b},105,true)
    local r=only(m:GetDR("a",105)); eq(r.stage,2); eq(r.started,105); eq(r.remaining,20); eq(r.uncertain,true)
    m:Observe("a",{a=b},106,true)
    r=only(m:GetDR("a",106)); eq(r.stage,2); eq(r.started,105); eq(r.remaining,19)
end)

test("a new explicit LoC start after aura observation is a reapplication", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,35,25); b.applicationSource="loc"
    m:Observe("a",{a=b},25,true)
    local r=only(m:GetDR("a",25)); eq(r.stage,2); eq(r.started,25)
    m:Observe("a",{a=b},26,true); eq(only(m:GetDR("a",26)).stage,2)
end)

test("explicit timing can correct a later refresh without counting it again", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,35.3,25.3); b.applicationSource="aura"
    m:Observe("a",{a=b},26,true)
    local c=effect("stun",100,35,25); c.applicationSource="loc"
    m:Observe("a",{a=c},27,true)
    local r=only(m:GetDR("a",27)); eq(r.stage,2); eq(r.started,25); eq(r.remaining,18)
end)

local function runModelTests()
    local failed=0
    for _, case in ipairs(cases) do
        local ok, err=pcall(case.fn)
        if ok then print("PASS "..case.name) else failed=failed+1; print("FAIL "..case.name..": "..tostring(err)) end
    end
    print(string.format("Model: %d passed, %d failed",#cases-failed,failed))
    return failed
end
assert(runModelTests() == 0, "model behavioral tests failed")
