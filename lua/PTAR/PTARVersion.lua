-- Single authoritative version value, shared by the Runner, Editor, and logger.
local M={}
M.VERSION='1.1.0-test.22'
function M.is_test() return M.VERSION:match('%-test%.')~=nil end
return M
