-- Matching-end aliases may recover application timing without binding a LoC end.
local T=dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
local G='Player-Enemy'
local cases,checks,failures=0,0,{}
local function eq(a,b,label)
 checks=checks+1
 assert(type(a)=='number' and type(b)=='number' and math.abs(a-b)<.000001 or a==b,
  (label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
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
local function weak(id,secretTiming)
 local a={spellId=id,auraInstanceID=1,isHarmful=true};local l={spellID=id,auraInstanceID=1}
 if secretTiming then
  local hidden={};local sec,tab,acc=issecretvalue,issecrettable,canaccessvalue
  issecretvalue=function(v)return v==hidden or sec(v)end
  issecrettable=function(v)return v==hidden or tab(v)end
  canaccessvalue=function(v)return v~=hidden and acc(v)end
  a.expirationTime=hidden;a.duration=hidden;l.startTime=hidden;l.duration=hidden
 end
 return a,l
end
local function inputs(e,id,transport,partial,secretTiming,start,endpoint,now)
 local a,l=weak(id,secretTiming);l.timeRemaining=endpoint-now
 e.auras.target={a,secretAt=2};e.exact.target={}
 if transport=='exact' then e.auras.target={secretAt=1};e.exact.target[id]=a end
 e.byloc.target={l};e.auras.focus={T.aura(id,1,start,endpoint-start)}
 if partial then e.auras.focus.secretAt=2 end
end
local function result(ns)
 local actor=assert(ns.model.units[G])
 return actor,assert(actor.categories.stun),assert(actor.effects['a:1'])
end
local function clean(ns)
 eq(ns.Observer.stats.apiErrors,0,'API errors');eq(ns.Observer.stats.scanGaps,0,'scan gaps')
end

-- Catches the .35 loc-source veto: a positive start is discarded on a partial alias.
for _,transport in ipairs({'indexed','exact'}) do
 for _,partial in ipairs({true,false}) do
  for _,secretTiming in ipairs({false,true}) do
   for _,sequence in ipairs({'first-calibration','refresh','duration-correction'}) do
    test(transport..'/partial='..tostring(partial)..'/secret='..tostring(secretTiming)..'/'..sequence,function()
     local e,ns,seen=fresh();local id=transport=='exact' and 20549 or 5211
     if sequence~='first-calibration' then
      e.auras.target={T.aura(id,1,10,3)};e.auras.focus={T.aura(id,1,10,3)};ns.Observer.Scan(10.1)
     end
     local start=sequence=='refresh' and 10.4 or 10
     local endpoint=sequence=='refresh' and 11.9 or sequence=='duration-correction' and 12 or 13
     inputs(e,id,transport,partial,secretTiming,start,endpoint,10.5);ns.Observer.Scan(10.5)
     local actor,cat,fx=result(ns);local raw=assert(seen.effects['a:1'])
     eq(cat.stage,sequence=='refresh' and 2 or 1,'stage');eq(fx.appliedAt,start,'application start')
     eq(fx.applicationSource,'aura','application source');eq(fx.expires,endpoint,'endpoint')
     if partial then eq(raw.expirySource,'loc','original endpoint source');eq(raw.expiryAppliedAt,nil,'unbound endpoint')
     else eq(raw.expirySource,'aura');eq(raw.expiryAppliedAt,start) end
     eq(raw.reportedDuration,nil,'remaining LoC never manufactures duration');eq(T.count(actor.effects),1)
     if not partial then eq(ns.Observer.GetUnitState('target').authoritativeUnit,'focus') end
     inputs(e,id,transport,partial,secretTiming,start,endpoint,10.7);ns.Observer.Scan(10.7)
     eq(cat.stage,sequence=='refresh' and 2 or 1,'repeat')
     e.byloc.target={};ns.Observer.Scan(10.9)
     eq(cat.stage,sequence=='refresh' and 2 or 1,'LoC donor gone')
     eq(ns.UI.GetRows('target',10.9)[1].stage,sequence=='refresh' and 2 or 1,'public stage');clean(ns)
    end)
   end
  end
 end
end
for _,secretTiming in ipairs({false,true}) do
 test('public late refresh survives donor loss secret='..tostring(secretTiming),function()
  local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3)};e.auras.focus={T.aura(5211,1,10,3)}
  for i=0,9 do ns.Observer.Scan(10.1+i*.2) end
  inputs(e,5211,'indexed',true,secretTiming,12,13.5,12.1);ns.Observer.Scan(12.1)
  local before=ns.UI.GetRows('target',12.1)[1]
  e.byloc.target={};ns.Observer.Scan(12.3)
  local after=ns.UI.GetRows('target',12.3)[1];local _,cat,fx=result(ns)
  eq(before.stage,2,'public refresh');eq(after.stage,2,'public donor-loss recovery')
  eq(before.remaining,19.9);eq(after.remaining,19.7);eq(cat.stage,2);eq(fx.appliedAt,12);eq(fx.expires,13.5);clean(ns)
 end)
end
test('late first clock calibrates one occurrence without recount',function()
 local e,ns,seen=fresh();local a,l=weak(5211);l.timeRemaining=2.9
 e.auras.target={a,secretAt=2};e.auras.focus={a,secretAt=2};e.byloc.target={l};ns.Observer.Scan(10.1)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,nil)
 inputs(e,5211,'indexed',true,false,10,13,10.3);ns.Observer.Scan(10.3)
 local _,currentCat,currentFx=result(ns);eq(currentCat.stage,1);eq(currentCat.appliedAt,10);eq(currentFx.appliedAt,10)
 eq(seen.effects['a:1'].expirySource,'loc');eq(seen.effects['a:1'].expiryAppliedAt,nil);clean(ns)
