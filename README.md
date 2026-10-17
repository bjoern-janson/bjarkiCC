# bjarkiCC for WoW Forever beta

## 0.4.17.6: Native, secure hostile-stun visual experiment (optional)

This experimental branch uses **Blizzard's `CustomAuraContainerTemplate`**, the same native secure aura presentation family used by bjarkiPortraits. Blizzard's own code permits spell-ID matching on harmful auras on non-assistable enemies. Unlike `GetAuraDataByIndex`, the native aura widget can sometimes display an actual aura without granting Lua access to the selected spell or its duration. Whether it does so for hidden Forever stun effects still requires a *real in-game test*.

- `/bcc aura on` creates/enables one compact native aura slot below **Target** and **Focus** DR grids, matching **only** Bash (5211, 6798, 8983), War Stomp (20549), and Iron Grenade (4068). The effect icon and native cooldown are **drawn by Blizzard**. The label **STUN AURA** is attached to the aura button itself, so no persistent extra label occupies the screen when no matching aura is visible.
- `/bcc aura off` disables this visual. `/bcc aura status` reports initialization/creation errors and whether the visual is requested. It deliberately **does not inspect the native aura slot's shown state**, which may be restricted.
- The widget is OFF by default and never reads protected aura information back into `Model.lua`. A genuine aura indicator is useful *visual confirmation* only; it is **not** an automatic DR application count. The existing DR stage, green/yellow/red borders, 20s application timer and provisional reset logic do not change.
- Creation is delayed to `PLAYER_ENTERING_WORLD`, all structural changes are out of combat, and requested changes during combat reconcile afterward. Each widget stays attached to the corresponding addon-owned DR bar and follows its placement.
- When `C_Secrets.ShouldUnitAuraIndexBeSecret(unit,index,"HARMFUL")` explicitly confirms an indexed aura would be secret, the observer now **skips that known-throwing query** and marks the snapshot *partial/unknown*. This reduces repeated taint errors without inventing a missing or present stun. `/bcc status` reports `predictedSecretAuraIndexes`.

**Fast test:** reload, target/focus your duel opponent, run `/bcc aura on` out of combat, Bash the opponent then test Iron Grenade/War Stomp separately. Look **just below the Target/Focus DR grids** for a small stun icon with the caption STUN AURA while the opponent is visibly stunned. If the native witness icon appears while `/bcc status` still reports unconfirmed DR, we have visually useful information but cannot automatically count a DR stage. If no native icon appears, tell us whether `/bcc aura status` reports constructed or unavailable; do **not** make a claim of a confirmed victim-specific hit.

The user has directly tested Bash, War Stomp and Iron Grenade sharing DR on Forever (2026-10-17). All remain in `Controlled Stun`, not `Incapacitate`. The game's `C_SpellDiminish.IsSystemSupported()` reported false on the tested client, so native Blizzard DR stage events remain unavailable independently of this custom aura-container attempt.


## 0.4.17.5: Native DR support probe for urgent Bash/Grenade duel testing

A supplied **0.4.17.3 live status report** showed 1,186 `C_UnitAuras.GetAuraDataByIndex` access errors, `auraEventPositives=0`, `nativeDREvents=0`, target/focus exact War Stomp/Grenade lookups returning `none`, and complete per-unit LoC lists with zero mapped hits. However, the **receiving player** had a confirmed LoC Bash (5211), proving the spell mapping worked on the receiving side. `ownCast.captured=14`, `ownCast.estimated=11`, and no unresolved cast destinations show that the general direct-cast correlation runs. **There is no proof of a victim-specific caster-side Bash or Grenade application** in that report. Do not turn successful casts into confirmed stun stages.

A community WoW Forever DR addon reports using Blizzard's built-in `C_SpellDiminish` system after enabling `spellDiminishPVPEnemiesEnabled`, but our prior `nativeDREvents=0` log does not establish whether the native feed is available on this client. This test adds an **explicit opt-in probe**:

