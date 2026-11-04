#pragma once

// Native side of the player modules (EEex.ini [X Module] Enable; Lua side in lua/IEX_Modules.lua).
//   - Empty Container: CGameContainer::Render (its vtable slot) records the container being drawn; the
//     CInfinity::OutlinePoly calls in Render are redirected, and for a highlight outline (hover / Tab, not the
//     red permanent one) the Lua global B3EmptyContainer_Hook_OnBeforeContainerOutlineRender(container, color)
//     runs first; color.value (IEX_UIntValue) is the color drawn. The highlight call site is published as the
//     EEex label "Hook-CGameContainer::Render()-B3EmptyContainer" (SadoEE reads the code after it).
//     IEX_SetEmptyContainerHook(on) turns the Lua call on or off (the module enables it).
#include <cstdint>

struct lua_State;

namespace iex {

void OpenLuaModules(lua_State* L);
// The permanent (red) outline of a container whose m_drawPoly == marker is drawn in the color (0xBBGGRR) stored at
// colorAddress, read each time (SadoEE #21 valuable containers). False when the outline hook is not installed.
bool SetContainerMarkerColor(std::uintptr_t colorAddress, int marker);
void InstallModuleHooks();

} // namespace iex
