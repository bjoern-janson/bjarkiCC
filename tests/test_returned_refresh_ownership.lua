-- A merged handoff must retain only the sources that sampled each occurrence.
-- Native APIs are fixtures; TOC modules, Main dispatch, Observer, Model and UI
-- run unchanged. Deleting donor provenance must duplicate the public row/HUD;
-- crediting unsampled/old donors must fail the negative continuity controls.
local fresh=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua')
local G='Player-ReturnedRefresh'
local cases,checks,failures=0,0,{}
local function eq(actual,expected,label)
 checks=checks+1
 assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function near(actual,expected,label)
 checks=checks+1;assert(actual and math.abs(actual-expected)<.00001,(label or 'clock')..': expected '..expected..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function aura(id,start,duration)
 return {spellId=2637,auraInstanceID=id,expirationTime=start+duration,duration=duration,isHarmful=true}
end
local function loc(id,start,duration)
 return {spellID=2637,auraInstanceID=id,startTime=start,duration=duration}
end
local function fixture(count)
 C_LossOfControl=nil;C_Secrets=nil;UnitFullName=nil;UnitCanAssist=nil
 local H=fresh();local ns=H.ns
 local indexed,byloc,reads={},{},{}
 C_UnitAuras.GetAuraDataByIndex=function(u,i)
  reads[u]=(reads[u] or 0)+1
  local list=indexed[u] or {}
  if list.secretAt and i>=list.secretAt then return H.hidden end
  return list[i]
 end
 C_LossOfControl={GetActiveLossOfControlDataCount=function()return 0 end,
  GetActiveLossOfControlData=function()end,
  GetActiveLossOfControlDataCountByUnit=function(u)return #(byloc[u] or {}) end,
  GetActiveLossOfControlDataByUnit=function(u,i)return (byloc[u] or {})[i] end}
 local f={H=H,ns=ns,indexed=indexed,byloc=byloc,reads=reads}
 function f:fire(t,event,...)
  H.time(t);ns.eventFrame.scripts.OnEvent(ns.eventFrame,event,...)
 end
 function f:state(t)
  local actor=assert(ns.model.units[G]);local cat=actor.categories.incapacitate
  local row=ns.model:GetDR(G,t,false)[1]
  local n=0;for _ in pairs(actor.effects)do n=n+1 end
  return row and row.stage or 0,cat,n
 end
 function f:proofs()
  return ns.Observer.guidContexts[G].state.witnessSources
 end
 function f:drop(t)
  H.units.target=nil;self:fire(t or 100.2,'PLAYER_TARGET_CHANGED')
 end
 function f:remove(token,t)
  H.units[token]=nil;self:fire(t or 100.25,'NAME_PLATE_UNIT_REMOVED',token)
 end
 function f:fallback(token,t,id,start,duration)
  indexed[token]={secretAt=1};byloc[token]={loc(id,start or 100.1,duration or 10)}
  self:fire(t,'UNIT_AURA',token,{isFullUpdate=true})
 end
 function f:hud(t,expected)
  H.units.target=G;H.hostile.target=true;indexed.target={secretAt=1}
  self:fire(t,'PLAYER_TARGET_CHANGED');ns.UI.Update(t)
  local icon=ns.UI.bars.target.icons[1]
  eq(icon and icon.row and icon.row.stage,expected,'real target HUD stage')
  eq(self:state(t),expected,'public DR stage')
 end
 function f:clean()
  eq(ns.Observer.stats.apiErrors,0,'no API errors');eq(ns.Observer.stats.scanGaps,0,'no scan gaps')
 end
 H.units.target=G;H.hostile.target=true;f:fire(100,'PLAYER_TARGET_CHANGED')
 for i=1,count do
  local token='nameplate'..i;H.units[token]=G;H.hostile[token]=true
  indexed[token]={};f:fire(100.05+i*.01,'NAME_PLATE_UNIT_ADDED',token)
 end
 f.order={};for token in pairs(ns.Observer.nameplates)do f.order[#f.order+1]=token end
 return f
end
for _,mode in ipairs({'absence','restricted','retained','absence-before-refresh','event-absence','event-retained','absence-current','absence-native'})do
 test(mode..' returned native source ownership',function()
  local f=fixture(2);local donor,selected=f.order[1],f.order[2]
  f:fallback('target',100.12,7,100.1,10)
  if mode=='absence-before-refresh' then
   f.indexed.target={};f.byloc.target={};f:fire(100.14,'UNIT_AURA','target',{isFullUpdate=true})
  end
  f:fallback('target',100.18,7,100.15,5);eq(f:state(100.18),2,'two observed explicit applications')
  if mode=='absence' or mode=='absence-current' or mode=='absence-native' or mode=='event-absence' then
   f.indexed.target={};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
   eq(f.ns.Observer.guidContexts[G].state.nativeIdentities['a:7'],nil,'complete absence revokes native metadata')
   eq(f:proofs()['a:7'],nil,'complete absence revokes positive source permission')
  elseif mode=='restricted' then
   f.indexed.target={secretAt=1};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
  end
  local accepted=f.ns.model.units[G].categories.incapacitate.witness
  near(accepted.appliedAt,100.15,'accepted explicit occurrence');near(accepted.expires,105.15,'accepted endpoint')
  f.indexed[donor]={aura(7,mode=='absence-current' and 100.15 or 100.1,mode=='absence-current' and 5 or 10),secretAt=2}
  f.indexed[selected]={}
  if mode=='event-absence' or mode=='event-retained' then
   f:fire(100.195,'UNIT_AURA',donor,{isFullUpdate=true})
   eq((f:proofs()['a:7'] or {})[donor],nil,'ordinary stale event cannot acquire proof')
  end
  f:drop()
  local proof=(f:proofs()['a:7'] or {})[donor]
  eq(proof~=nil,mode=='absence-current','only genuine current donor owns occurrence')
  if proof then near(proof.expires,105.15,'current donor owns current end')end
  f:remove(selected)
  f:fallback(donor,100.3,mode=='absence-native' and 7 or nil,100.15,5)
  local expected=(mode=='absence-current' or mode=='absence-native') and 2 or 3
  -- Stage 3 is the existing conservative unmatched-fallback policy, not a
  -- claim that this fixture proves a literal third gameplay application.
  eq(f:state(100.3),expected,'unknown fallback cannot borrow obsolete source proof')
  f.byloc.target=f.byloc[donor];f:hud(100.4,expected);f:clean()
 end)
end
for _,mode in ipairs({'first-loc','untimed','endpoint-only','current','different-key','different-spell'})do
 test(mode..' calibration and exact scope control',function()
  local f=fixture(2);local donor,selected=f.order[1],f.order[2]
  if mode=='first-loc' then
   f.indexed.target={aura(7,100.1,10)};f:fire(100.12,'UNIT_AURA','target',{isFullUpdate=true})
  else f:fallback('target',100.12,7,100.1,10)end
  f:fallback('target',100.18,7,100.15,5)
  f.indexed.target={};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
  local reading=aura(mode=='different-key' and 8 or 7,mode=='current' and 100.15 or 100.1,mode=='current' and 5 or 10)
  if mode=='untimed' then reading.duration=nil;reading.expirationTime=nil end
  if mode=='endpoint-only' then reading.duration=nil end
  if mode=='different-spell' then reading.spellId=6770 end
  f.indexed[donor]={reading,secretAt=2};f.indexed[selected]={};f:drop()
  local key=mode=='different-key' and 'a:8' or 'a:7'
  local owns=(f:proofs()[key] or {})[donor]~=nil
  eq(owns,true,'no unrelated negative rejection; first calibration and missing clocks remain eligible')
  f:remove(donor);eq((f:proofs()[key] or {})[donor],nil,'removal revokes donor permission')
  f:clean()
 end)
end
for _,change in ipairs({'removed','guid','friendly'})do
 test(change..' current donor loses all matching permission after absence',function()
  local f=fixture(2);local donor,selected=f.order[1],f.order[2]
  f:fallback('target',100.12,7,100.1,10);f:fallback('target',100.18,7,100.15,5)
  f.indexed.target={};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
  f.indexed[donor]={aura(7,100.15,5),secretAt=2};f.indexed[selected]={};f:drop()
  eq((f:proofs()['a:7'] or {})[donor]~=nil,true,'genuine donor initially owns occurrence')
  if change=='removed' then f:remove(donor,100.21)
  elseif change=='guid' then f.H.units[donor]='Player-Recycled';f:fire(100.21,'UNIT_AURA',donor,{isFullUpdate=true})
  else f.H.hostile[donor]=false;f:fire(100.21,'UNIT_AURA',donor,{isFullUpdate=true})end
  f.H.units[donor]=G;f.H.hostile[donor]=true;f.indexed[donor]={}
  f:fire(100.23,'NAME_PLATE_UNIT_ADDED',donor);f:remove(selected)
  f:fallback(donor,100.3,nil,100.15,5)
  eq(f:state(100.3),3,'old source qualification cannot match returned unknown fallback');f:clean()
 end)
end
test('mixed current and stale donors own only their sampled occurrence',function()
 local f=fixture(3);local stale,current,selected=f.order[1],f.order[2],f.order[3]
 f:fallback('target',100.12,7,100.1,10);f:fallback('target',100.18,7,100.15,5)
 f.indexed.target={};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
 f.indexed[stale]={aura(7,100.1,10),secretAt=2};f.indexed[current]={aura(7,100.15,5),secretAt=2};f.indexed[selected]={}
 f:drop();eq((f:proofs()['a:7'] or {})[stale],nil,'stale donor has no permission')
 eq((f:proofs()['a:7'] or {})[current]~=nil,true,'current donor retains permission')
 f:remove(selected);f:fallback(current,100.3,nil,100.15,5)
 eq(f:state(100.3),2,'actual current donor can match fallback');f:clean()
end)
-- A retained rejection boundary describes its own occurrence. A newly
-- accepted explicit refresh must qualify donors against the incoming boundary.
for _,mode in ipairs({'absence-current','absence-stale','retained-current','first-calibration','absence-mixed'})do
 test(mode..' incoming explicit occurrence owns its actual donors',function()
  local f=fixture(mode=='absence-mixed' and 3 or 2)
  local donor,selected=f.order[1],f.order[#f.order]
  if mode=='first-calibration' then
   -- Only an aura-derived clock, never a proven LoC refresh.
   f.indexed.target={aura(7,100.1,10)};f:fire(100.12,'UNIT_AURA','target',{isFullUpdate=true})
  else
   f:fallback('target',100.12,7,100.1,10);f:fallback('target',100.18,7,100.15,5)
  end
  if mode~='retained-current' then
   f.indexed.target={};f.byloc.target={};f:fire(100.19,'UNIT_AURA','target',{isFullUpdate=true})
   eq(next(f:proofs()),nil,'complete absence removes positive permission')
  end
  local donorStart=mode=='absence-stale' and 100.15 or mode=='first-calibration' and 100.1 or 100.2
  local donorDuration=mode=='absence-stale' and 5 or mode=='first-calibration' and 10 or 4
  f.indexed[donor]={aura(7,donorStart,donorDuration),secretAt=2}
  local stale=mode=='absence-mixed' and f.order[2]
  if stale then f.indexed[stale]={aura(7,100.15,5),secretAt=2}end
  f.indexed[selected]={};f.byloc[selected]={loc(7,100.2,4)}
  f:drop(100.21)
  local stage,cat,count=f:state(100.21)
  near(cat.appliedAt,100.2,'new explicit boundary accepted');near(cat.stageEndAt,104.2,'new explicit endpoint')
  eq(count,1,'one native occurrence before fallback')
  local proof=(f:proofs()['a:7'] or {})[donor]
  eq(proof~=nil,mode~='absence-stale','only actual incoming occurrence donor owns it')
  if proof then near(proof.expires,donorStart+donorDuration,'donor keeps its sampled endpoint')end
  if stale then eq((f:proofs()['a:7'] or {})[stale],nil,'old donor cannot inherit incoming refresh')end
  f:remove(selected,100.22);f:fallback(donor,100.23,nil,100.2,4)
  local nextStage,nextCat,nextCount=f:state(100.23)
  eq(nextCount,mode=='absence-stale' and 2 or 1,'current donor fallback must not duplicate accepted occurrence')
  if mode~='absence-stale' then
   eq(nextCat.applicationKey,'a:7','genuine donor preserves canonical native identity')
   near(f.ns.model.units[G].effects['a:7'].firstSeenAt,mode=='first-calibration' and 100.12 or 100.21,'same accepted occurrence after fallback')
  end
  near(nextCat.appliedAt,100.2,'fallback retains explicit clock')
  f.byloc.target=f.byloc[donor];f:hud(100.24,nextStage);f:clean()
 end)
end

test('retained marker is scalar and released with dormant actor',function()
 local f=fixture(0)
 f:fallback('target',100.12,7,100.1,10)
 for i=1,30 do
  local t=100.12+i*.02;local start=100.1+i*.02
  f:fallback('target',t,7,start,5)
  local state=f.ns.model.units[G].categories.incapacitate
  near(state.witness.explicitRefreshAt,start,'only latest proven boundary retained')
  eq(state.displacedApplication,nil,'refresh stores no displaced calibration snapshot')
  eq(state.previousApplication.previousApplication,nil,'refresh history remains flat')
 end
 f.indexed.target={};f.byloc.target={};f:fire(100.74,'UNIT_AURA','target',{isFullUpdate=true})
 eq(next(f.ns.Observer.guidContexts[G].state.nativeIdentities),nil,'absence releases native metadata')
 eq(next(f:proofs()),nil,'absence releases source permissions')
 near(f.ns.model.units[G].categories.incapacitate.witness.explicitRefreshAt,100.7,'negative boundary remains with closed occurrence')
 f:drop(100.8)
 for t=101,160 do f:fire(t,'PLAYER_TARGET_CHANGED')end
 eq(f.ns.model.units[G],nil,'dormant pruning releases accepted occurrence and marker')
 eq(f.ns.Observer.guidContexts[G],nil,'dormant actor releases observer context');f:clean()
end)

for _,failure in ipairs(failures)do print('FAIL returned refresh: '..failure)end
print('Returned refresh ownership: '..cases..' cases / '..checks..' checks / '..#failures..' failures')
assert(#failures==0,tostring(#failures)..' returned refresh cases failed')
