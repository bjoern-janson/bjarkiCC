-- Client boundaries only are simulated; all addon modules below are real.
local ns, frames = {}, {}
local frameMethods = {}
local generic = {'SetSize','SetWidth','SetHeight','SetPoint','ClearAllPoints','SetAllPoints','SetTextColor',
 'SetFont','SetJustifyH','SetTexCoord','SetTexture','SetFrameStrata','SetMovable','SetClampedToScreen',
 'RegisterForDrag','EnableMouse','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetDrawEdge',
 'SetHideCountdownNumbers','SetReverse','SetOwner','AddLine','SetOrientation','SetMinMaxValues',
 'SetValueStep','SetObeyStepOnDrag','SetThumbTexture','StartMoving','StopMovingOrSizing','SetAutoFocus',
 'SetMultiLine','SetFontObject','HighlightText','SetFocus','SetScrollChild','SetMaxLetters'}
for _,key in ipairs(generic) do frameMethods[key]=function() end end
function frameMethods:SetSize(w,h) self.width=w; self.height=h; self.sizeWrites=(self.sizeWrites or 0)+1 end
function frameMethods:SetPoint(...) self.point={...} end
function frameMethods:SetBackdropBorderColor(...) self.border={...} end
function frameMethods:SetColorTexture(...) self.color={...} end
function frameMethods:SetVertexColor(...) self.color={...} end
function frameMethods:SetAtlas(atlas) self.atlas=atlas end
function frameMethods:AddLine(text) self.lines=self.lines or {}; self.lines[#self.lines+1]=text end
function frameMethods:SetScript(event, fn) self.scripts[event]=fn end
function frameMethods:RegisterEvent(event) self.events[event]=true end
function frameMethods:SetText(text) self.text=text; if self.kind=='GameTooltip' then self.lines={} end end
function frameMethods:SetChecked(value) self.checked=value end
function frameMethods:GetChecked() return self.checked end
function frameMethods:SetValue(value) self.value=value; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end end
function frameMethods:GetCenter() return 500,400 end
function frameMethods:GetLeft() return 450 end
function frameMethods:GetRight() return 550 end
function frameMethods:GetTop() return 450 end
function frameMethods:GetBottom() return 350 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:GetFrameLevel() return self.frameLevel or 1 end
function frameMethods:SetFrameLevel(level) self.frameLevel=level end
function frameMethods:IsShown() return self.shown end
function frameMethods:IsVisible() return self.shown end
function frameMethods:Hide() self.shown=false end
function frameMethods:Show() local changed=not self.shown; self.shown=true; if changed and self.scripts.OnShow then self.scripts.OnShow(self) end end
function frameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function frameMethods:SetCooldown(start,duration)
 assert(type(start)=='number' and type(duration)=='number')
 self.cooldown={start,duration}; self.cooldownWrites=(self.cooldownWrites or 0)+1
end
local function object(kind,name,parent,template)
 local f=setmetatable({kind=kind,name=name,parent=parent,template=template,scripts={},events={},shown=true},{__index=frameMethods})
 frames[#frames+1]=f; if name then _G[name]=f end; return f
end
function frameMethods:CreateFontString() return object('FontString',nil,self) end
function frameMethods:CreateTexture() return object('Texture',nil,self) end
CreateFrame=object; UIParent=object('Frame','UIParent'); STANDARD_TEXT_FONT='font.ttf'; UISpecialFrames={}; SlashCmdList={}
C_Texture={GetAtlasInfo=function(atlas) return atlas=='UI-HUD-ActionBar-IconFrame' and {} or nil end}
PlayerFrame=object('Frame','PlayerFrame',UIParent)
TargetFrame=object('Frame','TargetFrame',UIParent)
FocusFrame=object('Frame','FocusFrame',UIParent)
local playerPortrait=object('MaskTexture',nil,PlayerFrame)
local targetPortrait=object('MaskTexture',nil,TargetFrame)
local focusPortrait=object('MaskTexture',nil,FocusFrame)
PlayerFrame.PlayerFrameContainer={PlayerPortraitMask=playerPortrait}
TargetFrame.TargetFrameContainer={PortraitMask=targetPortrait}
FocusFrame.TargetFrameContainer={PortraitMask=focusPortrait}
local playerHealth=object('StatusBar',nil,PlayerFrame)
local targetHealth=object('StatusBar',nil,TargetFrame)
local focusHealth=object('StatusBar',nil,FocusFrame)
PlayerFrame.PlayerFrameContent={PlayerFrameContentMain={HealthBarsContainer={HealthBar=playerHealth}}}
TargetFrame.TargetFrameContent={TargetFrameContentMain={HealthBarsContainer={HealthBar=targetHealth}}}
FocusFrame.TargetFrameContent={TargetFrameContentMain={HealthBarsContainer={HealthBar=focusHealth}}}
local now=100
local combat=false
InCombatLockdown=function() return combat end
GetTime=function() return now end
GetBuildInfo=function() return '1.60.1','70425','Oct 16 2026',16001 end
local units={player='Player-1-A'}
UnitGUID=function(unit) return units[unit] end
UnitIsPlayer=function(unit) return units[unit]~=nil end
UnitCanAttack=function() return false end
UnitName=function(unit)
 if units[unit] then return ({player='Tester',target='TargetEnemy',focus='FocusEnemy'})[unit] end
end
C_UnitAuras={GetAuraDataByIndex=function() return nil end}
C_Spell={GetSpellTexture=function() return 135963 end}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
issecretvalue=function() return false end; canaccessvalue=function() return true end
local dir=ADDON_DIR or 'work/bjarkiCC'
for _,file in ipairs({'Bootstrap','Data','Model','Observer','OwnCasts','Anchors','UI','NativeStuns'}) do assert(loadfile(dir..'/'..file..'.lua'))('bjarkiCC',ns) end
local main=io.open(dir..'/Main.lua'); assert(main,'Main is not implemented yet'); main:close()
assert(loadfile(dir..'/Main.lua'))('bjarkiCC',ns)
assert(ns.eventFrame.events.ADDON_LOADED,'addon initialization registered')
assert(not ns.eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED,'restricted event never registered')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'ADDON_LOADED','bjarkiCC')
assert(ns.db and ns.model and ns.UI.bars.player,'addon initializes without optional APIs')
assert(ns.NativeStuns and ns.db.nativeStunWitness==false,
 'secure stun visual is present in addon but disabled by default')
assert(not ns.NativeStuns.initialized,
 'secure aura hosts must wait until Blizzard frames load at world entry')
SlashCmdList.BJARKICC('aura status')
assert(ns.BuildStatus():find('Secure native stun visual:',1,true)
 and ns.BuildStatus():find('native shared-stun witness OFF',1,true),
 'diagnostics identify nonauthoritative witness status')
-- Probe the Blizzard-native DR option without modifying addon DR model state.
local nativeCVar="0"
local nativeSupported=true
C_SpellDiminish={IsSystemSupported=function() return nativeSupported end}
C_EventUtils={IsEventValid=function(event)
 assert(event=="UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED")
 return true
end}
C_CVar={
 GetCVar=function(key) assert(key=="spellDiminishPVPEnemiesEnabled"); return nativeCVar end,
 SetCVar=function(key,value)
  assert(key=="spellDiminishPVPEnemiesEnabled")
  nativeCVar=value
  return true
 end,
}
SlashCmdList.BJARKICC('native status')
assert(ns.BuildStatus():find('Native DR feed: supported=true; cvar=0; eventValid=true',1,true),
 'status reports off client-native DR option, independent of addon predictions')
SlashCmdList.BJARKICC('native on')
assert(nativeCVar=="1" and ns.BuildStatus():find('cvar=1',1,true),
 'explicit out-of-combat command enables supported Blizzard DR CVar')
SlashCmdList.BJARKICC('native off')
assert(nativeCVar=="0",'off restores off client-native DR option')
combat=true; SlashCmdList.BJARKICC('native on'); combat=false
assert(nativeCVar=="0",'native settings never changed in combat')
nativeSupported=false; SlashCmdList.BJARKICC('native on')
assert(nativeCVar=="0",'unsupported native DR system is not force-enabled')
nativeSupported=true
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','TargetEnemy','Cast-bash-probe',5211)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-bash-probe',5211)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','TargetEnemy','Cast-grenade-probe',4068)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-grenade-probe',4068)
assert(ns.Observer.stats.ownBashSent==1 and ns.Observer.stats.ownBashSucceeded==1
 and ns.Observer.stats.ownGrenadeSent==1 and ns.Observer.stats.ownGrenadeSucceeded==1,
 'real Main cast routing records useful Bash and grenade diagnostics independently of hits')