end)
for _,explicit in ipairs({false,true}) do
 test('conflicting endpoint retains clock explicit='..tostring(explicit),function()
  local e,ns,seen=fresh();inputs(e,5211,'indexed',true,false,10,13,10.5)
  if explicit then e.byloc.target={T.loc(5211,1,10.2,1.8)} else e.byloc.target[1].timeRemaining=1.5 end
  ns.Observer.Scan(10.5);local _,cat,fx=result(ns)
  eq(cat.stage,1);eq(fx.expires,12)
  if explicit then eq(fx.appliedAt,10.2);eq(fx.applicationSource,'loc');eq(seen.effects['a:1'].expiryAppliedAt,10.2)
  else eq(fx.appliedAt,nil);eq(fx.applicationSource,nil);eq(seen.effects['a:1'].expiryAppliedAt,nil) end
  eq(seen.effects['a:1'].expirySource,'loc');clean(ns)
 end)
end
test('matching endpoint never weakens explicit LoC clock',function()
 local e,ns,seen=fresh();inputs(e,5211,'indexed',true,false,10,13,10.5)
 e.byloc.target={T.loc(5211,1,10.2,2.8)};ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10.2);eq(fx.applicationSource,'loc')
 eq(seen.effects['a:1'].expiryAppliedAt,10.2);clean(ns)
end)
test('matching endpoint without readable duration cannot synthesize start',function()
 local e,ns,seen=fresh();inputs(e,5211,'indexed',true,true,10,13,10.5)
 local a=weak(5211,true);a.expirationTime=13;e.auras.focus={a,secretAt=2};ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,nil);eq(fx.expires,13)
 eq(seen.effects['a:1'].expiryAppliedAt,nil);clean(ns)
end)
for _,mismatch in ipairs({'spell','category','instance','guid'}) do
 test('alias cannot donate across '..mismatch..' mismatch',function()
  local e,ns,seen=fresh();inputs(e,5211,'indexed',true,false,10,13,10.5)
  if mismatch=='spell' then e.auras.focus[1].spellId=408
  elseif mismatch=='category' then e.auras.focus[1].spellId=339
  elseif mismatch=='instance' then e.auras.focus[1].auraInstanceID=2
  else e.identity.focus='Player-Other' end
  ns.Observer.Scan(10.5);local _,_,fx=result(ns)
  eq(fx.spellID,5211);eq(fx.appliedAt,nil);eq(fx.expires,13);eq(seen.effects['a:1'].expiryAppliedAt,nil);clean(ns)
 end)
end
test('reverse alias order retains timed aura endpoint',function()
 local e,ns,seen=fresh();local a,l=weak(5211,true);l.timeRemaining=2.5
 e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.byloc.target={l};e.auras.focus={a,secretAt=2};ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,13)
 eq(seen.effects['a:1'].expirySource,'aura');eq(seen.effects['a:1'].expiryAppliedAt,10);clean(ns)
end)
test('stale alias cannot rewind recovered refresh',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3)};e.auras.focus={T.aura(5211,1,10,3)};ns.Observer.Scan(10.1)
 inputs(e,5211,'indexed',true,false,10.4,11.9,10.5);ns.Observer.Scan(10.5)
 inputs(e,5211,'indexed',true,false,10,13,10.7);ns.Observer.Scan(10.7)
 local _,cat,fx=result(ns);eq(cat.stage,2);eq(fx.appliedAt,10.4);eq(fx.expires,11.9)
 inputs(e,5211,'indexed',true,false,10.4,11.9,10.9);ns.Observer.Scan(10.9)
 eq(cat.stage,2);eq(fx.appliedAt,10.4);clean(ns)
end)
test('complete absence removes recovered occurrence and new identity counts once',function()
 local e,ns=fresh();inputs(e,5211,'indexed',true,false,10,13,10.1);ns.Observer.Scan(10.1)
 e.auras.target={};e.auras.focus={};e.byloc.target={};ns.Observer.Scan(10.3)
 local actor=ns.model.units[G];eq(T.count(actor.effects),0);eq(actor.categories.stun.stageResetAt,28.3)
 e.auras.target={T.aura(5211,2,10.4,1.5)};e.auras.focus={};ns.Observer.Scan(10.5)
 eq(actor.categories.stun.stage,2);eq(T.count(actor.effects),1);clean(ns)
end)
test('repeated matching enrichment retains bounded identity history',function()
 local e,ns=fresh()
 for i=1,300 do local now=10+i*.1;inputs(e,5211,'indexed',true,false,10,50,now);ns.Observer.Scan(now) end
 local actor,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,50)
 eq(T.count(actor.effects),1);eq(T.count(ns.Observer.units.target.witnesses),1)
 eq(T.count(ns.Observer.guidContexts),2);clean(ns)
end)
for _,failure in ipairs(failures) do print('FAIL alias LoC timing: '..failure) end
assert(#failures==0,tostring(#failures)..' alias LoC timing case(s) failed')
print('alias LoC timing: '..cases..' cases / '..checks..' checks passed')
