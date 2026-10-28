-- Endpoint rounding must not hide a real application or manufacture LoC authority.
-- Exact-equality merge checks lose the readable start in these real sensor paths.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G='Player-Enemy'
local cases,checks,failures=0,0,{}
local function eq(a,b,label)
 checks=checks+1
 assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local function near(a,b,label)
 checks=checks+1
 assert(type(a)=='number' and math.abs(a-b)<1e-10,
  (label or 'clock')..': expected '..tostring(b)..', got '..tostring(a))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function fresh()
 local e,ns=T.fresh();e.identity.target=G;e.identity.focus=G
 ns.db={ownCastEstimates=false,aoeCastEstimates=false,categories={}}
 assert(loadfile(ADDON_DIR..'/UI.lua'))('test',ns)
 local seen={};local observe=ns.model.Observe
 ns.model.Observe=function(self,guid,effects,...)
  if guid==G then seen.effects=effects end
  return observe(self,guid,effects,...)
 end
 return e,ns,seen
end
local function weak(secretTiming)
 local a={spellId=5211,auraInstanceID=1,isHarmful=true}
 local l={spellID=5211,auraInstanceID=1}
 if secretTiming then
  local hidden={};local sec,tab,acc=issecretvalue,issecrettable,canaccessvalue
  issecretvalue=function(v)return v==hidden or sec(v)end
  issecrettable=function(v)return v==hidden or tab(v)end
  canaccessvalue=function(v)return v~=hidden and acc(v)end
  a.expirationTime=hidden;a.duration=hidden;l.startTime=hidden;l.duration=hidden
 end
 return a,l
end
local function inputs(e,now,start,auraEnd,locEnd,secretTiming)
 local a,l=weak(secretTiming);l.timeRemaining=locEnd-now
 local timed=T.aura(5211,1,start,auraEnd-start);timed.expirationTime=auraEnd
 e.auras.target={a,secretAt=2};e.byloc.target={l}
 e.auras.focus={timed,secretAt=2}
 return l,timed
end
local function result(ns)
 local actor=assert(ns.model.units[G])
 return actor,assert(actor.categories.stun),assert(actor.effects['a:1'])
end
local function clean(ns)
 eq(ns.Observer.stats.apiErrors,0,'API errors');eq(ns.Observer.stats.scanGaps,0,'scan gaps')
end
local function initial(e,ns)
 e.auras.target={T.aura(5211,1,10,3)};e.auras.focus={T.aura(5211,1,10,3)}
 for i=0,9 do ns.Observer.Scan(10.1+i*.2) end
end
for _,delta in ipairs({0,2^-49,-2^-49,.0001,-.0001}) do
 for _,secretTiming in ipairs({false,true}) do
  test('refresh endpoint delta='..delta..' secret='..tostring(secretTiming),function()
   local e,ns,seen=fresh();initial(e,ns)
   local l=inputs(e,12.13,11.51,13.01,13.01+delta,secretTiming)
   ns.Observer.Scan(12.13)
   local actor,cat,fx=result(ns);local raw=assert(seen.effects['a:1'])
   eq(cat.stage,2,'refresh stage');near(fx.appliedAt,11.51,'readable aura start')
   eq(raw.expires,12.13+l.timeRemaining,'original LoC endpoint')
   eq(raw.expirySource,'loc');eq(raw.expiryAppliedAt,nil,'LoC endpoint stays unbound')
   eq(raw.applicationSource,'aura');eq(raw.reportedDuration,nil)
   eq(ns.UI.GetRows('target',12.13)[1].stage,2,'public refresh')
   e.byloc.target={};ns.Observer.Scan(12.33)
   eq(cat.stage,2,'donor loss');eq(ns.UI.GetRows('target',12.33)[1].stage,2,'public donor loss')
   near(actor.effects['a:1'].appliedAt,11.51);eq(T.count(actor.effects),1);clean(ns)
  end)
 end
end
test('ordinary computed decimal retains start and stage after donor loss',function()
 local e,ns,seen=fresh();initial(e,ns)
 local l=inputs(e,12.13,11.51,13.01,13.01,false);l.timeRemaining=.88
 eq(12.13+.88==13.01,false,'fixture has distinct binary endpoints')
 ns.Observer.Scan(12.13);local _,cat,fx=result(ns)
 eq(cat.stage,2);near(fx.appliedAt,11.51);eq(seen.effects['a:1'].expires,12.13+.88)
 eq(seen.effects['a:1'].expirySource,'loc');eq(seen.effects['a:1'].expiryAppliedAt,nil)
 e.byloc.target={};ns.Observer.Scan(12.33)
 eq(ns.UI.GetRows('target',12.33)[1].stage,2);eq(cat.stage,2);clean(ns)
end)
-- .002-.001 is exactly the same represented value as the .001 tolerance.
-- Small positive clocks let both exact tolerance edges be exercised without
-- a large-clock subtraction rounding the boundary to its adjacent float.
for _,row in ipairs({
 {name='positive boundary',a=.001,l=.002,start=.00025,now=.0005,want=true},
 {name='negative boundary',a=.002,l=.001,start=.00025,now=.0005,want=true},
 {name='positive outside',a=.001,l=.0020000000000000005,start=.00025,now=.0005,want=false},
 {name='negative outside',a=.0020000000000000005,l=.001,start=.00025,now=.0005,want=false},
 {name='material conflict',a=13.01,l=13.02,start=11.51,now=12.13,want=false},
}) do
 test(row.name,function()
  local e,ns,seen=fresh();inputs(e,row.now,row.start,row.a,row.l,false);ns.Observer.Scan(row.now)
  local _,cat,fx=result(ns);eq(cat.stage,1)
  if row.want then near(fx.appliedAt,row.start);eq(fx.applicationSource,'aura')
  else eq(fx.appliedAt,nil,'conflicting endpoint cannot donate a start') end
  eq(seen.effects['a:1'].expires,row.now+(row.l-row.now));eq(seen.effects['a:1'].expirySource,'loc')
  eq(seen.effects['a:1'].expiryAppliedAt,nil);clean(ns)
 end)
