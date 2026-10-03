# Lessons Learned (running log)

Kept so nothing depends on either of our memories. **This is not the Development Protocol and does not change it.** At the release retrospective (after a stable v1.0) each entry is triaged by the developer into: **Protocol** (general project process), **CLAUDE.md** (working agreement with the AI, or project-specific guidance), or **Noise** (drop it).

How this log works:
- Claude appends an entry whenever a lesson appears during work, with the evidence that produced it (a decision-log entry, a commit, an incident).
- **Area** is what kind of lesson it is: Process, Collaboration, Technical or AI-behavior.
- **Suggested** is Claude's provisional guess at where it belongs. It is only a starting point for the retrospective.
- **Triage** stays blank until the retrospective. Do not fill it in earlier.
- Entries are append-only; a lesson found to be wrong is annotated, not deleted.

---

## 2026-09-28 (seeded from the first ~80 builds and the DL-010 / DL-011 to DL-013 work)

**L-001 — Build the test harness at the start, not after ~20 builds.**
Evidence: DL-011/DL-012 came late; earlier builds relied on live testing for logic bugs. Harness landed in `27926a6`.
Area: Process. Suggested: Protocol. Triage: Protocol (folded into sharpened §7, 2026-09-29).

**L-002 — Prove tests can fail; isolate each mutation to one condition.**
Evidence: mutation checks caught weak tests (the `RouteData` identifier check "passed" for the wrong reason until a test was added; DL-013 steps 1–3). Two early mutations changed more than one line and muddied what they proved.
Area: Process. Suggested: Protocol. Triage: Protocol (folded into sharpened §7, 2026-09-29).

**L-003 — Cite the requirement source for every expectation; never take expected values from the code's own output.**
Evidence: DL-012 guardrails; every `runner_core_test.lua` and `route_data_test.lua` test names its DL entry or spec line.
Area: Process. Suggested: Protocol. Triage: Protocol (folded into sharpened §7, 2026-09-29).

**L-004 — Label Requirement / Design choices / Implementation choices / Open, and remember approval of a name or number does not make it a requirement.**
Evidence: DL-010 and DL-013 mixed the layers until the retrofit; Protocol §1 names four categories but the log blurred them.
Area: Process. Suggested: Protocol. Triage: Protocol (§2 to require entries be structured into the four labeled blocks, 2026-09-29 retrospective, added).

