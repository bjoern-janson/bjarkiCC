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
function frameMethods:SetVertexColor(...) self.color={...} end
function frameMethods:SetAtlas(atlas) self.atlas=atlas end
function frameMethods:SetBlendMode(mode) self.blendMode=mode end
function frameMethods:SetDrawSwipe(value) self.drawSwipe=value end
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
for _,file in ipairs({'Bootstrap','Data','Model','Observer','OwnCasts','Anchors','UI'}) do assert(loadfile(dir..'/'..file..'.lua'))('bjarkiCC',ns) end
local main=io.open(dir..'/Main.lua'); assert(main,'Main is not implemented yet'); main:close()
assert(loadfile(dir..'/Main.lua'))('bjarkiCC',ns)
assert(ns.eventFrame.events.ADDON_LOADED,'addon initialization registered')
assert(not ns.eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED,'restricted event never registered')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'ADDON_LOADED','bjarkiCC')
assert(ns.db and ns.model and ns.UI.bars.player,'addon initializes without optional APIs')
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
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.3)
assert(not ns.UI.bars.player.shown and not ns.UI.bars.cooldown.shown,'empty bars hidden in normal play')
-- Application-based display: events observe application/removal; render the first
-- frame after removal, including early breaks, without waiting for a 0.1s tick.
ns.db.stageResetSeconds=20; ns.Command('clear')
units.target='Player-1-Dodge'
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','TargetEnemy','Cast-dodge-default',5211)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SUCCEEDED','player','Cast-dodge-default',5211)
ns.UI.Update(now)
assert(not ns.UI.bars.target.shown and #ns.model:GetDR(units.target,now,true)==0,'a cast without application cannot create a reset tracker')
units.target=nil
local liveAura
C_UnitAuras.GetAuraDataByIndex=function(unit,index) if unit=='player' and index==1 then return liveAura end end
now=101; liveAura={spellId=5211,auraInstanceID=889,expirationTime=121,duration=20}
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player'); ns.UI.Update(now)
assert(not ns.UI.bars.player.shown,'active CC does not show a DR reset icon')
assert(ns.model:GetDR(units.player,now)[1].stage==1,'application still advances the tracked stage immediately')
now=102; liveAura=nil
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.001)
local icon=ns.UI.bars.player.icons[1]
assert(ns.UI.bars.player.shown and icon.row.started==101 and icon.row.duration==20 and icon.row.remaining==19,
 'early break reveals the application countdown on the next rendered frame')
assert(icon.swipe.cooldown[1]==101 and icon.swipe.cooldown[2]==20 and icon.time.text=='','sweep and text use the original application window')
assert(icon.actionBorder and #icon.borderTextures==1 and icon.actionBorder.blendMode=='ADD' and icon.panelBackground.color[4]==0,
 'icons have only the requested native artwork uses additive blending over transparent backing')
for _,edge in ipairs(icon.borderTextures) do
 assert(edge.color[1]==.25 and edge.color[2]==1 and edge.parent.frameLevel>icon.swipe:GetFrameLevel(),'stage edges remain colored above the sweep')
end
now=103; ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player'); ns.UI.Update(now)
assert(icon.row.started==101 and icon.row.remaining==18,'repeated empty observations cannot restart the window')
now=116; ns.UI.Update(now); assert(icon.time.text=='5','the final-five-second text starts at exactly five')
now=116.6; ns.UI.Update(now); assert(icon.time.text=='4.4','decimals remain below five')
now=121; ns.UI.Update(now); assert(not ns.UI.bars.player.shown,'reset expiry hides the icon without a lingering tail')
assert(ns.BuildStatus():find('DR stage reset: 20s from last confirmed application',1,true),'status states the application policy')

-- A full twenty-second CC is hidden for its entire duration; the old display
-- application clock is also finished when it naturally ends.
ns.Command('clear'); now=200
liveAura={spellId=2637,auraInstanceID=890,expirationTime=220,duration=20}
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player'); ns.UI.Update(now)
now=207
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_SENT','player','TargetEnemy','Cast-rejected',2637)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_SPELLCAST_FAILED','player','Cast-rejected',2637)
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
local unchanged=ns.model:GetDR(units.player,now)[1]
assert(unchanged.stage==1 and unchanged.started==200 and unchanged.stageResetAt==220,
 'rejected Hibernate with unchanged aura cannot advance the stage or refresh the application deadline')
now=219.9; ns.UI.Update(now); assert(not ns.UI.bars.player.shown,'full-duration CC remains hidden until its end')
now=220; liveAura=nil; ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','player')
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.001)
assert(not ns.UI.bars.player.shown,
 'full CC expiry creates no fresh countdown')

-- Model handles overlap and partial evidence; the real UI must wait for the
-- category's final end and must not interpret hidden omissions as a fade.
ns.Command('clear'); now=300; ns.Observer.Scan(now)
ns.model:Observe(units.player,{a={category='stun',spellID=5211,appliedAt=300,expires=310},
 b={category='stun',spellID=20549,appliedAt=301,expires=305}},301,true)
