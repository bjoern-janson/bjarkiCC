-- Same-key alias timing must preserve readable positive evidence without
-- synthesizing a start/end pair from contradictory observations.
local T=dofile(ADDON_DIR..'/tests/timing_v16/support.lua')
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
local function hiddenAura(expiry,spell,instance)
 local hidden={}
 local oldSecret,oldTable,oldAccess=issecretvalue,issecrettable,canaccessvalue
 issecretvalue=function(v)return v==hidden or oldSecret(v)end
 issecrettable=function(v)return v==hidden or oldTable(v)end
 canaccessvalue=function(v)return v~=hidden and oldAccess(v)end
 return {spellId=spell or 5211,auraInstanceID=instance or 1,
  expirationTime=expiry or hidden,duration=hidden,isHarmful=true}
end
local function fresh()
 local e,ns=T.fresh();e.identity.target=G;e.identity.focus=G
 return e,ns
end
local function result(ns)
 local actor=assert(ns.model.units[G]);local cat=assert(actor.categories.stun)
 return actor,cat,assert(actor.effects['a:1']),ns.Observer.GetUnitState('target')
end
for _,kind in ipairs({'first','refresh','expiry-correction'}) do
 for _,alias in ipairs({'absent','matching','untimed','partial-untimed'}) do
  test(kind..'/'..alias,function()
   local e,ns=fresh()
   if alias=='absent' then e.identity.focus=nil end
   e.auras.target={T.aura(5211,1,10,3),secretAt=2}
   e.auras.focus={T.aura(5211,1,10,3)}
   if kind~='first' then ns.Observer.Scan(10.1) end
   local start=kind=='refresh' and 10.4 or 10
   local duration=kind=='refresh' and 1.5 or kind=='expiry-correction' and 2 or 3
   e.auras.target={T.aura(5211,1,start,duration),secretAt=2}
   e.auras.focus={alias=='matching' and T.aura(5211,1,start,duration) or hiddenAura()}
   if alias=='partial-untimed' then e.auras.focus.secretAt=2 end
   ns.Observer.Scan(10.5)
   local actor,cat,fx,state=result(ns)
   eq(cat.stage,kind=='refresh' and 2 or 1,'stage')
   eq(fx.appliedAt,start,'readable start');eq(fx.expires,start+duration,'readable end')
   eq(fx.expirySource,'aura','endpoint source');eq(fx.expiryAppliedAt,start,'endpoint donor start')
   eq(ns.Observer.stats.scanGaps,0,'scan gaps');eq(ns.Observer.stats.apiErrors,0,'API errors')
   if alias=='untimed' then eq(state.authoritativeUnit,'focus','complete alias removal owner') end
   ns.Observer.Scan(10.7)
   eq(cat.stage,kind=='refresh' and 2 or 1,'repeat does not count again')
   eq(T.count(actor.effects),1,'one accepted occurrence')
  end)
 end
end

test('matching end enriches missing start',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={hiddenAura(13)}
 ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,13);eq(fx.expiryAppliedAt,10)
end)

test('expiry-only positive survives untimed alias',function()
 local e,ns=fresh();e.auras.target={hiddenAura(13),secretAt=2};e.auras.focus={hiddenAura()}
 ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(cat.appliedAt,10.5);eq(fx.appliedAt,nil);eq(fx.expires,13)
 eq(fx.expiryAppliedAt,nil,'unbound endpoint stays unbound')
end)

test('conflicting readable endpoint cannot acquire donor start',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={hiddenAura(12)}
 ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,nil);eq(fx.expires,12);eq(fx.expiryAppliedAt,nil)
end)

test('timed alias retains a newer occurrence over old primary',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={T.aura(5211,1,10,3)}
 ns.Observer.Scan(10.1)
 e.auras.focus={T.aura(5211,1,10.4,1.5)};ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,2);eq(fx.appliedAt,10.4);eq(fx.expires,11.9)
end)

test('old primary cannot rewind a previously accepted refresh through untimed alias',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={hiddenAura()}
 ns.Observer.Scan(10.1)
 e.auras.target={T.aura(5211,1,10.4,1.5),secretAt=2};ns.Observer.Scan(10.5)
 e.auras.target={T.aura(5211,1,10,3),secretAt=2};ns.Observer.Scan(10.7)
 local _,cat,fx=result(ns);eq(cat.stage,2);eq(fx.appliedAt,10.4);eq(fx.expires,11.9)
 e.auras.target={T.aura(5211,1,10.4,1.5),secretAt=2};ns.Observer.Scan(10.9)
 eq(cat.stage,2,'recovery is not another refresh')
end)

test('explicit LoC timing remains authoritative over weaker aura',function()
 local e,ns=fresh();e.auras.target={secretAt=1};e.auras.focus={hiddenAura()}
 e.byloc.target={T.loc(5211,1,10,3)};ns.Observer.Scan(10.1)
 e.auras.target={T.aura(5211,1,9.5,2.5),secretAt=2};e.byloc.target={T.loc(5211,1,10,nil)}
 ns.Observer.Scan(10.5)
 local _,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,13);eq(fx.applicationSource,'loc')
end)

test('complete absence still removes a merged positive',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={hiddenAura()}
 ns.Observer.Scan(10.1)
 e.auras.target={};e.auras.focus={};ns.Observer.Scan(10.3)
 local actor=ns.model.units[G];eq(actor.categories.stun.stageResetAt,28.3,'observed end drives reset')
 eq(T.count(actor.effects),0,'complete absence retires active effect')
end)

test('contradictory complete absence does not remove readable primary',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,3),secretAt=2};e.auras.focus={}
 ns.Observer.Scan(10.5)
 local _,cat,fx,state=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,13)
 eq(state.aliasCoverage,'conflicting-positive')
end)

test('repeated enrichment has bounded identity state',function()
 local e,ns=fresh();e.auras.target={T.aura(5211,1,10,120),secretAt=2};e.auras.focus={hiddenAura()}
 for i=1,300 do ns.Observer.Scan(10+i*.1) end
 local actor,cat,fx=result(ns);eq(cat.stage,1);eq(fx.appliedAt,10);eq(fx.expires,130)
 eq(T.count(actor.effects),1);eq(T.count(ns.Observer.units.target.witnesses),1)
 eq(T.count(ns.Observer.guidContexts),2,'player plus enemy contexts stay bounded')
end)

for _,failure in ipairs(failures) do print('FAIL alias timing: '..failure) end
assert(#failures==0,tostring(#failures)..' alias timing case(s) failed')
print('alias timing: '..cases..' cases / '..checks..' checks passed')
