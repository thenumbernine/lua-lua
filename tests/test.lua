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

lua:close()
print'done'
