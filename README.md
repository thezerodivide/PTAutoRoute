# Project Triune AutoRoute — v0.2-test5

Project Triune AutoRoute (PTAR) lets you record a path through a zone and have one character follow it with MacroQuest's MQ2Nav. A path is called a **route**. It consists of labeled **waypoints**: places to visit in order, doors to open, and a place to finish or hand movement back to you.

This is a **test build**. It includes a route through part of Sleeper's Tomb and a route editor for making your own routes. The included route has been tested from the entrance to the first drop handoff. The runner does **not** automate drops in this version. Water can be part of a route when MQ2Nav has a usable path through it; the included Sleeper's Tomb route stops before its first drop because of navmesh gaps.

PTAR runs as a separate Lua alongside **Triune Auto Combat (TAC)**. TAC is **required for this test setup**: PTAR handles route movement while TAC handles combat. PTAR is not a TAC plugin and does not change TAC's files.

## What you need

- MacroQuest with Lua and ImGui support.
- Triune Auto Combat (TAC) installed and running. The route character uses **Manual** mode; followers use **Assist - Chase**.
- MQ2Nav loaded and a usable navmesh for the zone you want to run. PTAR cannot cross an area where MQ2Nav has no path.
- The `v0.2-test5` ZIP, including its `lua` and `config` folders. No extra Lua package installation is required.

Set TAC to **Manual mode** on the character running PTAR and start TAC before starting the route. For a group, run **one copy of PTAR on the route character only**. On each follower, set TAC to **Assist - Chase**, set its MA (main assist) to the PTAR character, and start TAC. PTAR does not configure, start, pause, or change TAC for you.

## Install the test build

1. Extract the ZIP. Open the extracted `lua` folder and copy **the files inside it** into MacroQuest's base `lua` folder. `PTAutoRoute.lua`, `PTAREditor.lua`, and the `PTAR*.lua` support files should all sit directly in that folder. Do not nest them in another PTAR folder.
2. Open the extracted `config` folder. Copy `PTAR_SleepersTombKera.lua` into MacroQuest's `config` folder. This is the included Sleeper's Tomb route. **Keep your existing copy if you have edited it**; copying the test route over it would replace your changes.
3. If MacroQuest's `config` folder does not yet contain `PTAR_Routes.txt`, copy the one from the ZIP. If it already exists, leave it in place and add `PTAR_SleepersTombKera.lua` on a line of its own if that line is missing. Do not replace an existing route list.
4. In game, run:

   ```text
   /lua run PTAutoRoute
   ```

The runner window title should say **Project Triune AutoRoute v0.2-test5**. The editor title should also show `v0.2-test5`. If you see an older version, check the files in the base `lua` folder. If pasting into the EQ client is inconvenient, put the command in an in-game macro and run that macro.

### What the files are for

| File | Purpose |
| --- | --- |
| `lua/PTAutoRoute.lua` | Opens the runner window. |
| `lua/PTAREditor.lua` | Opens the route capture and editing window. |
| Other `lua/PTAR*.lua` files | Shared route, navigation, file list, and logging code used by the two windows. Keep them together. |
| `config/PTAR_SleepersTombKera.lua` | Included route data: labels, locations, doors, and the handoff. |
| `config/PTAR_Routes.txt` | List of route filenames offered in the dropdown. A route file must be in `config` **and** listed here to appear. |

## First run: the included Sleeper's Tomb route

1. Enter Sleeper's Tomb on the route character and confirm MQ2Nav has a mesh loaded. Set TAC on that character to **Manual** and **start TAC**. If using followers, set each one's TAC to **Assist - Chase**, set its **MA** to the character running PTAR, and **start TAC** on each follower. Run PTAR only on the route character.
2. Run `/lua run PTAutoRoute`. In the **Route** dropdown, choose **Sleeper's Tomb - Kera Route**. If you just installed or edited a route and do not see it, click **Refresh Routes**.
3. At the entrance, leave the first entry selected in **Start waypoint** and click **Start**. The dropdown displays labels as well as waypoint numbers and IDs; it is where you choose a deliberate starting point. **Start does not automatically choose the nearest waypoint.**
4. Watch the **Status**, message, and **Current** waypoint in the window. PTAR navigates to each waypoint in order, checks door waypoints, opens closed doors, and waits for them to finish opening before continuing.
5. When the window says **Manual handoff** at **Drop 1 Manual Handoff**, PTAR has stopped moving. Handle the remaining drops and sections without navmesh paths yourself. This is the intended end of automated movement for the included route in this test build.

The Sleeper's Tomb navmesh has known gaps near the drops and in the pools. The route includes later markers, but PTAR does not run those sections in the included route. This limitation comes from the missing paths and disabled drop automation; water in another zone can be navigable if its navmesh supports it. You can still use the editor to inspect the later markers; do not start the runner at a drop expecting automated descent.

### Starting partway through or recovering

- **Use Nearest Waypoint** starts the route immediately from the nearest waypoint that MQ2Nav reports reachable and that is near your current elevation. Use it when you are already somewhere on a navigable part of the route.
- **Resume (nearest valid)** makes a *new* nearest-reachable selection from your current position after a pause or error. It does not promise to return to the exact waypoint that was active before you paused. Check **Current** after resuming.
- **Pause** stops PTAR's movement. **Stop** stops it and resets the Start selection to the first waypoint. Closing the runner ends the Lua.
- If there is no reachable waypoint near your elevation, move to a place with a usable navmesh path before using nearest or Resume. In a pool with missing navmesh coverage, swim out manually.

In combat, PTAR waits when the character is marked in combat **or** has Auto Hater XTargets. It keeps its current waypoint and retry count. Once both signals have been clear for 1.5 seconds, it tries that waypoint again. If navigation stalls outside combat, PTAR retries a finite number of times, then may return to a previously reached waypoint. If recovery fails, the window reports an error and stops movement; use **Resume (nearest valid)** after resolving the problem.

