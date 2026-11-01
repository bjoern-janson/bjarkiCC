-- Public Observer regressions: delayed evidence must follow the occurrence
-- while its bounded state is current or the flat predecessor. Client API
-- fixtures are shared; Observer/Model and their coverage decisions are real.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G,A,B='Player-Enemy',339,122
local cases,checks,failures=0,0,{}
local function eq(actual,expected,label)
 checks=checks+1
 assert(actual==expected,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function untimed(id,spell)
 return {spellId=spell or A,auraInstanceID=id,isHarmful=true}
end
local function fresh()
 local e,n=T.fresh();e.identity.target=G;e.identity.focus=G
 for i=0,499 do n.Observer.Scan(i*.2) end
 return e,n
end
local function read(e,n,auras,locs,now,complete)
 e.auras.target={};e.auras.focus={}
 for k,v in ipairs(auras) do e.auras.target[k]=v;e.auras.focus[k]=v end
 if not complete then e.auras.target.secretAt=#auras+1 end
 e.byloc.target=locs or {};n.Observer.Scan(now)
 eq(n.Observer.stats.scanGaps,0,'continuous coverage')
 eq(n.Observer.stats.apiErrors,0,'readable fixture')
end
local function state(n) return n.model.units[G].categories[n.Data.auraCategory[A]] end
local function baseline(n)
 local b=n.model.units[G].durationBaselines[A];return b and b.duration
end
local function row(n,now)
 for _,v in ipairs(n.model:GetDR(G,now,false)) do if v.category==n.Data.auraCategory[A] then return v end end
 error('missing root row')
end
local function poll(n,from,to)
 local i=1
 while from+i*.2<to-.000001 do n.Observer.Scan(from+i*.2);i=i+1 end
 n.Observer.Scan(to)
end
local function successor(e,n)
 poll(n,100.4,109.8);read(e,n,{}, {},110,true);poll(n,110,125.3)
 read(e,n,{untimed(3)},{T.loc(A,3,125.5,10)},125.5)
 return row(n,125.5)
end

-- Removing predecessor interval retention fails these before any raw duration
-- or older sibling correction can hide the missing veto.
for _,startOnly in ipairs({false,true}) do
 for _,interval in ipairs({10,20}) do
  test('late predecessor interval startOnly='..tostring(startOnly)..' duration='..interval,function()
   local e,n=fresh();local locs=startOnly and {T.loc(A,1,100,nil)} or {}
   read(e,n,{untimed(1)},locs,100)
   read(e,n,{untimed(1),untimed(2,B)},locs,100.1)
   read(e,n,{T.aura(A,1,100,interval),untimed(2,B)},{},100.2,true)
   local prior=assert(state(n).previousApplication)
   eq(prior.applicationKey,'a:1');eq(prior.durationContext.initialAuraDuration,interval,'predecessor retains first coherent interval')
   eq(prior.reportedDurationWitness,nil,'aura does not consume raw decision')
   eq(baseline(n),nil,'aura alone cannot teach baseline')
   eq(state(n).appliedAt,100.1,'late interval cannot rewind current occurrence')
   read(e,n,{T.aura(A,1,100,30-interval),untimed(2,B)},{},100.25,true)
   eq(state(n).previousApplication.durationContext.initialAuraDuration,interval,'first predecessor interval stays frozen')
  end)
 end
 test('backdated provisional sibling blocks restored baseline startOnly='..tostring(startOnly),function()
  local e,n=fresh();local locs=startOnly and {T.loc(A,1,100,nil)} or {}
  read(e,n,{untimed(1)},locs,100)
  read(e,n,{untimed(1),untimed(2,B)},locs,100.1)
  read(e,n,{T.aura(A,1,100,20),untimed(2,B)},{},100.2,true)
  read(e,n,{untimed(1),T.aura(B,2,99.9,20)},locs,100.3)
  read(e,n,{untimed(1)},{T.loc(A,1,100,10)},100.4)
  eq(baseline(n),nil,'late conflict cannot teach full duration')
  local nextRow=successor(e,n)
  eq(nextRow.stage,2,'successor cannot use poisoned baseline');eq(nextRow.resetEvidence,nil)
 end)
end

for _,mode in ipairs({'together','known-older','same-start','provisional','older-then-removed'}) do
 test('older same-category sibling revokes pending quiet: '..mode,function()
  local e,n=fresh();local old=T.aura(B,2,mode=='same-start' and 100 or 99.9,20)
  read(e,n,mode=='together' and {untimed(1),old} or {untimed(1)},{T.loc(A,1,100,nil)},100)
  if mode=='provisional' then read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil)},100.1) end
  if mode~='together' and mode~='same-start' then read(e,n,{untimed(1),old},{T.loc(A,1,100,nil)},100.2) end
  read(e,n,mode=='older-then-removed' and {untimed(1)} or {untimed(1),old},{T.loc(A,1,100,10)},100.3)
  eq(baseline(n),nil,'older overlap invalidates original quiet assumptions')
 end)
