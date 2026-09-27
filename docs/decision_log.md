# PTAR Decision Log

Maintained per [Development_Protocol.txt](Development_Protocol.txt) Section 2. This log records *why* material decisions were made and how they evolved. It is distinct from [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) (*what* the system must do) — do not merge the two, and do not reconstruct this log from memory; append to it as decisions are made.

Each entry captures: the decision, why it was made, the evidence/requirement/constraint that drove it, its status (confirmed / provisional / open-dependent), and what earlier entry (if any) it supersedes.

Never silently overwrite or reinterpret an existing entry. If new evidence conflicts with one, add a new entry that states the conflict explicitly and points back at the entry it revises — never edit history in place.

## Active overrides index

Entries below that supersede a specification item are indexed here so the supersession is visible without cross-referencing the whole log against the spec. Empty until an entry actually overrides an approved spec section.

*(none yet)*

## Log

Entries are ordered oldest first. New entries append at the bottom.

---

### DL-001 — Block Start/Resume during any active traversal phase

- **Status:** Implemented, pending live verification — code change complete and reviewed against spec; no in-game test has been run yet. Do not describe as "validated" or "passed" until a live test confirms it (Development Protocol §10, §15).
- **Decision:** Start and Resume must refuse to act whenever the runner's current phase is any traversal/water phase (`traverse_facing`, `traverse_approach`, `traverse_falling`, `water_facing`, `water_descend`, `water_cross`, `water_ascend`), not only mid-fall/mid-swim.
- **Why / evidence:** Every traversal phase occurs, by definition, in a location with no navmesh coverage (spec §7, §16). Without this guard, Start/Resume halts movement and then attempts to navigate to an unreachable point, producing an immediate, avoidable Error. The guard exists in the design (spec §8, §16) but the gap was confirmed against current code — traversal support was added after the original Start/Resume guardrails were designed, and those guardrails were never revisited against the new phase set.
- **Implementation notes:** Guarded in [PTARRunnerCore.lua](../lua/PTAR/PTARRunnerCore.lua) `self:start()`, which `self:resume()` and `self:start_nearest()` (the "Use Nearest Waypoint" button) both already route through — so a single guard point covers Start, Resume, and Use Nearest Waypoint, since all three share identical navigate-to-unreachable-point risk. Two additions beyond the literal spec text, required for the guard to be correct rather than merely present (Development Protocol §3 — necessary for correct implementation of the agreed behavior, not new scope):
  - `advance()` now clears `self.phase` before evaluating `manual_handoff`/finish, because a traverse waypoint whose exit is already within radius can reach `advance()` directly from a traversal phase (e.g. `traverse_falling`) without passing through `navigate()` first. Without this, a traversal waypoint flagged `manual_handoff` (or similar direct-advance cases) would leave `self.phase` permanently stuck on a traversal value even after reaching a terminal status, incorrectly blocking a later legitimate Start.
  - `self:stop()` now clears `self.phase`, since spec §10 treats Stop's resulting `Ready` status as a full reset to a clean startable state; leaving a stale traversal phase behind after an explicit Stop would otherwise permanently lock out Start via this new guard.
  - `self:pause()` was deliberately left untouched — `self.phase` must survive Pause for this guard to have anything to check on Resume.
- **Supersedes:** none.
- **Source:** [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) §8, §16, §21 (item 1).

---

### DL-002 — MQ-console echo toggle, per-line version stamping, single authoritative version source

