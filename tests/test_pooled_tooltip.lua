-- Keep the open tooltip attached to the logical row under a stationary pointer.
local testDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(testDir..'/world_recovery_support.lua'))()
local function fresh()
    local H = setup()
    H.units.target, H.units.focus = 'Player-1-Alpha', 'Player-1-Bravo'
    H.hostile.target, H.hostile.focus = true, true
    H.ns.db.targetOnly = false
    H.ns.db.bars.cooldown.enabled = true
    function H.fire(at, event, ...)
        H.time(at)
        H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame, event, ...)
        H.ns.UI.Update(at)
    end
    function H.cast(at, unit, id)
        H.fire(at, 'UNIT_SPELLCAST_SUCCEEDED', unit, 'Cast-'..unit..'-'..at, id)
    end
    return H, H.ns.UI, H.ns.UI.bars.cooldown
end
local function lines(UI)
    return table.concat(UI.tip.lines, '\n')
end
do
    local H, UI, bar = fresh()
    H.cast(100, 'target', 1776)
    H.cast(101, 'focus', 122)
    local first, second, width = bar.icons[1], bar.icons[2], bar.width
    first.scripts.OnEnter(first)
    assert(UI.tip.text == 'Gouge' and lines(UI):find('Claim #1', 1, true))

    H.units.target = 'Player-1-Charlie'
    H.cast(110, 'target', 5277)
    assert(first == bar.icons[1] and first.row.spellID == 122 and width == bar.width)
    assert(UI.tip:IsShown() and UI.tip.text == 'Frost Nova' and lines(UI):find('Claim #2', 1, true),
        'a stationary pointer sees the new spell and claim when the same slot is reused')

    second.scripts.OnEnter(second)
    first.scripts.OnLeave(first)
    assert(UI.tip:IsShown() and UI.tip.text == 'Evasion', 'a former owner cannot dismiss the new tooltip')
    H.ns.db.bars.cooldown.maxIcons = 1
    UI.Update(111)
    assert(not UI.tip:IsShown(), 'dropping the hovered slot dismisses its tooltip')
    H.ns.db.bars.cooldown.maxIcons = 4
    UI.Update(112)
    assert(not UI.tip:IsShown(), 'reusing a formerly hovered slot does not reopen its tooltip')
end
do
    local H, UI, bar = fresh()
    H.fire(100, 'UNIT_AURA', 'target', {addedAuras={{spellId=5277, isHelpful=true, auraInstanceID=5}}})
    local icon = bar.icons[1]
    icon.scripts.OnEnter(icon)
    assert(lines(UI):find('Claim #1 | first-sighting', 1, true))
    H.cast(100, 'target', 5277)
    assert(icon.row.started == 100 and icon.row.claimID == 1)
    assert(lines(UI):find('Claim #1 | cast-success-event', 1, true) and lines(UI):find('Revised', 1, true),
        'a changed basis for the same spell, start and claim updates the visible explanation')
    H.cast(101, 'target', 5277)
    assert(lines(UI):find('Claim #2', 1, true), 'a superseding claim of the same spell updates the tooltip')
    local body = UI.tip.lines
    for i=1,20 do UI.Update(101+i/10) end
    assert(UI.tip.lines == body, 'countdown-only updates leave the open tooltip intact')

    H.ns.demo = true
    UI.Update(104)
    assert(lines(UI):find('SAMPLE ONLY', 1, true), 'the open tooltip reflects preview mode')
    body = UI.tip.lines
    UI.Update(104.1)
    assert(UI.tip.lines == body, 'synthetic preview timestamps do not cause repeated tooltip writes')
    H.ns.db.bars.cooldown.enabled = false
    UI.Update(105)
    assert(not UI.tip:IsShown(), 'disabling the hovered bar closes its tooltip')
end
do
    local H, UI = fresh()
    local effect = {spellId=853, auraInstanceID=9, duration=6, expirationTime=106}
    C_UnitAuras.GetAuraDataByIndex = function(unit,index)
        if unit=='player' and index==1 then return effect end
    end
    H.fire(100, 'UNIT_AURA', 'player')
    local icon = assert(UI.bars.player.icons[1])
    icon.scripts.OnEnter(icon)
    local initialStage = icon.row.stage
    effect = {spellId=853, auraInstanceID=10, duration=3, expirationTime=110}
    H.fire(107, 'UNIT_AURA', 'player')
    assert(icon.row.stage ~= initialStage)
    assert(lines(UI):find('observed stage 2', 1, true),
        'a new same-spell DR application updates its stage while preserving uncertainty')
end
print('pooled tooltip: stationary rebinds, claim revisions, DR, ownership, hiding and stable ticks passed')
