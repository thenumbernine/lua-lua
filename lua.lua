require 'ext.gc'	-- allow __gc for luajit
local ffi = require 'ffi'

-- TODO This will need to vary with what underlying Lua is used to require() this file.
-- Also TODO rename ffi/lua.lua to ffi/lua5.3.lua or whatever version I generated it from.
local lib = require 'ffi.req' 'luajit'

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

--local top = lib.lua_gettop(L)
--print("top", top)
	-- while we're here, create a default Lua error handler, and save it somewhere
	--local result = lib.luaL_loadstring(L, "return tostring((...))..'\n'..debug.traceback()")
	--local result = lib.luaL_loadstring(L, "return _G.tostring((...))")	-- "attempt to call a string value"
	--local result = lib.luaL_loadstring(L, "assert(type((...)), 'string') return 'here'") -- works
	--local result = lib.luaL_loadstring(L, "assert(type((...)), 'string') return ...") -- works
	local result = lib.luaL_loadstring(L, "return ...") -- works
	if result ~= lib.LUA_OK then
		error("luaL_loadstring error handler failed")
	end
--assert(lib.lua_type(L, lib.lua_gettop(L)), lib.LUA_TFUNCTION)
	self.errHandlerRef = lib.luaL_ref(L, lib.LUA_REGISTRYINDEX)

--assert.eq(top, lib.lua_gettop(L))
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
--print('Lua:assert got error', errcode)
	assert.eq(lib.lua_type(L, -1), lib.LUA_TSTRING)
	local chr = lib.lua_tostring(L, -1)
	local str = ffi.string(chr)
--print('Lua:assert str', str)
	error(str, errcode)
end

function Lua:getglobal(f)
	lib.lua_getfield(self.L, lib.LUA_GLOBALSINDEX, 'load')
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
		--[[
		local str = string.dump(x)
		lib.lua_rawgeti(L, lib.LUA_REGISTRYINDEX, self.errHandlerRef)
		local errHandlerLoc = lib.lua_gettop(L)
		lib.luaL_loadbuffer(L, str, #str, 'Lua:pushargs')
		lib.lua_pcall(L, 1, 1, errHandlerLoc )
		lib.lua_remove(L, errHandlerLoc)
		--]]
	--elseif t == 'thread' then
	--	TODO string.buffer serialization?
	--elseif t == 'table' then
	else
		print('WARNING: idk how to push '..t)
		lib.lua_pushnil(L)
	end

	return self:pushargs(n-1, ...)
end

function Lua:get(i)
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
		local len = ffi.new(size_t_1)
		local ptr = lib.lua_tolstring(L, i, len)
		return ptr ~= nil and ffi.string(ptr, len[0]) or nil
	--elseif luatype == lib.LUA_TTABLE then
	--elseif luatype == lib.LUA_TFUNCTION then
		-- same trick as above? string.dump and reload?
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
	local result = self:get(i)
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
--print('Lua:run() begin')
--print(require'template.showcode'(code))
	local L = self.L
	local top = lib.lua_gettop(L)
--print('top', top)
	-- push error handler first
	lib.lua_rawgeti(L, lib.LUA_REGISTRYINDEX, self.errHandlerRef)
	local errHandlerLoc = lib.lua_gettop(L)
--print('errHandlerLoc', errHandlerLoc)
--assert.eq(errHandlerLoc, top+1)
--assert(lib.lua_type(L, errHandlerLoc), lib.LUA_TFUNCTION)

	-- push functin next
	self:assert(lib.luaL_loadstring(L, code))
--local funcloc = lib.lua_gettop(L)
--print('funcloc', funcloc)
--assert.eq(errHandlerLoc+1, funcloc)
--assert(lib.lua_type(L, funcloc), lib.LUA_TFUNCTION)

	-- push args next
	-- this is a serialize-deserialize layer to ensure that whatever is passed through changes to the new Lua state
	local n = select('#', ...)
--print('nargs', n)
	self:pushargs(n, ...)
--assert.eq(funcloc+n, lib.lua_gettop(L))
--print('top after pushing args', lib.lua_gettop(L))

--print('lib.lua_pcall', L, n, lib.LUA_MULTRET, errHandlerLoc)
	local result = lib.lua_pcall(L, n, lib.LUA_MULTRET, errHandlerLoc)
--print('pcall result', result)
	local newtop = lib.lua_gettop(L)
--print('pcall newtop', newtop)
	if result ~= lib.LUA_OK then
--assert.eq(lib.lua_gettop(L), newtop)
--assert.eq(lib.lua_type(L, newtop), lib.LUA_TSTRING)	-- not always true
		-- rethrow error
		--local err = self:get(newtop)	-- it's a string, right?
		--self:settop(top)
		local err = ffi.string(lib.lua_tostring(L, newtop))
		lib.lua_pop(L, 1)
		error('Lua:run(): '..tostring(err))
	end

--print('Lua:run() end')
	-- convert args on stack, reset top, and return converted args
	return self:settop(top, self:popargs(newtop - (top+1), top+2))
end

function Lua:__call(code, ...)
	return self:run(code, ...)
end

return Lua
