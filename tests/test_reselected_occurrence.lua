-- Native boundary only; all Observer/Main/Model/UI code comes from ADDON_DIR.
local td=TEST_DIR or ADDON_DIR..'/tests'
local T=dofile(td..'/timing_v16/support.lua')
local G='Player-DoubleCalibration'
local cases,checks,failures=0,0,{}
local function fresh(mode,allowGap)
 local e,n,dispatch
 if mode=='Main' then
  C_LossOfControl=nil;C_Secrets=nil;UnitFullName=nil;UnitCanAssist=nil
  local H=dofile(td..'/world_recovery_support.lua')()
  n=H.ns;e={identity=H.units,auras={},byloc={}}
  H.hostile.target=true;H.hostile.focus=true
  C_UnitAuras.GetAuraDataByIndex=function(u,i)
   local a=e.auras[u] or {};if a.secretAt and i>=a.secretAt then return H.hidden end;return a[i]
  end
  C_LossOfControl={GetActiveLossOfControlDataCount=function()return 0 end,
   GetActiveLossOfControlData=function()return nil end,
   GetActiveLossOfControlDataCountByUnit=function(u)return #(e.byloc[u] or {})end,
   GetActiveLossOfControlDataByUnit=function(u,i)return (e.byloc[u] or {})[i]end}
  dispatch=function(t)H.time(t);n.eventFrame.scripts.OnEvent(n.eventFrame,'UNIT_AURA','target',{isFullUpdate=true});n.UI.Update(t)end
 else e,n=T.fresh();dispatch=function(t)n.Observer.Scan(t)end end
 e.identity.target=G;e.identity.focus=G
 local function read(t,auras,locs)
  e.auras.target={};e.auras.focus={}
  for i,a in ipairs(auras)do e.auras.target[i]=a;e.auras.focus[i]=a end
  e.auras.target.secretAt=#auras+1;e.byloc.target=locs or {};dispatch(t)
  assert(n.Observer.stats.apiErrors==0 and n.Observer.stats.scanGaps==0,'fixture errors/gaps')
  if not allowGap then assert(n.model.units[G].durationEpoch==0,'complete focus must preserve primary coverage')end
 end
 return n,read,e,dispatch
end
local function eq(a,b,label)
 checks=checks+1
 assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local function near(a,b,label)
 checks=checks+1
 assert(type(a)=='number' and math.abs(a-b)<.000001,(label or 'clock')..': expected '..b..', got '..tostring(a))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err)end
end
local function row(n,mode,t,spell,start,stage)
 local r=n.model:GetDR(G,t,false,false)[1]
 eq(r.spellID,spell,'selected spell');near(r.started,start,'accepted application clock')
 near(r.remaining,start+20-t,'remaining countdown')
 if stage then eq(r.stage,stage,'saved conservative stage')else assert(r.stage<=2,'calibration fabricated third hit')end
 if mode=='Main' then
  local visible
  for _,icon in ipairs(n.UI.bars.target.icons)do if icon:IsShown() and icon.row and icon.row.category=='stun' then visible=icon.row end end
  assert(visible,'real HUD visible');eq(visible.spellID,spell,'HUD spell');near(visible.started,start,'HUD clock')
 end
 return r
