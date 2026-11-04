#pragma once

#include <cstdint>

struct lua_State;

namespace iex {

// Registers the EEex raw memory API: EEex_Malloc/Free, EEex_Read*/Write*, strings, code protection,
// EEex_AllocNear, EEex_Label and EEex_ExposeToLua. Addresses are plain Lua numbers.
void OpenLuaMemory(lua_State* L);

// A label known only at run time (an address IEX found while hooking), answered by EEex_Label before the engine
// description's symbols.
void RegisterRuntimeLabel(const char* name, std::uintptr_t address);

} // namespace iex
