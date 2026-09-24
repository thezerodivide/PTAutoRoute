-- State machine with an injected MacroQuest adapter. Times are milliseconds.
local M={}
local function dist(a,b)
  return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function radius(w) return w.radius or 15 end

function M.new(route,io,opts)
  opts=opts or {}
  local self={route=route,io=io,status='Ready',message='Select a waypoint and Start.',selected=1,
    index=nil,last_good=nil,attempt=0,backtracked=false,forward=false,door_tried=false}
  local waypoints=route.waypoints
  local function say(status,message)
    self.status=status; self.message=message; io.log(status..': '..message)
  end
  local function release()
    if self.forward then io.forward(false); self.forward=false end
  end
  local function halt()
    release(); io.nav_stop()
  end
  local function fail(reason)
    halt(); self.index=nil; say('Error',reason..' Use Resume (nearest valid waypoint) or Stop.')
  end
  local function navigate(now)
    local w=waypoints[self.index]
    if io.combat() then
      self.phase='combat'; self.combat_return='nav'; self.combat_clear_at=nil
      say('Waiting for combat','Combat interrupted navigation to '..w.label..'; keeping the current waypoint and retries.')
      return
    end
    if w.type=='drop_pre' and not opts.automate_drops then
      halt(); self.index=nil
      say('Manual handoff','Drop automation is deferred. Continue from '..w.label..' manually.')
      return
    end
    if not io.mesh() then fail('Navigation mesh is unavailable'); return end
    local p=io.position()
    if not p then fail('Character position unavailable'); return end
    if dist(p,w)<=radius(w) then
      self.phase='nav'; self.started=now; self.progress_at=now; self.best=0
      say('Running',string.format('#%d %s (%s), already within radius',self.index,w.label,w.type))
      return
    end
    if not io.path(w) then self:leg_failed('No navigable path to '..w.label,now); return end
    io.nav(w)
    self.phase='nav'; self.started=now; self.progress_at=now
    self.best=dist(p,w); self.door_tried=false
    say('Running',string.format('#%d %s (%s), attempt %d',self.index,w.label,w.type,self.attempt+1))
  end
  function self:leg_failed(reason,now)
    if io.combat() then
      local returning=self.phase=='backtrack' and 'backtrack' or 'nav'
      halt(); self.phase='combat'; self.combat_return=returning
      self.combat_clear_at=nil
      say('Waiting for combat','Combat interrupted '..reason..'; keeping the current waypoint and retries.')
      return
    end
    halt()
    if self.attempt<2 then
      self.attempt=self.attempt+1
      io.log('Retry '..self.attempt..'/2: '..reason)
      navigate(now); return
    end
    if not self.backtracked and self.last_good and self.last_good<self.index then
      local old=self.index
      self.backtracked=true; self.phase='backtrack'; self.started=now
      local back=waypoints[self.last_good]
      if io.mesh() and io.path(back) then
        io.nav(back); say('Recovering','Returning to # '..self.last_good..' '..back.label..' before retrying # '..old)
        return
      end
    end
    fail(reason..' (two retries and recovery exhausted)')
  end
  local function advance(now)
    local w=waypoints[self.index]
    io.nav_stop(); self.last_good=self.index
    if w.manual_handoff then
      self.index=nil; say('Manual handoff','Reached '..w.label..'. Continue the drops manually.'); return
    end
    if w.type=='finish' then
      self.index=nil; say('Completed','Reached '..w.label..'. TAC remains in manual mode.'); return
    end
    self.index=self.index+1
    if not waypoints[self.index] then fail('Route ended without a Finish'); return end
    self.attempt=0; self.backtracked=false
    navigate(now)
  end
  local function begin_door(now)
    local w=waypoints[self.index]
    io.nav_stop()
    self.phase='door'; self.door_since=now; self.door_poll_at=0
    self.door_click_at=nil; self.door_last_state=nil
    say('Running','Checking '..w.label..' before the next navigation leg')
  end
  local function begin_drop(now)
    local w=waypoints[self.index]
    halt(); io.face(w.heading); io.forward(true); self.forward=true
    self.phase='approach'; self.started=now; self.last_z=io.position().z; self.last_sample=now
    say('Running','Entering '..w.label..'; watching for downward movement')
  end
  local function land(now)
    local w=waypoints[self.index]
    release(); self.last_good=nil -- Never recover across a drop.
    local post=waypoints[self.index+1]
    if not post or post.type~='drop_post' or post.drop_id~=w.drop_id then
      fail('Drop pair is missing after '..w.label); return
    end
    if w.landing=='water' then
      self.index=nil; io.nav_stop()
      say('Paused','Fall settled in water after '..w.label..'. Swim out manually, then Resume from a dry waypoint.')
    else
      self.index=self.index+1; self.attempt=0; self.backtracked=false
      navigate(now)
    end
  end
  function self:nearest()
    local p=io.position(); if not p or not io.mesh() then return nil,'Position or navigation mesh unavailable' end
    local best,closest
    for i,w in ipairs(waypoints) do
      -- Same elevation plus a valid path keeps the selection on this side of a drop.
      if math.abs(p.z-w.z)<=35 and io.path(w) then
        local d=dist(p,w)
        if not closest or d<closest then best=i; closest=d end
      end
    end
    if not best then return nil,'No reachable dry waypoint near your elevation; swim to dry ground first' end
    return best
  end
  function self:start(index,now)
    halt()
    if not waypoints[index] then fail('Invalid waypoint selection'); return end
    if io.zone()~=route.zone_short_name then fail('Wrong zone: expected '..route.zone_short_name); return end
    if not io.mesh() then fail('Navigation mesh is unavailable'); return end
    self.selected=index; self.index=index; self.last_good=nil; self.attempt=0; self.backtracked=false
    navigate(now)
  end
  function self:start_nearest(now)
    local i,err=self:nearest()
    if not i then fail(err); return end
    self:start(i,now)
  end
  function self:resume(now)
    self:start_nearest(now)
  end
  function self:pause()
    halt(); self.index=nil; say('Paused','Paused. Resume selects the nearest reachable dry waypoint.')
  end
  function self:stop()
    halt(); self.index=nil; self.selected=1; self.last_good=nil
    say('Ready','Stopped. Start defaults to the first waypoint.')
  end
  function self:tick(now)
    if self.status~='Running' and self.status~='Recovering' and self.status~='Waiting for combat' then return end
    if io.zone()~=route.zone_short_name then fail('Zone changed'); return end
    local p=io.position(); if not p then fail('Character position unavailable'); return end
    local w=waypoints[self.index]
    if self.phase=='combat' then
      if io.combat() then
        if self.combat_clear_at then io.log('Combat resumed during clear window; waiting again') end
        self.combat_clear_at=nil; return
      end
      if not self.combat_clear_at then
        self.combat_clear_at=now
        io.log('Combat cleared; waiting 1500 ms before resuming '..w.label)
      end
      if now-self.combat_clear_at<1500 then return end
      local returning=self.combat_return
      self.combat_clear_at=nil; self.combat_return=nil
      io.log('Combat clear for 1500 ms; resuming '..returning..' toward '..w.label)
      if returning=='backtrack' then
        local back=waypoints[self.last_good]
        if dist(p,back)<=radius(back) then self.attempt=0; navigate(now)
        elseif not io.mesh() or not io.path(back) then fail('Could not return to previous known good waypoint')
        else io.nav(back); self.phase='backtrack'; self.started=now
          say('Recovering','Returning to # '..self.last_good..' '..back.label..' after combat') end
      else navigate(now) end
      return
    end
    if io.combat() and (self.phase=='nav' or self.phase=='backtrack' or self.phase=='door') then
      local returning=self.phase=='backtrack' and 'backtrack' or 'nav'
      halt(); self.phase='combat'; self.combat_return=returning; self.combat_clear_at=nil
      say('Waiting for combat','Combat interrupted '..w.label..'; keeping the current waypoint and retries.')
      return
    end
    if self.phase=='backtrack' then
      local back=waypoints[self.last_good]
      if dist(p,back)<=radius(back) then
        io.nav_stop(); self.attempt=0; navigate(now)
      elseif now-self.started>45000 or (now-self.started>3000 and not io.nav_active()) then
        fail('Could not return to previous known good waypoint')
      end
      return
    end
    if self.phase=='nav' then
      if dist(p,w)<=radius(w) then
        if w.type=='drop_pre' then begin_drop(now)
        elseif w.type=='door' then begin_door(now)
        else advance(now) end
        return
      end
      local d=dist(p,w)
      if d<self.best-3 then self.best=d; self.progress_at=now end
      if now-self.progress_at>12000 and not self.door_tried and self.index>1 then
        local previous=waypoints[self.index-1]
        if previous.type=='door' and dist(p,previous)<50 then
          self.door_tried=true
          local result=io.door(previous)
          io.log('Door stall fallback '..previous.label..': '..tostring(result))
          if result=='clicked' then self.progress_at=now; return end
        end
      end
      if now-self.progress_at>16000 or now-self.started>90000 or (now-self.started>3000 and not io.nav_active()) then
        self:leg_failed('Navigation stalled at '..w.label,now)
      end
      return
    end
    if self.phase=='door' then
      if now<self.door_poll_at then return end
      self.door_poll_at=now+300
      local state,detail=io.door_state(w)
      local state_text=state==nil and ('unavailable: '..tostring(detail)) or tostring(state)
      if state_text~=self.door_last_state then
        io.log(string.format('Door %s [%s]: state %s, attempt %d, elapsed %d ms',w.label,
          tostring(w.door and w.door.id),state_text,self.attempt+1,now-self.door_since))
        self.door_last_state=state_text
      end
      if state==true then advance(now); return end
      if state==nil then
        if now-self.door_since>=2000 then
          io.log('Door state unavailable; continuing with the existing Nav and stall fallback: '..w.label)
          advance(now)
        end
        return
      end
      if not self.door_click_at then
        local result=io.door(w)
        if result=='clicked' then
          self.door_click_at=now
          io.log('Clicked closed door '..w.label..'; awaiting fully open state')
        elseif result=='open' then
          io.log('Door opened before click: '..w.label)
        else
          io.log('Door click unavailable: '..w.label)
          self:leg_failed('Could not click '..w.label,now)
        end
      elseif now-self.door_click_at>=8000 then
        self:leg_failed('Door did not fully open: '..w.label,now)
      end
      return
    end
    if self.phase=='approach' or self.phase=='falling' then
      local elapsed=now-self.last_sample
      if elapsed>=100 then
        local speed=(self.last_z-p.z)*1000/elapsed
        self.last_z=p.z; self.last_sample=now
        if self.phase=='approach' and speed>15 then
          release(); self.phase='falling'; self.started=now; self.slow_since=nil
          io.log('Fall began at Z '..string.format('%.2f',p.z))
        elseif self.phase=='falling' then
          if speed<4 then self.slow_since=self.slow_since or now else self.slow_since=nil end
          if self.slow_since and now-self.slow_since>=750 then land(now); return end
        end
      end
      if self.phase=='approach' and now-self.started>7000 then fail('Fall did not begin at '..w.label)
      elseif self.phase=='falling' and now-self.started>20000 then fail('Fall did not settle at '..w.label) end
    end
  end
  return self
end
return M
