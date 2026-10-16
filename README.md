# bjarkiCC for WoW Forever beta

Compact icons show player, target and focus diminishing returns, plus observed enemy crowd-control cooldown estimates. Each DR bar follows its matching unit frame. The look follows old InterruptBar and Diminish: small square icons, centered timers and colored DR borders. Hammer of Justice, Kidney Shot, Frost Nova, traps and other CC families are included; interrupts can be enabled separately.

Version **0.4.0-beta** targets **1.60.1.70425**, interface **16001**. Offline Lua tests pass; revised outgoing detection and placement still need an in-game check. Protected enemy data can prevent confirmed target/focus DR or cooldown tracking on this beta.

## Changes in 0.4

- Target/focus can supplement incomplete aura scans with readable per-unit Loss of Control records. Diagnostics explain which sources are available and list readable unmapped IDs.
- Your eligible targeted CC casts can start an estimated DR display when enemy auras are hidden. These always show a gray `?`: a successful cast does not prove the CC landed. Readable applications take precedence without counting the same cast twice. Disable this fallback in DR settings.
- Icons now sit above the name/health area, inset from portrait badges. Player grows right; target/focus grow left. Old defaults migrate; custom positions are kept. `/bcc reset` adopts the new placement.
- The requested application-based timer remains: application starts or refreshes it, and breaking/removing CC never restarts it. Research distinguishes this chosen display policy from Classic's removal-based reset convention; Forever's exact reset rule remains unconfirmed. See [architecture.md](architecture.md).

## Frame anchoring

- Player DR follows `PlayerFrame`, target DR follows `TargetFrame`, and focus DR follows `FocusFrame`.
- Each uses the corresponding visible health region for placement, with portrait/frame fallbacks. Use `/bcc unlock` outside combat and drag the icons to adjust the offset; `/bcc lock` saves the layout from accidental movement. Offsets persist across reloads.
- Moving the native unit frame also moves its DR bar. Bars disappear with hidden unit frames during live play; preview/unlock still shows setup handles.
- The enemy cooldown bar remains independently movable.
- Target and focus share one observation history when they refer to the same player. Switching targets preserves the old target's DR if that player remains focused.

Upgrading initializes frame-relative DR offsets once, preserving size, filters and the cooldown bar's position. `/bcc reset` restores the default offsets. The anchors use Blizzard's named unit frames, including addons that reposition those frames. Replacement unit-frame addons with different frame names are not automatically detected. If a native frame is missing, a setup-only handle appears at the old screen position; its live DR bar stays hidden until the native frame exists.

## Minimal display

- DR icons default to 28px; cooldown icons to 32px, with 3px spacing.
- Live bars have no headings, category captions, backgrounds or empty-state messages.
- Timers use whole seconds, or compact minutes for long cooldowns.
- DR stages use colored borders. Percentage text and caster names are optional in Display settings.
- Small `?` markers remain visible when information is uncertain; `M` identifies a manually marked use.
- Empty bars disappear when locked. Labels appear only in preview or while moving bars.

Previous default sizes and spacing migrate once to the compact defaults. Diagnostics remain available through `/bcc status`.

## Install

