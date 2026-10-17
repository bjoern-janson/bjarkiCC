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
    -- The older fixtures exercise the explicitly configured 20s end window.
    return ns.Model.New(20, 20)
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

test("live a385 starts a fresh cycle after the provisional eighteen second end window", function()
    local m=ns.Model.New(20)
    local function observe(id, start, expiry, now)
        local value=effect("incapacitate",2637,expiry,start); value.applicationSource="loc"
        m:Observe("a",{[id]=value},now,true)
        return only(m:GetDR("a",now))
    end
    m:Observe("a",{},2657324.860,true)
    eq(observe("a:381",2657421.750,2657441.750,2657421.753).stage,1)
    eq(observe("a:381",2657432.500,2657442.500,2657432.543).stage,2)
    m:Observe("a",{},2657442.308,true)
    eq(observe("a:383",2657444.500,2657449.500,2657444.619).stage,3)
    m:Observe("a",{},2657449.235,true)
    local row=observe("a:385",2657467.250,2657487.250,2657467.256)
    eq(row.stage,1,"full application 18.015s after the observed end must not retain stage three")
    eq(row.stageResetAt,2657505.250)
    eq(row.started,2657467.250); eq(row.duration,20)
end)

test("stage resets at eighteen seconds after removal rather than at application expiry", function()
    for _,case in ipairs({{time=122.999,stage=2},{time=123,stage=1}}) do
        local m=ns.Model.New(20)
        m:Observe("a",{first=effect("stun",100,120,100)},100,true)
        m:Observe("a",{},105,true)
        m:Observe("a",{next=effect("stun",100,case.time+10,case.time)},case.time,true)
        eq(only(m:GetDR("a",case.time)).stage,case.stage)
    end
end)

