-- A remaining-only LoC end cannot serve as the aura refresh endpoint.
-- Real Observer -> Model -> UI with the unchanged client-boundary fixture.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G='Player-Enemy'
local checks,groups,failures=0,{},{}
local function eq(a,b,label)
 checks=checks+1
 assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local function near(a,b,label)
 checks=checks+1
 assert(type(a)=='number' and math.abs(a-b)<1e-8,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local function test(name,fn)
 local ok,err=pcall(fn);groups[#groups+1]={name=name,ok=ok,error=not ok and tostring(err) or nil}
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fresh()
 local e,ns=T.fresh();e.identity.target=G;e.identity.focus=G
 ns.db={ownCastEstimates=false,aoeCastEstimates=false,categories={}}
 assert(loadfile(ADDON_DIR..'/UI.lua'))('test',ns)
 e.auras.target={T.aura(5211,1,10,3)};e.auras.focus={T.aura(5211,1,10,3)}
 ns.Observer.Scan(10.05)
 return e,ns
end
local function inputs(e,now,start,delta,explicit,auraEnd,complete)
 auraEnd=auraEnd or 13
 e.auras.target={{spellId=5211,auraInstanceID=1,isHarmful=true},secretAt=2}
 e.auras.focus={T.aura(5211,1,start,auraEnd-start)}
 if not complete then e.auras.focus.secretAt=2 end
 e.byloc.target={{spellID=5211,auraInstanceID=1,timeRemaining=auraEnd+delta-now}}
 if explicit then e.byloc.target={T.loc(5211,1,explicit,auraEnd+delta-explicit)} end
end
local function row(ns,now) return assert(ns.UI.GetRows('target',now)[1]) end
for _,delta in ipairs({.00075,-.00075,13.000000000000002-13,12.999999999999998-13}) do
 for _,complete in ipairs({false,true}) do
  test('duration-only correction delta='..delta..' complete='..tostring(complete),function()
   local e,ns=fresh()
   inputs(e,10.1,10,delta,nil,nil,complete);ns.Observer.Scan(10.1)
   inputs(e,10.3,10.2,-delta,nil,nil,complete);ns.Observer.Scan(10.3)
   eq(row(ns,10.3).observedStage,1,'fixed aura end is one observed application')
   near(row(ns,10.3).started,10,'duration correction retains known application start')
   if not complete then
    local fx=ns.model.units[G].effects['a:1']
    near(fx.expires,13-delta,'remaining-only LoC keeps reset endpoint')
    eq(fx.expirySource,'loc','reset endpoint keeps source');eq(fx.expiryAppliedAt,nil,'endpoint stays unbound')
    near(row(ns,10.3).stageResetAt,31-delta,'reset clock follows donor')
   end
   inputs(e,10.5,10.4,delta,nil,nil,complete);ns.Observer.Scan(10.5)
   eq(row(ns,10.5).observedStage,1,'second duration correction is not a refresh')
   e.byloc.target={};ns.Observer.Scan(10.7)
   eq(row(ns,10.7).observedStage,1,'donor loss is not a refresh');near(row(ns,10.7).started,10)
   eq(ns.Observer.stats.apiErrors,0);eq(ns.Observer.stats.scanGaps,0)
  end)
 end
end
test('real aura refresh remains visible through donor acquisition loss and stale replay',function()
 local e,ns=fresh()
 inputs(e,10.1,10,.00075);ns.Observer.Scan(10.1)
 inputs(e,10.3,10.2,-.00075,nil,13.2);ns.Observer.Scan(10.3)
 eq(row(ns,10.3).observedStage,2,'new aura start and end prove refresh');near(row(ns,10.3).started,10.2)
 e.byloc.target={};ns.Observer.Scan(10.5)
 eq(row(ns,10.5).observedStage,2,'donor loss preserves refresh')
 inputs(e,10.7,10,.00075);ns.Observer.Scan(10.7)
 eq(row(ns,10.7).observedStage,2,'old aura replay stays old');near(row(ns,10.7).started,10.2)
 inputs(e,10.9,10.2,-.00075,nil,13.2);ns.Observer.Scan(10.9)
 eq(row(ns,10.9).observedStage,2,'return from stale replay cannot count again')
 inputs(e,11.1,10.4,.00075,nil,13.4);ns.Observer.Scan(11.1)
 eq(row(ns,11.1).observedStage,3,'next genuine same-ID aura refresh remains visible');near(row(ns,11.1).started,10.4)
end)
test('explicit LoC clock retains refresh and endpoint authority',function()
 local e,ns=fresh()
 inputs(e,10.1,10,.00075,10);ns.Observer.Scan(10.1)
 inputs(e,10.3,10.2,-.00075,10);ns.Observer.Scan(10.3)
 eq(row(ns,10.3).observedStage,1);near(row(ns,10.3).started,10)
 inputs(e,10.5,10.2,.00075,10.4);ns.Observer.Scan(10.5)
 eq(row(ns,10.5).observedStage,2);near(row(ns,10.5).started,10.4)
 e.byloc.target={};ns.Observer.Scan(10.7)
 eq(row(ns,10.7).observedStage,2);near(row(ns,10.7).started,10.4)
end)
test('stable jitter retains bounded witness state',function()
 local e,ns=fresh()
 for i=1,1200 do
  local now=10.1+i*.002
  inputs(e,now,10,i%2==0 and .00075 or -.00075);ns.Observer.Scan(now)
 end
 eq(row(ns,12.5).observedStage,1);eq(T.count(ns.model.units[G].effects),1)
 eq(T.count(ns.Observer.units.target.witnesses),1);eq(T.count(ns.Observer.units.target.nativeIdentities),1)
 eq(ns.Observer.stats.apiErrors,0);eq(ns.Observer.stats.scanGaps,0)
 local c=ns.model.units[G].categories.stun
 eq(c.previousApplication and c.previousApplication.previousApplication,nil)
end)
TEST_RESULTS={checks=checks,groups=groups,failures=#failures}
assert(#failures==0,table.concat(failures,'\n'))
return TEST_RESULTS