end

for _,kind in ipairs({'other-category','newer-same-category'}) do
 test('valid pending quiet survives '..kind,function()
  local e,n=fresh()
  read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
  local other=kind=='other-category' and T.aura(2637,2,99.9,20) or T.aura(B,2,100.1,20)
  -- The newer sibling did not exist before A. Its discovery must not invent
  -- overlap in A's saved pre-application history.
  if kind=='other-category' then read(e,n,{untimed(1),other},{T.loc(A,1,100,nil)},100.2) end
  read(e,n,{untimed(1),other},{T.loc(A,1,100,10)},100.3)
  eq(baseline(n),10,'uncontradicted quiet baseline remains learnable')
 end)
end

test('own late clock calibration keeps a genuinely newer sibling harmless',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{},100)
 -- B predates A's local arrival fallback, but not A's eventual explicit start.
 local later=T.aura(B,2,99.9,20)
 read(e,n,{untimed(1),later},{},100.1)
 read(e,n,{untimed(1),later},{T.loc(A,1,99,10)},100.3)
 eq(row(n,100.3).started,99,'own timing calibrates in place')
 eq(baseline(n),10,'compare sibling against calibrated occurrence, not arrival fallback')
end)

test('later sibling cannot rewrite a consumed raw-duration decision',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,10)},100)
 eq(baseline(n),10)
 read(e,n,{T.aura(A,1,100,20),T.aura(B,2,99.9,20)},{T.loc(A,1,100,10)},100.2)
 eq(baseline(n),10,'accepted baseline stays frozen')
 eq(state(n).reportedDurationWitness,10)
end)

test('a predecessor retains its consumed raw-duration decision',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,10)},100)
 read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,10)},100.1)
 read(e,n,{T.aura(A,1,100,20),untimed(2,B)},{},100.2,true)
 local prior=assert(state(n).previousApplication)
 eq(prior.reportedDurationWitness,10)
 eq(prior.durationContext.initialAuraDuration,nil,'late predecessor interval cannot reopen consumed decision')
 eq(baseline(n),10)
end)

for _,mismatch in ipairs({'start','spell'}) do
 test('predecessor veto rejects '..mismatch..' mismatch',function()
  local e,n=fresh()
  read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
  read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil)},100.1)
  local a=mismatch=='start' and T.aura(A,1,90,20) or T.aura(B,1,100,20)
  read(e,n,{a,untimed(2,B)},{},100.2,true)
  local prior=assert(state(n).previousApplication)
  eq(prior.spellID,A);eq(prior.durationContext.initialAuraDuration,nil,'unrelated interval cannot attach to predecessor')
 end)
end

test('genuine refresh starts an independent duration decision',function()
 local e,n=fresh()
 read(e,n,{T.aura(A,1,100,20)},{T.loc(A,1,100,10)},100)
 eq(baseline(n),nil)
 poll(n,100,109.8)
 read(e,n,{T.aura(A,1,100,20)},{T.loc(A,1,110,5)},110)
 eq(row(n,110).stage,2);eq(row(n,110).started,110)
 eq(state(n).durationContext.initialAuraDuration,nil,'old interval cannot bind refreshed start')
 eq(state(n).reportedDurationWitness,5,'refresh owns a separate first raw decision')
end)

for _,interval in ipairs({10,20}) do
 test('isolated matching/conflicting interval duration='..interval,function()
  local e,n=fresh()
  read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
  read(e,n,{T.aura(A,1,100,interval)},{},100.2,true)
  read(e,n,{untimed(1)},{T.loc(A,1,100,10)},100.4)
  eq(baseline(n),interval==10 and 10 or nil)
  local nextRow=successor(e,n)
  eq(nextRow.stage,interval==10 and 1 or 2,'valid matching-duration reset remains available')
  eq(nextRow.resetEvidence,interval==10 and 'matching-full-duration' or nil)
 end)
end