assert(#ns.model:GetDR('Player-1-A',100)==0,'a cast event alone is still not a DR witness')

assert(ns.db.bars.cooldown.enabled==false and ns.db.bars.cooldown.y==-170,
 'fresh enemy cooldown bar is opt-in and no longer overlaps the old castbar position')
assert(ns.BuildStatus():find('Enemy cooldown HUD: OFF by default',1,true),
 'status must not imply an unverified enemy feed is working')
-- These legacy timelines deliberately configure a 20-second stage window.
-- The Forever 18-second trace below exercises the independent default.
ns.db.stageResetSeconds=20
ns.model=ns.Model.New(ns.db.resetSeconds,ns.db.stageResetSeconds)
assert(not ns.UI.bars.player.template and not ns.UI.bars.target.template and not ns.UI.bars.focus.template,
 'unit-anchored bars must not inherit BackdropTemplate secret-size arithmetic')
for _,pair in ipairs({{'player',playerPortrait},{'target',targetPortrait},{'focus',focusPortrait}}) do
 local bar=ns.UI.bars[pair[1]]
 assert(bar.point[2]==pair[2] and bar.point[1]==(pair[1]=='player' and 'TOPRIGHT' or 'TOPLEFT')
  and bar.point[3]==(pair[1]=='player' and 'TOPLEFT' or 'TOPRIGHT')
  and bar.point[4]==(pair[1]=='player' and -18 or 18) and bar.point[5]==0,'each grid starts beside the outer portrait edge')
end
assert(ns.UI.bars.player.anchorFrame==PlayerFrame and ns.UI.bars.focus.anchorFrame==FocusFrame,
 'native frame remains the visibility owner')
assert(ns.eventFrame.events.PLAYER_FOCUS_CHANGED and ns.eventFrame.events.PLAYER_REGEN_ENABLED,'focus and anchor recovery events registered')
assert(ns.eventFrame.events.UNIT_SPELLCAST_SENT and ns.eventFrame.events.UNIT_SPELLCAST_SUCCEEDED
 and ns.eventFrame.events.UNIT_SPELLCAST_FAILED and ns.eventFrame.events.UNIT_SPELLCAST_INTERRUPTED,'outgoing cast correlation and cancellation events registered')
assert(ns.eventFrame.events.UNIT_SPELLCAST_START and ns.eventFrame.events.UNIT_SPELLCAST_CHANNEL_START,
 'non-authoritative cast-start telemetry registers without creating cooldowns')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_ENTERING_WORLD')
assert(ns.NativeStuns.initialized,
 'world entry initializes the isolated native widget without allowing a DR hit')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_START','target','Cast-start',853)
assert(ns.Observer.stats.castStartsOther==1 and #ns.model:GetCooldowns(100)==0,
 'cast-start evidence never starts speculative enemy cooldowns')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.3)
assert(not ns.UI.bars.player.shown and not ns.UI.bars.cooldown.shown,'empty bars hidden in normal play')
-- CC can apply and be removed between render ticks; event callbacks must sample it.
now=100.1
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if unit=='player' and index==1 then return {spellId=853,auraInstanceID=77,expirationTime=106} end
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
ns.UI.Update(now)
assert(ns.UI.bars.player.shown and ns.UI.bars.player.icons[1].time.text=='','application shows its DR icon while long countdown text stays hidden')
assert(ns.UI.bars.player.icons[1].swipe.cooldown[1]==100.1,'application supplies the cooldown sweep start')
local initialIcon=ns.UI.bars.player.icons[1]
local firstClockWrites=initialIcon.swipe.cooldownWrites
local firstSizeWrites=initialIcon.sizeWrites
local firstBarSizeWrites=ns.UI.bars.player.sizeWrites
ns.UI.Update(now+0.05)
assert(initialIcon.swipe.cooldownWrites==firstClockWrites and initialIcon.sizeWrites==firstSizeWrites
 and ns.UI.bars.player.sizeWrites==firstBarSizeWrites,
 'identical presentation updates must leave native cooldown clock and geometry alone')
local bevel=ns.UI.bars.player.icons[1].borderTextures[1]
assert(bevel.atlas=='UI-HUD-ActionBar-IconFrame', 'DR icons use the native action-button bevel')
assert(bevel.parent.frameLevel>ns.UI.bars.player.icons[1].swipe:GetFrameLevel(),
 'cooldown swipe cannot darken the DR stage border')