now=302; ns.model:Observe(units.player,{a={category='stun',spellID=5211,appliedAt=300,expires=310}},now,true)
ns.UI.Update(now); assert(not ns.UI.bars.player.shown,'ending one overlap cannot show the reset icon while another stun persists')
now=303; ns.model:Observe(units.player,{},now,false); ns.UI.Update(now)
assert(not ns.UI.bars.player.shown,'restricted empty snapshots cannot invent a break')
now=304; ns.model:Observe(units.player,{},now,true); ns.UI.Update(now)
assert(icon.row.started==301 and icon.row.remaining==17 and icon.row.stage==2,'last application owns the category countdown')

-- A readable expiry remains a conservative natural-end fallback if a fresh
-- empty list is unavailable. Unknown end times stay hidden instead.
ns.Command('clear'); now=400; ns.Observer.Scan(now)
ns.model:Observe(units.player,{a={category='stun',spellID=5211,appliedAt=400,expires=403}},now,true)
now=403; ns.UI.Update(now)
assert(ns.UI.bars.player.shown and icon.row.started==400 and icon.row.remaining==17 and icon.row.uncertain,'readable natural expiry reveals the remaining application window')
ns.Command('clear'); ns.Observer.Scan(now); ns.model:Observe(units.player,{a={category='stun',spellID=5211,appliedAt=400}},400,true)
ns.UI.Update(410); assert(not ns.UI.bars.player.shown,'unknown active CC end never invents a display deadline')

-- Focus visibility, settings and synthetic preview remain independent of hits.
units.focus=units.player; ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_FOCUS_CHANGED')
ns.demo=true; ns.UI.Update(now); ns.UI.OpenOptions()
assert(ns.UI.bars.player.icons[1].actionBorder.blendMode=='ADD','preview uses the requested native artwork')
ns.demo=false; ns.db.showNames=false; ns.db.showDRText=false
local refreshedIcon=ns.UI.bars.player.icons[1]
-- Historical traces below still verify application identity/stage evidence
-- through real Main and Observer. Only their display expectations change.
ns.db.stageResetSeconds=20
-- Preserve the recorded legacy-policy regressions separately from the new
-- shipping policy exercised above and below.
local actualNew=ns.Model.New
ns.Model.New=function(a,b) return actualNew(a,ns.db.stageResetSeconds,false) end
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
 now=at; ns.eventFrame.scripts.OnEvent(ns.eventFrame,event,'player'); ns.UI.Update(now)
 for _,unit in ipairs({'player','target','focus'}) do
  local raw=ns.model:GetDR(units[unit],now)[1]
  if stage then
   assert(raw and raw.stage==stage and raw.observedStage==stage,'historical Main replay preserves observed stages on '..unit..' at '..now..' expected '..stage..' got '..tostring(raw and raw.stage))
   assert(raw.started==start,'application evidence remains calibrated independently of display timing')
  end
  local rows=ns.UI.GetRows(unit,now)
  local bar=ns.UI.bars[unit]
  if #rows>0 then
   local icon=bar.icons[1]; local remaining=raw.remaining
   assert(bar.shown and not raw.active and icon.row.stage==raw.stage,'only ended historical CC is rendered')
   assert(icon.row.started==raw.started
    and icon.swipe.cooldown[1]==icon.row.started,'display number and sweep share the application boundary')
   assert(icon.time.text==(remaining<=5 and ns.UI.FormatTime(remaining) or ''),'application countdown obeys final-five-second text policy')
   local color=({{.25,1,.3},{1,.8,.15},{1,.2,.15}})[raw.stage]
   assert(icon.actionBorder and #icon.borderTextures==1 and icon.actionBorder.blendMode=='ADD','historical renders use additive native artwork')
   for _,edge in ipairs(icon.borderTextures) do
    assert(edge.color[1]==color[1] and edge.color[2]==color[2] and edge.color[3]==color[3],'faded icon retains the actual DR stage color')
   end
  else assert(not bar.shown,'active or expired historical CC has no reset icon') end
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
assert(not ns.UI.bars.player.shown,'the active half-duration CC does not display its reset window yet')
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
 assert(not ns.UI.bars[unit].shown,'full Hibernate has no time left at expiry')
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
 assert(not ns.UI.bars[unit].shown,'red icon expires at its application deadline')
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
local corrected={row=ns.model:GetDR(units.player,now)[1]}
assert(corrected.row.uncertain and corrected.row.resetEvidence=='matching-full-duration'
 and corrected.row.resetBaselineDuration==20,'duration correction exposes its bounded inference')
refreshedIcon.scripts.OnEnter(corrected)
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
local handoffCorrected=ns.model:GetDR(units.player,now)[1]
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
local chainCorrected=ns.model:GetDR(units.player,now)[1]
assert(chainCorrected.resetEvidence=='matching-full-duration' and chainCorrected.resetBaselineDuration==20
 and chainCorrected.uncertain,'the observed halving chain supports a bounded correction')
assert(chainCorrected.resetBaselineSource=='observed-halving-chain',
 'the correction retains its distinct sequence-based provenance')
refreshedIcon.scripts.OnEnter({row=chainCorrected})
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
assert(ns.model:GetDR(units.player,now)[1].fullDurationBaseline==nil
 and ns.model:GetDR(units.player,now)[1].durationCandidateStep==1,
 'the short initial quiet period begins a sequence without inventing a full baseline')
advanceObserved(2661831.139); handoffLoC=nil
handoffEvent(2661831.139,'LOSS_OF_CONTROL_UPDATE',1,2661812.250)
handoffLoC={spellID=2637,auraInstanceID=521,startTime=2661831.750,duration=10,timeRemaining=10}
handoffEvent(2661831.598,'LOSS_OF_CONTROL_ADDED',2,2661831.598)
handoffEvent(2661831.934,'LOSS_OF_CONTROL_UPDATE',2,2661831.750)
assert(ns.model:GetDR(units.player,now)[1].durationCandidateStep==2,
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
local refreshCorrected=ns.model:GetDR(units.player,now)[1]
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

-- Restore and verify the shipping policy after the legacy trace fixtures.
ns.Model.New=actualNew
ns.Command('clear'); ns.Observer.Scan(now)
assert(ns.model.resetOnApplication and ns.model.resetSeconds==20)
ns.model:Observe(units.player,{s={category='stun',spellID=853,appliedAt=now,expires=now+5}},now,true)
ns.model:Observe(units.player,{},now+2,true)
local view=ns.UI.GetRows('player',now+2)[1]
assert(view.started==now and view.duration==20 and view.remaining==18,'fade reveals the original application clock')
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
  assert(first.swipe.drawSwipe==false,'DR artwork stays readable without a dark radial overlay')
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
 assert(ns.UI.bars.cooldown.icons[1].swipe.drawSwipe==true,'enemy cooldown presentation keeps its own sweep')
end
ns.UI.GetRows=originalRows


-- Exercise the actual event payload route with the full-scan API denied.
ns.Command('clear'); now=500; units.target='Player-1-Event'; units.focus=units.target
C_LossOfControl=nil
C_UnitAuras={GetAuraDataByIndex=function() error('restricted enumeration') end}
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_TARGET_CHANGED')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','target',
 {isFullUpdate=false,addedAuras={{spellId=2637,auraInstanceID=9990,isHarmful=true,expirationTime=520,duration=20}}})
local eventRow=ns.model:GetDR(units.target,now)[1]
assert(eventRow and eventRow.stage==1 and not eventRow.estimated,'readable added aura is hit evidence even when indexed enumeration fails')
ns.UI.Update(now); assert(not ns.UI.bars.target.shown,'new confirmed active CC remains hidden')
now=504
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'UNIT_AURA','focus',{isFullUpdate=false,removedAuraInstanceIDs={9990}})
ns.eventFrame.scripts.OnUpdate(ns.eventFrame,.001)
assert(ns.UI.bars.target.shown and ns.UI.bars.focus.shown,'explicit event removal reveals aliased grids on the next frame')
assert(ns.UI.bars.target.icons[1].row.remaining==16 and ns.UI.bars.target.icons[1].row.started==500,
 'event removal preserves the original twenty-second application deadline')
