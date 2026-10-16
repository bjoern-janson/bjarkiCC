local _, ns = ...
local S, A = ns.Safe, {}
ns.Anchors = A
local names = {player='PlayerFrame', target='TargetFrame', focus='FocusFrame'}
local healthNames = {player='PlayerFrameHealthBar', target='TargetFrameHealthBar', focus='FocusFrameHealthBar'}
local portraitNames = {
    player={'PlayerPortrait','PlayerFramePortrait'},
    target={'TargetFramePortrait','TargetPortrait'},
    focus={'FocusFramePortrait','FocusPortrait'},
}

function A.InCombat()
    if type(InCombatLockdown) ~= 'function' then return false end
    -- An inaccessible combat state does not authorize repositioning.
    return S.Boolean(S.Call(InCombatLockdown)) ~= false
end

local function usableRegion(region)
    return region and type(S.Field(region, 'GetRight')) == 'function'
        and type(S.Field(region, 'GetTop')) == 'function'
end

local function reference(key)
    local name = names[key]
    if not name then return nil end
    local frame = S.Field(_G, name)
    if usableRegion(frame) then return frame end
end

local function portrait(key, frame)
    local container = S.Field(frame, key == 'player' and 'PlayerFrameContainer' or 'TargetFrameContainer')
    local mask = S.Field(container, key == 'player' and 'PlayerPortraitMask' or 'PortraitMask')
    if usableRegion(mask) then return mask end
    local image = S.Field(container, key == 'player' and 'PlayerPortrait' or 'Portrait')
    if usableRegion(image) then return image end
    for _, name in ipairs(portraitNames[key] or {}) do
        image = S.Field(_G, name)
        if usableRegion(image) then return image end
    end
    return frame
end

local function health(key, frame)
    local content = S.Field(frame, key == 'player' and 'PlayerFrameContent' or 'TargetFrameContent')
    local main = S.Field(content, key == 'player' and 'PlayerFrameContentMain' or 'TargetFrameContentMain')
    local container = S.Field(main, 'HealthBarsContainer')
    local region = S.Field(container, 'HealthBar')
    if usableRegion(region) then return region, true end
    region = S.Field(_G, healthNames[key])
    if usableRegion(region) then return region, true end
    region = S.Field(frame, 'healthbar')
    if usableRegion(region) then return region, true end
    return portrait(key, frame), false
end

local function legacyPoint(settings)
    if settings.vertical then return settings.reverse and 'BOTTOMLEFT' or 'TOPLEFT' end
    return settings.reverse and 'TOPRIGHT' or 'TOPLEFT'
end

local function placement(key, settings, frame)
    if not frame then return nil, 'CENTER', 'CENTER', 0, 0 end
    -- Preserve manually positioned v0.3.0 bars in their original coordinate
    -- system. Reset positions opts them into the health-bar placement.
    if settings.anchorKind == 'frame' then
        return frame, legacyPoint(settings), 'TOPRIGHT', 0, 0
    end
    if settings.anchorKind == 'health' then
        local region, found = health(key, frame)
        local size = settings.size or 28
        -- Start above the health edge nearest the portrait. Mirrored default
        -- directions keep rows inside the name/health area, clear of PvP badges.
        -- If a skin exposes no health region, use the portrait's inward top
        -- corner and remove the name-height allowance from the fallback offset.
        local right = key ~= 'player'
        local relativePoint = (found or region == frame) and (right and 'TOPRIGHT' or 'TOPLEFT')
            or (right and 'TOPLEFT' or 'TOPRIGHT')
        local dx, dy = 0, found and 0 or -20
        if settings.vertical then
            if right then dx = -size end
            if not settings.reverse then dy = dy + size end
            return region, settings.reverse and 'BOTTOMLEFT' or 'TOPLEFT', relativePoint, dx, dy
        end
        if right and not settings.reverse then dx = -size
        elseif not right and settings.reverse then dx = size end
        return region, settings.reverse and 'BOTTOMRIGHT' or 'BOTTOMLEFT', relativePoint, dx, dy
    end
    local region, size = portrait(key, frame), settings.size or 28
    if key == 'player' then
        if settings.vertical then
            return region, settings.reverse and 'BOTTOMLEFT' or 'TOPLEFT', 'TOPLEFT', 0, settings.reverse and 0 or size
        end
        return region, settings.reverse and 'BOTTOMRIGHT' or 'BOTTOMLEFT', 'TOPLEFT', settings.reverse and size or 0, 0
    end
    if settings.vertical then
        return region, settings.reverse and 'BOTTOMLEFT' or 'TOPLEFT', 'RIGHT', 0, settings.reverse and -size/2 or size/2
    end
    return region, settings.reverse and 'RIGHT' or 'LEFT', 'RIGHT', settings.reverse and size or 0, 0
