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
-- pass args in
lua([[local a,b = ... assert(a == 'foo') assert(b == 'bar')]], 'foo', 'bar')

-- return values
assert.eq(nil, lua[[return nil]])
assert.eq(true, lua[[return true]])
assert.eq(false, lua[[return false]])
assert.eq(43, lua[[return 43]])
assert.eq('bar', lua[[return 'bar']])
-- read args returned out
local a,b = lua[[return 'foo', 'bar']] assert(a == 'foo') assert(b == 'bar')

-- handle syntax errors
assert.eq(false, pcall(function() lua[[(;;;)]] end))

-- handle runtime errors
assert.eq(false, pcall(function() lua[[error'here']] end))

-- accept and evaluate functions
lua([[assert((...)() == 44)]], function() return 44 end)
lua([[assert((...)(44) == 88)]], function(x) return x * 2 end)

-- returning functions
local f = lua[[return function() return 42 end]] assert(f() == 42)

-- accept tables
lua([[local t = ... assert(t.a == 42)]], {a=42})

-- return tables
assert.eq(43, lua[[return {z=43}]].z)

--[=[
-- can we accept self-referencing tables?
-- no, not until I insert ext.tolua/fromlua as a fallback to string.buffer
do
	local t = {}
	t.t = t
	lua([[local t = ... assert(t.t == t)]], t)
end
--]=]

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

-- global access
do
	lua[[t = {k=42}]]
	assert.eq(lua.global.t.k, 42)
	-- notice that values are copied across lua states, so setting t.k won't reflect on the other side
	-- I could get around this by making proxy objects everywhere like I do in my [lua-interop](https://github.com/thenumbernine/lua-ffi-wasm/blob/master/lua-interop/lua-interop.js) Lua/JS implementation.
	-- but that brings a performance overhead with it
	lua.global.t = {v=43}
	lua[[assert(t.v == 43)]]
end

lua:close()
print'done'