test("application countdown customization does not change observed stage reset", function()
    local m=ns.Model.New(30)
    m:Observe("a",{first=effect("stun",100,110,100)},100,true)
    m:Observe("a",{},110,true)
    local row=only(m:GetDR("a",120))
    eq(row.remaining,10); eq(row.duration,30); eq(row.stageResetAt,128)
    eq(#m:GetDR("a",128),0,"an expired stage must not linger for the longer application clock")
    m=ns.Model.New(10)
    m:Observe("a",{first=effect("stun",100,110,100)},100,true)
    m:Observe("a",{},110,true)
    row=only(m:GetDR("a",115)); eq(row.remaining,0); eq(row.stageResetAt,128)
    m:Observe("a",{next=effect("stun",100,130,120)},120,true)
    eq(only(m:GetDR("a",120)).stage,2)
end)

test("explicit stage interval can retain the former twenty second policy", function()
    local m=ns.Model.New(10,20)
    m:Observe("a",{first=effect("stun",100,110,100)},100,true)
    m:Observe("a",{},110,true)
    local row=only(m:GetDR("a",129)); eq(row.remaining,0); eq(row.stageResetAt,130)
    m:Observe("a",{next=effect("stun",100,139,129)},129,true)
    eq(only(m:GetDR("a",129)).stage,2)
end)

test("instant break hides the expired stage before the application clock finishes", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{first=effect("stun",100,120,100)},100,true)
    m:Observe("a",{},100,true)
    local row=only(m:GetDR("a",117)); eq(row.remaining,3); eq(row.stage,1)
    eq(#m:GetDR("a",118),0,"do not display an old stage for the last two application seconds")
    m:Observe("a",{next=effect("stun",100,138,118)},118,true)
    row=only(m:GetDR("a",118)); eq(row.stage,1); eq(row.remaining,20)
end)

test("unknown and overlapping CC ends use the separate stage interval", function()
    local m=ns.Model.New(30,18)
    m:Observe("a",{long=effect("stun",100,140,100)},100,true)
    m:Observe("a",{long=effect("stun",100,140,100),short=effect("stun",101,115,110)},110,true)
    m:Observe("a",{long=effect("stun",100,140,100)},115,true)
    m:Observe("a",{},130,true)
    eq(only(m:GetDR("a",131)).stageResetAt,148)
    eq(#m:GetDR("a",148),0)
    m=ns.Model.New(30,18)
    m:Observe("a",{unknown=effect("stun",100,nil,100)},100,true)
    m:Observe("a",{},130,false)
    eq(only(m:GetDR("a",130)).stageResetPending,true)
    m:Observe("a",{},135,true)
    eq(only(m:GetDR("a",136)).stageResetAt,153)
    eq(#m:GetDR("a",153),0)
end)

test("unconfirmed casts keep their application window independently of stage interval", function()
    local m=ns.Model.New(30,18)
    eq(m:EstimateDR("a",100,"stun",100,"first",100),true)
    local row=only(m:GetDR("a",125)); eq(row.stage,1); eq(row.remaining,5)
    eq(m:EstimateDR("a",100,"stun",125,"second",125),true)
    row=only(m:GetDR("a",125)); eq(row.stage,2); eq(row.remaining,30)
    eq(#m:GetDR("a",155),0)
end)

test("quiet observation confidence uses the stage interval not the application display", function()
    local m=ns.Model.New(30,18)
    m:Observe("a",{},100,true)
    m:Observe("a",{first=effect("stun",100,128,118)},118,true)
    eq(only(m:GetDR("a",118)).uncertain,false)
    m=ns.Model.New(10,20)
    m:Observe("a",{},100,true)
    m:Observe("a",{first=effect("stun",100,128,118)},118,true)
    eq(only(m:GetDR("a",118)).uncertain,true)
end)

-- 0.4.7 policy: the visible application countdown and category stage lifetime
-- are separate. These regressions intentionally retain rows at remaining=0.
test("full half quarter chain retains stage after the first application countdown", function()
    local m=new()
    m:Observe("a",{full=effect("stun",100,120,100)},100,true)
    m:Observe("a",{},120,true)
    local r=only(m:GetDR("a",121)); eq(r.remaining,0); eq(r.applicationExpired,true)
    eq(r.stage,1); eq(r.stageResetAt,140); eq(r.stageRemaining,19)
    m:Observe("a",{half=effect("stun",100,132,122)},122,true)
    r=only(m:GetDR("a",122)); eq(r.stage,2); eq(r.started,122); eq(r.remaining,20)
    m:Observe("a",{},132,true)
    m:Observe("a",{quarter=effect("stun",100,139,134)},134,true)
    r=only(m:GetDR("a",134)); eq(r.stage,3); eq(r.started,134); eq(r.remaining,20)
    m:Observe("a",{},139,true)
    r=only(m:GetDR("a",154)); eq(r.stage,3); eq(r.remaining,0); eq(r.stageResetAt,159)
    eq(m:EstimateDR("a",100,"stun",155,"immune",155),false)
    eq(only(m:GetDR("a",158)).stageResetAt,159)
    eq(#m:GetDR("a",159),0)
end)

test("early break sets stage reset once while preserving application countdown", function()
    local m=new()
    m:Observe("a",{full=effect("stun",100,120,100)},100,true)
    m:Observe("a",{},104,true)
    m:Observe("a",{},110,true)
    local r=only(m:GetDR("a",121)); eq(r.stageResetAt,124); eq(r.remaining,0)
    m:Observe("a",{half=effect("stun",100,133,123)},123,true)
    eq(only(m:GetDR("a",123)).stage,2)
    m=new(); m:Observe("a",{full=effect("stun",100,120,100)},100,true)
    m:Observe("a",{},104,true)
    m:Observe("a",{full=effect("stun",100,144,124)},124,true)
    eq(only(m:GetDR("a",124)).stage,1)
end)

test("last overlapping CC end owns the separate category reset", function()
    local m=new()
    m:Observe("a",{long=effect("stun",100,140,100)},100,true)
    m:Observe("a",{long=effect("stun",100,140,100),short=effect("stun",101,115,110)},110,true)
    m:Observe("a",{long=effect("stun",100,140,100)},115,true)
    m:Observe("a",{},130,true)
    local r=only(m:GetDR("a",131)); eq(r.stage,2); eq(r.remaining,0); eq(r.stageResetAt,150)
    m:Observe("a",{},140,true); eq(only(m:GetDR("a",149)).stageResetAt,150)
    eq(#m:GetDR("a",150),0)
end)

test("partial omissions preserve known expiry and unknown expiry waits for removal", function()
    local m=new()
    m:Observe("a",{full=effect("stun",100,120,100)},100,true)
    m:Observe("a",{},121,false)
    local r=only(m:GetDR("a",125)); eq(r.stageResetAt,140); eq(r.uncertain,true)
    eq(#m:GetDR("a",140),0)
    m=new(); m:Observe("a",{full=effect("stun",100,nil,100)},100,true)
    m:Observe("a",{},125,false)
    r=only(m:GetDR("a",125)); eq(r.stageResetPending,true); eq(r.stageResetAt,nil)
    eq(r.remaining,0); eq(r.active,true)
    m:Observe("a",{},126,true)
    m:Observe("a",{},130,true)
    r=only(m:GetDR("a",145)); eq(r.stageResetAt,146); eq(r.stageResetPending,false)
    eq(#m:GetDR("a",146),0)
end)

test("stale returned expired witness never slides a recorded early removal", function()
    local m=new()
    local cc=effect("stun",100,120,100); cc.applicationSource="loc"
    m:Observe("a",{same=cc},100,true)
    m:Observe("a",{},104,true)
    m:Observe("a",{same=cc},121,true)
    local r=only(m:GetDR("a",121)); eq(r.stageResetAt,124); eq(r.stage,1); eq(r.remaining,0)
    m:Observe("a",{},122,true)
    eq(only(m:GetDR("a",123)).stageResetAt,124); eq(#m:GetDR("a",124),0)
end)

test("same future witness can restore active coverage without another application", function()
    local m=new()
    local cc=effect("stun",100,120,100); cc.applicationSource="loc"
    m:Observe("a",{same=cc},100,true)
    m:Observe("a",{},104,true)
    m:Observe("a",{same=cc},105,true)
    local r=only(m:GetDR("a",105)); eq(r.stage,1); eq(r.started,100)
    eq(r.stageResetAt,140); eq(r.active,true); eq(r.uncertain,true)
end)

test("first observed application keeps unknown earlier history", function()
    local m = new()
    m:Observe("a", {a=effect("stun",100,8)}, 0, true)
    local r = only(m:GetDR("a",0))
    eq(r.stage,1); eq(r.uncertain,true); eq(r.active,true); eq(r.started,0)
    m:Observe("a", {a=effect("stun",100,8)}, 19, true)
    eq(only(m:GetDR("a",19)).uncertain,true,"active history must not become confident")
    eq(only(m:GetDR("a",20)).remaining,0,"application countdown remains bounded")
    eq(#m:GetDR("a",28),0,"predicted CC end separately bounds stage retention")
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
    eq(only(m:GetDR("a",42)).remaining,0); eq(#m:GetDR("a",50),0)
    m:Observe("a", {c=effect()}, 51, true)
    r=only(m:GetDR("a",51)); eq(r.stage,1); eq(r.uncertain,false)
end)

test("instant break and natural removal never restart the application timer", function()
    local m = new(); baseline(m,"a"); baseline(m,"b")
    m:Observe("a", {a=effect("stun",100,30)}, 21, true)
    m:Observe("a", {}, 21, true)
    local r=only(m:GetDR("a",22)); eq(r.active,false); eq(r.started,21); eq(r.remaining,19)
    m:Observe("b", {b=effect("stun",100,30)}, 21, true)
    m:Observe("b", {}, 30, true)
    r=only(m:GetDR("b",31)); eq(r.active,false); eq(r.started,21); eq(r.remaining,10)
    eq(#m:GetDR("a",41),0); eq(only(m:GetDR("b",41)).remaining,0)
    eq(#m:GetDR("b",50),0,"natural end retains stage longer than instant break")
end)

test("reported expiration has no influence on the application timer", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,25)}, 21, true)
    local r=only(m:GetDR("a",26)); eq(r.active,false); eq(r.started,21); eq(r.remaining,15)
    eq(only(m:GetDR("a",41)).remaining,0)
    m:Observe("a", {}, 42, true)
    r=only(m:GetDR("a",42)); eq(r.remaining,0); eq(r.stageResetAt,45)
    eq(#m:GetDR("a",45),0,"late removal cannot slide the known end")
end)

test("timer expires while aura remains and stable polling never recreates it", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect("stun",100,100)}, 21, true)
    eq(only(m:GetDR("a",41)).remaining,0)
    m:Observe("a", {a=effect("stun",100,100)}, 42, true)
    m:Observe("a", {a=effect("stun",100,101)}, 43, true)
    eq(only(m:GetDR("a",43)).remaining,0,"unchanged identity does not restart the application countdown")
    m:Observe("a", {a=effect("stun",100,101),b=effect("stun",101,105)}, 44, true)
    local r=only(m:GetDR("a",44)); eq(r.stage,2); eq(r.started,44); eq(r.remaining,20)
    m:Observe("a", {a=effect("stun",100,101)}, 45, true)
    r=only(m:GetDR("a",45)); eq(r.stage,2); eq(r.started,44); eq(r.remaining,19)
end)

test("application countdown boundary does not reset an active category", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {b=effect()}, 41, true)
    local r=only(m:GetDR("a",41)); eq(r.stage,2); eq(r.started,41); eq(r.remaining,20)
end)

test("different categories keep independent application deadlines", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {a=effect(),b=effect("root",400)}, 25, true)
    local rows=m:GetDR("a",26)
    eq(#rows,2); eq(rows[1].started,21); eq(rows[1].remaining,15)
    eq(rows[2].started,25); eq(rows[2].remaining,19)
    rows=m:GetDR("a",41); eq(#rows,2)
    eq(rows[1].category,"stun"); eq(rows[1].remaining,0)
    eq(rows[2].category,"root"); eq(rows[2].remaining,4)
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

test("unknown expiry identities survive unreadable snapshots without new application", function()
    local m = new(); baseline(m,"a")
    m:Observe("a", {a=effect()}, 21, true)
    m:Observe("a", {}, 42, false)
    m:Observe("a", {a=effect()}, 43, true)
    local r=only(m:GetDR("a",43)); eq(r.remaining,0); eq(r.stageResetPending,true)
    m:Observe("a", {}, 44, true)
    m:Observe("a", {a=effect()}, 45, true)
    r=only(m:GetDR("a",45)); eq(r.stage,1); eq(r.started,21); eq(r.uncertain,true)
    eq(r.stageResetAt,64); eq(r.remaining,0)
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
    eq(r.stage,3,"uncertain display keeps the inferred chain")
    eq(r.observedStage,2,"observed stage ignores every prediction")
    eq(r.stageEstimated,true); eq(r.estimated,false); eq(r.started,28)
    eq(only(m:GetDR("a",28,false)).stage,2,"disabling estimates reveals only observed stage")
end)

test("confirming the second estimated cast preserves uncertain stage continuity", function()
    local m = new()
    m:EstimateDR("a",100,"stun",0,"Cast-1",0)
    m:EstimateDR("a",100,"stun",10,"Cast-2",10)
    eq(only(m:GetDR("a",10)).stage,2)
    m:Observe("a",{second=effect("stun",100,14,10)},11,true)
    local r=only(m:GetDR("a",11))
    eq(r.stage,2); eq(r.observedStage,1); eq(r.stageEstimated,true)
    eq(r.estimated,false); eq(r.uncertain,true); eq(r.started,10); eq(r.remaining,19)
    eq(m.units.a.categories.stun.stage,1,"the earlier cast must not become a landed application")
    r=only(m:GetDR("a",11,false)); eq(r.stage,1); eq(r.observedStage,1); eq(r.stageEstimated,false)
    m:Observe("a",{second=effect("stun",100,14,10)},12,true)
    eq(only(m:GetDR("a",12)).stage,2,"stable polling must retain the overlay")
    m:Observe("a",{third=effect("stun",100,19,15)},15,true)
    r=only(m:GetDR("a",15)); eq(r.stage,3); eq(r.observedStage,2); eq(r.stageEstimated,true)
    r=only(m:GetDR("a",15,false)); eq(r.stage,2); eq(r.stageEstimated,false)
    m:Observe("a",{next=effect("stun",100,43,39)},39,true)
    r=only(m:GetDR("a",39)); eq(r.stage,1); eq(r.observedStage,1); eq(r.stageEstimated,false)
end)

test("confirmation of a single estimate does not mark observed stage as estimated", function()
    local m=new()
    m:EstimateDR("a",100,"stun",10,"Cast-1",10)
    m:Observe("a",{a=effect("stun",100,14,10)},11,true)
    local r=only(m:GetDR("a",11))
    eq(r.stage,1); eq(r.observedStage,1); eq(r.stageEstimated,false); eq(r.estimated,false)
end)

test("a late second application chains by application time after the first display expires", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},0,true)
    m:Observe("a",{},5,true)
    eq(only(m:GetDR("a",20)).remaining,0)
    m:Observe("a",{second=effect("stun",100,30,10)},21,false)
    local r=only(m:GetDR("a",21))
    eq(r.stage,2); eq(r.observedStage,2); eq(r.stageEstimated,false)
    eq(r.started,10); eq(r.remaining,9); eq(r.uncertain,true)
    eq(only(m:GetDR("a",21,false)).stage,2)
    eq(only(m:GetDR("a",30)).remaining,0,"history must not extend the visible application timer")
    m:Observe("a",{third=effect("stun",100,34,30)},30,true)
    r=only(m:GetDR("a",30)); eq(r.stage,3); eq(r.started,30)
end)

test("expired late witnesses retain history without resurrecting an old timer", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},21,true)
    eq(only(m:GetDR("a",21)).remaining,0)
    m:Observe("a",{second=effect("stun",100,30,10)},22,false)
    local r=only(m:GetDR("a",22)); eq(r.stage,2); eq(r.started,10); eq(r.remaining,8)
    eq(only(m:GetDR("a",30)).remaining,0)
    m:Observe("a",{second=effect("stun",100,30,10)},31,true)
    eq(only(m:GetDR("a",31)).remaining,0)
end)

test("older witnesses cannot rewind retained history after display expiry", function()
    local m=new()
    m:Observe("a",{newer=effect("stun",100,29,25)},25,true)
    eq(only(m:GetDR("a",45)).remaining,0)
    m:Observe("a",{older=effect("stun",100,14,10)},46,false)
    eq(only(m:GetDR("a",46)).remaining,0)
    m:Observe("a",{latest=effect("stun",100,60,40)},47,false)
    local r=only(m:GetDR("a",47)); eq(r.stage,2); eq(r.started,40); eq(r.remaining,13)
end)

test("expired observed history cannot inflate a new cast estimate", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},0,true)
    m:EstimateDR("a",100,"stun",24,"Cast-new",24)
    local r=only(m:GetDR("a",24)); eq(r.stage,1); eq(r.estimated,true)
end)

test("split-readable application timing repairs the stage across an expired display", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},0,true)
    m:Observe("a",{},1,true)
    eq(only(m:GetDR("a",20)).remaining,0)
    m:Observe("a",{second=effect("stun",100,30)},21,false)
    local r=only(m:GetDR("a",21)); eq(r.stage,1); eq(r.started,21)
    local timed=effect("stun",100,30,10); timed.applicationSource="loc"
    m:Observe("a",{second=timed},22,false)
    r=only(m:GetDR("a",22)); eq(r.stage,2); eq(r.observedStage,2); eq(r.started,10); eq(r.remaining,8)
    m:Observe("a",{second=timed},23,false)
    r=only(m:GetDR("a",23)); eq(r.stage,2); eq(r.started,10); eq(r.remaining,7)
    eq(only(m:GetDR("a",30)).remaining,0)
end)

test("split-readable timing at the reset boundary remains the first stage", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},0,true)
    m:Observe("a",{},1,true)
    m:Observe("a",{second=effect("stun",100,24)},21,false)
    local timed=effect("stun",100,24,21); timed.applicationSource="loc"
    m:Observe("a",{second=timed},22,false)
    local r=only(m:GetDR("a",22)); eq(r.stage,1); eq(r.started,21); eq(r.remaining,19)
end)