- `/bcc native status` — reports `C_SpellDiminish.IsSystemSupported()`, the native `spellDiminishPVPEnemiesEnabled` CVar, native-event validity if inspectable, native event counts/readable category/secret payload counts, and your own Bash/Iron Grenade/War Stomp cast event counts.
- `/bcc native on` — only out of combat and only when `IsSystemSupported()` returns true, requests native DR CVar `1`, then rereads it. This changes a **client-global Blizzard option**, not just this addon. It is **never enabled automatically**.
- `/bcc native off` — out of combat, returns the same CVar to `0`. Since it is a client CVar, it may persist through reloads unless manually reverted.
- `/bcc status` — also shows the last **separately readable** native tracker fields (category number, start time, duration, showCountdown, isImmune) with unreadable fields explicitly shown as unknown, plus the last readable own Bash/Grenade/Stomp cast event. An event is *never* promoted to a confirmed stun or an observed DR count on its own.

**Fast live protocol:** Install, run `/bcc native status`. If `supported=true`, leave combat and run `/bcc native on`; make a targeted/focused opponent cast/receive Bash or Iron Grenade; run `/bcc native status`, then copy `/bcc status` during the CC if possible. If `nativeDREvents` increments but payload is restricted, the event exists but still does not authorize a caster-side stage. If `supported=false`, do not keep debugging the native feed: it is not supported through this API on this client. Finally, run `/bcc native off` if you do not want the native Blizzard option left enabled.

**No automatic DR breakthrough claimed:** This changes diagnostics and a controlled native UI setting only. It does not decode protected native events, bypass secret aura restrictions, conflate item use with a victim-specific hit, rewrite stage timers, add visual clutter, or change the 2×2 DR grid. The 0.4.17.4 experimental enemy cooldown opt-in remains.


## 0.4.17.4: Experimental enemy cooldown bar opt-in

The three "Enemy cooldowns (test)" icons shown by `/bcc test` are **synthetic Paladin/Rogue/Mage examples**, not evidence of live enemy casts. Earlier caster reports recorded `acceptedCasts=0`; there is still **no verified automatic enemy cooldown feed on Forever**. A live timer is created only after a readable enemy `UNIT_SPELLCAST_SUCCEEDED` event satisfies identity/hostility requirements (or `/bcc used <spellID>` is manually invoked). Cast START alone does not start a timer.

- **Cooldown bar defaults OFF**, without disabling any player/target/focus DR displays. Use `/bcc cooldowns on` to opt in, `/bcc cooldowns off` to hide, or `/bcc` → Display → **Enemy CDs (beta)**. The feature stays experimental and can still miss real enemy casts.
- The default position moves from **screen center (0,-280)**, which overlaps the user's Healing Touch cast bar, to **(0,-170)**. One-time schema 8 migration updates that old untouched default and disables an uncustomized legacy default-on bar. Explicitly customized/dragged positions and nondefault appearance/enable choices are preserved. The cooldown bar remains independently draggable when enabled and unlocked.
- When enabled, `/bcc test` titles the three fake examples **Enemy cooldowns (SAMPLE)** and explains the simulation on hover. Turning preview off returns to actual observations. The settings panel and tooltips explicitly warn of the unverified enemy event feed.
- `/bcc status` identifies whether the experimental cooldown HUD is enabled and already reports `castStartsOther`, `castSuccessOther`, `acceptedCasts`, and `castReject.*` counters. These allow diagnosis of absent events versus rejected readable events.
- **No change** to stun/root observation, War Stomp/Iron Grenade probes, the 2×2 DR grids, stage colors, application or reset clocks, manual cooldown marks, or the actual enemy cooldown model. This is a presentation/default-policy correction, not an invented fix for inaccessible enemy casts.

For live verification, disable preview, opt in only if you want to test automatic enemy tracking, and copy `/bcc status` immediately after a known enemy ability. If `castSuccessOther=0`, the addon has not seen a usable successful enemy cast event; if successful events arrive but `acceptedCasts=0`, inspect the rejection reasons.


## 0.4.17.3 AoE caster-witness test (still requires in-game verification)

**Reported:** War Stomp and Iron Grenade do not advance caster-side stun DR reliably despite visible hits on the opponent.

