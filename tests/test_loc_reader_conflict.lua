-- A native instance can be reused while one LoC reader still sees its old spell.
local fresh = dofile((TEST_DIR or ADDON_DIR..'/tests')..'/world_recovery_support.lua')
local function setup()
    C_LossOfControl = nil
    local h = fresh()
    local ns = h.ns
    ns.db.bars.cooldown.enabled = true
    ns.db.targetOnly = false
    C_UnitAuras.GetAuraDataByIndex = function(unit)
        if unit == 'player' then return h.hidden end
    end
    C_LossOfControl = {
        GetActiveLossOfControlDataCount = function() return h.ordinary and 1 or 0 end,
        GetActiveLossOfControlData = function() return h.ordinary end,
        GetActiveLossOfControlDataCountByUnit = function(unit) return unit == 'player' and h.byUnit and 1 or 0 end,
        GetActiveLossOfControlDataByUnit = function() return h.byUnit end,
    }
    function h.fire(now, event)
        h.time(now)
        ns.eventFrame.scripts.OnEvent(ns.eventFrame, event, 'player')
    end
    return h, ns
end
local function loc(spell, start, duration)
    return {spellID=spell, auraInstanceID=17, startTime=start, duration=duration}
end
local function rowFor(rows, spell)
    for _, row in ipairs(rows) do
        if row.spellID == spell then return row end
    end
end
local function overlap(newOnOrdinary, fallback)
    local h, ns = setup()
    local old, new = loc(853, 100, 2), loc(122, 102, 5)
    h.ordinary = fallback and {spellID=853, startTime=100, duration=2} or old
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    local oldClaim = assert(rowFor(ns.UI.GetRows('cooldown', 100), 853)).claimID

    h.ordinary = old
    h.fire(100.1, 'LOSS_OF_CONTROL_UPDATE')
    h.ordinary, h.byUnit = newOnOrdinary and new or old, newOnOrdinary and old or new
    for _, now in ipairs({102, 102.1}) do
        h.fire(now, 'LOSS_OF_CONTROL_UPDATE')
        local chosen = assert(ns.Observer.ReadPlayerLoCEffects(now)['a:17'])
        assert(chosen.spellID == 122 and chosen.appliedAt == 102 and chosen.expires == 107
            and chosen.reportedDuration == 5, 'newer Frost Nova must retain its own clock and duration')
        local cds = ns.UI.GetRows('cooldown', now)
        local hammer, nova = rowFor(cds, 853), rowFor(cds, 122)
        assert(#cds == 2 and hammer and hammer.claimID == oldClaim and hammer.started == 100
            and nova and nova.started == 102, 'replay must retain the two distinct spell claims')
        local dr = ns.UI.GetRows('player', now)
        hammer, nova = rowFor(dr, 853), rowFor(dr, 122)
        assert(#dr == 2 and hammer and hammer.started == 100 and hammer.stage == 1 and not hammer.active,
            'the overlap must not refresh stun DR')
        assert(nova and nova.started == 102 and nova.stage == 1 and nova.active and nova.uncertain
            and nova.stageResetAt == 125, 'the restricted root keeps its own uncertain DR and predicted end')
    end
    -- The lagging reader can briefly be the only positive. This is still its
    -- original occurrence, even after its native key learned a fallback alias.
    if newOnOrdinary then h.ordinary, h.byUnit = nil, old
    else h.ordinary, h.byUnit = old, nil end
    h.fire(102.2, 'LOSS_OF_CONTROL_UPDATE')
    local dr = ns.UI.GetRows('player', 102.2)
    assert(rowFor(dr, 853).stage == 1 and rowFor(dr, 122).active,
        'a stale solo poll must not reapply the displaced spell or remove its successor')
    h.ordinary, h.byUnit = newOnOrdinary and new or old, newOnOrdinary and old or new
    h.fire(102.3, 'LOSS_OF_CONTROL_UPDATE')
    assert(rowFor(ns.UI.GetRows('player', 102.3), 122).stage == 1,
        'recovered reader must not reapply the same root')
    h.ordinary, h.byUnit = nil, nil
    h.fire(102.4, 'LOSS_OF_CONTROL_UPDATE')
    local nova = assert(rowFor(ns.UI.GetRows('player', 102.4), 122))
    assert(nova.active ~= newOnOrdinary, 'only the ordinary reader can prove removal of its own spell')
end
for _, ordinary in ipairs({false, true}) do
    overlap(ordinary, false)
    overlap(ordinary, true)
end

-- After the native slot is reused, a lagging reader can lose the instance ID
-- while continuing to report the displaced spell's exact application time.
for _, aliases in ipairs({{}, {hammer=true}, {nova=true}, {hammer=true, nova=true}}) do
    local h, ns = setup()
    local old, new = loc(853, 100, 10), loc(122, 102, 5)
    h.ordinary = aliases.hammer and {spellID=853, startTime=100, duration=10} or old
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    h.ordinary = old
    h.fire(100.1, 'LOSS_OF_CONTROL_UPDATE')
    if aliases.nova then
        h.byUnit = {spellID=122, startTime=102, duration=5}
        h.fire(102, 'LOSS_OF_CONTROL_ADDED')
    end
    h.byUnit = new
    h.fire(102, 'LOSS_OF_CONTROL_UPDATE')
    h.byUnit = nil
    h.ordinary = {spellID=853, auraInstanceID=h.hidden, startTime=100, duration=10}
    for _, t in ipairs({102.1, 102.2}) do
        h.fire(t, 'LOSS_OF_CONTROL_UPDATE')
        local rows = ns.UI.GetRows('player', t)
        local hammer, nova = rowFor(rows, 853), rowFor(rows, 122)
        assert(hammer.stage == 1 and not hammer.active and nova.stage == 1 and nova.active,
            'a start-only replay cannot reapply a displaced stun or remove the root')
    end
    h.ordinary = {spellID=853, startTime=103, duration=3}
    h.fire(103, 'LOSS_OF_CONTROL_ADDED')
    local hammer = assert(rowFor(ns.UI.GetRows('player', 103), 853))
    assert(hammer.stage == 2 and hammer.active and hammer.started == 103,
        'a genuinely new start-only stun must still progress its own DR')
