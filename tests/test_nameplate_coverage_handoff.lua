-- Core-to-nameplate coverage must use a current complete snapshot, not plate
-- registration or its cached (possibly core-owned) diagnostic state.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G='Player-Enemy'
local cases,checks,failures=0,0,{}
local function eq(actual,expected,label)
 checks=checks+1
 assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fixture()
 local e,ns=T.fresh();e.identity.target=G;e.identity.focus=G
 local plateReads=0;local getter=C_UnitAuras.GetAuraDataByIndex
 C_UnitAuras.GetAuraDataByIndex=function(unit,index)
  if unit:match('^nameplate') then plateReads=plateReads+1 end
  return getter(unit,index)
 end
 for i=0,100 do ns.Observer.Scan(i*.2) end
 local f={e=e,ns=ns}
 function f:plate(token,partial)
  e.identity[token]=G;e.auras[token]=partial and {secretAt=1} or {}
  ns.Observer.OnNameplateAdded(token,20.05)
 end
 function f:drop()
  e.identity.target=nil;e.identity.focus=nil;ns.Observer.Scan(20.2)
 end
 function f:actor() return assert(ns.model.units[G]) end
 function f:reads() return plateReads end
 function f:clean()
  eq(ns.Observer.stats.scanGaps,0,'no scan gaps');eq(ns.Observer.stats.apiErrors,0,'no API errors')
 end
 return f
end
local function replay(kind)
 local f=fixture();local e,ns=f.e,f.ns
 if kind~='no plate' then f:plate('nameplate1',kind~='complete plate') end
 f:drop()
 local complete=kind=='complete plate';local actor=f:actor()
 eq(actor.completeSince,complete and 0 or nil,'coverage at core loss')
 if kind=='partial plate resampled' then ns.Observer.OnNameplateAura('nameplate1',{isFullUpdate=true},20.25) end
 local reads=f:reads()
 ns.Observer.Scan(20.4);ns.Observer.Scan(20.6);ns.Observer.Scan(20.8)
 eq(f:reads(),reads,'ordinary scans do not poll plates')
 e.identity.target=G;e.identity.focus=G
 e.auras.target={secretAt=1};e.byloc.target={T.loc(2637,1,21,10)}
 e.auras.focus={T.aura(2637,1,21,10)};ns.Observer.Scan(21)
 if kind~='no plate' then ns.Observer.OnNameplateAura('nameplate1',{isFullUpdate=true},21.05) end
 eq(actor.completeSince,complete and 0 or 21,'reacquired coverage starts after actual gap')
 eq(actor.durationBaselines[2637]~=nil,complete,'only complete handoff permits baseline')
 local row=assert(ns.model:GetDR(G,21,false)[1]);eq(row.uncertain,not complete,'public confidence')
 for i=1,49 do ns.Observer.Scan(21+i*.2) end
 e.byloc.target={};e.auras.focus={}
 for i=0,79 do ns.Observer.Scan(31+i*.2) end
 e.byloc.target={T.loc(2637,2,47,10)};e.auras.focus={T.aura(2637,2,47,10)};ns.Observer.Scan(47)
 row=assert(ns.model:GetDR(G,47,false)[1])
 eq(row.stage,complete and 1 or 2,'successor public stage')
 eq(row.resetEvidence,complete and 'matching-full-duration' or nil,'successor reset proof');f:clean()
end
for _,kind in ipairs({'no plate','partial plate','partial plate resampled','complete plate'}) do
 test(kind..' coverage and duration replay',function() replay(kind) end)
end
for _,wasPartial in ipairs({false,true}) do
 test('handoff resamples '..(wasPartial and 'newly complete' or 'newly partial')..' plate',function()
  local f=fixture();f:plate('nameplate1',wasPartial)
  -- A normal core scan also copies its state to the plate: cached status is
  -- deliberately indistinguishable from complete primary coverage.
  f.ns.Observer.Scan(20.1)
  f.e.auras.nameplate1=wasPartial and {} or {secretAt=1}
  local reads=f:reads();f:drop()
  eq(f:reads()>reads,true,'actual plate read on transition')
  eq(f:actor().completeSince,wasPartial and 0 or nil,'current plate coverage wins');f:clean()
 end)
