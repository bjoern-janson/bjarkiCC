# bjarkiCC known issues and validation status

## Current report: second full/half/quarter sequence remains red (0.4.9)

**Report and evidence:** the recipient's first sequence `a:421/423/425` supplies explicit durations 20/10/5 and stages 1/2/3. After `a:425` disappears at 2659065.120, `a:427` supplies a full 20-second duration at start 2659080.750, 15.630 seconds later, but retains stage three. The subsequent `a:429` (10 seconds) and `a:431` (5 seconds) also remain three. There are no scan gaps or own-cast estimates in the report. The expected color sequence is green/yellow/red for full/half/quarter; red on the third successful application indicates the next application is expected to be immune.

**Diagnosed cause:** the first `a:421` is observed through readable aura data, then through complete LoC data with the same exact ID. Observer nevertheless injects an incomplete model observation for the source switch. This increments the duration-evidence epoch and clears its quiet coverage. Later explicit duration 20 is readable, but the first application's captured context has the previous epoch, so no baseline is learned. The earlier integration fixture selected LoC before the quiet interval and therefore omitted this live transition.

**Correction in 0.4.10:** preserve previously established quiet context only across a complete player aura-to-LoC handoff with identical nonempty real aura-ID, spell and category sets and readable prior aura timing. Reconciliation/capacity checks happen before this decision. Empty, changed, missing, additional or ambiguous witnesses, restricted data and reverse switches still invalidate coverage. Earlier scan-gap invalidation cannot be undone. Initial aura-derived duration may veto conflicting later raw-duration baseline learning, but never supplies a full-duration baseline itself.

**Validation scope:** the exact `a:421` through `a:431` event replay fails in 0.4.9 at the second full application's explicit duration. The corrected replay must show 1/2/3 for the second sequence across player, target and focus, retain application clocks, and expose correction provenance. Boundary tests retain genuine gap/partial/identity invalidation and reject contradictory aura-to-LoC duration evidence. Live validation remains pending; the one API-error counter has no accompanying error message and is not diagnosed.

## Previous report: full-duration red Hibernate after an immune attempt (0.4.7)

**Report and evidence:** the user reproduced the problem by trying Hibernate while immune, then supplied a second 0.4.7 trace. The trace records a coherent 1/2/3 sequence ending with quarter-duration `a:403` at 2657965.000, followed by a full 20-second `a:405` starting at 2657980.500. That is 15.500 seconds after the model's accepted prior end, or 15.430 after the removal scan. The full application initially has an unknown start, then readable explicit timing. It is not an earlier duplicate-count case. The 152 API errors are counters without messages; their cause is not diagnosed.

**Reproduced cause:** fixed 20-second and 18-second post-CC windows both retain stage three for this application. The report does not capture an immune attempt moving a deadline, and no own-cast estimates were recorded. Injected unconfirmed attempts at stage three are rejected and preserve both clocks. The new landed application, rather than an observed immune result, is the logged point where the application countdown restarts. The 0.4.8 reset adjustment is therefore insufficient for this second sequence.

**Correction in 0.4.9:** retain the configured clocks and reconcile stale history only from matching, separately guarded full-duration LoC evidence. A per-victim, exact-spell baseline requires a preceding 20-second completely observed quiet interval; an eligible new application after at least 15 seconds of observed category absence following the prior end can reset to stage one when its first explicit duration matches. A late removal scan cannot backdate that absence. Missing/secret duration, remaining-only expiry, overlap, short gaps, other spells/victims, observation gaps and cast-only events cannot establish this correction. Corrected rows remain uncertain and identify their reason in tooltip/status. No half/quarter duration-ratio guessing or universal 15-second reset is added.

**Validation scope:** model, adapter and event-to-UI regressions cover the reported sequence, first-readable calibration, subsequent progression, protected duration fields, baseline eligibility/invalidation, clock preservation and immune-attempt rejection. The old status did not report raw duration separately, so the regression supplies explicit LoC duration consistent with its recorded boundaries; the updated diagnostic field still needs live validation. 0.4.9 live retesting remains pending.

