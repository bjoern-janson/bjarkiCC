-- Endpoint source and endpoint occurrence are independent from the merged
-- application clock. A tagged nil donor start stays unbound.
local cases = dofile(ADDON_DIR..'/tests/timing_v16/v16_expiry_authority_support.lua')
local NIL = '<nil>'
local expected = {
    ['mixed-end-11']={expires=13,reset=31,stage=1,rawExpirySource='aura'},
    ['mixed-end-20']={expires=13,reset=31,stage=1,rawExpirySource='aura'},
    ['initially-unknown-end-can-use-aura-end']={expires=20,reset=38,stage=1},
    ['later-missing-end-retains-same-occurrence-end']={expires=20,reset=38,stage=1},
    ['actual-loc-end-can-replace-initial-weak-end']={expires=13,reset=31,stage=1},
    ['same-start-remaining-time-end-is-not-raw-duration']={expires=16,reset=34,stage=1,rawDuration=NIL},
    ['stale-explicit-start-cannot-donate-remaining-end']={expires=16,reset=34,stage=1},
    ['unbound-native-loc-end-must-not-borrow-parallel-loc-start']={expires=13,reset=31,stage=1},
    ['legacy-direct-loc-end-without-provenance-or-duration']={expires=16,reset=34,stage=1},
    ['explicitly-weak-direct-mixed-end-must-not-be-upgraded']={expires=16,reset=34,stage=1},
    ['older-loc-endpoint-must-not-fill-newer-unknown-end']={expires=NIL,reset=NIL,pending=true,stage=1},
    ['older-aura-endpoint-must-not-fill-newer-unknown-end']={expires=NIL,reset=NIL,pending=true,stage=1},
    ['new-native-refresh-must-not-borrow-old-fallback-end']={expires=NIL,reset=NIL,pending=true,stage=2},
}
local failures, checks = {}, 0
for _, case in ipairs(cases) do
    for field, value in pairs(assert(expected[case.name], case.name)) do
        checks = checks + 1
        local actual = case[field]
        if actual == nil then actual = NIL end
        local equal = actual == value
        if type(actual) == 'number' and type(value) == 'number' then
            equal = math.abs(actual - value) <= 1e-9
        end
        if not equal then
            failures[#failures + 1] = case.name..' '..field..': expected '
                ..tostring(value)..', got '..tostring(actual)
        end
    end
end
assert(#cases == 13, 'all independent authority cases must execute')
for _, failure in ipairs(failures) do print('FAIL '..failure) end
assert(#failures == 0, #failures..' endpoint authority assertion failures')
print('PASS endpoint authority: '..#cases..' cases, '..checks..' assertions')
