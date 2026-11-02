-- Exercise local aura events, exact recovery and shared records at their observation time.
local fixtureDir = TEST_DIR or ((ADDON_DIR or '.')..'/tests')
local setup = assert(loadfile(fixtureDir..'/world_recovery_support.lua'))()
local failures, cases = {}, 0
local function case(name, run)
    local H = setup()
    local guid = 'Player-1-Rogue'
    H.units.target, H.hostile.target = guid, true
    local function fire(event, ...)
        H.ns.eventFrame.scripts.OnEvent(H.ns.eventFrame, event, ...)
    end
    function H.reset()
        H.time(100)
        fire('UNIT_SPELLCAST_SUCCEEDED', 'target', 'Cast-Evasion', 5277)
        assert(H.row(guid, 5277))
        H.time(115.05)
        fire('UNIT_SPELLCAST_SUCCEEDED', 'target', 'Cast-Preparation', 14185)
        assert(not H.row(guid, 5277))
    end
    function H.observe(path, at, duration, expiry, observedAt)
        H.time(at)
        local aura = {spellId=5277, isHelpful=true, auraInstanceID=34,
            duration=duration, expirationTime=expiry}
        if path == 'added' then
            fire('UNIT_AURA', 'target', {addedAuras={aura}})
        elseif path == 'exact' then
            H.auras.target = {[5277]=aura}
            fire('PLAYER_TARGET_CHANGED')
        else
            H.publish('target', guid, aura, observedAt or at, true)
            assert(H.ns.EvidenceBus.stats.errors == 0)
        end
        return H.row(guid, 5277)
    end
    local ok, why = pcall(run, H)
    cases = cases + 1
    if not ok then failures[#failures+1] = name..': '..tostring(why) end
end

for _, path in ipairs({'added', 'shared', 'exact'}) do
    case('expired first sighting '..path, function(H)
        assert(not H.observe(path, 100.101, 15, 100),
            'an already expired aura must not create a cooldown')
    end)
    case('expired endpoint with restricted duration '..path, function(H)
        assert(not H.observe(path, 100.101, H.hidden, 100),
            'a readable past endpoint bounds the aura even without its duration')
    end)
    case('stale report after Preparation '..path, function(H)
        H.reset()
        assert(not H.observe(path, 115.2, 15, 115),
            'an already expired native cannot reopen Evasion after Preparation')
        assert(not H.observe(path, 115.2, 15, 116),
            'a still-live pre-reset application also stays retired')
        local fresh = assert(H.observe(path, 115.5, 15, 130.5))
        assert(fresh.started == 115.5 and not fresh.timingEstimated,
            'stale evidence cannot consume admission of a genuine post-reset use')
    end)
    case('tolerated endpoint '..path, function(H)
        local row = assert(H.observe(path, 100.099, 15, 100))
        assert(row.started == 85 and not row.timingEstimated,
            'timing inside the clock tolerance retains its observed start')
    end)
    case('untimed evidence after Preparation '..path, function(H)
        H.reset()
        local row = H.observe(path, 115.2, H.hidden, H.hidden)
        if path == 'exact' then
            assert(not row, 'an untimed ordinary lookup cannot reopen the reset cooldown')
        else
            assert(row and row.started == 115.2 and row.timingEstimated,
                'a genuinely untimed added positive still permits a new use')
        end
    end)
end
case('subscriber replay of a valid shared observation', function(H)
    H.ns.EvidenceBus:Unsubscribe('bjarkiCC.cooldown-evidence')
    assert(not H.observe('shared', 99, 15, 100))
    H.time(105)
    H.ns.CooldownEvidence.ConnectShared(105)
    local row = assert(H.row(H.units.target, 5277))
    assert(row.started == 85 and not row.timingEstimated,
        'an aura active at observation remains valid evidence at replay')
end)
case('replay across reset', function(H)
    H.reset()
    assert(not H.observe('shared', 116, 15, 115, 114),
        'a valid historical observation cannot reopen the reset cooldown on delivery')
end)

assert(#failures == 0, table.concat(failures, '\n'))
print('PASS expired helpful aura evidence ('..cases..' cases)')
