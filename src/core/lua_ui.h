#pragma once

// UI menu objects (uiMenu / uiItem) behind lua/EEex_MenuUI.lua.
struct lua_State;

namespace iex {

// Hooks the call sites of drawItem(uiItem*, ...). Event:
//   BeforeUIItemRender(item)  an item whose name was registered with IEX_MenuWatchItemRender is about to be drawn.
void InstallUiHooks();

// Registers IEX_MenuFind, IEX_LuaRegistry, IEX_PointerToObject, IEX_MenuWatchItemRender.
void OpenLuaUi(lua_State* L);

} // namespace iex
