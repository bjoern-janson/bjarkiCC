-- Additional independent public-boundary checks for the v16 endpoint patch.
local T=dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local rows={}
local NIL='<nil>'
local G='Player-Enemy'
local function v(x) if x==nil then return NIL end return x end
local function fresh()
    local env,ns=T.fresh()
    local original=ns.model.Observe
    ns.model.Observe=function(self,guid,effects,now,complete,removed)
        local _,effect=next(effects)
        if effect then
            env.raw={}
            for k,x in pairs(effect) do env.raw[k]=x end
        end
        return original(self,guid,effects,now,complete,removed)
    end
    return env,ns
end
local function save(name,env,ns,guid,category,expected)
    local actor=assert(ns.model.units[guid])
    local state=assert(actor.categories[category or 'stun'])
    local effect=assert(actor.effects[state.applicationKey])
    local raw=env.raw or {}
    local dr=ns.model:GetDR(guid,actor.seen,false)
    rows[#rows+1]={name=name,expected=expected,stage=v(state.stage),start=v(effect.appliedAt),
        expires=v(effect.expires),source=v(effect.expirySource),bound=v(effect.expiryAppliedAt),
        pending=v(state.stageResetPending),reset=v(state.stageResetAt),
        rawSource=v(raw.expirySource),rawBound=v(raw.expiryAppliedAt),
        rawDuration=v(raw.reportedDuration),rawEnd=v(raw.expires),
        rawPlayer=v(raw.playerLoC),active=v(dr[1] and dr[1].active)}
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={T.aura(5211,1,10,10)}
    ns.Observer.Scan(10.1)
    save('indexed-aura-tags-readable-end',e,ns,G,nil,
        {expires=20,source='aura',bound=10,rawSource='aura',rawBound=10,stage=1})
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={secretAt=1};e.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    local aura=T.aura(5211,1,10,10);aura.duration=nil
    e.auras.target={aura,secretAt=2};e.byloc.target={T.loc(5211,1,10,nil)}
    ns.Observer.Scan(10.3)
    save('unbound-indexed-aura-keeps-own-missing-bound',e,ns,G,nil,
        {expires=13,source='loc',bound=10,rawSource='aura',rawBound=NIL,stage=1})
end
for _,id in ipairs({20549,4068,19975}) do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={secretAt=1};e.byloc.target={T.loc(id,1,10,3)}
    ns.Observer.Scan(10.1)
    e.exact.target={[id]=T.aura(id,1,10,10)};e.byloc.target={T.loc(id,1,10,nil)}
    ns.Observer.Scan(10.3)
    save('exact-aura-tags-readable-end-'..id,e,ns,G,ns.Data.auraCategory[id],
        {expires=13,source='loc',bound=10,rawSource='aura',rawBound=10,stage=1})
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={secretAt=1}
    ns.Observer.OnAuraEvent('target',{addedAuras={T.aura(20549,1,10,10)}},10.1)
    save('core-added-aura-event-tags-readable-end',e,ns,G,nil,
        {expires=20,source='aura',bound=10,rawSource='aura',rawBound=10,stage=1})
end
do
    local e,ns=fresh()
    e.identity.nameplate1=G;e.auras.nameplate1={secretAt=1}
    ns.Observer.OnNameplateAdded('nameplate1',10.1)
    ns.Observer.OnNameplateAura('nameplate1',{addedAuras={T.aura(4068,1,10,10)}},10.3)
    save('nameplate-added-aura-event-tags-readable-end',e,ns,G,nil,
        {expires=20,source='aura',bound=10,rawSource='aura',rawBound=10,stage=1})
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={secretAt=1};e.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    save('loc-duration-tags-own-end-and-raw-duration',e,ns,G,nil,
        {expires=13,source='loc',bound=10,rawSource='loc',rawBound=10,rawDuration=3,stage=1})
