-- Single authoritative version value, shared by the Runner, Editor, and logger.
local M={}
M.VERSION='1.0.0'
function M.is_test() return M.VERSION:match('%-test%.')~=nil end
return M
