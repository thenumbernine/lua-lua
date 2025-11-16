if jit then
return require 'lua.ffi.luajit'
else
return require 'lua.ffi.lua54'
end
