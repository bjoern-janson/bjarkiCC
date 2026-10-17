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
function frameMethods:SetSize(w,h) self.width=w; self.height=h end
function frameMethods:SetPoint(...) self.point={...} end
function frameMethods:SetBackdropBorderColor(...) self.border={...} end
function frameMethods:SetColorTexture(...) self.color={...} end
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
function frameMethods:SetCooldown(start,duration) assert(type(start)=='number' and type(duration)=='number'); self.cooldown={start,duration} end
local function object(kind,name,parent,template)
 local f=setmetatable({kind=kind,name=name,parent=parent,template=template,scripts={},events={},shown=true},{__index=frameMethods})
 frames[#frames+1]=f; if name then _G[name]=f end; return f
end
function frameMethods:CreateFontString() return object('FontString',nil,self) end
function frameMethods:CreateTexture() return object('Texture',nil,self) end
CreateFrame=object; UIParent=object('Frame','UIParent'); STANDARD_TEXT_FONT='font.ttf'; UISpecialFrames={}; SlashCmdList={}
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
for _,file in ipairs({'Bootstrap','Data','Model','Observer','OwnCasts','Anchors','UI'}) do assert(loadfile(dir..'/'..file..'.lua'))('bjarkiCC',ns) end
local main=io.open(dir..'/Main.lua'); assert(main,'Main is not implemented yet'); main:close()
assert(loadfile(dir..'/Main.lua'))('bjarkiCC',ns)
assert(ns.eventFrame.events.ADDON_LOADED,'addon initialization registered')
assert(not ns.eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED,'restricted event never registered')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'ADDON_LOADED','bjarkiCC')
assert(ns.db and ns.model and ns.UI.bars.player,'addon initializes without optional APIs')
assert(not ns.UI.bars.player.template and not ns.UI.bars.target.template and not ns.UI.bars.focus.template,
 'unit-anchored bars must not inherit BackdropTemplate secret-size arithmetic')
assert(ns.UI.bars.player.point[2]==playerHealth and ns.UI.bars.target.point[2]==targetHealth and ns.UI.bars.focus.point[2]==focusHealth,'default DR bars attach to the matching modern health regions')
assert(ns.UI.bars.player.point[1]=='BOTTOMLEFT' and ns.UI.bars.player.point[3]=='TOPLEFT'
 and ns.UI.bars.player.point[4]==24 and ns.UI.bars.player.point[5]==24,'player starts above the inward health edge')
assert(ns.UI.bars.target.point[1]=='BOTTOMRIGHT' and ns.UI.bars.target.point[3]=='TOPRIGHT'
 and ns.UI.bars.target.point[4]==-24 and ns.UI.bars.target.point[5]==24,'target starts above the mirrored inward health edge')
assert(ns.UI.bars.player.anchorFrame==PlayerFrame and ns.UI.bars.focus.anchorFrame==FocusFrame,'native visibility identity remains distinct from health-region geometry')
assert(ns.eventFrame.events.PLAYER_FOCUS_CHANGED and ns.eventFrame.events.PLAYER_REGEN_ENABLED,'focus and anchor recovery events registered')
assert(ns.eventFrame.events.UNIT_SPELLCAST_SENT and ns.eventFrame.events.UNIT_SPELLCAST_SUCCEEDED
 and ns.eventFrame.events.UNIT_SPELLCAST_FAILED and ns.eventFrame.events.UNIT_SPELLCAST_INTERRUPTED,'outgoing cast correlation and cancellation events registered')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.3)
assert(not ns.UI.bars.player.shown and not ns.UI.bars.cooldown.shown,'empty bars hidden in normal play')
-- CC can apply and be removed between render ticks; event callbacks must sample it.
now=100.1
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if unit=='player' and index==1 then return {spellId=853,auraInstanceID=77,expirationTime=106} end
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
ns.UI.Update(now)
assert(ns.UI.bars.player.shown and ns.UI.bars.player.icons[1].time.text=='20','application immediately supplies a visible DR timer')
assert(ns.UI.bars.player.icons[1].swipe.cooldown[1]==100.1,'application supplies the cooldown sweep start')
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
assert(ns.UI.bars.target.shown and targetIcon.row.estimated and targetIcon.time.text=='20'
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
assert(targetIcon.row.stage==2 and targetIcon.row.started==102 and targetIcon.time.text=='20','shorter consecutive CC refreshes application timer and advances stage')
for _,edge in ipairs(targetIcon.borderTextures) do
 assert(edge.color[1]==1 and edge.color[2]==.8 and edge.color[3]==.15,'second observed application renders the yellow stage border')
end
assert(not targetIcon.state.shown and targetIcon.row.uncertain,'derived refresh retains uncertainty without an icon marker')
assert(ns.BuildStatus():find('DR stun: stage 2; started 102.000',1,true),'status exposes the current application clock for runtime diagnosis')
now=103; targetAura.expirationTime=105.5; targetAura.duration=2.5
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==3 and targetIcon.row.started==103 and targetIcon.time.text=='20','third readable application refreshes the timer and reaches the final DR stage')
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
assert(ns.UI.bars.target.shown and ns.UI.bars.focus.shown and targetIcon.time.text=='20'
 and targetIcon.row.stage==1 and targetIcon.row.estimated,'space-qualified destination starts both same-GUID views immediately on success')
