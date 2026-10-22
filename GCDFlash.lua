local _, root = ...
local ns = root.GCD
local Public, Yes = ns.Public, ns.Yes

-- Compact, display-only GCD flashes by tarolg (MIT), adapted for bjarkiCC.
-- One place's flashes (a "spot") is an enemy nameplate's.
-- Each flash is an icon with a clock sweep over it that ticks down over a
-- global cooldown (1.5 s by default), as Blizzard's action buttons do, and
-- the spell's name under it, then it fades. Three things flash, each with
-- its own edge colour so the player can tell the routes apart:
--
-- Their casts (gold). Every spell a unit finishes arrives as
-- UNIT_SPELLCAST_SUCCEEDED (unitTarget, castGUID, spellID, castBarID;
-- UnitDocumentation.lua). For other players the spell ID is hidden
-- (SecretWhenUnitSpellCastRestricted), but it still goes to
-- C_Spell.GetSpellName and GetSpellTexture (SecretArguments =
-- AllowedWhenTainted), whose answers only reach this file's text and texture:
-- Forever Diagnostics drew enemy players' casts that way in battleground
-- combat on 1.60.1.70374 (ws-enemy-cast-drawn, 15 October 2026), and Forever
-- Cast 0.15.0 draws instants the same way. Most enemy instants send no event
-- at all (a priest's Shadow Word: Pain in a duel, 15 October 2026), which is
-- what the next two routes are for.
--
-- Their new buffs (green). Many instants put a buff on the caster (a shield,
-- Ghost Wolf, Blood Fury). Blizzard_AuraContainer (## UseSecureEnvironment)
-- reads the unit's auras itself and draws into regions an addon hands over:
-- an AuraContainer from CustomAuraContainerTemplate, whose buttons
-- (CustomAuraButtonSharedMixin, Blizzard_CustomAuraButton.lua) take an icon
-- texture (SetIcon), a text for the aura's name (SetSpellName) and animation
-- groups Blizzard plays only when an aura is newly assigned to the button
-- (AddAuraAssignedAnimation; ApplyAuraAssignmentAnimations on
-- Enum.CustomAuraButtonUpdateMode.Assignment, never on an update). One group,
-- newest first (AuraInstanceIDOnly, Reverse); a refresh keeps each button on
-- its aura (RefreshAuraGroup, Blizzard_AuraContainerGroups.lua), so only a
-- buff new to the unit flashes. Forever Cast 0.16.0 flashed a hunter's Blood
-- Fury by name this way in a duel in combat (1.60.1.70425, 16 October 2026,
-- cast-new-buffs). Every button rests at alpha 0 and is seen only while its
-- own flash plays.
--
-- Your new debuffs, in duels (red). Most other instants land a debuff on you
-- (Shadow Word: Pain, Concussive Shot, a sting). The same container pointed
-- at "player" with the HARMFUL filter flashes each new debuff of yours, and
-- its holder sits on your duel opponent's spot: in a duel only one enemy can
-- have put it there, so the guess cannot be wrong. Outside duels nothing is
-- attributed (AGENTS.md: guesses stay in Forever Diagnostics until proven).
-- The other session's frame-by-frame read of Hydra's clip (16 October 2026)
-- showed the enemy's Shadow Word: Pain icon on their plate in the same frame
-- the debuff landed on him. Not yet tried in client: whether the container
-- takes "player" and HARMFUL as it takes an enemy and HELPFUL.
--
-- When a container's unit changes, every aura the unit has gets a button and
-- flashes at once; none of them is new, so the container's holder stays at
-- alpha 0 until those have run (SETTLE). As in Forever Enemy Buffs,
-- initializeFrame runs before Blizzard locks a button against addon code
-- while C_Secrets.ShouldAurasBeSecret() is true, so a look change reaches
-- older buttons only once auras are not secret (RestyleAll). Nothing here
-- reads an aura, compares a hidden value or reads back a widget.

local MAX_BUTTONS = 6
local MAX_CAST_FLASHES = 4
local FADE_IN, FADE_OUT = 0.1, 0.3
local WHITE = "Interface\\Buttons\\WHITE8X8"
ns.COLORS = {
    cast = { 0.95, 0.76, 0.35 },
    buff = { 0.3, 0.85, 0.35 },
    debuff = { 0.9, 0.25, 0.2 },
}

local available, broken
local feeds = {}      -- every feed (one container each)
local pending = false -- a look change waits for auras to stop being secret

-- Blizzard_AuraContainer copies its sort tables into the global environment
-- (Blizzard_AuraContainerShared.lua); AnchorUtil is Blizzard_SharedXMLBase's.
local function Available()
    if not available then
        available = type(AuraContainerSortMethod) == "table" and type(AuraContainerSortMethod.AuraInstanceIDOnly) == "number"
            and type(AuraContainerSortDirection) == "table" and type(AuraContainerSortDirection.Reverse) == "number"
            and type(AnchorUtil) == "table" and type(AnchorUtil.FlowLayoutAxis) == "table"
            and type(AnchorUtil.FlowDirection) == "table"
    end
    return available and not broken
end
function ns.FlashAvailable() return Available() == true end

local function CanTouch()
    if type(C_Secrets) ~= "table" or type(C_Secrets.ShouldAurasBeSecret) ~= "function" then return true end
    local secret = C_Secrets.ShouldAurasBeSecret()
    return Public(secret) and secret == false
end

-- An enemy, or a unit whose side is hidden (it may be one).
function ns.Hostile(unit)
    if not unit or not Yes(UnitExists(unit)) then return false end
    local me = UnitIsUnit(unit, "player")
    if Public(me) and me then return false end
    local hostile = UnitCanAttack("player", unit)
    return not Public(hostile) or hostile == true
end

-- A duel opponent: a player of your own faction you can attack, outside
-- instances (battlegrounds and dungeons have no duels; a mind-controlled
-- teammate there would pass the rest). No API names the opponent
-- (DuelInfoDocumentation.lua has only events), so Plates.lua also asks that
-- only one plate passes, or that it is your target.
function ns.Opponent(unit)
    if not unit or not Yes(UnitExists(unit)) or not Yes(UnitIsPlayer(unit)) then return false end
    if not Yes(UnitCanAttack("player", unit)) then return false end
    local inside = IsInInstance()
    if not Public(inside) or inside == true then return false end
    local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(unit)
    return ns.Text(mine) and ns.Text(theirs) and mine ~= "" and mine == theirs
end

-- Parts ---------------------------------------------------------------------------------
-- The flash's look, shared by the live casts, Blizzard's buttons and the
-- samples: the icon in a black edge with a line of the route's colour inside
-- it, a clock sweep over the icon (below), the name under it. Built on frame (a
-- Blizzard button or a plain frame).
local function NameFont(label, size)
    local file, _, flags = GameFontHighlightSmall:GetFont()
    if file then label:SetFont(file, size, flags ~= "" and flags or "OUTLINE") end
end

-- The tick down, drawn by animations alone so Blizzard's aura code plays it
-- with the flash (it plays the groups it is handed and runs no addon code
-- then; a Cooldown started from the group's OnPlay never showed on aura
-- flashes in a duel, 16 October 2026). A clock wipe from two dark halves:
-- the right one turns 180 degrees clockwise about the icon's centre inside
-- the icon's right half, then the left one does the same in the left half,
-- so the dark part left is always what the hand has not reached yet. A
-- bright hand turns once round over the same time, the line that goes round
-- an action button cooling down. Every target is a descendant of the button,
-- as Blizzard requires (AuraContainerUtil.InitializeInboundAnimationGroup).
local SWEEP_DARK = 0.64
local function Clip(frame)
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local inner = CreateFrame("Frame", nil, clip)
    inner:SetAllPoints(clip)
    inner:EnableMouse(false)
    return clip, inner
end
local function Turn(group, target, origin)
    local turn = group:CreateAnimation("Rotation")
    turn:SetTarget(target)
    turn:SetOrigin(origin, 0, 0)
    turn:SetSmoothing("NONE")
    turn:SetOrder(2)
    return turn
end

function ns.BuildParts(frame)
    local p = { button = frame }
    p.edge = frame:CreateTexture(nil, "BACKGROUND")
    p.edge:SetColorTexture(0, 0, 0, 1)
    p.line = frame:CreateTexture(nil, "BORDER")
    p.line:SetTexture(WHITE)
    p.icon = frame:CreateTexture(nil, "ARTWORK")
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local inner
    p.rightClip, inner = Clip(frame)
    p.rightDark = inner:CreateTexture(nil, "ARTWORK")
    p.rightDark:SetColorTexture(0, 0, 0, SWEEP_DARK)
    p.leftClip, inner = Clip(frame)
    p.leftDark = inner:CreateTexture(nil, "ARTWORK")
    p.leftDark:SetColorTexture(0, 0, 0, SWEEP_DARK)
    p.handClip, inner = Clip(frame)
    p.hand = inner:CreateTexture(nil, "OVERLAY")
    p.hand:SetTexture(WHITE)
    p.hand:SetVertexColor(1, 0.9, 0.55, 0.9)
    p.hand:SetBlendMode("ADD")
    p.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.name:SetJustifyH("CENTER")
    p.name:SetWordWrap(false)
    -- The flash: in, held while the sweep turns, out; it ends at alpha 0.
    local flash = frame:CreateAnimationGroup()
    flash:SetToFinalAlpha(true)
    local into = flash:CreateAnimation("Alpha")
    into:SetFromAlpha(0)
    into:SetToAlpha(1)
    into:SetDuration(FADE_IN)
    into:SetOrder(1)
    local hold = flash:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetOrder(2)
    p.rightTurn = Turn(flash, p.rightDark, "LEFT")
    p.rightTurn:SetDegrees(-180)
    p.leftTurn = Turn(flash, p.leftDark, "RIGHT")
    p.leftTurn:SetDegrees(-180)
    p.handTurn = Turn(flash, p.hand, "BOTTOM")
    p.handTurn:SetDegrees(-360)
    local out = flash:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0)
    out:SetDuration(FADE_OUT)
    out:SetOrder(3)
    p.flash, p.hold = flash, hold
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    return p
end

-- How tall a flash is without its name, at icon size `size`.
function ns.FlashHeight(size) return size end
-- How tall a spot is: the flash and, when shown, the name under it.
function ns.SpotHeight(size)
    return ns.FlashHeight(size) + (ns.Get("name") == true and ((ns.Get("nameSize") or 10) + 3) or 0)
end
-- How long a flash is seen, from first light to gone.
function ns.FlashLength() return FADE_IN + ns.Seconds() + FADE_OUT end

-- Lays parts out: look = { size, name, nameSize, seconds, color }.
function ns.StyleParts(p, look)
    local frame, size = p.button, look.size
    frame:SetSize(size, ns.FlashHeight(size))
    p.edge:ClearAllPoints()
    p.edge:SetPoint("TOPLEFT", 0, 0)
    p.edge:SetSize(size, size)
    p.line:ClearAllPoints()
    p.line:SetPoint("TOPLEFT", 1, -1)
    p.line:SetSize(size - 2, size - 2)
    p.icon:ClearAllPoints()
    p.icon:SetPoint("TOPLEFT", 2, -2)
    p.icon:SetSize(size - 4, size - 4)
    if look.color then p.line:SetVertexColor(look.color[1], look.color[2], look.color[3], 1) end
    p.name:ClearAllPoints()
    p.name:SetPoint("TOP", frame, "TOP", 0, -(ns.FlashHeight(size) + 1))
    p.name:SetWidth(math.max(60, size * 3))
    NameFont(p.name, look.nameSize)
    p.name:SetShown(look.name)
    -- The sweep: each dark half as tall as twice the icon and as wide as
    -- it, pivoting on the icon's centre, so it covers its half at any angle.
    local inner, seconds = size - 4, look.seconds
    p.rightClip:ClearAllPoints()
    p.rightClip:SetPoint("TOPLEFT", p.icon, "TOP")
    p.rightClip:SetPoint("BOTTOMRIGHT", p.icon, "BOTTOMRIGHT")
    p.rightDark:ClearAllPoints()
    p.rightDark:SetPoint("LEFT", p.rightClip, "LEFT")
    p.rightDark:SetSize(inner, inner * 2)
    p.leftClip:ClearAllPoints()
    p.leftClip:SetPoint("TOPLEFT", p.icon, "TOPLEFT")
    p.leftClip:SetPoint("BOTTOMRIGHT", p.icon, "BOTTOM")
    p.leftDark:ClearAllPoints()
    p.leftDark:SetPoint("RIGHT", p.leftClip, "RIGHT")
    p.leftDark:SetSize(inner, inner * 2)
    p.handClip:ClearAllPoints()
    p.handClip:SetAllPoints(p.icon)
    p.hand:ClearAllPoints()
    p.hand:SetPoint("BOTTOM", p.handClip, "CENTER")
    p.hand:SetSize(2, inner * 0.75)
    p.hold:SetDuration(seconds)
    p.rightTurn:SetDuration(seconds / 2)
    p.leftTurn:SetStartDelay(seconds / 2)
    p.leftTurn:SetDuration(seconds / 2)
    p.handTurn:SetDuration(seconds)
end

-- The settings in use, for parts of colour `color`.
function ns.Look(size, color)
    return { size = size, name = ns.Get("name") == true, nameSize = ns.Get("nameSize") or 10,
        seconds = ns.Seconds(), color = color }
end

-- Plays a flash with plain or hidden values (a cast's name and icon go
-- straight from the C_Spell calls to the sinks). color: a sample's own.
function ns.PlayParts(p, name, icon, color)
    if color then p.line:SetVertexColor(color[1], color[2], color[3], 1) end
    p.icon:SetTexture(icon)
    p.name:SetText(name)
    p.flash:Stop()
    p.flash:Play()
end

-- Feeds: one aura container each ---------------------------------------------------------
local Feed = {}
Feed.__index = Feed

-- kind: "buff" (the unit's HELPFUL) or "debuff" (yours, HARMFUL).
local function NewFeed(spot, kind)
    local self = setmetatable({ spot = spot, kind = kind, filter = kind == "buff" and "HELPFUL" or "HARMFUL",
        unit = "none", parts = {}, settleUntil = 0, token = 0 }, Feed)
    feeds[#feeds + 1] = self
    return self
end

function Feed:InitButton(button)
    local p = ns.BuildParts(button)
    ns.StyleParts(p, ns.Look(self.spot.size, ns.COLORS[self.kind]))
    button:SetIcon(p.icon)
    button:SetSpellName(p.name)
    button:AddAuraAssignedAnimation(p.flash)
    self.parts[#self.parts + 1] = p
end

-- Makes the holder and container the first time they are wanted. False if
-- this build has no container or making one failed (then nothing tries
-- again; the error is in the Lua error log once).
function Feed:Build()
    if self.container then return true end
    if not Available() then return false end
    local holder = CreateFrame("Frame", nil, self.spot.frame)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:SetAlpha(0)
    holder:SetPoint("TOPRIGHT", self.spot.frame, "TOPRIGHT", 0, 0)
    local level = self.spot.frame:GetFrameLevel()
    if Public(level) and type(level) == "number" then holder:SetFrameLevel(level + (self.kind == "buff" and 2 or 1)) end
    broken = true
    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    container:SetEditModePreviewEnabled(false)
    -- New secure aura assignments start next to the plate and extend LEFT.
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutAnchorPoint("TOPRIGHT")
    container:AddAuraGroup(self.kind, self.filter, {
        maxFrameCount = MAX_BUTTONS,
        sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
        sortDirection = AuraContainerSortDirection.Reverse,
        layout = { lineSpacing = 1 },
        initializeFrame = function(button) self:InitButton(button) end,
    })
    broken = false
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    self.holder, self.container = holder, container
    return true
end

-- Seen once the unit's first flashes have run.
function Feed:UpdateShown()
    if not self.holder then return end
    self.holder:SetAlpha((self.unit ~= "none" and GetTime() >= self.settleUntil) and 1 or 0)
end

-- Follows unit ("none" stops). fresh: the unit behind the token changed (a
-- new target or plate), so the container starts over even if it already
-- follows that token.
function Feed:SetUnit(unit, fresh)
    if unit == self.unit and not fresh then return end
    if unit == "none" and self.unit == "none" then return end
    if unit ~= "none" and not self:Build() then return end
    if not self.container then return end
    self.container:SetUnit("none")
    if unit ~= "none" then self.container:SetUnit(unit) end
    self.unit = unit
    self.settleUntil = GetTime() + ns.FlashLength() + 0.1
    self:UpdateShown()
    if unit ~= "none" and C_Timer and C_Timer.After then
        self.token = self.token + 1
        local token = self.token
        C_Timer.After(ns.FlashLength() + 0.1, function()
            if self.token == token then self:UpdateShown() end
        end)
    end
end

-- A changed look reaches every button now, or once auras stop being secret.
local function RestyleAll()
    if not CanTouch() then
        pending = true
        return false
    end
    pending = false
    for _, feed in ipairs(feeds) do
        for _, p in ipairs(feed.parts) do ns.StyleParts(p, ns.Look(feed.spot.size, ns.COLORS[feed.kind])) end
    end
    return true
end
ns.RestyleAll = RestyleAll
function ns.RestylePending() return pending end

-- Spots ----------------------------------------------------------------------------------
local Spot = {}
Spot.__index = Spot

-- parent: the frame the spot's frame hangs from (a plate, the bar).
function ns.NewSpot(parent, size)
    local self = setmetatable({ size = size, unit = nil }, Spot)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    self.frame = frame
    -- Gold cast flashes have four bounded slots. New spells appear at the
    -- plate edge; previous flashes move LEFT without reading spell secrets.
    self.casts = {}
    local level = frame:GetFrameLevel()
    for i=1,MAX_CAST_FLASHES do
        local castFrame = CreateFrame("Frame", nil, frame)
        if Public(level) and type(level) == "number" then castFrame:SetFrameLevel(level + 3) end
        self.casts[i] = ns.BuildParts(castFrame)
    end
    self.cast = self.casts[1]
    self.buffs, self.debuffs = NewFeed(self, "buff"), NewFeed(self, "debuff")
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self:Style(size)
    return self
end

-- The spot at icon size `size`, in the settings' look.
function Spot:ReflowCasts()
    for i,part in ipairs(self.casts) do
        part.button:ClearAllPoints()
        part.button:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -(i-1)*(self.size+2), 0)
    end
    self.cast = self.casts[1]
end

function Spot:Style(size)
    self.size = size
    self.frame:SetSize(math.max(size, 1), ns.SpotHeight(size))
    for _,part in ipairs(self.casts) do ns.StyleParts(part, ns.Look(size, ns.COLORS.cast)) end
    self:ReflowCasts()
end

function Spot:NewCast(name, icon, color)
    local part = table.remove(self.casts, #self.casts)
    table.insert(self.casts, 1, part)
    self:ReflowCasts()
    ns.PlayParts(part, name, icon, color or ns.COLORS.cast)
end

-- Watches unit: its casts and new buffs while it is an enemy, and your new
-- debuffs while opponent is true. fresh: the unit behind the token changed.
function Spot:Follow(unit, opponent, fresh)
    local enemy = unit ~= nil and ns.Hostile(unit)
    local castUnit = (enemy and ns.Get("casts") == true) and unit or nil
    if castUnit ~= self.castUnit then
        self.events:UnregisterAllEvents()
        if castUnit then self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", castUnit) end
        self.castUnit = castUnit
    end
    if fresh or unit ~= self.unit then
        for _,part in ipairs(self.casts) do
            part.flash:Stop()
            part.button:SetAlpha(0)
        end
    end
    self.unit = unit
    self.buffs:SetUnit((enemy and ns.Get("buffs") == true) and unit or "none", fresh)
    -- Your debuffs are yours, so a new opponent does not restart them.
    self.debuffs:SetUnit((opponent and ns.Get("debuffs") == true) and "player" or "none", false)
    self.opponent = opponent == true
end

function Spot:Stop()
    self:Follow(nil, false, false)
end

function Spot:OnEvent(event, unit, _, spellID)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
    -- RegisterUnitEvent already limits delivery to this unit. The payload
    -- token is only used to reject a public mismatch; a secret one must not
    -- hide the cast.
    if Public(unit) and unit ~= self.castUnit then return end
    if Public(spellID) and spellID == nil then return end
    local name = C_Spell.GetSpellName(spellID)
    local icon = C_Spell.GetSpellTexture(spellID)
    self:NewCast(name, icon, ns.COLORS.cast)
end

-- A sample flash on the cast parts, in kind's colour (Show on screen and the
-- unlocked bar; nothing is read).
function Spot:Sample(sample)
    self:NewCast(sample.name, sample.icon, ns.COLORS[sample.kind])
end

-- After settings changed: the look of every feed's buttons.
local LOOK_KEYS = { name = true, nameSize = true, tenths = true, size = true, barSize = true }
function ns.FlashApply(keys)
    for _, key in ipairs(keys) do
        if LOOK_KEYS[key] then
            RestyleAll()
            return
        end
    end
end

-- Out of a fight a waiting look change goes through.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if pending and RestyleAll() and ns.RefreshSettings then ns.RefreshSettings() end
end)

-- Samples ----------------------------------------------------------------------------------
-- What the previews and the unlocked bar play: one of each route, with the
-- client's own name and icon when they read (spell IDs from the original
-- game; Forever's may differ, so each has its name too).
local QUESTION_MARK = 134400
ns.SAMPLES = {
    { kind = "cast", spell = 2136, name = "Fire Blast", caption = "their cast" },
    { kind = "buff", spell = 17, name = "Power Word: Shield", caption = "their new buff" },
    { kind = "debuff", spell = 5116, name = "Concussive Shot", caption = "your new debuff, in a duel" },
}
function ns.SampleEntry(sample)
    local name, icon = C_Spell.GetSpellName(sample.spell), C_Spell.GetSpellTexture(sample.spell)
    return { kind = sample.kind, caption = sample.caption,
        name = ns.Text(name) and name or sample.name, icon = ns.Number(icon) and icon or QUESTION_MARK }
end
