-- Lua state wrapper but with langfix load()
local Lua = require 'lua'

local LuaFixed = Lua:subclass()

LuaFixed.load = |:, data, source| do
	-- should I be exposing `langfix` as a global?
	return LuaFixed.super.load(self, langfix.luaToFixed(data), source)
end

return LuaFixed