## Current limitations of this test build

- **Navmesh gaps stop route movement.** PTAR sends destinations through MQ2Nav. If the mesh ends before the next waypoint, PTAR cannot walk across the missing section or create a path through it. It may retry and attempt to return to a previous known good waypoint, then report an error. Repair the mesh or move the character manually to navigable ground before resuming. A waypoint on the far side of a gap does not bridge the gap.
- **Automated drops are disabled.** The included Sleeper's Tomb route intentionally stops at the reachable Drop 1 handoff. PTAR does not step off ledges or perform landing and post-drop recovery in this build. Swimming is manual **where the navmesh lacks a usable water path**, including the affected pools on this route. In zones with complete water navmeshes, MQ2Nav can guide route movement through water. Capturing Drop Pre and Drop Post markers does not enable automated drops.
- **A route needs a path for each leg.** PTAR checks whether MQ2Nav can reach a waypoint and that the route is for the current zone. It cannot navigate to coordinates solely because they are listed in a route file. **Use Nearest Waypoint** and **Resume** also require a reachable waypoint near the character's elevation; they cannot choose a point across an inaccessible drop or pool.
- **Doors depend on the captured target.** The runner checks the saved door ID, name, and location before clicking. A changed or mismatched door target, a door too far away, or a missing Nav path may stop that leg. Verify the selected door when recording it and include the log if a door fails during a run.
- **Combat waiting uses two signals.** PTAR waits for `Me.Combat` or Auto Hater XTargets; it does not read TAC's internal combat state or manage TAC. If a character's combat is not reflected in either signal, include the log and describe what TAC and the character were doing.
- **A restart does not restore the exact active leg.** Start defaults to the first waypoint. After restarting, choose a labeled waypoint or use **Use Nearest Waypoint**. **Resume** also selects a new reachable waypoint from the current position.

## Make your own route

Open the editor from **New / Edit Route** in the runner, or run:

```text
/lua run PTAREditor
```

The editor records **the character's current location and heading at the moment you click Capture Selected Action**. Move the character to each place you want recorded before capturing it. Give each waypoint a useful label such as `Hall before north door`; those labels are shown in the runner. Capture waypoints in the order you want to travel. You must be in the route's zone to capture or replace a position.

### Create a route

1. Stand in the zone you want to map. On the editor's initial screen, enter a **New route name** and optional description. In **New route filename**, enter a short suffix such as `MyDungeon` and click **New Route**. PTAR creates `config/PTAR_MyDungeon.lua` for the current zone and adds it to `PTAR_Routes.txt`.
2. Move to the first location. In **Action**, choose **Add Waypoint**, enter a label, then click **Capture Selected Action**. Repeat as you move through the zone. A blank **Radius** uses the usual 15-unit arrival distance; you can enter a positive radius for a waypoint that needs a different arrival distance.
3. Add special actions where needed. Choose **Capture Door** for a door waypoint, or mark a normal waypoint **Manual handoff** to make PTAR stop there and let you take over. A complete navigable route needs a **Finish** waypoint or a **Manual handoff**. A Finish waypoint requires a positive Radius.
4. Captures and edits are saved as you make them. Check the editor's **Status**, messages, and validation errors. Once you are done, click **Refresh Routes** in the runner and select the new route.

### Capture a door

Make a normal approach waypoint before the door if the runner needs one. Then stand where the runner should arrive before opening it and:

1. Set **Action** to **Capture Door** and enter a label.
2. Click **Select Nearest Door**. This performs `/doortarget` for you. Read the displayed door name, ID, distance, and coordinates to make sure it selected the intended door or switch.
3. Click **Capture Selected Action**. The editor saves **your position** as the door waypoint and separately records the selected door's identity and position. Selecting a door alone does not capture a waypoint.

If several doors are close together, you can select one explicitly with `/doortarget id <number>` before capture. PTAR uses the saved identity when running; the label is there for you to recognize the waypoint.

### Edit a route

Choose a file in **Existing route**, then click **Load Route**. Click a row under **Route order** to edit it. You can commit metadata changes, replace the selected position with your current position, move the row up or down, delete it after confirmation, or undo the most recent creation. **Insert ... Before/After** actions use the selected row as their insertion point. The editor saves route changes to the route file and keeps a `.bak` copy when replacing a previous version.

To list a route file you already have in `config`, enter its filename in **Add existing route filename**, click **Add Existing Route**, then refresh the runner. New route filenames receive the `PTAR_` prefix automatically. The route list only determines what appears in the dropdown; the waypoint data lives in each route's `.lua` file.

**Drop Pre** and **Drop Post** markers can be recorded and paired by Drop ID, with water or ground landing metadata. The runner's drop automation is disabled in this build. Use a normal **Manual handoff** waypoint before a drop if you want the route to stop at a reachable approach.

## Debug logs and reporting a test result

**Verbose Debug starts ON** for this test build. The runner's button can turn it off or back on at any time. Each character writes a separate file in MacroQuest's `config` folder:

```text
PTAR_<server>_<character>.log
```

The log includes route and waypoint changes, Nav/path decisions, door identity and open state, retries, position, and the separate `meCombat`, `xtHaters`, and `effectiveCombat` readings. When it grows beyond 4 MiB, the previous log is retained as `.log.old`.

When reporting a problem, please include the log, the **v0.2-test5** window version, the zone and character role, the route and current waypoint label, what happened, and what you expected. A short description of TAC's modes on the route character and followers is helpful for group runs. This is especially useful when testing casters, characters who do not hold aggro, doors, and newly recorded routes.
