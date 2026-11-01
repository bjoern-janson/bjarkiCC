-- Accepted same-occurrence predecessor clocks must decide public DR order.
-- Reverting the predecessor calibration leaves B99.8 at stage 1/start100;
-- treating calibration as a refresh, accepting weaker clocks, or rebuilding
-- discarded history breaks the controls below. Only native API boundaries
-- are fixtures; Observe, Observer.Scan and Main event dispatch are real.
local testDir=TEST_DIR or ADDON_DIR..'/tests'
local T=dofile(testDir..'/timing_v16/support.lua')
local G,A,B='Player-Predecessor',339,122
local cases,checks,failures=0,0,{}
local function eq(actual,expected,label)
 checks=checks+1
 local same=type(actual)=='number' and type(expected)=='number'
  and math.abs(actual-expected)<.000001 or actual==expected
 assert(same,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function untimed(id,spell)return {spellId=spell or A,auraInstanceID=id,isHarmful=true}end
local function fresh(mode)
 local e,n,dispatch
 if mode=='Main' then
  C_LossOfControl=nil;C_Secrets=nil;UnitFullName=nil;UnitCanAssist=nil
  local H=dofile(testDir..'/world_recovery_support.lua')()
  n=H.ns;e={identity=H.units,auras={},byloc={}}
  H.hostile.target=true;H.hostile.focus=true
  C_UnitAuras.GetAuraDataByIndex=function(u,i)
   local list=e.auras[u] or {}
   if list.secretAt and i>=list.secretAt then return H.hidden end
   return list[i]
  end
  C_LossOfControl={GetActiveLossOfControlDataCount=function()return 0 end,
   GetActiveLossOfControlData=function()return nil end,
   GetActiveLossOfControlDataCountByUnit=function(u)return #(e.byloc[u] or {})end,
   GetActiveLossOfControlDataByUnit=function(u,i)return (e.byloc[u] or {})[i]end}
  dispatch=function(now)
   H.time(now);n.eventFrame.scripts.OnEvent(n.eventFrame,'UNIT_AURA','target',{isFullUpdate=true})
  end
 else
  e,n=T.fresh();dispatch=function(now)n.Observer.Scan(now)end
 end
 e.identity.target=G;e.identity.focus=G
 local function read(now,auras,locs)
  e.auras.target={};e.auras.focus={}
  for i,a in ipairs(auras)do e.auras.target[i]=a;e.auras.focus[i]=a end
  -- Target supplies supplemental explicit starts; focus proves complete coverage.
  e.auras.target.secretAt=#auras+1;e.byloc.target=locs or {};dispatch(now)
  eq(n.Observer.stats.scanGaps,0,'continuous scans')
  eq(n.Observer.stats.apiErrors,0,'readable API fixture')
  eq(n.model.units[G].durationEpoch,0,'complete alias preserves coverage')
 end
 local function state()return assert(n.model.units[G].categories[n.Data.auraCategory[A]])end
 local function row(now)
  for _,r in ipairs(n.model:GetDR(G,now,false))do if r.category==n.Data.auraCategory[A] then return r end end
  error('missing DR row')
 end
 return n,read,state,row
end

for _,mode in ipairs({'Observer','Main'})do
 for _,order in ipairs({'late','early','unchanged'})do
  test(mode..' predecessor calibration '..order,function()
   local n,read,state,row=fresh(mode)
   read(100,{T.aura(A,1,100,20)},{})
   if order=='early' then read(100.05,{untimed(1)},{T.loc(A,1,99,nil)})end
   read(100.1,{untimed(1),untimed(2,B)},{})
   local aStart=order=='unchanged' and 100 or 99
   read(100.2,{untimed(1),untimed(2,B)},{T.loc(A,1,aStart,nil)})
   eq(n.model.units[G].effects['a:1'].appliedAt,aStart,'accepted A clock')
   eq(n.model.units[G].effects['a:1'].applicationSource,'loc','accepted A authority')
   eq(row(100.2).stage,2,'calibration does not count another application')
   eq(state().applicationKey,'a:2','B remains provisional current')
   read(100.3,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,aStart,nil)})
   local unchanged=order=='unchanged'
   eq(row(100.3).started,unchanged and 100 or 99.8,'accepted clocks determine current start')
   eq(row(100.3).stage,unchanged and 1 or 2,'accepted order retains observed count')
   eq(row(100.3).spellID,unchanged and A or B,'newest accepted occurrence displayed')
   read(100.5,{untimed(1),T.aura(B,2,99.8,20),untimed(3)},
    {T.loc(A,1,aStart,nil),T.loc(A,3,100.5,nil)})
   eq(row(100.5).stage,unchanged and 2 or 3,'third hit preserves corrected count')
   eq(state().previousApplication.previousApplication,nil,'only one flat predecessor')
  end)
 end
end

