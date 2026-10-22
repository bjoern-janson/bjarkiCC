-- Read-only T2 verification against production Lua; no runtime source patching.
local T = dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local G, results = 'Player-Enemy', {}
local function n(value) if value == nil then return '<nil>' end; return value end
local function fresh()
    local e, ns = T.fresh()
    local inputs = {}
    local observe = ns.model.Observe
    function ns.model:Observe(guid, effects, now, complete, removedKeys)
        local rows = {}
        for key, effect in pairs(effects or {}) do
            rows[key] = {start=n(effect.appliedAt), expires=n(effect.expires),
                source=n(effect.applicationSource), playerLoC=n(effect.playerLoC),
                nativeKey=n(effect.nativeKey), nativeLoCStart=n(effect.nativeLoCStart)}
        end
        inputs[guid] = {at=now, complete=complete, effects=rows}
        return observe(self, guid, effects, now, complete, removedKeys)
    end
    return e, ns, inputs
end
local function record(name, ns, inputs, guid, key, at, expected, kind)
    local unit = assert(ns.model.units[guid], name..' actor missing')
    local state = assert(unit.categories.stun, name..' state missing')
    local effect = unit.effects[key]
    local rows = ns.model:GetDR(guid, at, false)
    local actual = {stage=state.stage, start=n(effect and effect.appliedAt),
        expires=n(effect and effect.expires), endedAt=n(effect and effect.endedAt),
        stageEndAt=n(state.stageEndAt), stageResetAt=n(state.stageResetAt),
        stageResetPending=state.stageResetPending, lastEndedAt=n(state.lastEndedAt),
        activeCount=state.activeCount, active=rows[1] and rows[1].active or false,
        key=state.applicationKey, scanGaps=ns.Observer.stats.scanGaps}
    local checks = {}
    for field, value in pairs(expected) do
        checks[#checks+1] = {field=field, expected=value, actual=n(actual[field]),
            passed=actual[field]==value}
    end
    results[#results+1] = {name=name,kind=kind or 'regression',actual=actual,
        input=inputs[guid],checks=checks}
end
local function expectUnknown(stage, start)
    return {stage=stage,start=start,expires='<nil>',stageResetAt='<nil>',
        stageResetPending=true,active=true,activeCount=1}
end
local function direct(name, firstStart, firstEnd, secondStart, secondEnd, expected, options)
    options = options or {}
    local _, ns, inputs = fresh()
    local function put(start, ending, now, source, key, spell)
        ns.model:Observe(G,{[key or 'a:1']={category='stun',spellID=spell or 5211,
            appliedAt=start,expires=ending,applicationSource=source or 'loc'}},now,
            options.complete~=false)
    end
    put(firstStart, firstEnd, 10.1, options.firstSource)
    if options.close then ns.model:Observe(G,{},10.2,true) end
    put(secondStart, secondEnd, 10.5, options.secondSource, options.secondKey, options.secondSpell)
    record(name,ns,inputs,G,options.secondKey or 'a:1',10.5,expected,options.kind)
end
for _, ending in ipairs({10.3,13,30}) do
    direct('direct/refresh-missing-end/old-'..ending,10,ending,10.4,nil,expectUnknown(2,10.4))
end
direct('direct/refresh-missing-end/partial',10,10.3,10.4,nil,expectUnknown(2,10.4),{complete=false})
direct('direct/refresh-from-retained-closed-witness',10,13,10.4,nil,expectUnknown(2,10.4),{close=true})
direct('direct/same-start-missing-end',10,13,10,nil,
    {stage=1,start=10,expires=13,stageResetAt=31,stageResetPending=false,active=true}, {kind='control'})
direct('direct/stale-start-missing-end',10,13,9,nil,
    {stage=1,start=10,expires=13,stageResetAt=31,stageResetPending=false,active=true}, {kind='control'})
direct('direct/sub-epsilon-start-missing-end',10,13,10.0005,nil,
    {stage=1,start=10,expires=13,stageResetAt=31,stageResetPending=false,active=true}, {kind='control'})
direct('direct/first-explicit-loc-calibrates-aura',10,13,10.4,nil,
    {stage=1,start=10.4,expires=13,stageResetAt=31,stageResetPending=false,active=true},
    {kind='control',firstSource='aura'})
direct('direct/first-readable-start-calibrates-untimed',nil,13,10.4,nil,
    {stage=1,start=10.4,expires=13,stageResetAt=31,stageResetPending=false,active=true}, {kind='control'})
direct('direct/new-native-id-missing-end',10,13,10.4,nil,expectUnknown(2,10.4),
    {kind='control',secondKey='a:2'})
direct('direct/changed-spell-same-key-missing-end',10,13,10.4,nil,expectUnknown(2,10.4),
    {kind='control',secondSpell=408})
direct('direct/refresh-new-end',10,13,10.4,11,
    {stage=2,start=10.4,expires=11,stageResetAt=29,stageResetPending=false,active=true}, {kind='control'})
