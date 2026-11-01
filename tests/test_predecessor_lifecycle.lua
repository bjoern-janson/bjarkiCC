-- Losing observed closure on displacement must not revive an expired DR cycle.
-- These native-boundary fixtures exercise real Observer, Main, Model and UI.
local testDir=TEST_DIR or ADDON_DIR..'/tests'
local T=dofile(testDir..'/timing_v16/support.lua')
local G,A,B='Player-PredecessorLifecycle',339,122
local cases,checks,failures=0,0,{}
local function plain(id,spell,expires)return {spellId=spell or A,auraInstanceID=id,isHarmful=true,expirationTime=expires}end
local function fresh(mode,allowGap)
 local e,n,dispatch
 if mode=='Main' then
  C_LossOfControl=nil;C_Secrets=nil;UnitFullName=nil;UnitCanAssist=nil
  local H=dofile(testDir..'/world_recovery_support.lua')()
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
  for i,a in ipairs(auras or {})do e.auras.target[i]=a;e.auras.focus[i]=a end
  e.auras.target.secretAt=#(auras or {})+1;e.byloc.target=locs or {};dispatch(t)
  assert(n.Observer.stats.apiErrors==0 and n.Observer.stats.scanGaps==0,'fixture introduced errors/gaps')
  if not allowGap then assert(n.model.units[G].durationEpoch==0,'complete alias must preserve coverage')end
 end
 return n,read,e,dispatch
