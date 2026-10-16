# bjarkiCC known issues and validation status

The latest user report is that receiving CC starts DR but applying CC does not, and the portrait-adjacent icons still need better placement. Version 0.3.1's observer had a player LoC fallback but depended on harmful aura reads for target/focus. Native portrait CC artwork does not prove those aura IDs are readable by Lua. That asymmetry is a diagnosed source limitation; the exact failing runtime event has not been captured.

Version 0.4.0 adds guarded per-unit LoC witnesses and optional own-cast estimates, always marked `?`, plus health-region anchors above the name area. It retains the explicitly requested application-based display timer even though the researched Classic reset convention differs. Offline regressions pass. Outgoing detection, revised visual alignment, and Forever server mechanics still require live validation; this is not a claim that every enemy CC is now observable.

## Open limitations

| Condition | Consequence | Status |
| --- | --- | --- |
| Beta hides enemy spell/identity/aura fields | Automatic target/focus DR or enemy cooldown tracking may be unavailable | Supported failure mode; live coverage unverified |
| Successful own cast is resisted, immune, delayed or sent to another same-name unit | Gray `?` estimate can appear without an actual application | Optional fallback; confirmed aura evidence takes precedence; cast success is not a hit guarantee |
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

These are diagnosed source issues with offline regression coverage, not claims of tested in-game fixes.
