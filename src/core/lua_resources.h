#pragma once

struct lua_State;

namespace iex {

// Registers the IEX_* Lua functions that read game resources (IEX_ResourceData, IEX_ResourceText).
// The EEex-compatible EEex_Resource_* names are built on them in lua/EEex_Resource.lua.
void OpenLuaResources(lua_State* L);

} // namespace iex