end
local function eq(actual,expected,label)
 checks=checks+1
 local same=type(actual)=='number' and type(expected)=='number'
  and math.abs(actual-expected)<.000001 or actual==expected
 assert(same,(label or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function test(name,fn)
 cases=cases+1;local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function row(n,mode,t,stage,start,remaining)
 local rows=n.model:GetDR(G,t,false)
 eq(#rows,1,'one public category');local r=rows[1]
 eq(r.stage,stage,'observed stage');eq(r.started,start,'application clock');eq(r.remaining,remaining,'countdown')
 if mode=='Main' then
  local visible=0
  for _,icon in ipairs(n.UI.bars.target.icons)do
   if icon:IsShown() and icon.row then
    visible=visible+1;eq(icon.row.stage,stage,'HUD stage');eq(icon.row.started,start,'HUD clock')
   end
  end
  eq(visible,remaining>0 and 1 or 0,'visible HUD countdown')
 end
 return r
end
local scenarios={
 {name='untimed-predecessor',pred=true},
 {name='untimed-current-control'},
 {name='different-key-control',pred=true,newKey=true},
 {name='end-only-predecessor',pred=true,ending=110},
 {name='end-only-after-bound-control',pred=true,ending=110,returnAt=130},
 {name='aura-refresh-predecessor',pred=true,source='aura'},
 {name='aura-refresh-current-control',source='aura'},
 {name='loc-refresh-predecessor',pred=true,source='loc'},
 {name='loc-refresh-current-control',source='loc'},
}
for _,mode in ipairs({'Observer','Main'})do
 for _,case in ipairs(scenarios)do
  test(mode..' observed reset '..case.name,function()
  local n,read=fresh(mode)
  local a=case.source=='aura' and T.aura(A,1,99,20) or plain(1,A,case.ending)
  local locs=case.source=='loc' and {T.loc(A,1,99,20)} or {}
  read(100,{a},locs)
  if case.pred then read(100.1,{a,plain(2,B)},locs)end
  read(100.2,case.pred and {plain(2,B)} or {});read(100.3,{})
  local at=case.returnAt or 125
  for tick=101,at do read(tick,{})end
  assert(#n.model:GetDR(G,at,false)==0,'full observed quiet should retire pre-return row')
  local returning=case.source=='aura' and T.aura(A,1,at,5) or plain(case.newKey and 3 or 1)
  local returnLoc=case.source=='loc' and {T.loc(A,1,at,5)} or {}
  read(at,{returning},returnLoc);row(n,mode,at,1,at,20)
  read(at+.1,{})
  read(at+.2,{T.aura(A,4,at+.2,3)});row(n,mode,at+.2,2,at+.2,20)
  end)
 end
end
for _,mode in ipairs({'Observer','Main'})do
 test(mode..' ignored newer occurrence cannot revive its older retained endpoint',function()
  local n,read=fresh(mode)
  local old=T.aura(A,1,99,20)
  read(100,{old});read(100.1,{old,plain(2,B)})
  -- A truly refreshes, but its accepted start is older than current B.
  read(100.2,{T.aura(A,1,100.05,20),plain(2,B)})
  row(n,mode,100.2,2,100.1,19.9)
  read(100.3,{plain(2,B)});read(100.4,{})
  for tick=101,125 do read(tick,{})end
  read(125,{old})
  eq(#n.model:GetDR(G,125,false),0,'older occurrence stays closed after newer same-key removal')
  read(125.1,{T.aura(A,1,125.1,5)})
  row(n,mode,125.1,1,125.1,20)
 end)
 test(mode..' unobserved disappearance keeps an estimated end bound',function()
  local n,read,e,dispatch=fresh(mode,true)
  local a=T.aura(A,1,99,20)
  read(100,{a});read(100.1,{a,plain(2,B)})
  e.identity.target=nil;e.identity.focus=nil;dispatch(100.2)
  for tick=101,125 do dispatch(tick)end
  e.identity.target=G;e.identity.focus=G
  read(125,{})
  local r=row(n,mode,125,2,100.1,0)
  eq(r.stageResetAt,138.1,'unseen untimed end retains frozen application bound')
  eq(r.stageResetSource,'unseen-end-estimate','absence during lost ownership is not observed quiet')
  read(125.1,{T.aura(A,1,125.1,5)})
  row(n,mode,125.1,3,125.1,20)
 end)
 test(mode..' short observed absence preserves the same occurrence',function()
  local n,read=fresh(mode)
  read(100,{plain(1)});read(100.1,{plain(1),plain(2,B)})
  read(100.2,{plain(2,B)});read(100.3,{})
  read(100.4,{plain(1)})
  row(n,mode,100.4,2,100.1,19.7)
  read(100.5,{plain(1),T.aura(A,4,100.5,3)})
  row(n,mode,100.5,3,100.5,20)
 end)
 test(mode..' stale timed return does not invent a new occurrence',function()
  local n,read=fresh(mode)
  local a=T.aura(A,1,99,20)
  read(100,{a});read(100.1,{a,plain(2,B)})
  read(100.2,{plain(2,B)});read(100.3,{})
  for tick=101,125 do read(tick,{})end
  read(125,{a})
  eq(#n.model:GetDR(G,125,false),0,'closed stale timed replay stays retired')
  read(125.1,{});read(125.2,{T.aura(A,4,125.2,3)})
  row(n,mode,125.2,1,125.2,20)
 end)
 test(mode..' overlapping live endpoint retains category window',function()
  local n,read=fresh(mode)
  local b=T.aura(B,2,100.1,30)
  read(100,{plain(1)});read(100.1,{plain(1),b})
  read(100.2,{b})
  for tick=101,125 do read(tick,{b})end
  read(125,{plain(1),b})
  local r=row(n,mode,125,2,100.1,0)
  eq(r.stageResetAt,148.1,'live overlap owns latest endpoint')
  read(125.1,{plain(1),b,T.aura(A,4,125.1,3)})
  row(n,mode,125.1,3,125.1,20)
 end)
end
for _,failure in ipairs(failures)do print('FAIL predecessor lifecycle: '..failure)end
print('Predecessor lifecycle: '..cases..' cases / '..checks..' checks / '..#failures..' failures')
assert(#failures==0,tostring(#failures)..' predecessor lifecycle cases failed')
