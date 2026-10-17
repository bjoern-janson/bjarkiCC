# bjarkiCC for WoW Forever beta

Compact icons show player, target and focus diminishing returns, plus observed enemy crowd-control cooldown estimates. Each DR bar follows its matching unit frame. The look follows old InterruptBar and Diminish: small square icons, centered timers and colored DR borders. Hammer of Justice, Kidney Shot, Frost Nova, traps and other CC families are included; interrupts can be enabled separately.

Version **0.4.13-beta** targets **1.60.1.70425**, interface **16001**. All nine offline Lua suites pass; revised behavior still needs an in-game check. Protected enemy data can prevent confirmed target/focus DR or cooldown tracking on this beta.

## Preserve consecutive refreshes in 0.4.13

The latest trace exposes a missing sequence-learning case: a ten-second Hibernate refreshes into a five-second Hibernate on the same aura ID, with the new start exactly at the prior end. The applications counted correctly, but the addon discarded its full/half/quarter learning progress because no empty snapshot occurred between them. Without that baseline, the following full and half-duration casts stayed red.

Version 0.4.13 accepts a narrowly verified, nonoverlapping same-ID refresh as a link in that three-application sequence. Both applications need explicit Loss of Control timing, coherent reported duration and exact identity; the gap must be shorter than 15 seconds with no competing category effect or observation gap. This only supplies sequence evidence. It does not invent an observed removal, shorten the stage-reset setting or restart a timer. The later reset correction still requires observed absence and a matching learned full duration.

The supplied sequence now replays green/yellow/red, then green/yellow. Border meaning remains the next expected duration: after the first successful CC green means 50%, after the second yellow means 25%, and after the third red means immune. The new bevel, decimal formatting and separate application/stage clocks remain in place. Offline replay passes; live retesting is still needed.

## Native action-button borders and countdown text in 0.4.12

Icons now use Forever's beveled action-button artwork. DR borders retain green/yellow/red stage colors; enemy cooldown borders use the artwork's neutral color. The border sits above the cooldown sweep so its tint stays visible. Clients without this atlas retain a simple outline. Icon size, saved positions and anchors are preserved.

Countdowns match the updated portrait addon's formatting: whole seconds truncate down (`12.8` displays `12`), with one decimal strictly below five seconds (`4.44` displays `4.4`). Exactly five displays `5`; long cooldowns retain compact minute text. This replaces the old nearest-second presentation without changing the application countdown, separate stage-reset estimate, or when icons disappear. `/bcc test` previews the artwork and the decimal transition.

The exact beta UI source supplies the atlas and its proportions; offline tests cover stage tint, layering, formatter boundaries and the protected-geometry regression. Appearance and readability still need an in-game check.

## Learn from a complete CC sequence in 0.4.11

The latest 0.4.10 log confirms the source handoff is preserved. However, tracking began only 13.851 seconds before the first Hibernate, so the 20-second quiet-learning requirement prevented any full-duration baseline. The first 20/10/5-second sequence counted correctly; the next full and half-duration applications incorrectly retained red because the correction had no learned baseline.

Version 0.4.11 adds another way to establish that baseline: three consecutive, completely observed applications of the same spell on the same player with explicit durations D, D/2 and D/4. Each subsequent application must follow an observed end with a gap shorter than 15 seconds, without overlap, missing observations, intervening category applications or inferred stages. One or two samples cannot qualify. The sequence supplies the original full-duration baseline only after its third application; it does not recolor individual casts by their duration ratio. The existing guarded correction can then recognize the subsequent full-duration return. This remains an inference under the provisional Classic profile.

The supplied trace replays as green/yellow/red, then green/yellow. A synthetic next quarter-duration application checks red. Red on the initial five-second third Hibernate is expected: it indicates that the next CC is expected to be immune. The later ten-second second Hibernate should be yellow, indicating 25% duration on the next CC.

Status now distinguishes an absent baseline, a partial sequence and a learned baseline with its evidence source. The 20-second application countdown and configurable stage-reset estimate are unchanged. Live validation remains necessary.

