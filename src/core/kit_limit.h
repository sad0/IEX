#pragma once

// Unlimited single-class kits (feature "kitLimit", docs/KIT_LIMIT.md).
//
// CRuleTables keeps the CLAB table of each kit in a fixed array of 256 C2DArray* (filled by its constructor for
// KITLIST rows 1..256 only), and CRuleTables::GetClassAbilityTable(class, kit) reads array[row - 1] with no upper
// bound: a single-class kit on KITLIST row 257 or higher reads past the array (crash or garbage abilities at chargen,
// level-up, AddKit, dual-class, level drain).
//
// With the feature, the two callers of GetClassAbilityTable (CGameSprite::AddClassAbilities and
// RemoveClassAbilities) call IEX instead:
//   kit without the 0x4000 flag, row 0, row <= 256, row past KITLIST, KITLIST CLASS != class
//                     the engine's own answer, unchanged
//   otherwise         IEX's CLAB table for that row: a C2DArray loaded on first use from KITLIST's ABILITIES column
//                     with the engine's own C2DArray::Load, kept for the session
// New limit: KITLIST row 16383 (the 0x4000 kit flag in the low word of the kit value). No CRE / save change.
//
// On by default. Baldur.lua: SetPrivateProfileString('IEX','Unlimited Kits','0') turns it off (read at start).
// Environment (takes precedence): IEX_KIT_LIMIT=0 / 1.
// Lua: IEX_Features.kitLimit = patched call sites (0 when off), IEX_KitLimit() -> {installed, sites, engineSlots,
// maxRow, tables, why}.

struct lua_State;

namespace iex {

// Installs the feature on the first call, then IEX_Features.kitLimit and IEX_KitLimit().
void OpenLuaKitLimit(lua_State* L);

} // namespace iex
