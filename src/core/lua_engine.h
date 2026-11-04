#pragma once

struct lua_State;

namespace iex {

// Registers the IEX_* Lua functions that call engine code (menu files, keyboard).
void OpenLuaEngine(lua_State* L);

} // namespace iex
