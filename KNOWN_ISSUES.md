# bjarkiCC known issues and validation status

## Current report: 0.4.2 Hibernate cycles

The user reports reduced outgoing Hibernate showing the first-cycle green border, full incoming Hibernate showing the second-cycle yellow border, and unnecessary DR question marks. The installed TOC is 0.4.2-beta. Live `/bcc status` during incoming Hibernate shows player LoC with one mapped witness, observed stage two at start 2654073.250, no own-cast estimates, and no scan gaps. Target/focus show the same player GUID's history. This rules out the own-cast overlay for that incoming yellow icon, but does not reveal the prior observation transition.

Two duplicate-count paths were reproduced through the real observer/model: a fallback LoC start changing from 21 to 21.0001 produced a new key and another stage, and a complete empty snapshot followed by the identical application also advanced the count. Version 0.4.3 stabilizes fallback identity within the existing 0.001-second tolerance and retains one bounded witness with category history. Tests cover each path and their combination, a real later start, distinct aura IDs and unchanged polls. Their relevance to the exact live incident remains unconfirmed.

**The reduced outgoing Hibernate case remains open.** The user is unsure whether the previous application was less or more than 20 seconds earlier. The selected policy resets the stage after 20 seconds from application; a full 20-second CC followed by another at 21 seconds therefore displays stage one even if the game still diminishes it. That policy consequence is reproduced, but it is not established as the screenshot's cause. Version 0.4.3 records bounded recent witness/stage transitions in `/bcc status` so a live repeat can distinguish expired history from missed evidence. It does not change timer semantics or infer server stages from remaining portrait seconds.

DR question marks are removed in 0.4.3. Incomplete or inferred evidence is still described in tooltips and status; uncertain rows omit optional percentages. Cooldown readiness markers and manual-use markers are unchanged. Live confirmation of the duplicate-count corrections remains pending.

## Previous report: 0.4.1

The user reports that the first offensive application still has no DR timer and a later screenshot shows stage one on the second CC. The live status report records `ownCast.captured: 0`, `ownCast.unresolved: 7`, and zero mapped target/focus aura or per-unit LoC witnesses. Readable UnitName fields were `Björn`, `Janson`; the actual SENT destination was `Björn Janson`. The resolver accepted only the bare name or `Björn-Janson`. This exact mismatch is reproduced and corrected in 0.4.2 by adding an exact space-qualified alias built from readable fields. Same-GUID aliases now share readable names, while distinct ambiguity remains rejected.

Two separate source undercounts were reproduced: confirming only the second of two own-cast estimates discarded the inferred first stage; and a late readable second application lost its predecessor when the old display timer had expired. Version 0.4.2 preserves inferred stages separately from observed counts and retains bounded category history for application-time ordering. The screenshot alone does not establish which stage-loss path occurred in that duel. These are tested source corrections, not an in-game validation result. The chosen 20-second application-only timer remains unchanged, including its stage-one restart at or beyond that boundary.

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
| Fallback LoC key included every start-time digit, bypassing refresh tolerance | Reconcile same-spell fallback identity within 0.001 seconds while retaining the original boundary | Tiny corrections remain stage one; genuine later starts advance; distinct aura IDs stay separate |
| Empty snapshot cleared the active identity, so the same returning record counted again | Retain one bounded immutable application witness with the category and its flat predecessor | Exact replay and replay with timestamp rounding stay on the same stage; activity still clears on removal |
| Persistent DR question marks clutter the compact display | Keep evidence details in tooltip/status; omit uncertain percentage text | UI integration confirms no DR badge while preserving tooltip provenance and independent cooldown markers |
| Forever SENT used a readable space-qualified name that the resolver did not accept | Build exact space-qualified aliases from readable name/realm fields; share names across same-GUID views | Exact live name case fails before the change and passes afterward; full Main-to-UI first/second cast regression passes |
| Later readable application discarded earlier inferred stage continuity | Store inferred stage separately from observed stage and expose uncertainty in UI/status | Hidden first/second cast followed by second-application confirmation retains yellow stage two with observed stage one; estimates-off shows the observed count |
| Expired display timer deleted category history before a delayed second application arrived; an untimed arrival could overwrite its predecessor | Retain bounded current-category evidence plus one flat predecessor and reconcile original application times | Delayed second application and split identity/timing arrivals advance within the first window; a genuine application at or beyond the boundary resets |
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

All nine suites pass for 0.4.3: Model 63 cases, Observer 72, OwnCasts 14, plus bootstrap, anchors, UI, event integration, backdrop and diagnostic-history regressions. These are diagnosed source issues with offline regression coverage, not claims of tested in-game fixes.