**L-005 — Start from a story and an observation, not a solution.**
Evidence: DL-013 began as a mechanism (explicit TAC commands) and the problem was written afterwards; no TAC interference had been observed. Led to `docs/User_Story_Template.md`.
Area: Process. Suggested: Protocol. Triage: Protocol (fold `User_Story_Template.md`'s shape into the Protocol itself, 2026-09-29 retrospective, added).

**L-006 — Track dependencies and shared seams between entries explicitly.**
Evidence: DL-010 and DL-013 both hook waypoint arrival and completion; the ordering (barrier, then `tac_before`, then the action) was only decided because the developer asked.
Area: Process. Suggested: Protocol. Triage: Protocol (add to §2, 2026-09-29 retrospective, added).

**L-007 — Update status lines when the work lands, with commit hash and verification tier.**
Evidence: DL-011 and DL-012 kept saying "in progress" and "pending" after they shipped (fixed in `30ebb08`).
Area: Process. Suggested: Protocol. Triage: Protocol — substantially covered by existing §10 plus the new §18 sweep; no further edit needed (2026-09-29 retrospective).

**L-008 — Keep an explicit "unverified, do not describe as confirmed" list per entry.**
Evidence: DL-013's Unverified bullet (live status-line catch, `BeginDisabled` in PTAR, pause latency).
Area: Process. Suggested: Protocol. Triage: Protocol (add as a required §2 field, 2026-09-29 retrospective, added).

**L-009 — Facts about the game, the developer's setup and risk tolerance must be asked, not inferred.**
Evidence: I treated a PT lockout as an unrecoverable cost without asking; the developer's facts (a manual waypoint before each door, Chase stalling at gaps, buffbots left at the entrance) each changed a recommendation.
Area: Collaboration. Suggested: Protocol (may overlap §14/§16) or CLAUDE.md. Triage: Protocol (folded into broadened §4 as a third leg — the target system, your own tooling, and the developer's own situation, 2026-09-29).

**L-010 — Before agreeing a design, ask which parts are justified by an observation; record deferrals with a revisit trigger.**
Evidence: DL-010 grew (turn order, exclusion mark, re-send, GO) for problems nobody had seen; the scope-reduction review (DL-010 item 8) cut it back.
Area: Process. Suggested: Protocol. Triage: Protocol (add to §3 as a required review pass before finalizing a nontrivial design, added).

**L-011 — Keep read-only local copies of external dependencies and cite file:line; a web-tool summary is a paraphrase, so check the raw text.**
Evidence: `reference/TAC` (v3.1) exposed Manual mode's default movement, the cast-time movement stop and the ungated plugin loop; the README summary alone would have missed them.
Area: Technical. Suggested: CLAUDE.md / project-specific. Triage: split — the principle (read source directly, cite file:line, don't trust a paraphrase) folded into broadened §4, 2026-09-29; the mechanism (a `reference/` folder) stays CLAUDE.md/project-specific.

**L-012 — Check the developer's sibling projects before designing a mechanism.**
Evidence: PTDeathRecovery already had the verified `/ac status` pattern; the DL-013 design took its shape instead of inventing one.
Area: Process. Suggested: CLAUDE.md. Triage: split — Protocol requires maintaining and consulting the list (new §21, 2026-09-29); the list itself lives in each project's CLAUDE.md (seeded for this project in CLAUDE.md's new "Related projects" section).

**L-013 — Log every decision and every send with its reason; review a representative log as an outside developer.**
Evidence: the DL-013 retry log said "not confirmed" but not what had been sent; the diagnostic review found it and a send line was added.
Area: Process. Suggested: Protocol (§8 partly covers). Triage: Protocol ("review as an outside developer" restates existing §8; "log every send with its reason" sharpens it, added).

**L-014 — State when a step is not shippable alone; use one build number per live test; with manual folder-copy deployment, new files need a copy checklist.**
Evidence: DL-013 step 2 could not run in-game until the adapter existed; `PTARTac.lua` is a new file that must be copied with the tree.
Area: Process. Suggested: Protocol / CLAUDE.md. Triage: Noise (the first two points are already covered by existing §6/§9) / CLAUDE.md for the copy-checklist point (specific to manual-folder-copy deployment, not every future project's model), 2026-09-29 retrospective.

**L-015 — Verify tooling assumptions by running them.**
Evidence: `cmd /c` strips outer quotes when a command has more than two (breaks paths with spaces; fixed by one outer pair, verified locally); `os.tmpname`, `xpcall`, exit-code and `popen:close()` assumptions were wrong when checked; long shell heredocs failed and were replaced by writing a file.
Area: Technical. Suggested: project-specific. Triage: Protocol (folded into broadened §4, 2026-09-29).

**L-016 — Append-only documents: retrofit by adding a classification section, never rewriting history; make status corrections visible.**
Evidence: the DL-010/DL-013 retrofit; DL-011/DL-012 status corrections noted in place.
Area: Process. Suggested: Protocol. Triage: Protocol (codify in §2 that the decision log is append-only, corrections via dated addendum, added).

**L-017 — One question at a time, and no request for a decision while the discussion is still open.**
Evidence: I asked for the DL-010 barrier-timeout decision about four times while facts were still being gathered, and ended messages with lists of questions. Saved as a preference.
Area: Collaboration. Suggested: CLAUDE.md. Triage: Protocol (folded into new §17, 2026-09-29 — reusable interaction-pacing rule, not tied to this developer specifically).

**L-018 — Give conclusions and constraints, not the full reasoning; say when a fact changes the recommendation.**
Evidence: the developer's "internal versus things you need to know" split; every fact that mattered was a constraint.
Area: Collaboration. Suggested: CLAUDE.md. Triage: split — "give conclusions not full reasoning" is a personal working-style preference (CLAUDE.md); "say when a fact changes the recommendation" is universal, folded into §17, 2026-09-29.

**L-019 — Bundled "agreed" is approval fatigue; approve item by item and label assumptions.**
Evidence: DL-013 recorded many implementation details as "decisions" through quick agreement on bundles.
Area: Collaboration. Suggested: CLAUDE.md / Protocol. Triage: Protocol (folded into new §17, 2026-09-29).

**L-020 — The developer's automation-versus-caution weighting is the developer's judgment; the AI states the worst case and recommends.**
Evidence: the barrier timeout and the unconfirmed-pause policy; the PT lockout correction removed my strongest objection.
Area: Collaboration. Suggested: CLAUDE.md. Triage: Protocol (folded into new §17, 2026-09-29).

**L-021 — AI memory-based claims need checking before they stand.**
Evidence: five were wrong when verified: `os.tmpname` paths, wrapping `xpcall`, a distinct launch exit code, `popen:close()` status, and MQ's Lua version.
Area: AI-behavior. Suggested: CLAUDE.md. Triage: Protocol (folded into broadened §4, 2026-09-29).

**L-022 — Ambiguous wording costs time; say who or what is meant.**
Evidence: "PTAR can't confirm a TAC command" was read as "nobody can"; the human could see TAC's acknowledgement line, PTAR could not read it.
Area: AI-behavior. Suggested: CLAUDE.md. Triage: Protocol (folded into §17, 2026-09-29 — a general precision-of-language principle, not tied to this developer).

**L-023 — Welcome pushback in both directions.**
Evidence: the developer's corrections (doors, Chase, buffbots, "are we overengineering?") reshaped DL-010 and DL-013; the AI's challenge of the automation weighting and the fixed primary did the same.
Area: Collaboration. Suggested: CLAUDE.md. Triage: Noise — already stated in existing §13 ("push back when I am materially wrong"); this would only restate it.

**L-024 — Push docs-only changes without asking; ask before pushing code.**
Evidence: applied throughout; no friction.
Area: Collaboration. Suggested: CLAUDE.md. Triage: CLAUDE.md — a trust/permission-scope call that varies by developer and repo, not universal.

**L-025 — Rebuild recaps from the repo and the log, not from memory; recaps expose stale entries.**
Evidence: the recap before DL-013 exposed the stale DL-011/DL-012 statuses.
Area: Process. Suggested: CLAUDE.md. Triage: Protocol (added to §11 — the mechanism that makes reading the ledger first, and the daily session boundary in L-031, actually work, 2026-09-29).

**L-026 — Read the existing code before extending it; it can hold a defect the design would have inherited.**
Evidence: reading `PTAR.lua` showed `confirmed_doors` is never cleared (across runs or zones), which changed DL-010's door-confirmation rule.
Area: Technical. Suggested: Protocol / CLAUDE.md. Triage: Protocol (added to §5, 2026-09-29).

**L-027 — Design a tool to be testable by separating its logic from its host bindings.**
Evidence: `PTARCombat` and `PTARTac` are MacroQuest-free modules, so the query guard and the combat decision are unit-tested; only the thin wiring is parse-checked.
Area: Technical. Suggested: CLAUDE.md. Triage: Protocol (promoted from a project pattern to an explicit requirement, new §20, 2026-09-29).

**L-028 — A config mistake can look exactly like a code defect; per-client diagnostic logging is what tells them apart, not a plausible-sounding guess.**
Evidence: a DL-010 non-happy-path test (populated dungeon, combat, 2026-09-28) showed a door stuck closed for 8s despite a correct identity match (no DL-014-style Target mismatch), then opening cleanly on retry — a pattern that could easily have been misdiagnosed as a game-side click miss or a new code bug. Reading both clients' logs side by side showed the real cause: the developer had forgotten to set `door_role=secondary` on one character before the run, so both clients clicked the same door within 0.3s of each other; the log line `Door role set to secondary`, fired mid-run when the developer corrected it live, pinpointed the exact moment the symptom stopped. Without that log line and the side-by-side comparison, this would have been an unexplained one-off.
Area: Technical. Suggested: Protocol (reinforces §4/§15 — don't guess at a cause, check the evidence) or CLAUDE.md. Triage: Protocol (added to §8 — diagnostics should be designed to distinguish operator/config error from a code defect, 2026-09-29).

## 2026-09-29 (release retrospective — found while preparing to triage the log above)

**L-029 — Documentation can go stale for weeks with nothing forcing a re-read; a sweep has to be a named practice, not an incidental byproduct of updating whatever's already in view.**
Evidence: the v1.0 release pass found Sections 3, 8, 14, and 21 of the spec still describing DL-001, DL-002, DL-004, and DL-005 as unfixed "confirmed gap"/"fix required" items, weeks after each had actually shipped and been live-verified. Nothing short of a dedicated end-to-end re-read (prompted only by the release itself) caught this — every earlier session had updated the decision log and ledger correctly but never circled back to the spec prose describing the original problem.
Area: Process. Suggested: Protocol (new §18). Triage: Protocol.

**L-030 — Work done outside the current repo/session doesn't go through the decision log just because it eventually gets merged back in.**
Evidence: the UI redesign (DL-015) was built in a separate repository (`PTAutoRoute-UI-Redesign`) across a separate session, with zero decision-log or lessons-log entries of its own for any of its choices (removing the Close buttons, removing the standalone Save button, the new dirty-edit tracking). Only a same-day functional-parity review, initiated for an unrelated reason (merging it in before release), caught this — the developer independently confirmed it was "a genuine oversight" once asked.
Area: Process. Suggested: Protocol (new §19). Triage: Protocol.

**L-031 — Session boundaries should follow a fixed external cadence (a work day), not "keep going while it's going well"; the project ledger's cold-start sufficiency is untested until a session boundary actually forces a cold start.**
Evidence: this entire project, from the rebaseline discussion through the v1.0 release, ran in a single continuous chat session spanning multiple real-world days, relying on the conversation's own memory rather than ever needing the decision log/ledger to carry state across a fresh start — which is the exact scenario Protocol §11 assumes will happen routinely. A milestone-based split ("end the session when this decision log entry is done") was considered and rejected as the primary rule, because judging "is this done yet" is itself the kind of in-the-moment call that gets skipped when momentum is good — which is how this session became one continuous thread in the first place. A daily boundary, aligned with an existing daily-retrospective habit, is unambiguous and doesn't depend on that judgment call.
Area: Process. Suggested: Protocol (new section, near §11). Triage: Protocol.

## 2026-10-02 (post-1.0, DL-017 live testing)

**L-032 — Departing from an approved mockup is a design change even when it is a single styling detail; it must be raised before building, not labeled an implementation choice and disclosed afterward.**
Evidence: DL-017's approved UI mockup showed the Mode toggle as two buttons. I built them without a selected-state highlight (avoiding an `ImGui.PushStyleColor` call this codebase had never used) and added a "(Solo selected)" text readout instead. I recorded that in the decision log as an implementation choice, after the fact. The developer, when the clumsiness came up, pointed out that this changed an approved design under the label of an implementation choice. The unfamiliar-API worry was a reasonable *reason* to raise the question, not authority to decide it.
Area: Process. Suggested: Protocol (§3/§14: a deviation from an approved mockup or acceptance criterion is a question for the developer, however small). Triage:

**L-033 — Status lines and summaries go stale one build at a time; a sweep has to follow every build, not only releases.**
Evidence: after the DL-016/017/018 builds (`1.1.0-test.1` to `test.10`) a sweep requested by the developer ("your bookkeeping is getting sloppy") found: DL-016/017/018 status lines still saying "local validation only / nothing live-tested" or naming an old build; DL-018's requirements 2, 4 and 5 still reading as originally approved with the developer's later changes recorded only in a note at the bottom; the ledger's "Up next" paragraph and Pending Live Verification header citing `test.2` and 184 tests; no ledger entry for DL-018 at all; a live confirmation (compact status showing during a run) never recorded; `CLAUDE.md` missing three modules, listing 13 phases and 8 statuses when the code has 18 and 9, and describing `PTARSettings` without its newer fields; and one backlog entry I wrote that misattributed my own oversight to the developer. Each was a small, locally reasonable omission made while the real work was in view; none was caught by the tests.
Area: Process. Suggested: Protocol (§18's documentation sweep, applied per build and not only at release; plus: a superseded requirement is marked inline where it is read, not only in a later note). Triage:

**L-034 — When two approved items conflict, raise the conflict; do not resolve it silently, and do not let a later "Perfect" on the whole build stand in for approval of the unraised choice.**
Evidence: the compact Pause/Resume button (DL-018). Approved requirement 6 (label changes between Pause and Resume) and the developer's later requirement (Full Mode's position stays fixed) conflict. I gave the button a fixed width without asking, disclosed it in the build message after the fact, then recorded it in the decision log under "developer direction ... confirmed (Perfect)". The developer pointed out it was a change to an approved design made without discussion, then promoted into the record as a requirement, alongside misattributed documentation.
Area: Process. Suggested: Protocol (§3/§14: a conflict between approved items is a question for the developer; the log records only what the developer decided, and a reaction to a whole build is not approval of a choice that was not raised). Triage:

**L-035 — Check a literal in the code before writing it into acceptance criteria.**
Evidence: DL-023. I drafted "Clicking OK" as an acceptance criterion and then the developer approved it "including the OK button", but the live button reads "Got it" ([PTAR.lua](../lua/PTAR.lua)). Nothing broke because the developer decided the label stays, but the criteria text was wrong at the moment it was approved, and the developer had to ask what it currently said. Same pattern as L-032 (stating something about the code from memory).
Area: Process. Suggested: CLAUDE.md "Before building" (read the current visible text before quoting or restating it in a proposal). Triage:

**L-036 — A state the live tests never entered can hide a missing control; check every early `return` in draw code against the requirement.**
Evidence: DL-018 fix. `draw_compact_rows()` had `if not runner then return end` after the Route dropdown, which removed the Full Mode button when there was no runner (compact view, zone with no routes, fresh start). The DL-021 live checks of that zone always had a preserved runner, and `PTAR.lua`'s draw code is parse-checked only, so nothing exercised the no-runner state. Found by the developer on the first live run of `1.1.0-test.23`.
Area: Process. Suggested: CLAUDE.md "Before building" (for UI changes, list the states a view can be in, including "no runner", and run the stubbed draw check for each, not just the one being changed). Triage:

**L-037 — The process itself has a cost to the developer; look for the shortest path that still keeps every decision with the developer (retrospective, 2026-10-03).**
Evidence: the developer's retrospective feedback — "Sometimes it feels like a slog" — after v1.1.0. Measured from the repo: 128 commits between 2026-10-01 and 2026-10-03, 82 of them docs-only; DL-024 (the folder scan) alone took 16 commits, 12 of them "record requirement N" docs commits made one answer at a time, and about 14 conversational turns passed between the story and the first line of code. The developer's own example of the cost (2026-10-03, during the retrospective): "Propose two tests when one test will capture the information required to complete two tests... that's something you've done that's caused a bit of overtesting." A clear instance: after `1.1.0-test.24` I proposed Test A (compact view with no routes) and Test B (the Group-beta notice) as two separate live tests, though one start of PTAR with no `PTAR_Notice.txt`, in compact view, in a zone with no routes, shows both; the developer had earlier said the same of two other checks ("Both can be tested together. No reason to run two tests when one will suffice"). The developer also named the strength to keep: implementation is strong once the design is fully nailed down (tests first, mutation checks, stubbed runs, logging inspection).
Area: Process. Suggested: CLAUDE.md "Before building" and Protocol §6/§14 (concrete options proposed to the developer in the retrospective; none adopted until the developer decides). Triage:
