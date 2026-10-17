-- Real Observer boundary tests; the WoW APIs are the external fixture.
-- Run from the workspace root with Lua 5.1 (or the bundled Lupa runner).
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": unexpected result")
end
local function truth(value, label) assert(value, label or "expected true") end
local secret = setmetatable({}, {
    __index = function() error("secret indexed") end,
    __tostring = function() error("secret formatted") end,
    __concat = function() error("secret concatenated") end,
    __lt = function() error("secret compared") end,
    __add = function() error("secret arithmetic") end,
})
local ns = {Safe = {}, Data = {
    auraCategory = {[118] = "incapacitate", [2637] = "incapacitate", [853] = "stun", [8056] = "frostshock"},
    castToSpell = {[853] = 853, [2139] = 2139, [60970] = 60970},
    spells = {[853] = {id = 853}, [2139] = {id = 2139, interrupt = true}, [60970] = {id = 60970}},
    resets = {[11958] = "mage"},
}, db = {interrupts = true, cooldownOverrides = {[853] = 55}}}
function ns.Safe.Readable(v) return not rawequal(v, secret) end
function ns.Safe.Number(v) if ns.Safe.Readable(v) and type(v) == "number" then return v end end
function ns.Safe.String(v) if ns.Safe.Readable(v) and type(v) == "string" then return v end end
function ns.Safe.Boolean(v) if ns.Safe.Readable(v) and type(v) == "boolean" then return v end end
function ns.Safe.Call(fn, ...) local ok,v=pcall(fn,...); if ok and ns.Safe.Readable(v) then return v end end

