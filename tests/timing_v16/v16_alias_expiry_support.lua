-- Independent read-only T3 controls. Loads exact runtime through existing API stubs.
local T = dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local rows = {}
local NIL = '<nil>'
local function value(v) if v == nil then return NIL end return v end
local function copy(v)
 if type(v) ~= 'table' then return v end
 local t={} for k,x in pairs(v) do t[k]=copy(x) end return t
end
local function fresh()
 local e,ns=T.fresh()
 e.auras.player={secretAt=1}
 local observed=ns.model.Observe
 ns.model.Observe=function(self,guid,effects,now,complete,removed)
  if guid=='Player-Self' then e.last={effects=copy(effects),removed=copy(removed),complete=complete,now=now} end
  return observed(self,guid,effects,now,complete,removed)
 end
 return e,ns
end
local function record(name,e,ns,expected,kind,key)
 local actor=assert(ns.model.units['Player-Self'])
 local state=actor.categories.stun or {}
 key=key or state.applicationKey or 'a:1'
 local model=actor.effects[key] or {}
 local current=e.last and e.last.effects[key] or {}
 local observer=ns.Observer.units.player
 local witness=observer.witnesses[key] or {}
 local dr=ns.model:GetDR('Player-Self',e.last.now,false)
 local row={name=name,kind=kind or 'control',key=key,expected=expected or {},
  stage=value(state.stage),start=value(model.appliedAt),expiry=value(model.expires),
  reset=value(state.stageResetAt),pending=value(state.stageResetPending),
  ended=value(model.endedAt),active=value(dr[1] and dr[1].active),
  inStart=value(current.appliedAt),inExpiry=value(current.expires),
  inDuration=value(current.reportedDuration),inPlayer=value(current.playerLoC),
  inNative=value(current.nativeKey),inBoundary=value(current.nativeLoCStart),
  witnessExpiry=value(witness.expires),witnessPlayer=value(witness.playerLoC),
  effects=T.count(actor.effects),inputs=T.count(e.last.effects),
  witnesses=T.count(observer.witnesses),scanGaps=ns.Observer.stats.scanGaps,
  removed=value(e.last.removed and e.last.removed[key])}
 rows[#rows+1]=row
 return row
end
local function loc(instance,start,duration,spell)
 return T.loc(spell or 5211,instance,start,duration)
end
local function prior(e,ns,start,duration,fallbackFirst)
 e.loc={loc(fallbackFirst and nil or 1,start,duration)}
 if fallbackFirst then e.loc={loc(nil,start,duration)} end
 e.byloc.player={}
 ns.Observer.Scan(10.1)
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10,6)}
 ns.Observer.Scan(10.1)
 record('fresh-native-missing-fallback-end16',e,ns,{expiry=16,reset=34,inExpiry=16,inputs=1,stage=1},'desired-T3','a:1')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3)
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10,6)}
 ns.Observer.Scan(10.3)
 record('same-start-correction-end13-to16',e,ns,{expiry=16,reset=34,inExpiry=16,stage=1},'desired-T3','a:1')
 e.loc={secret=true};e.byloc.player={secret=true}
 for i=1,33 do ns.Observer.Scan(10.3+i*.2) end
 e.auras.player={};e.loc={};e.byloc.player={};ns.Observer.Scan(17.1)
 for i=1,74 do ns.Observer.Scan(17.1+i*.2) end
 e.auras.player={secretAt=1};e.loc={loc(2,32,2)};ns.Observer.Scan(32.1)
 record('same-start-correction-next-application32',e,ns,{stage=2,scanGaps=0},'desired-T3','a:2')
end
do
 local e,ns=fresh()
 e.loc={loc(nil,10,6)};e.byloc.player={loc(1,10,nil)}
 ns.Observer.Scan(10.1)
 record('reversed-api-native-missing-fallback-end16',e,ns,{expiry=16,inExpiry=16,inPlayer=true,stage=1},'desired-T3','a:1')
 e.loc={};e.byloc.player={secret=true};ns.Observer.Scan(10.3)
 record('same-occurrence-removal-authority-retained',e,ns,{reset=28.3,active=false,removed=true,effects=0},'control','a:1')
end
for _,reverse in ipairs({false,true}) do
 local e,ns=fresh()
 local native,fallback=loc(1,10,nil),loc(nil,10,6)
 e.loc=reverse and {fallback,native} or {native,fallback}
 ns.Observer.Scan(10.1)
 record('same-api-row-order-'..tostring(reverse),e,ns,{expiry=16,inExpiry=16,stage=1,inputs=1},'desired-T3','a:1')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3,true)
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10,6)}
 ns.Observer.Scan(10.3)
 record('prior-fallback-canonical-inherited-end13',e,ns,{expiry=16,inExpiry=16,stage=1,inputs=1},'desired-T3','l:s:5211:10')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3)
 e.loc={};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.3)
 record('fallback-only-correction-normalizes16',e,ns,{inExpiry=16,stage=1,inputs=1},'control','a:1')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3)
 e.loc={loc(1,10,6)};e.byloc.player={};ns.Observer.Scan(10.3)
 record('native-only-correction-normalizes16',e,ns,{inExpiry=16,stage=1,inputs=1},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,3)};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.1)
 record('conflicting-readable-ends-keep-native',e,ns,{expiry=13,inExpiry=13,inDuration=3,stage=1,inputs=1},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,6)};e.byloc.player={loc(nil,10,nil)};ns.Observer.Scan(10.1)
 record('native-end16-fallback-missing',e,ns,{expiry=16,inExpiry=16,inDuration=6,stage=1},'control','a:1')
