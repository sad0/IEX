#pragma once

// Native combat / UI hooks for mods written against EEex's x64 hook API (StickLuaFunctions' ST_RegisterHook_*).
// IEX has no asm/JIT engine: each behaviour such a mod patches into the engine is implemented here in C++ (call-site
// hooks on both platforms), and the mod's Lua callback is called at the same moment with the same arguments.
// The mod's hook requests (EEex_Hook*(address, ...) calls, lua/IEX_NativeHooks.lua) say which behaviours are on and
// which Lua function each one calls. See docs/API_SPEC.md, "Native hooks".
struct lua_State;

namespace iex {

void InstallStickHooks();
void OpenLuaStickHooks(lua_State* L);

} // namespace iex