end
for _,completeToken in ipairs({'none','nameplate1','nameplate2'}) do
 test('multiple plates with complete source '..completeToken,function()
  local f=fixture();f:plate('nameplate1',true);f:plate('nameplate2',true)
  if completeToken~='none' then f.e.auras[completeToken]={} end
  f:drop();eq(f:actor().completeSince,completeToken~='none' and 0 or nil,'complete alternative keeps continuity')
  local reads=f:reads();f.ns.Observer.Scan(20.4);eq(f:reads(),reads,'no periodic scan');f:clean()
 end)
end
for _,invalid in ipairs({'missing','changed'}) do
 test('registered plate with '..invalid..' identity cannot preserve coverage',function()
  local f=fixture();f:plate('nameplate1',false)
  f.e.identity.nameplate1=invalid=='changed' and 'Player-Other' or nil
  f:drop();eq(f:actor().completeSince,nil,'unqualified plate invalidates history');f:clean()
 end)
end
test('remaining core alias keeps primary coverage without polling plate',function()
 local f=fixture();f:plate('nameplate1',true);local reads=f:reads()
 f.e.identity.target=nil;f.ns.Observer.Scan(20.2)
 eq(f:actor().completeSince,0,'focus still owns complete coverage');eq(f:reads(),reads,'not a core loss');f:clean()
end)
for _,identity in ipairs({'native','fallback'}) do
for _,partial in ipairs({false,true}) do
 test(identity..' '..(partial and 'partial' or 'complete')..' transition preserves active canonical identity and clocks',function()
  local f=fixture();local e,ns=f.e,f.ns
  e.auras.target={secretAt=1};e.auras.focus=identity=='native' and {T.aura(2637,7,20,10)} or {secretAt=1}
  e.byloc.target={T.loc(2637,identity=='native' and 7 or nil,20,10)};ns.Observer.Scan(20.02)
  e.auras.target={T.aura(2637,7,20,10)};e.auras.focus=e.auras.target;ns.Observer.Scan(20.04)
  local actor=f:actor();local state=actor.categories.incapacitate
  local key=state.applicationKey;eq(key,identity=='native' and 'a:7' or 'l:s:2637:20','established canonical key')
  e.identity.nameplate1=G;e.auras.nameplate1={T.aura(2637,7,20,10)}
  if partial then e.auras.nameplate1.secretAt=2 end
  ns.Observer.OnNameplateAdded('nameplate1',20.05)
  local applied,expires,stageEnd,resetAt=state.appliedAt,actor.effects[key].expires,state.stageEndAt,state.stageResetAt
  local epoch=actor.durationEpoch;f:drop()
  eq(state.applicationKey,key,'canonical key survives');eq(T.count(actor.effects),1,'no duplicate native identity')
  eq(state.stage,1,'application counted once');eq(state.appliedAt,applied,'application clock unchanged')
  eq(actor.effects[key].expires,expires,'expiry unchanged');eq(state.stageEndAt,stageEnd,'stage endpoint unchanged')
  eq(state.stageResetAt,resetAt,'18-second stage reset unchanged')
  -- Existing fallback reconciliation stays ambiguous; its identity and
  -- clocks must survive without granting stronger coverage authority.
  if identity=='native' then
   eq(actor.durationEpoch,epoch+(partial and 1 or 0),'only partial coverage invalidates history')
   eq(actor.completeSince,not partial and 0 or nil,'complete native handoff preserves history')
  end
  ns.Observer.OnNameplateAura('nameplate1',{isFullUpdate=true},20.25)
  eq(state.applicationKey,key,'event handoff retains canonical key');eq(state.stage,1,'event does not recount');f:clean()
 end)
end
end
for _,failure in ipairs(failures) do print('FAIL nameplate coverage handoff: '..failure) end
assert(#failures==0,tostring(#failures)..' nameplate coverage handoff case(s) failed')
print('nameplate coverage handoff: '..cases..' cases / '..checks..' checks passed')