end
for _,delta in ipairs({-.0005,.0005}) do
 local e,ns=fresh()
 prior(e,ns,10,3)
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10+delta,6)};ns.Observer.Scan(10.3)
 record('within-epsilon-fallback-delta-'..tostring(delta),e,ns,
  {inExpiry=16+delta,stage=1,inputs=1},delta > 0 and 'control' or 'desired-T3','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10.4,nil)};e.byloc.player={loc(nil,10,10)};ns.Observer.Scan(10.5)
 record('newer-native-missing-old-fallback-end20',e,ns,
  {inStart=10.4,inExpiry=NIL,expiry=NIL,inPlayer=true,pending=true},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(nil,10,10)};e.byloc.player={loc(1,10.4,nil)};ns.Observer.Scan(10.5)
 record('stale-ordinary-fallback-cannot-donate-end-or-authority',e,ns,
  {inStart=10.4,inExpiry=NIL,expiry=NIL,inPlayer=NIL,pending=true},'control','a:1')
 e.loc={};e.byloc.player={secret=true};ns.Observer.Scan(10.7)
 record('stale-ordinary-absence-cannot-remove-new-native',e,ns,
  {ended=NIL,active=true,removed=NIL,pending=true},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,.3)};e.byloc.player={loc(nil,10.4,nil)};ns.Observer.Scan(10.5)
 record('newer-fallback-without-end-inherits-stale-native-end',e,ns,
  {inStart=10.4,inExpiry=NIL,expiry=NIL,inPlayer=NIL,pending=true,active=true},'related-T2','a:1')
end
do
 local e,ns=fresh()
 prior(e,ns,10,.3)
 e.loc={loc(1,10,.3)};e.byloc.player={loc(nil,10.4,3)};ns.Observer.Scan(10.5)
 record('true-refresh-fallback-richer-drops-old-ordinary-authority',e,ns,
  {inStart=10.4,inExpiry=13.4,expiry=13.4,inPlayer=NIL,stage=2},'control','a:1')
 e.loc={};e.byloc.player={secret=true};ns.Observer.Scan(10.7)
 record('old-ordinary-absence-cannot-remove-new-fallback',e,ns,
  {ended=NIL,active=true,removed=NIL},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,10,6,853)};ns.Observer.Scan(10.1)
 record('different-spell-same-category-not-merged',e,ns,
  {inExpiry=NIL,inputs=2,effects=2},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,nil),loc(2,10,nil)};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.1)
 record('two-native-candidates-fallback-end-not-assigned',e,ns,
  {inExpiry=NIL,inputs=2,effects=2},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,nil,nil)};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.1)
 record('untimed-native-fallback-start-calibrates',e,ns,
  {inExpiry=16,expiry=16,inStart=10,stage=1,inputs=1},'control','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,nil)}
 local fallback=loc(nil,10,nil);fallback.timeRemaining=5.9;e.byloc.player={fallback};ns.Observer.Scan(10.1)
 record('same-start-fallback-remaining-only',e,ns,
  {inExpiry=16,expiry=16,inDuration=NIL},'desired-T3','a:1')
end
do
 local e,ns=fresh()
 e.loc={loc(1,10,nil)};e.byloc.player={loc(nil,nil,6)};ns.Observer.Scan(10.1)
 record('fallback-without-identity-is-unusable',e,ns,
  {inExpiry=NIL,expiry=NIL,inputs=1},'control','a:1')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3,true)
 e.loc={loc(1,nil,nil)};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.3)
 record('prior-fallback-untimed-current-native-masks-correction',e,ns,
  {inExpiry=16,expiry=16,stage=1,inputs=1},'desired-T3','l:s:5211:10')
end
do
 local e,ns=fresh()
 prior(e,ns,10,3,true)
 e.auras.player={T.aura(5211,1,10,10),secretAt=2}
 e.loc={};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.3)
 record('prior-fallback-current-aura-native-masks-correction',e,ns,
  {inExpiry=16,expiry=16,stage=1,inputs=1},'desired-T3','l:s:5211:10')
end
do
 local e,ns=fresh()
 local native=loc(1,10,nil);native.timeRemaining=5.9
 e.loc={native};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.1)
 record('equal-current-ends-can-enrich-raw-duration',e,ns,
  {inExpiry=16,expiry=16,inDuration=6,stage=1},'desired-enrichment','a:1')
end
do
 local e,ns=fresh()
 local native=loc(1,10,nil);native.timeRemaining=2.9
 e.loc={native};e.byloc.player={loc(nil,10,6)};ns.Observer.Scan(10.1)
 record('conflicting-current-ends-cannot-donate-raw-duration',e,ns,
  {inExpiry=13,expiry=13,inDuration=NIL,stage=1},'control','a:1')
end
for _,kind in ipairs({'timed','untimed','aura'}) do
 local e,ns=fresh()
 prior(e,ns,10,3,true)
 if kind=='aura' then
  e.loc={};e.auras.player={T.aura(5211,1,10,10),secretAt=2}
 else
  e.loc={loc(1,kind=='timed' and 10 or nil,nil)}
 end
 e.byloc.player={};ns.Observer.Scan(10.3)
 record('prior-fallback-'..kind..'-native-only-retains-model-end13',e,ns,
  {expiry=13,reset=31,stage=1,inputs=1,active=true},'control','l:s:5211:10')
end
return rows