now=100.15
C_UnitAuras.GetAuraDataByIndex=function() return nil end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
local transient=ns.model:GetDR('Player-1-A',now)
assert(#transient==1 and not transient[1].active,'short effects must retain reset window between UI ticks')
assert(transient[1].started==100.1 and math.abs(transient[1].remaining-19.95)<.0001,'instant break cannot restart the application timer')
-- Focus changes and aura events must work without waiting for the render tick.
units.focus='Player-1-F'
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_FOCUS_CHANGED')
assert(ns.Observer.GetUnitState('focus').guid=='Player-1-F','focus selection immediately observed')
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if unit=='focus' and index==1 then return {spellId=853,auraInstanceID=78,expirationTime=106} end
end
now=100.2
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','focus')
now=100.25
C_UnitAuras.GetAuraDataByIndex=function() return nil end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','focus')
local focusRows=ns.model:GetDR('Player-1-F',now)
assert(#focusRows==1 and focusRows[1].started==100.2,'focus aura transitions preserve the application start')
ns.UI.Update(now)
assert(ns.UI.bars.focus.shown,'focus DR renders beside visible FocusFrame')
FocusFrame:Hide(); ns.UI.Update(now)
assert(not ns.UI.bars.focus.shown,'live focus DR follows native visibility')
FocusFrame:Show()
units.focus=nil
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_FOCUS_CHANGED')
ns.UI.Update(now)
assert(not ns.UI.bars.focus.shown,'clearing focus removes its live bar')
-- The real event path must render an estimate even when outgoing aura IDs are hidden.
local outgoingSecret={}
issecretvalue=function(value) return rawequal(value,outgoingSecret) end
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if (unit=='target' or unit=='focus') and index==1 then return {spellId=outgoingSecret,auraInstanceID=99} end
end
units.target='Player-1-T'; units.focus='Player-1-F'
now=101
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','TargetEnemy','Cast-outgoing-1',853)
assert(#ns.model:GetDR('Player-1-T',now)==0,'sending alone must not create the outgoing estimate')
now=101.05
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-outgoing-1',853)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
local outgoing=ns.model:GetDR('Player-1-T',now)
local targetIcon=ns.UI.bars.target.icons[1]
assert(#outgoing==1 and outgoing[1].estimated and outgoing[1].uncertain and outgoing[1].stage==1,'correlated player success creates a separate uncertain estimate')
assert(ns.UI.bars.target.shown and targetIcon.row.estimated and targetIcon.time.text==''
 and not targetIcon.state.shown,'Main success dispatch renders the estimate with only its timer and border')
assert(not targetIcon.template,'anchored icon cannot inherit BackdropTemplate size callbacks')
for _,edge in ipairs(targetIcon.borderTextures) do
 assert(edge.color[1]==.25 and edge.color[2]==1 and edge.color[3]==.3,'estimated first DR retains its green stage border')
end
targetIcon.scripts.OnEnter(targetIcon)
assert(ns.UI.tip.lines[1]=='Next duration: unknown','estimated stage color must not promise the next CC duration')
assert(table.concat(ns.UI.tip.lines,'\n'):find('estimated stage 1',1,true),'estimate tooltip identifies what the border represents')
assert(next(ns.model.units['Player-1-T'].categories)==nil,'outgoing cast events do not populate observed DR history')
-- A later readable application replaces the estimate; it cannot become stage two.
now=101.1
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if unit=='target' and index==1 then return {spellId=853,auraInstanceID=100,expirationTime=107} end
 if unit=='focus' and index==1 then return {spellId=outgoingSecret,auraInstanceID=99} end
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
outgoing=ns.model:GetDR('Player-1-T',now)
assert(#outgoing==1 and not outgoing[1].estimated and outgoing[1].stage==1
 and outgoing[1].started==101.05 and outgoing[1].timeEstimated,'untimed confirmation retains the earlier cast clock without double counting')
assert(ns.UI.bars.target.shown and not targetIcon.row.estimated and targetIcon.row.stage==1,'the rendered target row switches to observed evidence')
targetIcon.scripts.OnEnter(targetIcon)
assert(table.concat(ns.UI.tip.lines,'\n'):find('timing is estimated from your earlier cast',1,true),'confirmed application does not silently make its cast clock exact')
-- Readable timing corrects the existing identity; then a shorter repeated CC
-- can end sooner than the original and still be a new application.
local targetAura={spellId=853,auraInstanceID=100,expirationTime=111.05,duration=10}
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if unit=='target' and index==1 then return targetAura end
 if unit=='focus' and index==1 then return {spellId=outgoingSecret,auraInstanceID=99} end
end
now=101.2
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
outgoing=ns.model:GetDR('Player-1-T',now)
assert(outgoing[1].stage==1 and not outgoing[1].timeEstimated and math.abs(outgoing[1].started-101.05)<.0001,'timing becoming readable corrects rather than duplicates the application')
now=102; targetAura.expirationTime=107; targetAura.duration=5
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==2 and targetIcon.row.started==102 and targetIcon.time.text=='','shorter consecutive CC refreshes application timer and advances stage')
for _,edge in ipairs(targetIcon.borderTextures) do
 assert(edge.color[1]==1 and edge.color[2]==.8 and edge.color[3]==.15,'second observed application renders the yellow stage border')
end
assert(not targetIcon.state.shown and targetIcon.row.uncertain,'derived refresh retains uncertainty without an icon marker')
assert(ns.BuildStatus():find('DR stun: stage 2; started 102.000',1,true),'status exposes the current application clock for runtime diagnosis')
now=103; targetAura.expirationTime=105.5; targetAura.duration=2.5
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==3 and targetIcon.row.started==103 and targetIcon.time.text=='','third readable application refreshes the timer and reaches the final DR stage')
for _,edge in ipairs(targetIcon.borderTextures) do
 assert(edge.color[1]==1 and edge.color[2]==.2 and edge.color[3]==.15,'third observed application renders its red border')
end
-- Failed/interrupted casts cannot seed focus predictions, even after a stale success.
for index,event in ipairs({'UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED'}) do
 now=104+index/10
 local castID='Cast-cancelled-'..index
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','FocusEnemy',castID,118)
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,event,'player',castID,118)
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player',castID,118)
 ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
 assert(#ns.model:GetDR('Player-1-F',now)==0 and not ns.UI.bars.focus.shown,'cancelled focus cast cannot become a visible estimate')
end
-- Forever's actual SENT destination can use a space between UnitName fields.
-- Keep the first hidden application as inference when only the second is seen.
SlashCmdList.BJARKICC('clear')
local originalUnitName=UnitName
UnitName=function(unit)
 if unit=='target' or unit=='focus' then return 'Björn','Janson' end
 return originalUnitName(unit)
end
units.target='Player-1-SPACE'; units.focus='Player-1-SPACE'
now=200
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-space-1',6770)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-space-1',6770)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
targetIcon=ns.UI.bars.target.icons[1]
assert(ns.UI.bars.target.shown and ns.UI.bars.focus.shown and targetIcon.time.text==''
 and targetIcon.row.stage==1 and targetIcon.row.estimated,'space-qualified destination starts both same-GUID views immediately on success')
now=210
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-space-2',6770)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-space-2',6770)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==2 and targetIcon.time.text=='','second hidden cast advances and refreshes the inferred timer')
now=211
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if (unit=='target' or unit=='focus') and index==1 then
  return {spellId=6770,auraInstanceID=202,expirationTime=220,duration=10}
 end
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(not targetIcon.row.estimated and targetIcon.row.stage==2 and targetIcon.row.observedStage==1
 and targetIcon.row.stageEstimated and targetIcon.row.uncertain and targetIcon.time.text=='',
 'confirming the second application preserves the inferred first stage without making it observed')
for _,edge in ipairs(targetIcon.borderTextures) do
 assert(edge.color[1]==1 and edge.color[2]==.8,'confirmed second application retains its inferred yellow border')
end
targetIcon.scripts.OnEnter(targetIcon)
assert(table.concat(ns.UI.tip.lines,'\n'):find('Earlier applications remain inferred',1,true),
 'tooltip must distinguish inferred prior stages from a confirmed current application')
local resolutionReport=ns.BuildStatus()
assert(resolutionReport:find('ownCast.resolve.resolved: 2',1,true)
 and resolutionReport:find('Björn Janson',1,true),'status exposes bounded safe destination-resolution evidence')
assert(resolutionReport:find('Observed stage 1; displayed stage 2 includes earlier inferred applications.',1,true),
 'status separates the observed stage from the inferred display')
ns.db.ownCastEstimates=false; ns.UI.Update(now)
assert(targetIcon.row.stage==1 and not targetIcon.row.stageEstimated,'disabling estimates removes inferred stage continuity')
ns.db.ownCastEstimates=true; ns.UI.Update(now)
assert(targetIcon.row.stage==2 and targetIcon.row.stageEstimated,'enabling estimates restores separate inferred continuity')
-- Third application starts the red window; further unconfirmed casts cannot
-- push its deadline forward, even for another spell in the same DR category.
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if (unit=='target' or unit=='focus') and index==1 then return {spellId=outgoingSecret,auraInstanceID=303} end
end
now=215
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-cap-3',2637)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-cap-3',2637)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==3 and targetIcon.row.started==215 and targetIcon.time.text=='',
 'the third application still starts its full red countdown')
for _,time in ipairs({218,222,234}) do
 now=time
 local castID='Cast-cap-'..time
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson',castID,2637)
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player',castID,2637)
 ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
 assert(targetIcon.row.stage==3 and targetIcon.row.started==215 and targetIcon.row.remaining==235-now,
  'attempts at the final DR stage must preserve the original deadline')
 assert(targetIcon.swipe.cooldown[1]==215 and targetIcon.time.text==((235-now)<=5 and ns.UI.FormatTime(235-now) or ''),
  'neither sweep nor number can restart on an unconfirmed immune-stage attempt')
 assert(ns.UI.bars.focus.icons[1].row.started==215,'same-GUID focus shares the preserved deadline')
end
assert(ns.OwnCasts.stats.estimated==3,'suppressed cap attempts are not accepted DR estimates')
now=235; ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.2)
assert(not ns.UI.bars.target.shown and not ns.UI.bars.focus.shown,
 'expired cast prediction hides rather than revealing an already-expired application icon')
local cappedHistory=ns.model:GetDR('Player-1-SPACE',now)
assert(cappedHistory[1].stage==2 and cappedHistory[1].remaining==0,
 'hiding the icon preserves the observed stage in internal history')
now=240; ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.2)
assert(not ns.UI.bars.target.shown and not ns.UI.bars.focus.shown,'known prior aura end bounds the retained observed stage')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-after-cap',2637)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-after-cap',2637)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==1 and targetIcon.row.started==240 and targetIcon.time.text=='',
 'a new cast after expiry begins a fresh first cycle')
UnitName=originalUnitName
issecretvalue=function() return false end
C_UnitAuras.GetAuraDataByIndex=function() return nil end
units.target=nil; units.focus=nil
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
SlashCmdList.BJARKICC('clear')
SlashCmdList.BJARKICC('test')
assert(ns.demo and ns.UI.bars.player.icons[1].shown,'demo visible')
assert(not ns.UI.bars.cooldown.shown,
 'normal DR preview must not show sample enemy cooldown icons without explicit opt-in')
