-- The Editor asks the Runner on the same character whether a route is in use (DL-022), over a named actor mailbox. No
-- MacroQuest dependency: PTAR.lua and PTAREditor.lua own the actor calls; this module owns the decisions.
local M={}

-- The mailbox is addressed by name alone (absolute, matched as a case-insensitive suffix of the registered name), so it
-- does not depend on how the Runner script was started. The header scopes it to this server and character, so another
-- character's Runner can never answer.
M.MAILBOX='PTAR_Runner_Mailbox'
M.TIMEOUT_MS=2000   -- first guess (Protocol 15); the elapsed time of every request is logged

local IN_USE={['Running']=true,['Recovering']=true,['Waiting for combat']=true,['Waiting for med break']=true,['Paused']=true}

-- A route is in use when it belongs to an unfinished run: the statuses above. Merely loaded, Ready, Completed, Error and
-- Manual handoff are not in use.
function M.in_use(status) return IN_USE[status]==true end

-- Runner side: the answer to a `check`.
function M.check_reply(file,loaded_file,status)
  local busy=file~=nil and file==loaded_file and M.in_use(status)
  return {id='check',file=file,busy=busy,status=status or 'none'}
end

function M.header(server,character)
  return {mailbox=M.MAILBOX,absolute_mailbox=true,server=server,character=character}
end

-- Editor side: turn a send result into an outcome. `status` and `content` are what the send callback received;
-- `R` is actors.ResponseStatus.
--   reply      -> the Runner answered (a usable answer wins over any status)
--   no_runner  -> RoutingFailed: no mailbox found, so there is no Runner for this character
--   refuse     -> anything else: the state could not be obtained, so deletion is refused
function M.interpret(status,content,R)
  if type(content)=='table' and content.id=='check' then
    return {kind='reply',busy=content.busy==true,status=content.status,code=status}
  end
  if status==R.RoutingFailed then return {kind='no_runner',code=status} end
  if status==R.AmbiguousRecipient then
    return {kind='refuse',code=status,reason='more than one PTAR Runner answered for this character'}
  end
  if status==R.NoConnection or status==R.ConnectionClosed then
    return {kind='refuse',code=status,reason='the MacroQuest messaging connection is unavailable'}
  end
  return {kind='refuse',code=status,reason='the Runner sent an answer PTAR could not understand'}
end

-- One request at a time: delivers exactly one outcome (an answer, or a refusal at the timeout), then ignores any late
-- or duplicate answer.
function M.tracker(clock)
  local t={pending=nil}
  function t:send(on_result)
    if self.pending then return false end
    self.pending={on_result=on_result,sent=clock()}
    return true
  end
  function t:receive(status,content,R)
    local p=self.pending
    if not p then return nil end
    self.pending=nil
    local result=M.interpret(status,content,R)
    result.elapsed=clock()-p.sent
    p.on_result(result)
    return result
  end
  function t:tick()
    local p=self.pending
    if not p then return nil end
    local elapsed=clock()-p.sent
    if elapsed<M.TIMEOUT_MS then return nil end
    self.pending=nil
    local result={kind='refuse',timeout=true,elapsed=elapsed,reason='the Runner did not answer within '..M.TIMEOUT_MS..' ms'}
    p.on_result(result)
    return result
  end
  return t
end

return M
