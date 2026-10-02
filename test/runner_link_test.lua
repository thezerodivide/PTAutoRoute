-- Requirement tests for PTARRunnerLink (DL-022 mechanism): the Editor asks the same character's Runner over a named actor
-- mailbox whether a route is in use. No MacroQuest dependency. Expectations come from the approved DL-022 text:
--   in use = the route is the Runner's loaded route AND its runner is Running, Recovering, Waiting for combat,
--   Waiting for med break, or Paused (merely loaded, Ready, Completed, Error or Manual handoff is not in use);
--   a delivery failure RoutingFailed means no Runner; every other failure to get an answer REFUSES; a 2000 ms timeout
--   refuses; a late or duplicate answer is ignored.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Link = require 'PTAR.PTARRunnerLink'

local R = { RoutingFailed = 3, AmbiguousRecipient = 4, NoConnection = 2, ConnectionClosed = 1 }   -- stand-in for actors.ResponseStatus

test('DL-022: the five unfinished-run statuses are in use', function()
  for _, status in ipairs({ 'Running', 'Recovering', 'Waiting for combat', 'Waiting for med break', 'Paused' }) do
    expect.equal(Link.in_use(status), true, status)
  end
end)

test('DL-022: Ready, Completed, Error, Manual handoff and no runner are not in use', function()
  for _, status in ipairs({ 'Ready', 'Completed', 'Error', 'Manual handoff' }) do
    expect.equal(Link.in_use(status), false, status)
  end
  expect.equal(Link.in_use(nil), false)
end)

test('DL-022: the Runner reports busy only for its own loaded route while that runner is unfinished', function()
  local busy = Link.check_reply('PTAR_A.lua', 'PTAR_A.lua', 'Running')
  expect.equal(busy.busy, true); expect.equal(busy.status, 'Running'); expect.equal(busy.id, 'check')
  expect.equal(Link.check_reply('PTAR_A.lua', 'PTAR_A.lua', 'Paused').busy, true)
end)

test('DL-022: a different route is not busy even while another route runs', function()
  expect.equal(Link.check_reply('PTAR_B.lua', 'PTAR_A.lua', 'Running').busy, false)
end)

test('DL-022: the loaded route is not busy once its run is Completed, Error, at Manual handoff or Ready', function()
  for _, status in ipairs({ 'Ready', 'Completed', 'Error', 'Manual handoff' }) do
    expect.equal(Link.check_reply('PTAR_A.lua', 'PTAR_A.lua', status).busy, false, status)
  end
end)

test('DL-022: with nothing loaded nothing is busy, and the reply says so', function()
  local reply = Link.check_reply('PTAR_A.lua', nil, nil)
  expect.equal(reply.busy, false); expect.equal(reply.status, 'none')
end)

test('DL-022: the address uses the unique mailbox name (no script name), absolute, scoped to this server and character', function()
  local h = Link.header('multiclass', 'Sithus')
  expect.equal(h.mailbox, Link.MAILBOX); expect.equal(h.absolute_mailbox, true)
  expect.equal(h.server, 'multiclass'); expect.equal(h.character, 'Sithus')
  expect.equal(h.script, nil)
end)

test('DL-022: a proper reply is used as the answer', function()
  local r = Link.interpret(0, { id = 'check', busy = true, status = 'Paused' }, R)
  expect.equal(r.kind, 'reply'); expect.equal(r.busy, true); expect.equal(r.status, 'Paused')
  expect.equal(Link.interpret(0, { id = 'check', busy = false, status = 'Ready' }, R).busy, false)
end)

test('DL-022: RoutingFailed (no mailbox found) means there is no Runner for this character', function()
  expect.equal(Link.interpret(R.RoutingFailed, nil, R).kind, 'no_runner')
end)

test('DL-022: ambiguous recipients, a closed or missing connection, and unusable answers all refuse with a reason', function()
  for name, args in pairs({ ambiguous = { R.AmbiguousRecipient, nil }, noconn = { R.NoConnection, nil },
      closed = { R.ConnectionClosed, nil }, empty = { 0, nil }, wrong_id = { 0, { id = 'other' } }, junk = { 0, 'text' } }) do
    local r = Link.interpret(args[1], args[2], R)
    expect.equal(r.kind, 'refuse', name)
    expect.truthy(type(r.reason) == 'string' and #r.reason > 0, name)
  end
end)

test('DL-022: a reply that arrives with a failure status is still read as the answer, never as "no Runner"', function()
  expect.equal(Link.interpret(R.RoutingFailed, { id = 'check', busy = true, status = 'Running' }, R).kind, 'reply')
end)

-- ---------------------------------------------------------------- the request tracker (timeout, once-only)
local function clock_at(t) local c = { now = t }; return c, function() return c.now end end

test('DL-022: the answer is delivered once, with the elapsed time', function()
  local c, clock = clock_at(1000)
  local tr = Link.tracker(clock)
  local got = {}
  expect.equal(tr:send(function(r) got[#got + 1] = r end), true)
  c.now = 1130
  tr:receive(0, { id = 'check', busy = false, status = 'Ready' }, R)
  expect.equal(#got, 1); expect.equal(got[1].kind, 'reply'); expect.equal(got[1].elapsed, 130)
  tr:receive(0, { id = 'check', busy = true, status = 'Running' }, R)    -- a duplicate is ignored
  expect.equal(#got, 1)
end)

test('DL-022: no answer by 2000 ms refuses, and not a moment earlier', function()
  local c, clock = clock_at(1000)
  local tr = Link.tracker(clock)
  local got = {}
  tr:send(function(r) got[#got + 1] = r end)
  c.now = 2999; tr:tick()
  expect.equal(#got, 0)
  c.now = 3000; tr:tick()
  expect.equal(#got, 1); expect.equal(got[1].kind, 'refuse'); expect.equal(got[1].timeout, true); expect.equal(got[1].elapsed, 2000)
  c.now = 4000; tr:tick()
  expect.equal(#got, 1)                                                  -- the timeout fires once
end)

test('DL-022: an answer that arrives after the timeout is ignored', function()
  local c, clock = clock_at(0)
  local tr = Link.tracker(clock)
  local got = {}
  tr:send(function(r) got[#got + 1] = r end)
  c.now = 2500; tr:tick()
  tr:receive(0, { id = 'check', busy = false, status = 'Ready' }, R)
  expect.equal(#got, 1); expect.equal(got[1].kind, 'refuse')
end)

test('DL-022: an answer before the timeout cancels it', function()
  local c, clock = clock_at(0)
  local tr = Link.tracker(clock)
  local got = {}
  tr:send(function(r) got[#got + 1] = r end)
  c.now = 100; tr:receive(R.RoutingFailed, nil, R)
  c.now = 5000; tr:tick()
  expect.equal(#got, 1); expect.equal(got[1].kind, 'no_runner')
end)

test('DL-022: a second request while one is waiting is refused, and the first is unaffected', function()
  local c, clock = clock_at(0)
  local tr = Link.tracker(clock)
  local first = {}
  expect.equal(tr:send(function(r) first[#first + 1] = r end), true)
  expect.equal(tr:send(function() end), false)
  tr:receive(0, { id = 'check', busy = true, status = 'Running' }, R)
  expect.equal(#first, 1)
  expect.equal(tr:send(function() end), true)                            -- free again once answered
end)