end

-- The old reader may lose its instance ID in the very scan that first shows
-- the slot's replacement. Both reads still describe previously known timing.
for _, firstFallback in ipairs({false, true}) do
    local h, ns = setup()
    h.ordinary = firstFallback and {spellID=853, startTime=100, duration=10} or loc(853, 100, 10)
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    h.ordinary = loc(853, 100, 10)
    h.fire(100.1, 'LOSS_OF_CONTROL_UPDATE')
    h.byUnit, h.ordinary = loc(122, 102, 5), {spellID=853, startTime=100, duration=10}
    h.fire(102, 'LOSS_OF_CONTROL_UPDATE')
    local rows = ns.UI.GetRows('player', 102)
    local hammer, nova = rowFor(rows, 853), rowFor(rows, 122)
    assert(hammer.stage == 1 and not hammer.active and nova.stage == 1 and nova.active,
        'the displaced start-only report cannot stay active beside its replacement')
end

-- If both spells share a DR category, the displaced application's accepted
-- start belongs to the category's predecessor rather than its selected row.
do
    local h, ns = setup()
    h.ordinary = loc(853, 100, 10)
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    h.byUnit = loc(5211, 102, 5)
    h.fire(102, 'LOSS_OF_CONTROL_UPDATE')
    h.ordinary, h.byUnit = {spellID=853, startTime=100, duration=10}, nil
    h.fire(102.1, 'LOSS_OF_CONTROL_UPDATE')
    local rows = ns.UI.GetRows('player', 102.1)
    local bash = rowFor(rows, 5211)
    assert(#rows == 1 and bash and bash.stage == 2 and bash.started == 102 and bash.active,
        'a fallback replay cannot retake its DR category from a newer stun')
    h.ordinary = loc(853, 103, 3)
    h.ordinary.auraInstanceID = 18
    h.fire(103, 'LOSS_OF_CONTROL_ADDED')
    local hammer = assert(rowFor(ns.UI.GetRows('player', 103), 853))
    assert(hammer.stage == 3 and hammer.active and hammer.started == 103,
        'a new, independently identified application must still be counted')
end

-- The current spell may itself retain a fallback canonical key after its
-- native instance becomes readable. A stale solo report still cannot revive it.
do
    local h, ns = setup()
    h.ordinary = loc(853, 100, 5)
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    h.byUnit = {spellID=122, startTime=102, duration=5}
    h.fire(102, 'LOSS_OF_CONTROL_ADDED')
    h.byUnit.auraInstanceID = 17
    h.fire(102.1, 'LOSS_OF_CONTROL_UPDATE')
    h.byUnit = nil
    h.fire(102.2, 'LOSS_OF_CONTROL_UPDATE')
    local dr = ns.UI.GetRows('player', 102.2)
    assert(not rowFor(dr, 853).active and rowFor(dr, 122).active,
        'native replay cannot reactivate a spell displaced by a fallback-key successor')
end

-- Restricted indexed reads and LoC participate in the same DR snapshot.
for _, newerAura in ipairs({false, true}) do
    local h, ns = setup()
    h.ordinary = loc(853, 100, 2)
    h.fire(100, 'LOSS_OF_CONTROL_ADDED')
    local aura = newerAura and {spellId=122, duration=5, expirationTime=107}
        or {spellId=853, duration=2, expirationTime=102}
    aura.auraInstanceID, aura.isHarmful = 17, true
    C_UnitAuras.GetAuraDataByIndex = function(unit, index)
        if unit == 'player' then return index == 1 and aura or h.hidden end
    end
    if not newerAura then h.ordinary = loc(122, 102, 5) end
    h.fire(102, 'LOSS_OF_CONTROL_UPDATE')
    local root = rowFor(ns.UI.GetRows('player', 102), 122)
    assert(root and root.started == 102 and root.stageResetAt == 125 and root.stage == 1,
        'a conflicting indexed and LoC reader must select the later spell with its own end')
end

-- With no established ordering, retain the primary positive with its own fields.
local h, ns = setup()
for _, times in ipairs({
    {100, 100}, {100, 100.0005}, {h.hidden, 102}, {102, h.hidden}, {h.hidden, h.hidden},
}) do
    h.ordinary, h.byUnit = loc(853, times[1], 2), loc(122, times[2], 5)
    local chosen = assert(ns.Observer.ReadPlayerLoCEffects(102)['a:17'])
    local start = times[1] ~= h.hidden and times[1] or nil
    assert(chosen.spellID == 853 and chosen.appliedAt == start and chosen.expires == (start and start + 2)
        and chosen.reportedDuration == (start and 2), 'unordered readers cannot exchange timing')
end
print('native LoC conflict: both orders, replay, removal, uncertain and unavailable timing passed')
