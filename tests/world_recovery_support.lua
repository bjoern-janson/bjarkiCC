return function()
_G.BjarkiEvidenceV1=nil
_G.bjarkiCCDB=nil
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
function frameMethods:SetAlpha(v) self.alpha=v end
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
-- Exercise the actual runtime load order, including every foundation module.

UnitExists=function(unit) return units[unit]~=nil end
UnitIsUnit=function(a,b) return units[a]~=nil and units[a]==units[b] end
C_NamePlate={GetNamePlateForUnit=function() return nil end}
local timers={}
C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
function frameMethods:RegisterUnitEvent(event,a,b)
 self.events[event]={ [a]=true }; if b then self.events[event][b]=true end
end
local loadedModules={}
for line in io.lines(dir..'/bjarkiCC.toc') do
 local file=line:match('^%s*([%w_]+%.lua)%s*$')
 if file then
  assert(not loadedModules[file],'TOC must not load a module twice')
  assert(loadfile(dir..'/'..file))('bjarkiCC',ns)
  loadedModules[file]=true
 end
end
assert(loadedModules['Claims.lua'] and loadedModules['CooldownEvidence.lua']
 and loadedModules['GCDPlates.lua'] and loadedModules['Main.lua'],'current TOC loads foundation dependencies')
assert(ns.eventFrame.events.ADDON_LOADED,'addon initialization registered')
assert(not ns.eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED,'restricted event never registered')
ns.eventFrame.scripts.OnEvent(ns.eventFrame,'ADDON_LOADED','bjarkiCC')
assert(ns.db and ns.model and ns.UI.bars.player,'addon initializes without optional APIs')
assert(ns.db.bars.cooldown.enabled==false,'experimental enemy cooldown HUD defaults off')

local H={ns=ns,units=units,auras={},hostile={},players={},queries={},blocked={},hidden={}}
UnitCanAttack=function(_,unit) return H.hostile[unit] == true end
UnitIsPlayer=function(unit) if H.players[unit]~=nil then return H.players[unit] end; return units[unit]~=nil end
issecretvalue=function(value)return value==H.hidden end
canaccessvalue=function(value)return value~=H.hidden end
C_UnitAuras.GetUnitAuraBySpellID=function(unit,id)
 H.queries[#H.queries+1]={unit=unit,id=id}
 if H.blocked[unit]=='error' then error('modeled unavailable query') end
 if H.blocked[unit]=='secret' then return H.hidden end
 return H.auras[unit] and H.auras[unit][id]
end
function H.time(value)now=value end
function H.world()ns.eventFrame.scripts.OnEvent(ns.eventFrame,'PLAYER_ENTERING_WORLD')end
function H.row(guid,id)local caster=ns.model.casters[guid];return caster and caster.cooldowns[id or 22812]end
function H.publish(unit,guid,aura,stamp,newApplication)
 return ns.EvidenceBus:Publish({source='bjarkiPortraits',kind='aura-positive',isHelpful=true,
  unit=unit,recipientGUID=guid,spellId=aura.spellId,auraInstanceID=aura.auraInstanceID,
  expirationTime=aura.expirationTime,duration=aura.duration,observedAt=stamp or now,
  newApplication=newApplication==true})
end
return H
end