local fixture, observed, forgotten, casts
local function reset()
    fixture = {
        guid = {player = "Player-1-Self", target = "Player-1-A", nameplate1 = "Player-1-A"},
        name = {player = "Self", target = "Enemy", nameplate1 = "Enemy"},
        player = {player = true, target = true, focus = true, nameplate1 = true},
        hostile = {player = false, target = true, nameplate1 = true},
        auras = {player = {}, target = {}, focus = {}}, loc = {}, auraScans = {},
    }
    observed, forgotten, casts = {}, {}, {}
    UnitGUID = function(unit) return fixture.guid[unit] end
    UnitName = function(unit) return fixture.name[unit] end
    UnitIsPlayer = function(unit) return fixture.player[unit] end
    UnitCanAttack = function(a,unit) equal(a,"player","attack source"); return fixture.hostile[unit] end
    C_UnitAuras = {GetAuraDataByIndex = function(unit,index,filter)
        equal(filter,"HARMFUL","aura filter")
        if index == 1 then fixture.auraScans[unit] = (fixture.auraScans[unit] or 0) + 1 end
        if fixture.auraError then error("unavailable API") end
        if fixture.auraAllSecret then return secret end
        if fixture.auraUnbounded then return {spellId = 99999, auraInstanceID = index} end
        return fixture.auras[unit] and fixture.auras[unit][index]
    end}
    C_LossOfControl = {
        GetActiveLossOfControlDataCount = function() return fixture.locCount or #fixture.loc end,
        GetActiveLossOfControlData = function(index) return fixture.loc[index] end,
    }
    ns.model = {
        Observe = function(_,guid,effects,now,complete)
            observed[#observed+1] = {guid=guid,effects=effects,now=now,complete=complete}
        end,
        Forget = function(_,guid) forgotten[#forgotten+1] = guid end,
        Cast = function(_,guid,name,id,now,castID,manual,overrides)
            casts[#casts+1] = {guid=guid,name=name,id=id,now=now,castID=castID,manual=manual,overrides=overrides}
        end,
    }
    ns.db.interrupts = true
    ns.Observer.Init()
end
local function last(guid)
    for i=#observed,1,-1 do if observed[i].guid == guid then return observed[i] end end
end
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function effect(row) for _,v in pairs(row.effects) do return v end end
local function contains(t,v) for _,item in ipairs(t) do if item==v then return true end end end
local addonDir = ADDON_DIR or "work/bjarkiCC"
local bootstrap = loadfile(addonDir .. "/Bootstrap.lua")
if bootstrap then
    -- Use the real Safe helpers when integration files are available. The
    -- sentinels approximate protected inputs; Lua 5.1 cannot reproduce WoW's
    -- engine-level prohibition on secret truthiness.
    issecretvalue = function(v) return rawequal(v,secret) end
    issecrettable = function(v) return rawequal(v,secret) end
    canaccessvalue = function(v) return not rawequal(v,secret) end
    bootstrap("bjarkiCC",ns)
end
local loader = loadfile(addonDir .. "/Observer.lua")
if loader then loader("bjarkiCC",ns) end
truth(ns.Observer and type(ns.Observer.Scan)=="function", "Observer must expose the scan boundary")
local tests = {}
local function test(name,fn) tests[#tests+1] = {name,fn} end

-- Removing classification or using a cast as DR evidence must fail this test.
test("readable aura snapshots retain stable applications", function()
    reset()
    fixture.auras.target = {{spellId=853,auraInstanceID=44,expirationTime=16}}
    ns.Observer.Scan(10)
    local first = last("Player-1-A")
    truth(first.complete); equal(size(first.effects),1)
    equal(effect(first).category,"stun"); equal(effect(first).spellID,853); equal(effect(first).expires,16)
    local key = next(first.effects)
    ns.Observer.Scan(11)
    truth(last("Player-1-A").effects[key],"poll must retain application identity")
    equal(ns.Observer.GetUnitState("target").sensor,"aura")
end)
test("unmapped readable auras do not prevent complete snapshots", function()
    reset(); fixture.auras.target={{spellId=99999,auraInstanceID=1}}
    ns.Observer.Scan(10); truth(last("Player-1-A").complete); equal(size(last("Player-1-A").effects),0)
end)
test("secret spell identifier invalidates absence evidence", function()
    reset(); fixture.auras.target={{spellId=secret,auraInstanceID=8}}
    ns.Observer.Scan(10); equal(last("Player-1-A").complete,false)
    equal(ns.Observer.GetUnitState("target").status,"restricted")
    truth(ns.Observer.stats.restricted>0)
end)
test("aura API failures invalidate snapshots", function()
    reset(); fixture.auraError=true
    ns.Observer.Scan(10); equal(last("Player-1-A").complete,false)
    truth(ns.Observer.stats.apiErrors>0)
end)
test("aura scan cap cannot masquerade as complete enumeration", function()
    reset(); fixture.auraUnbounded=true
    ns.Observer.Scan(10); equal(last("Player-1-A").complete,false)
end)
test("missing application identity invalidates a known aura", function()
    reset(); fixture.auras.target={{spellId=853,expirationTime=15}}
    ns.Observer.Scan(10); equal(last("Player-1-A").complete,false)
end)
test("target identity change forgets previous continuity", function()
    reset(); ns.Observer.Scan(10)
    fixture.guid.target="Player-1-B"; ns.Observer.Scan(11)
    truth(contains(forgotten,"Player-1-A")); equal(ns.Observer.GetUnitState("target").guid,"Player-1-B")
end)
test("secret GUID is unavailable and clears old identity", function()
    reset(); ns.Observer.Scan(10); fixture.guid.target=secret
    ns.Observer.Scan(11); truth(contains(forgotten,"Player-1-A"))
    equal(ns.Observer.GetUnitState("target").guid,nil); equal(ns.Observer.GetUnitState("target").status,"unavailable")
end)
test("NPC and pet targets are excluded from DR", function()
    reset(); fixture.guid.target="Pet-1-A"; fixture.player.target=false
    ns.Observer.Scan(10); equal(last("Pet-1-A"),nil)
end)
test("friendly player targets remain eligible for observed DR", function()
    reset(); fixture.hostile.target=false; ns.Observer.Scan(10)
    truth(last("Player-1-A").complete)
end)
test("player LoC fallback uses stable aura identity and known spell IDs", function()
    reset(); fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.loc={{spellID=118,locType="CONFUSE",auraInstanceID=72,startTime=8,duration=6,timeRemaining=4}}
    ns.Observer.Scan(10)
    local row=last("Player-1-Self"); truth(row.complete); equal(effect(row).category,"incapacitate")
    equal(effect(row).expires,14); local key=next(row.effects)
    fixture.loc[1].timeRemaining=3; ns.Observer.Scan(11)
    truth(last("Player-1-Self").effects[key]); equal(ns.Observer.GetUnitState("player").sensor,"loc")
    truth(ns.Observer.GetUnitState("player").coverageLimited)
end)
test("LoC type alone does not assign a DR category", function()
    reset(); C_UnitAuras=nil
    fixture.loc={{spellID=99999,locType="STUN",startTime=8,duration=5}}
    ns.Observer.Scan(10); equal(size(last("Player-1-Self").effects),0)
end)
test("LoC fallback key is stable when no aura instance is provided", function()
    reset(); C_UnitAuras=nil
    fixture.loc={{spellID=853,locType="STUN",startTime=8,duration=6}}
    ns.Observer.Scan(10); local row=last("Player-1-Self"); truth(row.complete); local key=next(row.effects)
    truth(key); ns.Observer.Scan(11); truth(last("Player-1-Self").effects[key])
end)
test("secret LoC data is incomplete rather than empty", function()
    reset(); C_UnitAuras=nil; fixture.loc={secret}
    ns.Observer.Scan(10); equal(last("Player-1-Self").complete,false)
end)
test("first successful LoC switch invalidates confidence without forgetting witnesses", function()
    reset(); fixture.guid.target=nil; ns.Observer.Scan(10); observed={}
    fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    ns.Observer.Scan(11); equal(#forgotten,0)
    equal(#observed,2); equal(observed[1].complete,false); equal(size(observed[1].effects),0)
    equal(observed[2].complete,true)
    observed={}; ns.Observer.Scan(12); equal(#observed,1,"stable sensor cannot repeat handoff invalidation")
end)
test("LoC observed removal preserves the original application timer", function()
    reset(); fixture.guid.target=nil
    ns.Data.categories={{key="stun"},{key="incapacitate"},{key="frostshock"}}
    assert(loadfile(addonDir .. "/Model.lua"))("bjarkiCC",ns)
    ns.model=ns.Model.New(20,20)
    ns.Observer.Scan(0)
    fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.loc={{spellID=853,auraInstanceID=72,startTime=22,duration=2}}
    ns.Observer.Scan(22)
    equal(#ns.model:GetDR("Player-1-Self",22),1)
    fixture.auras.player={}; fixture.loc={}
    ns.Observer.Scan(24)
    local rows=ns.model:GetDR("Player-1-Self",24)
    equal(#rows,1,"removing CC must retain its DR window")
    equal(rows[1].active,false); equal(rows[1].remaining,18); equal(rows[1].started,22); equal(rows[1].stage,1)
    equal(ns.Observer.GetUnitState("player").sensor,"loc")
    ns.Observer.Scan(25); equal(ns.model:GetDR("Player-1-Self",25)[1].remaining,17)
end)
test("selected LoC remains incomplete if its API vanishes despite readable auras", function()
    reset(); fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    ns.Observer.Scan(10)
    fixture.auras.player={}; C_LossOfControl=nil; ns.Observer.Scan(11)
    equal(ns.Observer.GetUnitState("player").sensor,"loc")
    equal(last("Player-1-Self").complete,false)
end)
test("observer Init permits a fresh aura sensor selection", function()
    reset(); fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    ns.Observer.Scan(10)
    fixture.auras.player={}; ns.Observer.Init(); ns.Observer.Scan(11)
    equal(ns.Observer.GetUnitState("player").sensor,"aura")
end)
test("a scan gap invalidates history before consuming fresh snapshots", function()
    reset(); ns.Observer.Scan(10); observed={}
    ns.Observer.Scan(12)
    equal(observed[1].guid,"Player-1-Self"); equal(observed[1].complete,false)
    equal(observed[2].guid,"Player-1-A"); equal(observed[2].complete,false)
    equal(observed[3].guid,"Player-1-Self"); equal(observed[3].complete,true)
    equal(observed[4].guid,"Player-1-A"); equal(observed[4].complete,true)
end)
test("a self target has only one invalidation per scan gap", function()
    reset(); fixture.guid.target="Player-1-Self"; ns.Observer.Scan(10); observed={}
    ns.Observer.Scan(12)
    equal(#observed,2); equal(observed[1].complete,false); equal(observed[2].complete,true)
end)
test("scan gap makes real DR uncertain until a new quiet window", function()
    reset(); fixture.guid.target=nil
    ns.Data.categories={{key="stun"},{key="incapacitate"},{key="frostshock"}}
    assert(loadfile(addonDir .. "/Model.lua"))("bjarkiCC",ns)
    ns.model=ns.Model.New(20,20)
    for now=0,20 do ns.Observer.Scan(now) end
    fixture.auras.player={{spellId=853,auraInstanceID=8,expirationTime=22}}
    ns.Observer.Scan(21)
    equal(ns.model:GetDR("Player-1-Self",21)[1].uncertain,false)
    fixture.auras.player={}; ns.Observer.Scan(24)
    local row=ns.model:GetDR("Player-1-Self",24)[1]
    truth(row); equal(row.uncertain,true); equal(row.active,false)
    for now=25,44 do ns.Observer.Scan(now) end
    fixture.auras.player={{spellId=853,auraInstanceID=9,expirationTime=47}}
    ns.Observer.Scan(45)
    equal(ns.model:GetDR("Player-1-Self",45)[1].uncertain,false)
end)
test("expired or secret optional timing does not force unsafe arithmetic", function()
    reset(); fixture.auras.target={{spellId=853,auraInstanceID=4,expirationTime=secret}}
    ns.Observer.Scan(10); equal(effect(last("Player-1-A")).expires,nil)
end)
test("hostile cast observations preserve caster and rank ID for model", function()
    reset(); ns.Observer.OnCast("nameplate1","Cast-44",853,10)
    equal(#casts,1); equal(casts[1].guid,"Player-1-A"); equal(casts[1].name,"Enemy")
    equal(casts[1].id,853); equal(casts[1].castID,"Cast-44"); equal(casts[1].manual,false)
    equal(casts[1].overrides[853],55); equal(ns.Observer.stats.acceptedCasts,1)
end)
test("friendly casts and hostile NPCs do not become player cooldowns", function()
    reset(); fixture.hostile.nameplate1=false; ns.Observer.OnCast("nameplate1","Cast-1",853,10)
    fixture.hostile.nameplate1=true; fixture.player.nameplate1=false; fixture.guid.nameplate1="Creature-1-A"
    ns.Observer.OnCast("nameplate1","Cast-2",853,11); equal(#casts,0)
end)
test("readable hostile pet casts retain their own identity", function()
    reset(); fixture.player.nameplate1=false; fixture.guid.nameplate1="Pet-1-A"
    ns.Observer.OnCast("nameplate1","Cast-2",853,11); equal(#casts,1); equal(casts[1].guid,"Pet-1-A")
end)
test("secret input cannot be normalized into an accepted cast", function()
    reset()
    ns.Observer.OnCast(secret,"Cast-1",853,10)
    ns.Observer.OnCast("target",secret,853,10)
    ns.Observer.OnCast("target","Cast-2",secret,10)
    fixture.name.target=secret; ns.Observer.OnCast("target","Cast-3",853,10)
    fixture.name.target="Enemy"; fixture.hostile.target=secret; ns.Observer.OnCast("target","Cast-4",853,10)
    equal(#casts,0)
end)
test("known reset casts reach model even without a cooldown row", function()
    reset(); ns.Observer.OnCast("target","Cast-1",11958,10); equal(#casts,1); equal(casts[1].id,11958)
end)
test("unknown spells are ignored while interrupt filtering retains observations", function()
    reset(); ns.Observer.OnCast("target","Cast-1",99999,10)
    ns.db.interrupts=false; ns.Observer.OnCast("target","Cast-2",2139,10); equal(#casts,1); equal(casts[1].id,2139)
end)
test("dropping a self target cannot erase the player history", function()
    reset(); fixture.guid.target="Player-1-Self"
    ns.Observer.Scan(10)
    fixture.guid.target=nil; ns.Observer.Scan(11)
    equal(contains(forgotten,"Player-1-Self"),nil)
end)
test("self target shares the player sensor without a second conflicting snapshot", function()
    reset(); fixture.guid.target="Player-1-Self"
    fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.loc={{spellID=853,auraInstanceID=2,startTime=8,duration=6}}
    ns.Observer.Scan(10)
    equal(#observed,1); equal(ns.Observer.GetUnitState("target").sensor,"loc")
    equal(size(last("Player-1-Self").effects),1)
end)
test("secret count and unreadable record access stay incomplete", function()
    reset(); C_UnitAuras=nil; fixture.locCount=secret
    ns.Observer.Scan(10); equal(last("Player-1-Self").complete,false)
    fixture.locCount=1; fixture.loc={setmetatable({}, {__index=function() error("field denied") end})}
    ns.Observer.Scan(11); equal(last("Player-1-Self").complete,false)
end)
test("no APIs means unavailable evidence and never a successful empty scan", function()
    reset(); C_UnitAuras=nil; C_LossOfControl=nil; ns.Observer.Scan(10)
    equal(last("Player-1-Self").complete,false); equal(last("Player-1-A").complete,false)
end)
test("readable nil cast identifier does not suppress a valid observation", function()
    reset(); ns.Observer.OnCast("target",nil,853,10)
    equal(#casts,1); equal(casts[1].castID,nil)
end)

-- Omitting focus or indexing history by a token instead of its GUID breaks
-- these cases. Use the real model where continuity affects visible DR rows.
local function realModel()
    ns.Data.categories={{key="stun"},{key="incapacitate"},{key="frostshock"}}
    assert(loadfile(addonDir .. "/Model.lua"))("bjarkiCC",ns)
    ns.model=ns.Model.New(20,20)
end

local function byUnitLoC()
    fixture.locByUnit = {target = {}, focus = {}}
    fixture.locByUnitScans = {}
    C_LossOfControl.GetActiveLossOfControlDataCountByUnit = function(unit)
        fixture.locByUnitScans[unit] = (fixture.locByUnitScans[unit] or 0) + 1
        return fixture.locByUnitCount or #(fixture.locByUnit[unit] or {})
    end
    C_LossOfControl.GetActiveLossOfControlDataByUnit = function(unit,index)
        return fixture.locByUnit[unit] and fixture.locByUnit[unit][index]
    end
end

test("target and focus accept readable ByUnit LoC witnesses on restricted aura scans", function()
    for _,unit in ipairs({"target","focus"}) do
        reset(); byUnitLoC(); fixture.guid[unit]="Player-1-Enemy"
        fixture.auras[unit]={{spellId=secret,auraInstanceID=19}}
        fixture.locByUnit[unit]={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
        ns.Observer.Scan(10)
        local row=last("Player-1-Enemy")
        truth(row.effects["a:19"]); equal(size(row.effects),1); equal(row.complete,false)
        equal(row.effects["a:19"].category,"stun")
        local state=ns.Observer.GetUnitState(unit)
        equal(state.sensor,"aura+loc"); equal(state.auraComplete,false)
        equal(state.mappedAuras,0); equal(state.byUnitAvailable,true)
        equal(state.byUnitComplete,true); equal(state.mappedLoC,1)
        truth(state.reason); truth(state.coverageLimited)
    end
end)

test("partial aura and ByUnit witnesses merge without duplicate instance applications", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=853,auraInstanceID=19},{spellId=secret,auraInstanceID=88}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=10,duration=6},
        {spellID=118,auraInstanceID=20,startTime=10,duration=6}}
    ns.Observer.Scan(10)
    local rows=ns.model:GetDR("Player-1-A",10)
    equal(#rows,2); equal(rows[1].stage,1); equal(rows[2].stage,1)
    equal(ns.Observer.GetUnitState("target").mappedAuras,1)
    equal(ns.Observer.GetUnitState("target").mappedLoC,2)
end)

test("mixed sensor handoffs preserve the application timer and stage", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
    ns.Observer.Scan(10)
    fixture.auras.target={{spellId=853,auraInstanceID=19}}; ns.Observer.Scan(11)
    local row=ns.model:GetDR("Player-1-A",11)[1]
    truth(row); equal(row.stage,1); equal(row.started,10); equal(row.remaining,19)
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}; ns.Observer.Scan(12)
    row=ns.model:GetDR("Player-1-A",12)[1]
    equal(row.stage,1); equal(row.started,10); equal(row.remaining,18)
end)

test("empty ByUnit snapshot cannot remove a partially observed aura or prove completeness", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
    ns.Observer.Scan(10); fixture.locByUnit.target={}; ns.Observer.Scan(11)
    local row=ns.model:GetDR("Player-1-A",11)[1]
    truth(row); equal(row.stage,1); equal(row.started,10); equal(row.active,true); truth(row.uncertain)
    equal(ns.Observer.GetUnitState("target").status,"restricted")
    equal(ns.Observer.GetUnitState("target").byUnitComplete,true)
end)

test("missing or secret ByUnit data preserves partial readable aura witnesses", function()
    for _,mode in ipairs({"missing","secret-count","secret-record","secret-spell","unknown-spell"}) do
        reset()
        fixture.auras.target={{spellId=853,auraInstanceID=19},{spellId=secret,auraInstanceID=20}}
        if mode~="missing" then
            byUnitLoC()
            fixture.locByUnit.target={{spellID=118,auraInstanceID=20,startTime=10,duration=6}}
            if mode=="secret-count" then fixture.locByUnitCount=secret end
            if mode=="secret-record" then fixture.locByUnit.target={secret} end
            if mode=="secret-spell" then fixture.locByUnit.target[1].spellID=secret end
            if mode=="unknown-spell" then fixture.locByUnit.target[1].spellID=99999 end
        end
        ns.Observer.Scan(10)
        local row=last("Player-1-A"); equal(row.complete,false); equal(size(row.effects),1)
        truth(row.effects["a:19"])
        equal(ns.Observer.GetUnitState("target").byUnitAvailable,mode~="missing")
        if mode=="unknown-spell" then equal(ns.Observer.GetUnitState("target").unmappedSpellIDs[1],99999) end
    end
end)

test("complete aura scans do not depend on ByUnit availability or expose unnecessary calls", function()
    reset(); byUnitLoC(); fixture.locByUnitCount=secret
    fixture.auras.target={{spellId=853,auraInstanceID=19}}
    ns.Observer.Scan(10)
    equal(last("Player-1-A").complete,true); equal(fixture.locByUnitScans.target,nil)
    local state=ns.Observer.GetUnitState("target")
    equal(state.auraComplete,true); equal(state.byUnitComplete,nil); equal(state.mappedLoC,0)
end)

test("ByUnit observations for a shared target focus GUID happen only once", function()
    reset(); byUnitLoC(); fixture.guid.focus="Player-1-A"
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
    ns.Observer.Scan(10)
    equal(fixture.locByUnitScans.target,1); equal(fixture.locByUnitScans.focus,nil)
    equal(ns.Observer.GetUnitState("target"),ns.Observer.GetUnitState("focus"))
    equal(size(last("Player-1-A").effects),1)
end)

test("missing-instance LoC fallback stays stable and does not duplicate same-spell aura", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,startTime=10,duration=6}}
    ns.Observer.Scan(10); ns.Observer.Scan(11)
    equal(ns.model:GetDR("Player-1-A",11)[1].stage,1)
    fixture.auras.target={{spellId=853,auraInstanceID=19},{spellId=secret,auraInstanceID=20}}
    ns.Observer.Scan(12)
    local row=ns.model:GetDR("Player-1-A",12)[1]
    equal(row.stage,1); equal(row.started,10); truth(row.uncertain)
    ns.Observer.Scan(13); equal(ns.model:GetDR("Player-1-A",13)[1].stage,1)
end)

test("unmapped aura diagnostics are readable sorted unique and bounded", function()
    reset()
    for id=99930,99901,-1 do fixture.auras.target[#fixture.auras.target+1]={spellId=id,auraInstanceID=id} end
    fixture.auras.target[#fixture.auras.target+1]={spellId=99901,auraInstanceID=77777}
    fixture.auras.target[#fixture.auras.target+1]={spellId=secret,auraInstanceID=88888}
    ns.Observer.Scan(10)
    local ids=ns.Observer.GetUnitState("target").unmappedSpellIDs
    truth(ids); equal(#ids,12)
    for i=2,#ids do truth(ids[i-1]<ids[i]) end
end)

test("player LoC and aura sensors use the same stable instance key", function()
    reset(); fixture.auras.player={{spellId=secret,auraInstanceID=19}}
    fixture.loc={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
    ns.Observer.Scan(10)
    truth(last("Player-1-Self").effects["a:19"])
end)

test("ByUnit failures and secret application keys cannot manufacture observations", function()
    for _,mode in ipairs({"error","fractional-count","missing-key","secret-key","secret-start","type-only"}) do
        reset(); byUnitLoC(); fixture.auras.target={{spellId=secret,auraInstanceID=19}}
        fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=10,duration=6}}
        if mode=="error" then C_LossOfControl.GetActiveLossOfControlDataByUnit=function() error("denied") end end
        if mode=="fractional-count" then fixture.locByUnitCount=1.5 end
        if mode=="missing-key" then fixture.locByUnit.target={{spellID=853}} end
        if mode=="secret-key" then fixture.locByUnit.target={{spellID=853,auraInstanceID=secret}} end
        if mode=="secret-start" then fixture.locByUnit.target={{spellID=853,startTime=secret}} end
        if mode=="type-only" then fixture.locByUnit.target={{locType="STUN",spellID=secret,auraInstanceID=19}} end
        ns.Observer.Scan(10)
        equal(size(last("Player-1-A").effects),0); equal(last("Player-1-A").complete,false)
        equal(ns.Observer.GetUnitState("target").byUnitComplete,false)
    end
end)

test("ByUnit start fallback cannot count a second copy of an existing aura", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=853,auraInstanceID=19},{spellId=secret,auraInstanceID=20}}
    fixture.locByUnit.target={{spellID=853,startTime=10,duration=6}}
    ns.Observer.Scan(10)
    local row=ns.model:GetDR("Player-1-A",10)[1]
    truth(row); equal(row.stage,1)
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}; ns.Observer.Scan(11)
    row=ns.model:GetDR("Player-1-A",11)[1]
    equal(row.stage,1); equal(row.started,10)
    fixture.auras.target={}; fixture.locByUnit.target={}; ns.Observer.Scan(12)
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,startTime=13,duration=6}}; ns.Observer.Scan(13)
    equal(ns.model:GetDR("Player-1-A",13)[1].stage,2)
end)

test("permanently restricted scans cannot grow retained witness memory without bound", function()
    reset(); realModel(); byUnitLoC(); fixture.guid.player=nil
    fixture.auras.target={{spellId=secret,auraInstanceID=9999}}
    for i=1,530 do
        fixture.locByUnit.target={{spellID=853,auraInstanceID=i,startTime=i,duration=6}}
        ns.Observer.Scan(i)
    end
    equal(size(ns.Observer.GetUnitState("target").witnesses),512)
    equal(size(ns.model.units["Player-1-A"].effects),512)
    truth(ns.Observer.GetUnitState("target").reason:find("capacity"))
    fixture.auras.target={}; fixture.locByUnit.target={}; ns.Observer.Scan(531)
    equal(size(ns.Observer.GetUnitState("target").witnesses),0)
    fixture.auras.target={{spellId=secret,auraInstanceID=9999}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=1000,startTime=532,duration=6}}
    ns.Observer.Scan(532); equal(size(ns.Observer.GetUnitState("target").witnesses),1)
end)

test("readable friendly focus has its own aura observation", function()
    reset(); fixture.guid.focus="Player-1-B"; fixture.hostile.focus=false
    fixture.auras.focus={{spellId=118,auraInstanceID=70,expirationTime=16}}
    ns.Observer.Scan(10)
    local row=last("Player-1-B")
    truth(row,"focus must be observed"); truth(row.complete)
    equal(effect(row).category,"incapacitate"); equal(effect(row).expires,16)
    local state=ns.Observer.GetUnitState("focus")
    truth(state); equal(state.guid,"Player-1-B"); equal(state.sensor,"aura")
    equal(state.status,"readable")
end)

test("shared target and focus are scanned only once", function()
    reset(); fixture.guid.focus="Player-1-A"
    fixture.auras.target={{spellId=853,auraInstanceID=44}}
    fixture.auras.focus={{spellId=118,auraInstanceID=70}}
    ns.Observer.Scan(10)
    equal(#observed,2); equal(fixture.auraScans.target,1); equal(fixture.auraScans.focus,nil)
    equal(effect(last("Player-1-A")).category,"stun")
    local target,focus=ns.Observer.GetUnitState("target"),ns.Observer.GetUnitState("focus")
    truth(focus); equal(focus.guid,target.guid); equal(focus.status,target.status)
    equal(focus.sensor,target.sensor)
end)

test("switching target preserves the DR reset window retained by focus", function()
    reset(); realModel(); fixture.guid.focus="Player-1-A"
    for now=0,20 do ns.Observer.Scan(now) end
    fixture.auras.target={{spellId=853,auraInstanceID=44,expirationTime=23}}
    ns.Observer.Scan(21)
    fixture.auras.target={}; fixture.guid.target="Player-1-B"
    ns.Observer.Scan(22)
    local row=ns.model:GetDR("Player-1-A",22)[1]
    truth(row,"focus must retain the target's DR history")
    equal(row.stage,1); equal(row.active,false); equal(row.remaining,19); equal(row.uncertain,false)
    fixture.auras.focus={{spellId=853,auraInstanceID=45,expirationTime=26}}
    ns.Observer.Scan(23)
    equal(ns.model:GetDR("Player-1-A",23)[1].stage,2)
end)

test("target and focus handoffs preserve a running DR window in both directions", function()
    for _,tokens in ipairs({{"target","focus"},{"focus","target"}}) do
        reset(); realModel(); fixture.guid.target=nil
        local old,new=tokens[1],tokens[2]
        fixture.guid[old]="Player-1-A"
        fixture.auras[old]={{spellId=853,auraInstanceID=44}}
        ns.Observer.Scan(10); fixture.auras[old]={}; ns.Observer.Scan(11)
        fixture.guid[old]=nil; fixture.guid[new]="Player-1-A"
        ns.Observer.Scan(12)
        local row=ns.model:GetDR("Player-1-A",12)[1]
        truth(row,"handoff must keep the reset window")
        equal(row.stage,1); equal(row.active,false); equal(row.remaining,18)
    end
end)

test("simultaneous target focus swaps preserve both histories", function()
    reset(); realModel(); fixture.guid.focus="Player-1-B"
    fixture.auras.target={{spellId=853,auraInstanceID=44}}
    fixture.auras.focus={{spellId=118,auraInstanceID=70}}
    ns.Observer.Scan(10)
    fixture.auras.target={}; fixture.auras.focus={}; ns.Observer.Scan(11)
    fixture.guid.target="Player-1-B"; fixture.guid.focus="Player-1-A"
    ns.Observer.Scan(12)
    local a,b=ns.model:GetDR("Player-1-A",12)[1],ns.model:GetDR("Player-1-B",12)[1]
    truth(a,"A must survive a swap"); truth(b,"B must survive a swap")
    equal(a.category,"stun"); equal(b.category,"incapacitate")
    equal(a.remaining,18); equal(b.remaining,18)
end)

test("an active aura handoff neither removes nor recounts the application", function()
    reset(); realModel()
    for now=0,20 do ns.Observer.Scan(now) end
    local aura={spellId=853,auraInstanceID=44,expirationTime=25}
    fixture.auras.target={aura}; ns.Observer.Scan(21)
    fixture.guid.target=nil; fixture.guid.focus="Player-1-A"
    fixture.auras.target={}; fixture.auras.focus={aura}; ns.Observer.Scan(22)
    local row=ns.model:GetDR("Player-1-A",22)[1]
    truth(row); equal(row.stage,1); equal(row.active,true); equal(row.uncertain,false)
    fixture.guid.target="Player-1-A"; fixture.guid.focus=nil
    fixture.auras.target={aura}; fixture.auras.focus={}; ns.Observer.Scan(23)
    row=ns.model:GetDR("Player-1-A",23)[1]
    truth(row); equal(row.stage,1); equal(row.active,true); equal(row.uncertain,false)
end)

test("clearing the last focus identity removes its stale DR history", function()
    reset(); realModel(); fixture.guid.focus="Player-1-B"
    fixture.auras.focus={{spellId=853,auraInstanceID=44}}
    ns.Observer.Scan(10); equal(#ns.model:GetDR("Player-1-B",10),1)
    fixture.guid.focus=nil; fixture.auras.focus={}; ns.Observer.Scan(11)
    equal(#ns.model:GetDR("Player-1-B",11),0)
    local state=ns.Observer.GetUnitState("focus")
    truth(state); equal(state.guid,nil); equal(state.status,"unavailable")
    fixture.guid.focus="Player-1-B"; ns.Observer.Scan(12)
    equal(#ns.model:GetDR("Player-1-B",12),0)
end)

test("shared GUID is forgotten once only after both aliases disappear", function()
    reset(); fixture.guid.focus="Player-1-A"; ns.Observer.Scan(10)
    local focus=ns.Observer.GetUnitState("focus"); truth(focus); equal(focus.guid,"Player-1-A")
    fixture.guid.focus=nil; ns.Observer.Scan(11)
    equal(contains(forgotten,"Player-1-A"),nil)
    fixture.guid.focus="Player-1-A"; ns.Observer.Scan(12)
    fixture.guid.target=nil; fixture.guid.focus=nil; ns.Observer.Scan(13)
    equal(#forgotten,1); equal(forgotten[1],"Player-1-A")
end)

test("self focus shares player LoC and clearing it preserves player history", function()
    reset(); fixture.guid.target="Player-1-Self"; fixture.guid.focus="Player-1-Self"
    fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.auras.focus={{spellId=118,auraInstanceID=70}}
    fixture.loc={{spellID=853,auraInstanceID=2,startTime=8,duration=6}}
    ns.Observer.Scan(10)
    equal(#observed,1); equal(fixture.auraScans.target,nil); equal(fixture.auraScans.focus,nil)
    local player,focus=ns.Observer.GetUnitState("player"),ns.Observer.GetUnitState("focus")
    truth(focus); equal(focus.sensor,"loc"); equal(focus.coverageLimited,true)
    equal(focus.coverageNote,player.coverageNote)
    equal(effect(last("Player-1-Self")).category,"stun")
    fixture.guid.focus=nil; ns.Observer.Scan(11)
    equal(contains(forgotten,"Player-1-Self"),nil)
end)

test("self focus sensor handoffs preserve observed stage and application clock", function()
    reset(); realModel(); fixture.guid.target=nil; fixture.guid.focus="Player-1-Self"
    fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.loc={{spellID=853,auraInstanceID=2,startTime=8,duration=6}}
    ns.Observer.Scan(10)
    fixture.loc={{spellID=853,auraInstanceID=3,startTime=11,duration=6}}
    ns.Observer.Scan(11); equal(ns.model:GetDR("Player-1-Self",11)[1].stage,2)
    equal(ns.Observer.GetUnitState("focus").sensor,"loc")
    fixture.auras.focus={{spellId=853,auraInstanceID=3,expirationTime=17,duration=6}}
    fixture.guid.player=secret; ns.Observer.Scan(12)
    local row=ns.model:GetDR("Player-1-Self",12)[1]
    equal(row.stage,2); equal(row.started,11); equal(row.remaining,19); truth(row.uncertain)
    equal(ns.Observer.GetUnitState("player").guid,nil)
    equal(ns.Observer.GetUnitState("focus").sensor,"aura")
    fixture.guid.player="Player-1-Self"; ns.Observer.Scan(13)
    row=ns.model:GetDR("Player-1-Self",13)[1]
    equal(row.stage,2); equal(row.started,11); equal(row.remaining,18); truth(row.uncertain)
    equal(ns.Observer.GetUnitState("focus").sensor,"loc")
end)

test("restricted or nonplayer focus identity cannot retain old history", function()
    local invalid={
        {guid=secret,player=true}, {guid="invalid",player=true},
        {guid="Pet-1-B",player=false}, {guid="Creature-1-B",player=false},
        {guid="Player-1-B",player=secret}, {guid="Player-1-B",player=false},
    }
    for _,case in ipairs(invalid) do
        reset(); fixture.guid.focus="Player-1-B"; ns.Observer.Scan(10)
        truth(last("Player-1-B"),"readable focus must first establish identity")
        fixture.guid.focus=case.guid; fixture.player.focus=case.player
        ns.Observer.Scan(11)
        truth(contains(forgotten,"Player-1-B"))
        equal(ns.Observer.GetUnitState("focus").guid,nil)
        equal(ns.Observer.GetUnitState("focus").status,"unavailable")
    end
end)

test("restricted focus alias cannot erase a readable target", function()
    reset(); fixture.guid.focus="Player-1-A"; ns.Observer.Scan(10)
    truth(ns.Observer.GetUnitState("focus"))
    fixture.player.focus=secret; ns.Observer.Scan(11)
    equal(ns.Observer.GetUnitState("focus").guid,nil)
    equal(ns.Observer.GetUnitState("target").guid,"Player-1-A")
    equal(contains(forgotten,"Player-1-A"),nil)
end)

test("scan gaps invalidate focus histories before fresh snapshots", function()
    reset(); fixture.guid.focus="Player-1-B"; ns.Observer.Scan(10); observed={}
    ns.Observer.Scan(12)
    equal(#observed,6)
    equal(observed[1].guid,"Player-1-Self"); equal(observed[1].complete,false)
    equal(observed[2].guid,"Player-1-A"); equal(observed[2].complete,false)
    equal(observed[3].guid,"Player-1-B"); equal(observed[3].complete,false)
    equal(observed[4].guid,"Player-1-Self"); equal(observed[4].complete,true)
    equal(observed[5].guid,"Player-1-A"); equal(observed[5].complete,true)
    equal(observed[6].guid,"Player-1-B"); equal(observed[6].complete,true)
end)

test("scan gaps invalidate shared target focus and self aliases once", function()
    for _,guid in ipairs({"Player-1-A","Player-1-Self"}) do
        reset(); fixture.guid.target=guid; fixture.guid.focus=guid; ns.Observer.Scan(10)
        truth(ns.Observer.GetUnitState("focus")); observed={}; ns.Observer.Scan(12)
        local invalidations,snapshots=0,0
        for _,row in ipairs(observed) do
            if row.guid==guid then
                if row.complete then snapshots=snapshots+1 else invalidations=invalidations+1 end
            end
        end
        equal(invalidations,1); equal(snapshots,1)
    end
end)

test("readable aura timing carries the original application time", function()
    reset(); fixture.auras.target={{spellId=853,auraInstanceID=44,expirationTime=40,duration=20}}
    ns.Observer.Scan(29)
    equal(effect(last("Player-1-A")).appliedAt,20)
end)

test("readable LoC timing carries startTime instead of scan time", function()
    reset(); fixture.auras.player={{spellId=secret,auraInstanceID=8}}
    fixture.loc={{spellID=118,auraInstanceID=72,startTime=20,duration=20}}
    ns.Observer.Scan(29)
    equal(effect(last("Player-1-Self")).appliedAt,20)
end)

test("unreadable invalid or future aura timing never becomes application arithmetic", function()
    for _,case in ipairs({{secret,20},{40,secret},{40,0},{10,20},{50,20},{math.huge,20},{40,math.huge}}) do
        reset(); fixture.auras.target={{spellId=853,auraInstanceID=44,expirationTime=case[1],duration=case[2]}}
        ns.Observer.Scan(29)
        equal(effect(last("Player-1-A")).appliedAt,nil)
    end
    for _,start in ipairs({secret,-1,30,math.huge}) do
        reset(); fixture.auras.player={{spellId=secret,auraInstanceID=8}}
        fixture.loc={{spellID=118,auraInstanceID=72,startTime=start,duration=20}}
        ns.Observer.Scan(29)
        equal(effect(last("Player-1-Self")).appliedAt,nil)
    end
end)

test("late LoC observations and repeated applications keep original boundaries end to end", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=secret,auraInstanceID=19}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=20,duration=20}}
    ns.Observer.Scan(29)
    local row=ns.model:GetDR("Player-1-A",29)[1]
    equal(row.started,20); equal(row.remaining,11); equal(row.stage,1)
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=30,duration=10}}
    ns.Observer.Scan(30)
    row=ns.model:GetDR("Player-1-A",30)[1]
    equal(row.started,30); equal(row.stage,2)
    ns.Observer.Scan(31); equal(ns.model:GetDR("Player-1-A",31)[1].stage,2)
    fixture.locByUnit.target={}; ns.Observer.Scan(32)
    equal(ns.model:GetDR("Player-1-A",32)[1].remaining,18)
end)

test("an exact merged LoC witness supplies the preferred application timestamp", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=853,auraInstanceID=19,expirationTime=40.3,duration=20},
        {spellId=secret,auraInstanceID=20}}
    fixture.locByUnit.target={{spellID=853,auraInstanceID=19,startTime=20,duration=20}}
    ns.Observer.Scan(29)
    local row=ns.model:GetDR("Player-1-A",29)[1]
    equal(row.started,20); equal(row.remaining,11); equal(row.stage,1)
end)

test("player aura to LoC handoff counts the second observed application", function()
    reset(); realModel(); fixture.guid.target=nil
    for now=0,20 do ns.Observer.Scan(now) end
    fixture.auras.player={{spellId=853,auraInstanceID=19,expirationTime=41,duration=20}}
    ns.Observer.Scan(21)
    local row=ns.model:GetDR("Player-1-Self",21)[1]
    equal(row.stage,1); equal(row.uncertain,false)
    fixture.auras.player={}; ns.Observer.Scan(22)
    fixture.auras.player={{spellId=secret,auraInstanceID=20}}
    fixture.loc={{spellID=853,auraInstanceID=20,startTime=23,duration=10}}
    ns.Observer.Scan(23)
    row=ns.model:GetDR("Player-1-Self",23)[1]
    equal(row.stage,2); equal(row.started,23); truth(row.uncertain)
    fixture.loc={}; ns.Observer.Scan(24)
    row=ns.model:GetDR("Player-1-Self",24)[1]
    equal(row.stage,2); equal(row.started,23); equal(row.remaining,19); equal(row.active,false)
end)

test("player handoff of the same application cannot double count or restart", function()
    for _,fallback in ipairs({false,true}) do
        reset(); realModel(); fixture.guid.target=nil
        fixture.auras.player={{spellId=853,auraInstanceID=19,expirationTime=41,duration=20}}
        ns.Observer.Scan(21)
        fixture.auras.player={{spellId=secret,auraInstanceID=19}}
        fixture.loc={{spellID=853,auraInstanceID=not fallback and 19 or nil,startTime=21,duration=20}}
        ns.Observer.Scan(22)
        local row=ns.model:GetDR("Player-1-Self",22)[1]
        equal(row.stage,1); equal(row.started,21); equal(row.remaining,19); truth(row.uncertain)
        if fallback then equal(ns.Observer.GetUnitState("player").status,"restricted") end
        ns.Observer.Scan(23)
        row=ns.model:GetDR("Player-1-Self",23)[1]
        equal(row.stage,1); equal(row.started,21); equal(row.remaining,18)
        fixture.loc={}; ns.Observer.Scan(24)
        equal(size(ns.model.units["Player-1-Self"].effects),0)
        ns.Observer.Scan(41)
        row=ns.model:GetDR("Player-1-Self",41)[1]
        truth(row,"stage survives the expired application timer")
        equal(row.stage,1); equal(row.remaining,0); equal(row.stageResetAt,44)
        ns.Observer.Scan(44); equal(#ns.model:GetDR("Player-1-Self",44),0)
    end
end)

test("no-instance LoC refresh retains canonical identity and newer application time", function()
    reset(); realModel(); fixture.guid.target=nil
    fixture.auras.player={{spellId=853,auraInstanceID=19,expirationTime=41,duration=20}}
    ns.Observer.Scan(21)
    fixture.auras.player={{spellId=secret,auraInstanceID=19}}
    fixture.loc={{spellID=853,startTime=21,duration=20}}
    ns.Observer.Scan(22)
    equal(ns.model:GetDR("Player-1-Self",22)[1].stage,1)
    fixture.loc={{spellID=853,startTime=25,duration=10}}
    ns.Observer.Scan(25)
    local row=ns.model:GetDR("Player-1-Self",25)[1]
    equal(row.stage,2); equal(row.started,25); equal(row.remaining,20); truth(row.uncertain)
    ns.Observer.Scan(26)
    row=ns.model:GetDR("Player-1-Self",26)[1]
    equal(row.stage,2); equal(row.started,25); equal(row.remaining,19)
    equal(size(ns.model.units["Player-1-Self"].effects),1)
    truth(ns.model.units["Player-1-Self"].effects["a:19"])
    fixture.loc={}; ns.Observer.Scan(27)
    equal(size(ns.Observer.GetUnitState("player").witnesses),0)
    ns.Observer.Scan(45)
    row=ns.model:GetDR("Player-1-Self",45)[1]
    truth(row,"stage survives the expired application timer")
    equal(row.stage,2); equal(row.remaining,0); equal(row.stageResetAt,47)
    ns.Observer.Scan(47); equal(#ns.model:GetDR("Player-1-Self",47),0)
end)

test("a simultaneous aura cannot overwrite canonical explicit LoC timing", function()
    reset(); realModel(); byUnitLoC()
    fixture.auras.target={{spellId=853,auraInstanceID=19,expirationTime=41.3,duration=20},
        {spellId=secret,auraInstanceID=20}}
    fixture.locByUnit.target={{spellID=853,startTime=21,duration=20}}
    ns.Observer.Scan(22)
    local row=ns.model:GetDR("Player-1-A",22)[1]
    equal(row.stage,1); equal(row.started,21); equal(row.remaining,19); truth(row.uncertain)
end)

test("fallback LoC rounding corrections preserve one application identity", function()
    reset(); realModel(); fixture.guid.target=nil; C_UnitAuras=nil
    fixture.loc={{spellID=118,startTime=21,duration=20}}
    ns.Observer.Scan(21)
    for _,start in ipairs({21.0001,21.0008,21.0003}) do
        fixture.loc[1].startTime=start
        ns.Observer.Scan(21.1)
        local row=ns.model:GetDR("Player-1-Self",21.1)[1]
        equal(row.stage,1,"rounding is not a second application"); equal(row.started,21)
        equal(size(ns.model.units["Player-1-Self"].effects),1)
    end
    fixture.loc[1].startTime=25; fixture.loc[1].duration=10
    ns.Observer.Scan(25)
    local row=ns.model:GetDR("Player-1-Self",25)[1]
    equal(row.stage,2); equal(row.started,25)
    ns.Observer.Scan(25.1); equal(ns.model:GetDR("Player-1-Self",25.1)[1].stage,2)
end)

test("an identical LoC application returning after an empty snapshot is not another CC", function()
    for _,instance in ipairs({false,true}) do
        reset(); realModel(); fixture.guid.target=nil; C_UnitAuras=nil
        local record={spellID=118,auraInstanceID=instance and 19 or nil,startTime=21,duration=20}
        fixture.loc={record}; ns.Observer.Scan(21)
        fixture.loc={}; ns.Observer.Scan(21.1)
        equal(ns.model:GetDR("Player-1-Self",21.1)[1].active,false)
        fixture.loc={record}; ns.Observer.Scan(21.2)
        local row=ns.model:GetDR("Player-1-Self",21.2)[1]
        equal(row.stage,1); equal(row.started,21); equal(row.remaining,19.8); truth(row.active)
        ns.Observer.Scan(21.3); equal(ns.model:GetDR("Player-1-Self",21.3)[1].stage,1)
        fixture.loc={}; ns.Observer.Scan(21.4)
        record.startTime=21.0001
        fixture.loc={record}; ns.Observer.Scan(21.5)
        row=ns.model:GetDR("Player-1-Self",21.5)[1]
        equal(row.stage,1,"an empty gap plus rounding is still the same application"); equal(row.started,21)
        fixture.loc={}; ns.Observer.Scan(22)
        fixture.loc={{spellID=118,auraInstanceID=instance and 19 or nil,startTime=25,duration=10}}
        ns.Observer.Scan(25)
        row=ns.model:GetDR("Player-1-Self",25)[1]
        equal(row.stage,2,"a later explicit application still advances"); equal(row.started,25)
    end
end)

test("distinct known aura identities are not collapsed by matching LoC timestamps", function()
    reset(); realModel(); fixture.guid.target=nil; C_UnitAuras=nil
    fixture.loc={{spellID=118,auraInstanceID=19,startTime=21,duration=20},
        {spellID=118,auraInstanceID=20,startTime=21,duration=20}}
    ns.Observer.Scan(21)
    equal(ns.model:GetDR("Player-1-Self",21)[1].stage,2)
    ns.Observer.Scan(21.1); equal(ns.model:GetDR("Player-1-Self",21.1)[1].stage,2)
end)

test("live Hibernate timing becoming admissible corrects one application across shared views", function()
    reset(); realModel(); C_UnitAuras=nil
    fixture.guid.target="Player-1-Self"; fixture.guid.focus="Player-1-Self"
    local function scan(at, instance, start, duration, stage, expectedStart)
        fixture.loc=instance and {{spellID=2637,auraInstanceID=instance,startTime=start,
            duration=duration,timeRemaining=duration}} or {}
        ns.Observer.Scan(at)
        for _,unit in ipairs({"player","target","focus"}) do
            local guid=ns.Observer.GetUnitState(unit).guid
            equal(guid,"Player-1-Self","shared player identity")
            local rows=ns.model:GetDR(guid,at)
            if stage then
                equal(#rows,1); equal(rows[1].stage,stage,"one count per landed Hibernate")
                equal(rows[1].observedStage,stage)
                equal(rows[1].started,expectedStart,"clock calibrated from the same application")
                truth(math.abs(rows[1].remaining-math.max(0,expectedStart+20-at))<0.000001)
            else
                equal(#rows,0,"stage window after observed removal expired")
            end
        end
    end
    -- Reproduce the normalized live trace with a briefly future raw timestamp.
    -- The trace does not establish why the original first start was unavailable.
    scan(2655121.649,315,2655121.750,20,1,2655121.649)
    equal(ns.model.units["Player-1-Self"].effects["a:315"].appliedAt,nil,
        "future start stays rejected at the API boundary")
    scan(2655121.778,315,2655121.750,20,1,2655121.750)
    scan(2655138.995,nil,nil,nil,1,2655121.750)
    scan(2655141.879,nil,nil,nil,1,2655121.750)
    equal(ns.model:GetDR("Player-1-Self",2655141.879)[1].stageResetAt,2655158.995)
    scan(2655159.000,nil,nil,nil,nil)
    scan(2655176.779,317,2655176.750,20,1,2655176.750)
    scan(2655186.431,nil,nil,nil,1,2655176.750)
    scan(2655186.838,319,2655187.000,10,2,2655186.838)
    scan(2655187.034,319,2655187.000,10,2,2655187.000)
    scan(2655187.234,319,2655187.000,10,2,2655187.000)
    scan(2655188.034,321,2655188.000,5,3,2655188.000)
end)

test("full half and quarter Hibernate preserve stage across expired application countdowns", function()
    reset(); realModel(); C_UnitAuras=nil
    fixture.guid.target="Player-1-Self"; fixture.guid.focus="Player-1-Self"
    for now=80,99 do ns.Observer.Scan(now) end
    local function rows(at, stage, started, resetAt)
        for _,unit in ipairs({"player","target","focus"}) do
            local guid=ns.Observer.GetUnitState(unit).guid
            equal(guid,"Player-1-Self")
            local row=ns.model:GetDR(guid,at)[1]
            truth(row,"stage must survive the separate application countdown")
            equal(row.stage,stage); equal(row.observedStage,stage)
            equal(row.started,started)
            equal(row.remaining,math.max(0,started+20-at))
            equal(row.applicationExpired,at>=started+20)
            equal(row.stageResetAt,resetAt); equal(row.stageRemaining,resetAt-at)
        end
    end
    fixture.loc={{spellID=2637,auraInstanceID=401,startTime=100,duration=20}}
    for now=100,119 do ns.Observer.Scan(now) end
    fixture.loc={}; ns.Observer.Scan(120)
    rows(120,1,100,140)
    ns.Observer.Scan(121)
    fixture.loc={{spellID=2637,auraInstanceID=402,startTime=122,duration=10}}
    ns.Observer.Scan(122); rows(122,2,122,152)
    for now=123,131 do ns.Observer.Scan(now) end
    fixture.loc={}; ns.Observer.Scan(132); ns.Observer.Scan(133)
    fixture.loc={{spellID=2637,auraInstanceID=403,startTime=134,duration=5}}
    ns.Observer.Scan(134); rows(134,3,134,159)
    for now=135,138 do ns.Observer.Scan(now) end
    fixture.loc={}
    for now=139,154 do ns.Observer.Scan(now) end
    rows(154,3,134,159)
    for now=155,158 do ns.Observer.Scan(now) end
    rows(158,3,134,159)
    ns.Observer.Scan(159)
    equal(#ns.model:GetDR("Player-1-Self",159),0,"stage expires twenty seconds after final CC end")
end)

test("early Hibernate removal sets the stage boundary without restarting its application countdown", function()
    for _,nextStart in ipairs({123,124}) do
        reset(); realModel(); C_UnitAuras=nil; fixture.guid.target=nil
        fixture.loc={{spellID=2637,auraInstanceID=410,startTime=100,duration=20}}
        for now=100,103 do ns.Observer.Scan(now) end
        fixture.loc={}; ns.Observer.Scan(104)
        local row=ns.model:GetDR("Player-1-Self",104)[1]
        equal(row.started,100); equal(row.remaining,16); equal(row.active,false)
        equal(row.stageResetAt,124,"early break overrides the original full expiry")
        for now=105,120 do ns.Observer.Scan(now) end
        row=ns.model:GetDR("Player-1-Self",120)[1]
        truth(row); equal(row.remaining,0); equal(row.stage,1); equal(row.stageRemaining,4)
        for now=121,nextStart-1 do ns.Observer.Scan(now) end
        fixture.loc={{spellID=2637,auraInstanceID=411,startTime=nextStart,duration=nextStart<124 and 10 or 20}}
        ns.Observer.Scan(nextStart)
        row=ns.model:GetDR("Player-1-Self",nextStart)[1]
        equal(row.stage,nextStart<124 and 2 or 1,"new cast uses CC end rather than old application deadline")
        equal(row.remaining,20); equal(row.started,nextStart)
    end
end)

test("partial LoC absence cannot start an early stage reset", function()
    reset(); realModel(); C_UnitAuras=nil; fixture.guid.target=nil
    fixture.loc={{spellID=2637,auraInstanceID=420,startTime=100,duration=20}}
    ns.Observer.Scan(100)
    fixture.loc={secret}
    for now=101,121 do ns.Observer.Scan(now) end
    local row=ns.model:GetDR("Player-1-Self",121)[1]
    truth(row,"restricted absence must retain known stage")
    equal(row.stage,1); equal(row.remaining,0); equal(row.stageResetAt,140)
    truth(row.uncertain)
    fixture.loc={{spellID=2637,auraInstanceID=421,startTime=122,duration=10}}
    ns.Observer.Scan(122)
    row=ns.model:GetDR("Player-1-Self",122)[1]
    equal(row.stage,2); equal(row.started,122); equal(row.remaining,20)
end)

test("unknown LoC end waits for complete removal before stage reset", function()
    reset(); realModel(); C_UnitAuras=nil; fixture.guid.target=nil
    fixture.loc={{spellID=2637,auraInstanceID=430,startTime=100}}
    ns.Observer.Scan(100)
    fixture.loc={secret}
    for now=101,125 do ns.Observer.Scan(now) end
    local row=ns.model:GetDR("Player-1-Self",125)[1]
    truth(row,"unknown end cannot become an application-based stage reset")
    equal(row.stage,1); equal(row.remaining,0); equal(row.stageResetAt,nil)
    equal(row.stageResetPending,true)
    fixture.loc={}; ns.Observer.Scan(126)
    row=ns.model:GetDR("Player-1-Self",126)[1]
    equal(row.stageResetAt,146); equal(row.stageResetPending,false); equal(row.remaining,0)
    for now=127,145 do ns.Observer.Scan(now) end
    equal(ns.model:GetDR("Player-1-Self",145)[1].stageResetAt,146,"empty polling cannot slide the deadline")
    ns.Observer.Scan(146); equal(#ns.model:GetDR("Player-1-Self",146),0)
end)

test("player and ByUnit LoC retain only guarded explicit reported durations", function()
    for _,unit in ipairs({"player","target","focus"}) do
        for _,duration in ipairs({5,10,20,120}) do
            reset(); byUnitLoC()
            fixture.guid[unit]="Player-1-Duration"
            fixture.auras[unit]={{spellId=secret,auraInstanceID=501}}
            local record={spellID=2637,auraInstanceID=501,startTime=100,duration=duration,timeRemaining=1}
            if unit=="player" then fixture.loc={record} else fixture.locByUnit[unit]={record} end
            ns.Observer.Scan(103)
            local current=effect(last("Player-1-Duration"))
            equal(current.applicationSource,"loc"); equal(current.appliedAt,100)
            equal(current.reportedDuration,duration,"raw duration is preserved rather than remaining time")
        end
    end
end)

test("missing secret nonfinite and out of range LoC durations are never reported evidence", function()
    for _,unit in ipairs({"player","target"}) do
        for _,case in ipairs({{}, {secret}, {0/0}, {math.huge}, {-math.huge}, {0}, {-1}, {121}, {"20"}}) do
            reset(); byUnitLoC(); fixture.guid[unit]="Player-1-Duration"
            fixture.auras[unit]={{spellId=secret,auraInstanceID=501}}
            local record={spellID=2637,auraInstanceID=501,startTime=100,duration=case[1],timeRemaining=7}
            if unit=="player" then fixture.loc={record} else fixture.locByUnit[unit]={record} end
            ns.Observer.Scan(103)
            local current=effect(last("Player-1-Duration"))
            equal(current.appliedAt,100); equal(current.applicationSource,"loc")
            equal(current.reportedDuration,nil,"invalid raw duration cannot become duration evidence")
        end
    end
end)

test("LoC duration waits for an admissible explicit start instead of using remaining time", function()
    for _,case in ipairs({{}, {secret}, {0/0}, {-1}, {math.huge}, {101}}) do
        reset(); C_UnitAuras=nil
        fixture.loc={{spellID=2637,auraInstanceID=501,startTime=case[1],duration=20,timeRemaining=10}}
        ns.Observer.Scan(100)
        local current=effect(last("Player-1-Self"))
        equal(current.appliedAt,nil); equal(current.applicationSource,nil)
        equal(current.reportedDuration,nil); equal(current.expires,110)
        fixture.loc[1].startTime=100.25
        ns.Observer.Scan(100.3)
        current=effect(last("Player-1-Self"))
        equal(current.appliedAt,100.25); equal(current.reportedDuration,20)
    end
end)

test("aura duration alone never becomes reported LoC evidence", function()
    reset()
    fixture.auras.target={{spellId=2637,auraInstanceID=501,expirationTime=120,duration=20}}
    ns.Observer.Scan(100)
    local current=effect(last("Player-1-A"))
    equal(current.appliedAt,100); equal(current.applicationSource,"aura")
    equal(current.reportedDuration,nil)
end)

test("exact aura merge copies current LoC duration and does not manufacture a missing one", function()
    reset(); byUnitLoC()
    fixture.auras.target={{spellId=2637,auraInstanceID=501,expirationTime=120,duration=20},
        {spellId=secret,auraInstanceID=502}}
    fixture.locByUnit.target={{spellID=2637,auraInstanceID=501,startTime=100,duration=10}}
    ns.Observer.Scan(100)
    local current=effect(last("Player-1-A"))
    equal(current.applicationSource,"loc"); equal(current.reportedDuration,10)
    fixture.locByUnit.target[1].duration=nil; fixture.locByUnit.target[1].timeRemaining=9
    ns.Observer.Scan(101)
    current=effect(last("Player-1-A"))
    equal(current.applicationSource,"loc"); equal(current.reportedDuration,nil)
end)

test("canonical LoC handoff carries current duration without stale duration on a new start", function()
    reset(); fixture.guid.target=nil
    fixture.auras.player={{spellId=2637,auraInstanceID=501,expirationTime=120,duration=20}}
    ns.Observer.Scan(100)
    fixture.auras.player={{spellId=secret,auraInstanceID=501}}
    fixture.loc={{spellID=2637,startTime=100,duration=20}}
    ns.Observer.Scan(101)
    local current=last("Player-1-Self").effects["a:501"]
    truth(current); equal(current.applicationSource,"loc"); equal(current.reportedDuration,20)
    fixture.loc={{spellID=2637,startTime=102,timeRemaining=10}}
    ns.Observer.Scan(102)
    current=last("Player-1-Self").effects["a:501"]
    truth(current); equal(current.appliedAt,102); equal(current.reportedDuration,nil)
    fixture.loc[1].duration=10
    ns.Observer.Scan(102.1)
    current=last("Player-1-Self").effects["a:501"]
    equal(current.appliedAt,102); equal(current.reportedDuration,10)
    fixture.loc[1].duration=secret
    ns.Observer.Scan(102.2)
    equal(last("Player-1-Self").effects["a:501"].reportedDuration,nil)
end)

test("a current aura handoff cannot reuse a prior LoC reported duration", function()
    reset(); byUnitLoC()
    fixture.auras.target={{spellId=secret,auraInstanceID=501}}
    fixture.locByUnit.target={{spellID=2637,startTime=100,duration=20}}
    ns.Observer.Scan(100)
    equal(effect(last("Player-1-A")).reportedDuration,20)
    fixture.auras.target={{spellId=2637,auraInstanceID=501,expirationTime=120,duration=20}}
    -- A readable aura sensor takes over while identity retains the LoC key.
    ns.Observer.Scan(101)
    equal(effect(last("Player-1-A")).reportedDuration,nil)
end)

test("exact player aura to LoC handoff preserves full duration learning and later reset correction", function()
    for _,lateStart in ipairs({false,true}) do
        reset(); realModel(); fixture.guid.target="Player-1-Self"; fixture.guid.focus="Player-1-Self"
        for now=0,20 do ns.Observer.Scan(now) end
        fixture.auras.player={{spellId=2637,auraInstanceID=700,expirationTime=41,duration=20}}
        ns.Observer.Scan(21)
        fixture.auras.player={{spellId=secret,auraInstanceID=700}}
        fixture.loc={{spellID=2637,auraInstanceID=700,startTime=lateStart and 21.25 or 21,
            duration=20,timeRemaining=20}}
        ns.Observer.Scan(21)
        if lateStart then
            equal(ns.model.units["Player-1-Self"].durationBaselines[2637],nil,
                "unknown explicit start cannot teach duration")
            ns.Observer.Scan(21.3)
        end
        local tracked=ns.model.units["Player-1-Self"]
        truth(tracked.durationBaselines[2637],"same complete identity must retain pre-CC quiet evidence")
        equal(tracked.durationBaselines[2637].duration,20)
        equal(ns.Observer.stats.handoffsPreserved,1)
        equal(ns.Observer.stats.handoffsInvalidated,0)
        fixture.loc={}; ns.Observer.Scan(22)
        fixture.loc={{spellID=2637,auraInstanceID=701,startTime=23,duration=10}}
        ns.Observer.Scan(23); equal(ns.model:GetDR("Player-1-Self",23)[1].stage,2)
        fixture.loc={}; ns.Observer.Scan(24)
        fixture.loc={{spellID=2637,auraInstanceID=702,startTime=25,duration=5}}
        ns.Observer.Scan(25); equal(ns.model:GetDR("Player-1-Self",25)[1].stage,3)
        fixture.loc={}
        for now=26,41 do ns.Observer.Scan(now) end
        fixture.loc={{spellID=2637,auraInstanceID=703,startTime=41.25,duration=20}}
        ns.Observer.Scan(41.25)
        for _,unit in ipairs({"player","target","focus"}) do
            local row=ns.model:GetDR(ns.Observer.GetUnitState(unit).guid,41.25)[1]
            equal(row.stage,1,"matching full duration corrects retained immunity")
            equal(row.started,41.25); equal(row.resetEvidence,"matching-full-duration")
        end
        fixture.loc={}; ns.Observer.Scan(42)
        fixture.loc={{spellID=2637,auraInstanceID=704,startTime=43,duration=10}}
        ns.Observer.Scan(43)
        equal(ns.model:GetDR("Player-1-Self",43)[1].stage,2,"next half-duration application advances from corrected stage")
    end
end)

test("unmatched incomplete and ambiguous handoffs cannot inherit old quiet duration evidence", function()
    local cases={"previous-empty","current-empty","new-id","missing-id","extra-id","missing-prior-id",
        "changed-spell","partial","missing-prior-time","invalid-prior-duration","oversized-prior-duration"}
    for _,case in ipairs(cases) do
        reset(); realModel(); fixture.guid.target=nil
        for now=0,20 do ns.Observer.Scan(now) end
        fixture.auras.player={{spellId=2637,auraInstanceID=700,expirationTime=41,duration=20}}
        if case=="previous-empty" then fixture.auras.player={}
        elseif case=="missing-prior-id" then
            fixture.auras.player[2]={spellId=853,auraInstanceID=701,expirationTime=41,duration=20}
        elseif case=="missing-prior-time" then fixture.auras.player[1].duration=nil
        elseif case=="invalid-prior-duration" then fixture.auras.player[1].duration=0
        elseif case=="oversized-prior-duration" then
            fixture.auras.player[1].duration=121; fixture.auras.player[1].expirationTime=142
        end
        ns.Observer.Scan(21)
        local before=ns.model.units["Player-1-Self"].durationEpoch
        fixture.auras.player={{spellId=secret,auraInstanceID=700}}
        fixture.loc={{spellID=2637,auraInstanceID=700,startTime=21,duration=20}}
        if case=="current-empty" then fixture.loc={}
        elseif case=="new-id" then fixture.loc[1].auraInstanceID=702
        elseif case=="missing-id" then fixture.loc[1].auraInstanceID=nil
        elseif case=="extra-id" then fixture.loc[2]={spellID=853,auraInstanceID=701,startTime=21,duration=20}
        elseif case=="changed-spell" then fixture.loc[1].spellID=118
        elseif case=="partial" then fixture.loc[2]=secret end
        ns.Observer.Scan(21.1)
        local tracked=ns.model.units["Player-1-Self"]
        truth(tracked.durationEpoch>before,case .. " must invalidate prior coverage")
        equal(tracked.durationBaselines[2637],nil,case .. " cannot teach full duration from stale quiet")
        equal(ns.Observer.stats.handoffsPreserved,0,case)
        equal(ns.Observer.stats.handoffsInvalidated,1,case)
    end
end)

test("an actual scan gap stays invalid even when exact aura and LoC identities match", function()
    reset(); realModel(); fixture.guid.target=nil
    for now=0,20 do ns.Observer.Scan(now) end
    fixture.auras.player={{spellId=2637,auraInstanceID=700,expirationTime=41,duration=20}}
    ns.Observer.Scan(21)
    local before=ns.model.units["Player-1-Self"].durationEpoch
    fixture.auras.player={{spellId=secret,auraInstanceID=700}}
    fixture.loc={{spellID=2637,auraInstanceID=700,startTime=21,duration=20}}
    ns.Observer.Scan(23)
    local tracked=ns.model.units["Player-1-Self"]
    truth(tracked.durationEpoch>before,"identity bridge cannot restore pre-gap coverage")
    equal(tracked.durationBaselines[2637],nil)
    equal(ns.Observer.stats.scanGaps,1)
end)

test("restricted prior aura coverage cannot become a readable player handoff proof", function()
    reset(); realModel(); fixture.guid.player=nil
    for now=0,20 do ns.Observer.Scan(now) end
    fixture.auras.target={{spellId=2637,auraInstanceID=700,expirationTime=41,duration=20},
        {spellId=secret,auraInstanceID=701}}
    ns.Observer.Scan(21)
    equal(ns.Observer.GetUnitState("target").status,"restricted")
    local before=ns.model.units["Player-1-A"].durationEpoch
    fixture.guid.player="Player-1-A"; fixture.guid.target=nil
    fixture.auras.player={{spellId=secret,auraInstanceID=700}}
    fixture.loc={{spellID=2637,auraInstanceID=700,startTime=21,duration=20}}
    ns.Observer.Scan(21.1)
    local tracked=ns.model.units["Player-1-A"]
    truth(tracked.durationEpoch>before)
    equal(tracked.durationBaselines[2637],nil)
    equal(ns.Observer.stats.handoffsPreserved,0); equal(ns.Observer.stats.handoffsInvalidated,1)
end)

test("reverse LoC to aura handoffs still invalidate learned duration evidence", function()
    reset(); realModel(); fixture.guid.target=nil; C_UnitAuras=nil
    for now=0,21 do ns.Observer.Scan(now) end
    fixture.loc={{spellID=2637,auraInstanceID=700,startTime=22,duration=20}}
    ns.Observer.Scan(22)
    truth(ns.model.units["Player-1-Self"].durationBaselines[2637])
    local before=ns.model.units["Player-1-Self"].durationEpoch
    fixture.guid.player=nil; fixture.guid.target="Player-1-Self"
    C_UnitAuras={GetAuraDataByIndex=function(unit,index)
        if unit=="target" and index==1 then
            return {spellId=2637,auraInstanceID=700,expirationTime=42,duration=20}
        end
    end}
    ns.Observer.Scan(22.1)
    local tracked=ns.model.units["Player-1-Self"]
    truth(tracked.durationEpoch>before); equal(tracked.durationBaselines[2637],nil)
    equal(ns.Observer.stats.handoffsPreserved,0)
    equal(ns.Observer.stats.handoffsInvalidated,1,"reverse switch still invalidates")
end)

test("API failures retain bounded sanitized first and latest readable messages", function()
    reset(); fixture.guid.player=nil
    local message="first\n|cffff0000denied|r"
    C_UnitAuras.GetAuraDataByIndex=function(unit,index,filter)
        equal(unit,"target"); equal(index,1); equal(filter,"HARMFUL")
        error(message,0)
    end
    ns.Observer.Scan(10)
    local failure=ns.Observer.apiFailures["C_UnitAuras.GetAuraDataByIndex"]
    truth(failure); equal(failure.count,1); equal(failure.lastUnit,"target")
    equal(failure.firstMessage,"first??cffff0000denied?r")
    equal(failure.lastMessage,failure.firstMessage)
    equal(last("Player-1-A").complete,false); equal(ns.Observer.stats.apiErrors,1)
    message="last\t" .. string.rep("x",300)
    ns.Observer.Scan(10.5)
    equal(failure.count,2); equal(#failure.lastMessage,240)
    equal(failure.lastMessage:sub(1,5),"last?")
    equal(failure.firstMessage,"first??cffff0000denied?r")
    equal(ns.Observer.stats.apiErrors,2); equal(size(ns.Observer.apiFailures),1)
end)

test("field access failures have a separate fixed operation label", function()
    reset(); fixture.guid.player=nil
    fixture.auras.target={setmetatable({}, {__index=function(_,key)
        equal(key,"spellId"); error("field denied",0)
    end})}
    ns.Observer.Scan(10)
    equal(ns.Observer.apiFailures["AuraData.spellId"].count,1)
    equal(ns.Observer.apiFailures["AuraData.spellId"].firstMessage,"field denied")
    equal(ns.Observer.apiFailures["AuraData.spellId"].lastUnit,"target")
    equal(ns.Observer.apiFailures["C_UnitAuras.GetAuraDataByIndex"],nil)
    equal(ns.Observer.stats.apiErrors,1); equal(last("Player-1-A").complete,false)
end)

test("player LoC count and record failures remain attributable and incomplete", function()
    reset(); fixture.guid.target=nil; C_UnitAuras=nil
    C_LossOfControl.GetActiveLossOfControlDataCount=function() error("count denied",0) end
    ns.Observer.Scan(10)
    local count=ns.Observer.apiFailures["C_LossOfControl.GetActiveLossOfControlDataCount"]
    equal(count.count,1); equal(count.lastUnit,"player")
    equal(last("Player-1-Self").complete,false)
    C_LossOfControl.GetActiveLossOfControlDataCount=function() return 1 end
    C_LossOfControl.GetActiveLossOfControlData=function(index)
        equal(index,1); error("record denied",0)
    end
    ns.Observer.Scan(10.5)
    equal(ns.Observer.apiFailures["C_LossOfControl.GetActiveLossOfControlData"].count,1)
    equal(last("Player-1-Self").complete,false); equal(ns.Observer.stats.apiErrors,2)
end)

test("ByUnit LoC errors preserve signatures and identify target and focus", function()
    reset(); fixture.guid.player=nil; fixture.guid.focus="Player-1-B"; C_UnitAuras=nil
    C_LossOfControl.GetActiveLossOfControlDataCountByUnit=function(unit)
        if unit=="focus" then error("focus count denied",0) end
        equal(unit,"target"); return 1
    end
    C_LossOfControl.GetActiveLossOfControlDataByUnit=function(unit,index)
        equal(unit,"target"); equal(index,1); error("target record denied",0)
    end
    ns.Observer.Scan(10)
    local count=ns.Observer.apiFailures["C_LossOfControl.GetActiveLossOfControlDataCountByUnit"]
    local data=ns.Observer.apiFailures["C_LossOfControl.GetActiveLossOfControlDataByUnit"]
    equal(count.count,1); equal(count.lastUnit,"focus")
    equal(data.count,1); equal(data.lastUnit,"target")
    equal(last("Player-1-A").complete,false); equal(last("Player-1-B").complete,false)
    equal(ns.Observer.stats.apiErrors,2)
end)

test("unreadable and non-string errors are counted without formatting", function()
    reset(); fixture.guid.player=nil
    local raw="readable first"
    C_UnitAuras.GetAuraDataByIndex=function() error(raw,0) end
    ns.Observer.Scan(10)
    local failure=ns.Observer.apiFailures["C_UnitAuras.GetAuraDataByIndex"]
    local object=setmetatable({}, {__tostring=function() error("must not format table") end})
    for index,value in ipairs({secret,object,17,false}) do
        raw=value; ns.Observer.Scan(10+index*.1)
        equal(failure.count,index+1)
        equal(failure.firstMessage,"readable first"); equal(failure.lastMessage,"readable first")
        equal(last("Player-1-A").complete,false)
    end
    ns.Observer.Init(); raw=secret; ns.Observer.Scan(11)
    failure=ns.Observer.apiFailures["C_UnitAuras.GetAuraDataByIndex"]
    equal(failure.count,1); equal(failure.firstMessage,nil); equal(failure.lastMessage,nil)
    equal(ns.Observer.stats.apiErrors,1)
end)

test("missing APIs and restricted results do not become API failure messages", function()
    reset(); fixture.guid.player=nil; C_UnitAuras=nil
    ns.Observer.Scan(10)
    equal(size(ns.Observer.apiFailures),0); equal(ns.Observer.stats.apiErrors,0)
    truth(ns.Observer.stats.missingApis>0); equal(last("Player-1-A").complete,false)
    C_UnitAuras={GetAuraDataByIndex=function() return secret end}
    ns.Observer.Scan(10.5)
    equal(size(ns.Observer.apiFailures),0); equal(ns.Observer.stats.apiErrors,0)
    truth(ns.Observer.stats.restricted>0); equal(last("Player-1-A").complete,false)
end)

test("varying cast units share a fixed label and bounded diagnostic count", function()
    reset(); UnitGUID=function() error("identity denied",0) end
    for index=1,40 do ns.Observer.OnCast("nameplate" .. index,nil,853,10) end
    equal(size(ns.Observer.apiFailures),1)
    local failure=ns.Observer.apiFailures.UnitGUID
    equal(failure.count,40); equal(failure.lastUnit,"other")
    failure.count=2147483647
    ns.Observer.OnCast("target",nil,853,10)
    equal(failure.count,2147483647); equal(failure.lastUnit,"target")
    equal(ns.Observer.stats.apiErrors,41); equal(ns.Observer.stats.acceptedCasts,0)
end)

test("Init clears API failure counts and saved error text", function()
    reset(); fixture.auraError=true; ns.Observer.Scan(10)
    truth(next(ns.Observer.apiFailures)); truth(ns.Observer.stats.apiErrors>0)
    ns.Observer.Init()
    equal(size(ns.Observer.apiFailures),0); equal(ns.Observer.stats.apiErrors,0)
    fixture.auraError=false; ns.Observer.Scan(10.5)
    equal(size(ns.Observer.apiFailures),0)
end)

test("confirmed War Stomp advances Bash DR through aura and ByUnit observations", function()
    local fixtureData=ns.Data
    assert(loadfile(addonDir .. "/Data.lua"))("bjarkiCC",ns)
    for _,sensor in ipairs({"aura","loc"}) do
        reset(); realModel(); fixture.guid.player=nil; fixture.guid.focus="Player-1-A"
        if sensor=="loc" then byUnitLoC(); C_UnitAuras=nil end
        local function observeSpell(spellID,instanceID,start,duration)
            if sensor=="aura" then
                fixture.auras.target={{spellId=spellID,auraInstanceID=instanceID,
                    expirationTime=start+duration,duration=duration}}
            else
                fixture.locByUnit.target={{spellID=spellID,auraInstanceID=instanceID,
                    startTime=start,duration=duration}}
            end
        end
        observeSpell(5211,801,10,3); ns.Observer.Scan(10)
        local row=ns.model:GetDR("Player-1-A",10)[1]
        equal(row.category,"stun"); equal(row.stage,1); equal(row.started,10)
        fixture.auras.target={}
        if sensor=="loc" then fixture.locByUnit.target={} end
        ns.Observer.Scan(11)
        ns.Observer.OnCast("target","Cast-WarStomp",20549,12)
        row=ns.model:GetDR("Player-1-A",12)[1]
        equal(ns.Observer.stats.acceptedCasts,1,"readable enemy cast can record its cooldown")
        equal(row.stage,1,"cast event alone cannot count a landed stun")
        equal(row.started,10); equal(row.remaining,18,"cast cannot refresh Bash DR")
        observeSpell(20549,802,12,1); ns.Observer.Scan(12)
        row=ns.model:GetDR("Player-1-A",12)[1]
        equal(row.stage,2,"a readable War Stomp hit must advance the stun category")
        equal(row.started,12); equal(row.remaining,20); equal(row.estimated,false)
        equal(ns.Observer.GetUnitState("target").guid,ns.Observer.GetUnitState("focus").guid)
        ns.Observer.Scan(12.1)
        equal(ns.model:GetDR("Player-1-A",12.1)[1].stage,2,"aliases and stable polls cannot count twice")
    end
    ns.Data=fixtureData
end)

test("non-secret exact War Stomp aura confirms a hit when enumeration is blocked", function()
    local fixtureData=ns.Data
    assert(loadfile(addonDir .. "/Data.lua"))("bjarkiCC",ns)
    reset(); realModel(); byUnitLoC(); fixture.guid.player=nil; fixture.guid.focus="Player-1-A"
    fixture.auras.target={{spellId=5211,auraInstanceID=899,expirationTime=11,duration=3}}
    ns.Observer.Scan(8)
    fixture.auras.target={}; ns.Observer.Scan(9)
    fixture.auraError=true
    local current={spellId=20549,auraInstanceID=900,startTime=10,expirationTime=12,duration=2}
    local calls=0
    C_UnitAuras.GetUnitAuraBySpellID=function(unit,id)
        equal(unit,"target"); equal(id,20549); calls=calls+1; return current
    end
    ns.Observer.Scan(10)
    local row=ns.model:GetDR("Player-1-A",10)[1]
    truth(row,"an exact readable positive must reach the real model")
    equal(row.category,"stun"); equal(row.observedStage,2); equal(row.started,10)
    equal(ns.Observer.GetUnitState("target").stompLookup,"confirmed")
    equal(ns.Observer.GetUnitState("target").auraComplete,false,"one hit cannot prove full aura coverage")
    equal(ns.Observer.GetUnitState("target").byUnitCount,0)
    ns.Observer.Scan(10.2); equal(ns.model:GetDR("Player-1-A",10.2)[1].stage,2)
    equal(calls,2,"shared target/focus identity queries only once per scan")
    fixture.locByUnit.target={{spellID=20549,auraInstanceID=900,startTime=10,duration=2}}
    ns.Observer.Scan(10.3)
    equal(ns.model:GetDR("Player-1-A",10.3)[1].stage,2,"matching LoC cannot count the exact aura twice")
    fixture.locByUnit.target={}
    current=nil; ns.Observer.Scan(11)
    equal(ns.Observer.GetUnitState("target").stompLookup,"none")
    row=ns.model:GetDR("Player-1-A",11)[1]
    equal(row.stage,2); equal(row.started,10)
    truth(row.stageResetSource~="observed-end","nil exact lookup is not proof of removal")
    ns.Data=fixtureData
end)

test("exact War Stomp lookup rejects hidden mismatched expired and failed records", function()
    local fixtureData=ns.Data
    assert(loadfile(addonDir .. "/Data.lua"))("bjarkiCC",ns)
    local cases={
        {value=nil,status="none"}, {value=secret,status="blocked"},
        {value={spellId=secret,auraInstanceID=901},status="identity-unavailable"},
        {value={spellId=20549,auraInstanceID=secret},status="identity-unavailable"},
        {value={spellId=5211,auraInstanceID=901},status="mismatch"},
        {value={spellId=20549,auraInstanceID=901,expirationTime=9},status="expired"},
        {fail=true,status="blocked"},
    }
    for _,case in ipairs(cases) do
        reset(); realModel(); fixture.guid.player=nil; fixture.auraError=true
        C_UnitAuras.GetUnitAuraBySpellID=function()
            if case.fail then error("exact lookup denied",0) end
            return case.value
        end
        ns.Observer.Scan(10)
        equal(#ns.model:GetDR("Player-1-A",10),0,"no hit without a readable matching instance")
        equal(ns.Observer.GetUnitState("target").stompLookup,case.status)
        if case.fail then equal(ns.Observer.apiFailures["C_UnitAuras.GetUnitAuraBySpellID"].count,1) end
    end
    ns.Data=fixtureData
end)

test("complete aura enumeration does not add an exact War Stomp query", function()
    reset(); local calls=0
    C_UnitAuras.GetUnitAuraBySpellID=function() calls=calls+1; error("must not query") end
    ns.Observer.Scan(10)
    equal(calls,0); equal(ns.Observer.GetUnitState("target").stompLookup,nil)
end)

local failures={}
for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2])
    if not ok then failures[#failures+1]=entry[1] .. ": " .. tostring(err) end
end
assert(#failures==0,table.concat(failures,"\n"))
print("observer: " .. #tests .. " tests passed")
