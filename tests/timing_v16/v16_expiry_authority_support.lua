-- Independent endpoint provenance probes. Loads the unmodified published modules
-- through the supplied public-API stubs; no production source substitution.
local T = dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local cases = {}
local function snapshot(name, ns, guid, key, raw)
    local actor = assert(ns.model.units[guid])
    local state = assert(actor.categories.stun)
    local effect = assert(actor.effects[key])
    cases[#cases + 1] = {
        name=name, stage=state.stage, appliedAt=effect.appliedAt,
        expires=effect.expires, reset=state.stageResetAt,
        pending=state.stageResetPending, applicationSource=effect.applicationSource,
        expirySource=effect.expirySource, rawExpires=raw and raw.expires,
        rawStart=raw and raw.appliedAt, rawSource=raw and raw.applicationSource,
        rawDuration=raw and raw.reportedDuration,
        rawExpirySource=raw and raw.expirySource,
    }
end
local function observing()
    local env, ns = T.fresh()
    local original, captured = ns.model.Observe, nil
    ns.model.Observe = function(self, guid, effects, now, complete, removed)
        local _, current = next(effects)
        if current then
            captured = {}
            for k,v in pairs(current) do captured[k]=v end
        end
        return original(self, guid, effects, now, complete, removed)
    end
    return env, ns, function() return captured end
end
local G='Player-Enemy'
for _, endAt in ipairs({11,20}) do
    local env, ns, raw = observing()
    env.identity.target=G;env.auras.target={secretAt=1}
    env.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    env.auras.target={T.aura(5211,1,10,endAt-10),secretAt=2}
    env.byloc.target={T.loc(5211,1,10,nil)}
    ns.Observer.Scan(10.3)
    snapshot('mixed-end-'..endAt,ns,G,'a:1',raw())
end
do
    local env, ns, raw = observing()
    env.identity.target=G;env.auras.target={secretAt=1}
    env.byloc.target={T.loc(5211,1,10,nil)}
    ns.Observer.Scan(10.1)
    env.auras.target={T.aura(5211,1,10,10),secretAt=2}
    ns.Observer.Scan(10.3)
    snapshot('initially-unknown-end-can-use-aura-end',ns,G,'a:1',raw())
    env.auras.target={secretAt=1}
    ns.Observer.Scan(10.5)
    snapshot('later-missing-end-retains-same-occurrence-end',ns,G,'a:1',raw())
    env.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.7)
    snapshot('actual-loc-end-can-replace-initial-weak-end',ns,G,'a:1',raw())
end
do
    local env, ns, raw = observing()
    env.identity.target=G;env.auras.target={secretAt=1}
    env.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    local incoming=T.loc(5211,1,10,nil);incoming.timeRemaining=5.7
    env.byloc.target={incoming}
    ns.Observer.Scan(10.3)
    snapshot('same-start-remaining-time-end-is-not-raw-duration',ns,G,'a:1',raw())
    incoming=T.loc(5211,1,9,nil);incoming.timeRemaining=20
    env.byloc.target={incoming}
    ns.Observer.Scan(10.5)
    snapshot('stale-explicit-start-cannot-donate-remaining-end',ns,G,'a:1',raw())
end
do
    local env, ns, raw = observing()
    env.auras.player={secretAt=1}
    env.loc={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    local native=T.loc(5211,1,nil,nil);native.timeRemaining=9.7
    env.loc={native}
    env.byloc.player={T.loc(5211,1,10,nil)}
    ns.Observer.Scan(10.3)
    snapshot('unbound-native-loc-end-must-not-borrow-parallel-loc-start',ns,'Player-Self','a:1',raw())
end
do
    local _,ns=T.fresh()
    local function put(start,ending,now,source,expirySource)
        ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,
            appliedAt=start,expires=ending,applicationSource=source,
            expirySource=expirySource}},now,false)
    end
    put(10,13,10.1,'loc')
    put(10,16,10.3,'loc')
    snapshot('legacy-direct-loc-end-without-provenance-or-duration',ns,G,'a:1')
    put(10,20,10.5,'loc','aura')
    snapshot('explicitly-weak-direct-mixed-end-must-not-be-upgraded',ns,G,'a:1')
end
for _, source in ipairs({'loc','aura'}) do
    local _,ns=T.fresh()
    ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,
        appliedAt=12,applicationSource='loc'}},12.1,false)
    ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,
        appliedAt=10,expires=20,applicationSource=source}},12.3,false)
    snapshot('older-'..source..'-endpoint-must-not-fill-newer-unknown-end',ns,G,'a:1')
end
do
    local env, ns, raw=observing()
    env.identity.target=G;env.auras.target={secretAt=1}
    env.byloc.target={T.loc(5211,nil,10,3)}
    ns.Observer.Scan(10.1)
    env.byloc.target={T.loc(5211,1,12,nil)}
    ns.Observer.Scan(12.1)
    local key=ns.model.units[G].categories.stun.applicationKey
    snapshot('new-native-refresh-must-not-borrow-old-fallback-end',ns,G,key,raw())
end
return cases
