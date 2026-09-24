-- /lua run PTAutoRoute
local mq=require('mq')
local imgui=require('ImGui')
local data=require('PTARRouteData')
local machine=require('PTARRunnerCore')
local files=require('PTARFiles')
local logger=require('PTARLog')
local running=true
local filename=nil
local choices={}
local runner,route
local notice='Select a route, then Start.'
local nav_owned=false
local function identity()
  local function read(fn) local ok,v=pcall(fn); return ok and v or 'unknown' end
  return read(function() return mq.TLO.EverQuest.Server() end),read(function() return mq.TLO.Me.Name() end)
end
local diag=logger.new(mq.configDir,identity,mq.gettime)

local function log(message)
  diag:event(message)
end
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
  local me_combat=read_bool(function() return mq.TLO.Me.Combat() end)
  local ok,count=pcall(function() return tonumber(mq.TLO.Me.XTHaterCount()) end)
  local xt_haters=ok and count or nil
  return me_combat,xt_haters,me_combat or (xt_haters or 0)>0
end
function adapter.combat()
  local me_combat,xt_haters,active=combat_signals()
  local signature=string.format('meCombat=%s xtHaters=%s effectiveCombat=%s',
    tostring(me_combat),xt_haters and tostring(xt_haters) or 'unavailable',tostring(active))
  if signature~=last_combat_signals then
    log('Combat signals: '..signature)
    last_combat_signals=signature
  end
  return active
end
function adapter.nav(w)
  local cmd='/nav '..coords(w)..' dist='..tostring(w.radius or 15)
  log(cmd); nav_owned=true; mq.cmd(cmd)
end
function adapter.nav_stop()
  if nav_owned or adapter.nav_active() then log('/nav stop'); mq.cmd('/nav stop') end
  nav_owned=false
end
function adapter.face(heading) mq.cmd(string.format('/face heading %.3f',heading)) end
function adapter.forward(held) mq.cmd(held and '/keypress forward hold' or '/keypress forward') end
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
function adapter.door(w)
  local open,reason=adapter.door_state(w)
  if open==nil then log('Door click refused for '..w.label..': '..tostring(reason)); return false end
  if open then return 'open' end
  log('DOOR CLICK '..w.id..' '..w.label); mq.cmd('/click left door'); return 'clicked'
end
local function snapshot()
  local p=adapter.position()
  local w=runner and runner.index and route.waypoints[runner.index]
  local function optional(fn) local ok,v=pcall(fn); return ok and tostring(v) or '?' end
  local heading=optional(function() return mq.TLO.Me.Heading.Degrees() end)
  local me_combat,xt_haters,effective_combat=combat_signals()
  local target=optional(function() return mq.TLO.Target.ID() end)
  local distance='?'
  if p and w then distance=string.format('%.1f',data.distance(p,w)) end
  local now=mq.gettime()
  return string.format('zone=%s route=%s status=%s phase=%s waypoint=%s lastGood=%s attempt=%s backtracked=%s pos=%s heading=%s dist=%s best=%s progressAgeMs=%s phaseAgeMs=%s navActive=%s mesh=%s meCombat=%s xtHaters=%s effectiveCombat=%s target=%s',
    tostring(adapter.zone()),tostring(filename),runner and runner.status or 'none',runner and tostring(runner.phase) or 'none',
    w and (w.id..'/'..w.label) or 'none',runner and tostring(runner.last_good) or 'none',
    runner and tostring(runner.attempt+1) or 'none',runner and tostring(runner.backtracked) or 'none',
    p and string.format('%.2f,%.2f,%.2f',p.x,p.y,p.z) or 'unavailable',heading,distance,
    runner and tostring(runner.best) or 'none',runner and runner.progress_at and tostring(now-runner.progress_at) or 'none',
    runner and runner.started and tostring(now-runner.started) or 'none',
    tostring(adapter.nav_active()),tostring(adapter.mesh()),tostring(me_combat),
    xt_haters and tostring(xt_haters) or 'unavailable',tostring(effective_combat),target)
end
local function refresh_routes()
  local found,err=files.scan(mq.configDir)
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
  local path=mq.configDir..'/'..filename
  local loaded,err=data.read(path)
  if not loaded then notice='Load failed: '..tostring(err); return end
  local errors=data.validate(loaded)
  for i,w in ipairs(loaded.waypoints) do
    if w.type=='drop_pre' then
      local post=loaded.waypoints[i+1]
      if not w.landing then errors[#errors+1]=w.label..' needs landing metadata (water or ground)' end
      if not post or post.type~='drop_post' or post.drop_id~=w.drop_id then
        errors[#errors+1]=w.label..' must be followed by its Drop Post marker'
      end
    end
  end
  if #errors>0 then notice='Route invalid: '..table.concat(errors,'; '); return end
  local endpoint=false
  for _,w in ipairs(loaded.waypoints) do if w.type=='finish' or w.manual_handoff then endpoint=true end end
  if #loaded.waypoints==0 or not endpoint then
    notice='Route is still being captured; add a Finish or Manual handoff waypoint before running.'; return
  end
  route=loaded; runner=machine.new(route,adapter)
  notice='Loaded '..route.route_name..' ('..#route.waypoints..' waypoints). Log: '..diag:path()
  log('Loaded '..path..' with '..#route.waypoints..' waypoints')
  diag:debug('Route load snapshot: '..snapshot())
end
local function draw()
  imgui.SetNextWindowSize(ImVec2(520,350),ImGuiCond.FirstUseEver)
  imgui.SetNextWindowPos(ImVec2(55,55),ImGuiCond.FirstUseEver)
  local open,visible=imgui.Begin('Project Triune AutoRoute v0.2-test5###Project Triune AutoRoute',true)
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
    imgui.SameLine(); if imgui.Button('New / Edit Route') then mq.cmd('/lua run PTAREditor') end
    if imgui.Button(diag.verbose and 'Verbose Debug: ON' or 'Verbose Debug: OFF') then
      diag:set_verbose(not diag.verbose,snapshot)
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
      if imgui.Button('Start') then runner:start(runner.selected,mq.gettime()) end
      imgui.SameLine(); if imgui.Button('Use Nearest Waypoint') then runner:start_nearest(mq.gettime()) end
      if imgui.Button('Pause') then runner:pause() end
      imgui.SameLine(); if imgui.Button('Resume (nearest valid)') then runner:resume(mq.gettime()) end
      imgui.SameLine(); if imgui.Button('Stop') then runner:stop() end
      imgui.TextWrapped('TAC stays manual. Marked handoffs stop the runner; continue manually.')
    end
  end
  imgui.End()
end

refresh_routes()
if filename then load_route() end
diag:set_verbose(true,snapshot)
log('AutoRoute session started; verbose default ON (test build); log '..diag:path())
mq.imgui.init('PTAutoRoute',draw)
local next_snapshot=0
while running do
  local ok,err=pcall(function()
    local now=mq.gettime()
    if runner then runner:tick(now) end
    if diag.verbose and now>=next_snapshot then
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
