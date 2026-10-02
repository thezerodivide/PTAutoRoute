-- /lua run PTAR
local mq=require('mq')
local imgui=require('ImGui')
local data=require('PTAR.PTARRouteData')
local machine=require('PTAR.PTARRunnerCore')
local files=require('PTAR.PTARFiles')
local logger=require('PTAR.PTARLog')
local combat=require('PTAR.PTARCombat')
local path_setup=require('PTAR.PTARPaths')
local version=require('PTAR.PTARVersion')
local settings_mod=require('PTAR.PTARSettings')
local tac_module=require('PTAR.PTARTac')
local barrier_module=require('PTAR.PTARBarrier')
local door_match=require('PTAR.PTARDoorMatch')
local running=true
local filename=nil
local start_mode='selected'
local door_role='primary'
-- DL-017: Solo is the default for every installation, new or existing -- Group mode is currently beta. The
-- one-time notice modal's job is proof of notice, not enforcement (nothing forces the user to read it).
local mode='solo'
local seen_mode_notice=false
-- DL-018: 'full' (default) or 'compact'. full_size remembers the user's full-view window size when they go compact
-- so Full restores it; apply_size forces the window size for exactly one frame after a view switch.
local view='full'
local full_size={w=560,h=390}
local apply_size=nil
local COMPACT_SIZE={w=300,h=120}
local COMPACT_MIN_W=230
local COMPACT_ROUTE_MIN_W=240  -- compact Route dropdown: never narrower than this...
local full_route_w=nil          -- ...and never wider than the Route dropdown in full view (measured there)
local compact_w=nil              -- the user's compact window width, remembered when they leave compact view
local compact_min_w=nil         -- narrowest compact window: minimum dropdown and the whole button row, plus padding
local compact_pr_w=nil          -- fixed width of the compact Pause/Resume button, so Stop/Full Mode never shift
local constraints_logged=false
local compact_h=nil  -- content height measured at the end of the previous compact frame
local confirmed_doors={}
local choices={}
local runner,route
local notice='Select a route, then Start.'
local nav_owned=false
local function identity()
  local function read(fn) local ok,v=pcall(fn); return ok and v or 'unknown' end
  return read(function() return mq.TLO.EverQuest.Server() end),read(function() return mq.TLO.Me.Name() end)
end
local paths,path_error=path_setup.prepare(mq.configDir)
if not paths then error('PTAR directory setup stopped: '..tostring(path_error)) end
local function echo_fn(message) mq.print(message) end
local diag=logger.new(paths.logs,identity,mq.gettime,version.VERSION,echo_fn)

local function log(message)
  diag:event(message)
end
local function save_settings()
  settings_mod.save(paths.config,identity,{last_route=filename,echo_enabled=diag.echo,door_role=door_role,
    mode=mode,seen_mode_notice=seen_mode_notice,view=view})
end
mq.event('ptar_door_open',"#1# tells the group, '#2#'",function(line,sender,message)
  local id=tonumber(message:match('^PTAR:DOOR:(%d+):OPEN$'))
  if id and not confirmed_doors[id] then
    confirmed_doors[id]=true
    log('Door open confirmation received for door '..id..' from '..tostring(sender))
  end
end)
-- TAC status answers (DL-013). Pattern and query-active guard follow PTDeathRecovery; the logic is in PTARTac.
local tac=tac_module.new(log)
mq.event('ptar_tac_status','#*#[Triune] status: #1#, mode: #2#, burn: #3##*#',function(line,state,mode,burn)
  tac:on_status_line(line,state,mode,burn)
end)
-- Waypoint barrier (DL-010). Roster membership needs both group presence and a recent heartbeat; the heartbeat
-- carries no progress/waypoint/door information at all, by design -- its only job is roster liveness.
local barrier=barrier_module.new()
local HEARTBEAT_INTERVAL_MS=5000  -- first guess, not measured (Protocol section 15)
local ROSTER_EXPIRY_MS=15000      -- first guess, not measured (Protocol section 15)
mq.event('ptar_here',"#1# tells the group, 'PTAR:HERE'",function(line,sender)
  barrier:heartbeat(sender,mq.gettime())
end)
mq.event('ptar_waypoint_reached',"#1# tells the group, 'PTAR:WAYPOINT:#2#:REACHED'",function(line,sender,waypoint_id)
  barrier:record_reached(waypoint_id,sender)
end)
-- TAC med breaks (DL-016). My own break is detected locally from TAC's own console lines (the same mq.event
-- pattern already used for its /ac status line); whenever my own flag toggles, I announce it to the group so
-- everyone's barrier logic can defer on it, the same shape as the existing HERE/WAYPOINT:REACHED barks.
-- MEDBREAK_GRACE_MS: TAC prints the start line, then issues /sit a moment later -- the Sitting/Ducking fallback
-- (for the one silent-clear path that stands the character up, DL-016) is not trusted until this grace period
-- has passed, so it cannot fire on the brief window before /sit actually takes effect. First guess (Protocol s15).
local MEDBREAK_GRACE_MS=3000
local my_medbreak=false
local medbreak_started_at=nil
local function set_my_medbreak(active,now)
  if active==my_medbreak then return end
  my_medbreak=active; medbreak_started_at=active and now or nil
  local cmd='/g PTAR:MEDBREAK:'..(active and 'START' or 'END')
  -- DL-017: my own flag still toggles in Solo (it drives my own pause), but the announcement is a Group-mode
  -- coordination bark like the others, so it is not sent. Found live 2026-10-02: this send was missed at first.
  if mode=='solo' then log(cmd..' (Solo mode: not sent)'); return end
  log(cmd); mq.cmd(cmd)
