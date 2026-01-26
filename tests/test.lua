#!/usr/bin/env luajit
local assert = require 'ext.assert'
local Lua = require 'lua'
local lua = Lua()

assert.eq(lua:gettop(), 0)

lua[[assert = require 'ext.assert']]
assert.eq(lua:gettop(), 0)

-- accept values
lua([[assert.eq(..., nil)]], nil)
assert.eq(lua:gettop(), 0)
lua([[assert.eq(..., false)]], false)
assert.eq(lua:gettop(), 0)
lua([[assert.eq(..., true)]], true)
assert.eq(lua:gettop(), 0)
lua([[assert.eq(..., 42)]], 42)
assert.eq(lua:gettop(), 0)
lua([[assert.eq(..., 'foo')]], 'foo')
assert.eq(lua:gettop(), 0)
-- pass args in
lua([[
local a,b = ...
assert.eq(a, 'foo')
assert.eq(b, 'bar')
]], 'foo', 'bar')
assert.eq(lua:gettop(), 0)

-- return values
assert.eq(nil, lua[[return nil]])
assert.eq(lua:gettop(), 0)
assert.eq(true, lua[[return true]])
assert.eq(lua:gettop(), 0)
assert.eq(false, lua[[return false]])
assert.eq(lua:gettop(), 0)
assert.eq(43, lua[[return 43]])
assert.eq(lua:gettop(), 0)
assert.eq('bar', lua[[return 'bar']])
assert.eq(lua:gettop(), 0)
-- read args returned out
do
	local a,b = lua[[return 'foo', 'bar']]
assert.eq(lua:gettop(), 0)
	assert.eq(a, 'foo')
	assert.eq(b, 'bar')
end

-- handle syntax errors
assert.eq(false, pcall(function() lua[[(;;;)]] end))
assert.eq(lua:gettop(), 0)

-- handle runtime errors
assert.eq(false, pcall(function() lua[[error'here']] end))
assert.eq(lua:gettop(), 0)

-- accept and evaluate functions
lua([[assert.eq((...)(), 44)]], function() return 44 end)
assert.eq(lua:gettop(), 0)
lua([[assert.eq((...)(44), 88)]], function(x) return x * 2 end)
assert.eq(lua:gettop(), 0)

-- returning functions
local f = lua[[return function() return 42 end]]
assert.eq(f(), 42)
assert.eq(lua:gettop(), 0)

-- accept tables
lua([[local t = ... assert.eq(t.a, 42)]], {a=42})
assert.eq(lua:gettop(), 0)

-- return tables
assert.eq(43, lua[[return {z=43}]].z)
assert.eq(lua:gettop(), 0)

-- can we accept self-referencing tables?
-- yes, now that I added an ext.tolua/fromlua pathway to serialization
do
	local t = {}
	t.t = t
	lua([[local t = ... assert.eq(t.t, t)]], t)
	assert.eq(lua:gettop(), 0)
end
do
	local t = lua[[
local t = {}
t.t = t
return t
]]
	assert.eq(t, t.t)
	assert.eq(lua:gettop(), 0)
end

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
assert.eq(lua:gettop(), 0)

do
	local ffi = require 'ffi'
	-- passing in void* cdata
	lua([[
local result = ...
assert.eq(result, require 'ffi'.cast('void*', 42))
]], ffi.cast('void*', 42))
	assert.eq(lua:gettop(), 0)

	-- returning void* cdata
	local result = lua([[return require 'ffi'.cast('void*', 42)]])
	assert.eq(result, ffi.cast('void*', 42))
	assert.eq(lua:gettop(), 0)

	-- passing in int* cdata
	lua([[
local ffi = require 'ffi'
local result = ...
assert.eq(result, ffi.cast('int*', 42))
assert.eq(ffi.typeof(result), ffi.typeof('int*'))
assert.ne(ffi.typeof(result), ffi.typeof('void*'))
]], ffi.cast('int*', 42))
	assert.eq(lua:gettop(), 0)

	--[=[ returning int* cdata
-- NOT working yet cuz the current code casts the returned type
-- and for function-pointers that means creating a new closure and screwing things up
	local result = lua([[return require 'ffi'.cast('int*', 42)]])
	assert.eq(result, ffi.cast('int*', 42))
	assert.eq(ffi.typeof(result), ffi.typeof('int*'))
	assert.ne(ffi.typeof(result), ffi.typeof('void*'))
	assert.eq(lua:gettop(), 0)
	--]=]
end

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
	assert.eq(lua:gettop(), 0)
end

-- global access
do
	lua[[t = {k=42}]]
	assert.eq(lua:gettop(), 0)
--[[
	assert.eq(lua.global.t.k, 42)
--]]
-- [[
	local tmp = lua.global.t
	assert.eq(lua:gettop(), 0)
	assert.eq(tmp.k, 42)
	assert.eq(lua:gettop(), 0)
--]]
	assert.eq(lua:gettop(), 0)
	-- notice that values are copied across lua states, so setting t.k won't reflect on the other side
	-- I could get around this by making proxy objects everywhere like I do in my [lua-interop](https://github.com/thenumbernine/lua-ffi-wasm/blob/master/lua-interop/lua-interop.js) Lua/JS implementation.
	-- but that brings a performance overhead with it
	lua.global.t = {v=43}
	assert.eq(lua:gettop(), 0)
	lua[[assert.eq(t.v, 43)]]
	assert.eq(lua:gettop(), 0)
end

do
	lua.global.t = {'a', 'b', 'c'}
	assert.eq(lua:gettop(), 0)
	lua[[
assert.eq(#t, 3)
assert.eq(t[1], 'a')
assert.eq(t[2], 'b')
assert.eq(t[3], 'c')
]]
	assert.eq(lua:gettop(), 0)
end

assert.eq(lua:gettop(), 0)
lua:close()
print'done'
