#pragma once

// Spell slots 51-99: CRuleTables::GetMageSpell / GetPriestSpell (SPWI<level><nn> / SPPR<level><nn>, the class spell
// lists of chargen, level-up, dual-class and the priests' automatic spells) return an empty resref past slot 50.
// The native hook point "spellSlots99" (a switch) moves that bound to 99 by changing the one compared byte in each
// function. The SpellSlots mod enables it (with SPELLS.2DA at 99 and the engine's own x51-x99 spells hidden);
// without it nothing changes, so vanilla's internal x51-x99 spells never reach the player lists.

namespace iex {

// Registers the "spellSlots99" installer.
void InstallSpellSlotHooks();

} // namespace iex