end
mq.event('ptar_medbreak_start','#*#[Triune] Med Break -- #*#',function(line)
  set_my_medbreak(true,mq.gettime())
end)
mq.event('ptar_medbreak_over','#*#[Triune] Med Break over -- #*#',function(line)
  set_my_medbreak(false,mq.gettime())
end)
mq.event('ptar_medbreak_cancelled','#*#[Triune] Med Break cancelled -- #*#',function(line)
  set_my_medbreak(false,mq.gettime())
end)
mq.event('ptar_medbreak_group_start',"#1# tells the group, 'PTAR:MEDBREAK:START'",function(line,sender)
  barrier:mark_medbreak(sender)
end)
mq.event('ptar_medbreak_group_end',"#1# tells the group, 'PTAR:MEDBREAK:END'",function(line,sender)
  barrier:clear_medbreak(sender)
end)
local function coords(w) return string.format('locyxz %.3f %.3f %.3f',w.y,w.x,w.z) end
local function read_bool(fn)
  local ok,v=pcall(fn); return ok and v==true
end
local adapter={log=log}
function adapter.zone()
  local ok,v=pcall(function() return mq.TLO.Zone.ShortName() end)
  return ok and v or nil
end
function adapter.position()
  local ok,x,y,z=pcall(function() return tonumber(mq.TLO.Me.X()),tonumber(mq.TLO.Me.Y()),tonumber(mq.TLO.Me.Z()) end)
  if ok and x and y and z then return {x=x,y=y,z=z} end
end
function adapter.mesh() return read_bool(function() return mq.TLO.Navigation.MeshLoaded() end) end
function adapter.path(w)
  local yes=read_bool(function() return mq.TLO.Navigation.PathExists(coords(w))() end)
  diag:debug(string.format('PATH #%s %s => %s | from %s',w.id,w.label,tostring(yes),
    (function() local p=adapter.position(); return p and string.format('%.1f,%.1f,%.1f',p.x,p.y,p.z) or 'unavailable' end)()))
  return yes
end
function adapter.nav_active() return read_bool(function() return mq.TLO.Navigation.Active() end) end
local last_combat_signals
local function combat_signals()
  return combat.read(mq)