## Preserve the first full-duration sample in 0.4.10

The new 0.4.9 report exposes a source transition missed by the earlier replay. The first Hibernate was read through auras, then Loss of Control reported that same aura. The addon treated the switch itself as lost coverage and discarded the preceding quiet history. It therefore never learned the full-duration baseline, and the next full/half/quarter sequence remained red.

Version 0.4.10 preserves that history only for a complete player aura-to-LoC transition with the same nonempty set of exact aura IDs, spells and categories, and readable prior aura timing. Real observation gaps, partial data, ambiguous identities and mismatched effect sets still invalidate it. The original aura duration is only a consistency check: a conflicting later LoC duration cannot be learned as full. Only explicit LoC duration supplies a baseline.

The supplied sequence is covered through real event handling, observation, stage tracking and all three displays: the second full 20-second Hibernate should return to green, the following 10-second one to yellow, and the 5-second one to red. This is offline replay coverage; live retesting remains necessary. Application countdown and configured stage-reset interval are unchanged. `/bcc status` includes source-handoff counters alongside the existing duration evidence.

## Full-duration evidence correction in 0.4.9

Another 0.4.7 trace shows full Hibernate returning **15.5 seconds after the previous CC's accepted end**. The 18-second estimate added in 0.4.8 also retains red too long in this case. The log does not show an immune attempt extending either clock: the next recorded change is a new landed aura. Neither this trace nor the earlier one establishes an exact universal reset interval.

Version 0.4.9 keeps the application countdown at 20 seconds and the configurable reset estimate at 18. It adds a narrow correction when explicit Loss of Control timing matches a previously observed full duration for the same player and exact spell. Learning requires at least 20 seconds of continuous complete category absence beforehand; correcting requires at least 15 seconds of observed absence after the prior end, no overlapping CC and matching readable duration evidence. The stage then returns to green without restarting or lengthening that application's countdown. This remains an inference, shown on hover and in `/bcc status`; it does not infer half/quarter stages from remaining time.

The correction requires a learned baseline. Missing/secret duration, an observation gap, ambiguous identity, active overlap or an unconfirmed cast cannot trigger it. Lost visibility clears learned duration evidence. Icons still disappear at application expiry, and immune-stage cast attempts without a new aura still preserve both deadlines. For a live check, stay free of the category for more than 20 seconds while continuously tracked, then repeat the full/half/quarter sequence and the reported subsequent full application. Capture `/bcc status` while it is active; it now records explicit reported duration separately from predicted expiry.

## Countdown cleanup and independent reset in 0.4.8

DR icons now disappear when their application countdown ends. The model keeps stage history internally, so hiding an icon does not reset the next application's color. If the stage expires first, its icon also disappears; an old stage color is not kept alive solely to finish a number.

The display countdown remains 20 seconds from application. The separate stage-reset setting now defaults to **18 seconds after CC ends**, and both values can be changed independently under DR settings. Existing application-countdown preferences are preserved. The supplied 0.4.7 trace has a full 20-second Hibernate landing 18.015 seconds after the preceding quarter-duration effect disappeared; the old 20-second stage rule incorrectly carried red into it. The 18-second estimate replays that application as green. This is a provisional adjustment from the captured sequence, not proof of a universal 18-second Forever reset. That release did not use duration to correct stage history; the guarded full-duration correction added in 0.4.9 is described above.

## Separate stage reset introduced in 0.4.7

The 20-second application countdown stays as requested, but reaching zero no longer resets the DR stage. Observed stage history lasts through the CC and the configured reset interval after it ends. A full 20-second Hibernate followed by another at 22 seconds therefore keeps its place in the sequence. Early breaks adjust the stage deadline without restarting the application countdown.

Version 0.4.7 kept a blank colored icon after the application countdown and used the same 20-second setting for stage reset. Version 0.4.8 hides that icon and gives stage reset its own provisional 18-second setting. Unknown CC ends remain pending internally; restricted or missing aura data cannot prove removal. Unconfirmed cast estimates remain bounded by their application countdown because they supply no confirmed CC end.

