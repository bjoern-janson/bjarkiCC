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
    auraCategory = {[118] = "incapacitate", [853] = "stun", [8056] = "frostshock"},
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
    ns.model=ns.Model.New(20)
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
    ns.model=ns.Model.New(20)
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
    ns.model=ns.Model.New(20)
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
        ns.Observer.Scan(41); equal(#ns.model:GetDR("Player-1-Self",41),0)
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
    ns.Observer.Scan(45); equal(#ns.model:GetDR("Player-1-Self",45),0)
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

local failures={}
for _,entry in ipairs(tests) do
    local ok,err=pcall(entry[2])
    if not ok then failures[#failures+1]=entry[1] .. ": " .. tostring(err) end
end
assert(#failures==0,table.concat(failures,"\n"))
print("observer: " .. #tests .. " tests passed")