SlashCmdList.BJARKICC('aura on')
assert(ns.db.nativeStunWitness,
 'opt-in secure aura widget does not depend on ordinary DR stage tracking')
SlashCmdList.BJARKICC('aura off')
assert(not ns.db.nativeStunWitness,'native aura visual can be disabled independently')
SlashCmdList.BJARKICC('cooldowns on')
assert(ns.db.bars.cooldown.enabled and ns.UI.bars.cooldown.shown,
 'explicit command enables experimental cooldown preview without altering DR')
assert(ns.UI.bars.cooldown.title.text=='Enemy cooldowns (SAMPLE)',
 'fake preview must not be confused with detected enemy cooldowns')
local recordedMessages, oldChatWriter={}, DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage=function(_,message) recordedMessages[#recordedMessages+1]=message end
SlashCmdList.BJARKICC('cooldowns status')
assert(#recordedMessages>=2 and recordedMessages[#recordedMessages]:find('accepted automatic cooldowns=',1,true),
 'quick cooldown status reports actual accepted-cast counts, not sample icons')
DEFAULT_CHAT_FRAME.AddMessage=oldChatWriter
assert(ns.UI.bars.focus.icons[1].shown,'focus has an independent preview')
assert(ns.UI.bars.player.title.shown,'test bars identified')
assert(not ns.UI.bars.player.icons[1].caption.shown,'no category captions in minimal view')
assert(not ns.UI.bars.player.icons[1].state.shown,'known DR uses border without duplicate stage text')
assert(not ns.UI.bars.cooldown.icons[1].caption.shown and not ns.UI.bars.cooldown.icons[1].state.shown,'cooldown minimal view has just timer')
local previewIcon=ns.UI.bars.cooldown.icons[1]
previewIcon.scripts.OnEnter(previewIcon)
assert(ns.UI.tip.lines[1]=='SAMPLE ONLY: no enemy cast was observed.',
 'hovering a demo cooldown must identify it as synthetic, not verified live data')
assert(ns.UI.bars.player.icons[1].time.parent:GetFrameLevel()>ns.UI.bars.player.icons[1].swipe:GetFrameLevel(),'countdown text must sit above swipe')
SlashCmdList.BJARKICC('test')
assert(not ns.demo and not ns.UI.bars.player.icons[1].shown,'demo never survives into live display')
SlashCmdList.BJARKICC('unlock'); assert(not ns.db.locked and ns.UI.bars.player.shown,'empty anchors reappear to move')
local focusBar=ns.UI.bars.focus
focusBar.scripts.OnDragStart(focusBar)
assert(focusBar.dragging,'unit anchor can be dragged out of combat')
combat=true
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_REGEN_DISABLED')
assert(not focusBar.dragging and focusBar.anchorPending,'combat cancels dragging and queues reattachment')
combat=false
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_REGEN_ENABLED')
assert(not focusBar.anchorPending and focusBar.point[2]==focusPortrait,'combat exit restores the modern health-region anchor')
SlashCmdList.BJARKICC('lock'); assert(ns.db.locked and not ns.UI.bars.player.shown,'locking removes empty anchors')
SlashCmdList.BJARKICC('cooldown 10308 47')
assert(ns.db.cooldownOverrides[853]==47,'rank override normalizes')
SlashCmdList.BJARKICC('cooldown 853 -2')
assert(ns.db.cooldownOverrides[853]==47,'invalid timing does not destroy saved override')
SlashCmdList.BJARKICC('cooldown 853 default'); assert(ns.db.cooldownOverrides[853]==nil)
ns.demo=true; ns.db.locked=false
SlashCmdList.BJARKICC('')
assert(ns.UI.options.shown,'settings opens')
local endPreview,lockBars=false,false
for _,f in ipairs(frames) do endPreview=endPreview or f.text=='End preview'; lockBars=lockBars or f.text=='Lock bars' end
assert(endPreview and lockBars,'new settings reflect already active preview and unlocked bars')
ns.demo=false; ns.db.locked=true
SlashCmdList.BJARKICC('status'); assert(ns.BuildStatus():find('70425',1,true),'diagnostic includes actual build')
assert(ns.BuildStatus():find('focus:',1,true) and ns.BuildStatus():find('FocusFrame',1,true),'diagnostics include focus sensor and anchor')
-- Rebuild native frame layout in every orientation with test rows.
ns.demo=true
for _,bar in pairs(ns.db.bars) do bar.vertical=true; bar.reverse=true end
ns.UI.ApplyLayout()
assert(ns.UI.bars.cooldown.icons[1].cooldown==nil,'cooldown is rendered by child widget')
assert(ns.UI.bars.cooldown.icons[1].swipe.cooldown[2]==60,'render uses estimated max duration')
assert(ns.UI.bars.player.height==59,'DR grid remains two rows regardless of legacy vertical settings')
ns.db.showNames=true; ns.db.showDRText=true
ns.UI.Update(now)
assert(ns.UI.bars.cooldown.icons[1].caption.shown and ns.UI.bars.cooldown.icons[1].caption.text=='Paladin','optional caster identity')
assert(ns.UI.bars.player.icons[1].state.shown and ns.UI.bars.player.icons[1].state.text=='50%','optional accessible stage text')
ns.db.showNames=false; ns.db.showDRText=false
ns.demo=false
local realModel=ns.model
ns.Observer.units.player={guid='Player-1-A',status='readable'}
ns.model={GetDR=function() return {{category='stun',spellID=853,stage=3,active=true,uncertain=true,started=now,duration=20,remaining=20}} end,
 GetCooldowns=function() return {
 {guid='Player-1-B',name='Enemy',spellID=853,category='stun',started=now-46,duration=60,remaining=14,earlyRemaining=0},
 {guid='Player-1-C',name='Other',spellID=853,category='stun',started=now-2,duration=60,remaining=58,earlyRemaining=43}} end}
ns.db.bars.cooldown.maxIcons=1
ns.UI.Update(now)
assert(not ns.UI.bars.player.title.shown,'no headers in normal play')
assert(ns.UI.bars.player.icons[1].time.text=='','DR icon is visible from application while countdown text waits until five seconds')
assert(ns.UI.bars.player.icons[1].swipe.shown and ns.UI.bars.player.icons[1].swipe.cooldown[1]==now,'DR sweep starts on the observed application')
assert(not ns.UI.bars.player.icons[1].state.shown,'uncertain DR does not add a question mark to the icon')
for _,edge in ipairs(ns.UI.bars.player.icons[1].borderTextures) do
 assert(edge.color[1]==1 and edge.color[2]==.2 and edge.color[3]==.15,'uncertain observed stage three keeps its red stage border')
end
ns.UI.bars.player.icons[1].scripts.OnEnter(ns.UI.bars.player.icons[1])
assert(ns.UI.tip.lines[1]=='Next duration: unknown'
 and table.concat(ns.UI.tip.lines,'\n'):find('observed stage 3',1,true),'incomplete observed history remains explicit in the stage-colored tooltip')
ns.db.showDRText=true
ns.UI.Update(now)
assert(not ns.UI.bars.player.icons[1].state.shown,'optional percentages cannot claim an exact duration for uncertain DR')
assert(ns.UI.bars.player.icons[1].time.point[1]=='CENTER'
 and ns.UI.bars.player.icons[1].time.point[3]==0,'omitted uncertain percentages leave the timer centered')
ns.db.showDRText=false
assert(ns.UI.bars.cooldown.icons[1].state.shown and ns.UI.bars.cooldown.icons[1].state.text=='?','earliest-ready uncertainty visible')
assert(ns.UI.bars.cooldown.overflow.shown and ns.UI.bars.cooldown.overflow.text=='+1','overflow stays visible without heading')
local hovered=ns.UI.bars.cooldown.icons[1]
hovered.row.remaining=125
hovered.scripts.OnEnter(hovered)
assert(ns.UI.tip.lines[3]=='Estimated remaining: 125s','long tooltip timers keep correct seconds unit')
ns.model.GetDR=function() return {{category='stun',spellID=853,stage=3,active=false,uncertain=true,
 started=now-20,duration=20,remaining=0,stageRemaining=7,stageResetAt=now+7}} end
ns.UI.Update(now)
assert(not ns.UI.bars.player.shown and not ns.UI.bars.player.icons[1].shown,
 'the whole DR icon hides when its application countdown ends')
ns.model.GetDR=function() return {
 {category='stun',spellID=853,stage=3,active=false,started=now-20,duration=20,remaining=0,stageRemaining=7},
 {category='fear',spellID=5782,stage=1,active=true,started=now-2,duration=20,remaining=18}} end
local previousMax=ns.db.bars.player.maxIcons
ns.db.bars.player.maxIcons=1
ns.UI.Update(now)
assert(ns.UI.bars.player.icons[1].row.category=='fear' and not ns.UI.bars.player.overflow.shown,
 'expired categories consume neither visible icon slots nor overflow count')
assert(ns.UI.bars.cooldown.icons[1].shown and ns.UI.bars.cooldown.overflow.text=='+1',
 'DR expiry filtering does not change cooldown visibility or overflow')
ns.db.bars.player.maxIcons=previousMax
ns.model=realModel
-- Replay the recipient's 0.4.5 Hibernate trace through events, observation,
-- shared GUID state and rendered colors. The first clock comes from aura data;
-- LoC supplies a different explicit start before a real same-ID reapplication.
SlashCmdList.BJARKICC('clear')
units.target=units.player; units.focus=units.player
local handoffAura, handoffLoC
local handoffSecret={}
issecretvalue=function(value) return rawequal(value,handoffSecret) end
canaccessvalue=function(value) return not rawequal(value,handoffSecret) end
C_UnitAuras={GetAuraDataByIndex=function(unit,index)
 if unit=='player' and index==1 then return handoffAura end
end}
C_LossOfControl={GetActiveLossOfControlDataCount=function() return handoffLoC and 1 or 0 end,
 GetActiveLossOfControlData=function() return handoffLoC end}
local function handoffEvent(at,event,stage,start)
 now=at
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,event,'player')
 ns.UI.Update(now)
 for _,unit in ipairs({'player','target','focus'}) do
  local bar=ns.UI.bars[unit]
  if stage and start+20>now then
   local icon=bar.icons[1]
   assert(bar.shown and icon.row.stage==stage and icon.row.observedStage==stage,
    'Hibernate source handoff must not invent a stage on '..unit)
   assert(icon.row.started==start and icon.swipe.cooldown[1]==start,
    'numeric countdown and sweep share the calibrated application time')
   assert(icon.time.text==((start+20-now)<=5 and ns.UI.FormatTime(start+20-now) or ''),
    'visible countdown retains the application policy')
   local color=({{.25,1,.3},{1,.8,.15},{1,.2,.15}})[stage]
   assert(icon.actionBorder and icon.actionBorder.atlas=='UI-HUD-ActionBar-IconFrame'
    and icon.actionBorder.parent.frameLevel>icon.swipe:GetFrameLevel(),
    'native action-button artwork stays above the cooldown on '..unit)
   for _,edge in ipairs(icon.borderTextures) do
    assert(edge.color[1]==color[1] and edge.color[2]==color[2] and edge.color[3]==color[3],
     'rendered Hibernate border follows the corrected observed cycle')
   end
   assert(not icon.state.shown,'no DR question mark is reintroduced')
  else
   assert(not bar.shown,'application timer expires without being restarted by removal')
   if stage then
    local history=ns.model:GetDR(units[unit],now)
    assert(history[1].stage==stage and history[1].remaining==0,
     'expired presentation leaves the DR stage available to subsequent applications')
   end
  end
 end
