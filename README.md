# LuaJIT for LuaJIT

I know the repo name is `lua-lua`, but it's directly tied to the LuaJIT ffi library so it is in fact LuaJIT-for-LuaJIT.

I spun this off of [CapsAdmin luajit-pureffi/threads.lua](https://github.com/CapsAdmin/luajit-pureffi/blob/main/threads.lua),
which makes use of LuaJIT-within-LuaJIT calls, and then just kept wrapping classes and adding more OOP bureaucracy.

Create your own distinct `lua_State`'s in LuaJIT.

Allows passing data between states.

- `Lua = require 'lua'`
- `lua = Lua()` = create a new Lua state
- `lua:close()` = close Lua state.  This is automatically called upon `__gc`
- `lua:run(code, ...)` = runs `code`, passes in `...` as args, returns whats returned.
- `lua:load(code, [name])` = loads the code and pushes it onto the stack using `luaL_loadbuffer`.
- `lua:globalrw(name, [value])` = gets/sets the global with name `name`.
- `lua:global[name] [= value]` = same as `lua:globalrw()` but if you prefer index access.
- `lua:pushargs(n, ...)` = push `n` args from Lua data into the Lua state's stack.
- `lua:popargs(n, i)` = pops `n` arguments starting at location `i` from the Lua state's stack and returns them.
- `lua:getstack(i)` = returns the i'th stack location as Lua data.
- `lua:getboolean(i)` = returns the i'th stack location as a boolean.
- `lua:getpointer(i)` = returns the i'th stack location as a `lua_topointer`.
- `lua:getnumber(i)` = returns the i'th stack location as a number.
- `lua:getstring(i)` = returns the i'th stack location as a string.
- `lua:gettable(i)` = returns the i'th stack location as a table.
- `lua:getfunction(i)` = returns the i'th stack location as a function.
- `lua:getcdata(i)` = returns the i'th stack location as if it were cdata, i.e. using `lua_topointer` then returning the pointer within the pointer.
- `lua:assert(err, ...)` = asserts that `err` is equal to 0 i.e. `LUA_OK`. If not then raises an error with the top value on stack as the error string.

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

# LangFix

I also provide support for my [langfix](http://github.com/thenumbernine/langfix-lua) library:

- `LuaFixed = require 'lua.langfix'`
- `lua = LuaFixed()`

... and now you can use langfix operators in your Lua state's code.