`/bcc status` includes the separate stage deadline and the latest 24 observation changes from its bounded history. The 0.4.6 live report showed 10- and 5-second Hibernate records counted as stages one and two, but omitted the preceding full application. The old application-only reset can reproduce that undercount; the report alone does not establish exactly what happened before those records. The new policy was explicitly selected by the user.

## Correction in 0.4.6

The next live report identified a second double-count path: an aura-derived start was followed by a slightly later explicit Loss of Control start for the same Hibernate. That source change counted the first CC twice and made the real second CC red. The first explicit LoC time now calibrates the existing application; the later LoC refresh still advances it to yellow. Once known, that explicit clock survives lower-quality aura samples and older LoC timestamps. This preserves the 20-second application timer and prevents the same source handoff from repeatedly inflating the cycle. Replay tests include the actual event path, all three unit bars, colors and countdowns. A new live check is still needed.

## Correction in 0.4.5

The live Hibernate trace exposed the same aura being counted twice: once before its application time was readable, then again when that timestamp arrived shortly afterward. The first readable time now corrects that application's clock without counting another CC, even if it is later than the initial observation. The recorded first Hibernate stays green and the recorded second stays yellow. Subsequent new applications still advance normally. The 20-second application-based timer is unchanged. This corrects the reproduced duplicate count; the trace does not establish that a resisted cast was counted.

## Correction in 0.4.4

Further unconfirmed cast attempts no longer restart a red DR timer. The third application starts the final-stage countdown; subsequent own casts in that category leave its deadline intact until it expires. This applies to observed, inferred and mixed stage history. A readable new application can still correct the tracked state. Cast success alone does not prove a hit or immunity, and the chosen application-based timer is unchanged.

## Corrections in 0.4.3

- A sub-millisecond correction to a Loss of Control start time no longer counts the same CC again when no aura instance ID is available. The same application returning after an empty snapshot also keeps its count; a genuinely newer application still advances it.
- DR icons no longer show question marks. Uncertainty remains in the tooltip and `/bcc status`; uncertain rows omit optional percentage text. Borders show the tracked cycle: green first, yellow second, red third.
- `/bcc status` includes the last eight observation changes, with readable witness identities, original timing and counted stages. A bounded 48-entry history ignores unchanged polls and expiry-only noise, so another mismatch can be diagnosed from its actual sequence.
- Reduced Hibernate showing green remains an open live report. That release's application-only stage policy restarted the cycle at 20 seconds from the preceding application (superseded by 0.4.7); that can differ from the game's DR reset. The earlier cast interval was not recorded. No server-timing change or duration-based stage guess is included.

## Corrections in 0.4.2

- Accept Forever's observed `Name Realm` cast destination alongside `Name` and `Name-Realm`, using readable unit-name fields. This fixes the reproduced matching failure that prevented offensive estimates from starting. Target/focus aliases of the same GUID share readable names; distinct ambiguous destinations remain rejected.
- Keep inferred stage progression when a later application becomes readable. A confirmed second CC no longer discards the earlier cast estimate and displays stage one. Tooltips and diagnostics distinguish earlier inferred applications from observed stages.
- Retain bounded category history after the icon expires so a delayed readable application can advance from its actual timestamp. This release still used an application-only stage boundary, superseded by the separate stage reset in 0.4.7.
- `/bcc status` now gives destination-resolution counts and the last safe name-matching summary. The application-based timer, frame offsets and solid texture borders are unchanged.

## Corrections in 0.4.1

- Late observations use a readable application timestamp instead of starting another full 20 seconds at discovery. A timestamp becoming readable later corrects the existing clock. This cannot make hidden events visible earlier.
- Consecutive applications can refresh a reused aura identity when its readable timing establishes a new application. Unchanged polling does not advance DR.
- Switching observation sources preserves already recorded DR instead of resetting its stage; incomplete evidence remains flagged as uncertain.
- Borders keep their green/yellow/red stage colors. Tooltips distinguish uncertain history or an inferred cast; color alone is not confirmation of the victim's actual DR.
- Whole-second text uses the portrait's rounding convention, without subtracting a second from the timer.
- Anchored bars/icons use solid textures instead of Blizzard's backdrop size handler. The client log identified that handler performing arithmetic on a protected width during CC.

