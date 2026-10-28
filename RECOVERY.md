# Recover the 0.4.17 settings after a rollback

This document preserves the **historical 0.4.17 rollback**. The current repository runtime is **0.4.17.43-correction-fixes-test**. The command below is not required when upgrading to the current build; use the current settings and migration described in [README.md](README.md). Historical statements about confirmed-hit-only War Stomp and the nine passing suites refer to the rollback source.

Recovery recorded 2026-10-17. At this recovery checkpoint, runtime and tests were restored to the original 0.4.17-beta release (commit `9ad8325c460f5a2704a701b47e3de91ffd040935`). Later changes remain in Git history. This is a rollback, not a new tracking fix.

## Why replacing the addon did not restore its behavior

WoW stores `bjarkiCCDB` separately in account SavedVariables. Reinstalling an older addon does not reset it. The installed Lua files and TOCs matched the original 0.4.17 ZIP, but both inspected profiles retained `ownCastEstimates=false` and `stageResetSeconds=20` from later builds. The original initializer accepts these values, so its behavior differed from a fresh 0.4.17 profile.

## Restore the original defaults

With 0.4.17 loaded, run this on each affected client:

```lua
/run bjarkiCCDB.ownCastEstimates=true; bjarkiCCDB.stageResetSeconds=18; ReloadUI()
```

This restores only the original caster-estimate and stage-retention defaults. The application countdown remains 20 seconds. Artwork, bar positions, sizes, filters and cooldown settings are preserved. The 18-second retention after CC ends is this version's provisional policy, not a verified Forever server rule. Schema needs no manual change. `/bcc reset` resets positions only; `/bcc clear` clears tracking history only.

The two inspected profiles were backed up and repaired on disk. A later read showed those edits had been overwritten; external read-back did not establish that the loaded clients had adopted them. Use the in-client command above to update loaded settings. The subsequent supplied 0.4.17 status reports caster estimates enabled and stage retention at 18 seconds. The actual 0.4.17 initializer reproduced the mismatch and verified the restored values, with every other initialized setting unchanged. Both written files were read back and hash-verified. Account names and personal SavedVariables are not included in this repository.

## Unresolved behavior

- Direct-cast estimates can count dodges, resists or immune attempts; cast success is not a confirmed hit. Restoring estimates restores this old limitation too.
- War Stomp remains confirmed-hit only. In the supplied caster trace, indexed aura access was restricted, the exact lookup returned no aura, and ByUnit Loss of Control returned no records. Recipient-side detection does not establish caster-side coverage.
- Enemy cooldown observation remains unresolved in supplied reports (`acceptedCasts=0`).
- Reported stage/color, timing and appearance problems are not all explained by the saved-settings mismatch. No successful live retest has established reliable tracking after recovery.

All nine original offline Lua suites pass. Source/package equality and settings verification establish the rollback only, not live gameplay correctness.

Original ZIP SHA-256: `ef6c8fe5650267ee34ab0bb03b2bcec92e2657df87ec0f6d6b01a36f86399e2e`.

The subsequent 0.4.17.1 patch adds only the Nature's Grasp observation fallback and diagnostics; the original artwork, stage model and saved-setting initialization remain the baseline.
