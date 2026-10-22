-- Independent T2 reproductions and calibration/ownership controls.
local cases = dofile(ADDON_DIR..'/tests/timing_v16/v16_refresh_recovery_support.lua')
local failures, checks = {}, 0
for _, case in ipairs(cases) do
    for _, check in ipairs(case.checks) do
        checks = checks + 1
        if not check.passed then
            failures[#failures + 1] = case.name..' '..check.field..': expected '
                ..tostring(check.expected)..', got '..tostring(check.actual)
        end
    end
end
for _, failure in ipairs(failures) do print('FAIL '..failure) end
assert(#failures == 0, #failures..' occurrence assertion failures')
print('PASS refresh recovery: '..#cases..' cases, '..checks..' assertions')
