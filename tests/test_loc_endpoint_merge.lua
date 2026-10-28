-- Native LoC remaining time is positive endpoint evidence, not an application
-- start or full duration. Exercise the real Observer -> Model -> UI path.
local T=dofile((TEST_DIR or ADDON_DIR..'/tests')..'/timing_v16/support.lua')
local G='Player-Enemy'
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
 local e,ns=T.fresh();e.identity.target=G
 return e,ns
end
local function untimed(id,instance)
 return {spellId=id or 5211,auraInstanceID=instance or 1,isHarmful=true}
end
local function remaining(value,duration,id,instance)
 local loc=T.loc(id or 5211,instance or 1,nil,duration);loc.timeRemaining=value
 return loc
end
local function result(ns,guid)
 local actor=assert(ns.model.units[guid or G])
 return actor,assert(actor.categories.stun),assert(actor.effects['a:1'])
end

test('remaining-only collision resets before the next public application row',function()
 local e,ns=fresh()
 e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9,3)}
 ns.Observer.Scan(10.1)
 local _,cat,fx=result(ns)
 -- Keep the original snapshots so the public regression executes even if
 -- the initial end is lost. 13 + 18 = 31 is the known reset deadline.
 local initialExpiry,initialReset=fx.expires,cat.stageResetAt
 e.auras.target={secretAt=1};e.byloc.target={secret=true}
 for i=1,106 do ns.Observer.Scan(10.1+i*.2) end
 e.auras.target={T.aura(5211,2,31.4,3)};e.byloc.target={};ns.Observer.Scan(31.5)
 ns.db={ownCastEstimates=false,aoeCastEstimates=false,categories={}}
 assert(loadfile(ADDON_DIR..'/UI.lua'))('test',ns)
 local rows=ns.UI.GetRows('target',31.5)
 eq(#rows,1,'one public row');eq(rows[1].stage,1,'public stage after known reset')
 eq(initialExpiry,13,'initial endpoint');eq(initialReset,31,'initial reset')
 eq(rows[1].remaining,19.9,'application clock remains independent')
 eq(ns.Observer.stats.scanGaps,0,'no scan gaps');eq(ns.Observer.stats.apiErrors,0,'no API errors')
end)


local function capture(ns,guid)
 local seen={};local observe=ns.model.Observe
 ns.model.Observe=function(self,who,effects,now,complete,removed)
  if who==(guid or G) then seen.effects=effects end
  return observe(self,who,effects,now,complete,removed)
 end
 return seen
end
for _,secretTiming in ipairs({false,true}) do
 for _,rawDuration in ipairs({false,true}) do
  test('initial endpoint secret='..tostring(secretTiming)..' duration='..tostring(rawDuration),function()
   local e,ns=fresh();local seen=capture(ns)
   local a=untimed();local l=remaining(2.9,rawDuration and 3 or nil)
   if secretTiming then
    local hidden={};local sec,tab,acc=issecretvalue,issecrettable,canaccessvalue
    issecretvalue=function(v)return v==hidden or sec(v)end
    issecrettable=function(v)return v==hidden or tab(v)end
    canaccessvalue=function(v)return v~=hidden and acc(v)end
    a.duration=hidden;a.expirationTime=hidden;l.startTime=hidden
   end
   e.auras.target={a,secretAt=2};e.byloc.target={l};ns.Observer.Scan(10.1)
   local actor,cat,fx=result(ns);local raw=assert(seen.effects['a:1'])
   eq(fx.expires,13);eq(cat.stageResetAt,31);eq(fx.expirySource,'loc')
   eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil);eq(raw.reportedDuration,nil)
   eq(raw.applicationSource,nil);eq(cat.appliedAt,10.1);eq(cat.stage,1)
   eq(T.count(actor.effects),1);eq(ns.Observer.stats.apiErrors,0)
  end)
 end
end
for _,endpoint in ipairs({12,14}) do
 test('later endpoint '..endpoint..' corrects reset without another count',function()
  local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9)}
  ns.Observer.Scan(10.1);e.byloc.target={remaining(endpoint-10.3,3)};ns.Observer.Scan(10.3)
  local _,cat,fx=result(ns)
  eq(fx.expires,endpoint);eq(cat.stageResetAt,endpoint+18);eq(cat.stage,1)
  eq(cat.appliedAt,10.1);eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil)
  e.byloc.target={remaining(endpoint-10.5)};ns.Observer.Scan(10.5);eq(cat.stage,1)
 end)
end
for _,partial in ipairs({false,true}) do
 test('untimed same-GUID alias partial='..tostring(partial),function()
  local e,ns=fresh();e.identity.focus=G
  e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9)}
  e.auras.focus={untimed()};if partial then e.auras.focus.secretAt=2 end
  ns.Observer.Scan(10.1);local actor,cat,fx=result(ns)
  eq(fx.expires,13);eq(fx.expirySource,'loc');eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil)
  eq(cat.stage,1);eq(T.count(actor.effects),1)
  if not partial then eq(ns.Observer.GetUnitState('target').authoritativeUnit,'focus') end
 end)
