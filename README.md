# LuaJIT for LuaJIT

I know the repo name is `lua-lua`, but it's directly tied to the LuaJIT ffi library so it is in fact LuaJIT-for-LuaJIT.

Create your own distinct `lua_State`'s in LuaJIT.

Allows passing data between states.

Use the `__call` operator to execute code on the new state.

Example:

```
local lua = require 'lua'()
local y = lua([[
local f = ...
assert(f(2) == 3)
return f(4)
]], function(x) return x + 1 end)
assert(y == 5)
```
