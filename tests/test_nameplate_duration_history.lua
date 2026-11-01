-- Supplemental nameplate positives must not erase independently complete
-- primary duration history, or acquire primary absence/quiet authority.
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
 ns.db={ownCastEstimates=false,aoeCastEstimates=false,categories={}}
 assert(loadfile(ADDON_DIR..'/UI.lua'))('test',ns)
 local f={e=e,ns=ns,current={},readable=false}
 function f:auras()
  local list={}
  for _,r in ipairs(self.current) do list[#list+1]=T.aura(r[1],r[2],r[3],r[4]) end
  return list
 end
 function f:sample(now)
  e.auras.target=self.readable and self:auras() or {secretAt=1}
  e.auras.focus=self:auras();e.byloc.target={}
  for _,r in ipairs(self.current) do
   e.byloc.target[#e.byloc.target+1]=T.loc(r[1],r[2],r[3],r[4])
  end
  ns.Observer.Scan(now)
 end
 function f:plate(now,partial)
  e.identity.nameplate1=G;e.auras.nameplate1=self:auras()
  if partial then e.auras.nameplate1.secretAt=#e.auras.nameplate1+1 end
  ns.Observer.OnNameplateAdded('nameplate1',now)
 end
 function f:update(now)
  ns.Observer.OnNameplateAura('nameplate1',{isFullUpdate=true},now)
 end
 function f:actor() return assert(ns.model.units[G]) end
 return f
end
local function learned()
 local f=fixture()
 -- Establish a separately quiet category so duplicate positives must retain
 -- existing quiet proof as well as the active Hibernate baseline.
 f.current={{339,10,0,.5}}
 for i=0,2 do f:sample(i*.2) end
 f.current={}
 for i=3,104 do f:sample(i*.2) end
 f.current={{2637,1,21,20}};f:sample(21)
 local actor=f:actor()
 eq(actor.durationBaselines[2637].duration,20,'learned baseline')
 f.readable=true;f:sample(21.05)
 eq(f.ns.Observer.GetUnitState('target').auraComplete,true,'readable primary')
 eq(f.ns.Observer.GetUnitState('target').sensor,'aura','primary indexed scan')
 return f
end
local function nextFull(f)
 for i=1,99 do f:sample(21+i*.2) end
 f.current={};f:sample(41)
 for i=1,79 do f:sample(41+i*.2) end
 f.readable=false;f.current={{2637,2,57,20}};f:sample(57)
 return assert(f.ns.UI.GetRows('target',57)[1])
end
local function clean(f)
 eq(f.ns.Observer.stats.apiErrors,0,'API errors')
 eq(f.ns.Observer.stats.scanGaps,0,'scan gaps')
end
test('complete primary control still corrects next full duration',function()
 local f=learned();local row=nextFull(f)
 eq(row.stage,1);eq(row.resetEvidence,'matching-full-duration');clean(f)
end)
for _,kind in ipairs({'added','aura','partial'}) do
 test('duplicate '..kind..' preserves complete primary proof',function()
  local f=learned();local actor=f:actor()
  local since,epoch,quiet=actor.completeSince,actor.durationEpoch,actor.categories.root.observedQuietSince
  if kind=='aura' then
   f.e.identity.nameplate1=G;f.e.auras.nameplate1={}
   f.ns.Observer.OnNameplateAdded('nameplate1',21.08)
   f.e.auras.nameplate1=f:auras();f:update(21.1);f:update(21.12)
  else f:plate(21.1,kind=='partial') end
  eq(actor.durationBaselines[2637] and actor.durationBaselines[2637].duration,20,'baseline survives')
  eq(actor.completeSince,since,'primary coverage is unchanged')
  eq(actor.durationEpoch,epoch,'coverage epoch is unchanged')
  eq(actor.categories.root.observedQuietSince,quiet,'established quiet is unchanged')
  eq(actor.categories.incapacitate.observedQuietSince,nil,'active category is not quiet')
  eq(actor.categories.incapacitate.stage,1,'duplicate counts once')
  local row=nextFull(f)
  eq(row.stage,1,'public full-duration correction');eq(row.resetEvidence,'matching-full-duration');clean(f)
 end)
end
test('supplemental absence cannot remove active effects or establish quiet',function()
 local f=learned();local actor=f:actor();local ending=actor.categories.incapacitate.stageEndAt
 f:plate(21.1);f.e.auras.nameplate1={};f:update(21.15)
 eq(actor.effects['a:1']~=nil,true,'primary witness retained')
 eq(actor.categories.incapacitate.stageEndAt,ending,'no removal endpoint')
 eq(actor.categories.incapacitate.stageResetSource,'predicted-end')
 eq(actor.categories.incapacitate.observedQuietSince,nil,'no supplemental quiet')
 eq(actor.durationBaselines[2637] and actor.durationBaselines[2637].duration,20)
 clean(f)
end)
for _,kind in ipairs({'new identity','new category','refresh'}) do
 test('supplemental '..kind..' advances once and invalidates duration proof',function()
  local f=learned();local actor=f:actor();local category='incapacitate'
  if kind=='new identity' then f.current={{2637,1,21,20},{2637,2,21.1,10}}
  elseif kind=='new category' then f.current={{2637,1,21,20},{5211,2,21.1,4}};category='stun'
  else
   f.current={{2637,1,21,20},{5211,2,21.1,4}};f:sample(21.1)
   f.current={{2637,1,21,20},{5211,2,21.2,2}};category='stun'
  end
  local previous=actor.categories[category] and actor.categories[category].stage or 0
  f:plate(21.25);f:update(21.3)
  eq(actor.categories[category].stage,previous+1,'positive counts exactly once')
  eq(actor.durationBaselines[2637],nil,'incompatible history invalidated')
  eq(actor.completeSince,nil,'supplement does not establish complete coverage')
  eq(actor.categories.root.observedQuietSince,nil,'quiet history invalidated')
  eq(actor.categories[category].observedQuietSince,nil,'positive is not quiet');clean(f)
 end)
end
test('duplicate cannot restore proof after incomplete primary scan',function()
 local f=learned();local actor=f:actor();f:plate(21.1)
 f.e.auras.target={secretAt=1};f.e.auras.focus={secretAt=1};f.e.byloc.target={}
 f.ns.Observer.Scan(21.2)
 eq(actor.completeSince,nil);eq(actor.durationBaselines[2637],nil)
 f:update(21.25)
 eq(actor.completeSince,nil,'duplicate cannot repair gap')
 eq(actor.durationBaselines[2637],nil);eq(actor.categories.root.observedQuietSince,nil)
 eq(actor.categories.incapacitate.stage,1);clean(f)
end)
test('closed primary witness cannot preserve coverage through supplemental reappearance',function()
 local f=learned();local actor=f:actor();local current=f.current
 f.current={};f:sample(21.2)
 eq(actor.effects['a:1'],nil);eq(actor.categories.incapacitate.observedQuietSince,21.2)
 f.current=current;f:plate(21.25);f:update(21.3)
 eq(actor.completeSince,nil,'contradictory reappearance invalidates coverage')
 eq(actor.durationBaselines[2637],nil);eq(actor.categories.incapacitate.observedQuietSince,nil)
 eq(actor.categories.incapacitate.stage,1,'retained occurrence is not counted again');clean(f)
end)
test('duplicate cannot restore proof after primary observer pause',function()
 local f=learned();local actor=f:actor()
 f.e.identity.target=nil;f.e.identity.focus=nil;f.ns.Observer.Scan(21.2)
 eq(actor.paused,true);eq(actor.durationBaselines[2637],nil)
 f.e.identity.target=G;f.e.identity.focus=G;f:sample(21.4)
 eq(actor.completeSince,21.4,'new primary coverage starts after pause')
 f:plate(21.45);f:update(21.5)
 eq(actor.completeSince,21.4,'supplement cannot backdate coverage')
 eq(actor.durationBaselines[2637],nil,'lost baseline stays lost')
 eq(actor.categories.incapacitate.stage,1);clean(f)
end)
test('duplicate cannot restore proof lost to a primary scan time gap',function()
 local f=learned();local actor=f:actor();f:sample(22.2)
 eq(f.ns.Observer.stats.scanGaps,1);eq(actor.completeSince,22.2)
 f:plate(22.25);f:update(22.3)
 eq(actor.completeSince,22.2);eq(actor.durationBaselines[2637],nil)
 eq(actor.categories.incapacitate.stage,1);eq(f.ns.Observer.stats.apiErrors,0)
end)
test('duplicate preserves a developing halving ladder without teaching duration',function()
 local f=fixture();f:sample(0);f.current={{2637,1,.2,20}};f:sample(.2)
 local actor=f:actor();local ladder=assert(actor.durationLadders.incapacitate)
 f.readable=true;f:sample(.25);f:plate(.3);f:update(.35)
 eq(actor.durationLadders.incapacitate,ladder,'existing ladder survives')
 eq(actor.durationBaselines[2637],nil,'duplicate cannot teach a baseline')
 eq(actor.completeSince,0);eq(actor.categories.incapacitate.stage,1);clean(f)
end)
test('supplemental raw duration cannot teach a full-duration baseline',function()
 local f=fixture();f.readable=true
 for i=0,104 do f:sample(i*.2) end
 f.current={{2637,1,21,20}};f:sample(21)
 local actor=f:actor();eq(actor.durationBaselines[2637],nil,'aura timing is not raw duration proof')
 f.e.identity.nameplate1=G;f.e.auras.nameplate1={secretAt=1}
 f.e.byloc.nameplate1={T.loc(2637,1,21,20)}
 f.ns.Observer.OnNameplateAdded('nameplate1',21.1);f:update(21.15)
 eq(actor.completeSince,0,'existing primary coverage survives')
 eq(actor.durationBaselines[2637],nil,'positive-only raw duration cannot teach')
 eq(actor.categories.incapacitate.reportedDurationWitness,nil)
 eq(actor.categories.incapacitate.stage,1);clean(f)
end)
for _,failure in ipairs(failures) do print('FAIL nameplate duration history: '..failure) end
assert(#failures==0,tostring(#failures)..' nameplate duration history case(s) failed')
print('nameplate duration history: '..cases..' cases / '..checks..' checks passed')
