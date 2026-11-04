#pragma once

// Creature combat / spell-use moments exposed to Lua (EEex sprite listeners, Lua side in lua/EEex_TA.lua):
//   - CGameSprite::CheckQuickLists (a spell / item ability use changed its remaining count):
//       IEX_TA_QuickListsChecked(sprite, resref, changeAmount);
//   - CGameSprite::Damage called by CGameSprite::Swing (a weapon attack hit; Damage sends the weapon's on-hit
//     effects and returns the base weapon damage effect):
//       before: IEX_TA_BlockWeaponHit(attacker, target, weapon, launcher, abilityIndex) -> true blocks the damage
//               and the on-hit effects (Swing gets an inert effect instead);
//       after:  IEX_TA_AlterBaseWeaponDamage(attacker, target, effect, weapon, launcher, abilityIndex, isCritical,
//               isLeftHand, attackRoll);
//   - the d20 attack roll of CGameSprite::Hit (kept for attackRoll).
struct lua_State;

namespace iex {

void OpenLuaSpriteHooks(lua_State* L);
void InstallSpriteHooks();

// The attack roll of the current Hit was changed after IEX recorded it (native_stick.cpp): roll = d20 result (1..20).
void NoteHitRoll(int roll);

} // namespace iex
