# PTAR Advanced User Guide

The [README](../README.md) covers enough to capture and run a basic route. This guide covers every option the Editor and Runner expose, what each one does, and the sharp edges worth knowing about before you rely on them. If you only need the quick start, you don't need this document.

## Editor — Routes panel

- **Existing route** — a dropdown of every route file registered in `config/PTAR/PTAR_Routes.txt`. This is not the same as "every route file on disk" — see Register Route File below.
- **Load Route** — loads the route selected in the dropdown. Refused while a route is loaded and unsaved (fix or save it first), or while a traversal capture is in progress.
- **Refresh Routes** — re-scans the config folder and rebuilds the dropdown list.
- **New Route...** — expands a filename/name/description form and a **Create Route** button. The filename gets a `PTAR_` prefix automatically if you don't include one.
- **Register Route File...** — for a route file that already exists in `config/PTAR/` (copied in by hand, or shared by someone else) but doesn't show up in the Existing route dropdown. Registering adds it to the index without touching its contents.

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

- **Route** — pick any registered route. Switching routes, or refreshing the list, is refused while Running, Recovering, or Waiting for combat — pause or stop first.
- **Selected waypoint** — the specific waypoint used when the start method is "At Selected Waypoint."
- **Start method** — At Selected Waypoint, At Beginning Waypoint, or At Nearest Valid Waypoint. Chosen once, then applied by clicking Start.
- **Start / Pause / Resume at nearest valid / Stop** — see the README for what each does. Start and Resume are the only two ever gated by a busy state (mid-traversal or mid-TAC-command); Pause and Stop are never blocked.
- **Door Opening Role** — Primary or Secondary. See the README's multi-character section; exactly one Primary per group.
- **Console debug** — mirrors log detail to the in-game console. Does not affect what's written to the log file.

Every setting (last-used route, Console debug, Door Opening Role) persists per server/character and reloads automatically next time.
