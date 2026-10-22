-- Candidate review: recovery, repeated timing, provenance, and removal.
local T = dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local G, results = 'Player-Enemy', {}
local function n(value) if value == nil then return '<nil>' end; return value end
local function fresh()
    local e, ns = T.fresh()
    local inputs = {}
    local observe = ns.model.Observe
    function ns.model:Observe(guid, effects, now, complete, removedKeys)
        local rows={}
        for key,effect in pairs(effects or {}) do
            rows[key]={expires=n(effect.expires),expirySource=n(effect.expirySource),
                expiryAppliedAt=n(effect.expiryAppliedAt),appliedAt=n(effect.appliedAt),
                applicationSource=n(effect.applicationSource),playerLoC=n(effect.playerLoC)}
        end
        inputs[guid] = {at=now,complete=complete,removed=removedKeys and removedKeys['a:1'] or false,effects=rows}
        return observe(self,guid,effects,now,complete,removedKeys)
    end
    return e, ns, inputs
end
local function record(name,ns,inputs,guid,at,expected)
    local unit=assert(ns.model.units[guid]);local state=assert(unit.categories.stun)
    local effect=unit.effects[state.applicationKey];local dr=ns.model:GetDR(guid,at,false)[1]
    local incoming=inputs[guid] and inputs[guid].effects[state.applicationKey]
    local actual={stage=state.stage,start=n(effect and effect.appliedAt),
        expires=n(effect and effect.expires),expirySource=n(effect and effect.expirySource),
        expiryAppliedAt=n(effect and effect.expiryAppliedAt),endedAt=n(effect and effect.endedAt),
        present=effect~=nil,active=dr and dr.active or false,activeCount=state.activeCount,
        stageResetPending=state.stageResetPending,stageResetAt=n(state.stageResetAt),
        lastEndedAt=n(state.lastEndedAt),stageEndAt=n(state.stageEndAt),
        witnessEndedAt=n(state.witness and state.witness.endedAt),
        inputExpires=n(incoming and incoming.expires),inputExpirySource=n(incoming and incoming.expirySource),
        inputExpiryAppliedAt=n(incoming and incoming.expiryAppliedAt),
        scanGaps=ns.Observer.stats.scanGaps}
    local checks={}
    for field,value in pairs(expected) do
        checks[#checks+1]={field=field,expected=value,actual=n(actual[field]),passed=actual[field]==value}
    end
    results[#results+1]={name=name,actual=actual,input=inputs[guid],checks=checks}
end
local function unknown(stage,start)
    return {stage=stage or 2,start=start or 10.4,expires='<nil>',expirySource='<nil>',
        expiryAppliedAt='<nil>',present=true,active=true,activeCount=1,
        stageResetPending=true,stageResetAt='<nil>',endedAt='<nil>',scanGaps=0}
end
local function known(ending,stage,start,source,boundary)
    return {stage=stage or 2,start=start or 10.4,expires=ending,expirySource=source or 'loc',
        expiryAppliedAt=boundary or start or 10.4,present=true,active=true,activeCount=1,
        stageResetPending=false,stageResetAt=ending+18,endedAt='<nil>',scanGaps=0}
end
local function removed(at)
    return {stage=2,present=false,active=false,activeCount=0,stageResetPending=false,
        stageResetAt=at+18,lastEndedAt=at,witnessEndedAt=at,scanGaps=0}
end
local function direct()
    local e,ns,inputs=fresh()
    local function put(start,ending,now,source)
        ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,
            appliedAt=start,expires=ending,applicationSource=source or 'loc'}},now,true)
    end
    return e,ns,inputs,put
end
do
    local _,ns,inputs,put=direct()
    put(10,13,10.1);put(10.4,nil,10.5)
    for _,at in ipairs({10.7,10.9,11.1}) do put(10.4,nil,at) end
    record('direct/repeated-missing-ends',ns,inputs,G,11.1,unknown())
    put(10,13,11.3)
    record('direct/stale-predecessor-end-after-refresh',ns,inputs,G,11.3,unknown())
    put(10.4,14,11.5)
    record('direct/later-current-end-recovers',ns,inputs,G,11.5,known(14))
    put(10.4,nil,11.7)
    record('direct/missing-after-recovery-retains-current-end',ns,inputs,G,11.7,known(14))