end
for _,delta in ipairs({.0001,-.0001}) do
 test('explicit LoC authority delta='..delta,function()
  local e,ns,seen=fresh();inputs(e,12.13,11.51,13.01,13.01+delta,false)
  e.byloc.target={T.loc(5211,1,11.7,1.31+delta)};ns.Observer.Scan(12.13)
  local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,11.7);eq(fx.applicationSource,'loc')
  eq(seen.effects['a:1'].expiryAppliedAt,11.7);clean(ns)
 end)
end
for _,timing in ipairs({'missing-duration','secret-duration','missing-end','secret-end'}) do
 test('unreadable aura '..timing,function()
  local e,ns=fresh();local _,a=inputs(e,12.13,11.51,13.01,13.0101,true)
  if timing=='missing-duration' then a.duration=nil
  elseif timing=='missing-end' then a.expirationTime=nil
  else
   local hidden={};local sec=issecretvalue
   issecretvalue=function(v)return v==hidden or sec(v)end
   if timing=='secret-duration' then a.duration=hidden else a.expirationTime=hidden end
  end
  ns.Observer.Scan(12.13);local _,_,fx=result(ns);eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil);clean(ns)
 end)
end
for _,mismatch in ipairs({'spell','category','instance','guid'}) do
 test('near endpoints cannot cross '..mismatch,function()
  local e,ns=fresh();local _,a=inputs(e,12.13,11.51,13.01,13.0101,false)
  if mismatch=='spell' then a.spellId=408 elseif mismatch=='category' then a.spellId=339
  elseif mismatch=='instance' then a.auraInstanceID=2 else e.identity.focus='Player-Other' end
  ns.Observer.Scan(12.13);local _,_,fx=result(ns);eq(fx.appliedAt,nil);eq(fx.spellID,5211);clean(ns)
 end)
end
test('reversed source order preserves aura endpoint and bound provenance',function()
 local e,ns,seen=fresh();local l,a=inputs(e,12.13,11.51,13.01,13.0101,true)
 local weakAura=e.auras.target[1];e.auras.target={a,secretAt=2};e.auras.focus={weakAura,secretAt=2}
 ns.Observer.Scan(12.13);local _,_,fx=result(ns);near(fx.appliedAt,11.51)
 eq(seen.effects['a:1'].expires,13.01);eq(seen.effects['a:1'].expirySource,'aura')
 near(seen.effects['a:1'].expiryAppliedAt,11.51);clean(ns)
end)
test('stale readable alias cannot rewind recovered refresh',function()
 local e,ns=fresh();initial(e,ns)
 inputs(e,12.13,11.51,13.01,13.0101,false);ns.Observer.Scan(12.13)
 inputs(e,12.33,10,13,13.0001,false);ns.Observer.Scan(12.33)
 local _,cat,fx=result(ns);eq(cat.stage,2);near(fx.appliedAt,11.51)
 e.byloc.target={};ns.Observer.Scan(12.53);eq(cat.stage,2);near(fx.appliedAt,11.51);clean(ns)
end)
test('first clock calibrates once and repeated refresh readings stay bounded',function()
 local e,ns=fresh();local a,l=weak(true);l.timeRemaining=2.9
 e.auras.target={a,secretAt=2};e.byloc.target={l};e.auras.focus={a,secretAt=2};ns.Observer.Scan(10.1)
 inputs(e,10.3,10,13,13.0001,true);ns.Observer.Scan(10.3)
 local actor,cat,fx=result(ns);eq(cat.stage,1);near(fx.appliedAt,10)
 for i=1,250 do
  local now=10.3+i*.005
  inputs(e,now,10,13,13.0001,i%2==0);ns.Observer.Scan(now)
 end
 eq(cat.stage,1);eq(T.count(actor.effects),1);eq(T.count(ns.Observer.units.target.witnesses),1)
 inputs(e,11.6,11.5,13.2,13.2001,true);ns.Observer.Scan(11.6);eq(cat.stage,2)
 for i=1,200 do
  local now=11.6+i*.005
  inputs(e,now,11.5,13.2,13.2001,i%2==0);ns.Observer.Scan(now)
 end
 eq(cat.stage,2);eq(T.count(actor.effects),1);eq(T.count(ns.Observer.units.target.witnesses),1)
 eq(T.count(ns.Observer.guidContexts),2);clean(ns)
end)
for _,failure in ipairs(failures) do print('FAIL alias endpoint precision: '..failure) end
assert(#failures==0,tostring(#failures)..' alias endpoint precision case(s) failed')
print('alias endpoint precision: '..cases..' cases / '..checks..' checks passed')