## Changes in 0.4

- Target/focus can supplement incomplete aura scans with readable per-unit Loss of Control records. Diagnostics explain which sources are available and list readable unmapped IDs.
- Your eligible targeted CC casts can start an estimated DR display when enemy auras are hidden. Hover identifies these estimates: a successful cast does not prove the CC landed. Readable applications take precedence without counting the same cast twice. Disable this fallback in DR settings.
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
- DR uncertainty is explained on hover. Cooldown `?` marks the uncertain talent range; `M` identifies a manually marked use.
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

DR borders show the tracked cycle: **green = first**, **yellow = second**, **red = third**. In the baseline profile these correspond to a next duration of **50%**, **25%**, and **immune**. Optional percentage text appears only when history is considered complete; hover to see whether the count is observed, cast-inferred or corrected by matching full-duration evidence. The countdown starts on application, including while CC remains active. New applications refresh it; an early break or removal does not change its start. Icons hide when the application countdown ends or the stage resets, whichever comes first. Stage history can remain internally after the icon hides; its separate reset estimate is available in `/bcc status` and on hover while the icon is visible. The display has no DR question-mark badge.

The default profile uses nine Classic categories, the requested 20-second countdown from the last observed application, and an independently configurable stage reset window, defaulting to 18 seconds after CC ends. Its category and timing assumptions remain provisional for Forever. Own-cast estimates instead start at cast success, approximating an application that may be hidden or may never land; they always remain uncertain. Initial login, a newly observed player, unavailable data, and a scan gap longer than one second invalidate observed history. A full observation window is needed before new applications can be assigned confident stages. History remains continuous while the same player stays observable through player, target or focus, including target/focus swaps. Losing the last tracked reference discards that player's observed DR history. Recorded enemy cooldowns remain independent of target/focus changes.

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
8. Cast your own mapped CC on the target, then on a different focus via a focus macro. Where auras are hidden, a stage-colored estimate should appear; hover to inspect its evidence. Interrupt a cast before it succeeds and check that no new estimate appears. If an aura becomes readable, it must replace the estimate without a double stage advance. Capture `/bcc status` while a missing effect or incorrect cycle is still active; it includes recent observation changes.
9. Let a full 20-second Hibernate finish, then reapply 22 seconds after the first application (about two seconds after it ends). Stage two must remain even though the first application countdown has ended. Repeat the same category within the separate reset window. Confirm green → yellow → red and a fresh application countdown for each readable reapplication. An unchanged active CC must not advance on its own. Let the CC end and repeat it while checking for Lua errors.

10. Repeat the full/half/quarter chain, then try a new Hibernate about 18 seconds after the quarter effect ends. Record actual duration and `/bcc status`; the provisional 18-second model starts a fresh green cycle at its reset boundary. Compare several trials near the boundary before treating that value as a server constant. Let an application countdown finish: its icon must hide, while `/bcc status` can still retain stage history.

## Development and tests

The `tests` directory is not loaded by the addon. With Python 3 and `lupa==2.8` installed, run `python tests/run_tests.py` from the addon/repository folder. The runner uses `lupa.lua51` to execute the actual Lua modules. Nine suites cover the tracking model, guarded API inputs, own-cast correlation, migration, scale-aware dragging, combat deferral, focus continuity, compact display states, protected backdrop geometry and addon initialization/event/command integration. UI boundary fixtures cannot reproduce WoW's complete protected execution engine or visually validate the in-game frames.

Visual references: [original InterruptBar](https://www.wowace.com/projects/interruptbar), [Diminish](https://github.com/wardz/Diminish). This is an original UI implementation; no code from those interfaces was copied.

See [architecture.md](architecture.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