end
for _,throughUnknown in ipairs({false,true}) do
    local _,ns,inputs,put=direct()
    put(10,13,10.1)
    if throughUnknown then put(10.4,nil,10.5) end
    put(10.4,13,10.7)
    record('direct/new-end-equals-old-value/through-unknown-'..tostring(throughUnknown),
        ns,inputs,G,10.7,known(13))
end
do
    local _,ns,inputs,put=direct()
    put(10,13,10.1,'aura');put(10.4,nil,10.5)
    record('direct/first-aura-loc-calibration-retains-end-and-provenance',
        ns,inputs,G,10.5,known(13,1,10.4,'aura',10))
    put(10.4,nil,10.7)
    record('direct/repeated-calibration-retains-end-and-provenance',
        ns,inputs,G,10.7,known(13,1,10.4,'aura',10))
    put(10.8,nil,10.9)
    record('direct/next-explicit-refresh-clears-calibrated-old-end',
        ns,inputs,G,10.9,unknown(2,10.8))
end
for _,complete in ipairs({false,true}) do
    local _,ns,inputs,put=direct()
    put(10,13,10.1);put(10.4,nil,10.5)
    ns.model:Observe(G,{},10.7,false)
    record('direct/partial-absence-before-removal/complete-'..tostring(complete),
        ns,inputs,G,10.7,unknown())
    ns.model:Observe(G,{},11,complete,not complete and {['a:1']=true} or nil)
    record('direct/authorized-removal/complete-'..tostring(complete),
        ns,inputs,G,11,removed(11))
    ns.model:Observe(G,{},11.2,true)
    record('direct/repeated-absence-keeps-observed-end/complete-'..tostring(complete),
        ns,inputs,G,11.2,removed(11))
end
local function observer(token,options)
    options=options or {}
    local e,ns,inputs=fresh()
    local guid=token=='player' and 'Player-Self' or G
    e.identity[token]=guid;e.auras[token]={secretAt=1}
    local function loc(start,ending)
        local rows=start and {T.loc(5211,1,start,ending and ending-start or nil)} or {}
        if token=='player' then e.loc=rows else e.byloc[token]=rows end
    end
    if options.aura then e.auras[token]={T.aura(5211,1,10,3)}
    else loc(10,13) end
    ns.Observer.Scan(10.1)
    e.auras[token]={secretAt=1}
    loc(10.4,options.newEnd)
    ns.Observer.Scan(10.5)
    return e,ns,inputs,guid,loc
end
for _,token in ipairs({'target','focus','player'}) do
    do
        local e,ns,inputs,guid,loc=observer(token)
        ns.Observer.Scan(10.7);ns.Observer.Scan(10.9)
        record('observer/'..token..'/repeated-missing-ends',ns,inputs,guid,10.9,unknown())
        loc(10,13);ns.Observer.Scan(11.1)
        record('observer/'..token..'/stale-predecessor-end-after-refresh',ns,inputs,guid,11.1,unknown())
        loc(10.4,14);ns.Observer.Scan(11.3)
        record('observer/'..token..'/later-current-end-recovers',ns,inputs,guid,11.3,known(14))
        loc(10.4,nil);ns.Observer.Scan(11.5)
        record('observer/'..token..'/missing-after-recovery-retains-end',ns,inputs,guid,11.5,known(14))
    end
    do
        local _,ns,inputs,guid=observer(token,{newEnd=13})
        record('observer/'..token..'/new-end-equals-predecessor-value',ns,inputs,guid,10.5,known(13))
    end
    do
        local _,ns,inputs,guid=observer(token,{aura=true})
        record('observer/'..token..'/first-aura-loc-calibration-retains-end',
            ns,inputs,guid,10.5,known(13,1,10.4,'aura',10))
    end
    do
        local e,ns,inputs,guid,loc=observer(token)
        if token=='player' then e.loc={secret=true};e.byloc.player={secret=true}
        else loc(nil) end
        ns.Observer.Scan(10.7)
        record('observer/'..token..'/partial-absence-retains-positive',ns,inputs,guid,10.7,unknown())
        if token=='player' then e.loc={};e.byloc.player={}
        else e.auras[token]={} end
        ns.Observer.Scan(11)
        record('observer/'..token..'/authorized-removal',ns,inputs,guid,11,removed(11))
    end