test("split-readable older timing restores the newer application instead of rewinding it", function()
    local m=new()
    m:Observe("a",{newer=effect("stun",100,24,20)},20,true)
    m:Observe("a",{older=effect("stun",100,14)},21,false)
    local timed=effect("stun",100,14,10); timed.applicationSource="loc"
    m:Observe("a",{older=timed},22,false)
    local r=only(m:GetDR("a",22)); eq(r.stage,1); eq(r.started,20); eq(r.remaining,18); eq(r.uncertain,true)
    m:Observe("a",{older=timed},23,false)
    r=only(m:GetDR("a",23)); eq(r.stage,1); eq(r.started,20)
end)

test("split-readable stage correction retains only one nonrecursive predecessor", function()
    local m=new()
    for i=0,100 do
        m:Observe("a",{["application"..i]=effect("stun",100,i+4,i)},i,true)
    end
    local current=m.units.a.categories.stun
    eq(current.appliedAt,100); eq(current.previousApplication.appliedAt,99)
    eq(current.previousApplication.previousApplication,nil,"history must not form a recursive chain")
end)

test("correcting restored history preserves its known count without older recursive history", function()
    local m=new()
    m:Observe("a",{first=effect("stun",100,4,0)},0,true)
    local newer=effect("stun",100,9,5); newer.applicationSource="aura"
    m:Observe("a",{newer=newer},5,true)
    m:Observe("a",{older=effect("stun",100,7)},6,false)
    local older=effect("stun",100,7,1); older.applicationSource="loc"
    m:Observe("a",{older=older},7,false)
    eq(only(m:GetDR("a",7)).stage,2)
    newer=effect("stun",100,8.8,4.8); newer.applicationSource="loc"
    m:Observe("a",{newer=newer},8,false)
    local r=only(m:GetDR("a",8)); eq(r.stage,2); eq(r.started,4.8)
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

test("unconfirmed attempts at estimated immunity preserve the third application deadline", function()
    local m=new()
    eq(m:EstimateDR("a",100,"stun",0,"Cast-1"),true)
    eq(m:EstimateDR("a",100,"stun",5,"Cast-2"),true)
    eq(m:EstimateDR("a",100,"stun",10,"Cast-3"),true)
    local r=only(m:GetDR("a",10)); eq(r.stage,3); eq(r.started,10); eq(r.remaining,20)
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune"),false)
    r=only(m:GetDR("a",15)); eq(r.stage,3); eq(r.started,10); eq(r.remaining,15); eq(r.estimated,true)
    eq(m:EstimateDR("a",101,"stun",29.999,"Cast-immune-later"),false)
    eq(only(m:GetDR("a",29.999)).started,10,"another spell in the category cannot extend immunity")
    eq(#m:GetDR("a",30),0,"repeated attempts cannot postpone the original reset")
end)

test("unconfirmed attempts at observed immunity preserve the observed deadline", function()
    local m=new()
    for i=0,2 do m:Observe("a",{["cc"..i]=effect("stun",100,i*5+2,i*5)},i*5,true) end
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune",14),false)
    local r=only(m:GetDR("a",15)); eq(r.stage,3); eq(r.observedStage,3); eq(r.started,10); eq(r.remaining,15)
    eq(r.estimated,false); eq(r.stageEstimated,false)
    eq(next(m.estimates.a.categories),nil,"a rejected guess must not overlay observed history")
    eq(only(m:GetDR("a",30)).remaining,0)
    eq(#m:GetDR("a",32),0,"unconfirmed casts cannot move the predicted end plus reset")
end)

test("inferred immunity on an observed application also rejects unconfirmed refreshes", function()
    local m=new()
    for i=0,2 do m:EstimateDR("a",100,"stun",i*5,"Cast-"..i) end
    m:Observe("a",{third=effect("stun",100,12,10)},10.5,true)
    local r=only(m:GetDR("a",11)); eq(r.stage,3); eq(r.observedStage,1); eq(r.stageEstimated,true)
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune",14),false)
    r=only(m:GetDR("a",15)); eq(r.stage,3); eq(r.observedStage,1); eq(r.started,10); eq(r.remaining,15)
    eq(r.estimated,false); eq(r.stageEstimated,true)
    r=only(m:GetDR("a",15,false)); eq(r.stage,1); eq(r.started,10)
end)

test("suppressed immunity attempts stay deduplicated after the timer expires", function()
    local m=new()
    for i=0,2 do m:EstimateDR("a",100,"stun",i*5,"Cast-"..i) end
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune"),false)
    eq(#m:GetDR("a",30),0)
    eq(m:EstimateDR("a",100,"stun",30,"Cast-immune"),false,"the same success cannot resurrect expired DR")
    eq(#m:GetDR("a",30),0)
    eq(m:EstimateDR("a",100,"stun",30,"Cast-new"),true,"a new application at the boundary starts a fresh cycle")
    local r=only(m:GetDR("a",30)); eq(r.stage,1); eq(r.started,30); eq(r.remaining,20)
end)

test("immunity suppression is isolated by destination and category", function()
    local m=new()
    for i=0,2 do m:EstimateDR("a",100,"stun",i*5,"Cast-"..i) end
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune"),false)
    eq(m:EstimateDR("a",200,"fear",15,"Cast-fear"),true)
    eq(m:EstimateDR("b",100,"stun",15,"Cast-other"),true)
    local rows=m:GetDR("a",15); eq(#rows,2)
    eq(rows[1].category,"stun"); eq(rows[1].stage,3); eq(rows[1].started,10)
    eq(rows[2].category,"fear"); eq(rows[2].stage,1); eq(rows[2].started,15)
    local r=only(m:GetDR("b",15)); eq(r.stage,1); eq(r.started,15)
end)

test("positive application evidence can correct an estimated immunity deadline", function()
    local m=new()
    for i=0,2 do m:EstimateDR("a",100,"stun",i*5,"Cast-"..i) end
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune",14),false)
    m:Observe("a",{landed=effect("stun",100,19,15)},16,true)
    local r=only(m:GetDR("a",16)); eq(r.started,15); eq(r.remaining,19); eq(r.estimated,false)
    eq(r.observedStage,1,"predictions do not turn into earlier confirmed applications")
    eq(only(m:GetDR("a",35)).remaining,0)
    eq(#m:GetDR("a",39),0)
end)

test("positive application evidence remains authoritative after observed stage three", function()
    local m=new()
    for i=0,2 do m:Observe("a",{["cc"..i]=effect("stun",100,i*5+2,i*5)},i*5,true) end
    eq(m:EstimateDR("a",100,"stun",15,"Cast-immune",14),false)
    m:Observe("a",{landed=effect("stun",100,19,15)},16,true)
    local r=only(m:GetDR("a",16)); eq(r.stage,3); eq(r.observedStage,3); eq(r.started,15); eq(r.remaining,19)
    eq(r.estimated,false)
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
    eq(only(m:GetDR("a",31)).remaining,0)
    m:Observe("a",{a=effect("stun",100,80)},32,true)
    eq(only(m:GetDR("a",32)).remaining,0,"losing readable timing cannot restart the countdown")
    eq(#m:GetDR("a",100),0)
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

test("newly readable expired application timing stays zero while stage remains active", function()
    local m = new()
    m:Observe("a",{a=effect()},30,true)
    local a=effect("stun",100,60,10); a.applicationSource="loc"
    m:Observe("a",{a=a},31,true)
    eq(only(m:GetDR("a",31)).remaining,0)
    m:Observe("a",{a=a},32,true); eq(only(m:GetDR("a",32)).remaining,0)
    m = new(); m:Observe("a",{a=effect()},0,true); eq(only(m:GetDR("a",20)).remaining,0)
    a=effect("stun",100,60,0); a.applicationSource="loc"
    m:Observe("a",{a=a},21,true); eq(only(m:GetDR("a",21)).remaining,0)
    eq(#m:GetDR("a",80),0)
end)

test("derived refresh advances observed stage while preserving ambiguity", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,45,25); b.applicationSource="aura"
    m:Observe("a",{a=b},25,true)
    local r=only(m:GetDR("a",25)); eq(r.stage,2); eq(r.uncertain,true)
end)

test("first readable timing after an untimed identity calibrates rather than proving a refresh", function()
    for _,source in ipairs({"loc","aura"}) do
        local m = new(); baseline(m,"a")
        m:Observe("a",{a=effect("stun",100,41)},21,true)
        local a=effect("stun",100,45,25); a.applicationSource=source
        m:Observe("a",{a=a},26,true)
        -- First-seen time is a local fallback, not a known earlier application
        -- timestamp. Live 0.4.4 records a readable start after first-seen for
        -- the same Hibernate; that alone cannot prove a second application.
        local r=only(m:GetDR("a",26)); eq(r.stage,1); eq(r.started,25); eq(r.remaining,19)
        m:Observe("a",{a=a},27,true); eq(only(m:GetDR("a",27)).stage,1)
        local refreshed=effect("stun",100,50,30); refreshed.applicationSource=source
        m:Observe("a",{a=refreshed},30,true)
        r=only(m:GetDR("a",30)); eq(r.stage,2); eq(r.started,30)
    end
end)

test("live Hibernate a315 gets its first readable timestamp without advancing stage", function()
    local m=new()
    m:Observe("a",{["a:315"]=effect("incapacitate",2637,2655141.649)},2655121.649,true)
    eq(only(m:GetDR("a",2655121.649)).stage,1)
    local timed=effect("incapacitate",2637,2655141.750,2655121.750); timed.applicationSource="loc"
    m:Observe("a",{["a:315"]=timed},2655121.778,true)
    local row=only(m:GetDR("a",2655121.778))
    eq(row.stage,1); eq(row.observedStage,1); eq(row.started,2655121.750)
    m:Observe("a",{},2655138.995,true)
    row=only(m:GetDR("a",2655140.750)); eq(row.stage,1); eq(row.remaining,1)
    eq(only(m:GetDR("a",2655141.750)).remaining,0)
    eq(#m:GetDR("a",2655158.995),0)
end)

test("live second Hibernate a319 counts once when its timestamp becomes readable", function()
    local m=new()
    local first=effect("incapacitate",2637,2655196.750,2655176.750); first.applicationSource="loc"
    m:Observe("a",{["a:317"]=first},2655176.779,true)
    eq(only(m:GetDR("a",2655176.779)).stage,1)
    m:Observe("a",{},2655186.431,true)
    m:Observe("a",{["a:319"]=effect("incapacitate",2637,2655196.838)},2655186.838,true)
    eq(only(m:GetDR("a",2655186.838)).stage,2)
    local second=effect("incapacitate",2637,2655197.000,2655187.000); second.applicationSource="loc"
    m:Observe("a",{["a:319"]=second},2655187.034,true)
    local row=only(m:GetDR("a",2655187.034))
    eq(row.stage,2); eq(row.observedStage,2); eq(row.started,2655187.000)
    m:Observe("a",{["a:319"]=second},2655190,true)
    row=only(m:GetDR("a",2655190)); eq(row.stage,2); eq(row.remaining,17)
end)

test("first timing after a complete witness gap still calibrates the retained untimed identity", function()
    local m=new()
    m:Observe("a",{same=effect("stun",100,41)},21,true)
    m:Observe("a",{},21.1,true)
    local timed=effect("stun",100,41.15,21.15); timed.applicationSource="loc"
    m:Observe("a",{same=timed},21.2,true)
    local row=only(m:GetDR("a",22.15)); eq(row.stage,1); eq(row.started,21.15); eq(row.remaining,19)
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

test("first explicit LoC timing after aura observation calibrates the same identity", function()
    local m = new(); baseline(m,"a")
    local a=effect("stun",100,41,21); a.applicationSource="aura"
    m:Observe("a",{a=a},21,true)
    local b=effect("stun",100,35,25); b.applicationSource="loc"
    m:Observe("a",{a=b},25,true)
    -- A changed sensor clock does not prove another application. The live
    -- a:325 trace has this transition while its first Hibernate is still active.
    local r=only(m:GetDR("a",25)); eq(r.stage,1); eq(r.started,25); eq(r.uncertain,true)
    m:Observe("a",{a=b},26,true); eq(only(m:GetDR("a",26)).stage,1)
end)

test("live a325 source handoff calibrates once then its real LoC refresh advances once", function()
    local m=new()
    m:Observe("a",{},2655614.460,true)
    local initial=effect("incapacitate",2637,2655646.973,2655626.973); initial.applicationSource="aura"
    m:Observe("a",{["a:325"]=initial},2655626.973,true)
    local untimed=effect("incapacitate",2637,2655646.973); untimed.applicationSource="loc"
    m:Observe("a",{["a:325"]=untimed},2655626.973,true)
    eq(only(m:GetDR("a",2655626.973)).stage,1)
    local first=effect("incapacitate",2637,2655647.250,2655627.250); first.applicationSource="loc"
    m:Observe("a",{["a:325"]=first},2655627.270,true)
    local row=only(m:GetDR("a",2655627.270))
    eq(row.stage,1,"first explicit clock must not manufacture the second application")
    eq(row.observedStage,1); eq(row.started,2655627.250)
    untimed=effect("incapacitate",2637,2655647.511); untimed.applicationSource="loc"
    m:Observe("a",{["a:325"]=untimed},2655637.512,true)
    row=only(m:GetDR("a",2655637.512)); eq(row.stage,1); eq(row.started,2655627.250)
    local second=effect("incapacitate",2637,2655647.750,2655637.750); second.applicationSource="loc"
    m:Observe("a",{["a:325"]=second},2655637.765,true)
    row=only(m:GetDR("a",2655637.765)); eq(row.stage,2); eq(row.observedStage,2); eq(row.started,2655637.750)
    m:Observe("a",{},2655647.495,true)
    row=only(m:GetDR("a",2655652.750)); eq(row.stage,2); eq(row.remaining,5); eq(row.active,false)
    eq(only(m:GetDR("a",2655657.750)).remaining,0)
    eq(#m:GetDR("a",2655667.495),0)
end)

test("aura samples cannot replace an established LoC refresh baseline", function()
    local m=new()
    local explicit=effect("stun",100,120,100); explicit.applicationSource="loc"
    m:Observe("a",{same=explicit},100,true)
    local derived=effect("stun",100,120.3,100.3); derived.applicationSource="aura"
    m:Observe("a",{same=derived},100.3,true)
    local row=only(m:GetDR("a",100.3)); eq(row.stage,1); eq(row.started,100)
    -- Even another changed pair of derived boundaries cannot supersede an
    -- explicit clock for this identity. Wait for LoC or a new identity.
    derived=effect("stun",100,120.6,100.6); derived.applicationSource="aura"
    m:Observe("a",{same=derived},100.6,true)
    row=only(m:GetDR("a",100.6)); eq(row.stage,1); eq(row.started,100)
    m:Observe("a",{same=explicit},101,true)
    row=only(m:GetDR("a",101)); eq(row.stage,1); eq(row.started,100)
    derived=effect("stun",100,125.3,105.3); derived.applicationSource="aura"
    m:Observe("a",{same=derived},105.3,true)
    explicit=effect("stun",100,115,105); explicit.applicationSource="loc"
    m:Observe("a",{same=explicit},105.4,true)
    row=only(m:GetDR("a",105.4)); eq(row.stage,2); eq(row.started,105)
end)

test("an older LoC sample cannot replace the accepted refresh baseline", function()
    local m=new()
    local explicit=effect("stun",100,120,100); explicit.applicationSource="loc"
    m:Observe("a",{same=explicit},100,true)
    local stale=effect("stun",100,119,99); stale.applicationSource="loc"
    m:Observe("a",{same=stale},101,true)
    local row=only(m:GetDR("a",101)); eq(row.stage,1); eq(row.started,100)
    m:Observe("a",{same=explicit},102,true)
    row=only(m:GetDR("a",102)); eq(row.stage,1); eq(row.started,100)
end)

test("conflicting diminished aura timing after LoC remains uncertain without inventing a stage", function()
    local m=new()
    m:Observe("a",{},80,true)
    local explicit=effect("stun",100,120,100); explicit.applicationSource="loc"
    m:Observe("a",{same=explicit},100,true)
    eq(only(m:GetDR("a",100)).uncertain,false)
    local derived=effect("stun",100,111,101); derived.applicationSource="aura"
    m:Observe("a",{same=derived},101,true)
    local row=only(m:GetDR("a",101))
    eq(row.stage,1); eq(row.started,100); eq(row.uncertain,true)
end)

test("a distinct aura identity advances despite a prior explicit LoC clock", function()
    local m=new()
    local explicit=effect("stun",100,120,100); explicit.applicationSource="loc"
    m:Observe("a",{["a:1"]=explicit},100,true)
    local derived=effect("stun",100,115.3,105.3); derived.applicationSource="aura"
    m:Observe("a",{["a:2"]=derived},105.3,true)
    local row=only(m:GetDR("a",105.3)); eq(row.stage,2); eq(row.started,105.3)
    explicit=effect("stun",100,115.5,105.5); explicit.applicationSource="loc"
    m:Observe("a",{["a:2"]=explicit},105.6,true)
    row=only(m:GetDR("a",105.6)); eq(row.stage,2); eq(row.started,105.5)
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

test("a removed witness returning unchanged does not advance its category", function()
    local m=new()
    local a=effect("stun",100,41,21); a.applicationSource="loc"
    m:Observe("a",{same=a},21,true)
    m:Observe("a",{},21.1,true)
    m:Observe("a",{same=a},21.2,true)
    local row=only(m:GetDR("a",21.2)); eq(row.stage,1); eq(row.started,21); eq(row.active,true)
    m:Observe("a",{},22,true)
    local b=effect("stun",100,35,25); b.applicationSource="loc"
    m:Observe("a",{same=b},25,true)
    row=only(m:GetDR("a",25)); eq(row.stage,2); eq(row.started,25)
end)

test("timing becoming readable after a witness gap corrects the existing application", function()
    local m=new()
    m:Observe("a",{same=effect("stun",100)},25,true)
    m:Observe("a",{},26,true)
    local timed=effect("stun",100,41,21); timed.applicationSource="loc"
    m:Observe("a",{same=timed},27,true)
    local row=only(m:GetDR("a",27)); eq(row.stage,1); eq(row.started,21); eq(row.remaining,14)
end)

-- A duration witness is deliberately distinct from expiration minus start:
-- only the guarded LoC adapter can supply reportedDuration in production.
local function durationEffect(start, duration, reported, spellID)
    local value=effect("stun",spellID or 100,start and start+duration or nil,start)
    value.applicationSource=start and "loc" or nil
    value.reportedDuration=reported
    return value
end

local function durationSequence(options)
    options=options or {}
    local m=options.model or ns.Model.New(20,18)
    local guid=options.guid or "a"
    m:Observe(guid,{},options.coverageStart or 0,true)
    local first=durationEffect(100,20,options.noBaseline and nil or 20)
    if options.noBaseline then first.reportedDuration=nil end
    m:Observe(guid,{first=first},100,true)
    if options.partial then
        m:Observe(guid,{},105,false)
        m:Observe(guid,{first=first},106,true)
    end
    m:Observe(guid,{},120,true)
    m:Observe(guid,{second=durationEffect(130,10,10)},130,true)
    m:Observe(guid,{},140,true)
    m:Observe(guid,{third=durationEffect(141,5,5)},141,true)
    if not options.noThirdRemoval then m:Observe(guid,{},options.thirdRemovalAt or 146,true) end
    return m,guid
end

test("matching explicit full duration reconciles the retained immune stage after fifteen seconds", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    local row=only(m:GetDR("a",161.5))
    eq(row.stage,1); eq(row.observedStage,1)
    eq(row.started,161.5); eq(row.remaining,20); eq(row.duration,20)
    eq(row.resetEvidence,"matching-full-duration"); eq(row.resetBaselineDuration,20)
    eq(row.uncertain,true,"duration evidence remains an estimate")
    eq(row.stageResetAt,199.5,"the configured eighteen second end window is unchanged")
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},165,true)
    row=only(m:GetDR("a",165)); eq(row.stage,1); eq(row.started,161.5)
    m:Observe("a",{},166,true)
    m:Observe("a",{fifth=durationEffect(168,10,10)},168,true)
    row=only(m:GetDR("a",168)); eq(row.stage,2); eq(row.resetEvidence,nil)
end)

test("the a399 to a405 trace reconciles full duration without changing application timing", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},2657668.836,true)
    local function read(key,start,duration,now)
        local value=durationEffect(start,duration,start and duration or nil)
        if not start then value.expires=now+duration end
        m:Observe("a",{[key]=value},now,true)
        return only(m:GetDR("a",now))
    end
    read("a:399",nil,20,2657932.655)
    eq(read("a:399",2657932.750,20,2657932.926).stage,1)
    m:Observe("a",{},2657943.623,true)
    read("a:401",nil,10,2657949.595)
    eq(read("a:401",2657949.750,10,2657949.823).stage,2)
    m:Observe("a",{},2657959.608,true)
    eq(read("a:403",2657960.000,5,2657960.064).stage,3)
    m:Observe("a",{},2657965.070,true)
    eq(read("a:405",nil,20,2657980.436).stage,3,"unknown timing alone is not evidence")
    local row=read("a:405",2657980.500,20,2657980.571)
    eq(row.stage,1); eq(row.started,2657980.500)
    eq(row.resetEvidence,"matching-full-duration")
end)

test("first explicit duration can enrich an already timed application without restarting it", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,20,nil)},161.6,true)
    eq(only(m:GetDR("a",161.6)).stage,3)
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},163,true)
    local row=only(m:GetDR("a",163)); eq(row.stage,1); eq(row.started,161.5); eq(row.remaining,18.5)
    m:Observe("a",{fourth=durationEffect(161.5,20,nil)},164,true)
    row=only(m:GetDR("a",164)); eq(row.stage,1); eq(row.resetEvidence,"matching-full-duration")
end)

test("remaining-only aura and malformed duration evidence cannot reset a retained stage", function()
    for _,case in ipairs({
        {name="missing"}, {name="zero",duration=0}, {name="negative",duration=-20},
        {name="infinity",duration=math.huge}, {name="nan",duration=0/0},
        {name="too large",duration=121}, {name="string",duration="20"},
        {name="opaque",duration={}}, {name="aura",duration=20,source="aura"},
        {name="incoherent",duration=20,expiry=180},
    }) do
        local m=durationSequence()
        local value=durationEffect(161.5,20,case.duration)
        if case.source then value.applicationSource=case.source end
        if case.expiry then value.expires=case.expiry end
        m:Observe("a",{fourth=value},161.5,true)
        local row=only(m:GetDR("a",161.5))
        eq(row.stage,3,case.name); eq(row.resetEvidence,nil,case.name)
    end
end)

test("short quiet observation needs all three halving hits before teaching a baseline", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true)
    local row=only(m:GetDR("a",100))
    eq(row.fullDurationBaseline,nil); eq(row.durationCandidateStep,1)
    m:Observe("a",{},120,true)
    m:Observe("a",{second=durationEffect(130,10,10)},130,true)
    row=only(m:GetDR("a",130)); eq(row.fullDurationBaseline,nil); eq(row.durationCandidateStep,2)
    m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    row=only(m:GetDR("a",141))
    eq(row.stage,3,"the chain teaches duration without recoloring the third application")
    eq(row.fullDurationBaseline,20); eq(row.fullDurationBaselineSource,"observed-halving-chain")
    eq(row.durationCandidateStep,nil)
    m:Observe("a",{},146,true)
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    row=only(m:GetDR("a",161.5))
    eq(row.stage,1); eq(row.resetBaselineSource,"observed-halving-chain"); eq(row.uncertain,true)
end)

test("continuous coverage alone cannot teach a baseline while category history is recent", function()
    local m=ns.Model.New(20,10)
    m:Observe("a",{},0,true)
    m:Observe("a",{one=durationEffect(100,5,nil)},100,true)
    m:Observe("a",{},105,true)
    m:Observe("a",{two=durationEffect(116,20,20)},116,true)
    eq(only(m:GetDR("a",116)).stage,1,"configured stage timeout alone does not prove full duration")
    m:Observe("a",{},117,true)
    m.stageResetSeconds=18
    m:Observe("a",{three=durationEffect(132.5,20,20)},132.5,true)
    eq(only(m:GetDR("a",132.5)).stage,2,"eleven quiet seconds must not establish the baseline")
end)

test("duration baselines are isolated by exact spell and unit identity", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,20,20,101)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,3,"another rank cannot borrow the baseline")
    durationSequence({model=m,guid="b",noBaseline=true})
    m:Observe("b",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("b",161.5)).stage,3,"another unit cannot borrow the baseline")
end)

