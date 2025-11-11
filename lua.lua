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

function Lua:load(code, func)
	local L = self.L
	self:assert(ffi.C.luaL_loadstring(L, code))
	local str = string.dump(func)
	ffi.C.lua_pushlstring(L, str, #str)
	self:assert(ffi.C.lua_pcall(L, 1, 1, 0))
	local ptr = ffi.C.lua_topointer(L, -1)
	ffi.C.lua_settop(L, -2)
	local box = ffi.cast("uintptr_t*", ptr)
	return box[0]
end

return Lua