## Previous report: lingering icons and full-duration red Hibernate in 0.4.7

**Evidence:** the installed addon and supplied recipient status are 0.4.7-beta. The user reports icons remaining after the countdown and a full-duration Hibernate while the icon is red. The trace records no own-cast estimates or scan gaps. Its two complete full/half/quarter sequences each count once per application; first-readable timing corrections do not duplicate them.

**Diagnosed reset mismatch:** quarter-duration `a:383` disappears at 2657449.235, earlier than its predicted expiry 2657449.500. The new `a:385` starts at 2657467.250 and ends at 2657487.250, a full 20-second interval landing 18.015 seconds after observed removal. The 0.4.7 model retains stage three until 2657469.235 because it uses 20 seconds after removal. Replaying the supplied sequence reproduces the red stage without an additional event-counting defect.

**Correction in 0.4.8:** separate the saved stage-reset setting from the application countdown and default it to a provisional 18 seconds. The same replay resets the earlier stage at 2657467.235 and displays the new application green. Existing application countdown preferences remain unchanged (default 20 seconds); either value is independently configurable. The UI hides expired countdown rows before layout/overflow counting while preserving model history for subsequent applications and status. A stage that resets before its countdown finishes also hides, avoiding a stale color.

**Claim limit:** the 18-second setting fits that captured application by only 15 milliseconds. That observation does not prove Forever has an exact fixed 18-second server reset. Predicted expiry and observed disappearance differ, and other categories or future beta builds may differ. Version 0.4.8 did not use duration to correct stage history; the later correction is described above. Unknown ends, incomplete coverage, resisted cast estimates and unseen applications retain their documented uncertainty.

**Validation:** exact trace replay, independent reset boundaries/settings, legacy preference migration, quiet-observation confidence, hidden-history progression, shared player/target/focus display and icon overflow have offline regression coverage. The later 0.4.7 report above demonstrates a sequence that still fails with the 0.4.8 reset default; live validation of the revised correction remains pending.

## Previous report: immune-stage Hibernate still shows yellow in 0.4.6

The installed client and report are 0.4.6-beta. The user reports being at full DR while the screenshot shows a yellow icon with two seconds left. The supplied recipient trace starts with no visible DR row, then shows `a:349` at start 2656289.250/end 2656299.250 counted once as stage one, and `a:351` at start 2656299.250/end 2656304.250 counted once as stage two. Their initial unknown starts are calibrated without an extra increment. No own-cast estimates or scan gaps are reported. Thus these entries do not reproduce the earlier duplicate-count bugs.

**Diagnosed policy limitation:** the old model used the same application-plus-20 boundary both to finish the countdown and to discard stage continuity. A full 20-second Hibernate followed at 22 seconds therefore reset the addon to stage one, even though a post-CC reset model would retain the earlier stage. This reproduces a one-stage undercount for a full/half/quarter sequence. The eight-entry live excerpt omits the preceding full application, so those hypothetical preceding times are not asserted as the exact live cause. The observed 10- and 5-second intervals alone are not used to infer a server DR stage.

**Explicit user decision:** keep the 20-second application countdown and track DR stage reset separately. Version 0.4.7 retains observed stage history through CC and the configured interval after its end. Early breaks alter the stage deadline without restarting the application clock. That release kept the colored stage icon visible without a number or sweep after the application countdown; 0.4.8 removes this lingering display. Its separate estimated deadline and observed-disappearance versus predicted-expiry basis appear in the tooltip/status. That release used 20 seconds after CC as a provisional Classic baseline, superseded by the independent 18-second estimate in 0.4.8; Forever's exact reset rule remains unverified.

**Coverage limits:** complete disappearance can record an observed end; partial absence cannot. Readable expiration can bound the stage window as a prediction when removal is unavailable. An active effect with no readable end keeps an uncertain stage pending rather than fabricating readiness. Cast-only predictions still expire at their application deadline because they do not establish a landed CC or its end. Missing earlier observations can still undercount stages.