test("partial observation clears duration baseline eligibility", function()
    local m=durationSequence({partial=true})
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,3)
end)

test("a gap before late duration arrives prevents repairing from old quiet evidence", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,20,nil)},161.5,true)
    m:Observe("a",{},162,false)
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},163,true)
    eq(only(m:GetDR("a",163)).stage,3)
end)

test("duration matching before fifteen seconds cannot reset a retained stage", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(160.999,20,20)},160.999,true)
    eq(only(m:GetDR("a",160.999)).stage,3)
end)

test("overlapping category effects cannot trigger duration reset correction", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,20,20),overlap=durationEffect(161.5,10,10,101)},161.5,true)
    local row=only(m:GetDR("a",161.5)); eq(row.stage,3); eq(row.resetEvidence,nil)
end)

test("a known duration changing at a stable application time is not reset evidence", function()
    local m=durationSequence()
    m:Observe("a",{fourth=durationEffect(161.5,10,10)},161.5,true)
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},162,true)
    local row=only(m:GetDR("a",162)); eq(row.stage,3); eq(row.resetEvidence,nil)
end)

test("own cast attempts at immunity cannot synthesize duration reset evidence", function()
    local m=durationSequence()
    eq(m:EstimateDR("a",100,"stun",161.5,"immune",160),false)
    local row=only(m:GetDR("a",161.5))
    eq(row.stage,3); eq(row.started,141); eq(row.stageResetAt,164); eq(row.resetEvidence,nil)
end)