end

function A.Apply(bar, force)
    if bar.dragging then return end
    local settings = ns.db.bars[bar.key]
    local anchor = reference(bar.key)
    local region, point, relativePoint, dx, dy = placement(bar.key, settings, anchor)
    local x = anchor and settings.offsetX + dx or settings.x
    local y = anchor and settings.offsetY + dy or settings.y
    if not force and not bar.anchorPending and bar.anchorApplied
        and bar.anchorFrame == anchor and bar.anchorRegion == region
        and bar.anchorPoint == point and bar.anchorRelativePoint == relativePoint
        and bar.anchorX == x and bar.anchorY == y then return end
    if A.InCombat() then bar.anchorPending = true; return end
    -- Only addon frames are repositioned. A native relative anchor follows
    -- Edit Mode and other movement without a unit-frame hook or parent change.
    bar:ClearAllPoints()
    bar:SetPoint(point, region or UIParent, relativePoint, x, y)
    bar.anchorFrame, bar.anchorPoint = anchor, point
    bar.anchorRegion, bar.anchorRelativePoint = region, relativePoint
    bar.anchorX, bar.anchorY = x, y
    bar.anchorApplied, bar.anchorPending = true, false
end

function A.Visible(bar)
    if not names[bar.key] then return true end
    local frame = reference(bar.key)
    if not frame or frame ~= bar.anchorFrame or not bar.anchorApplied then return false end
    local region = placement(bar.key, ns.db.bars[bar.key], frame)
    if region ~= bar.anchorRegion then return false end
    return S.Boolean(S.Call(S.Field(frame, 'IsVisible'), frame)) == true
end

function A.StartDrag(bar)
    if ns.db.locked or A.InCombat() then return false end
    if names[bar.key] and not reference(bar.key) then return false end
    if bar.dragging then return true end
    bar:StartMoving()
    bar.dragging = true
    return true
end

local function coordinate(frame, method)
    return S.Number(S.Call(S.Field(frame, method), frame))
end

local function center(frame)
    local method = S.Field(frame, 'GetCenter')
    if type(method) ~= 'function' then return end
    local ok,x,y = pcall(method, frame)
    if ok then return S.Number(x), S.Number(y) end
end

local function clamp(value)
    return math.max(-10000, math.min(10000, value))
end

local function pointCoordinates(frame, point)
    local x, y = center(frame)
    if string.find(point, 'LEFT', 1, true) then x = coordinate(frame, 'GetLeft')
    elseif string.find(point, 'RIGHT', 1, true) then x = coordinate(frame, 'GetRight') end
    if string.find(point, 'TOP', 1, true) then y = coordinate(frame, 'GetTop')
    elseif string.find(point, 'BOTTOM', 1, true) then y = coordinate(frame, 'GetBottom') end
    return x, y
end

function A.StopDrag(bar)
    if not bar.dragging then return end
    bar:StopMovingOrSizing()
    bar.dragging = false
    -- StartMoving switches to screen coordinates. Even if no position can be
    -- saved, always restore the relative anchor at the next safe opportunity.
    bar.anchorPending = true
    if A.InCombat() then return end
    local settings, anchor = ns.db.bars[bar.key], reference(bar.key)
    local scale = coordinate(bar, 'GetEffectiveScale')
    if not ns.db.locked and scale and scale > 0 then
        if anchor then
            local region, point, relativePoint, dx, dy = placement(bar.key, settings, anchor)
            local nativeScale = coordinate(region, 'GetEffectiveScale')
            local x,y = pointCoordinates(bar, point)
            local ax,ay = pointCoordinates(region, relativePoint)
            if x and y and ax and ay and nativeScale and nativeScale > 0 then
                settings.offsetX = clamp(x - ax*nativeScale/scale - dx)
                settings.offsetY = clamp(y - ay*nativeScale/scale - dy)
            end
        elseif not names[bar.key] then
            local parentScale = coordinate(UIParent, 'GetEffectiveScale')
            local x,y = center(bar)
            local px,py = center(UIParent)
            if x and y and px and py and parentScale and parentScale > 0 then
                settings.x = clamp(x - px*parentScale/scale)
                settings.y = clamp(y - py*parentScale/scale)
            end
        end
    end
    A.Apply(bar, true)
end