**Validation:** replay tests cover a full/half/quarter chain across the old application boundary, early breaks, overlapping effects, partial observations, unknown ends, stale records and immunity attempts. Main-to-UI tests check all three frames, retained colored icons after the application number ends and disappearance at the separate stage deadline. Status now includes the latest 24 changes instead of eight to retain more preceding evidence. The subsequent 0.4.7 report above demonstrates continuous stage progression but exposes the longer reset-window mismatch and undesired lingering icons.

## Previous report: half-duration Hibernate shows final-stage red in 0.4.5

The user supplied a screenshot and recipient status from installed 0.4.5-beta: half-duration Hibernate displays red, with observed stage three shared by player, target and focus. There are no own-cast estimates or scan gaps. The same aura instance `a:325` appears throughout:

| Observation time | Timing source | Start | Observed stage in 0.4.5 |
| --- | --- | --- | --- |
| 2655626.973 | aura | 2655626.973 | 1 |
| 2655626.973 | LoC | unknown | 1 |
| 2655627.270 | LoC | 2655627.250 | 2, duplicate |
| 2655637.512 | LoC | unknown | 2 |
| 2655637.765 | LoC | 2655637.750 | 3, should be 2 |
| 2655647.495 | removal | no effect | 3 retained until the application deadline |

**Diagnosed cause:** 0.4.5 handled untimed-to-timed observations but still treated a first explicit LoC start later than an aura-derived start/first-seen time as another CC. The first Hibernate was therefore counted twice before the real second application arrived. This is an observed-source bookkeeping error, independent of the cast-estimate fallback and the user's application-based timer choice.

**Source correction in 0.4.6:** calibrate the same application's first explicit LoC clock across the source handoff, then compare subsequent explicit timestamps against that baseline. Retain known LoC timing through lower-quality aura samples or stale explicit timestamps so source reversals cannot poison the comparison. The sequence now stays stage one at 2655627.250 and advances once to stage two at 2655637.750. No latency threshold is introduced. A genuinely new identity still counts; known LoC-to-LoC and pre-LoC aura-to-aura refreshes remain supported.

**Evidence limit:** a same-ID reapplication hidden before the first explicit LoC timestamp cannot be distinguished from calibration using these snapshots alone. After explicit LoC timing is known, an aura-only timing change on the same identity is conservatively withheld until a newer LoC start or new identity is observed. Ambiguous data remains uncertain.

**Validation:** the exact trace fails against 0.4.5 through real Main events, Observer, Model and UI. The correction is checked against the same sequence, including green/yellow borders, timer/sweep alignment, shared player/target/focus state and removal without a timer restart. Additional regressions cover reverse handoffs and stale timestamps. The later 0.4.6 live excerpt above shows no duplicate in its listed steps, but does not exercise the original aura-to-LoC handoff; live validation of that specific sequence remains pending.

## Previous report: Hibernate stays out of sync on the next attempt

The user reports a possibly resisted Hibernate followed by a full application showing yellow, then supplies a 0.4.4 recipient trace from the next attempt that remained out of sync. The trace has no own-cast estimates and identifies a concrete duplicate count of each same-instance application:

| Observation time | Aura | Readable start | Observed stage in 0.4.4 |
| --- | --- | --- | --- |
| 2655121.649 | `a:315`, Hibernate 2637 | unknown | 1 |
| 2655121.778 | `a:315`, Hibernate 2637 | 2655121.750 | 2, duplicate |
| 2655176.779 | `a:317`, Hibernate 2637 | 2655176.750 | 1 |
| 2655186.838 | `a:319`, Hibernate 2637 | unknown | 2 |
| 2655187.034 | `a:319`, Hibernate 2637 | 2655187.000 | 3, duplicate |

**Diagnosed cause:** the refresh detector compared a first readable application timestamp with the earlier local first-seen fallback. When the timestamp became available 0.101 or 0.162 seconds after that fallback, it was counted as a new CC. The correction branch also rejected such later timestamps. Shared player/target/focus views expose the same GUID's count; they are not three independent applications. This evidence establishes duplicate counting, not that the possible resisted attempt was counted.

