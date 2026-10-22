-- Independent T3 reproductions, order variants, and source/removal controls.
local cases = dofile(ADDON_DIR..'/tests/timing_v16/v16_alias_expiry_support.lua')
local failures, checks = {}, 0
for _, case in ipairs(cases) do
    for field, expected in pairs(case.expected) do
        checks = checks + 1
        local actual = case[field]
        local equal = actual == expected
        if type(actual) == 'number' and type(expected) == 'number' then
            equal = math.abs(actual - expected) <= 1e-9
        end
        if not equal then
            failures[#failures + 1] = case.name..' '..field..': expected '
                ..tostring(expected)..', got '..tostring(actual)
        end
    end
end
for _, failure in ipairs(failures) do print('FAIL '..failure) end
assert(#failures == 0, #failures..' alias assertion failures')
print('PASS alias expiry: '..#cases..' cases, '..checks..' assertions')