The 0.4.17.2 evidence-first baseline already checked exact War Stomp aura 20549, with previous live trials returning no readable positive on the caster. It did **not** explicitly query Iron Grenade's harmful stun effect 4068. This update adds an exact 4068 query whenever target/focus indexed harmful-aura enumeration is incomplete. Only a readable matching spell **and real aura instance** advances observed DR; nil, secret, mismatched, expired or missing-ID results prove neither a hit nor a removal.

`UNIT_AURA` now has a separate, **positive-only** path for readable `updateInfo.addedAuras` containing harmful spell 20549/4068 with a valid instance. This can retain a very short hit when a subsequent indexed snapshot loses access. It does **not** process arbitrary event data, use expired events, trust friendly auras or infer that a cast landed. If the event's payload is secret, it is ignored and logged as restricted. A positive event conflicting with an empty complete scan preserves the hit while marking coverage incomplete. The native `UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED` event is **diagnostics only**: its secret payload is never decoded into a category/stage/hit.

`/bcc status` exposes `lookup20549`, `grenadeLookup`, `auraEventCalls`, `auraEventRestricted`, `auraEventPositives`, `auraEventConflicts`, `nativeDREvents`, `nativeDRRestricted`, and `nativeDRReadable`. Capture status **while War Stomp or Iron Grenade is active on a selected opponent**, preferably also focusing them. Have the recipient capture the same duel to distinguish actual hits from unreadable caster evidence.

**Evidence ceiling:** WoW Forever marks `UNIT_AURA` updates secret when auras are restricted; `GetUnitAuraBySpellID` may return nil for a secret aura. Therefore this change is not a guarantee of automatic caster-side tracking during restricted duels. Neither area cast is allowed to guess the victim. The native DR event cannot safely be used to infer a stun category from a secret tracker. If all three positive paths fail, a correct confirmed DR stage cannot be reconstructed from permitted addon data alone. Defaults, timers, display and persistent settings remain unchanged.


## 0.4.17.2: evidence-first test candidate (not yet live verified)

This build retains the original 0.4.17 side-grid artwork, colors, controls, application clock (20s), separate provisional stage retention (18s), own-cast setting default, and SavedVariables schema. It is **not** a demonstrated fix for every restricted combat event. A GitHub Actions Lua test workflow builds an installable candidate ZIP after tests pass.

Changes informed by bjarkiPortraits' evidence discipline:
- When a Target aura list is restricted and Focus is the **same readable player GUID**, probe Focus before declaring the observation incomplete. A complete alias becomes the authoritative snapshot; otherwise merge only positive aura-instance records. A missing or secret alias is not a removal.
- Pending, reviewed **own direct casts** can select a bounded exact-aura lookup for that spell when enumeration is restricted. This is only a query selector: the cast still never advances observed DR without a readable matching positive aura instance. Area War Stomp and Nature's Grasp retain their preexisting, separate confirmation probes.
- A readable Player GUID remains a valid identity witness if UnitIsPlayer is unavailable, while an explicit contradictory result vetoes it. A readable hostile GUID can begin an observed cooldown even if UnitName is temporarily unavailable (the display may initially use a GUID).
- `/bcc status` now separates cast-start delivery, successful event delivery, validation rejections, **actually accepted** cooldown records, alias coverage and exact lookup outcomes. Cast START is diagnostic only and does not create a cooldown.
- Native cooldown swipes keep their original start/duration between render ticks; stable HUD geometry is not needlessly reanchored and resized.

**Live checks needed:** incoming/outgoing CC with Target and Focus on the same enemy; compare complete/partial alias coverage; cast Hibernate or Entangling Roots through an indexed-aura restriction and check `castLookup`; repeat War Stomp and Nature's Grasp; note whether enemy cast START and SUCCEEDED events actually arrive. Check `/bcc status` during an active effect. The direct lookup cannot bypass secret data, and enemy cooldown tracking remains conditional on readable events.


## 0.4.17.1: Nature's Grasp confirmation fallback

This narrow patch keeps the 0.4.17 artwork, layout, timers and saved-setting policy. When target/focus indexed aura scanning is restricted, it also checks the six known Nature's Grasp root-effect IDs through the same guarded exact-spell API used for War Stomp. Only a readable matching spell and aura instance can add a root application; activating the self-buff never assigns a victim.

