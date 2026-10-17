# bjarkiCC development guardrails

These rules preserve the 0.4.17 baseline while improving correctness on the WoW Forever beta.

## What constitutes evidence

- A spellcast **start** or a successful cast event is not proof that crowd control landed. Only a guarded, readable positive aura/LoC witness can advance observed DR. An own-cast guess stays an explicitly uncertain overlay.
- A nil/secret/erroring indexed or exact aura query is **unknown**, not proof of absence. Only a complete readable harmful-aura enumeration can authorize removal. A complete LoC list does not enumerate every debuff.
- A readable player GUID and a readable positive hostility result are useful independent witnesses. A readable contradictory identity must veto the association. Never unwrap or format protected values to manufacture evidence.
- Target and Focus referring to the same GUID are aliases, not independent victims. Any alternate-unit probe must revalidate the GUID; reconcile positive witnesses and commit to the model only once.
- The AoE stun effect IDs 20549 (War Stomp) and 4068 (Iron Grenade) have distinct victim-side positive lookups. A racial/item cast is never a verified hit. Only readable matching harmful aura instances may update observed DR.
- UNIT_AURA updateInfo is fully secret when auras are restricted on modern clients. Readable AoE addedAuras may contribute a positive witness, never absence; a contradictory indexed complete scan must not erase it. Native DR tracker payloads are secret and are telemetry only, not category/history data.
- Exact-spell lookups must be selected from explicit, narrow known IDs or a bounded outstanding direct-cast estimate. Do NOT poll all 120+ DR spells, guess victims from area casts or declare a nil lookup a hit.
- Native secure aura icons may display while ordinary addon Lua cannot inspect the spell or instance. Do not promote their visible artwork to historical DR proof. Follow the distinction learned in bjarkiPortraits between native presentation and readable identity.

- When caster-side Bash/Grenade are absent, inspect actual available evidence before adding another guessed cast stage: recipient player-LoC may be confirmed while hostile target/focus indexed aura, exact lookups, ByUnit LoC, and event addedAuras all provide zero positives. These cannot be equated.
- The native `C_SpellDiminish` feed is a separate **explicit client-CVar opt-in experiment** via `/bcc native on|off|status`. Native events have secret payloads; preserve readable/unknown distinction and do not turn their mere arrival or own cast delivery into a confirmed DR application. Do not set the global CVar automatically.



- `NativeStuns.lua` is a **secure native visual-only witness**. Never inspect its slot/button visibility, duration, identity or cooldown in addon Lua, and never adapt its presence into `Model:Observe` or a confirmed DR stage. Aura containers preallocate frames specifically to avoid revealing secure aura presence through construction counts.
- Keep the native stun witness off by default and out-of-combat only. The successful creation of a CustomAuraContainer does *not* establish live ability to display secret stuns on this client. Test its effect in actual combat before claiming the feature works.
- `C_Secrets.ShouldUnitAuraIndexBeSecret` may safely advise **not to query** an inaccessible aura index. Skipping its lookup must always yield partial/unknown coverage, never `complete=true` or a missing-stun conclusion.


- The user **explicitly opted into AoE estimates** for War Stomp and Iron Grenade after testing a shared DR category with Bash; after confirming the estimates worked in game, they requested clean DR icons **without a visible `?` glyph**. `OwnCasts.lua` may snapshot *possible* target/focus player GUIDs and, only after your own successful AoE cast, set an uncertain Model estimate tagged `estimateKind="aoe"`; never call it a confirmed hit, even if only one target is selected.
- **Do not reintroduce the AoE `?` HUD badge.** The same colored stage border and countdown as other uncertain DR predictions are desired. The tooltip and `/bcc status` must still identify AoE applications as unconfirmed *possible recipients*. Individual target/focus candidates have independent counters; duplicate GUID aliases count once. Real aura/LoC evidence retains priority, and turning AoE estimates OFF must not hide observed history underneath.
- Avoid further secure native aura duplication unless explicitly requested. `/bcc aura off` hides the optional STUN AURA widget; `/bcc aoe on` handles AoE DR estimates without the separate widget.

## Timer and HUD invariants

- `resetSeconds` is the visible application-based countdown, default 20s. CC ending/removal does not restart it.
- `stageResetSeconds` is a *separate provisional* DR stage retention after CC ends, default 18s. Never claim it is a verified Forever server constant.
- An inferred stage never silently becomes an observed one. Preserve the accepted 0.4.17 DR 2×2 geometry, stage colors and countdown policy. Schema 8 is a narrow migration for the experimental enemy-cooldown HUD; do not reset other saved settings.
- Let native Cooldown frames advance unchanged countdowns; avoid resetting clocks, fonts, icon geometry and anchor points every 0.1 seconds.
- Enemy cooldown tracking is unverified on this Forever build. Keep its HUD opt-in and separate its synthetic /bcc test icons from observed successful hostile casts and manually marked uses. Do not display a fake preview as if it were live combat evidence, or infer unseen enemy uses from cast START, a blank bar or talent assumptions.
- The old cooldown screen anchor (0,-280) overlapped the cast bar. Schema 8 moves only the untouched default to (0,-170); user-customized positions and explicit opt-in after migration must remain stable.

## Verification and change control

- Run `python tests/run_tests.py` and check both TOCs and Lua 5.1 compatibility. Add a regression for each failure, including negative or inaccessible evidence paths.
- Browser screenshots and local Lua mocks cannot establish protected API availability on the live beta. State exactly what is source-verified, fixture-tested or observed in game.
- Prefer small reversible changes; do not bundle speculative server-rule adjustments, UI redesigns and sensor changes into one repair.
- Preserve user configuration on upgrade and rollback. Replacing Lua files does not overwrite WoW SavedVariables.
- Use `/bcc status` during the CC itself. Capture which token and API supplied a readable positive, not just whether an icon appeared afterward. Do not hide a failing observation by resetting history before diagnostics.
