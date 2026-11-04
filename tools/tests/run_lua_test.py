"""Run a Lua 5.1 module regression with the installed SDK's Lua runtime."""
import ctypes
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
lua = ctypes.CDLL(str(root.parent/'ogsr-sdk/bin/editors/lua51.dll'))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise RuntimeError('Cannot initialize SDK Lua 5.1')
try:
    lua.luaL_openlibs(state)
    source = Path(sys.argv[1]).read_text(encoding='utf-8-sig')
    test = Path(sys.argv[2]).read_text(encoding='utf-8-sig')
    script = ('module_source=[====['+source+']====];\n'+test).encode('utf-8')
    result = lua.luaL_loadstring(state, script) or lua.lua_pcall(state, 0, 0, 0)
    if result:
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode('utf-8', 'replace'))
finally:
    lua.lua_close(state)