end
for _,kind in ipairs({'untimed-conflict','timed-conflict','matching-unbound','alias-conflict'}) do
 test('existing aura endpoint '..kind,function()
  local e,ns=fresh();local aura=untimed()
  aura.expirationTime=kind=='matching-unbound' and 13 or 14
  if kind=='timed-conflict' then aura.duration=4 end
  e.auras.target={aura,secretAt=2};e.byloc.target={remaining(2.9)}
  if kind=='alias-conflict' then e.identity.focus=G;e.auras.focus={aura};e.auras.target={untimed(),secretAt=2} end
  ns.Observer.Scan(10.1);local _,cat,fx=result(ns)
  eq(fx.expires,kind=='matching-unbound' and 13 or 14)
  eq(fx.appliedAt,kind=='timed-conflict' and 10 or nil)
  eq(fx.expiryAppliedAt,kind=='timed-conflict' and 10 or nil)
  eq(fx.expirySource,'aura','existing endpoint keeps its source')
  eq(cat.stage,1)
 end)
end
for _,spell in ipairs({408,339}) do
 test('same native number rejects another spell '..spell,function()
  local e,ns=fresh();e.auras.target={untimed(),secretAt=2}
  e.byloc.target={remaining(2.9,nil,spell)};ns.Observer.Scan(10.1)
  local actor,cat,fx=result(ns);eq(fx.spellID,5211);eq(fx.expires,nil)
  eq(cat.stage,1);eq(T.count(actor.effects),1)
 end)
end
test('different native instance stays separate',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9,nil,5211,2)}
 ns.Observer.Scan(10.1);local actor,_,fx=result(ns)
 eq(fx.expires,nil);eq(actor.effects['a:2'].expires,13);eq(T.count(actor.effects),2)
end)
test('different GUID cannot donate an endpoint',function()
 local e,ns=fresh();e.identity.focus='Player-Other'
 e.auras.target={untimed(),secretAt=2};e.auras.focus={secretAt=1};e.byloc.focus={remaining(2.9)}
 ns.Observer.Scan(10.1);local _,_,fx=result(ns)
 eq(fx.expires,nil);eq(ns.model.units['Player-Other'].effects['a:1'].expires,13)
end)
test('remaining time without native identity cannot join an aura',function()
 local e,ns=fresh();local l=remaining(2.9);l.auraInstanceID=nil
 e.auras.target={untimed(),secretAt=2};e.byloc.target={l};ns.Observer.Scan(10.1)
 local actor,_,fx=result(ns);eq(fx.expires,nil);eq(T.count(actor.effects),1)
end)
for _,source in ipairs({'ordinary','byunit'}) do
 test('player '..source..' collision and removal authority',function()
  local e,ns=fresh();local self='Player-Self';local seen=capture(ns,self)
  e.auras.player={untimed(),secretAt=2}
  if source=='ordinary' then e.loc={remaining(2.9,3)} else e.byloc.player={remaining(2.9,3)} end
  ns.Observer.Scan(10.1);local _,cat,fx=result(ns,self)
  eq(fx.expires,13);eq(cat.stageResetAt,31);eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil)
  eq(seen.effects['a:1'].reportedDuration,nil)
  e.auras.player={secretAt=1};e.loc={};e.byloc.player={};ns.Observer.Scan(10.3)
  local actor=ns.model.units[self]
  eq(actor.categories.stun.stageResetAt,source=='ordinary' and 28.3 or 31)
  eq(T.count(actor.effects),source=='ordinary' and 0 or 1)
 end)
end
test('remaining endpoint cannot correct accepted explicit endpoint',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={T.loc(5211,1,10,3)}
 ns.Observer.Scan(10.1);local _,_,initial=result(ns);eq(initial.expires,13);eq(initial.expiryAppliedAt,10)
 e.byloc.target={remaining(1.7)};ns.Observer.Scan(10.3)
 local _,cat,fx=result(ns);eq(fx.appliedAt,10);eq(fx.expires,13);eq(fx.expiryAppliedAt,10);eq(cat.stage,1)
end)
test('first explicit start never binds old remaining endpoint and refresh discards it',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9,3)}
 ns.Observer.Scan(10.1);e.byloc.target={T.loc(5211,1,10,nil)};ns.Observer.Scan(10.3)
 local _,cat,fx=result(ns);eq(fx.appliedAt,10);eq(fx.expires,13);eq(fx.expiryAppliedAt,nil)
 eq(fx.expirySource,'loc');eq(cat.stage,1)
 e.byloc.target={T.loc(5211,1,10.4,nil)};ns.Observer.Scan(10.5)
 local _,newCat,newFx=result(ns);eq(newCat.stage,2);eq(newFx.appliedAt,10.4)
 eq(newFx.expires,nil);eq(newFx.expiryAppliedAt,nil)
