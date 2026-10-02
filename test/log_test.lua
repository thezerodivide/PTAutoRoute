-- Requirement tests for PTARLog's file naming (DL-022 build: the Editor gets its own log file so it never shares a file
-- with the Runner's log). The Runner's file name must not change.
local T = require 'harness.t'
local test, expect = T.test, T.expect

local Log = require 'PTAR.PTARLog'
local function identity() return 'multiclass', 'Sithus' end
local function clock() return 1234 end

test('DL-022: the default log file name is unchanged: PTAR_<server>_<character>.log', function()
  local l = Log.new('dir', identity, clock, '1.0.0')
  expect.equal(l:filename(), 'PTAR_multiclass_Sithus.log')
end)

test('DL-022: a prefix gives the Editor its own file, PTAR_Editor_<server>_<character>.log', function()
  local l = Log.new('dir', identity, clock, '1.0.0', nil, 'PTAR_Editor')
  expect.equal(l:filename(), 'PTAR_Editor_multiclass_Sithus.log')
end)

test('DL-022: the prefixed logger writes lines stamped with the build version to that file', function()
  local dir = T.with_temp_dir()
  local l = Log.new(dir, identity, clock, '9.9.9-test.1', nil, 'PTAR_Editor')
  l:event('hello editor')
  local text = assert(io.open(dir .. '/PTAR_Editor_multiclass_Sithus.log', 'r')):read('*a')
  expect.truthy(text:find('9.9.9-test.1', 1, true))
  expect.truthy(text:find('EVENT', 1, true))
  expect.truthy(text:find('hello editor', 1, true))
end)