end
handoffEvent(2655614.460,'UNIT_AURA')
handoffAura={spellId=2637,auraInstanceID=325,expirationTime=2655646.973,duration=20}
handoffEvent(2655626.973,'UNIT_AURA',1,2655626.973)
handoffAura={spellId=handoffSecret,auraInstanceID=325}
handoffLoC={spellID=2637,auraInstanceID=325,startTime=2655627.250,duration=20,timeRemaining=20}
handoffEvent(2655626.973,'LOSS_OF_CONTROL_ADDED',1,2655626.973)
handoffEvent(2655627.270,'LOSS_OF_CONTROL_UPDATE',1,2655627.250)
handoffLoC={spellID=2637,auraInstanceID=325,startTime=2655637.750,duration=10,timeRemaining=9.999}
handoffEvent(2655637.512,'LOSS_OF_CONTROL_UPDATE',1,2655627.250)
handoffEvent(2655637.765,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
handoffEvent(2655642.750,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
assert(ns.UI.bars.player.icons[1].time.text=='','half-duration CC now has the yellow second cycle at 15s')
handoffLoC=nil
handoffEvent(2655647.495,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
handoffEvent(2655652.402,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
assert(ns.OwnCasts.stats.estimated==0,'recipient regression is entirely observed history')
handoffEvent(2655657.750,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
handoffEvent(2655667.495,'LOSS_OF_CONTROL_UPDATE')
-- With stage retention separate from the visible application clock, a full
-- 20-second Hibernate followed after 22 seconds must not lose the first stage.
SlashCmdList.BJARKICC('clear')
local chainStart=3000000
handoffLoC={spellID=2637,auraInstanceID=401,startTime=chainStart,duration=20,timeRemaining=20}
handoffEvent(chainStart,'LOSS_OF_CONTROL_ADDED',1,chainStart)
handoffLoC=nil
now=chainStart+20
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'LOSS_OF_CONTROL_UPDATE','player')
ns.UI.Update(now)
for _,unit in ipairs({'player','target','focus'}) do
 assert(not ns.UI.bars[unit].shown,'full Hibernate icon hides at application expiry')
 local history=ns.model:GetDR(units[unit],now)
 assert(history[1].stage==1 and history[1].remaining==0,
  'full Hibernate stage remains internal after its icon disappears')
end
handoffLoC={spellID=2637,auraInstanceID=403,startTime=chainStart+22,duration=10,timeRemaining=10}
handoffEvent(chainStart+22,'LOSS_OF_CONTROL_ADDED',2,chainStart+22)
handoffLoC=nil
handoffEvent(chainStart+32,'LOSS_OF_CONTROL_UPDATE',2,chainStart+22)
handoffLoC={spellID=2637,auraInstanceID=405,startTime=chainStart+34,duration=5,timeRemaining=5}
handoffEvent(chainStart+34,'LOSS_OF_CONTROL_ADDED',3,chainStart+34)
handoffLoC=nil
handoffEvent(chainStart+39,'LOSS_OF_CONTROL_UPDATE',3,chainStart+34)
now=chainStart+54
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'LOSS_OF_CONTROL_UPDATE','player')
ns.UI.Update(now)
for _,unit in ipairs({'player','target','focus'}) do
 assert(not ns.UI.bars[unit].shown,'red icon disappears after the 20-second application countdown')
 local history=ns.model:GetDR(units[unit],now)
 assert(history[1].stage==3 and history[1].remaining==0,'hidden red stage remains available to the model')
 assert(history[1].stageResetAt==chainStart+59,'stage reset is measured from the final CC ending')
 assert(history[1].stageRemaining==5,'stage clock is separate from the finished display countdown')
end
handoffEvent(chainStart+59,'LOSS_OF_CONTROL_UPDATE')
handoffLoC={spellID=2637,auraInstanceID=407,startTime=chainStart+60,duration=20,timeRemaining=20}
handoffEvent(chainStart+60,'LOSS_OF_CONTROL_ADDED',1,chainStart+60)
-- Replay the reported full-duration application 18.015s after the last CC
-- disappeared. The old 20-second stage estimate incorrectly stayed red.
ns.db.stageResetSeconds=18
SlashCmdList.BJARKICC('clear')
handoffLoC=nil
handoffEvent(2657324.860,'LOSS_OF_CONTROL_UPDATE')
handoffLoC={spellID=2637,auraInstanceID=381,startTime=2657421.750,duration=20,timeRemaining=20}
handoffEvent(2657421.467,'LOSS_OF_CONTROL_ADDED',1,2657421.467)
handoffEvent(2657421.753,'LOSS_OF_CONTROL_UPDATE',1,2657421.750)
handoffLoC={spellID=2637,auraInstanceID=381,startTime=2657432.500,duration=10,timeRemaining=10}
handoffEvent(2657432.255,'LOSS_OF_CONTROL_UPDATE',1,2657421.750)
handoffEvent(2657432.543,'LOSS_OF_CONTROL_UPDATE',2,2657432.500)
handoffLoC=nil
handoffEvent(2657442.308,'LOSS_OF_CONTROL_UPDATE',2,2657432.500)
handoffLoC={spellID=2637,auraInstanceID=383,startTime=2657444.500,duration=5,timeRemaining=5}
handoffEvent(2657444.243,'LOSS_OF_CONTROL_ADDED',3,2657444.243)
handoffEvent(2657444.619,'LOSS_OF_CONTROL_UPDATE',3,2657444.500)
handoffLoC=nil
handoffEvent(2657449.235,'LOSS_OF_CONTROL_UPDATE',3,2657444.500)
handoffLoC={spellID=2637,auraInstanceID=385,startTime=2657467.250,duration=20,timeRemaining=19.994}
handoffEvent(2657467.256,'LOSS_OF_CONTROL_ADDED',1,2657467.250)
local refreshedIcon=ns.UI.bars.player.icons[1]
refreshedIcon.scripts.OnEnter(refreshedIcon)
local stageTooltip=table.concat(ns.UI.tip.lines,'\n')

-- Full Hibernate returns before the configured 18-second reset in the next
-- live report. Only an explicitly reported duration can correct this history.
SlashCmdList.BJARKICC('clear')
handoffLoC=nil
handoffEvent(2657900,'LOSS_OF_CONTROL_UPDATE')
local function advanceObserved(to)
 while now+.5<to do
  now=now+.5
  ns.eventFrame.scripts.OnEvent(ns.eventFrame,'LOSS_OF_CONTROL_UPDATE','player')
 end
end
advanceObserved(2657932.655)
handoffLoC={spellID=2637,auraInstanceID=399,startTime=2657932.750,duration=20,timeRemaining=19.999}
handoffEvent(2657932.655,'LOSS_OF_CONTROL_ADDED',1,2657932.655)
handoffEvent(2657932.926,'LOSS_OF_CONTROL_UPDATE',1,2657932.750)
advanceObserved(2657943.623); handoffLoC=nil
handoffEvent(2657943.623,'LOSS_OF_CONTROL_UPDATE',1,2657932.750)
advanceObserved(2657949.595)
handoffLoC={spellID=2637,auraInstanceID=401,startTime=2657949.750,duration=10,timeRemaining=10}
handoffEvent(2657949.595,'LOSS_OF_CONTROL_ADDED',2,2657949.595)
handoffEvent(2657949.823,'LOSS_OF_CONTROL_UPDATE',2,2657949.750)
advanceObserved(2657959.608); handoffLoC=nil
handoffEvent(2657959.608,'LOSS_OF_CONTROL_UPDATE',2,2657949.750)
handoffLoC={spellID=2637,auraInstanceID=403,startTime=2657960,duration=5,timeRemaining=4.936}
handoffEvent(2657960.064,'LOSS_OF_CONTROL_ADDED',3,2657960)
advanceObserved(2657965.070); handoffLoC=nil
handoffEvent(2657965.070,'LOSS_OF_CONTROL_UPDATE',3,2657960)
advanceObserved(2657970)
local beforeAttempt=ns.model:GetDR(units.player,now)[1]
assert(not ns.model:EstimateDR(units.player,2637,'incapacitate',now,'immune-regression',now),
 'an unconfirmed cast at the observed cap cannot extend either clock')
local afterAttempt=ns.model:GetDR(units.player,now)[1]
assert(afterAttempt.started==beforeAttempt.started and afterAttempt.stageResetAt==beforeAttempt.stageResetAt,
 'an immune-stage attempt without an aura preserves both deadlines')
advanceObserved(2657980.436)
handoffLoC={spellID=2637,auraInstanceID=405,startTime=2657980.500,duration=20,timeRemaining=20}
handoffEvent(2657980.436,'LOSS_OF_CONTROL_ADDED',3,2657980.436)
handoffEvent(2657980.571,'LOSS_OF_CONTROL_UPDATE',1,2657980.500)
local corrected=ns.UI.bars.player.icons[1]
assert(corrected.row.uncertain and corrected.row.resetEvidence=='matching-full-duration'
 and corrected.row.resetBaselineDuration==20,'duration correction exposes its bounded inference')
corrected.scripts.OnEnter(corrected)
assert(table.concat(ns.UI.tip.lines,'\n'):find('Full-duration match',1,true),
 'tooltip explains why the stage was corrected without claiming exact reset timing')
local correctedStatus=ns.BuildStatus()
assert(correctedStatus:find('Stage correction: matching full duration (20.000s)',1,true),
 'status records the duration-supported correction')
assert(correctedStatus:find('reportedDuration=20.000',1,true),
 'trace distinguishes raw reported duration from remaining-time expiry')
handoffEvent(2657980.800,'LOSS_OF_CONTROL_UPDATE',1,2657980.500)

-- The 0.4.9 live sequence begins with readable aura coverage, unlike the
-- preceding fixture which entered LoC during its empty baseline. The first
-- positive application crosses sensors before explicit duration is available.
SlashCmdList.BJARKICC('clear')
handoffAura=nil; handoffLoC=nil
handoffEvent(2659009.170,'UNIT_AURA')
advanceObserved(2659029.859)
handoffAura={spellId=2637,auraInstanceID=421,expirationTime=2659049.859,duration=20}
handoffEvent(2659029.859,'UNIT_AURA',1,2659029.859)
handoffAura={spellId=handoffSecret,auraInstanceID=421}
handoffLoC={spellID=2637,auraInstanceID=421,startTime=2659030,duration=20,timeRemaining=20}
handoffEvent(2659029.859,'LOSS_OF_CONTROL_ADDED',1,2659029.859)
handoffEvent(2659030.143,'LOSS_OF_CONTROL_UPDATE',1,2659030)
advanceObserved(2659048.138); handoffLoC=nil
handoffEvent(2659048.138,'LOSS_OF_CONTROL_UPDATE',1,2659030)
advanceObserved(2659050.047)
handoffLoC={spellID=2637,auraInstanceID=423,startTime=2659050,duration=10,timeRemaining=9.953}
handoffEvent(2659050.047,'LOSS_OF_CONTROL_ADDED',2,2659050)
advanceObserved(2659060.205); handoffLoC=nil
handoffEvent(2659060.205,'LOSS_OF_CONTROL_UPDATE',2,2659050)
handoffLoC={spellID=2637,auraInstanceID=425,startTime=2659060.250,duration=5,timeRemaining=5}
handoffEvent(2659060.205,'LOSS_OF_CONTROL_ADDED',3,2659060.205)
handoffEvent(2659060.356,'LOSS_OF_CONTROL_UPDATE',3,2659060.250)
advanceObserved(2659065.120); handoffLoC=nil
handoffEvent(2659065.120,'LOSS_OF_CONTROL_UPDATE',3,2659060.250)
advanceObserved(2659080.707)
handoffLoC={spellID=2637,auraInstanceID=427,startTime=2659080.750,duration=20,timeRemaining=19.999}
handoffEvent(2659080.707,'LOSS_OF_CONTROL_ADDED',3,2659080.707)
handoffEvent(2659080.760,'LOSS_OF_CONTROL_UPDATE',1,2659080.750)
local handoffCorrected=ns.UI.bars.player.icons[1].row
assert(handoffCorrected.resetEvidence=='matching-full-duration'
 and handoffCorrected.resetBaselineDuration==20 and handoffCorrected.uncertain,
 'the original quiet aura history supports a bounded baseline after exact-identity LoC handoff')
advanceObserved(2659100.714); handoffLoC=nil
handoffEvent(2659100.714,'LOSS_OF_CONTROL_UPDATE',1,2659080.750)
handoffLoC={spellID=2637,auraInstanceID=429,startTime=2659101,duration=10,timeRemaining=10}
handoffEvent(2659100.993,'LOSS_OF_CONTROL_ADDED',2,2659100.993)
handoffEvent(2659101.079,'LOSS_OF_CONTROL_UPDATE',2,2659101)
advanceObserved(2659110.972); handoffLoC=nil
handoffEvent(2659110.972,'LOSS_OF_CONTROL_UPDATE',2,2659101)
handoffLoC={spellID=2637,auraInstanceID=431,startTime=2659111.500,duration=5,timeRemaining=5}
handoffEvent(2659111.389,'LOSS_OF_CONTROL_ADDED',3,2659111.389)
handoffEvent(2659111.691,'LOSS_OF_CONTROL_UPDATE',3,2659111.500)
advanceObserved(2659116.432); handoffLoC=nil
handoffEvent(2659116.432,'LOSS_OF_CONTROL_UPDATE',3,2659111.500)
assert(ns.Observer.stats.scanGaps==0 and ns.OwnCasts.stats.estimated==0,
 'this handoff regression contains continuous polling and no cast-derived stage overlay')

-- Replay the 0.4.10 a477/a479/a481/a483 trace independently. Its first
-- explicit application starts only 13.851 seconds after observation began;
-- the later 20/10/5 chain, rather than a twenty-second quiet baseline, must
-- support correcting the next full duration. The second cycle refreshes a483.
SlashCmdList.BJARKICC('clear')
handoffAura=nil; handoffLoC=nil
handoffEvent(2660043.899,'UNIT_AURA')
advanceObserved(2660057.587)
handoffAura={spellId=2637,auraInstanceID=477,expirationTime=2660077.587,duration=20}
handoffEvent(2660057.587,'UNIT_AURA',1,2660057.587)
handoffAura={spellId=handoffSecret,auraInstanceID=477}
handoffLoC={spellID=2637,auraInstanceID=477,startTime=2660057.750,duration=20,timeRemaining=20}
handoffEvent(2660057.587,'LOSS_OF_CONTROL_ADDED',1,2660057.587)
handoffEvent(2660057.844,'LOSS_OF_CONTROL_UPDATE',1,2660057.750)
assert(ns.model.units[units.player].durationBaselines[2637]==nil,
 '13.851 seconds of quiet observation alone cannot establish a full-duration baseline')
advanceObserved(2660074.212); handoffLoC=nil
handoffEvent(2660074.212,'LOSS_OF_CONTROL_UPDATE',1,2660057.750)
advanceObserved(2660076.459)
handoffLoC={spellID=2637,auraInstanceID=479,startTime=2660076.750,duration=10,timeRemaining=10}
handoffEvent(2660076.459,'LOSS_OF_CONTROL_ADDED',2,2660076.459)
handoffEvent(2660076.769,'LOSS_OF_CONTROL_UPDATE',2,2660076.750)
advanceObserved(2660086.643); handoffLoC=nil
handoffEvent(2660086.643,'LOSS_OF_CONTROL_UPDATE',2,2660076.750)
advanceObserved(2660089.007)
handoffLoC={spellID=2637,auraInstanceID=481,startTime=2660089.250,duration=5,timeRemaining=5}
handoffEvent(2660089.007,'LOSS_OF_CONTROL_ADDED',3,2660089.007)
handoffEvent(2660089.324,'LOSS_OF_CONTROL_UPDATE',3,2660089.250)
advanceObserved(2660094.112); handoffLoC=nil
handoffEvent(2660094.112,'LOSS_OF_CONTROL_UPDATE',3,2660089.250)
advanceObserved(2660109.701)
handoffLoC={spellID=2637,auraInstanceID=483,startTime=2660110,duration=20,timeRemaining=20}
handoffEvent(2660109.701,'LOSS_OF_CONTROL_ADDED',3,2660109.701)
handoffEvent(2660110.187,'LOSS_OF_CONTROL_UPDATE',1,2660110)
local chainCorrected=ns.UI.bars.player.icons[1].row
assert(chainCorrected.resetEvidence=='matching-full-duration' and chainCorrected.resetBaselineDuration==20
 and chainCorrected.uncertain,'the observed halving chain supports a bounded correction')
assert(chainCorrected.resetBaselineSource=='observed-halving-chain',
 'the correction retains its distinct sequence-based provenance')
ns.UI.bars.player.icons[1].scripts.OnEnter(ns.UI.bars.player.icons[1])
assert(table.concat(ns.UI.tip.lines,'\n'):find(
 'Baseline learned from three consecutive full/half/quarter observations (provisional profile).',1,true),
 'tooltip identifies the observed sequence as provisional baseline evidence')
assert(ns.BuildStatus():find('Baseline evidence: observed full/half/quarter sequence.',1,true),
 'status exposes the correction baseline source')
advanceObserved(2660120.941)
handoffLoC={spellID=2637,auraInstanceID=483,startTime=2660121,duration=10,timeRemaining=10}
handoffEvent(2660120.941,'LOSS_OF_CONTROL_UPDATE',1,2660110)
handoffEvent(2660121.074,'LOSS_OF_CONTROL_UPDATE',2,2660121)
advanceObserved(2660130.879); handoffLoC=nil
handoffEvent(2660130.879,'LOSS_OF_CONTROL_UPDATE',2,2660121)
assert(ns.Observer.stats.handoffsPreserved==1 and ns.Observer.stats.handoffsInvalidated==0,
 'the reported exact aura-to-LoC handoff remains preserved')
assert(ns.Observer.stats.scanGaps==0 and ns.OwnCasts.stats.estimated==0,
 'the a477 replay contains continuous observation without cast predictions')
-- Synthetic extension, not part of the supplied trace: another distinct
-- five-second application must advance the corrected second cycle to three.
advanceObserved(2660132)
handoffLoC={spellID=2637,auraInstanceID=485,startTime=2660132,duration=5,timeRemaining=5}
handoffEvent(2660132,'LOSS_OF_CONTROL_ADDED',3,2660132)

-- Replay the 0.4.12 a519/a521/a523/a525 report. The first cycle's third
-- application refreshes the same a521 identity at its prior expiry, without
-- any empty observation between the ten-second and five-second durations.
SlashCmdList.BJARKICC('clear')
handoffAura=nil; handoffLoC=nil
handoffEvent(2661803.181,'UNIT_AURA')
advanceObserved(2661812.161)
handoffAura={spellId=2637,auraInstanceID=519,expirationTime=2661832.161,duration=20}
handoffEvent(2661812.161,'UNIT_AURA',1,2661812.161)
handoffAura={spellId=handoffSecret,auraInstanceID=519}
handoffLoC={spellID=2637,auraInstanceID=519,startTime=2661812.250,duration=20,timeRemaining=20}
handoffEvent(2661812.161,'LOSS_OF_CONTROL_ADDED',1,2661812.161)
handoffEvent(2661812.334,'LOSS_OF_CONTROL_UPDATE',1,2661812.250)
assert(ns.UI.bars.player.icons[1].row.fullDurationBaseline==nil
 and ns.UI.bars.player.icons[1].row.durationCandidateStep==1,
 'the short initial quiet period begins a sequence without inventing a full baseline')
advanceObserved(2661831.139); handoffLoC=nil
handoffEvent(2661831.139,'LOSS_OF_CONTROL_UPDATE',1,2661812.250)
handoffLoC={spellID=2637,auraInstanceID=521,startTime=2661831.750,duration=10,timeRemaining=10}
handoffEvent(2661831.598,'LOSS_OF_CONTROL_ADDED',2,2661831.598)
handoffEvent(2661831.934,'LOSS_OF_CONTROL_UPDATE',2,2661831.750)
assert(ns.UI.bars.player.icons[1].row.durationCandidateStep==2,
 'the ten-second application supplies the second observation')
advanceObserved(2661841.677)
handoffLoC={spellID=2637,auraInstanceID=521,startTime=2661841.750,duration=5,timeRemaining=5}
handoffEvent(2661841.677,'LOSS_OF_CONTROL_UPDATE',2,2661831.750)
handoffEvent(2661841.940,'LOSS_OF_CONTROL_UPDATE',3,2661841.750)
advanceObserved(2661846.575); handoffLoC=nil
handoffEvent(2661846.575,'LOSS_OF_CONTROL_UPDATE',3,2661841.750)
advanceObserved(2661863.386)
handoffLoC={spellID=2637,auraInstanceID=523,startTime=2661863.500,duration=20,timeRemaining=19.999}
handoffEvent(2661863.386,'LOSS_OF_CONTROL_ADDED',3,2661863.386)
handoffEvent(2661863.671,'LOSS_OF_CONTROL_UPDATE',1,2661863.500)
local refreshCorrected=ns.UI.bars.player.icons[1].row
assert(refreshCorrected.resetEvidence=='matching-full-duration'
 and refreshCorrected.resetBaselineSource=='observed-halving-chain'
 and refreshCorrected.resetBaselineDuration==20 and refreshCorrected.uncertain,
 'a verified same-ID quarter refresh supports the later bounded reset correction')
advanceObserved(2661873.175); handoffLoC=nil
handoffEvent(2661873.175,'LOSS_OF_CONTROL_UPDATE',1,2661863.500)
advanceObserved(2661876.116)
handoffLoC={spellID=2637,auraInstanceID=525,startTime=2661876.250,duration=10,timeRemaining=10}
handoffEvent(2661876.116,'LOSS_OF_CONTROL_ADDED',2,2661876.116)
handoffEvent(2661876.289,'LOSS_OF_CONTROL_UPDATE',2,2661876.250)
advanceObserved(2661886.108); handoffLoC=nil
handoffEvent(2661886.108,'LOSS_OF_CONTROL_UPDATE',2,2661876.250)
advanceObserved(2661896.789)
handoffEvent(2661896.789,'LOSS_OF_CONTROL_UPDATE',2,2661876.250)
assert(ns.Observer.stats.handoffsPreserved==1 and ns.Observer.stats.handoffsInvalidated==0
 and ns.Observer.stats.scanGaps==0 and ns.OwnCasts.stats.estimated==0,
 'the exact a521 refresh replay preserves its handoff, continuous polling and observed-only stages')

-- Real settings callbacks must change one clock without silently changing the
-- other, and rebuild tracking so old observations cannot keep stale settings.
local applicationSlider,stageSlider
for _,frame in ipairs(frames) do
 if frame.kind=='Slider' and frame.point and frame.point[3]==-240 then
  if frame.point[2]==6 then applicationSlider=frame end
  if frame.point[2]==246 then stageSlider=frame end
 end
end
assert(applicationSlider and stageSlider,'application and stage reset have separate controls')
assert(stageTooltip:find('18s after CC ends (provisional estimate)',1,true),
 'tooltip identifies the independent stage estimate')
stageSlider:SetValue(17)
assert(ns.db.resetSeconds==20 and ns.db.stageResetSeconds==17,'stage control preserves the application countdown')
assert(#ns.model:GetDR(units.player,now)==0,'changing a timing setting clears incompatible tracking history')
ns.model:Observe(units.player,{settings={category='stun',spellID=853,appliedAt=now,expires=now+5}},now,true)
local configured=ns.model:GetDR(units.player,now)[1]
assert(configured.duration==20 and configured.stageRemaining==22,'stage slider rebuilds the model with both clocks')
applicationSlider:SetValue(21)
assert(ns.db.resetSeconds==21 and ns.db.stageResetSeconds==17,'application control preserves the stage interval')
assert(#ns.model:GetDR(units.player,now)==0,'application setting also clears incompatible tracking history')
ns.model:Observe(units.player,{settings={category='stun',spellID=853,appliedAt=now,expires=now+5}},now,true)
configured=ns.model:GetDR(units.player,now)[1]
assert(configured.duration==21 and configured.stageRemaining==22,'application slider rebuilds the model without changing stage timing')
-- The actual reused icon must clear long text and reveal the final five
-- seconds without shifting the sweep, stage, or expiry.
local originalRows=ns.UI.GetRows
local remaining=5.01
ns.UI.GetRows=function(key)
 if key=='cooldown' then return {{spellID=853,category='stun',name='Enemy',started=300,duration=60,remaining=40}} end
 return {{spellID=853,category='stun',stage=1,started=300,duration=20,remaining=remaining,uncertain=true},
         {spellID=5782,category='fear',stage=2,started=300,duration=20,remaining=remaining,uncertain=true},
         {spellID=408,category='kidney',stage=3,started=300,duration=20,remaining=remaining,uncertain=true},
         {spellID=122,category='root',stage=1,started=300,duration=20,remaining=remaining,uncertain=true},
         {spellID=2637,category='incapacitate',stage=1,started=300,duration=20,remaining=remaining,uncertain=true}}
end
ns.demo=false; ns.db.locked=true
for _,key in ipairs({'player','target','focus'}) do
 ns.db.bars[key].vertical=true; ns.db.bars[key].reverse=true; ns.db.bars[key].maxIcons=30
end
for _,case in ipairs({{5.01,''},{5,'5'},{4.44,'4.4'},{.24,'0.2'},{12,''}}) do
 remaining=case[1]; ns.UI.Update(315)
 for _,key in ipairs({'player','target','focus'}) do
  local bar=ns.UI.bars[key]; local first,second=bar.icons[1],bar.icons[2]
  assert(first.time.text==case[2],'DR number appears only at five seconds or below')
  assert(first.swipe.cooldown[1]==300 and first.swipe.cooldown[2]==20,'text threshold never changes the application clock')
  local step=ns.db.bars[key].size+ns.db.bars[key].gap
  local sign=key=='player' and -1 or 1
  assert(first.point[1]==(key=='player' and 'TOPRIGHT' or 'TOPLEFT') and first.point[4]==0 and first.point[5]==0,
   'first icon stays beside its unit frame')
  assert(second.point[4]==sign*step and second.point[5]==0,'second icon completes the first row away from the frame')
  assert(bar.icons[3].point[4]==0 and bar.icons[3].point[5]==-step,'third starts the second row')
  assert(bar.icons[4].point[4]==sign*step and bar.icons[4].point[5]==-step,'fourth completes the second row')
  assert(not (bar.icons[5] and bar.icons[5].shown) and not bar.overflow.shown,'no fifth icon or overflow label is displayed')
  assert(bar.width==2*ns.db.bars[key].size+ns.db.bars[key].gap and bar.height==bar.width,'grid bounds stay fixed at two by two')
 end
 assert(ns.UI.bars.cooldown.icons[1].time.text=='40','enemy cooldown numbers retain normal full-duration display')
end
ns.UI.GetRows=originalRows
SlashCmdList.BJARKICC('cooldowns off')
assert(not ns.db.bars.cooldown.enabled and not ns.UI.bars.cooldown.shown,
 'disabling unverified cooldown HUD never requires clearing DR history')
assert(ns.BuildStatus():find('Enemy cooldown HUD: OFF by default',1,true),
 'cooldown off state is exposed in status')
-- New source path must run through the real Main event router, not only the
-- unit observer's isolated fixture. A readable harmful AoE delta survives a
-- restricted indexed scan, while the secret native DR feed is diagnostic only.
SlashCmdList.BJARKICC('clear')
now=3000000.01
units.target='Player-1-Grenade'; units.focus=nil
C_UnitAuras.GetAuraDataByIndex=function(unit)
 if unit=='target' then error('restricted target aura stream',0) end
 return nil
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target',{
 addedAuras={{spellId=4068,auraInstanceID=2300,isHarmful=true,
  expirationTime=3000003,duration=3}}
})
local grenade=ns.model:GetDR('Player-1-Grenade',now)
assert(#grenade==1 and grenade[1].spellID==4068 and grenade[1].started==3000000
 and not grenade[1].estimated,'Main routes a readable Grenade event to observed stun DR')
assert(ns.Observer.GetUnitState('target').eventWitnesses==1
 and ns.Observer.stats.auraEventPositives==1,'Main retains event evidence in diagnostics')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED',
 'target',{category=2,startTime=3000000,duration=18,showCountdown=true,isImmune=false})
assert(ns.Observer.stats.nativeDREvents==1
 and ns.model:GetDR('Player-1-Grenade',now)[1].stage==1,
 'native DR telemetry cannot advance an observed stage without a stun witness')
print('integration: TOC-order initialization, events, commands, settings, demo and bars passed')