test("a newly discovered old disappearance cannot create duration reset evidence", function()
    local m=durationSequence({noThirdRemoval=true})
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,3,"the preceding end was only predicted until this snapshot")
end)

test("baseline learning requires previously observed quiet category history", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    m:Observe("a",{one=durationEffect(100,5,nil)},100,true)
    -- The expired old effect was not observed absent before this new spell.
    m:Observe("a",{two=durationEffect(126,20,20)},126,true)
    eq(only(m:GetDR("a",126)).stage,1)
    m:Observe("a",{},127,true)
    m:Observe("a",{three=durationEffect(142.5,20,20)},142.5,true)
    eq(only(m:GetDR("a",142.5)).stage,2,"predicted quiet alone must not teach a duration baseline")
end)

test("late disappearance cannot backdate the quiet evidence for duration correction", function()
    local m=durationSequence({thirdRemovalAt=148})
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,3,"only thirteen and a half seconds of observed absence")
end)

test("late disappearance cannot backdate twenty seconds of quiet baseline learning", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    m:Observe("a",{one=durationEffect(100,5,nil)},100,true)
    m:Observe("a",{},115,true)
    m:Observe("a",{two=durationEffect(126,20,20)},126,true)
    eq(only(m:GetDR("a",126)).stage,1)
    m:Observe("a",{},127,true)
    m:Observe("a",{three=durationEffect(142.5,20,20)},142.5,true)
    eq(only(m:GetDR("a",142.5)).stage,2,"eleven observed quiet seconds cannot establish a full baseline")
end)