**Source correction in 0.4.5:** first readable timing for the same untimed identity calibrates the existing application. A same-identity refresh requires an already known earlier application timestamp. No arbitrary grace period is added. The recorded `a:315` stays stage one, `a:319` stays stage two, and genuine later applications can still advance. The application-only 20-second policy and removal behavior remain unchanged.

**Validation:** exact normalized traces fail against 0.4.4 and pass against the correction, including retained witnesses after an empty snapshot. A real Observer-to-Model fixture also reproduces the trace across all three shared views by providing a briefly future LoC timestamp; the future-time guard stays intact. The raw reason for the live timestamp's initial unavailability was not captured. The subsequent 0.4.5 live report above exposes a separate aura-to-LoC timing path that the untimed-only fix did not cover. The earlier outgoing green-on-reduced report remains separate and unresolved.

## Previous report: final-stage timer restarts on further casts

The user supplied an older-version screenshot and reports that attempts at full DR refresh the timer, obscuring when it drops. The same source defect remains in 0.4.3: `EstimateDR` caps the stage at three but unconditionally sets `appliedAt` to each new successful-cast event's time. That event confirms a cast, not a landed CC, so immune attempts can indefinitely postpone the displayed deadline.

Version 0.4.4 rejects further own-cast estimates while the selected unexpired category is already at its final displayed stage. It preserves the third application's timer, still permits progression from stage two to three and a fresh cycle after expiry, and retains cast deduplication. Readable new application evidence can still update state; the entire observation path is not frozen because an inferred red stage may be wrong. The regression reproduces repeated cast attempts moving the red countdown, and checks that both target/focus countdown numbers and sweeps retain the original deadline. Live retesting remains pending; this does not establish Forever's exact server reset time.

## Open earlier report: 0.4.2 Hibernate cycles

The user reports reduced outgoing Hibernate showing the first-cycle green border, full incoming Hibernate showing the second-cycle yellow border, and unnecessary DR question marks. The installed TOC is 0.4.2-beta. Live `/bcc status` during incoming Hibernate shows player LoC with one mapped witness, observed stage two at start 2654073.250, no own-cast estimates, and no scan gaps. Target/focus show the same player GUID's history. This rules out the own-cast overlay for that incoming yellow icon, but does not reveal the prior observation transition.

Two duplicate-count paths were reproduced through the real observer/model: a fallback LoC start changing from 21 to 21.0001 produced a new key and another stage, and a complete empty snapshot followed by the identical application also advanced the count. Version 0.4.3 stabilizes fallback identity within the existing 0.001-second tolerance and retains one bounded witness with category history. Tests cover each path and their combination, a real later start, distinct aura IDs and unchanged polls. Their relevance to the exact live incident remains unconfirmed.

**The reduced outgoing Hibernate case remains open.** The user is unsure whether the previous application was less or more than 20 seconds earlier. The policy at that release reset the stage after 20 seconds from application; a full 20-second CC followed by another at 21 seconds therefore displayed stage one even if the game still diminished it. That policy consequence is reproduced, but it is not established as the screenshot's cause. Version 0.4.3 added bounded recent witness/stage transitions in `/bcc status` without changing timer semantics or inferring server stages from remaining portrait seconds. Version 0.4.7 supersedes the application-only stage boundary with separate post-CC stage retention as described above.

DR question marks are removed in 0.4.3. Incomplete or inferred evidence is still described in tooltips and status; uncertain rows omit optional percentages. Cooldown readiness markers and manual-use markers are unchanged. Live confirmation of the duplicate-count corrections remains pending.

## Previous report: 0.4.1

The user reports that the first offensive application still has no DR timer and a later screenshot shows stage one on the second CC. The live status report records `ownCast.captured: 0`, `ownCast.unresolved: 7`, and zero mapped target/focus aura or per-unit LoC witnesses. Readable UnitName fields were `Björn`, `Janson`; the actual SENT destination was `Björn Janson`. The resolver accepted only the bare name or `Björn-Janson`. This exact mismatch is reproduced and corrected in 0.4.2 by adding an exact space-qualified alias built from readable fields. Same-GUID aliases now share readable names, while distinct ambiguity remains rejected.