- **Status:** Pending (open-dependent — not yet implemented; explicitly one combined piece of work, not three separate ones)
- **Decision:** (a) Add a new UI toggle controlling only whether DEBUG-level log lines are also echoed to the in-game MQ console (file logging unaffected either way); default on in test builds, off in release/RC builds, but any persisted user preference always wins over the build default. (b) Every log line must include the running build's version number. (c) Version identity must be derived from a single authoritative internal value, replacing the current hardcoded per-window literal strings.
- **Why / evidence:** (b) and (c) are linked because per-line version stamping cannot be trusted while the version string is hardcoded independently in each window title (spec §14 notes both currently read `v0.2.0-test.18` as independent literals — a drift risk). (a) is a new feature, not present in current code. Per-line version stamping is also a **restored requirement**: it was specifically requested previously and silently dropped in an earlier implementation pass — the exact failure mode the decision-log discipline exists to prevent (spec §12).
- **Constraint carried forward:** Development Protocol §9 requires version numbers to follow SemVer. The current literal `v0.2.0-test.18` is already valid SemVer (`MAJOR.MINOR.PATCH-prerelease.identifier`, with `test.18` a legal dot-separated pre-release identifier) — the single authoritative value this decision introduces must preserve that, not just consolidate the duplicate literals.
- **§9's unique-filename requirement — resolved for this project, not literally:** `/lua run PTAR` and every internal `require('PTAR.X')` call resolve to fixed filenames; renaming files per build would require changing the run command and every `require` call each time, which is more complexity than this project's scale warrants (Development Protocol §13). Confirmed with the developer that deployment is a **manual copy** from this repo to the live MacroQuest lua folder — no symlink, no sync script. Given that, §9's actual goal ("make it easy to confirm you're testing the intended version") is satisfied by the single authoritative version value (item c above) shown in the window title and stamped in the log, **paired with a deployment rule, not a code change: always copy the entire `lua/PTAR/` tree plus `lua/PTAR.lua` as one unit for every test build, never individual changed files.** Without that pairing, a bumped version string only proves the entry-point file is current, not that every changed module (e.g. a `PTARRunnerCore.lua`-only change like DL-001) was actually copied — which would produce false confidence, worse than no version number at all. This deployment rule is a process note for the developer, not something enforceable by the code itself.
- **Supersedes:** none.
- **Source:** [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) §12, §14, §21 (item 2).

---

### DL-003 — Persist last-used route and MQ-console-echo preference per server/character

- **Status:** Pending (open-dependent — not yet implemented; the echo-preference half also depends on DL-002 landing first)
- **Decision:** Last-used route persists across relaunches, scoped per server/character. The MQ-console-echo toggle (DL-002) also persists per server/character; its build-based default applies only before any preference has been set.
- **Why / evidence:** Stated requirement (spec §13). Flagged provisional in one respect: once route-chaining exists (a Finish that loads a different route), persistence should resolve to the root of the route tree rather than the specific sub-route last active — that refinement depends on the not-yet-designed chaining feature (spec §20) and is out of scope until that design happens.
- **Supersedes:** none.
- **Source:** [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) §13, §21 (item 3).

---

### DL-004 — Rename the PTAutorunner folder

- **Status:** Pending (open-dependent — not yet implemented)
- **Decision:** Rename the `PTAutorunner` config/logs subfolder to a name consistent with the project's actual name, before this folder structure becomes the template other projects copy.
- **Why / evidence:** `PTAutorunner` is a legacy name (spec §14). The config/logs separation pattern itself (`macroquest/config/<name>` vs `macroquest/logs/<name>`) is confirmed correct and matches Development Protocol §8 — only the specific name needs to change, not the separation pattern.
- **Supersedes:** none.
- **Source:** [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) §14, §21 (item 4).

---

### DL-005 — Remove route/log file relocation-on-launch behavior before release

- **Status:** Pending (open-dependent — removal not yet scheduled/implemented; current relocation behavior is intentional and active in the meantime)
- **Decision:** The automatic relocation of legacy route and log files from the MacroQuest config root into the dedicated subfolder, performed on every launch, stays active during testing but must be removed before release.
- **Why / evidence:** This is relocation-only behavior — never a schema edit — kept deliberately during the testing period to smooth the folder-layout transition (spec §3). It is not meant to be permanent, so its removal is tracked here rather than left to be forgotten once testing ends.
- **Supersedes:** none.
- **Source:** [PTAR_Rebaseline_Spec.md](PTAR_Rebaseline_Spec.md) §3, §21 (item 5).
