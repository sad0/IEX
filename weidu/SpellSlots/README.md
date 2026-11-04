# SpellSlots

Wizard and priest spells in slots 51-99 (`SPWI<level>51`-`99`, `SPPR<level>51`-`99`) become available like slots
01-50: mage / sorcerer / bard choices at chargen and level-up, dual-class, and the spells priests get automatically.

The unmodded engine stops these class spell lists at slot 50 (`CRuleTables::GetMageSpell` / `GetPriestSpell`).
Spells in 51-99 work in scripts, but players can never pick them.

## Install

Right after IEX or EEex, before spell mods, ClassSpellTool mods and SFO mods. BGEE, BG2EE, EET.

- `SPELLS.2DA`: the `MAGE` and `PRIEST` rows set to 99.
- `HIDESPL.2DA`: the engine's own NPC / internal spells in 51-99 that were not hidden yet (`SPPR599 698 699`,
  `SPWI961-965`, BGEE `SPWI975`), so they never reach the player lists.
- `M_SPSLOT.lua`: at game start, moves the engine bound from 50 to 99.
  - IEX: native hook point `spellSlots99` (Windows + Linux, 2.7.3).
  - EEex: byte patch on Windows 2.6.6 / 2.7.3, only when the game's bytes are found unchanged.
  - `SpellSlots_Status` tells what happened.

## Limits

- WeiDU's `ADD_SPELL` still fills slots 01-50 only, so this mod alone does not fix
  `Couldn't add ... no slots remain`. See the WeiDU proposal (it reads `SPELLS.2DA`).
- Auto-pick ("Pick For Me") and the specialist check still only look at slots 01-50.
- SFO's `ui_extra_spells` also injects 51-99 spells into the chargen list. Check for duplicates
  before using both.
