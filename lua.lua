require 'ext.gc'	-- allow __gc for luajit
local ffi = require 'ffi'
local buffer = require 'string.buffer'
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

	-- create a default Lua error handler
	self:load[[
return tostring((...)) .. '\n' .. debug.traceback()
]]
	self.errHandlerRef = self:makeref()

	-- create table serialization functions
	local top = self:gettop()
	self:runAndPush[[
local buffer = require 'string.buffer'
local function serTable(x)
	return buffer.encode(x)
end
local function deserTable(s)
	return buffer.decode(s)
end
return serTable, deserTable
]]
assert.eq(self:gettop(), top+3)
	self.deserTableRef = self:makeref()
	self.serTableRef = self:makeref()
	self:settop(top)

	-- index access if you don't mind the overhead
	self.global = setmetatable({}, {
		__index = function(t, name)
			return self:globalrw(name)
		end,
		__newindex = function(t, name, value)
			return self:globalrw(name, value)
		end,
	})
end

function Lua:gettop()
	return lib.lua_gettop(self.L)
end

function Lua:makeref()
	return lib.luaL_ref(self.L, lib.LUA_REGISTRYINDEX)
end

function Lua:pushref(ref)
	lib.lua_rawgeti(self.L, lib.LUA_REGISTRYINDEX, ref)
end

function Lua:load(str, name)
	--self:assert(lib.luaL_loadstring(self.L, str))
	self:assert(lib.luaL_loadbuffer(self.L, str, #str, name or str))
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
		self:load(str, 'Lua:pushargs')
	--elseif t == 'thread' then
	--	TODO string.buffer serialization?
	elseif t == 'table' then

		local s = buffer.encode(x)
		self:pushref(self.deserTableRef)
		lib.lua_pushlstring(L, ffi.cast('char*', s), #s)
		lib.lua_pcall(L, 1, 1, 0)

	else
		print('WARNING: idk how to push '..t)
		lib.lua_pushnil(L)
	end

	return self:pushargs(n-1, ...)
end

-- get stack location as bool
function Lua:getboolean(i)
	return 0 ~= lib.lua_toboolean(self.L, i)
end

function Lua:getpointer(i)
	return lib.lua_topointer(self.L, i)
end

function Lua:getnumber(i)
	return lib.lua_tonumber(self.L, i)
end

-- get stack location as string
function Lua:getstring(i)
	local len = ffi.new(size_t_1)
	local ptr = lib.lua_tolstring(self.L, i, len)
	return ptr ~= nil and ffi.string(ptr, len[0]) or nil
end

function Lua:gettable(i)
	local L = self.L

	self:pushref(self.serTableRef)
	lib.lua_pushvalue(L, i)
	lib.lua_pcall(L, 1, 1, 0)
	local s = self:getstring(-1)
	return buffer.decode(s)
end

function Lua:getfunction(i)
	local L = self.L
	-- same trick as above? string.dump and reload?
	self:pushref(self.errHandlerRef)
	local errHandlerLoc = self:gettop()		-- errHandler
	lib.lua_getglobal(L, 'string')			-- errHandler, string
	lib.lua_getfield(L, -1, 'dump')			-- errhandler, string, dump
	lib.lua_remove(L, -2)					-- errHandler, dump
	lib.lua_pushvalue(L, i)					-- errHandler, dump, i
	self:assert(lib.lua_pcall(L, 1, 1, errHandlerLoc))	-- result
	local data = self:getstring(-1)
	lib.lua_pop(L, 1)
	return load(data)
end

function Lua:getcdata(i)
	local ptr = lib.lua_topointer(self.L, i)
	-- I guess all LuaJIT cdata's hold ... pointers ... ? always?
	-- I suspect this can get me into trouble:
	local result = ffi.cast(void_pp, ptr)
	if result == nil then return nil end
	return result[0]
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
		return self:getboolean(i)
	elseif luatype == lib.LUA_TLIGHTUSERDATA then
		return self:getpointer(i)	-- is this ok?
	elseif luatype == lib.LUA_TNUMBER then
		return self:getnumber(i)
	elseif luatype == lib.LUA_TSTRING then
		return self:getstring(i)
	elseif luatype == lib.LUA_TTABLE then
		return self:gettable(i)
	elseif luatype == lib.LUA_TFUNCTION then
		return self:getfunction(i)
	--elseif luatype == lib.LUA_TUSERDATA then
		-- return a string binary-blob of the data?
	--elseif luatype == lib.LUA_TTHREAD
	--elseif luatype == lib.TPROTO
	elseif luatype == lib.LUA_TCDATA then
		return self:getcdata(i)
	else
		print("WARNING: idk how to pop "..tostring(luatype))
		return nil
	end
end

-- pop args from stack, convert them, and return them
function Lua:popargs(n, i)
	if n <= 0 then return end
	-- how are args evaluated? left-to-right?
	local result = self:getstack(i)
	return result, self:popargs(n-1, i+1)
end

-- read/write a global
function Lua:globalrw(name, ...)
	local L = self.L
	if select('#', ...) > 0 then
		-- write a global
		self:pushargs(1, (...))
		lib.lua_setglobal(L, name)
	else
		-- read a global
		lib.lua_getglobal(L, name)
		return self:popargs(1, self:gettop())
	end
end

function Lua:settop(top, ...)
	lib.lua_settop(self.L, top)
	return ...
end

-- runs `code`
-- accepts Lua args
-- but leaves results on the stack 
-- also leaves the error handler on the stack under them
function Lua:runAndPush(code, ...)
	local L = self.L

	-- push error handler first
	self:pushref(self.errHandlerRef)
	local errHandlerLoc = self:gettop()

	-- push functin next
	self:load(code)

	-- push args next
	-- this is a serialize-deserialize layer to ensure that whatever is passed through changes to the new Lua state
	local n = select('#', ...)
	self:pushargs(n, ...)

	self:assert(lib.lua_pcall(L, n, lib.LUA_MULTRET, errHandlerLoc))
end

-- this is very specific to pureffi/threads.lua's "threads.new" function
-- loads 'code' in the enclosed Lua state
-- serializes and passes any args into 'code's function
-- calls the function
-- returns the results, cast as a uintptr_t*
function Lua:run(code, ...)
	local top = self:gettop()
	self:runAndPush(code, ...)
	local newtop = self:gettop()

	-- convert args on stack, reset top, and return converted args
	return self:settop(top, self:popargs(newtop - (top+1), top+2))
end

function Lua:__call(code, ...)
	return self:run(code, ...)
end

return Lua
