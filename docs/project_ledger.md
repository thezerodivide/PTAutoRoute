# PTAR Project Ledger

Maintained per [Development_Protocol.txt](Development_Protocol.txt) Section 11. This ledger tracks the project's *current state* in four categories. Read this first to orient; consult [decision_log.md](decision_log.md) for the rationale, history, and active overrides behind any entry only as needed — don't reconstruct current state by reading the full decision log from scratch.

When new evidence resolves an open question, update this ledger before building on that conclusion. Do not silently rewrite prior entries — if something here turns out wrong, record the correction and, if the correction is material, add a decision log entry explaining why.

## Up next

**[DL-011](decision_log.md#dl-011--add-syntax-checking-and-unit-tests-for-mq-free-modules-priority-item-for-next-session) (syntax checking + unit tests for the MQ-free modules) is the explicitly agreed first thing to do in the next working session** — ahead of DL-010's implementation or anything else. Not yet started; tooling choice and which modules get tests first are still undecided.

## Pending Live Verification

Implemented code changes not yet confirmed by live testing. Check this before assuming a fix in the code is validated — cross-reference each with its decision log entry for full context. Move an item out of this section (and update its decision log status) the moment it's confirmed, whichever bucket it's in.

**Opportunistic only** — can't be deliberately engineered, will be confirmed whenever the right conditions occur naturally during ordinary play:
- [DL-006](decision_log.md#dl-006--ignore-combat-during-traversal-phases-treat-ground_exit-combat-like-normal-nav) (ignore combat during the 7 traverse/water phases; `ground_exit` gets pause-and-resume) — needs combat to overlap a traversal or a `ground_exit` leg.
- [DL-007](decision_log.md#dl-007--fall-approach-passed-limit-failure-the-2d-distance-formula-not-the-capture-is-wrong) (3D fall-approach distance, `+45` margin) — needs another incline-based ground/water drop to occur.

**Deliberately testable, just not prioritized yet** — a specific test setup already exists and could be run on demand:
- [DL-001](decision_log.md#dl-001--block-startresume-during-any-active-traversal-phase)'s diagnostic edge case: pressing "Use Nearest Waypoint" mid-traversal, with zero *other* waypoints currently reachable, should show the traversal-block message rather than the older generic "no reachable waypoint" message. (The core DL-001 guard itself is already fully live-verified — only this one narrow message-routing path remains untested.)

## Resolved behavior

Behavior actually agreed upon (source: [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md), approved as current source of truth).

- Two-part suite: Editor (capture-only, never moves/clicks/targets/fights) and Runner (playback via MQ2Nav plus special-case handling for ground drops, water drops, water crossings, doors).
- Route files are pure data behind a literal-only parser; route schema changes are never auto-applied, and an unsupported `format_version` is hard-rejected, never silently edited or upgraded.
- Saves (route data and route index) are atomic: `.tmp` write, round-trip verify, promote to main, `.bak` retained.
- Normal nav legs: 2 retries in place, then 1 (non-retried) backtrack to the last known-good waypoint, then terminal failure. This is the only true retry-covered operation in the system; every other wait (14+ across nav/drops/water/doors/combat) is a bounded wait, not a retry.
- No navmesh / no path available fails the leg immediately via the same retry/backtrack/fail sequence as a stall — no generic manual-movement fallback for normal waypoints.
- Traversal capture order: departure position+heading → ledge (if a fall phase exists) → underwater target (requires FeetWet=true and HeadWet=true) → exit (requires FeetWet=false for any water-phase preset).
- Ground drop: fails outright (not "short") if total descent doesn't meet the minimum threshold.
- Water drop/crossing: landing requires FeetWet=true or the leg fails outright; completion requires FeetWet=false and being within the exit's radius.
- Door outcomes are distinct: continue / finish_open / finish_zone, each with its own wait-then-click-or-click-then-wait sequencing; a normal door falls back to advancing on an unconfirmed state (logged as a stall fallback), a finish_zone door fails the leg outright on the same condition.
- Pause is unguarded at every phase, by design — it only stops movement and never attempts further navigation afterward, so it's mechanically safe even mid-traversal.
- Resume searches for the nearest reachable waypoint (bounded elevation range, valid path) rather than resuming the exact interrupted step — deliberately different from DeathRecovery's model, because PTAR's terrain has navmesh gaps by definition and DeathRecovery's environment (The Bazaar) does not.
- Terminal statuses (Error, Completed, Manual handoff, Ready) are distinct and not interchangeable; there is no auto-rearm after Completed/Manual handoff, matching PTAR's always-user-initiated trigger model (vs. DeathRecovery's async death trigger).
- File logging is always full verbose/DEBUG in every build, with no toggle to reduce it.
- No user-configurable retry/timeout settings — deliberate, given the size/interdependence of the timing surface and the lack of live-test data justifying specific values.
- Route selector / Refresh Routes are guarded against Running/Recovering/Waiting-for-combat (would swap route data out from under an active run); Start/Pause/Resume/Stop are not guarded against active status, since they only command state and never replace route data — except that Start/Resume now additionally refuse to act while `self.phase` is any of the 7 traverse/water_* phases, per DL-001 (**live-verified, PASS**, 2026-09-27).
- Editor and Runner are independent processes with no cross-process awareness; the Runner only reloads route data on an explicit, already-guarded user action, so editing/saving in the Editor while the Runner is active does not corrupt or desync anything.
- Log/config folder separation (`macroquest/config/<name>` vs `macroquest/logs/<name>`) is confirmed correct and will be the standard pattern adopted across other projects. The folder itself is now named `PTAR` (renamed from the legacy `PTAutorunner`, [DL-004](decision_log.md#dl-004--rename-the-ptautorunner-folder)).
- File relocation-on-launch (moving legacy route/log files from the raw MacroQuest config root) has been **removed** ([DL-005](decision_log.md#dl-005--remove-routelog-file-relocation-on-launch-behavior-before-release)) — `PTARPaths.lua` now only resolves/creates the `PTAR` config and log directories, nothing more.
- **[DL-001](decision_log.md#dl-001--block-startresume-during-any-active-traversal-phase) (Start/Resume traversal-phase guard) is implemented and live-verified** — PASS on all 3 planned test scenarios, 2026-09-27, against `v0.2.0-test.19`. One diagnostic-only edge case was observed and recorded (not a functional defect): "Use Nearest Waypoint" shows the older generic no-reachable-waypoint message instead of the traversal-block message when `self:nearest()` itself finds zero candidates — no bad navigation occurs either way.
- **[DL-006](decision_log.md#dl-006--ignore-combat-during-traversal-phases-treat-ground_exit-combat-like-normal-nav) (ignore combat during traversal, pause-and-resume for `ground_exit`) is implemented, not yet live-verified.** Corrects spec §4 (see decision log's Active overrides index).
- **[DL-007](decision_log.md#dl-007--fall-approach-passed-limit-failure-the-2d-distance-formula-not-the-capture-is-wrong) (ground-drop approach limit now uses full 3D distance, margin raised 15→45) is implemented, not yet live-verified.** The `+45` margin is a reasoned estimate approved by the developer, explicitly not a precisely-measured value — expect it to be revisited from real-world usage.
- **[DL-002](decision_log.md#dl-002--mq-console-echo-toggle-per-line-version-stamping-single-authoritative-version-source) and [DL-003](decision_log.md#dl-003--persist-last-used-route-and-mq-console-echo-preference-per-servercharacter) are implemented together and live-verified (PASS, 2026-09-27).** Shipped as `v0.2.0-test.20`. New: `PTARVersion.lua` (single version source) and `PTARSettings.lua` (per-server/character preferences, Runner-only). File logging now unconditionally writes DEBUG lines (no toggle reduces it, per spec §12); the former "Verbose Debug" button is repurposed as "MQ Console Echo" and now only controls whether DEBUG lines are also mirrored to the MQ console — EVENT lines are never console-echoed by this mechanism.
- **[DL-004](decision_log.md#dl-004--rename-the-ptautorunner-folder) and [DL-005](decision_log.md#dl-005--remove-routelog-file-relocation-on-launch-behavior-before-release) are implemented together and live-verified (PASS, 2026-09-27).** Shipped as `v0.2.0-test.21`. All five of Section 21's original concrete fixes are now implemented and live-verified.
- **[DL-008](decision_log.md#dl-008--multi-character-door-coordination-via-group-chat-primarysecondary-roles) (multi-character door coordination via group chat) is implemented and live-verified (PASS, 2026-09-27).** New functionality, not spec-derived — solves a confirmed multibox failure mode (two independent PTAR instances both clicking the same door, toggling it closed again, looping forever). Primary clicks and broadcasts `PTAR:DOOR:<id>:OPEN` via `/g`; secondaries never click a `continue`/`finish_open` door, only `finish_zone` doors (zoning is per-client, unaffected by this feature). Shipped as `v0.2.0-test.22`. Both race directions (secondary-arrives-first and secondary-catches-up) confirmed working, plus `finish_zone` unaffected.

## Confirmed live/system facts

Facts established through source inspection, documentation, or (once it occurs) live testing.

- Route `format_version = 3`. Waypoint types: normal, door, traverse, finish.
- Traversal presets: ground (`{fall}`), water_drop (`{fall, descend, cross, ascend}`), water_cross (`{descend, cross, ascend}`).
- Traversal departure/approach radius defaults to 3 if left blank; capped at 5 maximum.
- Underwater target radius has no fallback default (required for water_drop/water_cross only) — swimming drift from interacting variables (momentum, heading, etc.) is too fast-changing to generalize a default for.
- Exit radius is required on every traverse preset including ground, with no code-level fallback (Editor UI pre-fills 5 as a suggestion only).
- Ground drop detection is speed-based: descent >15 Z/s signals a fall has begun; landing is declared once vertical speed stays under 4 Z/s for 750ms; minimum 15 Z units total descent required.
- Normal nav legs: 2 retries in place, then 1 backtrack, then terminal failure (see also Resolved behavior).
- Combat interrupts navigation, door interaction, and `ground_exit` legs; 2000ms clear-and-resume delay after combat ends. **Corrected 2026-09-27 ([DL-006](decision_log.md#dl-006--ignore-combat-during-traversal-phases-treat-ground_exit-combat-like-normal-nav)):** the 7 traverse/water phases do **not** get this pause-and-resume treatment — combat is ignored (not acted on) during them, since TAC cannot function in a navmesh gap regardless, and pausing there previously produced an unbounded `Error`-state exposure window (confirmed fatal in practice: water deals damage over time, on top of the attacking mob).
- `/face` and `Me.Heading.Degrees()` use opposite numeric directions on RoF2 (source comment + explicit conversion function, `PTARRunnerCore.face_heading`).
- Implementation state machine has 13 phases and 8 statuses (spec §16) — see [CLAUDE.md](../CLAUDE.md) architecture section for the current list.
- Section 4.1 timing/threshold constants (fall windows, water descend/cross/exit timeouts, heading tolerances, stall/timeout thresholds) are implementation choices made during prior development, not derived from a stated requirement. **One has now been attributed to a specific live failure and revised** ([DL-007](decision_log.md#dl-007--fall-approach-passed-limit-failure-the-2d-distance-formula-not-the-capture-is-wrong): the ground-drop approach-distance formula discarded elevation change entirely and its margin was too tight). The rest remain unproven-not-wrong, not confirmed-correct, per the Development Protocol §15 standard.
- The config/log subfolder is now named `PTAR` (see [PTARPaths.lua](../lua/PTAR/PTARPaths.lua)), renamed from the legacy `PTAutorunner` per DL-004.

## Open implementation details

Questions intentionally unresolved — do not decide these unilaterally; surface them for discussion when they become relevant.

- **Route ending rule, provisional (spec §5):** the current rule that a route must have an explicit ending (finish waypoint, manual handoff, or finish-configured door) before it can be loaded/run is accurate to today's code but flagged provisional — a future route-chaining feature may require it to change. Also currently adds testing friction (no end-to-end run during capture without planting/removing a Finish waypoint each time).
- **Persistence-to-root, provisional (spec §13):** once route trees exist, last-used-route persistence should resolve to the root of the tree rather than the specific sub-route last active. Depends on the not-yet-designed route-chaining feature.
- **Door/door_zone phase safety for Start/Resume interruption (spec §8, §16):** assumed safe because a door position is proven reachable by ordinary route playback before door logic ever runs — but this is an assumption, not yet independently live-verified. Treated as self-resolving through ordinary use rather than requiring dedicated testing; only revisit if a specific failure is observed and logged.
- **Route chaining design (spec §20):** a Finish that loads a different route (e.g. Eastern Wastes → Sleeper's Tomb) is not yet designed. Affects the route-ending rule (§5) and the persistence-to-root caveat (§13) above. Do not implement any part of this speculatively.
- **Full UI redesign, both Runner and Editor windows (spec §11, §20):** current layout for both windows is not considered satisfactory; a redesign is planned as a future revision and is explicitly out of scope for the current spec document.
- **TAC integration, if ever added (spec §3, §15):** out of scope for this version; if added later, scope is explicitly limited to starting TAC in Manual mode when the user presses Start — no broader TAC state management. Not a current open question, but noted so a broader TAC integration is never assumed in without a fresh scoping discussion.
- **Levitate breaks ground-drop fall-detection ([DL-009](decision_log.md#dl-009--levitate-breaks-ground-drop-traversal-fall-detection-known-limitation-deferred)), confirmed and deliberately deferred:** a character with Levitate active never triggers the speed-based fall detection, so a fall-based traversal will always time out and fail. Documented as a known limitation (don't levitate before a fall-based traversal) rather than fixed — developer's own assessment is that clean detection/handling is "possible but messy." Revisit only if this recurs as a practical problem.
- **Multi-client waypoint barrier sync ([DL-010](decision_log.md#dl-010--multi-client-waypoint-barrier-sync-agreed-design-implementation-deliberately-held)) — design fully agreed, implementation not started.** Solves the drift/combat-desync problem found during the DL-008 live test. Every client now runs PTAR for the *entire* route continuously (TAC left in Manual, fight-only) — Assist-Chase was never viable full-route since it relies on `/nav`, which can't cross a navmesh gap. Agreed shape: full barrier sync at every waypoint (everyone waits for everyone, bounding drift to at most one waypoint regardless of client count), with participant roster membership requiring both live group membership *and* a recent `PTAR:HERE` heartbeat. `door_role` stays scoped to door-clicking only, unaffected by this. Traversal waypoints get barrier-gated on **both** sides — departure (with alphabetical one-at-a-time ordering and a loose automatic waiting radius, to avoid multi-client collision at the tight departure spot) and exit (plain barrier-wait, no turn-based ordering, relying on natural staggering from the departure order). No implementation yet — ready to build whenever the developer says go.

## Out of scope

Explicitly decided not to build or investigate (spec §15).

- Navmesh generation, installation, or repair.
- Broader TAC control beyond starting it in Manual mode on Start (see Open implementation details above for the narrow exception).
- Death detection/recovery — an intentional tool separation from DeathRecovery, not a missing integration. PTAR has no death awareness. May be reconsidered later; no current plans.
- Combat participation — PTAR only detects combat to pause/resume navigation, never fights.
- Automatic route generation/pathing discovery — routes are always hand-captured.
- Cross-zone routes — a route is locked to a single `zone_short_name`.
