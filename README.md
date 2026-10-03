# PTAutoRoute (PTAR)

PTAR is a MacroQuest Lua suite built specifically for Project Triune.

It automates the travel between a dungeon's entrance and a boss encounter: normal navigation, ground drops, water crossings, and doors, so a group doesn't have to hand-navigate every hallway and terrain gap on every run.

PTAR does not replace TAC, MQ2Nav, or any other tool. It orchestrates them for this one purpose.

## Features

- Records a route once, by walking it and capturing each waypoint as you go, then plays it back on demand
- Handles ground drops and water crossings where MQ2Nav has no coverage
- Shows only the routes that start in the zone you're in, and remembers the last route you started in each zone
- Pauses and resumes around combat and Triune AutoCombat Med Breaks automatically
- Can pause and resume Triune AutoCombat at specific waypoints
- Blocks Start/Resume while mid-drop, mid-swim, or mid-TAC-command to avoid an unrecoverable error
- Solo mode by default; an optional Group mode (beta) coordinates door opening across a group and keeps every character within one waypoint of each other
- Full and Compact window modes
- Deletes a route you no longer need from the Editor
- Finds route files you copy into the config folder and adds them to the route list for you
- Persists your settings and your last-started route for each zone, per character/server
- Detailed diagnostic logging always on, with an optional in-game console echo

## How Route Capture and Playback Works

PTAR is two separate scripts.

The Editor records a route. It reads your character's live position, heading, and door target when asked, and writes that into a route file. It never moves you, clicks doors, targets monsters, or fights. The only command it sends is `/doortarget`, from Select Nearest Door, to select a door so it can read the door's details.

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

To delete a route you no longer need, pick it in **Existing route**, click **Delete Route**, and confirm in the popup. A delete is permanent: PTAR removes the route file, its `.bak` and `.tmp` copies, and its entry in the route list, and there is no undo. A Runner that already has the route loaded keeps running it from memory; click **Refresh Routes** in the Runner to update its list.