end
do
    local e,ns,inputs=fresh();e.auras.player={secretAt=1}
    e.loc={T.loc(5211,1,10,3)};ns.Observer.Scan(10.1)
    e.byloc.player={T.loc(5211,1,10.4,nil)};ns.Observer.Scan(10.5)
    e.loc={};e.byloc.player={};ns.Observer.Scan(10.7)
    record('observer/old-ordinary-absence-cannot-remove-byunit-refresh',
        ns,inputs,'Player-Self',10.7,unknown())
    e.auras.player={};ns.Observer.Scan(11)
    record('observer/complete-absence-removes-byunit-refresh',
        ns,inputs,'Player-Self',11,removed(11))
end
do
    local e,ns,inputs=fresh();e.identity.target=G;e.auras.target={secretAt=1}
    e.byloc.target={T.loc(5211,1,10,3)};ns.Observer.Scan(10.1)
    e.byloc.target={T.loc(5211,nil,10.4,nil)};ns.Observer.Scan(10.5)
    ns.Observer.Scan(10.7)
    record('observer/canonical-fallback-repeated-missing-end',ns,inputs,G,10.7,unknown())
    e.byloc.target={T.loc(5211,nil,10.4,3.6)};ns.Observer.Scan(10.9)
    record('observer/canonical-fallback-later-current-end-recovers',ns,inputs,G,10.9,known(14))
    e.byloc.target={T.loc(5211,1,10.4,nil)};ns.Observer.Scan(11.1)
    record('observer/canonical-native-reacquisition-retains-recovered-end',ns,inputs,G,11.1,known(14))
end
-- Pin the latest add() enrichment branch: current optional timing is useful
-- for calibration, but it must not cross an explicit occurrence boundary.
local function donor(expected,ending,source,start)
    expected.inputExpires=n(ending);expected.inputExpirySource=n(source)
    expected.inputExpiryAppliedAt=n(start);return expected
end
for _,haveHistory in ipairs({false,true}) do
    for _,newNative in ipairs({false,true}) do
        local e,ns,inputs=fresh();e.auras.player={secretAt=1}
        e.loc={T.loc(5211,1,10,3)}
        if haveHistory then ns.Observer.Scan(10.1) end
        local row=T.loc(5211,nil,10.4,nil)
        if newNative then row.auraInstanceID=1 end
        e.byloc.player={row};ns.Observer.Scan(10.5)
        record('observer/current-end-donation/old-loc/history-'..tostring(haveHistory)..'/native-'..tostring(newNative),
            ns,inputs,'Player-Self',10.5,donor(unknown(haveHistory and 2 or 1),nil,nil,nil))
    end
end
for _,boundAura in ipairs({false,true}) do
    local e,ns,inputs=fresh();e.identity.target=G;e.auras.target={secretAt=1}
    e.byloc.target={T.loc(5211,1,10,3)};ns.Observer.Scan(10.1)
    local aura=T.aura(5211,1,10,3)
    if not boundAura then aura.duration=nil end
    e.auras.target={aura,secretAt=2}
    e.byloc.target={T.loc(5211,nil,10.4,nil)};ns.Observer.Scan(10.5)
    record('observer/current-end-donation/aura-to-fallback/bound-'..tostring(boundAura),
        ns,inputs,G,10.5,donor(unknown(),13,'aura',boundAura and 10 or nil))
end
do
    local e,ns,inputs=fresh();e.identity.target=G
    e.auras.target={T.aura(5211,1,10,3),secretAt=2}
    e.byloc.target={T.loc(5211,nil,10.4,nil)};ns.Observer.Scan(10.5)
    record('observer/current-end-donation/first-clock-calibration-preserves-aura-end',
        ns,inputs,G,10.5,donor(known(13,1,10.4,'aura',10),13,'aura',10))
end
do
    local e,ns,inputs=fresh();e.identity.target=G;e.auras.target={secretAt=1}
    e.byloc.target={T.loc(5211,nil,10,3)};ns.Observer.Scan(10.1)
    e.auras.target={T.aura(5211,1,10,3),secretAt=2}
    e.byloc.target={T.loc(5211,nil,10.4,nil)};ns.Observer.Scan(10.5)
    record('observer/current-end-donation/canonical-start-only-refresh-clears-old-end',
        ns,inputs,G,10.5,donor(unknown(),nil,nil,nil))
end
return results
