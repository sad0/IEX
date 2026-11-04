#pragma once

// EEex-compatible effects and script extensions (see lua/EEex_Opcode.lua for the Lua side):
//   - "OpcodeListsResolved" event after a sprite's effect lists were re-evaluated
//     (EEex_Opcode_AddListsResolvedListener);
//   - opcode 401 (extended stats, X-STATS.2DA), 402 (invoke Lua), 403 (screen incoming effects);
//   - EEex_GameObject_ApplyEffect (IEX_ApplyEffect);
//   - script trigger EEex_LuaTrigger / EEex_IsImmuneToOpcode and action EEex_LuaAction.
struct lua_State;

namespace iex {

// Installs the engine hooks. Call after InstallEffectHooks (needs the inert effect vtable).
void InstallOpcodeHooks();

// Registers the IEX_* functions and keeps the Lua state for the hooks. Call once on the engine Lua state.
void OpenLuaOpcodes(lua_State* L);

} // namespace iex
