#pragma once

// Action bar (CInfButtonArray) hooks and Lua helpers behind lua/EEex_Actionbar.lua.
struct lua_State;

namespace iex {

// Hooks the call sites of CInfButtonArray::SetState / UpdateButtons. Events:
//   ActionbarStateChanged   SetState rebuilt the button kinds; listeners may rewrite m_buttonTypes before
//                           UpdateButtons turns them into buttons.
//   ActionbarButtonsUpdated UpdateButtons finished (outermost call only).
void InstallActionbarHooks();

// Registers IEX_ActionbarSetState(array, state) and IEX_ActionbarUpdate(array).
void OpenLuaActionbar(lua_State* L);

} // namespace iex
