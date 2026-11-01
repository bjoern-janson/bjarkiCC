-- A merged handoff must retain only the sources that sampled each occurrence.
-- Native APIs are fixtures; TOC modules, Main dispatch, Observer, Model and UI
-- run unchanged. Deleting donor provenance must duplicate the public row/HUD;
-- crediting unsampled/old donors must fail the negative continuity controls.
local fresh=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua')
local G='Player-DonorOwnership'
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
for _,mode in ipairs({'new-donor','prior-donor','selected-stays','native-control','compatible','all-partial','multiple-donors','fallback-canonical'})do
 test(mode..' handoff retains sampled donor canonical application',function()
  local f=fixture(mode=='multiple-donors' and 3 or 2)
  local donor,selected=f.order[1],f.order[#f.order]
  if mode=='all-partial' then selected,donor=f.order[1],f.order[2] end
  local key='a:7'
  if mode=='fallback-canonical' then
   f.indexed.target={secretAt=1};f.byloc.target={loc(nil,100.1,10)}
   f:fire(100.12,'UNIT_AURA','target',{isFullUpdate=true});key='l:s:2637:100.1'
   f.indexed[donor]={secretAt=1};f.byloc[donor]={loc(nil,100.1,10)}
   f:fire(100.13,'UNIT_AURA',donor,{isFullUpdate=true});f.byloc[donor]={}
  end
  f.indexed[donor]={aura(7,100.1,10),secretAt=2}
  f.indexed[selected]=mode=='compatible' and {aura(7,100.1,10)} or {}
  if mode=='all-partial' then f.indexed[selected].secretAt=1 end
  if mode=='multiple-donors' then f.indexed[f.order[2]]={aura(7,100.1,10),secretAt=2} end
  if mode=='prior-donor' then f:fire(100.15,'UNIT_AURA',donor,{isFullUpdate=true}) end
  f:drop()
  eq(f:state(100.2),1,'handoff stage')
  local proofs={};for token,proof in pairs(f:proofs()[key] or {})do proofs[token]=proof end
  if mode=='multiple-donors' then
   eq(proofs[f.order[2]]~=nil,true,'second actual donor owns occurrence')
   f:remove(donor,100.23);donor=f.order[2]
  end
  if mode~='selected-stays' then f:remove(selected) end
  f:fallback(donor,100.3,mode=='native-control' and 7 or nil)
  local stage,cat,n=f:state(100.3)
  f.byloc.target=f.byloc[donor];f:hud(100.31,1)
  eq(stage,1,'same no-ID occurrence counts once');eq(cat.applicationKey,key,'canonical key survives');eq(n,1,'one active effect')
  near(cat.stageEndAt,110.1,'native end');near(cat.stageResetAt,128.1,'18-second reset')
  f:fallback(donor,100.35,mode=='native-control' and 7 or nil)
  eq(f:state(100.35),1,'repeated positive counts once')
  f.byloc.target=f.byloc[donor];f:hud(100.4,1)
  eq(proofs[donor]~=nil,true,'actual sampled donor owns occurrence')
  eq(proofs[selected]~=nil,mode=='compatible','empty selected alias cannot acquire donor proof')
  f:clean()
 end)
end
for _,invalid in ipairs({'removed','recycled','hostility-loss'})do
 test(invalid..' donor loses continuity and cannot lend proof',function()
  local f=fixture(2);local donor,selected=f.order[1],f.order[2]
  f.indexed[donor]={aura(7,100.1,10),secretAt=2};f:drop()
  if invalid=='removed' then
   f:remove(donor,100.22)
   f.H.units[donor]=G;f.H.hostile[donor]=true;f.indexed[donor]={}
   f:fire(100.23,'NAME_PLATE_UNIT_ADDED',donor)
  elseif invalid=='recycled' then
   f.H.units[donor]='Player-Different';f:fire(100.22,'UNIT_AURA',donor,{isFullUpdate=true})
   f.H.units[donor]=G;f.indexed[donor]={};f:fire(100.23,'NAME_PLATE_UNIT_ADDED',donor)
  else
   f.H.hostile[donor]=false;f:fire(100.22,'UNIT_AURA',donor,{isFullUpdate=true})
   f.H.hostile[donor]=true;f.indexed[donor]={};f:fire(100.23,'NAME_PLATE_UNIT_ADDED',donor)
  end
  f:remove(selected)
  f:fallback(donor,100.3,nil)
  eq(f:state(100.3),2,'new registration cannot reclaim stale occurrence')
  f.byloc.target=f.byloc[donor];f:hud(100.4,2);f:clean()
 end)
end
test('first complete source never grants proof to unread positive plate',function()
 local f=fixture(3);local selected,unread=f.order[1],f.order[2]
 f.indexed[unread]={aura(7,100.1,10),secretAt=2}
 local before=f.reads[unread];f:drop()
 eq(f.reads[unread],before,'no read after first complete source');eq(f:state(100.2),0,'unread positive has no effect')
 f:remove(selected);f:fallback(unread,100.3,nil)
 eq(f:state(100.3),1,'first actual positive creates one application');f:clean()
end)
test('owned donor real refresh counts once with its own endpoint',function()
 local f=fixture(2);local donor,selected=f.order[1],f.order[2]
 f.indexed[donor]={aura(7,100.1,10),secretAt=2};f:drop();f:remove(selected)
 f:fallback(donor,100.27,nil,100.1,10)
 f:fallback(donor,100.3,nil,100.25,5)
 local stage,cat,n=f:state(100.3)
 eq(stage,2,'new explicit start counts once');eq(n,1,'refresh stays canonical')
 near(cat.stageEndAt,105.25,'refresh endpoint');near(cat.stageResetAt,123.25,'refresh reset')
 f:fallback(donor,100.35,nil,100.25,5);eq(f:state(100.35),2,'refresh replay counts once');f:clean()
end)
test('each donor retains only its sampled expiry, never merged renewal',function()
 local f=fixture(2);local donor,selected=f.order[1],f.order[2]
 f.indexed[donor]={aura(7,100.1,1),secretAt=2}
 f.indexed[selected]={aura(7,100.1,10)};f:drop()
 local sources=f:proofs()['a:7'] or {}
 near(sources[donor] and sources[donor].expires,101.1,'short donor endpoint')
 near(sources[selected] and sources[selected].expires,110.1,'long donor endpoint')
 -- Maintain event-driven observation; a new core token may not use an expired
 -- short donor proof after the longer donor disappears.
 f:fire(100.8,'PLAYER_TARGET_CHANGED')
 f:remove(selected,101.2)
 f.H.units.target=G;f.indexed.target={secretAt=1};f.byloc.target={loc(nil,100.1,10)}
 f:hud(101.3,2);f:clean()
end)
test('old donor cannot own a newer selected explicit occurrence',function()
 local f=fixture(2);local selected,donor=f.order[1],f.order[2]
 f.indexed.target={secretAt=1};f.byloc.target={loc(7,100.1,10)}
 f:fire(100.12,'UNIT_AURA','target',{isFullUpdate=true})
 f.indexed[selected]={secretAt=1};f.byloc[selected]={loc(7,100.15,5)}
 f.indexed[donor]={aura(7,100.1,10),secretAt=2};f:drop()
 local stage,cat=f:state(100.2);eq(stage,2,'new explicit occurrence accepted')
 near(cat.stageEndAt,105.15,'selected explicit endpoint')
 local sources=f:proofs()['a:7'] or {}
 eq(sources[donor],nil,'old aura donor cannot inherit newer occurrence');eq(sources[selected]~=nil,true,'actual refresh donor owns occurrence')
 f:fire(100.23,'UNIT_AURA',donor,{isFullUpdate=true})
 eq((f:proofs()['a:7'] or {})[donor],nil,'later stale native reading cannot reacquire newer occurrence')
 f:remove(selected);f:fallback(donor,100.3,nil,100.15,5)
 eq(f:state(100.3),3,'source with no newer proof cannot reclaim canonical occurrence');f:clean()
end)
-- Aura-derived and explicit LoC starts use different clocks. Rejecting a
-- mismatch before a second explicit start proves a refresh loses real donors.
for _,sample in ipairs({
 {name='first explicit later',start=100.15},
 {name='first explicit earlier',start=100.05},
 {name='equal first explicit clock',start=100.1},
 {name='prior-positive donor first explicit later',start=100.15,prior=true},
 {name='prior-positive donor first explicit earlier',start=100.05,prior=true},
 {name='native fallback first explicit later',start=100.15,native=true},
 {name='native fallback first explicit earlier',start=100.05,native=true},
})do
 test(sample.name..' preserves sampled donor through calibration',function()
  local f=fixture(2);local donor,selected=f.order[1],f.order[2]
  f.indexed[donor]={aura(7,100.1,10),secretAt=2}
  f.indexed[selected]={};f.byloc[selected]={loc(7,sample.start,110.1-sample.start)}
  if sample.prior then f:fire(100.15,'UNIT_AURA',donor,{isFullUpdate=true}) end
  f:drop()
  local firstStage,firstCat=f:state(100.2)
  eq(firstStage,1,'first explicit clock calibrates one occurrence')
  near(firstCat.appliedAt,sample.start,'first explicit clock accepted')
  local donorProof=(f:proofs()['a:7'] or {})[donor]
  f:remove(selected)
  f:fallback(donor,100.3,sample.native and 7 or nil,sample.start,110.1-sample.start)
  local stage,cat,n=f:state(100.3)
  f.byloc.target=f.byloc[donor];f:hud(100.4,1)
  eq(stage,1,'calibrated fallback does not recount');eq(n,1,'one calibrated active effect')
  eq(cat.applicationKey,'a:7','native canonical identity survives')
  near(cat.stageEndAt,110.1,'accepted endpoint survives calibration')
  eq(donorProof~=nil,true,'actual aura donor retains ownership')
  near(donorProof.expires,110.1,'aura donor retains its own endpoint');f:clean()
 end)
end
for _,auraStart in ipairs({100.05,100.15})do
 test('accepted first explicit clock retains aura donor at '..auraStart,function()
  local f=fixture(1);local donor=f.order[1]
  f.indexed.target={secretAt=1};f.byloc.target={loc(7,100.1,10)}
  f:fire(100.12,'UNIT_AURA','target',{isFullUpdate=true})
  f.indexed[donor]={aura(7,auraStart,110.1-auraStart)};f:drop()
  local donorProof=(f:proofs()['a:7'] or {})[donor]
  f:fallback(donor,100.3,nil,100.1,10)
  local stage,cat,n=f:state(100.3)
  f.byloc.target=f.byloc[donor];f:hud(100.4,1)
  eq(stage,1,'first accepted explicit clock is not a refresh');eq(n,1,'one active effect after handoff')
  eq(cat.applicationKey,'a:7','native canonical identity survives')
  near(cat.appliedAt,100.1,'explicit clock remains accepted')
  eq(donorProof~=nil,true,'same-native aura positive owns this occurrence')
  near(donorProof.expires,110.1,'donor endpoint remains its own');f:clean()
 end)
end
for _,failure in ipairs(failures) do print('FAIL nameplate donor ownership: '..failure) end
assert(#failures==0,tostring(#failures)..' nameplate donor ownership case(s) failed')
print('nameplate donor ownership: '..cases..' cases / '..checks..' checks passed')