assert(ns.BuildStatus():find('auraEventsAdded: 1',1,true) and ns.BuildStatus():find('auraEventsRemoved: 1',1,true),
 'status makes accepted event evidence visible without a manual macro')

-- DR-only spells need deterministic art when the caster's spell texture is
-- unavailable. All Hibernate ranks must agree across player/target/focus.
function frameMethods:SetTexture(texture) self.textureAsset=texture end
local savedRows=ns.UI.GetRows
local textureSecret={}
issecretvalue=function(v) return rawequal(v,textureSecret) end
canaccessvalue=function(v) return not rawequal(v,textureSecret) end
for _,id in ipairs({2637,18657,18658}) do
 ns.UI.GetRows=function(key)
  if key=='cooldown' then return {} end
  return {{spellID=id,category='incapacitate',stage=1,started=100,duration=20,remaining=8}}
 end
 for _,mode in ipairs({'nil','secret','zero','error','readable'}) do
  C_Spell={GetSpellTexture=function()
   if mode=='secret' then return textureSecret end
   if mode=='zero' then return 0 end
   if mode=='error' then error('restricted texture') end
   if mode=='readable' then return 136090 end
  end}
  ns.UI.Update(112)
  for _,key in ipairs({'player','target','focus'}) do
   assert(ns.UI.bars[key].icons[1].texture.textureAsset==table.concat({'Interface','Icons','Spell_Nature_Sleep'},string.char(92)),
    'Hibernate must retain its own icon on every POV and rank when texture access is '..mode)
  end
 end
end
ns.UI.GetRows=savedRows

print('integration: TOC-order initialization, events, commands, settings, demo and bars passed')