1. Exit WoW and extract the ZIP into `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. The resulting file must be `Interface/AddOns/bjarkiCC/bjarkiCC.toc`, with no extra nested folder.
3. Start the beta, enable **bjarkiCC (Forever)** in AddOns and log in.
4. Select a target and set a focus so both frames are visible. Outside combat, run `/bcc test`, then `/bcc unlock`. Drag the three DR bars beside their frames and place the cooldown bar where you prefer.
5. Run `/bcc lock`, then `/bcc test` again to return to live observation.

The package includes all Lua source; no other addon or library is required. Installation does not replace bjarkiUI or bjarkiPortraits.

## Controls

| Command | Action |
| --- | --- |
| `/bcc` | Open settings: bars, DR categories, cooldown filters |
| `/bcc test` | Toggle clearly labeled synthetic preview icons |
| `/bcc unlock` / `/bcc lock` | Adjust DR offsets and cooldown position outside combat, or lock bars |
| `/bcc reset` | Restore default frame offsets and cooldown position; preserve other settings |
| `/bcc clear` | Clear observation history and restart the sensors |
| `/bcc status` | Open a copyable build/API diagnostic report |
| `/bcc cooldown 853 45` | Use a 45-second HoJ estimate for future observations |
| `/bcc cooldown 853 default` | Restore HoJ's default estimate range |
| `/bcc used 853` | Manually mark HoJ used by the selected hostile player |

The Display panel has enable, size and vertical-layout controls for each of the four bars, plus optional caster names and DR percentages. The cooldown panel offers a current-target filter, optional interrupts, and individual ability toggles. Existing custom spacing, growth direction and icon limits remain saved. Positions and preferences are saved account-wide. Live combat history and test mode are not saved. Anchor changes made in combat apply after combat; combat starting during a drag restores the previously saved offset.

## Read the bars

DR borders show the estimated duration of the **next** application: **green = 50%**, **yellow = 25%**, **red = immune**. Optional percentage text shows the same stages. The countdown starts on application, including while CC remains active. New applications refresh it; CC duration, expiry or an early break do not change its start. Gray **?** means earlier applications or removals may have been missed.

The default profile uses nine Classic categories and the requested 20-second timer from the last observed application. Its category and timing assumptions remain provisional for Forever. Own-cast estimates instead start at cast success, approximating an application that may be hidden or may never land; they always remain uncertain. Initial login, a newly observed player, unavailable data, and a scan gap longer than one second invalidate observed history. A full observation window is needed before new applications can be assigned confident stages. History remains continuous while the same player stays observable through player, target or focus, including target/focus swaps. Losing the last tracked reference discards that player's observed DR history. Recorded enemy cooldowns remain independent of target/focus changes.

Cooldown icons show the remaining configured estimate. Caster names appear on hover, or beneath the icons when enabled. Identical spell icons can belong to different enemies. For talent ranges such as HoJ's 45–60 seconds, the main timer counts toward 60; **?** appears once the 45-second estimate has elapsed. Hover for the shorter estimate. These ranges do not cover every item, beta change or unobserved reset. **M** marks a manual entry. Expired icons disappear; absence does not mean confirmed readiness. A small `+N` indicates additional timers beyond the bar's icon limit.

Spammable abilities such as Polymorph contribute to the DR map without receiving an invented cooldown. Shared shocks use one cooldown icon. Blind and Death Coil have cooldown icons but no DR entry in the selected Classic profile.

## Beta observation limits

Forever restricts combat-log access, so bjarkiCC never registers combat-log events. It uses readable harmful aura snapshots, guarded player/per-unit Loss of Control APIs when needed, and readable unit-cast events. It does not recover or branch on protected values.

Own-cast estimates correlate the intended name at cast-send time with a visible player target/focus, then require matching successful cast and spell identifiers. Switching target after sending cannot redirect that estimate. Failed/interrupted casts are discarded; area effects, traps, procs and pet orders are excluded. Same-name ambiguity between target and focus is rejected, but a different same-name mouseover/outside unit cannot be ruled out because the event supplies a name, not a victim GUID. Resistance and immunity can still leave a false-positive estimate. This fallback cannot reconstruct other players' hidden CC.

An enemy timer requires a visible event plus readable spell ID, unit identity, name and hostility. Off-screen enemies, late target selection, secret casts and unobserved resets can be missed. Player pets are tracked under their own identity. The target-only filter does not attribute a pet's cooldown to its owner. Hidden empty bars do not mean the data is available; check `/bcc status` if expected icons never appear.

Loss of Control can omit debuffs such as Frost Shock. Once a readable player fallback is selected, it remains selected until `/bcc clear`, world entry, or reload. Target/focus accept readable per-unit witnesses alongside partial auras, but an empty LoC list cannot establish that all effects ended. An unavailable or partial scan remains restricted in diagnostics. Target and focus DR are PvP player tracking; NPC targets do not produce DR bars.

There are **120 aura/effect IDs**, **85 cast IDs** and **27 cooldown families** in this initial registry. New Forever spells and item activation cooldowns are not fully covered. Data provenance and specific timing assumptions are in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## First live check

1. Enable Lua errors with `/console scriptErrors 1`, then `/reload`.
2. Use `/bcc test` to check icon size, dragging, tooltips and both orientations. Move the player/target/focus frames in Edit Mode and confirm their DR bars follow. Adjust each offset, `/reload`, and confirm it persists. Turn test mode off.
3. With a paladin opponent, select each other and remain free of CC for more than 20 seconds.
4. Observe HoJ: its cooldown icon should identify the paladin if the cast event is readable. Your stun DR countdown should start immediately on application and keep counting without jumping when HoJ ends. Repeat with a breakable CC, breaking it immediately; its original timer should continue.
5. Within the reset window, test another mapped stun. Check duration/stage against what actually happens in the duel. Test Kidney Shot separately.
6. Focus the opponent, then switch targets: the opponent's DR window should remain on the focus frame. Target the opponent again and confirm target/focus agree. Clear both references, then select the opponent again: observation should restart uncertain. Old enemy cooldown estimates may remain on the all-enemies bar.
7. Copy `/bcc status` after the duel. Record expected behavior, actual behavior, spell rank, talents and any Lua error. Never treat test-mode icons as proof that the beta exposes the required combat events.
8. Cast your own mapped CC on the target, then on a different focus via a focus macro. Where auras are hidden, a gray `?` estimate should appear. Interrupt a cast before it succeeds and check that no new estimate appears. If an aura becomes readable, it must replace the estimate without a double stage advance. Capture `/bcc status` while a missing effect is still active.

## Development and tests

The `tests` directory is not loaded by the addon. With Python 3 and `lupa==2.8` installed, run `python tests/run_tests.py` from the addon/repository folder. The runner uses `lupa.lua51` to execute the actual Lua modules. Seven suites cover the tracking model, guarded API inputs, own-cast correlation, migration, scale-aware dragging, combat deferral, focus continuity, compact display states, filtering and addon initialization/event/command integration. UI boundary fixtures cannot reproduce WoW's protected execution engine or visually validate the in-game frames.

Visual references: [original InterruptBar](https://www.wowace.com/projects/interruptbar), [Diminish](https://github.com/wardz/Diminish). This is an original UI implementation; no code from those interfaces was copied.

See [architecture.md](architecture.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