test("late baseline duration survives timing calibration but not another application's timestamp", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    m:Observe("a",{first=durationEffect(100,20,nil)},100,true)
    m:Observe("a",{first=durationEffect(100,20,20)},102,true)
    m:Observe("a",{},120,true)
    m:Observe("a",{second=durationEffect(130,10,10)},130,true)
    m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    m:Observe("a",{},146,true)
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,1)
    -- An older sample cannot rewrite the corrected application or its evidence.
    m:Observe("a",{fourth=durationEffect(141,5,5)},162,true)
    local row=only(m:GetDR("a",162)); eq(row.stage,1); eq(row.started,161.5)
    eq(row.resetEvidence,"matching-full-duration")
end)

test("forgetting a unit removes its learned duration evidence", function()
    local m=durationSequence()
    m:Forget("a")
    durationSequence({model=m,noBaseline=true})
    m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
    eq(only(m:GetDR("a",161.5)).stage,3)
end)

test("learning many exact spell durations keeps per unit evidence bounded", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    for spellID=1,160 do
        local start=spellID*100
        m:Observe("a",{current=durationEffect(start,20,20,spellID)},start,true)
        m:Observe("a",{},start+20,true)
    end
    local count=0
    for _ in pairs(m.units.a.durationBaselines) do count=count+1 end
    assert(count<=64,"duration baselines grew without a bound")
    eq(m.units.a.durationBaselines[1],nil,"oldest evidence must be evictable")
    eq(m.units.a.durationBaselines[160].duration,20,"recent usable evidence survives churn")
end)

test("a shorter first LoC interval cannot teach a full baseline after a twenty second aura", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    local aura=durationEffect(100,20,nil); aura.applicationSource="aura"
    m:Observe("a",{same=aura},100,true)
    -- Same identity does not rule out a refresh before its first explicit LoC
    -- timestamp. The differing duration can veto learning, not infer a stage.
    m:Observe("a",{same=durationEffect(110,10,10)},110,true)
    eq(only(m:GetDR("a",110)).stage,1,"duration disagreement must not invent a half-stage count")
    m:Observe("a",{},120,true)
    m:Observe("a",{next=durationEffect(135.5,10,10)},135.5,true)
    local row=only(m:GetDR("a",135.5))
    eq(row.stage,2,"ten seconds was never established as this spell's full duration")
    eq(row.resetEvidence,nil)
end)

test("an initially untimed aura still contributes its first readable duration veto", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    m:Observe("a",{same=effect("stun",100)},100,true)
    local aura=durationEffect(100.1,20,nil); aura.applicationSource="aura"
    m:Observe("a",{same=aura},100.2,true)
    m:Observe("a",{same=durationEffect(110.1,10,10)},110.2,true)
    m:Observe("a",{},120.1,true)
    m:Observe("a",{next=durationEffect(135.6,10,10)},135.6,true)
    local row=only(m:GetDR("a",135.6)); eq(row.stage,2); eq(row.resetEvidence,nil)
end)

test("matching aura and LoC durations permit baseline learning despite clock calibration", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},0,true)
    local aura=durationEffect(100.2,20,nil); aura.applicationSource="aura"
    m:Observe("a",{same=aura},100.2,true)
    m:Observe("a",{same=durationEffect(100.5,20,20)},100.6,true)
    m:Observe("a",{},120.5,true)
    m:Observe("a",{next=durationEffect(136,20,20)},136,true)
    local row=only(m:GetDR("a",136))
    eq(row.stage,1); eq(row.started,136)
    eq(row.resetEvidence,"matching-full-duration"); eq(row.resetBaselineDuration,20)
end)

test("the cold a477 through a483 trace learns a full baseline before its later reset", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},2660043.899,true)
    local aura=durationEffect(2660057.587,20,nil); aura.applicationSource="aura"
    m:Observe("a",{["a:477"]=aura},2660057.587,true)
    local function read(key,start,duration,now)
        local value=durationEffect(start,duration,start and duration or nil)
        if not start then value.expires=now+duration end
        m:Observe("a",{[key]=value},now,true)
        return only(m:GetDR("a",now))
    end
    read("a:477",nil,20,2660057.587)
    eq(read("a:477",2660057.750,20,2660057.844).stage,1)
    m:Observe("a",{},2660074.212,true)
    read("a:479",nil,10,2660076.459)
    eq(read("a:479",2660076.750,10,2660076.769).stage,2)
    m:Observe("a",{},2660086.643,true)
    read("a:481",nil,5,2660089.007)
    local row=read("a:481",2660089.250,5,2660089.324)
    eq(row.stage,3); eq(row.fullDurationBaseline,20)
    eq(row.fullDurationBaselineSource,"observed-halving-chain")
    m:Observe("a",{},2660094.112,true)
    read("a:483",nil,20,2660109.701)
    row=read("a:483",2660110,20,2660110.187)
    eq(row.stage,1); eq(row.started,2660110); eq(row.resetBaselineSource,"observed-halving-chain")
    read("a:483",nil,10,2660120.941)
    row=read("a:483",2660121,10,2660121.074)
    eq(row.stage,2); eq(row.started,2660121); eq(row.resetEvidence,nil)