end
function adapter.combat()
  local s=combat_signals()
  local identities={}
  for _,entry in ipairs(s.entries) do identities[#identities+1]=entry:gsub(':hp=[^:]+','') end
  local signature=string.format('meCombat=%s xtHaters=%s xtSlots=%s activeXTargets=%d effectiveCombat=%s [%s]',
    tostring(s.me_combat),s.xt_haters and tostring(s.xt_haters) or 'unavailable',
    s.slots and tostring(s.slots) or 'unavailable',s.active_targets,tostring(s.active),table.concat(identities,', '))
  if signature~=last_combat_signals then
    log('Combat signals: '..signature..' ['..table.concat(s.entries,', ')..']')
    last_combat_signals=signature
  end
  return s.active
end
function adapter.nav(w)
  local cmd='/nav '..coords(w)..' dist='..tostring(w.radius or 15)
  log(cmd); nav_owned=true; mq.cmd(cmd)
end
function adapter.nav_stop()
  if nav_owned or adapter.nav_active() then log('/nav stop'); mq.cmd('/nav stop') end
  nav_owned=false
end
function adapter.face(heading)
  local command_heading=machine.face_heading(heading)
  log(string.format('FACE captured %.3f -> /face fast heading %.3f',heading,command_heading))
  mq.cmd(string.format('/face fast heading %.3f',command_heading))
end
function adapter.heading()
  local ok,value=pcall(function() return tonumber(mq.TLO.Me.Heading.Degrees()) end)
  return ok and value or nil
end
function adapter.forward(held) mq.cmd(held and '/keypress forward hold' or '/keypress forward') end
function adapter.vertical(direction,held)
  local angle=held and (direction=='down' and -75 or 75) or 0
  local command='/look '..tostring(angle)
  log(command); mq.cmd(command)
end
function adapter.wet()
  local ok,feet,head=pcall(function() return mq.TLO.Me.FeetWet(),mq.TLO.Me.HeadWet() end)
  if ok and type(feet)=='boolean' and type(head)=='boolean' then return feet,head end
  return nil,nil
end
function adapter.bearing(w)
  local ok,value=pcall(function()
    return tonumber(mq.TLO.Me.HeadingToLoc(string.format('%.3f,%.3f',w.y,w.x)).Degrees())
  end)
  return ok and value or nil
end
function adapter.door_state(w)
  local d=w.door; if not d then return nil end
  mq.cmd('/doortarget id '..tostring(d.id))
  local ok,id,name,x,y,z,distance,open=pcall(function()
    local t=mq.TLO.SwitchTarget
    return tonumber(t.ID()),t.Name(),tonumber(t.X()),tonumber(t.Y()),tonumber(t.Z()),tonumber(t.Distance3D()),t.Open()
  end)
  if not ok then return nil,'SwitchTarget query failed: '..tostring(id) end
  if not distance or distance>35 then
    return nil,string.format('Target mismatch: player too far from target (distance %s)',tostring(distance))
  end
  -- X/Y identity match only (PTARDoorMatch): some doors travel far in Z when they open (a portcullis-style
  -- gate, confirmed across multiple zones' MQ2Nav door data, 2026-09-28), so matching Z against the captured
  -- closed-state position produced a false mismatch on exactly this kind of door once it was open.
  local match_ok,match_detail=door_match.matches({id=id,name=name,x=x,y=y},d)
  if not match_ok then
    return nil,string.format('Target mismatch: %s (observed z=%s)',match_detail,tostring(z))
  end
  if open~=true and open~=false then return nil,'Open value unavailable: '..tostring(open) end
  -- z is diagnostic-only here (not part of the identity match), so it is formatted defensively: some doors
  -- travel far enough in Z that it is worth logging, and a missing/non-numeric read must not error the format.
  local zdisp=type(z)=='number' and string.format('%.2f',z) or tostring(z)
  diag:debug(string.format('DOOR target %s id=%d name=%s xyz=%.2f,%.2f,%s distance=%.1f open=%s',
    w.id,id,name,x,y,zdisp,distance,tostring(open)))
  return open
end
function adapter.door(w,click_even_if_open)
  local open,reason=adapter.door_state(w)
  if open==nil then log('Door click refused for '..w.label..': '..tostring(reason)); return false end
  if open and not click_even_if_open then return 'open' end
  log('DOOR CLICK '..w.id..' '..w.label); mq.cmd('/click left door'); return 'clicked'
end
-- DL-017: overridden at the read site, never mutated -- the stored Group-mode value is untouched by switching
-- modes, which is what makes "switching preserves/restores Group settings" free (nothing was ever overwritten).
function adapter.door_role() return mode=='solo' and 'primary' or door_role end
function adapter.door_confirmed(id) return confirmed_doors[id]==true end
function adapter.announce_door_open(id)
  local cmd='/g PTAR:DOOR:'..tostring(id)..':OPEN'
  if mode=='solo' then log(cmd..' (Solo mode: not sent)'); return end
  log(cmd); mq.cmd(cmd)
end
-- TAC control (DL-013): PTAR only pauses or runs TAC where a route's waypoints say so. The acknowledgement line
-- TAC prints is not treated as proof; the runner verifies through tac_query/tac_state.
function adapter.tac_command(command)
  local cmd=(command=='pause') and '/ac pause' or '/ac run'
  log('ACTION '..cmd..' (acknowledgement is not treated as proof)'); mq.cmd(cmd)
end
function adapter.tac_query()
  mq.flushevents('ptar_tac_status')
  tac:begin_query()
  log('ACTION /ac status (TAC state query)'); mq.cmd('/ac status')
end
function adapter.tac_state() return tac:take() end
-- Waypoint barrier (DL-010): roster is live group membership filtered to those with a recent heartbeat.
-- mq.TLO.Group.Member(i) enumerates OTHER group members, not the local character (live-confirmed 2026-09-28,
-- DL-010: Me.Name()=Kateri, Group.Members()=2, members Evelynne/Benedict, Kateri's own name never listed).
-- DL-017: an empty roster in Solo mode reuses check_barrier()'s already-tested "nobody to wait for, release
-- immediately" path (the same path a true solo run already took before Solo mode existed as a concept) --
-- no change needed in PTARRunnerCore.lua at all. medbreak_group_active() derives from this same roster, so
-- Solo mode also correctly never defers on a groupmate's med break, for the same reason.
function adapter.barrier_roster()
  if mode=='solo' then return {} end
  local candidates={}
  local ok,count=pcall(function() return mq.TLO.Group.Members() end)
  if ok and count then
    for i=1,count do
      local ok2,name=pcall(function() return mq.TLO.Group.Member(i).Name() end)
      if ok2 and name and name~='' then candidates[#candidates+1]=name end
    end
  end
  return barrier:active_names(candidates,mq.gettime(),ROSTER_EXPIRY_MS)
end
function adapter.barrier_seen(waypoint_id) return barrier:seen_names(waypoint_id) end
-- DL-017: the runner keeps calling this unconditionally either way (DL-010's "bark unconditionally on arrival"
-- invariant is untouched); Solo mode only suppresses the actual chat send, still logging what would have gone
-- out since that costs almost nothing and can still help read a log (developer's own call).
function adapter.barrier_announce(waypoint_id)
  local cmd='/g PTAR:WAYPOINT:'..tostring(waypoint_id)..':REACHED'
  if mode=='solo' then log(cmd..' (Solo mode: not sent)'); return end
  log(cmd); mq.cmd(cmd)
end
function adapter.barrier_clear() barrier:clear() end
function adapter.clear_door_confirmed(id) confirmed_doors[id]=nil end
-- DL-016: my own med break (local, from TAC's own console lines) versus the group-wide flag (mine or anyone's
-- still-active announced break, filtered by the same live roster barrier_roster() already computes).
function adapter.medbreak() return my_medbreak end
function adapter.medbreak_group_active()
  local active=barrier:medbreak_active_names(adapter.barrier_roster())
  return #active>0
end
-- Fallback end-detection for TAC's silent medBreakActive clears that still stand the character up (DL-016): if
-- my own break is still flagged active well past the grace period but I am no longer sitting/ducking, treat
-- that as an implicit end. Does not close the one remaining silent gap (switching TAC's own mode mid-break,
-- which does not stand the character up either) -- accepted as a known limitation, not solved here.
local function check_medbreak_stood(now)
  if not my_medbreak then return end
  if not medbreak_started_at or now-medbreak_started_at<MEDBREAK_GRACE_MS then return end
  local sitting=read_bool(function() return mq.TLO.Me.Sitting() end)
  local ducking=read_bool(function() return mq.TLO.Me.Ducking() end)
  if not sitting and not ducking then
    log('Med break end inferred: no longer sitting/ducking with no explicit end line seen')
    set_my_medbreak(false,now)
  end
end
local function snapshot()
  local p=adapter.position()
  local w=runner and runner.index and route.waypoints[runner.index]
  local function optional(fn) local ok,v=pcall(fn); return ok and tostring(v) or '?' end
  local heading=optional(function() return mq.TLO.Me.Heading.Degrees() end)
  local combat_state=combat_signals()
  local target=optional(function() return mq.TLO.Target.ID() end)
  local distance='?'
  if p and w then distance=string.format('%.1f',data.distance(p,w)) end
  local now=mq.gettime()
  return string.format('zone=%s route=%s status=%s phase=%s waypoint=%s lastGood=%s attempt=%s backtracked=%s pos=%s heading=%s dist=%s best=%s progressAgeMs=%s phaseAgeMs=%s navActive=%s mesh=%s meCombat=%s xtHaters=%s activeXTargets=%d xtSlots=%s effectiveCombat=%s xtEntries=[%s] target=%s',
    tostring(adapter.zone()),tostring(filename),runner and runner.status or 'none',runner and tostring(runner.phase) or 'none',
    w and (w.id..'/'..w.label) or 'none',runner and tostring(runner.last_good) or 'none',
    runner and tostring(runner.attempt+1) or 'none',runner and tostring(runner.backtracked) or 'none',
    p and string.format('%.2f,%.2f,%.2f',p.x,p.y,p.z) or 'unavailable',heading,distance,
    runner and tostring(runner.best) or 'none',runner and runner.progress_at and tostring(now-runner.progress_at) or 'none',
    runner and runner.started and tostring(now-runner.started) or 'none',
    tostring(adapter.nav_active()),tostring(adapter.mesh()),tostring(combat_state.me_combat),
    combat_state.xt_haters and tostring(combat_state.xt_haters) or 'unavailable',combat_state.active_targets,
    combat_state.slots and tostring(combat_state.slots) or 'unavailable',tostring(combat_state.active),
    table.concat(combat_state.entries,', '),target)
end
local function refresh_routes()
  local found,err=files.scan(paths.config)
  if not found then notice='Could not scan config routes: '..tostring(err); log(notice); return end
  choices=found
  local exists=false
  for _,entry in ipairs(choices) do if entry.file==filename then exists=true end end
  if not exists then filename=choices[1] and choices[1].file or nil end
  log('Route scan: '..#choices..' candidates; selected '..tostring(filename))
end
local function load_route()
  if runner and (runner.status=='Running' or runner.status=='Recovering' or runner.status=='Waiting for combat') then notice='Pause or Stop before loading another route.'; return end
  if not filename or not files.accept(filename) then notice='Select a route from the list.'; return end
  runner=nil; route=nil
  local path=paths.config..'/'..filename
  local loaded,err=data.read(path)
  if not loaded then notice='Load failed: '..tostring(err); return end
  local errors=data.validate(loaded)
  if #errors>0 then notice='Route invalid: '..table.concat(errors,'; '); return end
  local endpoint=false
  for _,w in ipairs(loaded.waypoints) do
    if w.type=='finish' or w.manual_handoff or w.door_after=='finish_open' or w.door_after=='finish_zone' then endpoint=true end
  end
  if #loaded.waypoints==0 or not endpoint then
    notice='Route is still being captured; add a Finish or Manual handoff waypoint before running.'; return
  end
  route=loaded; runner=machine.new(route,adapter)
  notice='Loaded '..route.route_name..' ('..#route.waypoints..' waypoints).\nLog: '..diag:path()
  log('Loaded '..path..' with '..#route.waypoints..' waypoints')
  diag:debug('Route load snapshot: '..snapshot())
  save_settings()
end
-- DL-018: right-align the next item. GetWindowWidth is used by other Project Triune scripts; if it is ever
-- unavailable the item simply follows the previous one on the same line.
local function right_align(offset)
  local ok,width=pcall(function() return imgui.GetWindowWidth() end)
  if ok and type(width)=='number' then imgui.SameLine(width-offset) else imgui.SameLine() end
end
-- ImGui reads that may return a vector or two numbers (TAC's own scripts tolerate both).
local function xy(a,b) if type(a)=='number' then return a,b end return a.x,a.y end
-- Switching views changes presentation only. Going compact remembers the full-view window size (read inside the
-- window, so call from draw()); going full restores it. The size is applied to exactly one frame.
local function set_view(target)
  if target==view then return end
  if target=='compact' then
    local ok,w,h=pcall(function() return imgui.GetWindowSize() end)
    if ok and type(w)=='number' and type(h)=='number' and w>0 and h>0 then full_size={w=w,h=h}
    else log('Could not read the full-view window size; Full will restore '..full_size.w..'x'..full_size.h) end
  else
    local ok,w=pcall(function() return (xy(imgui.GetWindowSize())) end)
    if ok and type(w)=='number' and w>0 then compact_w=w
    else log('Could not read the compact window width; compact will reopen at its default width') end
  end
  view=target; apply_size=target
  log('View set to '..target)
  save_settings()
end
-- Left and right edge of the last item, as offsets from the window's left edge (the unit SameLine takes), or nil.
local function last_item_extent()
  local ok,l,r=pcall(function()
    local origin=xy(imgui.GetCursorScreenPos())-imgui.GetCursorPosX()
    return xy(imgui.GetItemRectMin())-origin,xy(imgui.GetItemRectMax())-origin
  end)
  if ok and type(l)=='number' and type(r)=='number' then return l,r end
end
-- Route selector, shared by full and compact view so the guard and the load behave identically. In compact view
-- the dropdown takes the room the window gives it, between its minimum width and the full-view dropdown's width.
local function route_selector(compact)
  imgui.AlignTextToFramePadding(); imgui.Text('Route'); imgui.SameLine()
  if compact then
    local max_w=full_route_w or math.floor(0.65*(full_size.w-16))
    local width=COMPACT_ROUTE_MIN_W
    local ok,avail=pcall(function() return (xy(imgui.GetContentRegionAvail())) end)
    if ok and type(avail)=='number' then width=math.max(COMPACT_ROUTE_MIN_W,math.min(avail,max_w)) end
    imgui.SetNextItemWidth(width)
  end
  local display=filename or '(no routes found)'
  for _,entry in ipairs(choices) do if entry.file==filename then display=entry.label end end
  if imgui.BeginCombo('##runner_route',display) then
    for _,entry in ipairs(choices) do
      if imgui.Selectable(entry.label..'##'..entry.file,filename==entry.file) then
        if runner and (runner.status=='Running' or runner.status=='Recovering' or runner.status=='Waiting for combat') then
          notice='Pause or Stop before changing routes.'
        else filename=entry.file; load_route() end
      end
    end
    imgui.EndCombo()
  end
  local left,right=last_item_extent()
  if left and not compact then full_route_w=right-left end
  return left,right
end
-- Start with the method and waypoint chosen in full view; compact view calls this too.
local function do_start()
  if start_mode=='selected' then runner:start(runner.selected,mq.gettime())
  elseif start_mode=='beginning' then runner:start(1,mq.gettime())
  else runner:start_nearest(mq.gettime()) end
end
-- DL-018: compact view -- Route, Status, then Start / Pause-Resume / Stop / Full Mode. Deliberately quiet: no
-- messages, notices or block explanations (full view has them). Button positions do not depend on the window
-- or dropdown width.
local function draw_compact_rows()
  local combo_left=route_selector(true)
  if not runner then return end
  imgui.Text('Status: '..runner.status)
  local busy=runner:tac_busy() or runner:traversal_blocking()
  if busy then imgui.BeginDisabled() end
  local start_clicked=imgui.Button('Start')
  if busy then imgui.EndDisabled() end
  -- Frame padding is learned from the Start button (its width minus its text), then used to give Pause/Resume
  -- the width of its longest label whichever label it shows.
  if not compact_pr_w then
    local sl,sr=last_item_extent()
    local ok,tw_start=pcall(function() return (xy(imgui.CalcTextSize('Start'))) end)
    local ok2,tw_pr=pcall(function() return (xy(imgui.CalcTextSize('Pause/Resume'))) end)
    if sl and ok and ok2 and type(tw_start)=='number' and type(tw_pr)=='number' then
      compact_pr_w=tw_pr+(sr-sl-tw_start)
    end
  end
  imgui.SameLine()
  local pr=runner:pause_resume_state()
  local pr_labels={pause='Pause',resume='Resume',disabled='Pause/Resume'}
  local pr_off=(pr=='disabled') or (pr=='resume' and busy)
  if pr_off then imgui.BeginDisabled() end
  local pr_clicked
  if compact_pr_w then pr_clicked=imgui.Button(pr_labels[pr]..'##pr',compact_pr_w,0)
  else pr_clicked=imgui.Button(pr_labels[pr]..'##pr') end
  if pr_off then imgui.EndDisabled() end
  imgui.SameLine(); local stop_clicked=imgui.Button('Stop')
  imgui.SameLine(); local full_clicked=imgui.Button('Full Mode')
  local _,row_right=last_item_extent()
  if combo_left and row_right then compact_min_w=math.max(combo_left+COMPACT_ROUTE_MIN_W,row_right)+8 end
  -- DL-018 (developer, 2026-10-02): compact Start always starts at the nearest valid waypoint, ignoring the
  -- full-view start method and waypoint.
  if start_clicked then runner:start_nearest(mq.gettime()) end
  if pr_clicked then
    if pr=='pause' then runner:pause() elseif pr=='resume' then runner:resume(mq.gettime()) end
  end
  if stop_clicked then runner:stop() end
  if full_clicked then set_view('full') end
end
local function draw_compact()
  draw_compact_rows()
  -- Height follows the content (dead space below the buttons is waste); width stays user-resizable.
  local ok,y=pcall(function() return imgui.GetCursorPosY() end)
  if ok and type(y)=='number' and y>0 then compact_h=y+6 end
end
local function draw()
  if view=='compact' and compact_h then
    local ok,err=pcall(function()
      imgui.SetNextWindowSizeConstraints(ImVec2(compact_min_w or COMPACT_MIN_W,compact_h),ImVec2(10000,compact_h))
    end)
    if not ok and not constraints_logged then constraints_logged=true; log('Compact height lock unavailable: '..tostring(err)) end
  end
  if apply_size=='compact' then imgui.SetNextWindowSize(ImVec2(math.max(compact_w or 0,compact_min_w or COMPACT_SIZE.w),compact_h or COMPACT_SIZE.h),ImGuiCond.Always)
  elseif apply_size=='full' then imgui.SetNextWindowSize(ImVec2(full_size.w,full_size.h),ImGuiCond.Always)
  elseif view=='compact' then imgui.SetNextWindowSize(ImVec2(compact_min_w or COMPACT_SIZE.w,COMPACT_SIZE.h),ImGuiCond.FirstUseEver)
  else imgui.SetNextWindowSize(ImVec2(full_size.w,full_size.h),ImGuiCond.FirstUseEver) end
  apply_size=nil
  imgui.SetNextWindowPos(ImVec2(55,55),ImGuiCond.FirstUseEver)
  local open,visible=imgui.Begin('Project Triune AutoRoute v'..version.VERSION..'###Project Triune AutoRoute',true)
  if open==false then running=false end
  if visible then
    -- DL-017: shown once, ever, regardless of which mode is chosen. Proof of notice, not enforcement -- nothing
    -- forces the user to read it, per the developer's own framing ("we can only give you the information").
    if not seen_mode_notice then imgui.OpenPopup('Mode Notice') end
    -- A popup with no size set rendered as a narrow strip live (2026-10-02). Popups are not saved to the ini, so
    -- FirstUseEver (already used for the main window) applies on every open.
    -- Centered on the game window using ImGui.GetIO().DisplaySize, the same read TAC's own windows use; falls back
    -- to a fixed position if the display size cannot be read.
    local notice_w,notice_h=440,200
    local notice_x,notice_y=80,80
    local size_ok,display_w,display_h=pcall(function()
      local io=imgui.GetIO(); return io.DisplaySize.x,io.DisplaySize.y
    end)
    if size_ok and display_w and display_h and display_w>notice_w and display_h>notice_h then
      notice_x=(display_w-notice_w)/2; notice_y=(display_h-notice_h)/2
    end
    imgui.SetNextWindowSize(ImVec2(notice_w,notice_h),ImGuiCond.FirstUseEver)
    imgui.SetNextWindowPos(ImVec2(notice_x,notice_y),ImGuiCond.FirstUseEver)
    if imgui.BeginPopupModal('Mode Notice',nil) then
      imgui.TextWrapped('Group mode is currently in beta and can still behave unexpectedly in some situations. Solo mode is the default and the most reliable option.')
      imgui.TextWrapped('This setting is local to this character only. It never affects any other PTAR instance -- each one sets its own mode independently.')
      if imgui.Button('Got it') then
        seen_mode_notice=true; save_settings()
        imgui.CloseCurrentPopup()
      end
      imgui.EndPopup()
    end
    if view=='compact' then draw_compact() else
    imgui.AlignTextToFramePadding(); imgui.Text('Mode'); imgui.SameLine()
    local mode_busy=runner and (runner.status=='Running' or runner.status=='Recovering' or
      runner.status=='Waiting for combat' or runner.status=='Waiting for med break')
    if mode_busy then imgui.BeginDisabled() end
    local function mode_button(label,value)
      local selected=(mode==value)
      if selected then imgui.PushStyleColor(ImGuiCol.Button,0.2,0.55,0.25,1) end
      local clicked=imgui.Button(label)
      if selected then imgui.PopStyleColor() end
      if clicked and not selected then mode=value; log('Mode set to '..value); save_settings() end
    end
    mode_button('Solo','solo'); imgui.SameLine(); mode_button('Group (Beta)','group')
    if mode_busy then imgui.EndDisabled() end
    right_align(88); if imgui.Button('Compact') then set_view('compact') end
    if mode_busy then imgui.TextColored(1,0.8,0.2,1,'Pause or Stop to switch modes.') end
    route_selector()
    if imgui.Button('Refresh Routes') then
      if runner and (runner.status=='Running' or runner.status=='Recovering' or runner.status=='Waiting for combat') then notice='Pause or Stop before refreshing routes.'
      else refresh_routes(); load_route() end
    end
    imgui.SameLine(); if imgui.Button('Open Editor') then mq.cmd('/lua run PTAR/PTAREditor') end
    imgui.TextWrapped(notice)
    if runner then
      imgui.Separator()
      imgui.Text('Status: '..runner.status)
      imgui.TextWrapped(runner.message)
      local chosen=route.waypoints[runner.selected]
      local current=runner.index and route.waypoints[runner.index]
      imgui.Text('Current: '..(current and string.format('#%d %s',runner.index,current.label) or 'none'))
      local label=string.format('#%d %s [%s, %s]',runner.selected,chosen.label,chosen.type,chosen.id)
      imgui.AlignTextToFramePadding(); imgui.Text('Selected waypoint'); imgui.SameLine()
      if imgui.BeginCombo('##runner_start_waypoint',label) then
        for i,w in ipairs(route.waypoints) do
          local entry=string.format('#%d %s [%s, %s]',i,w.label,w.type,w.id)
          if imgui.Selectable(entry..'##'..w.id,runner.selected==i) then runner.selected=i end
        end
        imgui.EndCombo()
      end
      -- While PTAR is setting TAC (DL-013) or mid-traversal (DL-001), Start/Resume are unavailable;
      -- Pause and Stop stay enabled. Both `busy` reasons are read fresh from runner state every frame -- never
      -- from `runner.message` -- because the traversal block's old message-based note was found live (2026-09-28)
      -- to get silently overwritten within seconds by the traversal's own routine progress narration, making it
      -- easy to miss. `busy` is read once per frame so BeginDisabled/EndDisabled stay balanced, and clicks are
      -- acted on after EndDisabled so nothing between the pair can throw.
      local tac_busy=runner:tac_busy()
      local traversal_busy=runner:traversal_blocking()
      local busy=tac_busy or traversal_busy
      if tac_busy then
        imgui.TextColored(1,0.8,0.2,1,'PTAR is setting TAC. Starting or resuming is unavailable until it finishes. Pause and Stop still work.')
      elseif traversal_busy then
        imgui.TextColored(1,0.8,0.2,1,'PTAR is mid-traversal ('..tostring(runner.phase)..'). Starting or resuming is unavailable until this phase completes. Pause and Stop still work.')
      end
      if busy then imgui.BeginDisabled() end
      local start_clicked=imgui.Button('Start')
      if busy then imgui.EndDisabled() end
      imgui.SameLine()
      local start_labels={selected='At Selected Waypoint',beginning='At Beginning Waypoint',nearest='At Nearest Valid Waypoint'}
      imgui.SetNextItemWidth(220)
      if imgui.BeginCombo('##runner_start_method',start_labels[start_mode]) then
        for _,start_choice in ipairs({'selected','beginning','nearest'}) do
          if imgui.Selectable(start_labels[start_choice],start_mode==start_choice) then start_mode=start_choice end
        end
        imgui.EndCombo()
      end
      if start_clicked then do_start() end
      if imgui.Button('Pause') then runner:pause() end
      imgui.SameLine()
      if busy then imgui.BeginDisabled() end
      local resume_clicked=imgui.Button('Resume at nearest valid')
      if busy then imgui.EndDisabled() end
      if resume_clicked then runner:resume(mq.gettime()) end
      imgui.SameLine(); if imgui.Button('Stop') then runner:stop() end
      imgui.TextWrapped('Start uses the selected method and restarts the route. Resume finds the nearest reachable waypoint.')
    end
    imgui.Separator()
    imgui.Text('Settings')
    -- DL-017: a setting meaningful only in Group mode is hidden entirely in Solo mode, not shown read-only --
    -- a general rule (today's only example is Door Opening Role; a future group-only setting follows the same
    -- treatment without a fresh discussion).
    if mode=='group' then
      imgui.AlignTextToFramePadding(); imgui.Text('Door Opening Role'); imgui.SameLine()
      local role_labels={primary='Primary (only one client)',secondary='Secondary (all other clients)'}
      imgui.SetNextItemWidth(240)
      if imgui.BeginCombo('##door_opening_role',role_labels[door_role]) then
        for _,choice in ipairs({'primary','secondary'}) do
          if imgui.Selectable(role_labels[choice]..'##door_role',door_role==choice) and door_role~=choice then
            door_role=choice
            log('Door role set to '..door_role)
            save_settings()
          end
        end
        imgui.EndCombo()
      end
    else
      imgui.TextColored(0.6,0.6,0.6,1,'Heartbeat barks and waits for other PTAR clients: Off')
      imgui.TextColored(0.6,0.6,0.6,1,'Group settings saved for when you switch back.')
    end
    if imgui.Button(diag.echo and 'Console debug: ON' or 'Console debug: OFF') then
      diag:set_echo(not diag.echo,snapshot)
      save_settings()
    end
    end
  end
  imgui.End()
end

local settings=settings_mod.read(paths.config,identity)
if settings.last_route then filename=settings.last_route end
if settings.door_role then door_role=settings.door_role end
if settings.mode then mode=settings.mode end
if settings.view then view=settings.view end
if settings.seen_mode_notice then seen_mode_notice=settings.seen_mode_notice end
local echo_default=settings.echo_enabled
if echo_default==nil then echo_default=version.is_test() end
diag:set_echo(echo_default,snapshot)
refresh_routes()
if filename then load_route() end
log('AutoRoute session started (build '..version.VERSION..', view '..view..'); log '..diag:path())
mq.imgui.init('PTAutoRoute',draw)
local next_snapshot=0
local next_heartbeat=0
while running do
  local ok,err=pcall(function()
    mq.doevents()
    local now=mq.gettime()
    check_medbreak_stood(now)
    if runner then runner:tick(now) end
    -- DL-010: HERE is sent only while actively trying to complete the route (the rule lives in the runner, so
    -- it is unit-tested), so an errored/paused/stopped/completed/dead client drops out of every barrier quickly.
    -- DL-017: never sent at all in Solo mode -- it exists solely to facilitate Group-mode coordination.
    if mode=='group' and runner and runner:heartbeat_active() and now>=next_heartbeat then
      next_heartbeat=now+HEARTBEAT_INTERVAL_MS
      mq.cmd('/g PTAR:HERE')
    end
    if now>=next_snapshot then
      next_snapshot=now+1000; diag:debug('TICK '..snapshot())
    end
  end)
  if not ok then
    if runner then runner:pause() end
    notice='Runner error: '..tostring(err); log(notice)
  end
  mq.delay(100)
end
if runner then runner:stop() end
log('AutoRoute session ended')
mq.imgui.destroy('PTAutoRoute')
