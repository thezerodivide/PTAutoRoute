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
local running=true
local filename=nil
local door_role='primary'
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
  settings_mod.save(paths.config,identity,{last_route=filename,echo_enabled=diag.echo,door_role=door_role})
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
  if id~=d.id or name~=d.name or not x or not y or not z or not distance or distance>35 or
      math.sqrt((x-d.x)^2+(y-d.y)^2+(z-d.z)^2)>10 then
    return nil,string.format('Target mismatch: expected %s/%s at %.1f,%.1f,%.1f; observed %s/%s at %s,%s,%s distance %s',
      tostring(d.id),d.name,d.x,d.y,d.z,tostring(id),tostring(name),tostring(x),tostring(y),tostring(z),tostring(distance))
  end
  if open~=true and open~=false then return nil,'Open value unavailable: '..tostring(open) end
  diag:debug(string.format('DOOR target %s id=%d name=%s xyz=%.2f,%.2f,%.2f distance=%.1f open=%s',
    w.id,id,name,x,y,z,distance,tostring(open)))
  return open
end
function adapter.door(w,click_even_if_open)
  local open,reason=adapter.door_state(w)
  if open==nil then log('Door click refused for '..w.label..': '..tostring(reason)); return false end
  if open and not click_even_if_open then return 'open' end
  log('DOOR CLICK '..w.id..' '..w.label); mq.cmd('/click left door'); return 'clicked'
end
function adapter.door_role() return door_role end
function adapter.door_confirmed(id) return confirmed_doors[id]==true end
function adapter.announce_door_open(id)
  local cmd='/g PTAR:DOOR:'..tostring(id)..':OPEN'
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
  notice='Loaded '..route.route_name..' ('..#route.waypoints..' waypoints). Log: '..diag:path()
  log('Loaded '..path..' with '..#route.waypoints..' waypoints')
  diag:debug('Route load snapshot: '..snapshot())
  save_settings()
end
local function draw()
  imgui.SetNextWindowSize(ImVec2(520,350),ImGuiCond.FirstUseEver)
  imgui.SetNextWindowPos(ImVec2(55,55),ImGuiCond.FirstUseEver)
  local open,visible=imgui.Begin('Project Triune AutoRoute v'..version.VERSION..'###Project Triune AutoRoute',true)
  if open==false then running=false end
  if visible then
    if imgui.Button('Close Runner') then running=false end
    local display=filename or '(no routes found)'
    for _,entry in ipairs(choices) do if entry.file==filename then display=entry.label end end
    if imgui.BeginCombo('Route',display) then
      for _,entry in ipairs(choices) do
        if imgui.Selectable(entry.label..'##'..entry.file,filename==entry.file) then
          if runner and (runner.status=='Running' or runner.status=='Recovering' or runner.status=='Waiting for combat') then
            notice='Pause or Stop before changing routes.'
          else filename=entry.file; load_route() end
        end
      end
      imgui.EndCombo()
    end
    if imgui.Button('Refresh Routes') then
      if runner and (runner.status=='Running' or runner.status=='Recovering' or runner.status=='Waiting for combat') then notice='Pause or Stop before refreshing routes.'
      else refresh_routes(); load_route() end
    end
    imgui.SameLine(); if imgui.Button('New / Edit Route') then mq.cmd('/lua run PTAR/PTAREditor') end
    if imgui.Button(diag.echo and 'MQ Console Echo: ON' or 'MQ Console Echo: OFF') then
      diag:set_echo(not diag.echo,snapshot)
      save_settings()
    end
    if imgui.Button('Door Role: '..(door_role=='primary' and 'Primary' or 'Secondary')) then
      door_role=door_role=='primary' and 'secondary' or 'primary'
      log('Door role set to '..door_role)
      save_settings()
    end
    imgui.TextWrapped(notice)
    if runner then
      imgui.Separator()
      imgui.Text('Status: '..runner.status)
      imgui.TextWrapped(runner.message)
      local chosen=route.waypoints[runner.selected]
      local current=runner.index and route.waypoints[runner.index]
      imgui.Text('Current: '..(current and string.format('#%d %s',runner.index,current.label) or 'none'))
      local label=string.format('#%d %s [%s, %s]',runner.selected,chosen.label,chosen.type,chosen.id)
      if imgui.BeginCombo('Start waypoint',label) then
        for i,w in ipairs(route.waypoints) do
          local entry=string.format('#%d %s [%s, %s]',i,w.label,w.type,w.id)
          if imgui.Selectable(entry..'##'..w.id,runner.selected==i) then runner.selected=i end
        end
        imgui.EndCombo()
      end
      -- While PTAR is setting TAC (DL-013) Start/Use Nearest/Resume are unavailable for a few seconds; Pause and Stop
      -- stay enabled. `busy` is read once so BeginDisabled/EndDisabled stay balanced, and clicks are acted on after
      -- EndDisabled so nothing between the pair can throw.
      local busy=runner:tac_busy()
      if busy then imgui.TextColored(1,0.8,0.2,1,'PTAR is setting TAC. Start, Use Nearest Waypoint and Resume are unavailable until it finishes (a few seconds). Pause and Stop still work.') end
      if busy then imgui.BeginDisabled() end
      local start_clicked=imgui.Button('Start')
      imgui.SameLine(); local nearest_clicked=imgui.Button('Use Nearest Waypoint')
      if busy then imgui.EndDisabled() end
      if start_clicked then runner:start(runner.selected,mq.gettime()) end
      if nearest_clicked then runner:start_nearest(mq.gettime()) end
      if imgui.Button('Pause') then runner:pause() end
      imgui.SameLine()
      if busy then imgui.BeginDisabled() end
      local resume_clicked=imgui.Button('Resume (nearest valid)')
      if busy then imgui.EndDisabled() end
      if resume_clicked then runner:resume(mq.gettime()) end
      imgui.SameLine(); if imgui.Button('Stop') then runner:stop() end
    end
  end
  imgui.End()
end

local settings=settings_mod.read(paths.config,identity)
if settings.last_route then filename=settings.last_route end
if settings.door_role then door_role=settings.door_role end
local echo_default=settings.echo_enabled
if echo_default==nil then echo_default=version.is_test() end
diag:set_echo(echo_default,snapshot)
refresh_routes()
if filename then load_route() end
log('AutoRoute session started (build '..version.VERSION..'); log '..diag:path())
mq.imgui.init('PTAutoRoute',draw)
local next_snapshot=0
while running do
  local ok,err=pcall(function()
    mq.doevents()
    local now=mq.gettime()
    if runner then runner:tick(now) end
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
