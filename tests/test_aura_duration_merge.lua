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

-- LoC may reveal its start before either sensor reveals duration. A later
-- complete aura scan bypasses LoC, so its first interval must survive until
-- the first raw LoC duration, without acquiring LoC clock/endpoint authority.
local function startOnly(remaining)
 local e,ns=fresh();local hidden={}
 local wasSecret,wasAccessible=issecretvalue,canaccessvalue
 issecretvalue=function(v)return v==hidden or wasSecret(v)end
 canaccessvalue=function(v)return v~=hidden and wasAccessible(v)end
 local function hiddenAura()
  local a=untimed();a.duration=hidden;a.expirationTime=hidden;return a
 end
 local loc=T.loc(SPELL,1,100,hidden);loc.timeRemaining=remaining or hidden
 current(e,hiddenAura(),loc);ns.Observer.Scan(100)
 eq(state(ns).reportedDurationWitness,nil,'first raw duration is unreadable')
 eq(row(ns,100).fullDurationBaseline,nil)
 return e,ns,hiddenAura
end
local function auraOnly(e,ns,start,duration,now)
 e.auras.target={T.aura(SPELL,1,start,duration)}
 e.auras.focus={T.aura(SPELL,1,start,duration)}
 e.byloc.target={};ns.Observer.Scan(now)
end

for _,duration in ipairs({20,10}) do
 for _,knownEnd in ipairs({false,true}) do
  test('separate late aura '..duration..' known LoC end='..tostring(knownEnd),function()
   local e,ns,hiddenAura=startOnly(knownEnd and 15 or nil)
   auraOnly(e,ns,100,duration,100.2)
   eq(row(ns,100.2).started,100,'accepted LoC start remains fixed')
   eq(state(ns).witness.applicationSource,'loc','LoC retains clock authority')
   if knownEnd then
    eq(state(ns).witness.expires,115,'aura cannot replace accepted LoC end')
    eq(state(ns).witness.expirySource,'loc')
   end
   eq(row(ns,100.2).fullDurationBaseline,nil,'aura alone never teaches full duration')
   eq(state(ns).reportedDurationWitness,nil)
   current(e,hiddenAura(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100.4)
   eq(state(ns).witness.expires,110,'readable same-start LoC can correct its end')
   eq(row(ns,100.4).fullDurationBaseline,duration==10 and 10 or nil,'first aura interval governs learning veto')
   local nextRow=successor(e,ns,100.4,110,125.5)
   eq(nextRow.stage,duration==10 and 1 or 2,'late conflict cannot authorize early reset')
   eq(nextRow.resetEvidence,duration==10 and 'matching-full-duration' or nil)
  end)
 end
end

for _,firstDuration in ipairs({20,10}) do
 test('first separate late aura interval stays frozen '..firstDuration,function()
  local e,ns,hiddenAura=startOnly()
  auraOnly(e,ns,100,firstDuration,100.2)
  auraOnly(e,ns,100,30-firstDuration,100.3)
  current(e,hiddenAura(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100.4)
  local nextRow=successor(e,ns,100.4,110,125.5)
  eq(nextRow.stage,firstDuration==10 and 1 or 2,'later aura interval cannot replace first veto')
  eq(nextRow.resetEvidence,firstDuration==10 and 'matching-full-duration' or nil)
 end)
end

for _,start in ipairs({90,100.1}) do
 test('separate aura with mismatched start cannot veto '..start,function()
  local e,ns,hiddenAura=startOnly(15)
  auraOnly(e,ns,start,20,100.2)
  eq(row(ns,100.2).started,100);eq(state(ns).witness.expires,115)
  eq(state(ns).durationContext.initialAuraDuration,nil,'interval is not bound to accepted occurrence')
  current(e,hiddenAura(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100.4)
  eq(row(ns,100.4).fullDurationBaseline,10)
  eq(successor(e,ns,100.4,110,125.5).stage,1)
 end)
end

test('aura after first accepted raw duration cannot reopen the decision',function()
 local e,ns=fresh();current(e,untimed(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100)
 eq(row(ns,100).fullDurationBaseline,10);eq(state(ns).reportedDurationWitness,10)
 auraOnly(e,ns,100,20,100.2)
 eq(state(ns).witness.expires,110);eq(row(ns,100.2).started,100)
 eq(state(ns).durationContext.initialAuraDuration,nil,'consumed duration decision stays frozen')
 current(e,T.aura(SPELL,1,100,20),T.loc(SPELL,1,100,10));ns.Observer.Scan(100.4)
 eq(state(ns).durationContext.initialAuraDuration,nil,'merged later aura cannot reopen decision either')
 eq(row(ns,100.4).fullDurationBaseline,10)
 eq(successor(e,ns,100.4,110,125.5).stage,1)
end)

test('separate predecessor aura cannot veto a start-only explicit refresh',function()
 local e,ns,hiddenAura=startOnly(10)
 current(e,hiddenAura(),T.loc(SPELL,1,100,10));ns.Observer.Scan(100.2)
 poll(ns,100.2,109.8)
 local loc=T.loc(SPELL,1,110,nil);loc.timeRemaining=5
 current(e,hiddenAura(),loc);ns.Observer.Scan(110)
 eq(row(ns,110).stage,2);eq(row(ns,110).started,110)
 auraOnly(e,ns,100,20,110.2)
 eq(state(ns).durationContext.initialAuraDuration,nil,'old occurrence cannot supply new veto')
 eq(row(ns,110.2).started,110);eq(state(ns).witness.expires,115)
 current(e,hiddenAura(),T.loc(SPELL,1,110,5));ns.Observer.Scan(110.4)
 eq(row(ns,110.4).stage,2);eq(row(ns,110.4).fullDurationBaseline,10)
 eq(ns.Observer.stats.scanGaps,0);eq(ns.Observer.stats.apiErrors,0)
end)

for _,failure in ipairs(failures) do print('FAIL aura duration merge: '..failure) end
assert(#failures==0,tostring(#failures)..' aura duration merge case(s) failed')
print('Aura duration merge: '..cases..' cases / '..checks..' checks passed')
