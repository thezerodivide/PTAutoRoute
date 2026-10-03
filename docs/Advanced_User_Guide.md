# PTAR Advanced User Guide

The [README](../README.md) covers enough to capture and run a basic route. This guide covers every option the Editor and Runner expose, what each one does, and the sharp edges worth knowing about before you rely on them. If you only need the quick start, you don't need this document.

## Editor — Routes panel

- **Existing route** — a dropdown of every route in `config/PTAR/PTAR_Routes.txt`. PTAR adds route files it finds in the folder to that list at startup and on **Refresh Routes** (see [Route folder scan](#route-folder-scan)).
- **Load Route** — loads the route selected in the dropdown. Refused while a route is loaded and unsaved (fix or save it first), or while a traversal capture is in progress.
- **Refresh Routes** — looks in the config folder for route files that are not in the list yet and adds them (see [Route folder scan](#route-folder-scan)), then rebuilds the dropdown list.
- **Delete Route** — deletes the route selected in the dropdown, after you confirm in a popup titled **Delete Route** (it shows `File Name: <filename>` with **Confirm Delete** and **Cancel**; Cancel, or closing the Editor, changes nothing). The route's entry in `PTAR_Routes.txt` is removed first, then the route file and its `.bak` and `.tmp` copies. On success the Editor says `Delete confirmed: <filename> has been deleted. Refresh Routes in the Runner to update its list.`, refreshes its own list, and — if that route was the one open in the Editor — unloads it, dropping any unsaved edits. If the list can't be updated, nothing is deleted; if the route file itself can't be deleted, the route has already left the list and the Editor tells you to use **Register Route File** to bring it back (the file is still in the folder, so the next scan adds it back too — delete the file by hand to remove it for good); if a `.bak` or `.tmp` can't be removed, the Editor names it so you can delete it by hand. A delete can't be undone. It never affects a Runner that already has the route loaded: that Runner keeps running it from memory until it loads something else or PTAR restarts. The Existing route dropdown lists every registered route regardless of zone.
- **New Route...** — expands a filename/name/description form and a **Create Route** button. The filename gets a `PTAR_` prefix automatically if you don't include one.
- **Register Route File...** — for a route file that already exists in `config/PTAR/` but doesn't show up in the Existing route dropdown, for example when the folder scan is unavailable because LuaFileSystem is missing. Registering adds it to the index without touching its contents.

## Route folder scan

PTAR keeps its routes in a list, `config/PTAR/PTAR_Routes.txt`. The Runner and the Editor both scan the config folder for route files that are not in the list yet and add them, so a file copied in by hand needs no registering:

- **When:** when the Runner or the Editor starts, and when you click **Refresh Routes** in either one. Creating, registering, loading or deleting a route does not scan. In the Runner, the button's usual refusal while Running, Recovering or Waiting for combat applies, and no scan runs then.
- **Which files:** a file named `PTAR_<letters, digits, _ or ->.lua` (and the two older `SleeperTombRoute` names PTAR already accepts) that is not already listed. `.bak`, `.tmp` and any other file are ignored.
- **Damaged or unfinished files** are added too. The Editor labels them invalid, and the Runner lists the ones for your zone as greyed `[INVALID]` entries (a file whose zone can't be read is hidden from the Runner and written to the log).
- **Add only:** the scan never removes or edits a list entry and never changes a route file. An entry whose file is gone stays until you delete it with Delete Route.
- **What you see:** `Added 2 route files to the route list: PTAR_A.lua, PTAR_B.lua.` (`Added 1 route file ...` for one; with more than three, the first three then `and N more`), only when something was added. It shows in the Runner's message line (Full view) and the Editor's message line, and a later message replaces it. At Runner startup, loading the zone's default route replaces it at once; the log still names every file added.
- **If the list can't be updated** (for example another PTAR is writing it at that moment): `Could not update the route list: <error>. Refresh Routes to try again.` Nothing is lost; the next scan finds the file again.
- **LuaFileSystem (`lfs`)** does the folder listing. If it isn't installed, the scan is skipped and PTAR says `Route folder scan unavailable: LuaFileSystem (lfs) is not installed. New route files will not be found automatically; register them in the Editor.` (in the Editor: `... register them with Register Route File...`). Everything else works as before, and Register Route File... still adds a file.
- The Runner log (and the Editor log) records each scan: the folder, how many matching files it found, how many were already listed, each file added, and any failure.

## Saving model

Two different things happen when you interact with the Editor, and they're **not** the same:

- **Captures, moves, deletes, and route-order changes save immediately.** You never need to press anything extra for these.
- **Typed fields need an explicit apply.** Anything you type into a text box (Label, Notes, Radius, door coordinates, the route's Name/Description, and so on) stays local to the form until you click **Apply Route Details & Save** or **Apply Waypoint Edits & Save**. Until then you'll see "Typed changes have not been applied," and the Editor blocks capturing a new waypoint or switching routes until you either apply or click **Discard Typed Changes**.

If a save ever fails, whatever you were trying to apply is rolled back in memory to match what's actually on disk — the Editor won't let its in-memory state drift from the saved file. **Retry Save** appears specifically when a save has failed, or succeeded but couldn't be added to the route index.

## Capture types

The **Capture type** dropdown offers six kinds. All except the three traversal presets also get a separate **Placement** dropdown (append at the end, insert before the currently selected waypoint, or insert after it) — traversal waypoints don't get a placement choice; they're always inserted right after whatever waypoint was selected when you started the capture, or appended if nothing was selected.

| Capture type | Produces | Notes |
|---|---|---|
| Waypoint | a `normal` waypoint | Ordinary travel point. |
| Door | a `door` waypoint | Needs a confirmed live door target before capture — see Door capture below. |
| Finish | a `finish` waypoint | Ends the route. |
| Ground drop | a `traverse` waypoint, ground preset | Captured in stages — see Traversal capture below. |
| Drop into water | a `traverse` waypoint, water-drop preset | Captured in stages, includes an underwater leg. |
| Water crossing | a `traverse` waypoint, water-crossing preset | Same as above without the initial fall. |

Common fields on every capture:

- **Label** — required to be non-empty when you actually create the waypoint (traversal captures require it up front, before the first stage).
- **Notes** — free text, optional.
- **Radius** — the arrival tolerance. Leave blank for a sensible default on most types; a Finish waypoint requires an explicit radius. Traversal radius is capped at 5 and defaults to 3 if left blank.
- **TAC before / TAC after** — None, Pause TAC, or Run TAC. See the README's TAC section for what these actually do at runtime. This is available on every capture type, including traversals.

Capture is blocked outright if your current zone doesn't match the route's zone, and a capture at effectively the same spot as your last one (within 750 ms and 1 game unit) is silently ignored rather than creating a stray duplicate waypoint — if a click seems to have done nothing, this is usually why.

### Door capture

Before capturing a Door waypoint, you need a confirmed live door target: click **Select Nearest Door**, or run `/doortarget id <number>` yourself, then check the door info line shown under the capture form. Capture is refused if no valid target is selected.

**After door** controls what happens once the Runner opens this door during playback:

- **Continue to next waypoint** — the normal case.
- **Finish upon open** — the route ends once this door is confirmed open.
- **Click door, then finish after zoning** — for a door that zones you; the route ends after the zone change completes.

### Traversal capture (ground drop / water drop / water crossing)

A traversal isn't captured in one click. The same capture button walks you through a fixed sequence, and the message line always says what it expects next:

1. **Departure** — your position and heading when you click the first time. This is also when Label, Notes, Radius, the underwater/exit radius fields, and TAC before/after are locked in for this waypoint.
2. **Ledge** — only for presets with a fall (ground, and drop-into-water). Your position right before you fall.
3. **Underwater target** — only for water presets. The Editor refuses this step unless `FeetWet` and `HeadWet` are both true, i.e. you're actually submerged.
4. **Exit** — your position once you're done. For water presets the Editor refuses this step unless `FeetWet` is false, i.e. you're back on dry ground.

**Cancel Traversal Capture** abandons the in-progress capture with no change to the route — use it if you started the wrong preset or need to reposition.

The underwater target radius field is hidden for the ground preset (it doesn't apply); the exit radius is required for every traversal preset.

## Route Order table

Every waypoint is listed in order, with its label, ID, type, distance from the previous waypoint, and its TAC Behavior (a plain-language summary of its TAC before/after fields). Click a row's label to select it for editing.

If you have unapplied typed edits on the currently selected waypoint and click a different row, the Editor won't silently discard your edits — it asks you to **Discard Edits & Switch** or **Stay Here**.

## Editing an existing waypoint

Selecting a row shows its saved position, your current live position, and distance from you, followed by editable fields: Label, Type, Notes, Radius, TAC before/after, and type-specific fields (below). Nothing here takes effect until you click **Apply Waypoint Edits & Save**.

**The Type dropdown only offers Waypoint, Door, and Finish — never Traverse.** You can freely convert a waypoint between those three types. But if you select an existing **traverse** waypoint and then pick any of those three types from the dropdown and apply, its phases, ledge, underwater target, and exit are all discarded permanently — there is no way to change a waypoint's type *into* or *out of* traverse through editing. If you need to change a traversal's geometry, delete it and capture it again; don't touch its Type field.

### Door fields (when editing a door waypoint)

The door's ID, name, and X/Y/Z are all directly editable text fields — useful for correcting a bad capture without redoing the whole waypoint. **Use Current Door Target** fills all five fields at once from whatever your live `/doortarget` is currently pointed at, the same source the capture-time door target uses.

### Traversal fields (when editing a traverse waypoint)

You can see and adjust the underwater target radius and exit radius. The phases, ledge position, underwater target position, and exit position themselves are read-only here — they were fixed at capture time and can only be changed by recapturing.

### Position, ordering, and deletion

- **Replace Position** — overwrites the waypoint's saved X/Y/Z/heading with your current live position, after a confirm step showing how far the old and new positions are apart. Useful for nudging a waypoint that turned out to be slightly off, without deleting and recapturing it.
- **Move Up / Move Down** — swaps the waypoint with its neighbor in route order. Saves immediately.
- **Delete Selected** — asks for confirmation, then removes the waypoint and saves immediately.
- **Undo Last Creation** — appears only immediately after a capture, and only undoes that one most recent capture. It's not a general-purpose undo history.

All four of these, along with the Type/other typed fields, are disabled while you have unapplied typed edits pending — apply or discard them first. Once a confirmation prompt (for Replace Position or Delete) is actually showing, though, its own Confirm/Cancel stay clickable regardless of what you type elsewhere afterward.

## What the Editor warns you about

After every save, the Editor re-validates the whole route and shows the result as `ERROR:`/`Warning:` lines. Warnings don't block saving; they flag things worth checking:

- **No Finish waypoint yet** / **Multiple Finish waypoints**
- **Finish is not last** — a Finish waypoint exists but isn't the final one, and no door before it is configured to end the route either
- **large spacing (N)** — two consecutive waypoints are more than 400 units apart, which often means a missed capture in between
- **Route ends with TAC paused (no later "run" event)** — the last TAC event in the route is a Pause with no matching Run afterward

Errors (missing required fields, an invalid radius, a malformed traversal, a duplicate waypoint ID, and similar) block the route from being considered valid, though the Editor still lets you keep working on it — a route with errors just can't be loaded by the Runner.

## Runner — every option

### Window and mode

- **Mode: Solo / Group (Beta)** — Solo (the default) sends no group chat and never waits for anyone; Group (Beta) coordinates doors and waypoint waits across a group. The selected button is highlighted. Switching is refused while a route is Running, Recovering, Waiting for combat or Waiting for med break (the buttons grey out and say "Pause or Stop to switch modes."). The setting is per character. A one-time notice about Group being in beta appears the first time PTAR runs.
- **Compact / Full Mode** — **Compact** (top right of the Mode row) switches to a small window with the Route dropdown, the status, and Start / Pause-Resume / Stop; **Full Mode** switches back. Compact shows no Mode buttons, settings, waypoint controls, messages or notices — switch to Full to see why something is greyed out. PTAR remembers the last view between sessions, restores your Full window size when you return to it, and remembers the Compact width within a session.

### Route list

- **Route** — lists only the routes that start in the zone you're in (the route's stored zone), sorted by route name (ignoring case), then file name. The route shown when you arrive is the one you last started in this zone if it's still available, otherwise the first valid route alphabetically. With none, it reads `No routes available for this zone` and Start is unavailable.
- **Invalid routes** — in Full mode, a route for this zone that can't be run (invalid, or still being captured with no Finish or Manual handoff) is listed greyed as `[INVALID] <name> [<zone>] — <file>`. Clicking one doesn't select it or change the loaded route; the notice line explains why. Routes whose zone can't be read at all never appear in the Runner (they still appear in the Editor, and each scan logs them). Compact mode lists only valid routes.
- **Switching routes** — selecting a route loads it. Selecting is refused while Running, Recovering or Waiting for combat — pause or stop first.
- **Refresh Routes** — first looks in the config folder for route files that are not in the list yet and adds them (see [Route folder scan](#route-folder-scan)), then re-scans the route files and re-applies the current zone: with no run in progress it loads this zone's default route, which replaces a route you had only selected and not started. Refused while Running, Recovering or Waiting for combat.
- **Last route per zone** — a route is remembered for its starting zone the first time a run actually starts moving (a navigation command, a door click, or traversal movement); failed start attempts, loading and selecting never change it. The old single "last route" setting is no longer used.
- **After you change zones** — PTAR watches your zone. With no runner, or a Ready one, it loads the new zone's default. After a Completed, Error, Manual handoff or Paused run, the old status and message stay, the dropdown shows the new zone's default, the Selected waypoint dropdown is disabled and says `Waypoints load when you select or Start this route.`, and **Resume at nearest valid** (and Compact's Pause/Resume) is disabled; selecting the route, or pressing Start, loads it (Start then starts it). Zone back to the loaded route's own zone and it returns with everything enabled. A run that is still going when you zone ends with a "Zone changed" error, or completes if you zoned through its finish door.

### Controls

- **Selected waypoint** — the waypoint used when the start method is "At Selected Waypoint." Until the displayed route has loaded, "At Selected Waypoint" starts at its first waypoint.
- **Start method** — At Selected Waypoint, At Beginning Waypoint, or At Nearest Valid Waypoint. Chosen once, then applied by clicking Start. In Compact, Start always starts at the nearest valid waypoint.
- **Start / Pause / Resume at nearest valid / Stop** — see the README for what each does. Start and Resume are the only two ever gated by a busy state (mid-traversal or mid-TAC-command); Pause and Stop are never blocked. In Compact, one **Pause/Resume** button reads "Pause" while a route is Running, Recovering, Waiting for combat or Waiting for med break, "Resume" while Paused, and is greyed in every other status.
- **Statuses** — Ready, Running, Recovering, Waiting for combat, Waiting for med break, Paused, Error, Manual handoff, Completed. While TAC is on a Med Break, PTAR shows Waiting for med break and does nothing until the break ends; combat and a med break never both let PTAR move.
- **Door Opening Role** — Primary or Secondary; shown only in Group mode (Solo shows two grey lines instead). See the README's Solo and Group Modes section; exactly one Primary per group. Your Group settings are kept while you're in Solo.
- **Console debug** — mirrors log detail to the in-game console. Does not affect what's written to the log file.

Every setting (mode, view, Console debug, Door Opening Role, and the last route started in each zone) persists per server/character and reloads automatically next time.
