#pragma once

// Class spell lists past the SPWI/SPPR numbering (native switch "spellLists").
//
// The engine builds every class spell list (chargen and level-up choices, sorcerer / bard picks, dual-class, the
// priests' automatic spells) by asking CRuleTables::GetMageSpell / GetPriestSpell(level, index) for index 0, 1,
// 2... Those getters only format "SPWI<level><index+1, 2 digits>" and stop at slot 50 (99 with spellSlots99): the
// spell.ids scheme (type*1000 + level*100 + n) cannot go further.
//
// With the switch, every call site of the two getters (and of CRuleTables::GetNumPriestSpells, the loop count of
// the priests' automatic spells and of dual-class) goes through IEX:
//   index < base            the engine's own answer, unchanged (base = 50, or 99 once spellSlots99 is on)
//   index = base + k        entry k of the IEX list of that type and level (any resref, set by mods)
//   past the list           the empty resref, which ends the engine's loops
//   GetNumPriestSpells      min(SPELLS.2DA value, base) + list size when the list is not empty; the GetPriestSpell
//                           calls of those loops (priests' automatic spells, dual-class) put the list right after
//                           min(SPELLS.2DA, base), so a lower SPELLS.2DA value still limits the engine slots
//   MageSchoolSpellsAvailable  (specialist bonus slot) also scans slots 51-99 and the list (register hook on its
//                           GetMageSpell call that drives the fixed 0..49 loop counter)
// Lists: IEX_SpellList_Add / Remove / Get / Clear (Lua), filled from IEXSPLST.2DA by lua/IEX_SpellLists.lua.
// The engine's getters are not modified (only the call instructions), so spellSlots99 keeps working, on or off.

struct lua_State;

namespace iex {

// Registers the "spellLists" installer.
void InstallSpellListHooks();

// IEX_SpellList_Add / Remove / Get / Clear / Count.
void OpenLuaSpellLists(lua_State* L);

} // namespace iex