The supplied caster report first saw root 19975 at 2672672.095, despite its application time being 2672665.719: 6.376 seconds late. The mapping worked, but indexed access was blocked initially. The fallback can recover an individually readable root when enumeration fails; it cannot read a root whose own data is restricted. Live availability of this alternate source is unverified. `/bcc status` records its outcome as `graspLookup`.

## Current baseline: 0.4.17 rollback

The original 0.4.17-beta is the baseline for the narrow observation patch above. Newer SavedVariables can survive reinstalling it and change its behavior. See [RECOVERY.md](RECOVERY.md) for the verified two-setting recovery and remaining limitations. This rollback does not establish reliable live DR tracking; direct-cast false positives, caster-side War Stomp and enemy cooldown coverage remain unresolved.

The version sections below describe historical changes; the current layout is the 0.4.17 side grid.

Compact icons show player, target and focus diminishing returns, plus observed enemy crowd-control cooldown estimates. Each DR bar follows its matching unit frame. The look follows old InterruptBar and Diminish: small square icons, centered timers and colored DR borders. Hammer of Justice, Kidney Shot, Frost Nova, traps and other CC families are included; interrupts can be enabled separately.

Version **0.4.17-beta** targets **1.60.1.70425**, interface **16001**. All nine offline Lua suites pass; revised behavior still needs an in-game check. Protected enemy data can prevent confirmed target/focus DR or cooldown tracking on this beta.

## Unit-frame side grids in 0.4.17

DR trackers now use a fixed two-row, two-column layout beside the unit frames, inspired by target-of-target debuffs. Player DR sits outside the left portrait edge; target and focus DR sit outside the right edge. An 18-pixel gap leaves room for the PvP badge. Icons fill the first row away from the frame, then the second row below. At most four icons appear, with no extra overflow label. Other active categories remain in the model and diagnostics.

Upgrade moves all three DR bars once; subsequent drag offsets persist. Existing icon size, gap, filters and enemy cooldown settings survive. DR countdown text still appears only at five seconds and below. `/bcc test` previews all four grid positions, and `/bcc unlock` allows moving the grids outside combat.

## Portrait columns and final-five-second numbers in 0.4.16

Player, target and focus DR icons now start centered eight pixels above their portraits. Additional categories stack vertically upward, leaving the first icon fixed as the column grows. Upgrade applies this requested layout to all three DR bars once; later dragging and layout choices remain saved. Sizes, gaps, category filters, tracking settings and the enemy cooldown bar's placement are preserved.

DR icons, stage borders and cooldown sweeps still appear from application. Countdown numbers remain blank above five seconds, show `5` at exactly five, then use one decimal below five. This changes presentation only; both underlying clocks and expiry behavior remain in place. Enemy cooldown numbers retain their normal full countdown. Use `/bcc test` to preview and `/bcc unlock` outside combat to adjust the portrait offsets.

## Exact War Stomp confirmation in 0.4.15

The new caster report identifies the failed source: `GetAuraDataByIndex` raises an aura-access restriction. The existing per-unit Loss of Control fallback adds no mapped hit in the captured trace. This explains why a recipient can track its own stun while the caster has no confirmed application; the report does not establish whether another documented source is readable during War Stomp.

When target/focus aura enumeration is incomplete, the addon now also queries the documented `GetUnitAuraBySpellID(unit, 20549)` non-secret-aura endpoint. A positive must contain readable matching War Stomp and aura-instance IDs. It then advances stun DR with the normal aura path. Hidden, mismatched, expired, failed or empty results cannot invent a hit; empty results cannot prove removal or complete coverage. This is one bounded lookup per tracked victim per scan, with target/focus aliases shared. War Stomp cast events still do not estimate a victim.

`/bcc status` retains lookup outcomes and per-unit LoC counts in the recent observation history, including after the stun ends. No `/run` probes are required. The first supplied 0.4.15 live caster report shows the fallback running but returning no aura, with zero ByUnit LoC records and blocked indexed scanning. Offensive War Stomp confirmation still fails in that reported trial; passing offline fallback/rejection tests does not establish live coverage. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for the captured result and its limits. Cast-only War Stomp estimates remain excluded by request.

