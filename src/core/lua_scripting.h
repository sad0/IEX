#pragma once

// Engine script parsing and evaluation for Lua (EEex_Object_ParseString, EEex_Trigger_ParseConditionalString,
// EEex_Action_ParseResponseString, EEex_*_GetAllOfTypeInRange) and a few creature queries (visual range,
// personal space). The EEex-compatible names are bound in lua/EEex_TA.lua.
struct lua_State;

namespace iex {

// Registers the IEX_* functions. Call once on the engine Lua state.
void OpenLuaScripting(lua_State* L);

// Redirects the engine's CAIObjectType::Decode calls so script objects can name EEex_LuaObject and
// EEex_Target("name"). Call once, with the other engine hooks.
void InstallScriptingHooks();

} // namespace iex