test('simultaneous calibration restores accepted predecessor even when current sorts first',function()
 local n,read,state,row=fresh()
 read(100,{T.aura(A,1,100,20)},{})
 read(100.1,{untimed(1),untimed(2,B)},{})
 -- B98.8 sorts before A99, so synchronizing only while visiting A is too late.
 read(100.2,{untimed(1),T.aura(B,2,98.8,20)},{T.loc(A,1,99,nil)})
 eq(row(100.2).started,99,'restored predecessor uses accepted calibration')
 eq(row(100.2).stage,1,'older B is not an additional successor')
 eq(state().applicationKey,'a:1','newer accepted A restored')
end)

for _,mode in ipairs({'Observer','Main'})do
 test(mode..' complete absence then same-occurrence predecessor calibration',function()
  local n,read,state,row=fresh(mode)
  read(100,{T.aura(A,1,100,20)},{})
  read(100.1,{untimed(1),untimed(2,B)},{})
  read(100.2,{untimed(2,B)},{})
  read(100.3,{untimed(1),untimed(2,B)},{T.loc(A,1,99,nil)})
  eq(n.model.units[G].effects['a:1'].appliedAt,99,'returned A accepts first explicit calibration')
  read(100.4,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,99,nil)})
  eq(row(100.4).started,99.8,'returned predecessor uses accepted clock for ordering')
  eq(row(100.4).stage,2,'same occurrence return does not add or discard a hit')
  read(100.5,{untimed(1),T.aura(B,2,99.8,20),untimed(3)},
   {T.loc(A,1,99,nil),T.loc(A,3,100.5,nil)})
  eq(row(100.5).stage,3,'third hit retains count after predecessor return')
 end)
end

test('complete absence then newer explicit predecessor return is a real refresh',function()
 local n,read,state,row=fresh()
 read(100,{untimed(1)},{T.loc(A,1,99,nil)})
 read(100.1,{untimed(1),untimed(2,B)},{T.loc(A,1,99,nil)})
 read(100.2,{untimed(2,B)},{})
 read(100.3,{untimed(1),untimed(2,B)},{T.loc(A,1,100.25,nil)})
 eq(row(100.3).started,100.25,'returned refresh owns its new start')
 eq(row(100.3).stage,3,'returned refresh counts one new hit')
 eq(state().previousApplication.applicationKey,'a:2','refresh retains B as its only predecessor')
 read(100.4,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,100.25,nil)})
 eq(row(100.4).started,100.25,'B timing cannot undo returned refresh')
 eq(row(100.4).stage,3,'returned refresh counted once')
end)

for _,mode in ipairs({'Observer','Main'})do
 test(mode..' calibrated predecessor return with newer LoC is a refresh',function()
  local n,read,state,row=fresh(mode)
  read(100,{T.aura(A,1,100,20)},{})
  read(100.1,{untimed(1),untimed(2,B)},{})
  read(100.2,{untimed(1),untimed(2,B)},{T.loc(A,1,99,nil)})
  read(100.3,{untimed(2,B)},{})
  read(100.4,{untimed(1),untimed(2,B)},{T.loc(A,1,100.35,nil)})
  eq(row(100.4).started,100.35,'second explicit start refreshes calibrated occurrence')
  eq(row(100.4).stage,3,'returned explicit refresh counts the third hit')
  read(100.5,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,100.35,nil)})
  eq(row(100.5).started,100.35,'B calibration cannot undo returned refresh')
  eq(row(100.5).stage,3,'returned refresh keeps all three hits')
 end)
 test(mode..' stale return cannot rewrite accepted predecessor calibration',function()
  local n,read,state,row=fresh(mode)
  read(100,{T.aura(A,1,100,20)},{})
  read(100.1,{untimed(1),untimed(2,B)},{})
  read(100.2,{untimed(1),untimed(2,B)},{T.loc(A,1,99,nil)})
  read(100.3,{untimed(2,B)},{})
  read(100.4,{untimed(1),untimed(2,B)},{T.loc(A,1,98,10)})
  eq(state().previousApplication.appliedAt,99,'stale return preserves accepted predecessor clock')
  eq(n.model.units[G].effects['a:1'].appliedAt,99,'returned effect retains explicit authority')
  eq(state().previousApplication.durationContext.initialAuraDuration,20,'first historical aura veto stays frozen')
  eq(state().previousApplication.reportedDurationWitness,nil,'historical return gains no raw learning authority')
  read(100.5,{untimed(1),T.aura(B,2,98.5,20)},{T.loc(A,1,98,10)})
  eq(row(100.5).started,99,'valid restoration uses accepted clock')
  eq(row(100.5).stage,1,'older B cannot add a successor')
 end)
end

test('a returned current refresh cannot calibrate its older same-key predecessor',function()
 local n,read,state,row=fresh()
 read(100,{T.aura(A,1,99,20)},{})
 read(100.1,{T.aura(A,1,100.05,20)},{})
 read(100.2,{},{})
 read(100.3,{untimed(1)},{T.loc(A,1,100.25,nil)})
 eq(row(100.3).started,100.25,'current occurrence accepts its first explicit calibration')
 eq(row(100.3).stage,2,'return calibrates rather than counts another refresh')
 eq(state().previousApplication.appliedAt,99,'older same-key occurrence keeps its own clock')
 eq(state().previousApplication.previousApplication,nil,'current fallback remains flat')
end)

