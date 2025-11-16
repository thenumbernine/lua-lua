require 'ext.gc'	-- allow __gc for luajit
local ffi = require 'ffi'
local lib = require 'lua.ffi'
local assert = require 'ext.assert'
local class = require 'ext.class'


local void_pp = ffi.typeof'void**'
local size_t_1 = ffi.typeof'size_t[1]'


local Lua = class()

function Lua:init()
	local L = lib.luaL_newstate()
	if not L then error("luaL_newstate failed", 2) end
	self.L = L
	lib.luaL_openlibs(L)

	-- while we're here, create a default Lua error handler, and save it somewhere
	self:assert(lib.luaL_loadstring(L, [[return tostring((...)) .. '\n' .. debug.traceback()]]))
	self.errHandlerRef = lib.luaL_ref(L, lib.LUA_REGISTRYINDEX)
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
	local L = self.L
	local errcode = ...
	if not errcode then return ... end
	if errcode == lib.LUA_OK then return ... end
	assert.eq(lib.lua_type(L, -1), lib.LUA_TSTRING)
	local chr = lib.lua_tostring(L, -1)
	local str = ffi.string(chr)
	error(str, errcode)
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
		self:assert(lib.luaL_loadbuffer(L, str, #str, 'Lua:pushargs'))
	--elseif t == 'thread' then
	--	TODO string.buffer serialization?
	--elseif t == 'table' then
	else
		print('WARNING: idk how to push '..t)
		lib.lua_pushnil(L)
	end

	return self:pushargs(n-1, ...)
end

function Lua:getstring(i)
	local L = self.L
	local len = ffi.new(size_t_1)
	local ptr = lib.lua_tolstring(L, i, len)
	return ptr ~= nil and ffi.string(ptr, len[0]) or nil
end

-- get stack location
function Lua:getstack(i)
	local L = self.L
	local luatype = lib.lua_type(L, i)
	if luatype == lib.LUA_TNONE
	or luatype == lib.LUA_TNIL
	then
		-- it's already nil
	elseif luatype == lib.LUA_TBOOLEAN then
		return 0 ~= lib.lua_toboolean(L, i)
	elseif luatype == lib.LUA_TLIGHTUSERDATA then
		return lib.lua_topointer(L, i)	-- is this ok?
	elseif luatype == lib.LUA_TNUMBER then
		return lib.lua_tonumber(L, i)
	elseif luatype == lib.LUA_TSTRING then
		return self:getstring(i)
	--elseif luatype == lib.LUA_TTABLE then
	elseif luatype == lib.LUA_TFUNCTION then
		-- same trick as above? string.dump and reload?
		lib.lua_rawgeti(L, lib.LUA_REGISTRYINDEX, self.errHandlerRef)
		local errHandlerLoc = lib.lua_gettop(L)	-- errHandler
		lib.lua_getglobal(L, 'string')			-- errHandler, string
		lib.lua_getfield(L, -1, 'dump')			-- errhandler, string, dump
		lib.lua_remove(L, -2)					-- errHandler, dump
		lib.lua_pushvalue(L, i)					-- errHandler, dump, i
		self:assert(lib.lua_pcall(L, 1, 1, errHandlerLoc))	-- result
		local data = self:getstring(-1)
		lib.lua_pop(L, 1)
		return load(data)
	--elseif luatype == lib.LUA_TUSERDATA then
		-- return a string binary-blob of the data?
	--elseif luatype == lib.LUA_TTHREAD
	--elseif luatype == lib.TPROTO
	elseif luatype == lib.LUA_TCDATA then
		local ptr = lib.lua_topointer(L, i)
		-- I guess all LuaJIT cdata's hold ... pointers ... ? always?
		-- I suspect this can get me into trouble:
		local result = ffi.cast(void_pp, ptr)
		if result == nil then return nil end
		return result[0]
	else
		print("WARNING: idk how to pop "..tostring(luatype))
		return nil
	end
end

function Lua:popargs(n, i)
	if n <= 0 then return end
	-- how are args evaluated? left-to-right?
	local result = self:getstack(i)
	return result, self:popargs(n-1, i+1)
end

function Lua:settop(top, ...)
	lib.lua_settop(self.L, top)
	return ...
end

-- this is very specific to pureffi/threads.lua's "threads.new" function
-- loads 'code' in the enclosed Lua state
-- serializes and passes any args into 'code's function
-- calls the function
-- returns the results, cast as a uintptr_t*
function Lua:run(code, ...)
	local L = self.L
	local top = lib.lua_gettop(L)

	-- push error handler first
	lib.lua_rawgeti(L, lib.LUA_REGISTRYINDEX, self.errHandlerRef)
	local errHandlerLoc = lib.lua_gettop(L)

	-- push functin next
	self:assert(lib.luaL_loadstring(L, code))

	-- push args next
	-- this is a serialize-deserialize layer to ensure that whatever is passed through changes to the new Lua state
	local n = select('#', ...)
	self:pushargs(n, ...)

	self:assert(lib.lua_pcall(L, n, lib.LUA_MULTRET, errHandlerLoc))
	local newtop = lib.lua_gettop(L)

	-- convert args on stack, reset top, and return converted args
	return self:settop(top, self:popargs(newtop - (top+1), top+2))
end

function Lua:__call(code, ...)
	return self:run(code, ...)
end

return Lua