now=210
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-space-2',6770)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-space-2',6770)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==2 and targetIcon.time.text=='20','second hidden cast advances and refreshes the inferred timer')
now=211
C_UnitAuras.GetAuraDataByIndex=function(unit,index)
 if (unit=='target' or unit=='focus') and index==1 then
  return {spellId=6770,auraInstanceID=202,expirationTime=220,duration=10}
 end
end
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(not targetIcon.row.estimated and targetIcon.row.stage==2 and targetIcon.row.observedStage==1
 and targetIcon.row.stageEstimated and targetIcon.row.uncertain and targetIcon.time.text=='19',
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
assert(targetIcon.row.stage==3 and targetIcon.row.started==215 and targetIcon.time.text=='20',
 'the third application still starts its full red countdown')
for _,time in ipairs({218,222,234}) do
 now=time
 local castID='Cast-cap-'..time
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson',castID,2637)
 ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player',castID,2637)
 ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
 assert(targetIcon.row.stage==3 and targetIcon.row.started==215 and targetIcon.row.remaining==235-now,
  'attempts at the final DR stage must preserve the original deadline')
 assert(targetIcon.swipe.cooldown[1]==215 and targetIcon.time.text==tostring(235-now),
  'neither sweep nor number can restart on an unconfirmed immune-stage attempt')
 assert(ns.UI.bars.focus.icons[1].row.started==215,'same-GUID focus shares the preserved deadline')
end
assert(ns.OwnCasts.stats.estimated==3,'suppressed cap attempts are not accepted DR estimates')
now=235; ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.2)
assert(not ns.UI.bars.target.shown and not ns.UI.bars.focus.shown,'red icons expire on the third application deadline')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','Björn Janson','Cast-after-cap',2637)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-after-cap',2637)
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.1)
assert(targetIcon.row.stage==1 and targetIcon.row.started==235 and targetIcon.time.text=='20',
 'a new cast after expiry begins a fresh first cycle')
UnitName=originalUnitName
issecretvalue=function() return false end
C_UnitAuras.GetAuraDataByIndex=function() return nil end
units.target=nil; units.focus=nil
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
SlashCmdList.BJARKICC('clear')
SlashCmdList.BJARKICC('test')
assert(ns.demo and ns.UI.bars.player.icons[1].shown,'demo visible')
assert(ns.UI.bars.focus.icons[1].shown,'focus has an independent preview')
assert(ns.UI.bars.player.title.shown,'test bars identified')
assert(not ns.UI.bars.player.icons[1].caption.shown,'no category captions in minimal view')
assert(not ns.UI.bars.player.icons[1].state.shown,'known DR uses border without duplicate stage text')
assert(not ns.UI.bars.cooldown.icons[1].caption.shown and not ns.UI.bars.cooldown.icons[1].state.shown,'cooldown minimal view has just timer')
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
assert(not focusBar.anchorPending and focusBar.point[2]==focusHealth,'combat exit restores the modern health-region anchor')
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
assert(ns.UI.bars.player.height==90,'vertical DR rows have no phantom caption spacing')
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
assert(ns.UI.bars.player.icons[1].time.text=='20','DR countdown is visible from application while CC remains active')
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
  if stage then
   local icon=bar.icons[1]
   assert(bar.shown and icon.row.stage==stage and icon.row.observedStage==stage,
    'Hibernate source handoff must not invent a stage on '..unit)
   assert(icon.row.started==start and icon.swipe.cooldown[1]==start,
    'numeric countdown and sweep share the calibrated application time')
   assert(icon.time.text==ns.UI.FormatTime(start+20-now),'countdown retains the application policy')
   local color=({{.25,1,.3},{1,.8,.15},{1,.2,.15}})[stage]
   for _,edge in ipairs(icon.borderTextures) do
    assert(edge.color[1]==color[1] and edge.color[2]==color[2] and edge.color[3]==color[3],
     'rendered Hibernate border follows the corrected observed cycle')
   end
   assert(not icon.state.shown,'no DR question mark is reintroduced')
  else
   assert(not bar.shown,'application timer expires without being restarted by removal')
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
assert(ns.UI.bars.player.icons[1].time.text=='15','half-duration CC now has the yellow second cycle at 15s')
handoffLoC=nil
handoffEvent(2655647.495,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
handoffEvent(2655652.402,'LOSS_OF_CONTROL_UPDATE',2,2655637.750)
assert(ns.OwnCasts.stats.estimated==0,'recipient regression is entirely observed history')
handoffEvent(2655657.750,'LOSS_OF_CONTROL_UPDATE')
print('integration: TOC-order initialization, events, commands, settings, demo and bars passed')