To add a route someone shared with you, copy the route file into `config\PTAR\`. PTAR looks for new route files when the Runner or the Editor starts and whenever you click **Refresh Routes**, and adds any it finds to the route list. A file that isn't a usable route (still being captured, or damaged) is added too and shows as **[INVALID]**, so you can see why it can't run. This uses LuaFileSystem (`lfs`). If it isn't installed on your computer, PTAR says so in the window, and you add each file yourself with **Register Route File...** in the Editor.

## Basic Usage — Running a Route

1. Run `/lua run PTAR`. The **Route** dropdown lists only the routes that start in the zone you're in, and PTAR loads one for you: the route you last started in this zone if it's still available, otherwise the first one alphabetically. If no route starts in this zone, it says `No routes available for this zone` and Start isn't available.
2. Choose a starting point — At Selected Waypoint, At Beginning Waypoint, or At Nearest Valid Waypoint — then click **Start**.
3. **Pause** and **Stop** work at any time, including mid-drop or mid-swim.
4. **Resume at nearest valid** finds the closest waypoint it can safely resume from. It does not resume the exact interrupted step, because PTAR's routes cross navmesh gaps by design and the exact step may no longer be reachable from wherever you ended up.

If Start or Resume are grayed out, PTAR is finishing a drop/swim or a TAC command. Both clear on their own within a few seconds. Pause and Stop are never blocked by this.

A route counts as your last-started route for its zone once a run actually starts moving. Selecting or loading a route doesn't change it.

In Full mode, a route in this zone that can't be run yet (still being captured, or invalid) appears greyed out and marked `[INVALID]`. Clicking it doesn't select it; it tells you why. Compact mode lists only routes that are ready to run.

**After you zone.** If a run has finished (or ended in an error, or you paused it) and you then change zones, its status stays on screen and the dropdown shows the new zone's route. That route loads when you select it or press Start, and **Resume at nearest valid** is unavailable until it does. Zone back to the original route's zone and it returns. A run that is still going when you change zones stops with a "Zone changed" error, unless the zone change is the route's own finish door.

### Compact window

Click **Compact** (top right) to shrink the window to the route, the status, and Start / Pause-Resume / Stop; click **Full Mode** to switch back. In Compact, **Start** always starts at the nearest valid waypoint, and the single **Pause/Resume** button pauses a running route and resumes a paused one. PTAR remembers which view you were using.

## Solo and Group Modes

PTAR runs in **Solo** mode by default. In Solo mode it behaves as the only PTAR in the group: it sends no group chat at all and never waits for anyone.

**Group (Beta)** is for running the same route on several characters at once. Group mode is still in beta and can behave unexpectedly in some situations; Solo is the most reliable choice. The first time you run PTAR on a computer, a notice explains this once. It appears again only when a new major or minor release (for example 1.2) ships while Group is still in beta; patch releases don't repeat it.

Switch modes with the **Solo** and **Group (Beta)** buttons at the top of the Runner's Full view. You can only switch while PTAR isn't running a route — Pause or Stop first. The setting belongs to one character and never affects another character's PTAR.

In Group mode, one setting matters: **Door Opening Role**, in the Runner's Settings.

Exactly one character in the group should be set to **Primary**. Everyone else should be **Secondary**. The Primary clicks doors; Secondaries wait for the Primary's confirmation instead of clicking themselves. If more than one character is left set to Primary, a door can get stuck for several seconds before recovering on retry.

Waypoint synchronization needs no setting. In Group mode every character running the same route waits for the others at each waypoint before continuing, so nobody gets far enough ahead to pull a fight alone.

## Triune AutoCombat Setup

Leave TAC in **Manual** mode on every character before running PTAR, and keep it there.

In Manual mode you move and pick targets, and TAC attacks, casts, heals, and uses abilities — it never moves your character on its own. Any other mode (Assist-Chase, Puller, and so on) fights PTAR for control of movement, and modes like Assist-Chase can't follow through the navmesh gaps PTAR's drops and crossings exist to cross in the first place. PTAR itself never starts, stops, or switches TAC's mode; that's on you, once, before Start.

If you use TAC's **Med Break**, PTAR stops while the break is active, shows **Waiting for med break**, and carries on toward the same waypoint once TAC says the break is over (or PTAR sees your character stand up). Combat and a med break never both let PTAR move: if one ends while the other is still active, PTAR keeps waiting. One limitation: if you switch TAC out of Manual mode in the middle of a med break, PTAR has no way to see the break end, and stays paused until you Stop or Resume yourself. In Group mode, a groupmate's med break also holds the waypoint wait (part of the Group beta).

With TAC in Manual, a route waypoint can optionally tell PTAR to pause or run TAC for that stretch of the route.

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

Deleting a route from the Editor always asks for confirmation first, and removes the route from the list before it deletes the files, so a failure part-way is reported rather than hidden.

## Logging

Diagnostic logging is always on, in full detail, not just for errors.

Logs are written to:

```text
MacroQuest\logs\PTAR\PTAR_<server>_<character>.log          (the Runner)
MacroQuest\logs\PTAR\PTAR_Editor_<server>_<character>.log   (the Editor)
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
v1.1.0
```

## Compatibility

PTAR was written and tested specifically for Project Triune. Behavior on other EverQuest servers, emulators, or progression environments is not supported or guaranteed.

## Disclaimer

Use at your own risk.

PTAR is designed to fail a leg outright rather than guess when it can't verify what it needs — a missing navmesh, an unreachable door, a stalled drop — but EverQuest automation always carries some risk, including from the underlying game client, MacroQuest, MQ2Nav, and TAC.

## Wanting more detail

This README covers what you need to capture and run a route. For every option the Editor and Runner expose — including the less obvious ones, like what happens if you change an existing traversal waypoint's type — see:

- [`docs/Advanced_User_Guide.md`](docs/Advanced_User_Guide.md) — the full option reference, field by field.

For the behavioral specification, the reasoning behind specific design decisions, and the history of what's been tested and how, see:

- [`docs/PTAR_Rebaseline_Spec.md`](docs/PTAR_Rebaseline_Spec.md) — the full specification.
- [`docs/decision_log.md`](docs/decision_log.md) — why specific behaviors work the way they do, with the evidence behind each one.
- [`docs/project_ledger.md`](docs/project_ledger.md) — current state: what's confirmed, what's still open.
