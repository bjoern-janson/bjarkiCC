-- Extra independent ownership checks for the candidate; original fixture intact.
local T=dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local NIL='<nil>'
local cases={}
local function val(x) if x==nil then return NIL end return x end
local function fresh()
 local e,ns=T.fresh();e.auras.player={secretAt=1};return e,ns
end
local function loc(id,start,duration) return T.loc(5211,id,start,duration) end
local function save(name,e,ns,expected,key,extra)
 key=key or 'a:1'
 local actor=assert(ns.model.units['Player-Self'])
 local fx=actor.effects[key] or {}
 local category=actor.categories.stun or {}
 local observer=ns.Observer.units.player
 local ow=observer.witnesses[key] or {}
 local dr=ns.model:GetDR('Player-Self',e.now,false)
 local row={name=name,expected=expected,expiry=val(fx.expires),start=val(fx.appliedAt),
  stage=val(category.stage),active=val(dr[1] and dr[1].active),pending=val(category.stageResetPending),
  player=val(ow.playerLoC),observerExpiry=val(ow.expires),duration=val(ow.reportedDuration),
  native=val(ow.nativeKey),boundary=val(ow.nativeLoCStart),effects=T.count(actor.effects),
  witnesses=T.count(observer.witnesses),ended=val(fx.endedAt),scanGaps=ns.Observer.stats.scanGaps}
 for k,v in pairs(extra or {}) do row[k]=val(v) end
 cases[#cases+1]=row
end
local function scan(e,ns,now) e.now=now;ns.Observer.Scan(now) end
do
 local e,ns=fresh()
 e.loc={loc(1,10,3)};e.byloc.player={loc(nil,10.0005,6)}
 scan(e,ns,10.1)
 save('sub-epsilon-conflicting-current-end-retains-native',e,ns,
  {expiry=13,start=10,stage=1,player=true,duration=3,native='a:1',boundary=10})
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,.3)};scan(e,ns,10.1)
 e.byloc.player={loc(nil,10.4,nil)};scan(e,ns,10.5)
 save('fallback-refresh-unknown-end-drops-old-ordinary-authority',e,ns,
  {expiry=NIL,start=10.4,stage=2,player=NIL,active=true,pending=true})
 e.byloc.player={secret=true};scan(e,ns,10.7)
 save('delayed-ordinary-predecessor-cannot-fill-end-or-regain-authority',e,ns,
  {expiry=NIL,start=10.4,stage=2,player=NIL,active=true,pending=true,ended=NIL})
 e.loc={};scan(e,ns,10.9)
 save('ordinary-empty-after-delayed-predecessor-cannot-remove-refresh',e,ns,
  {expiry=NIL,start=10.4,stage=2,active=true,pending=true,ended=NIL,scanGaps=0})
end
do
 local e,ns=fresh()
 e.loc={loc(nil,10,6)};e.byloc.player={loc(1,10,nil),loc(2,10,nil)}
 scan(e,ns,10.1)
 local other=ns.Observer.units.player.witnesses['a:2'] or {}
 save('ordinary-fallback-ambiguous-between-two-natives-gives-neither-authority',e,ns,
  {expiry=NIL,player=NIL,effects=2,witnesses=2,otherPlayer=NIL,otherExpiry=NIL},'a:1',
  {otherPlayer=val(other.playerLoC),otherExpiry=val(other.expires)})
 e.loc={};e.byloc.player={secret=true};scan(e,ns,10.3)
 save('ordinary-empty-cannot-remove-unresolved-byunit-natives',e,ns,
  {expiry=NIL,active=true,pending=true,effects=2,witnesses=2,ended=NIL})
end
do
 local e,ns=fresh()
 e.identity.target='Player-Self';e.identity.focus='Player-Self'
 e.loc={loc(1,10,3)};e.byloc.player={loc(nil,10,3)};scan(e,ns,10.1)
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10,6)};scan(e,ns,10.3)
 local context=assert(ns.Observer.guidContexts['Player-Self']).state
 local sources=context.witnessSources['a:1'] or {}
 save('corrected-end-is-carried-by-qualified-alias-source-proofs',e,ns,
  {expiry=16,observerExpiry=16,stage=1,player=true,boundary=10,
   proofPlayer=16,proofTarget=16,proofFocus=16},'a:1',
  {proofPlayer=val(sources.player and sources.player.expires),
   proofTarget=val(sources.target and sources.target.expires),
   proofFocus=val(sources.focus and sources.focus.expires)})
end
return cases
