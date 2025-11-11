#!/usr/bin/env luajit
local assert = require 'ext.assert'
local Lua = require 'lua'
local lua = Lua()

-- load and run code on the new state
local x, y = lua([[
local assert = require 'ext.assert'
local a, b, c = ...
assert.eq(a, 137)
assert.eq(b, 'foo')
assert.eq(c(2), 245)
return 42, 'bar'
]], 137, 'foo', function(x) return x + 243 end)
assert.eq(x, 42)
assert.eq(y, 'bar')

-- right now it just returns errors.
-- TODO error handling.
-- how, idk?
-- how about the default :run() / __call() throws errors into the parent lua_State?
-- and then I'll provide a separate Lua:pcall() that returns errors ...
-- ... and maybe maybe a separate Lua:xpcall that passes the error-handler across ...
local result = lua([[
error'here'
return result
]])
assert.eq(result, [[[string "error'here'..."]:1: here]])

lua:close()
print'done'