end
for _,mode in ipairs({'Observer','Main'})do
 for _,order in ipairs({'early','late'})do
  for _,clock in ipairs({99.2,99.1,99.05})do
   test(mode..' '..order..' B LoC '..clock,function()
    local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
    local loc={T.loc(853,2,clock,10)}
    read(100,{a});read(100.1,{a,T.aura(853,2)})
    read(100.2,{a,b},order=='early' and loc or {})
    read(100.3,{a,b},loc)
    local spell=clock>99.1 and 853 or (clock==99.1 and order=='early' and 853 or 5211)
    local start=math.max(99.1,clock)
    local stage
    for _,t in ipairs({100.3,100.4,100.5})do
     if t>100.3 then read(t,{a,b},loc)end
     local r=row(n,mode,t,spell,start,stage);stage=r.stage
     near(n.model.units[G].effects['a:2'].firstSeenAt,100.1,'same B occurrence')
    end
   end)
  end
 end
 test(mode..' exact witness survives complete absence and reselects',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b});read(100.25,{})
  read(100.3,{a,b},{T.loc(853,2,99.2,10)})
  row(n,mode,100.3,853,99.2,2)
  near(n.model.units[G].effects['a:2'].firstSeenAt,100.1,'returned same B occurrence')
  read(100.4,{a,b,T.aura(5211,3,100.35,5)},{T.loc(853,2,99.2,10)})
  row(n,mode,100.4,5211,100.35,3)
 end)
 test(mode..' successive calibration alternation stays flat and counts next hit once',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b})
  read(100.3,{a,b},{T.loc(853,2,99.2,10)});row(n,mode,100.3,853,99.2,2)
  read(100.4,{a,b},{T.loc(853,2,99.2,10),T.loc(5211,1,99.3,10)})
  row(n,mode,100.4,5211,99.3,1)
  for i=1,5 do
   read(100.4+i*.02,{a,b},{T.loc(853,2,99.2,10),T.loc(5211,1,99.3,10)})
   row(n,mode,100.4+i*.02,5211,99.3,1)
  end
  local state=n.model.units[G].categories.stun
  for _,slot in ipairs({'previousApplication','displacedApplication'})do
   local saved=state[slot]
   if saved then eq(saved.previousApplication,nil,'flat predecessor');eq(saved.displacedApplication,nil,'flat displaced')end
  end
  read(100.6,{a,b,T.aura(853,3,100.55,5)},{T.loc(853,2,99.2,10),T.loc(5211,1,99.3,10)})
  row(n,mode,100.6,853,100.55,2)
  eq(n.model.units[G].categories.stun.displacedApplication,nil,'new application releases displaced snapshot')
 end)
 test(mode..' simultaneous refined clocks and weak return use accepted newest clock',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b})
  local loc={T.loc(5211,1,99.3,10),T.loc(853,2,99.2,10)}
  read(100.3,{a,b},loc);row(n,mode,100.3,5211,99.3,1)
  read(100.4,{T.aura(5211,1,98,20),T.aura(853,2,100.3,20)})
  row(n,mode,100.4,5211,99.3,1)
 end)
 test(mode..' genuine native refresh is separate from reselection',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b})
  read(100.3,{a,b},{T.loc(853,2,99.2,10)});row(n,mode,100.3,853,99.2,2)
  read(100.4,{a,b},{T.loc(853,2,100.35,5)});row(n,mode,100.4,853,100.35,3)
  near(n.model.units[G].effects['a:2'].firstSeenAt,100.4,'real refresh gets fresh occurrence')
 end)
 test(mode..' displaced removed occurrence stays closed through late calibration',function()
  local n,read=fresh(mode,true);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b});read(100.3,{a})
  read(100.4,{a},{T.loc(853,2,99.2,1)})
  row(n,mode,100.4,853,99.2,2)
  near(n.model.units[G].categories.stun.witness.endedAt,100.3,'displaced occurrence retains observed closure')
 end)
 test(mode..' first aura interval remains frozen through reselection',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b})
  local saved=n.model.units[G].categories.stun.displacedApplication
  assert(saved,'displaced B evidence retained');local context=saved.durationContext
  near(context.initialAuraDuration,10,'B first aura interval captured while displaced')
  read(100.25,{a,T.aura(853,2,99,20)})
  near(context.initialAuraDuration,10,'later aura correction cannot replace first interval')
  read(100.3,{a,b},{T.loc(853,2,99.2,10)})
  local selected=n.model.units[G].categories.stun
  row(n,mode,100.3,853,99.2,2)
  eq(selected.durationContext,context,'B owns the same duration decision context')
  near(selected.durationContext.initialAuraDuration,10,'reselection keeps first interval')
  eq(n.model.units[G].durationBaselines[853],nil,'overlap cannot teach full duration')
 end)
 test(mode..' same-key displaced replacement cannot overwrite old witness closure',function()
  local n,read=fresh(mode);local a=T.aura(5211,1,99.1,10);local b=T.aura(853,2,99,10)
  read(100,{a});read(100.1,{a,T.aura(853,2)});read(100.2,{a,b})
  local saved=n.model.units[G].categories.stun.displacedApplication
  assert(saved,'B displaced snapshot exists')
  read(100.3,{a,T.aura(853,2,99.05,5)})
  row(n,mode,100.3,5211,99.1,1)
  near(saved.witness.appliedAt,99,'old displaced occurrence keeps its own clock')
  near(saved.witness.endedAt,99.05,'old displaced occurrence closed by actual refresh')
  read(100.4,{a,T.aura(853,2,99.05,5)},{T.loc(853,2,99.2,5)})
  row(n,mode,100.4,5211,99.1,1)
  near(saved.witness.appliedAt,99,'newer same-key occurrence cannot calibrate old displaced history')
 end)

end
for _,f in ipairs(failures)do print('FAIL reselected occurrence: '..f)end
print('Reselected occurrence: '..cases..' cases / '..checks..' checks / '..#failures..' failures')
assert(#failures==0,tostring(#failures)..' reselected occurrence cases failed')