end)

test("two durations alone cannot declare the first one full", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,10,10)},100,true)
    m:Observe("a",{},110,true)
    m:Observe("a",{second=durationEffect(112,5,5)},112,true)
    m:Observe("a",{},117,true)
    m:Observe("a",{third=durationEffect(132.5,10,10)},132.5,true)
    local row=only(m:GetDR("a",132.5))
    eq(row.stage,3); eq(row.fullDurationBaseline,nil); eq(row.resetEvidence,nil)
end)

test("every halving-chain application requires a coherent explicit duration", function()
    for _,bad in ipairs({{name="missing"},{name="opaque",value={}},{name="nan",value=0/0},
        {name="zero",value=0},{name="remaining-only"}}) do
        for step=1,3 do
            local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
            for index,item in ipairs({{100,20,120},{130,10,140},{141,5,146}}) do
                local reported=index==step and bad.value or item[2]
                if index==step then reported=bad.value end
                m:Observe("a",{[tostring(index)]=durationEffect(item[1],item[2],reported)},item[1],true)
                m:Observe("a",{},item[3],true)
            end
            m:Observe("a",{fourth=durationEffect(161.5,20,20)},161.5,true)
            local row=only(m:GetDR("a",161.5))
            eq(row.stage,3,bad.name.." step "..step); eq(row.fullDurationBaseline,nil)
        end
    end
end)

test("wrong ratios and a possible reset between hits cannot establish a halving chain", function()
    for _,case in ipairs({{second=11,third=5},{second=10,third=6},{second=10,third=5,gap=15}}) do
        local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
        m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
        local second=120+(case.gap or 10)
        m:Observe("a",{second=durationEffect(second,case.second,case.second)},second,true)
        m:Observe("a",{},second+case.second,true)
        local third=second+case.second+1
        m:Observe("a",{third=durationEffect(third,case.third,case.third)},third,true)
        local row=only(m:GetDR("a",third)); eq(row.stage,3); eq(row.fullDurationBaseline,nil)
    end
end)

test("a partial observation invalidates an unfinished duration chain", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true)
    eq(only(m:GetDR("a",100)).durationCandidateStep,1)
    m:Observe("a",{},105,false)
    eq(only(m:GetDR("a",105)).durationCandidateStep,nil)
    m:Observe("a",{},120,true)
    m:Observe("a",{second=durationEffect(130,10,10)},130,true); m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    eq(only(m:GetDR("a",141)).fullDurationBaseline,nil)
end)

test("same-category intervening spells and overlapping effects break a duration chain", function()
    for _,overlap in ipairs({false,true}) do
        local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
        m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
        local effects={second=durationEffect(130,10,10,overlap and 100 or 101)}
        if overlap then effects.other=durationEffect(130,10,10,101) end
        m:Observe("a",effects,130,true); m:Observe("a",{},140,true)
        m:Observe("a",{third=durationEffect(141,5,5)},141,true)
        eq(only(m:GetDR("a",141)).fullDurationBaseline,nil)
    end
end)

test("duration chains do not borrow observations from another unit", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},90,true); m:Observe("b",{},120,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
    m:Observe("b",{second=durationEffect(130,10,10)},130,true); m:Observe("b",{},140,true)
    m:Observe("b",{third=durationEffect(141,5,5)},141,true)
    eq(only(m:GetDR("b",141)).fullDurationBaseline,nil)
end)

test("unrelated DR categories do not invalidate a fully observed duration chain", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
    local root=effect("root",400,125,121); root.applicationSource="loc"; root.reportedDuration=4
    m:Observe("a",{root=root},121,true); m:Observe("a",{},125,true)
    m:Observe("a",{second=durationEffect(130,10,10)},130,true); m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    local row=m:GetDR("a",141)[1]
    eq(row.category,"stun"); eq(row.fullDurationBaseline,20)
end)

test("cast-inferred elevation cannot qualify a duration chain", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
    m:EstimateDR("a",100,"stun",121,"guessed-two",121)
    m:EstimateDR("a",100,"stun",122,"guessed-three",122)
    m:Observe("a",{second=durationEffect(130,10,10)},130,true)
    eq(only(m:GetDR("a",130)).stageEstimated,true)
    m:Observe("a",{},140,true); m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    eq(only(m:GetDR("a",141)).fullDurationBaseline,nil)
end)

test("aura disagreement vetoes halving-chain samples without guessing their stages", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
    local aura=durationEffect(130,20,nil); aura.applicationSource="aura"
    m:Observe("a",{second=aura},130,true)
    m:Observe("a",{second=durationEffect(130.2,10,10)},130.3,true)
    m:Observe("a",{},140.2,true); m:Observe("a",{third=durationEffect(141,5,5)},141,true)
    local row=only(m:GetDR("a",141)); eq(row.stage,3); eq(row.fullDurationBaseline,nil)
end)

test("stable polls and late first timing can contribute only once to a duration chain", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    local unknown=effect("stun",100,120)
    m:Observe("a",{first=unknown},99.9,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100.1,true)
    for time=101,119 do
        m:Observe("a",{first=durationEffect(100,20,20)},time,true)
        local row=only(m:GetDR("a",time)); eq(row.stage,1); eq(row.durationCandidateStep,1)
    end
    m:Observe("a",{},120,true)
    m:Observe("a",{second=durationEffect(130,10,10)},130.1,true); m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,5)},141.1,true)
    eq(only(m:GetDR("a",141.1)).fullDurationBaseline,20)
end)

test("pending duration progress disappears once an unmeasured application is superseded", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{first=durationEffect(100,20,20)},100,true); m:Observe("a",{},120,true)
    m:Observe("a",{second=durationEffect(130,10,nil)},130,true)
    eq(only(m:GetDR("a",130)).durationCandidateStep,1,"the immediate next application can still gain timing")
    m:Observe("a",{},140,true)
    m:Observe("a",{third=durationEffect(141,5,nil)},141,true)
    local row=only(m:GetDR("a",141)); eq(row.durationCandidateStep,nil); eq(row.fullDurationBaseline,nil)
    m:Observe("a",{third=durationEffect(141,5,5)},141.1,true)
    row=only(m:GetDR("a",141.1)); eq(row.stage,3)
    eq(row.durationCandidateStep,nil); eq(row.fullDurationBaseline,nil)
end)

test("live a519 through a525 learns through an exact-end same-ID successor", function()
    local m=ns.Model.New(20,18)
    m:Observe("a",{},2661803.181,true)
    local aura=durationEffect(2661812.161,20,nil); aura.applicationSource="aura"
    m:Observe("a",{["a:519"]=aura},2661812.161,true)
    local function read(key,start,duration,now)
        local value=durationEffect(start,duration,start and duration or nil)
        if not start then value.expires=now+duration end
        m:Observe("a",{[key]=value},now,true)
        return only(m:GetDR("a",now))
    end
    read("a:519",nil,20,2661812.161)
    eq(read("a:519",2661812.250,20,2661812.334).durationCandidateStep,1)
    m:Observe("a",{},2661831.139,true)
    read("a:521",nil,10,2661831.598)
    eq(read("a:521",2661831.750,10,2661831.934).durationCandidateStep,2)
    read("a:521",nil,5,2661841.677)
    local row=read("a:521",2661841.750,5,2661841.940)
    eq(row.stage,3); eq(row.fullDurationBaseline,20)
    eq(row.fullDurationBaselineSource,"observed-halving-chain"); eq(row.resetEvidence,nil)
    m:Observe("a",{},2661846.575,true)
    read("a:523",nil,20,2661863.386)
    row=read("a:523",2661863.500,20,2661863.671)
    eq(row.stage,1); eq(row.started,2661863.500)
    eq(row.resetBaselineSource,"observed-halving-chain")
    m:Observe("a",{},2661873.175,true)
    read("a:525",nil,10,2661876.116)
    row=read("a:525",2661876.250,10,2661876.289)
    eq(row.stage,2); eq(row.resetEvidence,nil)
end)

local function replacementChain(key)
    key=key or "a:2"
    local m=ns.Model.New(20,18)
    m:Observe("a",{},90,true)
    m:Observe("a",{["a:1"]=durationEffect(100,20,20)},100,true)
    m:Observe("a",{},119,true)
    m:Observe("a",{[key]=durationEffect(120,10,10)},120,true)
    eq(only(m:GetDR("a",120)).durationCandidateStep,2)
    return m