Two separate source undercounts were reproduced: confirming only the second of two own-cast estimates discarded the inferred first stage; and a late readable second application lost its predecessor when the old display timer had expired. Version 0.4.2 preserves inferred stages separately from observed counts and retains bounded category history for application-time ordering. The screenshot alone does not establish which stage-loss path occurred in that duel. These are tested source corrections, not an in-game validation result. That release kept the chosen 20-second application-only timer, including its stage-one restart at or beyond that boundary. Version 0.4.7 keeps the display countdown but supersedes that stage boundary with separate post-CC retention.

The report also includes 165 API-call errors without their messages. That counter is not enough to identify an additional failure or attribute it to the earlier Backdrop error. The fixed backdrop path remains covered by its regression. Live retesting of offensive detection and consecutive stages is still pending.

## Previous report: 0.4.0

The user reports an outgoing timer appearing about nine seconds late with a white border, a DR countdown one second above the portrait countdown, and many errors after receiving CC. On a later attempt the error warning did not recur, but borders remained white and consecutive DR did not refresh.

The client General.log contains 1,632 entries of the same Lua error: `Backdrop.lua:226: attempt to perform arithmetic on local 'width' (a secret number value, while execution tainted by 'bjarkiCC')`, followed by `SetupTextureCoordinates` and the size callback at line 191. The repeated entries occur at the addon's 0.1-second render cadence. The installed UI.lua matched the released source byte-for-byte. The user's subsequent error at 00:54:10 (Count 398) includes locals identifying `self=Frame <UI.lua:93>`, the icon created with `BackdropTemplate`, and secret width/height. This confirms the exact offending icon/template path; it does not establish that every reported symptom shares that cause.

Source inspection also confirms that application timestamps were discarded, uncertainty deliberately made borders gray, countdown text rounded up rather than using the portrait's nearest-second convention, and same-identity timing extensions did not advance a stage. Version 0.4.1 addresses those paths with timestamp preservation, supported refresh detection, colored borders plus a separate `?`, matching text rounding, and solid textures on anchored frames. Live retesting remains required. The exact reason the outgoing source was unavailable for the first nine seconds is not yet captured.

## Earlier reports

The earlier report was that receiving CC starts DR but applying CC does not, with portrait-adjacent icons poorly placed. Version 0.3.1's observer had a player LoC fallback but depended on harmful aura reads for target/focus. Native portrait CC artwork does not prove those aura IDs are readable by Lua. That asymmetry is a diagnosed source limitation.

Version 0.4.0 adds guarded per-unit LoC witnesses and optional own-cast estimates, always marked `?`, plus health-region anchors above the name area. It retains the explicitly requested application-based display timer even though the researched Classic reset convention differs. Offline regressions pass. Outgoing detection, revised visual alignment, and Forever server mechanics still require live validation; this is not a claim that every enemy CC is now observable.

## Open limitations

