-- Conflicting aura timing can veto a learned LoC baseline, including when
-- both sensors first become readable in one Observer scan. All inputs cross
-- the real Observer and Model; only client API boundaries come from support.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G='Player-Enemy'
local SPELL=2637
local cases,checks,failures=0,0,{}
local function eq(actual,expected,label)
 checks=checks+1
 local same=type(actual)=='number' and type(expected)=='number'
  and math.abs(actual-expected)<.000001 or actual==expected
 assert(same,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fresh()
 local e,ns=T.fresh();e.identity.target=G;e.identity.focus=G
 for i=0,499 do ns.Observer.Scan(i*.2) end
 return e,ns
end
local function row(ns,now)
 local rows=ns.model:GetDR(G,now,false);eq(#rows,1,'one category row')
 return rows[1]
end
local function state(ns)
 return assert(ns.model.units[G].categories[ns.Data.auraCategory[SPELL]])
end
local function untimed(instance)
 return {spellId=SPELL,auraInstanceID=instance or 1,isHarmful=true}
end
local function current(e,aura,loc)
 e.auras.target={aura,secretAt=2};e.auras.focus={aura};e.byloc.target={loc}
end
local function poll(ns,from,to)
 local i=1
 while from+i*.2<to-.000001 do ns.Observer.Scan(from+i*.2);i=i+1 end
 ns.Observer.Scan(to)
end
local function successor(e,ns,from,firstEnd,secondStart)
 poll(ns,from,firstEnd-.2)
 e.auras.target={};e.auras.focus={};e.byloc.target={};ns.Observer.Scan(firstEnd)
 poll(ns,firstEnd,secondStart-.2)
 current(e,T.aura(SPELL,2,secondStart,10),T.loc(SPELL,2,secondStart,10))
 ns.Observer.Scan(secondStart)
 eq(ns.Observer.stats.scanGaps,0,'continuous observation')
 eq(ns.Observer.stats.apiErrors,0,'no API errors')
 return row(ns,secondStart)
end

for _,arrival in ipairs({'together','aura-first','loc-first'}) do
 test('conflicting first interval '..arrival,function()
  local e,ns=fresh();local now=100
  if arrival=='aura-first' then
   e.auras.target={T.aura(SPELL,1,100,20)};e.auras.focus={T.aura(SPELL,1,100,20)}
   ns.Observer.Scan(100);now=100.2
  elseif arrival=='loc-first' then
   -- The explicit start is readable before either sensor supplies duration.
   current(e,untimed(),T.loc(SPELL,1,100,nil));ns.Observer.Scan(100);now=100.2
  end
  current(e,T.aura(SPELL,1,100,20),T.loc(SPELL,1,100,10));ns.Observer.Scan(now)
  local initial=row(ns,now);eq(initial.stage,1,'veto never infers a half-stage')
  eq(initial.started,100,'explicit start');eq(initial.fullDurationBaseline,nil,'conflict blocks baseline')
  local nextRow=successor(e,ns,now,110,125.5)
  eq(nextRow.stage,2,'no premature stage reset');eq(nextRow.resetEvidence,nil)
 end)
end

test('reverse alias merge retains current aura veto',function()
 local e,ns=fresh()
 e.auras.target={untimed(),secretAt=2};e.byloc.target={T.loc(SPELL,1,100,10)}
 e.auras.focus={T.aura(SPELL,1,100,20),secretAt=2}
 ns.Observer.Scan(100)
 eq(state(ns).durationContext.initialAuraDuration,20,'aura arrives after explicit normalization')
 eq(row(ns,100).stage,1);eq(row(ns,100).fullDurationBaseline,nil)
end)

for _,firstDuration in ipairs({10,20}) do
 for _,completeAlias in ipairs({false,true}) do
  test('first aura interval stays frozen '..firstDuration..' alias complete='..tostring(completeAlias),function()
   local e,ns=fresh()
   e.auras.target={T.aura(SPELL,1,100,firstDuration),secretAt=2}
   e.byloc.target={T.loc(SPELL,1,100,10)}
   e.auras.focus={T.aura(SPELL,1,100,30-firstDuration)}
   if not completeAlias then e.auras.focus.secretAt=2 end
   ns.Observer.Scan(100)
   eq(state(ns).durationContext.initialAuraDuration,firstDuration,'first coherent current aura interval')
   eq(row(ns,100).fullDurationBaseline,completeAlias and firstDuration==10 and 10 or nil)
  end)
 end
end

for _,arrival in ipairs({'together','aura-first','loc-first'}) do
 test('matching first interval '..arrival,function()
  local e,ns=fresh();local now=100
  if arrival=='aura-first' then
   e.auras.target={T.aura(SPELL,1,100,10)};e.auras.focus={T.aura(SPELL,1,100,10)}
   ns.Observer.Scan(100);now=100.2
  elseif arrival=='loc-first' then
   current(e,untimed(),T.loc(SPELL,1,100,nil));ns.Observer.Scan(100);now=100.2
  end
  current(e,T.aura(SPELL,1,100,10),T.loc(SPELL,1,100,10));ns.Observer.Scan(now)
  eq(row(ns,now).fullDurationBaseline,10,'coherent explicit baseline remains usable')
  local nextRow=successor(e,ns,now,110,125.5)
  eq(nextRow.stage,1);eq(nextRow.resetEvidence,'matching-full-duration')
 end)
end

local invalid={
 {name='untimed',make=function()return untimed()end},
 {name='missing-duration',make=function()local a=untimed();a.expirationTime=120;return a end},
 {name='zero-duration',make=function()return T.aura(SPELL,1,100,0)end},
 {name='negative-duration',make=function()return T.aura(SPELL,1,100,-2)end},
 {name='NaN-duration',make=function()local a=T.aura(SPELL,1,100,20);a.duration=0/0;return a end},
 {name='infinite-duration',make=function()local a=T.aura(SPELL,1,100,20);a.duration=math.huge;return a end},
 {name='overlong-duration',make=function()return T.aura(SPELL,1,100,121)end},
 {name='future-start',make=function()return T.aura(SPELL,1,101,20)end},
 {name='stale-start',make=function()return T.aura(SPELL,1,90,20)end},
}
for _,kind in ipairs(invalid) do
 test('unusable aura interval does not veto '..kind.name,function()
  local e,ns=fresh();current(e,kind.make(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100)
  local initial=row(ns,100);eq(initial.stage,1);eq(initial.started,100)
  eq(initial.fullDurationBaseline,10,'only a coherent same-occurrence interval can veto')
  eq(state(ns).durationContext.initialAuraDuration,nil)
 end)
end

test('aura duration alone cannot teach a baseline',function()
 local e,ns=fresh();e.auras.target={T.aura(SPELL,1,100,20)};e.auras.focus={T.aura(SPELL,1,100,20)}
 ns.Observer.Scan(100);local initial=row(ns,100)
 eq(initial.stage,1);eq(initial.fullDurationBaseline,nil)
 eq(state(ns).durationContext.initialAuraDuration,20)
end)

test('explicit refresh cannot borrow predecessor aura duration',function()
 local e,ns=fresh()
 current(e,T.aura(SPELL,1,100,20),T.loc(SPELL,1,100,10));ns.Observer.Scan(100)
 poll(ns,100,110-.2)
 -- The aura still describes the predecessor when the next explicit start is
 -- read on the same native ID. Its duration cannot veto this new occurrence.
 current(e,T.aura(SPELL,1,100,20),T.loc(SPELL,1,110,5));ns.Observer.Scan(110)
 local refreshed=row(ns,110);eq(refreshed.stage,2);eq(refreshed.started,110)
 eq(state(ns).durationContext.initialAuraDuration,nil,'predecessor veto is not inherited')
 eq(state(ns).witness.expires,115,'explicit endpoint retains custody')
end)

test('current aura veto survives fallback identity reconciliation',function()
 local e,ns=fresh()
 local loc=T.loc(SPELL,nil,100,10)
 current(e,T.aura(SPELL,1,100,20),loc);ns.Observer.Scan(100)
 local initial=row(ns,100);eq(initial.stage,1);eq(initial.fullDurationBaseline,nil)
 eq(state(ns).durationContext.initialAuraDuration,20,'current native aura follows canonical identity')
end)

test('fallback refresh cannot borrow historical aura duration',function()
 local e,ns=fresh()
 current(e,T.aura(SPELL,1,100,20),T.loc(SPELL,nil,100,10));ns.Observer.Scan(100)
 poll(ns,100,110-.2)
 -- No current timed aura supports the refreshed fallback sample.
 current(e,untimed(),T.loc(SPELL,nil,110,5));ns.Observer.Scan(110)
 local refreshed=row(ns,110);eq(refreshed.stage,2);eq(refreshed.started,110)
 eq(state(ns).durationContext.initialAuraDuration,nil)
end)

for _,failure in ipairs(failures) do print('FAIL aura duration merge: '..failure) end
assert(#failures==0,tostring(#failures)..' aura duration merge case(s) failed')
print('Aura duration merge: '..cases..' cases / '..checks..' checks passed')