test('predecessor raw duration and first aura interval stay frozen',function()
 local n,read,state,row=fresh()
 read(100,{T.aura(A,1,100,20)},{T.loc(A,1,100,20)})
 eq(state().reportedDurationWitness,20,'first raw duration accepted')
 read(100.1,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil)})
 read(100.2,{T.aura(A,1,100,10),untimed(2,B)},{T.loc(A,1,100,10)})
 eq(state().previousApplication.reportedDurationWitness,20,'historical raw decision remains frozen')
 eq(state().previousApplication.durationContext.initialAuraDuration,20,'first coherent interval remains frozen')
 read(100.3,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,100,10)})
 eq(row(100.3).started,100,'valid restoration survives duration edits')
 eq(state().reportedDurationWitness,20,'restoration retains original raw decision')
end)

test('weaker aura and older explicit samples cannot recalibrate predecessor',function()
 local n,read,state,row=fresh()
 read(100,{untimed(1)},{T.loc(A,1,100,nil)})
 read(100.1,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil)})
 read(100.2,{T.aura(A,1,99,20),untimed(2,B)},{})
 read(100.3,{untimed(1),untimed(2,B)},{T.loc(A,1,98,nil)})
 eq(n.model.units[G].effects['a:1'].appliedAt,100,'strong accepted clock retained')
 read(100.4,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,98,nil)})
 eq(row(100.4).started,100,'stale clocks cannot defeat valid restoration')
 eq(row(100.4).stage,1,'weaker clocks cannot invent successor order')
end)

test('a newer explicit predecessor occurrence remains a refresh',function()
 local n,read,state,row=fresh()
 read(100,{untimed(1)},{T.loc(A,1,99,nil)})
 read(100.1,{untimed(1),untimed(2,B)},{T.loc(A,1,99,nil)})
 read(100.2,{untimed(1),untimed(2,B)},{T.loc(A,1,100.15,nil)})
 eq(row(100.2).started,100.15,'explicit refresh advances current occurrence')
 eq(row(100.2).stage,3,'refresh is the third observed hit')
 eq(state().previousApplication.applicationKey,'a:2','B remains flat predecessor')
 read(100.3,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,100.15,nil)})
 eq(row(100.3).started,100.15,'older B cannot rewind refresh')
 eq(row(100.3).stage,3,'refresh counted once')
end)

test('calibration of an ignored older refresh cannot rewrite another occurrence',function()
 local n,read,state,row=fresh()
 read(100,{T.aura(A,1,99,20)},{})
 read(100.1,{untimed(1),untimed(2,B)},{})
 -- A's real refresh is older than provisional B. Its new occurrence is kept
 -- in the effect inventory, but does not replace the flat A99 predecessor.
 read(100.2,{T.aura(A,1,100.05,20),untimed(2,B)},{})
 read(100.3,{untimed(1),untimed(2,B)},{T.loc(A,1,100.07,nil)})
 eq(n.model.units[G].effects['a:1'].appliedAt,100.07,'new occurrence accepts its own calibration')
 eq(state().previousApplication.appliedAt,99,'different occurrence cannot rewrite flat history')
 read(100.4,{untimed(1),T.aura(B,2,99.8,20)},{T.loc(A,1,100.07,nil)})
 eq(row(100.4).started,99.8,'calibration does not grant ignored refresh history')
 eq(row(100.4).stage,2,'bounded retained order keeps its count')
end)

test('calibrating discarded older history does not reconstruct a predecessor',function()
 local n,read,state,row=fresh()
 read(100,{T.aura(A,1,100,20)},{})
 read(100.1,{untimed(1),untimed(2,B)},{})
 read(100.2,{untimed(1),untimed(2,B),untimed(3)},{})
 read(100.3,{untimed(1),untimed(2,B),untimed(3)},{T.loc(A,1,99,nil)})
 eq(row(100.3).stage,3,'older calibration does not recount history')
 eq(state().previousApplication.applicationKey,'a:2','only immediate predecessor retained')
 eq(state().previousApplication.previousApplication,nil,'no older history reconstructed')
 read(100.4,{untimed(1),untimed(2,B),T.aura(A,3,99.5,20)},{T.loc(A,1,99,nil)})
 eq(row(100.4).started,100.1,'restores only retained immediate predecessor')
 eq(row(100.4).stage,2,'retained predecessor keeps its known count')
 eq(state().previousApplication,nil,'restoration does not acquire discarded history')
end)

for _,failure in ipairs(failures)do print('FAIL predecessor timing: '..failure)end
print('Predecessor timing: '..cases..' cases / '..checks..' checks / '..#failures..' failures')
assert(#failures==0,tostring(#failures)..' predecessor timing cases failed')