| Condition | Consequence | Status |
| --- | --- | --- |
| Beta hides enemy spell/identity/aura fields | Automatic target/focus DR or enemy cooldown tracking may be unavailable | Supported failure mode; live coverage unverified |
| Successful own cast is resisted, immune, delayed or sent to another same-name unit | Stage-colored estimate can appear without an actual application | Optional fallback; hover shows uncertainty; cast success is not a hit guarantee |
| Application event and its timestamp are both hidden | The display can start late; a correct earlier deadline cannot be recovered without evidence | Readable timing corrects late observations; no claim of universally immediate detection |
| Own cast lacks a readable cast ID/name or targets an area/trap/pet effect | No own-cast fallback appears | Deliberately excluded; target/focus name matching is not global victim identification |
| Per-unit LoC API exists but returns secret, incomplete or no records | Target/focus fallback may add no usable witnesses | Only readable positives accepted; incomplete aura coverage stays uncertain |
| Classic categories and requested application-based timer | Estimated stages/timing can differ from Forever server rules | Requires duel validation |
| LoC fallback lacks some debuffs | Player Frost Shock or other categories can be absent | Known API coverage limit |
| Unseen, extremely short, or unreadable effects | Application history can be missed; same-key refreshes may be ambiguous | Conservative uncertainty where detectable; not full combat history |
| Last tracked reference lost, reload or observation gap | DR history becomes uncertain; early stages are not reconstructed | Intentional; target/focus handoffs preserve continuous history |
| Enemy talents/items and unseen reset spells | Configured cooldown ranges may not contain actual availability | Estimates with per-spell overrides |
| New beta abilities/items | Incomplete registry coverage | 120 effects / 85 casts / 27 cooldown families currently supplied |
| Counterattack rank 1242634 | Root effect is verified client data; DR grouping inherited from its family | Provisional classification |
| Pet casts and owner target filter | Pet records do not merge into owner records | Owner identity is not inferred |
| UI size/layout and native protection rules | Offline fixtures cannot establish revised game rendering or every protected call | Version 0.4 health-region placement awaits live check with leader/PvP badges and frame scaling |
| Unit-frame addon replaces Blizzard's named frames | DR anchor may be missing or follow the hidden original frame | Only PlayerFrame, TargetFrame and FocusFrame supported; moving those frames is supported |
| Target and focus are the same GUID but their APIs expose different data | Target snapshot has priority; a more readable focus alias is not tried | Conservative incomplete observation; no secret data inferred |
| Combat begins during a drag | Unsaved movement is discarded and previous offset restored after combat | Intentional; combat anchor changes are deferred |
| Icons share an estimated spell but names are hidden | Two identical icons can refer to different enemies | Hover for caster identity or enable Caster names |
| Empty bars hidden in compact mode | Unavailable data has no persistent HUD message | Use /bcc status for availability |

## Bugs diagnosed and fixed before packaging