## Confirmed War Stomp and API diagnostics in 0.4.14

War Stomp advances stun DR only when readable aura or Loss of Control data confirms an application. Its area cast cannot identify the victim, so it remains excluded from own-cast estimates, as requested. Bash retains its existing optional direct-cast estimate. A visible recipient icon does not establish that the casting client's APIs expose the same hit.

The supplied caster report records one Bash estimate and no confirmed stun application, alongside 470 unattributed API errors. This release adds bounded error details to `/bcc status`: operation, count, last unit token and first/latest readable error messages. Secret and non-string error values are never formatted. `/bcc clear` resets these details along with tracking history. This is a diagnostic update; it does not yet fix or establish the cause of the missing offensive War Stomp observation.

For the next check, reload this build, use `/bcc clear` before a fresh test, then Bash followed by War Stomp. Copy `/bcc status` from the casting client while the stun is active or immediately afterward. The report will identify failing API operations while preserving confirmed-hit tracking, the two clocks and existing visuals.

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
- Each uses the visible outer portrait edge for placement, with native-frame fallback, in a fixed 2 x 2 grid beside it. Use `/bcc unlock` outside combat and drag the icons to adjust the offset; `/bcc lock` saves the layout from accidental movement. Offsets persist across reloads.
- Moving the native unit frame also moves its DR bar. Bars disappear with hidden unit frames during live play; preview/unlock still shows setup handles.
- The experimental enemy cooldown bar is disabled by default, independently movable if enabled, and does not follow cast-bar geometry automatically.
- Target and focus share one observation history when they refer to the same player. Switching targets preserves the old target's DR if that player remains focused.

Upgrading initializes frame-relative DR offsets once, preserving size, filters and the cooldown bar's position. `/bcc reset` restores the default offsets. The anchors use Blizzard's named unit frames, including addons that reposition those frames. Replacement unit-frame addons with different frame names are not automatically detected. If a native frame is missing, a setup-only handle appears at the old screen position; its live DR bar stays hidden until the native frame exists.

## Minimal display

- DR icons default to 28px; cooldown icons to 32px, with 3px spacing.
- Live bars have no headings, category captions, backgrounds or empty-state messages.
- DR numbers appear only at five seconds remaining or below, with decimals below five. Enemy cooldowns retain whole seconds or compact minutes for long timers.
- DR stages use colored borders. Percentage text and caster names are optional in Display settings.
- DR uncertainty is explained on hover. Cooldown `?` marks the uncertain talent range; `M` identifies a manually marked use.
- Empty bars disappear when locked. Labels appear only in preview or while moving bars.

Previous default sizes and spacing migrate once to the compact defaults. Diagnostics remain available through `/bcc status`.

## Install

