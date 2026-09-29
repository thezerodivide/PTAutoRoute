# PTAR — Project Triune AutoRoute

A travel automation suite for **[Project Triune](https://nms.bestemu.com/)** EverQuest, running on [MacroQuest](https://macroquest.org/). PTAR gets your group from the entrance of a dungeon to the boss encounter you actually care about — normal navigation, ground drops, water crossings, and doors — so nobody has to babysit every hallway and terrain gap by hand. It doesn't replace TAC, MQ2Nav, or anything else you already use; it just orchestrates them for this one job.

---

## Install

1. Make sure you already have MacroQuest with Lua, ImGui, and MQ2Nav, and a loaded navmesh for the zone you'll be routing through — PTAR checks that a navmesh exists, it doesn't build or install one.
2. Drop the `PTAR` folder into your MacroQuest `lua` directory, so you end up with `lua/PTAR.lua` and `lua/PTAR/*.lua` alongside it. No build step, nothing else to install.

PTAR creates its own folders the first time it runs — you don't need to make these yourself:

- Routes: `<MacroQuest config>/PTAR/`
- Logs: `<MacroQuest logs>/PTAR/`

---

## First run: capture a route

PTAR is two separate windows. The **Editor** records a route by walking it once; the **Runner** plays a saved route back. You'll use the Editor once per route, then the Runner every time you want to run it.

1. Run `/lua run PTAR` to open the Runner, then click **Open Editor** (or run `/lua run PTAR/PTAREditor` directly).
2. Click **New Route...**, fill in a filename, name, and short description, then **Create Route**.
3. Walk your character to the first point on the path you want captured.
4. Pick a **Capture type** — usually "Waypoint" for ordinary travel. Door, Finish, Ground drop, Drop into water, and Water crossing handle the special cases below.
5. Click the capture button (its label follows your Capture type — "Capture Waypoint", "Capture Door", etc.) to record your current position.
6. Walk to the next point and repeat. The **Route Order** table shows every waypoint in order with the distance between them — click a row's label to select it for editing or deleting.
7. Before you finish, capture a **Finish** waypoint, mark a waypoint as **Manual handoff**, or set a door's **After door** option to one of the finish variants. **A route needs one of these before the Runner will let you load it.**

A few things worth knowing while you're capturing:

- **Typed fields need an explicit save.** Type into a Label, Notes, Radius, or similar field and you'll see "Typed changes have not been applied" until you click **Apply Route Details & Save** or **Apply Waypoint Edits & Save** (or **Discard Typed Changes** to back out). Captures, moves, and deletes save themselves immediately — only typed edits need this extra step.
- **Doors need their live target confirmed before capture.** Click **Select Nearest Door** (or `/doortarget id <number>` yourself) and check the door info shown before capturing a Door waypoint.
- **Drops and crossings are captured in stages.** The same capture button walks you through departure → ledge (if you're about to fall) → underwater target (if you're about to swim) → exit, in that order, telling you what it expects next each time.

---

## Running a route

1. Run `/lua run PTAR` if it isn't already open, and pick your route from the **Route** dropdown.
2. Choose a starting point — **At Selected Waypoint** (pick one from the dropdown beside it), **At Beginning Waypoint**, or **At Nearest Valid Waypoint** — then click **Start**.
3. **Pause** and **Stop** always work, even mid-drop or mid-swim. To pick back up afterward, **Resume at nearest valid** finds the closest waypoint it can safely resume from, rather than the exact step you left off at — PTAR's routes cross navmesh gaps by design, so resuming the precise interrupted step isn't always possible.

Status and current waypoint are always shown. If Start/Resume are briefly grayed out, PTAR is finishing a drop/swim or setting TAC's state — both clear on their own in a few seconds; Pause and Stop are never blocked by this.

---

## Running with more than one character

| Setting | What it's for |
|---|---|
| **Door Opening Role** (Settings, in the Runner) | Set exactly **one** character to **Primary** and everyone else to **Secondary**. The Primary clicks doors; Secondaries wait for its confirmation instead of clicking themselves, so the group doesn't fight over the same door. |
| Waypoint sync | Automatic — no setting needed. Every character on the same route waits for the others at each waypoint, so nobody gets far enough ahead to pull a fight alone. |

---

## Settings

| Setting | What it does |
|---|---|
| **Console debug: ON/OFF** | Whether PTAR's detailed log lines also print to your in-game console. Everything is always written to the log file regardless of this setting. |
| **Door Opening Role** | See "Running with more than one character" above. |

---

## When something goes wrong

- **"Route is still being captured" when you try to load it?** The route has no Finish waypoint, Manual handoff waypoint, or finish-configured door yet — go back to the Editor and add one.
- **A door gets stuck for several seconds during a multi-character run, then recovers on retry?** Check every character's **Door Opening Role** — this almost always means more than one character was left set to Primary.
- **Fell through the world / a ground drop won't detect the fall?** Levitate breaks PTAR's fall detection (it watches your descent speed to know you're falling). Don't levitate right before a fall-based drop.
- **Need to see exactly what happened?** Every run is logged in full detail, not just errors — see "Where your files live" below.

---

## Where your files live

All paths are inside your MacroQuest folder.

| File | What it holds |
|---|---|
| `config/PTAR/PTAR_*.lua` | Your captured routes. |
| `config/PTAR/PTAR_Routes.txt` | The list of routes shown in the Route dropdown. |
| `logs/PTAR/PTAR_<server>_<character>.log` | Full diagnostic log for that character, rotating to `.old` when large. |
| `lua/PTAR.lua` | The Runner. |
| `lua/PTAR/PTAREditor.lua` | The Editor. |
| `lua/PTAR/*.lua` | Everything else the suite needs. |

---

## Known limitations

- **Levitating before a ground-drop waypoint breaks fall detection** (see "When something goes wrong").
- **Routes are locked to one zone** — a route can't span a zone line.
- **Routes are hand-captured, not generated** — there's no automatic pathing/route-discovery; you walk it once with the Editor.

---

## Wanting more detail

This README covers what you need to capture and run a route. For the full behavioral specification, the reasoning behind specific design decisions, and the history of what's been tested and how, see:

- [`docs/PTAR_Rebaseline_Spec.md`](docs/PTAR_Rebaseline_Spec.md) — the full specification.
- [`docs/decision_log.md`](docs/decision_log.md) — why specific behaviors work the way they do, with the evidence behind each one.
- [`docs/project_ledger.md`](docs/project_ledger.md) — current state: what's confirmed, what's still open.