| Diagnosed cause | Source fix | Verification |
| --- | --- | --- |
| Stage was capped at three while every new cast estimate still replaced its application time | Reject unconfirmed cast estimates at an unexpired final displayed stage; keep deduplication and observed evidence handling | Repeated attempts preserve number/sweep deadline; third application, expiry, separate categories/GUIDs and positive evidence remain functional |
| Fallback LoC key included every start-time digit, bypassing refresh tolerance | Reconcile same-spell fallback identity within 0.001 seconds while retaining the original boundary | Tiny corrections remain stage one; genuine later starts advance; distinct aura IDs stay separate |
| Empty snapshot cleared the active identity, so the same returning record counted again | Retain one bounded immutable application witness with the category and its flat predecessor | Exact replay and replay with timestamp rounding stay on the same stage; activity still clears on removal |
| Persistent DR question marks clutter the compact display | Keep evidence details in tooltip/status; omit uncertain percentage text | UI integration confirms no DR badge while preserving tooltip provenance and independent cooldown markers |
| Forever SENT used a readable space-qualified name that the resolver did not accept | Build exact space-qualified aliases from readable name/realm fields; share names across same-GUID views | Exact live name case fails before the change and passes afterward; full Main-to-UI first/second cast regression passes |
| Later readable application discarded earlier inferred stage continuity | Store inferred stage separately from observed stage and expose uncertainty in UI/status | Hidden first/second cast followed by second-application confirmation retains yellow stage two with observed stage one; estimates-off shows the observed count |
| Expired display timer deleted category history before a delayed second application arrived; an untimed arrival could overwrite its predecessor | Retain bounded current-category evidence plus one flat predecessor and reconcile original application times | Delayed application and split identity/timing arrivals preserve progression; since 0.4.7, a fresh stage requires the separate post-CC reset boundary |
| Player returned from LoC fallback to readable empty auras, discarding the DR timer | Keep successful LoC fallback selected until initialization | Real-model observer regression passes; now asserts unchanged application deadline |
| A long scan gap retained supposedly complete earlier history | Invalidate continuity after a gap over one second before fresh observations | Gap/uncertainty/recovery regression passes |
| CC could apply and be removed between throttled scans | Sample relevant aura/LoC events immediately; throttle rendering separately | Integration regression passes |
| Parent text could render under the child cooldown sweep | Place text on a frame above the cooldown frame | Frame-level integration assertion passes; visual check pending |
| Compact minute formatting was reused with a seconds suffix | Use explicit seconds in cooldown tooltips | 125-second tooltip regression passes |
| Newly created settings frame might already be shown | Refresh action captions explicitly and during display updates | Native-style OnShow fixture regression passes |
| Token-based ownership could discard DR still visible through focus | Resolve identities first; share observation and sensor state by GUID | Focus, handoff, swap, self-focus and gap regressions pass |
| StartMoving changes a frame-relative anchor into a screen-relative position | Save scale-adjusted offset and restore native anchor after drag | Anchor geometry and combat interruption regressions pass |
| Whole-unit-frame TOPRIGHT includes padding, matching the reported displaced icons | Anchor defaults to visible portrait mask/image: player above, target/focus beside | Portrait geometry, scaling, visibility and migration regressions pass; live appearance pending |
| Reset start was assigned on removal and active CC hid countdown text/sweep | Record application time and display countdown immediately; removals do not restart it | Instant break, normal removal, overlaps, event integration and expiry regressions pass |
| Expiring an application-based timer while its aura remains could recreate it on the next scan | Retain stable effect identities after timer expiry | Long aura, repeated polling and partial-observation regressions pass |
| Only player had LoC fallback when aura scans were incomplete | Supplement target/focus partial auras with readable per-unit LoC; retain stable cross-source identities | Positive witness, protected field, incomplete coverage, handoff and capacity regressions pass; live API coverage pending |
| Hidden enemy auras leave no observed outgoing application | Add isolated uncertain estimates for correlated eligible own casts; never count them as observed applications | Success, failure, target change, ambiguity and aura-before/after-cast regressions pass; hidden casts may remain unavailable |
| Portrait-side defaults compete with badges and do not align across mirrored frames | Place default rows above health/name regions with inward offsets and mirrored growth | Modern/legacy region, migration, scale, orientation and first-icon stability regressions pass; live appearance pending |
| Anchored icon BackdropTemplate performs implicit arithmetic on restricted width during size changes | Replace anchored backdrops with plain frames and constant-anchored solid textures | Old release reproduces failure in a poisoned-geometry fixture; replacement passes CC removal and next-CC sequence; live retest pending |
| First observation discarded readable application timing | Preserve guarded LoC start or aura expiration-minus-duration; correct late clocks without inventing a new application | Nine-second-late, untimed-to-timed correction, expired identity and cast confirmation regressions |
| Same aura identity prevented all reapplications from advancing | Recognize a later explicit start or a changed derived start/end pair, preserving ambiguity markers | Stable-key refresh, shortened repeated CC, unchanged polling and incomplete-timing regressions |
| First aura-to-LoC sensor handoff discarded earlier observed DR | Preserve same-GUID stages/deadlines and reconcile identities while invalidating confidence | Same-effect handoff must not duplicate; a second readable CC must advance the retained stage |
| Gray uncertainty border hid counted DR stage | Always show stage color; explain uncertainty in tooltip/status (on-icon `?` removed in 0.4.3) | First-stage estimate green, second stage yellow and uncertain third-stage red display assertions |
| Ceiling versus portrait nearest-second formatting differed by one | Match native `%.0f` text without shifting the underlying clock | 12.2 seconds displays 12; 12.8 displays 13; boundary assertions |

All nine suites pass for 0.4.10: Model 115 cases, Observer 89, OwnCasts 14, plus bootstrap, anchors, UI, event integration, backdrop and diagnostic-history regressions. Replays include the full-duration return after 15.5 seconds, the later a:421 through a:431 aura-to-LoC sequence, rejected cast estimates at the cap, late explicit duration and shared player/target/focus displays. Guard cases cover actual gaps, mismatched handoffs, contradictory aura/LoC durations, backdated removal, insufficient observed absence, partial coverage, overlaps, different spells/victims and later duration-only edits. These are diagnosed source issues with offline regression coverage, not claims of tested in-game fixes.
