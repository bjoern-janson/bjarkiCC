-- Regression for the live 0.4.0 Backdrop.lua secret-width error. This fixture
-- models the template's implicit OnSizeChanged geometry arithmetic; it does
-- not emulate WoW's secret system or prove live-client correctness.
local ns, frames, methods = {}, {}, {}
local restrictedGeometry, restrictedReads = false, 0
local poison = setmetatable({}, {
    __div = function() error('BackdropTemplate attempted arithmetic on secret width') end,
})
local function anchoredToNative(frame, visited)
    if type(frame) ~= 'table' then return false end
    visited = visited or {}
    if visited[frame] then return false end
    visited[frame] = true
    if frame.native then return true end
    if anchoredToNative(frame.parent, visited) then return true end
    return frame.point and anchoredToNative(frame.point[2], visited) or false
end
local function dimension(frame, value)
    if restrictedGeometry and anchoredToNative(frame) then
        restrictedReads = restrictedReads + 1
        return poison
    end
    return value
end
function methods:GetWidth() return dimension(self, self.width or 28) end
function methods:GetHeight() return dimension(self, self.height or 28) end
function methods:GetEffectiveScale() return dimension(self, 1) end
local function backdropCoordinates(frame)
    if frame.template == 'BackdropTemplate' and frame.backdropInfo then
        -- BackdropTemplateMixin:OnBackdropSizeChanged -> SetupTextureCoordinates.
        -- A constant SetSize does not make geometry reads safe after anchoring.
        local repeatX = frame:GetWidth() / 1
        local repeatY = frame:GetHeight() / 1
        local scale = frame:GetEffectiveScale()
        frame.backdropRepeat = {repeatX * scale, repeatY * scale}
    end
end
function methods:SetSize(w, h)
    self.width, self.height = w, h
    backdropCoordinates(self)
end
function methods:SetWidth(w) self.width = w; backdropCoordinates(self) end
function methods:SetHeight(h) self.height = h; backdropCoordinates(self) end
function methods:SetBackdrop(info) self.backdropInfo = info; backdropCoordinates(self) end
function methods:SetPoint(...) self.point = {...} end
function methods:SetAllPoints(relative) self.point = {'TOPLEFT', relative or self.parent} end
function methods:ClearAllPoints() self.point = nil end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsVisible() return self.shown end
function methods:GetFrameLevel() return 1 end
function methods:GetRight() return 250 end
function methods:GetTop() return 200 end
function methods:SetText(value) self.text = value end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetVertexColor(...) self.color = {...} end
for _, name in ipairs({'SetFont','SetTextColor','SetTexture','SetTexCoord',
    'SetFrameStrata','SetMovable','SetClampedToScreen','RegisterForDrag','EnableMouse',
    'SetDrawEdge','SetHideCountdownNumbers','SetReverse','SetFrameLevel',
    'SetCooldown','SetBackdropColor','SetBackdropBorderColor'}) do
    methods[name] = function() end
end
local function object(kind, name, parent, template)
    local result = setmetatable({kind=kind, name=name, parent=parent, template=template,
        scripts={}, shown=true}, {__index=methods})
    frames[#frames + 1] = result
    if name then _G[name] = result end
    return result
end
function methods:CreateFontString() return object('FontString', nil, self) end
function methods:CreateTexture() return object('Texture', nil, self) end
CreateFrame = object
UIParent = object('Frame', 'UIParent')
STANDARD_TEXT_FONT = 'font.ttf'
local now, aura = 100, nil
GetTime = function() return now end
InCombatLockdown = function() return false end
UnitGUID = function() return 'Player-1-A' end
UnitIsPlayer = function() return true end
issecretvalue = function(value) return rawequal(value, poison) end
canaccessvalue = function(value) return not rawequal(value, poison) end
C_UnitAuras = {GetAuraDataByIndex=function(_, index) if index == 1 then return aura end end}
C_Spell = {GetSpellTexture=function() return 135963 end}
for _, name in ipairs({'PlayerFrame','TargetFrame','FocusFrame'}) do
    local native = object('Frame', name, UIParent)
    native.native = true
    native.healthbar = object('StatusBar', nil, native)
end
local dir = ADDON_DIR or 'work/bjarkiCC'
for _, file in ipairs({'Bootstrap','Data','Model','Observer','OwnCasts','Anchors'}) do
    assert(loadfile(dir..'/'..file..'.lua'))('bjarkiCC', ns)
end
assert(loadfile(UI_SOURCE_OVERRIDE or (dir..'/UI.lua')))('bjarkiCC', ns)
ns.InitializeDB()
ns.model = ns.Model.New(20)
ns.Observer.Init()
ns.OwnCasts.Init()
ns.Observer.Scan(now)
ns.UI.Init()

-- Calibrate the fixture against the exact unsafe pattern before the regression.
local legacy = object('Frame', nil, PlayerFrame, 'BackdropTemplate')
legacy:SetBackdrop({edgeSize=1})
restrictedGeometry = true
local ok, err = pcall(legacy.SetSize, legacy, 28, 28)
assert(not ok and tostring(err):find('secret width', 1, true), 'fixture must expose BackdropTemplate geometry arithmetic')
legacy:SetBackdrop(nil)
restrictedReads, restrictedGeometry = 0, false

-- The first CC draws normally. The removal transition then makes native
-- geometry inaccessible; repeated redraws and the next CC cannot read it.
now = 121
aura = {spellId=853, auraInstanceID=1, expirationTime=127}
ns.Observer.Scan(now)
ns.UI.Update(now)
for _, unit in ipairs({'player','target','focus'}) do
    assert(ns.UI.bars[unit].shown and ns.UI.bars[unit].icons[1].shown, 'CC must still render on every aliased frame')
end
restrictedGeometry = true
now, aura = 127, nil
ns.Observer.Scan(now)
for tick=1,20 do ns.UI.Update(now + tick/10) end
now = 130
aura = {spellId=853, auraInstanceID=2, expirationTime=133}
ns.Observer.Scan(now)
ns.UI.Update(now)
assert(ns.UI.bars.player.icons[1].row.stage == 2, 'the next CC remains renderable after removal')
now, aura = 133, nil
ns.Observer.Scan(now)
ns.UI.Update(now)
ns.db.locked = false
ns.UI.ApplyLayout()
ns.db.locked = true
ns.UI.ApplyLayout()
now = 151
ns.Observer.Scan(now)
ns.UI.Update(now)
assert(not ns.UI.bars.player.shown, 'expired DR hides normally')
assert(restrictedReads == 0, 'anchored bars, icons and their children must not read restricted dimensions or scale')
for _, frame in ipairs(frames) do
    if frame ~= legacy and anchoredToNative(frame) then
        assert(frame.template ~= 'BackdropTemplate', 'anchored display cannot install BackdropTemplate size callbacks')
    end
end
print('backdrops: template failure reproduced; CC application, removal, next CC and layout avoid restricted geometry reads')
