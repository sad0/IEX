#pragma once

// Native engine hook points exposed to Lua, the same on Windows and Linux (docs/API_SPEC.md, "Native hook points").
// They replace engine patches some mods write in Windows x64 machine code (SadoEE #6 endless ammo, #11 attack-move):
// those patches cannot run on Linux, these hooks do the same thing from C++ on both builds.
//
//   keepAmmo         CGameSprite::Swing, its call of CItem::SetUsageCount(item, ability, count - 1) when a shot
//                    uses up one charge / one piece of ammo:
//                      IEX_NativeHook_KeepAmmo(sprite, item) -> true: the count stays as it was.
//   groundMoveClick  every engine call of CGameArea::OnActionButtonClickGround while the game state
//                    (CInfGame::m_nState) is 0, i.e. a ground click that gives a move order:
//                      IEX_NativeHook_GroundMoveClick(area, x, y), before the engine handles the click.
//
// The hooks are installed on demand (IEX_NativeHook_Install(name), from lua/IEX_NativeHooks.lua), never at
// startup, so a mod's own patch of the same site, installed when its M_*.lua file loads, wins: IEX then finds
// the site changed and leaves it alone.
struct lua_State;

namespace iex {

// Registers IEX_NativeHook_Install / IEX_NativeHook_Installed / IEX_NativeHook_Available and
// IEX_Features.nativeHooks / IEX_Features.platform and the IEX_Eng_* engine call functions.
void OpenLuaNativeHooks(lua_State* L);

} // namespace iex
