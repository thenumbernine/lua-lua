require 'ext.gc'	-- allow __gc for luajit
local ffi = require 'ffi'
local assert = require 'ext.assert'

-- TODO This will need to vary with what underlying Lua is used to require() this file.
-- Also TODO rename ffi/lua.lua to ffi/lua5.3.lua or whatever version I generated it from.
local lib = require 'ffi.req' 'luajit'

local class = require 'ext.class'
local Lua = class()

function Lua:init()
	self.L = lib.luaL_newstate()
	if not self.L then error("luaL_newstate failed", 2) end
	lib.luaL_openlibs(self.L)
end

function Lua:close()
	if self.L then
		lib.lua_close(self.L)
		self.L = nil
	end
end

function Lua:__gc()
	return self:close()
end

function Lua:assert(...)
	if not ret then return ... end
	if ret == 0 then return ... end
	local chr = lib.lua_tolstring(L, -1, nil)
	error(ffi.string(chr), 2)
end

function Lua:pushargs(n, x, ...)
	if n <= 0 then return end
	local L = self.L

	local t = type(x)
	if t == 'nil' then
		lib.lua_pushnil(L)
	elseif t == 'number' then
		lib.lua_pushnumber(L, x)
	elseif t == 'string' then
		lib.lua_pushlstring(L, x, #x)
	elseif t == 'boolean' then
		lib.lua_pushboolean(L, x and 1 or 0)
	elseif t == 'function' then
		local str = string.dump(x)
		lib.lua_pushlstring(L, str, #str)
	-- threads
	-- tables
	else
		print('WARNING: idk how to push '..t)
		lib.lua_pushnil(L)
	end

	return self:pushargs(n-1, ...)
end

-- this is very specific to pureffi/threads.lua's "threads.new" function
-- loads 'code' in the enclosed Lua state
-- serializes and passes any args into 'code's function
-- calls the function
-- returns the results, cast as a uintptr_t*
function Lua:loadfunc(code, ...)
	local L = self.L
	self:assert(lib.luaL_loadstring(L, code))

	-- this is a serialize-deserialize layer to ensure that whatever is passed through 'func' changes context to the new Lua state
	local n = select('#', ...)
	self:pushargs(n, ...)

	self:assert(lib.lua_pcall(L, n, 1, 0))
	local ptr = lib.lua_topointer(L, -1)
	lib.lua_settop(L, -2)

	-- and here we assert that code's function passes back a uintptr_t[1] of the closure-cast function ptr of the function it wants to return
	-- (while saving a ref of it in the enclosed Lua state so it doesnt get gc'd)
	local box = ffi.cast("uintptr_t*", ptr)
	if box == nil then return nil end
	return box[0]
end

return Lua
