#!/usr/bin/env luajit
local assert = require 'ext.assert'
local Lua = require 'lua'
local lua = Lua()

-- accept values
lua([[assert(... == nil)]], nil)
lua([[assert(... == false)]], false)
lua([[assert(... == true)]], true)
lua([[assert(... == 42)]], 42)
lua([[assert(... == 'foo')]], 'foo')
lua([[local a,b = ... assert(a == 'foo') assert(b == 'bar')]], 'foo', 'bar')

-- return values
assert(nil == lua[[return nil]])
assert(true == lua[[return true]])
assert(false == lua[[return false]])
assert(43 == lua[[return 43]])
assert('bar' == lua[[return 'bar']])
local a,b = lua[[return 'foo', 'bar']] assert(a == 'foo') assert(b == 'bar')

-- syntax errors
assert(false == pcall(function() lua[[(;;;)]] end))

-- runtime errors
assert(false == pcall(function() lua[[error'here']] end))

-- accepting functions
lua([[assert((...)() == 44)]], function() return 44 end)
lua([[assert((...)(44) == 88)]], function(x) return x * 2 end)

-- returning functions
local f = lua[[return function() return 42 end]] assert(f() == 42)

-- load and run code on the new state
local x, y = lua([[
local assert = require 'ext.assert'
local a, b, c = ...
assert.eq(a, 137)
assert.eq(b, 'foo')
assert.type(c, 'function')
assert.eq(c(2), 245)
return 42, 'bar'
]], 137, 'foo', function(x) return x + 243 end)
assert.eq(x, 42)
assert.eq(y, 'bar')

do
	local result
	assert.eq(false, xpcall(function()
		result = lua([[
error'here'
return result
	]])
	end, function(err)
		-- if you want to assert the error message.  though it does contain a stack trace from the enclosed Lua state
		--print(require 'ext.tolua'(err))
		--print('err', err)
	end))
	assert.eq(result, nil)
end

lua:close()
print'done'
