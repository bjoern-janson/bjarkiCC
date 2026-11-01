-- A late accepted predecessor clock crossing the current clock must select
-- the newer occurrence without treating timing evidence as another application.
local testDir=TEST_DIR or ADDON_DIR..'/tests'
local fresh=dofile(testDir..'/world_recovery_support.lua')
local G='Player-1-StateAudit'
local cases,checks,failures=0,0,{}
local function eq(a,b,label)
 checks=checks+1
 assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local function near(a,b,label)
 checks=checks+1
 assert(type(a)=='number' and math.abs(a-b)<.000001,(label or 'near')..': expected '..tostring(b)..', got '..tostring(a))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]={name=name,error=tostring(err)} end
end
local function aura(id,start,duration,spell)
 local a={spellId=spell or 5211,auraInstanceID=id,isHarmful=true}
 if start and duration then a.duration=duration;a.expirationTime=start+duration end
 return a
end
local function setup(start)
 C_LossOfControl=nil;C_Secrets=nil;UnitFullName=nil;UnitCanAssist=nil
 local H=fresh();IsInInstance=function()return false end;UnitFactionGroup=function()return 'Alliance' end;H.units.target=G;H.units.focus=G;H.hostile.target=true;H.hostile.focus=true
 H.ns.db.ownCastEstimates=true;H.ns.db.aoeCastEstimates=true
 H.indexed={};H.byloc={};H.reads={}
 UnitName=function(u)if H.units[u] then return H.units[u]==G and 'StateEnemy' or 'Tester','Realm' end end
 UnitFullName=UnitName
 C_UnitAuras.GetAuraDataByIndex=function(u,i)
  H.reads[u]=(H.reads[u] or 0)+1
  local data=H.indexed[u] or {}
  if data.secretAt and i>=data.secretAt then return H.hidden end
  return data[i]
 end
 C_LossOfControl={GetActiveLossOfControlDataCount=function()return 0 end,
 GetActiveLossOfControlData=function()return nil end,
 GetActiveLossOfControlDataCountByUnit=function(u)return #(H.byloc[u] or {}) end,
 GetActiveLossOfControlDataByUnit=function(u,i)return (H.byloc[u] or {})[i] end}
 function H.fire(t,e,...)
  H.time(t);H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame,e,...)
 end
 function H.tick(t,dt)
  H.time(t);H.ns.eventFrame.scripts.OnUpdate(H.ns.eventFrame,dt or .2)
 end
 function H.row(t,estimates,aoe)
  for _,r in ipairs(H.ns.model:GetDR(G,t,estimates,aoe))do if r.category=='stun' then return r end end
 end
 function H.cast(t,id,spell)
  H.fire(t,'UNIT_SPELLCAST_SENT','player','StateEnemy-Realm','Cast-State-'..id,spell or 5211)
  H.fire(t+.01,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-State-'..id,spell or 5211)
 end
 function H.select(t)
  H.fire(t,'PLAYER_TARGET_CHANGED')
 end
 function H.plate(t,data)
  H.units.nameplate1=G;H.hostile.nameplate1=true;H.indexed.nameplate1=data or {}
  H.fire(t,'NAME_PLATE_UNIT_ADDED','nameplate1')
 end
 function H.drop(t)
  H.units.target=nil;H.units.focus=nil;H.fire(t,'PLAYER_TARGET_CHANGED')
 end
 H.select(start or 97.9)
 return H
end




for _,ORDER in ipairs({'early','late'})do
 for _,case in ipairs({{start=99.5,spell=5211,clock=99.5},{start=98.5,spell=853,clock=99},{start=99,spell=853,clock=99}})do
  test(ORDER..' accepted A start '..case.start,function()
  local A_START=case.start

local H=setup()
H.cast(98,'older')
for i=1,9 do H.tick(98+i*.2) end
H.indexed.target={aura(81)};H.indexed.focus={aura(81)}
H.fire(100,'UNIT_AURA','target',{isFullUpdate=true})
local function loc()
 H.indexed.target={aura(81),secretAt=2};H.indexed.focus={aura(81)}
 if ORDER=='late' then H.indexed.target={aura(81),aura(82,99,10,853),secretAt=3};H.indexed.focus={aura(81),aura(82,99,10,853)} end
 H.byloc.target={{spellID=5211,auraInstanceID=81,startTime=A_START,duration=10}}
end
if ORDER=='early' then loc();H.fire(100.05,'UNIT_AURA','target',{isFullUpdate=true})end
H.indexed.target={aura(81),aura(82,99,10,853),secretAt=3};H.indexed.focus={aura(81),aura(82,99,10,853)}
H.fire(100.1,'UNIT_AURA','target',{isFullUpdate=true})
if ORDER=='late' then loc() end
H.fire(100.2,'UNIT_AURA','target',{isFullUpdate=true})
H.tick(100.3)
local after=H.row(100.3,true,true)
local rendered=H.ns.UI.bars.target.icons[1].row
local state=H.ns.model.units[G].categories.stun

eq(after.spellID,case.spell,'public newest spell')
near(after.started,case.clock,'public newest clock')
near(after.remaining,case.clock==99.5 and 19.2 or 18.7,'public countdown')
eq(rendered.spellID,case.spell,'HUD newest spell')
near(rendered.started,case.clock,'HUD newest clock')
near(H.ns.model.units[G].effects['a:81'].appliedAt,A_START,'native A accepted start')
near(H.ns.model.units[G].effects['a:81'].firstSeenAt,100,'same A occurrence')
eq(H.ns.Observer.stats.apiErrors,0,'readable native fixture')
eq(H.ns.Observer.stats.scanGaps,0,'continuous scans')
-- Calibration cannot create a third application. Earlier calibration can
-- conservatively ignore an older arrival, so stage equality is not an oracle.
assert(after.stage<=2,'clock calibration invented an application')
  end)
 end
end

local function observe(H,t,auras,locs)
 H.indexed.target={};H.indexed.focus={}
 for i,a in ipairs(auras)do H.indexed.target[i]=a;H.indexed.focus[i]=a end
 H.indexed.target.secretAt=#auras+1;H.byloc.target=locs or {}
 H.fire(t,'UNIT_AURA','target',{isFullUpdate=true});H.ns.UI.Update(t)
end

test('crossing restores the occurrence own confirmation ancestry',function()
 local H=setup()
 H.cast(98,'first');H.tick(98.2);H.tick(98.4);H.cast(98.5,'second')
 for _,t in ipairs({98.7,98.9,99.1,99.3,99.5,99.7,99.9})do H.tick(t)end
 observe(H,100,{aura(81)})
 observe(H,100.1,{aura(81),aura(82,99,10,853)})
 eq(H.row(100.1,true,true).stage,3,'B inherits optional earlier cast ancestry')
 observe(H,100.2,{aura(81),aura(82,99,10,853)},
  {{spellID=5211,auraInstanceID=81,startTime=99.5,duration=10}})
 local observed=H.row(100.2,false,false)
 eq(observed.spellID,5211,'accepted A selected');near(observed.started,99.5,'accepted A clock')
 eq(observed.stage,1,'flat restoration keeps conservative known A count')
 eq(observed.uncertain,true,'reordered history remains uncertain')
 eq(H.row(100.2,true,true).stage,2,'A retains own valid full confirmation')
 eq(H.row(100.2,true,false).stage,2,'A retains own valid direct confirmation')
 observe(H,100.3,{aura(81),aura(82,99,10,853),aura(83,100.3,3,853)},
  {{spellID=5211,auraInstanceID=81,startTime=99.5,duration=10}})
 eq(H.row(100.3,false,false).stage,2,'next distinct hit counts once')
 eq(H.row(100.3,true,true).stage,3,'valid ancestry advances once with next distinct hit')
end)

test('restored pending duration cannot borrow quiet history across an older sibling',function()
 local H=setup(70)
 for t=71,97 do H.tick(t)end
 H.cast(98,'duration')
 for i=1,9 do H.tick(98+i*.2)end
 observe(H,100,{aura(81)})
 observe(H,100.1,{aura(81),aura(82,99,10,853)})
 observe(H,100.2,{aura(81),aura(82,99,10,853)},
  {{spellID=5211,auraInstanceID=81,startTime=99.5,duration=10}})
 near(H.row(100.2,false,false).started,99.5,'restored application uses accepted clock')
 observe(H,100.4,{})
 for t=101,116 do observe(H,t,{})end
 observe(H,116.1,{aura(84)},{{spellID=5211,auraInstanceID=84,startTime=116.1,duration=10}})
 eq(H.row(116.1,false,false).stage,2,'overlap cannot teach baseline for a premature full-duration reset')
 near(H.row(116.1,false,false).started,116.1,'actual next application clock')
end)

test('simultaneous current calibration still selects the accepted newer clock',function()
 local H=setup();H.cast(98,'simultaneous')
 for i=1,9 do H.tick(98+i*.2)end
 observe(H,100,{aura(81)})
 observe(H,100.1,{aura(81),aura(82,99,10,853)})
 observe(H,100.2,{aura(81),aura(82,99,10,853)},
  {{spellID=5211,auraInstanceID=81,startTime=99.5,duration=10},
   {spellID=853,auraInstanceID=82,startTime=99.75,duration=10}})
 eq(H.row(100.2,false,false).spellID,853,'B newer accepted clock wins simultaneous refinements')
 near(H.row(100.2,false,false).started,99.75,'B accepted clock')
end)

test('a genuine newer current refresh is not displaced by simultaneous predecessor calibration',function()
 local H=setup();H.cast(98,'current-refresh')
 for i=1,9 do H.tick(98+i*.2)end
 observe(H,100,{aura(81)})
 observe(H,100.1,{aura(81),aura(82,99,10,853)})
 observe(H,100.2,{aura(81),aura(82,100.15,5,853)},
  {{spellID=5211,auraInstanceID=81,startTime=99.5,duration=10}})
 eq(H.row(100.2,false,false).spellID,853,'real newer B refresh stays selected')
 near(H.row(100.2,false,false).started,100.15,'refresh owns new clock')
 eq(H.row(100.2,false,false).stage,3,'three positively observed applications remain counted')
end)

-- A returning current witness has left inventory, but its accepted explicit
-- clock still outranks a weaker aura. Raw older/later aura clocks must neither
-- cause false restoration nor block a valid crossing. A real refresh remains
-- a separate application under the same-source refresh rules.
for _,case in ipairs({
 {name='older weaker aura cannot falsely restore A',aStart=98.5,bReturn=98,source='loc',spell=853,clock=99,remaining=18.7,stage=2},
 {name='later weaker aura cannot block newer accepted A',aStart=99.5,bReturn=100,source='loc',spell=5211,clock=99.5,remaining=19.2,stage=1},
 {name='returned explicit current refresh remains a new application',aStart=99.5,bReturn=100.15,source='loc',refresh=true,spell=853,clock=100.15,remaining=19.85,stage=3},
 {name='returned aura current refresh remains a new application',aStart=99.5,bReturn=100.15,source='aura',refresh=true,spell=853,clock=100.15,remaining=19.85,stage=3},
})do
 test(case.name,function()
  local H=setup();H.cast(98,'retained-current')
  for i=1,9 do H.tick(98+i*.2)end
  observe(H,100,{aura(81)})
  observe(H,100.1,{aura(81),aura(82,99,10,853)},case.source=='loc'
   and {{spellID=853,auraInstanceID=82,startTime=99,duration=10}} or {})
  observe(H,100.15,{aura(81)})
  eq(H.row(100.15,false,false).spellID,853,'removed current stays selected before return')
  near(H.row(100.15,false,false).started,99,'removed current retains accepted clock')
  local locs={{spellID=5211,auraInstanceID=81,startTime=case.aStart,duration=10}}
  if case.refresh and case.source=='loc' then
   locs[#locs+1]={spellID=853,auraInstanceID=82,startTime=case.bReturn,duration=5}
  end
  observe(H,100.2,{aura(81),aura(82,case.bReturn,case.refresh and 5 or 10,853)},locs)
  H.tick(100.3)
  local r=H.row(100.3,false,false)
  eq(r.spellID,case.spell,'accepted newest occurrence after return')
  near(r.started,case.clock,'accepted newest clock after return')
  near(r.remaining,case.remaining,'public countdown follows accepted clock')
  eq(r.stage,case.stage,'calibration or genuine refresh follows conservative count policy')
  local rendered=H.ns.UI.bars.target.icons[1].row
  eq(rendered.spellID,case.spell,'HUD follows accepted occurrence')
  near(rendered.started,case.clock,'HUD follows accepted clock')
  eq(H.ns.Observer.stats.apiErrors,0,'readable fixture')
  eq(H.ns.Observer.stats.scanGaps,0,'continuous observations')
 end)
end

for _,failure in ipairs(failures)do print('FAIL predecessor order: '..failure.name..': '..failure.error)end
print('Predecessor order: '..cases..' cases / '..checks..' checks / '..#failures..' failures')
assert(#failures==0,tostring(#failures)..' predecessor order cases failed')
