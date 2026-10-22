-- Original external v15 audit scenarios, with desired-behavior assertions.
local cases = dofile(ADDON_DIR..'/tests/timing_v16/v16_audit_timing_support.lua')
local failures, checks = {}, 0
local function check(case, field, expected)
    checks = checks + 1
    if case[field] ~= expected then
        failures[#failures + 1] = case.name..' '..field..': expected '
            ..tostring(expected)..', got '..tostring(case[field])
    end
end
for _, case in ipairs(cases) do
    if case.name == 'direct-refresh-without-expiry'
        or case.name == 'observer-refresh-without-expiry' then
        check(case, 'effectExpires', nil)
        check(case, 'stageResetAt', nil)
        check(case, 'stageResetPending', true)
        check(case, 'active', true)
        check(case, 'stage', 2)
    elseif case.name:find('weaker%-aura%-fills%-missing%-loc%-expiry') then
        -- This was exploratory, not a confirmed defect. Preserve the useful
        -- same-occurrence weak bound when no accepted end exists.
        check(case, 'effectExpires', 20)
        check(case, 'stage', 1)
    else
        for expected, field in pairs({expectedExpiry='effectExpires',
            expectedStage='stage', expectedReset='stageResetAt'}) do
            if case[expected] ~= nil then check(case, field, case[expected]) end
        end
    end
    if case.scanGaps ~= nil then check(case, 'scanGaps', 0) end
end
for _, failure in ipairs(failures) do print('FAIL '..failure) end
assert(#failures == 0, #failures..' external audit assertion failures')
print('PASS external audit timing: '..#cases..' observations, '..checks..' assertions')