end)
test('unbound parallel LoC end cannot attach to explicit current occurrence',function()
 local e,ns=fresh();e.loc={T.loc(5211,1,10,nil)};e.byloc.player={remaining(2.9)}
 local fx=assert(ns.Observer.ReadPlayerLoCEffects(10.1)['a:1'])
 eq(fx.appliedAt,10);eq(fx.expires,nil);eq(fx.expiryAppliedAt,nil);eq(fx.reportedDuration,nil)
end)
test('stale parallel explicit donor cannot rewind current occurrence',function()
 local e,ns=fresh();e.loc={T.loc(5211,1,10.4,nil)}
 local stale=T.loc(5211,1,10,nil);stale.timeRemaining=2.5;e.byloc.player={stale}
 local fx=assert(ns.Observer.ReadPlayerLoCEffects(10.5)['a:1'])
 eq(fx.appliedAt,10.4);eq(fx.expires,nil);eq(fx.expiryAppliedAt,nil)
end)
test('proved refresh rejects a merged unbound end from another player source',function()
 local e,ns=fresh();e.auras.player={secretAt=1};e.loc={T.loc(5211,1,10,3)}
 ns.Observer.Scan(10.1)
 e.loc={remaining(2.7)};e.byloc.player={T.loc(5211,1,10.4,nil)};ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns,'Player-Self');eq(cat.stage,2);eq(fx.appliedAt,10.4);eq(fx.expires,nil)
 eq(fx.expiryAppliedAt,nil)
end)
test('complete absence then a new native occurrence counts once',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(2.9)}
 ns.Observer.Scan(10.1);e.auras.target={};e.byloc.target={};ns.Observer.Scan(10.3)
 local actor=ns.model.units[G];eq(actor.categories.stun.stageResetAt,28.3);eq(T.count(actor.effects),0)
 e.auras.target={untimed(5211,2),secretAt=2};e.byloc.target={remaining(2.5,nil,5211,2)}
 ns.Observer.Scan(10.5);ns.Observer.Scan(10.7);eq(actor.categories.stun.stage,2);eq(T.count(actor.effects),1)
end)
test('stale explicit replay cannot contaminate refreshed unknown endpoint',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={T.loc(5211,1,10,3)}
 ns.Observer.Scan(10.1);e.byloc.target={T.loc(5211,1,10.4,nil)};ns.Observer.Scan(10.5)
 local stale=T.loc(5211,1,10,nil);stale.timeRemaining=2.3;e.byloc.target={stale};ns.Observer.Scan(10.7)
 local _,cat,fx=result(ns);eq(cat.stage,2);eq(fx.appliedAt,10.4);eq(fx.expires,nil);eq(fx.expiryAppliedAt,nil)
end)
test('repeated readings keep one occurrence and bounded witness state',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2}
 for i=1,300 do local now=10+i*.1;e.byloc.target={remaining(50-now)};ns.Observer.Scan(now) end
 local actor,cat,fx=result(ns);eq(cat.stage,1);eq(cat.appliedAt,10.1);eq(fx.expires,50)
 eq(fx.appliedAt,nil);eq(fx.expiryAppliedAt,nil);eq(T.count(actor.effects),1)
 eq(T.count(ns.Observer.units.target.witnesses),1);eq(T.count(ns.Observer.guidContexts),2)
 eq(ns.Observer.stats.apiErrors,0);eq(ns.Observer.stats.scanGaps,0)
end)
test('many witnesses retain existing effect cap',function()
 local e,ns=fresh();e.auras.target={secretAt=1}
 for batch=0,3 do
  e.byloc.target={};for i=1,255 do e.byloc.target[i]=remaining(100,nil,5211,batch*255+i) end
  ns.Observer.Scan(10.1+batch*.2)
 end
 eq(T.count(ns.model.units[G].effects),512);eq(T.count(ns.Observer.units.target.witnesses),512)
end)
test('many actors retain existing actor cap',function()
 local e,ns=fresh();e.auras.target={untimed(),secretAt=2};e.byloc.target={remaining(100)}
 for i=1,140 do e.identity.target='Player-Enemy-'..i;ns.Observer.Scan(10+i*.2) end
 eq(T.count(ns.model.units),128);eq(T.count(ns.Observer.guidContexts),128)
end)

for _,failure in ipairs(failures) do print('FAIL LoC endpoint merge: '..failure) end
assert(#failures==0,tostring(#failures)..' LoC endpoint merge case(s) failed')
print('LoC endpoint merge: '..cases..' cases / '..checks..' checks passed')