direct('direct/refresh-old-and-new-unknown',10,nil,10.4,nil,expectUnknown(2,10.4), {kind='control'})
direct('direct/aura-change-cannot-prove-refresh-without-end',10,13,10.4,nil,
    {stage=1,expires=13,stageResetAt=31,stageResetPending=false},
    {kind='control',firstSource='aura',secondSource='aura'})

-- An expired predecessor and a future predecessor are both invalid donors.
for _, token in ipairs({'target','focus','player'}) do
    for _, ending in ipairs({10.3,13}) do
        local e, ns, inputs = fresh()
        local guid = token=='player' and 'Player-Self' or G
        e.identity[token]=guid; e.auras[token]={secretAt=1}
        local function loc(rows)
            if token=='player' then e.loc=rows else e.byloc[token]=rows end
        end
        loc({T.loc(5211,1,10,ending-10)})
        ns.Observer.Scan(10.1)
        loc({T.loc(5211,1,10.4,nil)})
        ns.Observer.Scan(10.5)
        record('observer/'..token..'/refresh-missing-end/old-'..ending,
            ns,inputs,guid,'a:1',10.5,expectUnknown(2,10.4))
    end
end

for _, firstScanOnly in ipairs({false,true}) do
    local e, ns, inputs = fresh()
    e.auras.player={secretAt=1};e.loc={T.loc(5211,1,10,3)}
    if not firstScanOnly then ns.Observer.Scan(10.1) end
    e.byloc.player={T.loc(5211,1,10.4,nil)}
    ns.Observer.Scan(10.5)
    record('observer/same-scan-exact-loc-merge/first-only-'..tostring(firstScanOnly),
        ns,inputs,'Player-Self','a:1',10.5,expectUnknown(firstScanOnly and 1 or 2,10.4))
end
do
    local e, ns, inputs = fresh()
    e.auras.player={secretAt=1};e.loc={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    e.loc={T.loc(5211,1,10.4,nil)};e.byloc.player={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.5)
    record('observer/same-scan-exact-loc-merge/reverse-source-order',
        ns,inputs,'Player-Self','a:1',10.5,expectUnknown(2,10.4))
end
for _, token in ipairs({'target','focus','player'}) do
    local e, ns, inputs = fresh()
    local guid = token=='player' and 'Player-Self' or G
    e.identity[token]=guid;e.auras[token]={secretAt=1}
    local function loc(rows)
        if token=='player' then e.loc=rows else e.byloc[token]=rows end
    end
    loc({T.loc(5211,1,10,3)})
    ns.Observer.Scan(10.1)
    e.auras[token]={T.aura(5211,1,10,3),secretAt=2}
    loc({T.loc(5211,1,10.4,nil)})
    ns.Observer.Scan(10.5)
    record('observer/'..token..'/same-scan-predecessor-aura-merge',
        ns,inputs,guid,'a:1',10.5,expectUnknown(2,10.4))
end
for _, fallbackCurrent in ipairs({false,true}) do
    local e, ns, inputs = fresh()
    e.identity.target=G;e.auras.target={secretAt=1}
    e.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    if fallbackCurrent then e.auras.target={T.aura(5211,1,10,3),secretAt=2} end
    e.byloc.target={T.loc(5211,nil,10.4,nil)}
    ns.Observer.Scan(10.5)
    record('observer/canonical-fallback-refresh/current-native-'..tostring(fallbackCurrent),
        ns,inputs,G,'a:1',10.5,expectUnknown(2,10.4))
end
do
    local e, ns, inputs = fresh()
    e.auras.player={secretAt=1}
    e.loc={T.loc(5211,1,10,3)}
    e.byloc.player={T.loc(5211,nil,10.4,nil)}
    ns.Observer.Scan(10.5)
    record('observer/same-scan-native-and-newer-fallback-first-scan',
        ns,inputs,'Player-Self','a:1',10.5,expectUnknown(1,10.4))
end
do
    local e, ns, inputs = fresh()
    e.identity.target=G;e.auras.target={secretAt=1}
    e.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    e.byloc.target={T.loc(5211,nil,10,nil)}
    ns.Observer.Scan(10.5)
    record('observer/same-occurrence-fallback-can-retain-end',
        ns,inputs,G,'a:1',10.5,{stage=1,start=10,expires=13,stageResetAt=31,
            stageResetPending=false,active=true},'control')
end

-- Adjacent negative test: after a new unknown-ended occurrence is accepted,
-- stale timing must not populate that occurrence merely because its end is nil.
do
    local _, ns, inputs = fresh()
    local function put(start,ending,now)
        ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,
            appliedAt=start,expires=ending,applicationSource='loc'}},now,true)
    end
    put(10,nil,10.1);put(10.4,nil,10.5);put(10,13,10.7)
    record('direct/stale-predecessor-end-cannot-fill-current-unknown',
        ns,inputs,G,'a:1',10.7,expectUnknown(2,10.4),'adjacent-negative')
end
return results
