-- Opt-in native aura witness, NOT a DR sensor.
-- Blizzard owns the aura identity, selection, availability and cooldown.
-- No addon code reads a secure aura button's visibility, duration, or identity.
local _, ns = ...
local S = ns.Safe
local Witness = {hosts={}, pending=false, errors={}}
ns.NativeStuns = Witness

local EFFECTS = {
    [5211]=true, [6798]=true, [8983]=true, -- Bash ranks
    [20549]=true,                         -- War Stomp
    [4068]=true,                          -- Iron Grenade
}
local UNITS = {"target","focus"}
local ANCHOR_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

local function outsideCombat()
    -- Unknown combat state is not authorization for structural work.
    return S.Boolean(S.Call(InCombatLockdown)) == false
end

local function errorText(value)
    local text = S.String(value)
    if text then return text:sub(1,160):gsub("[%c|]","?") end
    return "unreadable API failure"
end

local function initializeAuraFrame(host, button)
    -- Native aura containers decide visibility entirely within secure code.
    button:SetAllPoints(host)
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(.07,.93,.07,.93)
    button:SetIcon(icon)

    local timer=CreateFrame("Cooldown",nil,button,
        "CooldownFrameTemplate,"..ANCHOR_TEMPLATE)
    timer:SetAllPoints(button)
    if timer.SetReverse then timer:SetReverse(true) end
    if timer.SetDrawBling then timer:SetDrawBling(false) end
    if timer.SetDrawEdge then timer:SetDrawEdge(false) end
    if timer.SetHideCountdownNumbers then timer:SetHideCountdownNumbers(false) end
    if timer.SetCountdownMillisecondsThreshold then timer:SetCountdownMillisecondsThreshold(5) end
    button:SetDurationCooldown(timer)

    -- Text is owned by the secure aura button: hidden native slots have no
    -- independent label. "AURA" means the aura is present, NOT the DR stage.
    local label=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    label:SetPoint("TOP",button,"BOTTOM",0,-2)
    label:SetText("STUN AURA")
    label:SetTextColor(.9,.75,.43)
    button:EnableMouse(false)
end

local function build(unit)
    local bar=ns.UI and ns.UI.bars and ns.UI.bars[unit]
    if not bar or not outsideCombat() or type(CreateFrame)~="function" then
        return nil,"missing parent or combat"
    end
    if not AuraContainerSortMethod or not AuraContainerSortDirection
        or not AuraContainerSortMethod.AuraInstanceIDOnly
        or not AuraContainerSortDirection.Reverse then
        return nil,"native aura sorting unavailable"
    end
    local host, container
    local ok, reason = pcall(function()
        -- Independent sibling to the DR grid. No native unit-frame reparenting
        -- or forbidden geometry reads. Follows draggable grid automatically.
        host=CreateFrame("Frame",nil,UIParent,ANCHOR_TEMPLATE)
        host:SetSize(28,28)
        host:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",0,-15)
        host:SetFrameStrata("MEDIUM")
        host:Hide()

        container=CreateFrame("AuraContainer",nil,host,"CustomAuraContainerTemplate")
        assert(container and type(container.AddAuraSlot)=="function",
            "CustomAuraContainerTemplate unavailable")
        container:SetAllPoints(host)
        container:SetUnit(unit)
        container:SetEnabled(false)
        container:Hide()
        container:AddAuraSlot("SharedStun","HARMFUL|INCLUDE_NAME_PLATE_ONLY",{
            sortMethod=AuraContainerSortMethod.AuraInstanceIDOnly,
            sortDirection=AuraContainerSortDirection.Reverse,
            candidateFilters={includeSpellIDs=EFFECTS},
            initializeFrame=function(button) initializeAuraFrame(host,button) end,
        })
    end)
    if not ok then
        if container then
            pcall(container.SetEnabled,container,false)
            pcall(container.Hide,container)
        end
        if host then pcall(host.Hide,host) end
        return nil,errorText(reason)
    end
    return {unit=unit,frame=host,container=container,ready=true}
end

function Witness.Init()
    if Witness.initialized then return end
    if not outsideCombat() then
        Witness.pending=true
        return
    end
    Witness.initialized=true
    for _,unit in ipairs(UNITS) do
        local host,why=build(unit)
        Witness.hosts[unit]=host
        if not host then Witness.errors[unit]=why end
    end
    Witness.Refresh()
end

function Witness.Refresh(force)
    if not Witness.initialized then
        Witness.Init()
        if not Witness.initialized then return false,"initialization pending combat" end
    end
    if not outsideCombat() then
        Witness.pending=true
        return false,"deferred until out of combat"
    end
    Witness.pending=false
    local desired = ns.db and ns.db.nativeStunWitness == true
    for _,unit in ipairs(UNITS) do
        local host=Witness.hosts[unit]
        if host then
            -- Never inspect native aura selection or use a secure button
            -- as a private-data oracle. Only control our own host.
            local ok=pcall(function()
                host.container:SetEnabled(desired)
                host.container:SetShown(desired)
                host.frame:SetShown(desired)
                if force and desired and host.container.UpdateAllAuras then
                    host.container:UpdateAllAuras()
                end
            end)
            if not ok then
                Witness.errors[unit]="native container refresh rejected"
                Witness.pending=true
            end
        end
    end
    return not Witness.pending, Witness.pending and "refresh failed" or "ready"
end

function Witness.Status()
    local parts={}
    for _,unit in ipairs(UNITS) do
        local host=Witness.hosts[unit]
        parts[#parts+1]=unit.."="..(host and "constructed" or (Witness.errors[unit] or "not constructed"))
    end
    return "secure native shared-stun witness "..((ns.db and ns.db.nativeStunWitness) and "ON" or "OFF")
        .."; "..table.concat(parts,", ").."; pending="..tostring(Witness.pending)
        .."; does not expose private aura identity or advance DR"
end
