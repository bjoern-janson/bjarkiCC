-- v16 timing regressions; each group loads fresh real addon modules.
local scripts = {
    'v16_alias_expiry.lua',
    'v16_alias_ownership.lua',
    'v16_audit_timing.lua',
    'v16_endpoint_constructors.lua',
    'v16_expiry_authority.lua',
    'v16_refresh_occurrence.lua',
    'v16_refresh_recovery.lua',
}
for _, name in ipairs(scripts) do
    assert(loadfile(ADDON_DIR..'/tests/timing_v16/'..name))()
end
print('PASS seven v16 timing groups')
