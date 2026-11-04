#pragma once

struct lua_State;

namespace iex {

// EEex.GetINIString / EEex.SetINIString (lua_ini.cpp).
void OpenLuaIni(lua_State* L);

} // namespace iex