end

test("both same-ID explicit successors can teach a chain without manufacturing quiet history", function()
    local m=ns.Model.New(20,18); m:Observe("a",{},90,true)
    m:Observe("a",{["a:1"]=durationEffect(100,20,20)},100,true)
    m:Observe("a",{["a:1"]=effect("stun",100,129.9)},119.9,true)
    m:Observe("a",{["a:1"]=durationEffect(120,10,10)},120,true)
    eq(only(m:GetDR("a",120)).durationCandidateStep,2)
    m:Observe("a",{["a:1"]=durationEffect(130,5,5)},130,true)
    local row=only(m:GetDR("a",130))
    eq(row.stage,3); eq(row.fullDurationBaseline,20); eq(row.resetEvidence,nil)
    -- Continued visibility after the old expiry is not observed absence.
    m:Observe("a",{["a:1"]=durationEffect(151,20,20)},151,true)
    row=only(m:GetDR("a",151)); eq(row.stage,3); eq(row.resetEvidence,nil)
end)

test("same-ID chain proof survives late first raw duration but not a changed evidence epoch", function()
    for _,partial in ipairs({false,true}) do
        local m=replacementChain()
        m:Observe("a",{["a:2"]=durationEffect(130,5,nil)},130,true)
        eq(only(m:GetDR("a",130)).fullDurationBaseline,nil)
        if partial then m:Observe("a",{},130.1,false) end
        m:Observe("a",{["a:2"]=durationEffect(130,5,5)},130.2,true)
        local row=only(m:GetDR("a",130.2))
        if partial then eq(row.fullDurationBaseline,nil) else eq(row.fullDurationBaseline,20) end
        eq(row.stage,3); eq(row.started,130)
        m:Observe("a",{["a:2"]=durationEffect(130,5,5)},131,true)
        row=only(m:GetDR("a",131)); eq(row.stage,3); eq(row.started,130)
    end
end)

test("only a live real identity with coherent explicit predecessor timing can connect a chain", function()
    for _,case in ipairs({"different-key","non-aura-key","fallback-old","fallback-new","retained-closed",
        "incoherent-old-end","overlap-boundary","reset-gap","partial","partial-current","wrong-ratio"}) do
        local m=replacementChain()
        local key,start,received="a:2",130,nil
        local value=durationEffect(start,5,5)
        if case=="different-key" then key="a:3"
        elseif case=="non-aura-key" then key="l:2"; m=replacementChain(key)
        elseif case=="fallback-old" then
            local prior=durationEffect(120,10,10); prior.fallbackIdentity=true
            m:Observe("a",{[key]=prior},121,true)
        elseif case=="fallback-new" then value.fallbackIdentity=true
        elseif case=="retained-closed" then m:Observe("a",{},131,true); received=131.2
        elseif case=="incoherent-old-end" then
            -- The model retains accepted explicit boundaries across weak polls;
            -- create the contradiction at the accepted first witness instead.
            m=ns.Model.New(20,18); m:Observe("a",{},90,true)
            m:Observe("a",{["a:1"]=durationEffect(100,20,20)},100,true); m:Observe("a",{},119,true)
            local prior=durationEffect(120,11,10)
            m:Observe("a",{[key]=prior},120,true)
            start=131; value=durationEffect(start,5,5)
        elseif case=="overlap-boundary" then start=129.999; value=durationEffect(start,5,5)
        elseif case=="reset-gap" then start=145; value=durationEffect(start,5,5)
        elseif case=="partial" then m:Observe("a",{},129,false)
        elseif case=="wrong-ratio" then value=durationEffect(start,6,6) end
        m:Observe("a",{[key]=value},received or start,case~="partial-current")
        local row=only(m:GetDR("a",received or start)); eq(row.fullDurationBaseline,nil,case)
        eq(row.resetEvidence,nil,case)
    end
end)

test("other prior or current category witnesses cannot establish a replacement-only chain", function()
    for _,case in ipairs({"prior-known","prior-pending","current-known","current-pending"}) do
        local m=replacementChain()
        -- A late older witness cannot advance the current category or replace
        -- candidate2; rejection must come from snapshot overlap evidence.
        local other=effect("stun",101,140,119)
        if case:find("pending") then other.expires=nil end
        if case:find("prior") then
            m:Observe("a",{["a:2"]=durationEffect(120,10,10),other=other},121,true)
            eq(only(m:GetDR("a",121)).durationCandidateStep,2)
        end
        local effects={["a:2"]=durationEffect(130,5,5)}
        if case:find("current") then effects.other=other end
        m:Observe("a",effects,130,true)
        local row=only(m:GetDR("a",130)); eq(row.fullDurationBaseline,nil,case)
        eq(row.resetEvidence,nil,case)
    end
end)

test("later or transient overlap invalidates an unfinished replacement proof", function()
    for _,case in ipairs({"with-raw","before-raw","while-current-absent"}) do
        local m=replacementChain()
        m:Observe("a",{["a:2"]=durationEffect(130,5,nil)},130,true)
        local other=effect("stun",101,140,119)
        if case=="with-raw" then
            m:Observe("a",{["a:2"]=durationEffect(130,5,5),other=other},130.2,true)
        else
            local effects={other=other}
            if case=="before-raw" then effects["a:2"]=durationEffect(130,5,nil) end
            m:Observe("a",effects,130.1,true)
            m:Observe("a",{["a:2"]=durationEffect(130,5,5)},130.2,true)
        end
        local row=only(m:GetDR("a",130.2)); eq(row.fullDurationBaseline,nil,case)
        eq(row.durationCandidateStep,nil,case)
    end
end)

test("a replacement boundary cannot teach a quiet baseline after a configured early reset", function()
    local m=ns.Model.New(20,1); m:Observe("a",{},0,true)
    m:Observe("a",{["a:1"]=durationEffect(100,20,nil)},100,true)
    m:Observe("a",{["a:1"]=durationEffect(122,10,10)},122,true)
    local row=only(m:GetDR("a",122)); eq(row.stage,1)
    eq(row.fullDurationBaseline,nil,"predicted nonoverlap is not twenty seconds of observed quiet")
end)


-- Shipping policy: stage and presentation share the application deadline.
test("application policy uses twenty seconds regardless of CC duration or early break", function()
    for _,duration in ipairs({2,3,4,20,30}) do
        local m=ns.Model.New(20,20,true)
        m:Observe("a",{x=effect("stun",100,100+duration,100)},100,true)
        local row=only(m:GetDR("a",100))
        eq(row.stageResetAt,120); eq(row.stageResetSource,"application")
        m:Observe("a",{},101,true)
        row=only(m:GetDR("a",119)); eq(row.remaining,1); eq(row.stage,1)
        eq(row.started,100); eq(row.active,false); eq(#m:GetDR("a",120),0)
        m:Observe("a",{y=effect("stun",100,124,120)},120,true)
        row=only(m:GetDR("a",120)); eq(row.stage,1); eq(row.stageResetAt,140)
    end
end)
test("application policy advances only on a new application within the window", function()
    local m=ns.Model.New(20,20,true)
    m:Observe("a",{x=effect("stun",100,120,100)},100,true)
    -- A rejected cast has no new aura. Stable polls must leave history alone.
    for _,at in ipairs({101,107,109}) do
        m:Observe("a",{x=effect("stun",100,120,100)},at,true)
        local row=only(m:GetDR("a",at)); eq(row.stage,1); eq(row.started,100); eq(row.stageResetAt,120)
    end
    m:Observe("a",{y=effect("stun",100,130,110)},110,true)
    local row=only(m:GetDR("a",110)); eq(row.stage,2); eq(row.stageResetAt,130)
    m:Observe("a",{},111,true)
    row=only(m:GetDR("a",129)); eq(row.stage,2); eq(row.remaining,1)
    eq(#m:GetDR("a",130),0)
end)
test("expired application cannot be recounted by an ongoing effect", function()
    local m=ns.Model.New(20,20,true)
    for _,at in ipairs({100,119,120,125,130}) do
        m:Observe("a",{x=effect("stun",100,140,100)},at,true)
        if at<120 then eq(only(m:GetDR("a",at)).stage,1)
        else eq(#m:GetDR("a",at),0) end
    end
end)
test("application policy cannot learn an earlier duration-based reset", function()
    local m=ns.Model.New(20,20,true)
    for i,duration in ipairs({20,10,5,20}) do
        local at=100+(i-1)*5
        local e=effect("stun",100,at+duration,at)
        e.applicationSource="loc"; e.reportedDuration=duration
        m:Observe("a",{[tostring(i)]=e},at,true)
        local row=only(m:GetDR("a",at))
        eq(row.stage,math.min(i,3)); eq(row.resetEvidence,nil); eq(row.stageResetAt,at+20)
    end
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