for _,independentOlder in ipairs({false,true}) do
 test('authoritative sibling calibration independent older='..tostring(independentOlder),function()
  local e,n=fresh()
  read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
  local aa={untimed(1),T.aura(B,2,99.9,20)}
  if independentOlder then aa[3]=T.aura(B,4,99.7,20) end
  read(e,n,aa,{T.loc(A,1,100,nil)},100.1)
  -- The independent older occurrence disappears before the calibration. Its
  -- evidence must survive, while B's own weaker clock must be replaceable.
  read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil),T.loc(B,2,100.1,nil)},100.2)
  read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,10),T.loc(B,2,100.1,nil)},100.3)
  eq(n.model.units[G].effects['a:2'].appliedAt,100.1,'stronger sibling start accepted')
  local expected=10;if independentOlder then expected=nil end
  eq(baseline(n),expected,'only the calibrated occurrence changes its evidence')
 end)
end

for _,rawStart in ipairs({99,98}) do
 test('untimed predecessor interval survives first explicit clock '..rawStart,function()
  local e,n=fresh()
  read(e,n,{untimed(1)},{},100)
  read(e,n,{untimed(1),untimed(2,B)},{},100.1)
  read(e,n,{T.aura(A,1,99,20),untimed(2,B)},{},100.2)
  read(e,n,{untimed(1),T.aura(B,2,99.8,20)},{},100.3)
  read(e,n,{untimed(1)},{T.loc(A,1,rawStart,10)},100.4)
  eq(state(n).appliedAt,rawStart,'own explicit start calibrates')
  -- As for a current aura-first occurrence, first LoC timing calibrates the
  -- identity; it cannot erase the already accepted first interval veto.
  eq(baseline(n),nil,'first explicit calibration retains same-occurrence interval veto')
  eq(successor(e,n).stage,2,'uncalibrated predecessor conflict cannot authorize a later reset')
 end)
end

test('sibling refresh does not erase its actual earlier occurrence',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
 read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil),T.loc(B,2,99.9,nil)},100.1)
 -- An explicit newer start is a refresh, not an aura-clock calibration.
 read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,10),T.loc(B,2,100.1,nil)},100.2)
 eq(baseline(n),nil,'refresh preserves evidence of the preceding overlap')
end)

test('multiple independent sibling clocks can each calibrate newer',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
 read(e,n,{untimed(1),T.aura(B,2,99.9,20),T.aura(B,4,99.7,20)},
  {T.loc(A,1,100,nil)},100.1)
 read(e,n,{untimed(1),untimed(2,B),untimed(4,B)},
  {T.loc(A,1,100,nil),T.loc(B,2,100.1,nil),T.loc(B,4,100.15,nil)},100.2)
 read(e,n,{untimed(1),untimed(2,B),untimed(4,B)},
  {T.loc(A,1,100,10),T.loc(B,2,100.1,nil),T.loc(B,4,100.15,nil)},100.3)
 eq(baseline(n),10,'all genuinely newer calibrated siblings preserve quiet learning')
end)

test('a weaker sibling clock cannot undo its authoritative calibration',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
 read(e,n,{untimed(1),T.aura(B,2,99.9,20)},{T.loc(A,1,100,nil)},100.1)
 read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,nil),T.loc(B,2,100.1,nil)},100.2)
 read(e,n,{untimed(1),T.aura(B,2,99.8,20)},{},100.25,true)
 read(e,n,{untimed(1),untimed(2,B)},{T.loc(A,1,100,10),T.loc(B,2,100.1,nil)},100.3)
 eq(baseline(n),10,'weaker aura cannot backdate the accepted sibling origin')
end)

test('pending sibling churn remains bounded without granting quiet learning',function()
 local e,n=fresh()
 read(e,n,{untimed(1)},{T.loc(A,1,100,nil)},100)
 for i=1,520 do
  read(e,n,{untimed(1),T.aura(B,1000+i,99.9,20)},{T.loc(A,1,100,nil)},100+i*.001)
 end
 local context=state(n).durationContext
 eq(T.count(context.siblingOrigins)<=512,true,'pending references obey existing effect inventory cap')
 read(e,n,{untimed(1)},{T.loc(A,1,100,10)},100.6)
 eq(baseline(n),nil,'discarding excess sibling evidence cannot establish quiet')
end)

print('pending duration evidence: '..cases..' cases, '..checks..' checks, '..#failures..' failures')
for _,failure in ipairs(failures) do print('FAIL '..failure) end
assert(#failures==0,table.concat(failures,'\n'))