end
for _,token in ipairs({'target','focus','player'}) do
    local e,ns=fresh()
    local guid=token=='player' and 'Player-Self' or G
    e.identity[token]=guid;e.auras[token]={T.aura(5211,1,10,10),secretAt=2}
    if token=='player' then e.loc={T.loc(5211,nil,10,nil)}
    else e.byloc[token]={T.loc(5211,nil,10,nil)} end
    ns.Observer.Scan(10.1)
    save('current-native-aura-end-enriches-start-only-loc-'..token,e,ns,guid,nil,
        {expires=20,source='aura',bound=10,reset=38,pending=false,stage=1})
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={T.aura(5211,1,10,10),secretAt=2}
    e.byloc.target={T.loc(5211,1,12,nil)}
    ns.Observer.Scan(12.1)
    save('first-native-loc-calibration-keeps-weak-aura-bound',e,ns,G,nil,
        {expires=20,source='aura',bound=10,start=12,reset=38,pending=false,stage=1})
end
do
    local e,ns=fresh()
    ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,appliedAt=10,
        expires=13,applicationSource='loc'}},10.1,false)
    ns.model:Observe(G,{['a:1']={category='stun',spellID=5211,appliedAt=10,
        expires=20,applicationSource='loc',expirySource='unknown'}},10.3,false)
    save('explicit-unknown-end-does-not-infer-merged-loc-authority',e,ns,G,nil,
        {expires=13,source='loc',bound=10,stage=1})
end
do
    local e,ns=fresh()
    e.auras.player={secretAt=1}
    e.loc={T.loc(5211,1,10,10)}
    e.byloc.player={T.loc(5211,nil,10.4,nil)}
    ns.Observer.Scan(10.5)
    save('current-older-native-loc-cannot-donate-end-to-newer-fallback',e,ns,'Player-Self',nil,
        {expires=NIL,source=NIL,bound=NIL,start=10.4,reset=NIL,pending=true,stage=1,
         rawPlayer=NIL,active=true})
end
do
    local e,ns=fresh()
    e.auras.player={secretAt=1};e.loc={T.loc(5211,1,10,10)}
    ns.Observer.Scan(10.1)
    e.byloc.player={T.loc(5211,nil,10.4,nil)}
    ns.Observer.Scan(10.5)
    save('accepted-older-native-loc-cannot-donate-end-to-refreshed-fallback',e,ns,'Player-Self',nil,
        {expires=NIL,source=NIL,bound=NIL,start=10.4,reset=NIL,pending=true,stage=2,
         rawPlayer=NIL,active=true})
end
for _,unbound in ipairs({false,true}) do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={secretAt=1};e.byloc.target={T.loc(5211,1,10,3)}
    ns.Observer.Scan(10.1)
    local aura=T.aura(5211,1,10,10)
    if unbound then aura.duration=nil end
    e.auras.target={aura,secretAt=2};e.byloc.target={T.loc(5211,nil,10.4,nil)}
    ns.Observer.Scan(10.5)
    save('model-known-refresh-rejects-current-native-aura-donor-unbound-'..tostring(unbound),e,ns,G,nil,
        {expires=NIL,source=NIL,bound=NIL,start=10.4,reset=NIL,pending=true,stage=2,active=true})
end
do
    local e,ns=fresh()
    e.identity.target=G;e.auras.target={T.aura(5211,1,10,10),secretAt=2}
    e.byloc.target={T.loc(5211,nil,12,nil)}
    ns.Observer.Scan(12.1)
    save('first-start-only-loc-calibration-keeps-current-weak-end',e,ns,G,nil,
        {expires=20,source='aura',bound=10,start=12,reset=38,pending=false,stage=1})
end
do
    local e,ns=fresh()
    e.auras.player={secretAt=1};e.loc={T.loc(5211,1,10.4,nil)}
    e.byloc.player={T.loc(5211,nil,10,10)}
    ns.Observer.Scan(10.5)
    save('current-older-fallback-cannot-fill-newer-native-unknown-end',e,ns,'Player-Self',nil,
        {expires=NIL,source=NIL,bound=NIL,start=10.4,reset=NIL,pending=true,stage=1,active=true})
end
return rows
