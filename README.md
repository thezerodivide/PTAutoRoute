# PTAutoRoute (PTAR)

PTAR is a MacroQuest Lua suite built specifically for Project Triune.

It automates the travel between a dungeon's entrance and a boss encounter: normal navigation, ground drops, water crossings, and doors, so a group doesn't have to hand-navigate every hallway and terrain gap on every run.

PTAR does not replace TAC, MQ2Nav, or any other tool. It orchestrates them for this one purpose.

## Features

- Records a route once, by walking it and capturing each waypoint as you go, then plays it back on demand
- Handles ground drops and water crossings where MQ2Nav has no coverage
- Coordinates door opening across a multi-character group without duplicate clicks
- Keeps every character on the same route within one waypoint of each other
- Pauses and resumes around combat automatically
- Can pause and resume Triune AutoCombat at specific waypoints
- Blocks Start/Resume while mid-drop, mid-swim, or mid-TAC-command to avoid an unrecoverable error
- Persists last-used route and settings per character/server
- Detailed diagnostic logging always on, with an optional in-game console echo

## How Route Capture and Playback Works

PTAR is two separate scripts.

The Editor records a route. It reads your character's live position, heading, and door target when asked, and writes that into a route file. It never moves you, clicks anything, targets, or fights.

The Runner plays a saved route back. It reads waypoints in order and, for each one, either navigates there with MQ2Nav or runs the special-case logic a waypoint needs:

```text
Waypoint type       What the Runner does
normal              /nav to the captured position
door                /nav to a stand-off point, then click/verify the door
traverse (ground)   manual forward movement through a navmesh gap, then a controlled fall
traverse (water)    manual forward movement, then descend/cross/ascend through the gap
finish              ends the route
```

A route needs a Finish waypoint, a Manual handoff waypoint, or a finish-configured door before the Runner will load it. Route files are plain data — a literal-only parser rejects any executable content, even in a hand-edited file.

## Installation

Copy:

```text
PTAR.lua
PTAR/
```

to your MacroQuest Lua directory.

Example:

```text
MacroQuest\lua\PTAR.lua
MacroQuest\lua\PTAR\
```

PTAR creates its own config and log folders the first time it runs:

```text
MacroQuest\config\PTAR\
MacroQuest\logs\PTAR\
```

You don't need to create these yourself.

## Basic Usage — Capturing a Route

1. Run the Runner with `/lua run PTAR`, then click **Open Editor** (or run `/lua run PTAR/PTAREditor` directly).
2. Click **New Route...**, enter a filename, name, and description, then **Create Route**.
3. Walk to the first point you want captured.
4. Pick a **Capture type** — Waypoint, Door, Finish, Ground drop, Drop into water, or Water crossing.
5. Click the capture button to record your current position.
6. Walk to the next point and repeat. The **Route Order** table shows every waypoint captured so far, in order.
7. Capture a **Finish** waypoint, mark a waypoint as **Manual handoff**, or set a door to a finish variant, before ending capture.

Typed fields (Label, Notes, Radius, and similar) need an explicit **Apply & Save** before they take effect. Captures, moves, and deletes save immediately on their own.

A door capture needs a confirmed live target first — click **Select Nearest Door** (or `/doortarget id <number>` yourself) and check the door info shown before capturing.

A ground drop or water crossing is captured in stages: departure, then ledge (if falling), then underwater target (if swimming), then exit. The same capture button walks through each stage in order.

## Basic Usage — Running a Route

1. Run `/lua run PTAR` and pick a route from the **Route** dropdown.
2. Choose a starting point — At Selected Waypoint, At Beginning Waypoint, or At Nearest Valid Waypoint — then click **Start**.
3. **Pause** and **Stop** work at any time, including mid-drop or mid-swim.
4. **Resume at nearest valid** finds the closest waypoint it can safely resume from. It does not resume the exact interrupted step, because PTAR's routes cross navmesh gaps by design and the exact step may no longer be reachable from wherever you ended up.

If Start or Resume are grayed out, PTAR is finishing a drop/swim or a TAC command. Both clear on their own within a few seconds. Pause and Stop are never blocked by this.

## Multi-Character Coordination

Running the same route on more than one character at once needs one setting: **Door Opening Role**, in the Runner's Settings.

Exactly one character in the group should be set to **Primary**. Everyone else should be **Secondary**. The Primary clicks doors; Secondaries wait for the Primary's confirmation instead of clicking themselves. If more than one character is left set to Primary, a door can get stuck for several seconds before recovering on retry.

Waypoint synchronization needs no setting. Every character running the same route waits for the others at each waypoint before continuing, so nobody gets far enough ahead to pull a fight alone.

## Triune AutoCombat Integration

A route waypoint can optionally tell PTAR to pause or run TAC.

PTAR only uses:

```text
/ac status
/ac pause
/ac run
```

It does not use a bare `/ac`. Every command is verified through `/ac status` before PTAR trusts it, not through TAC's own acknowledgement.

This is opt-in per waypoint. A route with no TAC events makes zero TAC commands and behaves exactly as if the feature didn't exist.

## Safety

PTAR is intentionally conservative.

It does not:

- Move, click, target, or fight from the Editor, under any circumstance
- Generate, install, or repair a navmesh
- Fall back to manual movement for an ordinary waypoint that has navmesh coverage
- Retry a stalled ground drop or water crossing — a stall fails that leg outright, since the manual-movement path exists only because no other option was viable there
- Let a Secondary character click a door, under any circumstance, including its own timeout
- Auto-migrate a route file written in an older format — an unsupported version is rejected, never silently edited
- Expose user-adjustable retry/timeout values — those are implementation choices, changed only through reviewed code, not a settings panel

Saves are atomic everywhere: a `.tmp` file is written and verified before it replaces the real file, and a `.bak` copy is kept.

## Logging

Diagnostic logging is always on, in full detail, not just for errors.

Logs are written to:

```text
MacroQuest\logs\PTAR\PTAR_<server>_<character>.log
```

rotating to `.old` when a log file gets large.

An optional **Console debug** toggle also echoes the same detail to your in-game console. Turning it off only affects the console; the log file is unaffected.

## Commands

```text
/lua run PTAR
/lua run PTAR/PTAREditor
```

## Version

Current release:

```text
v1.0.0
```

## Compatibility

PTAR was written and tested specifically for Project Triune. Behavior on other EverQuest servers, emulators, or progression environments is not supported or guaranteed.

## Disclaimer

Use at your own risk.

PTAR is designed to fail a leg outright rather than guess when it can't verify what it needs — a missing navmesh, an unreachable door, a stalled drop — but EverQuest automation always carries some risk, including from the underlying game client, MacroQuest, MQ2Nav, and TAC.

## Wanting more detail

This README covers what you need to capture and run a route. For the full behavioral specification, the reasoning behind specific design decisions, and the history of what's been tested and how, see:

- [`docs/PTAR_Rebaseline_Spec.md`](docs/PTAR_Rebaseline_Spec.md) — the full specification.
- [`docs/decision_log.md`](docs/decision_log.md) — why specific behaviors work the way they do, with the evidence behind each one.
- [`docs/project_ledger.md`](docs/project_ledger.md) — current state: what's confirmed, what's still open.
