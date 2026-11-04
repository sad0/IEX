#pragma once

#include <string>

struct lua_State;

namespace iex {

// Settings files that EEex-dependent mods write or test, read once at startup from the game folder:
//   InfinityLoader.ini [General]: LuaPatchMode (EXTERNAL / REPLACE_INTERNAL_WITH_EXTERNAL give mods the io / os
//     libraries, as under EEex's LuaJIT mode), LogFile (Lua print() output mirrored to that file).
//   EEex.ini [<name> Module] Enable: EEex's module switches (EEex_Modules in Lua).
void LoadSettings(const std::string& gameDir);

// IEX_Settings (the parsed files), io / os when LuaPatchMode asks for them, the print() mirror, and
// IEX_ReadINIFile / IEX_WriteINIFile (INI files in the game folder, for EEex_Options' INI storages).
void OpenLuaSettings(lua_State* L);

} // namespace iex