1. Exit WoW and extract the ZIP into `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. The resulting file must be `Interface/AddOns/bjarkiCC/bjarkiCC.toc`, with no extra nested folder.
3. Start the beta, enable **bjarkiCC (Forever)** in AddOns and log in.
4. Select a target and set a focus so both frames are visible. Outside combat, run `/bcc test`, then `/bcc unlock`. Drag the three DR grids beside their frames. The experimental enemy cooldown bar is hidden by default; use `/bcc cooldowns on` only if you want to test it, then drag it well clear of your cast bar.
5. Run `/bcc lock`, then `/bcc test` again to return to live observation.

The package includes all Lua source; no other addon or library is required. Installation does not replace bjarkiUI or bjarkiPortraits.

## Controls

| Command | Action |
| --- | --- |
| `/bcc` | Open settings: bars, DR categories, cooldown filters |
| `/bcc test` | Toggle synthetic preview icons (never proof of live tracking) |
| `/bcc unlock` / `/bcc lock` | Adjust DR offsets and cooldown position outside combat, or lock bars |
| `/bcc reset` | Restore default frame offsets and cooldown position; preserve other settings |
| `/bcc clear` | Clear observation history and restart the sensors |
| `/bcc status` | Open a copyable build/API diagnostic report |
| `/bcc cooldowns on` / `off` | Opt into or hide the experimental enemy cooldown bar |
| `/bcc cooldowns status` | Check the experimental bar's current visibility setting |
| `/bcc cooldown 853 45` | Use a 45-second HoJ estimate for future observations |
| `/bcc cooldown 853 default` | Restore HoJ's default estimate range |
| `/bcc used 853` | Manually mark HoJ used by the selected hostile player |

The Display panel has enable and size controls for each bar, a fixed 2 x 2 label for DR grids, and a vertical-layout control for enemy cooldowns, plus optional caster names and DR percentages. The cooldown panel offers a current-target filter, optional interrupts, and individual ability toggles. Positions and preferences are saved account-wide. Live combat history and test mode are not saved. Anchor changes made in combat apply after combat; combat starting during a drag restores the previously saved offset.

## Read the bars

DR borders show the tracked cycle: **green = first**, **yellow = second**, **red = third**. In the baseline profile these correspond to a next duration of **50%**, **25%**, and **immune**. Optional percentage text appears only when history is considered complete; hover to see whether the count is observed, cast-inferred or corrected by matching full-duration evidence. The countdown starts on application, including while CC remains active. New applications refresh it; an early break or removal does not change its start. Icons hide when the application countdown ends or the stage resets, whichever comes first. Stage history can remain internally after the icon hides; its separate reset estimate is available in `/bcc status` and on hover while the icon is visible. The display has no DR question-mark badge.

The default profile uses nine Classic categories, the requested 20-second countdown from the last observed application, and an independently configurable stage reset window, defaulting to 18 seconds after CC ends. Its category and timing assumptions remain provisional for Forever. Own-cast estimates instead start at cast success, approximating an application that may be hidden or may never land; they always remain uncertain. Initial login, a newly observed player, unavailable data, and a scan gap longer than one second invalidate observed history. A full observation window is needed before new applications can be assigned confident stages. History remains continuous while the same player stays observable through player, target or focus, including target/focus swaps. Losing the last tracked reference discards that player's observed DR history. Recorded enemy cooldowns remain independent of target/focus changes.

Cooldown icons show the remaining configured estimate. Caster names appear on hover, or beneath the icons when enabled. Identical spell icons can belong to different enemies. For talent ranges such as HoJ's 45–60 seconds, the main timer counts toward 60; **?** appears once the 45-second estimate has elapsed. Hover for the shorter estimate. These ranges do not cover every item, beta change or unobserved reset. **M** marks a manual entry. Expired icons disappear; absence does not mean confirmed readiness. A small `+N` indicates additional timers beyond the bar's icon limit.

Spammable abilities such as Polymorph contribute to the DR map without receiving an invented cooldown. Shared shocks use one cooldown icon. Blind and Death Coil have cooldown icons but no DR entry in the selected Classic profile.

## Beta observation limits

Forever restricts combat-log access, so bjarkiCC never registers combat-log events. It uses readable harmful aura snapshots, guarded player/per-unit Loss of Control APIs when needed, and readable unit-cast events. It does not recover or branch on protected values.

Own-cast estimates correlate the intended name at cast-send time with a visible player target/focus, then require matching successful cast and spell identifiers. Switching target after sending cannot redirect that estimate. Failed/interrupted casts are discarded; area effects, traps, procs and pet orders are excluded. Same-name ambiguity between target and focus is rejected, but a different same-name mouseover/outside unit cannot be ruled out because the event supplies a name, not a victim GUID. Resistance and immunity can still leave a false-positive estimate. This fallback cannot reconstruct other players' hidden CC.

An automatically observed enemy timer requires a readable successful enemy spellcast event, a tracked spell ID, confirmed hostile unit identity and a valid cooldown rule; the caster name is optional. Off-screen enemies, secret casts and unobserved resets can be missed. The experimental cooldown bar is OFF until enabled; no visible timer is never proof of readiness. Player pets are tracked under their own identity. The target-only filter does not attribute a pet's cooldown to its owner. Hidden empty bars do not mean the data is available; check `/bcc status` if expected icons never appear.

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
