#!/bin/sh
# Regenerates every engine/*.iexd from the game-derived tables in E:/Dev/IEX-data (not in the repo).
# Hand-verified symbols (E:/Dev/IEX-data/engine/win/verified_*.json, with their evidence) override the
# automatically transferred Windows table; a few data globals and constants are given with --symbol / --const.
set -e
cd "$(dirname "$0")/../.."
DATA=E:/Dev/IEX-data
VERIFIED="--verified $DATA/engine/win/verified_t1a.json --verified $DATA/engine/win/verified_t1b.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_t1d_effects.json --verified $DATA/engine/win/verified_t1e_camera.json --verified $DATA/engine/win/verified_t1f_actions.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_fps.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_bar.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_opc.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_ta.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_ui.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_bgbot.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_instant.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_spell.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_vision.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_hooks.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_intro.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_values.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_modules.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_native.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_marshal.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_sado2.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_stick.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_path.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_prof.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_spelllist.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_hd.json"
VERIFIED="$VERIFIED --verified $DATA/engine/win/verified_fixes.json"
# Pathfinding Redux: CGameSprite search paint flags (m_bAddedToSearch-like at painted, "was painted" at repaint),
# creature category (counter choice), CGameAnimationType::GetPersonalSpace vtable offset, CSearchBitmap private
# snapshot pointer, CGameArea damage counter (CanSaveGame combat check, next to m_nBattleSongCounter).
PATHW="--const IEX.path.painted=0x5250 --const IEX.path.repaint=0x5254 --const IEX.path.category=0x492c --const IEX.path.vtPersonalSpace=0xc0 --const IEX.path.snapshot=0x128 --const IEX.path.damageCounter=0xfa8"
PATHL="--const IEX.path.painted=0x5238 --const IEX.path.repaint=0x523c --const IEX.path.category=0x4914 --const IEX.path.vtPersonalSpace=0xc8 --const IEX.path.snapshot=0x128 --const IEX.path.damageCounter=0xfa8"
# Party vision: CGameArea -> CVisibilityMap, CGameObject "seen" countdown, first 8 bytes of the replaced functions.
VIS="--const IEX.vis.areaMap=0xbb0 --const IEX.vis.objectActive=0x4c"
# Object ids (src/core/object_ids.cpp): CGameObjectArray statics on Windows (Linux has them in .symtab) and the
# CChitin multiplayer byte that CGameObjectArray::Add tests.
OBJW="--symbol _ZN16CGameObjectArray8m_nArrayE=0x68f8f0 --symbol _ZN16CGameObjectArray15m_maxArrayIndexE=0x68f8f4 --symbol _ZN16CGameObjectArray14m_nextObjectIdE=0x68f8f8 --symbol _ZN16CGameObjectArray17m_deletedListHeadE=0x68f8fc --symbol _ZN16CGameObjectArray16m_temporalNextIdE=0x68f900 --symbol _ZN16CGameObjectArray8m_pArrayE=0x68f910 --const IEX.objid.mpFlag=0x2c9"
OBJL="--const IEX.objid.mpFlag=0x2d1"
# spellLists (src/core/spell_lists.cpp): MageSchoolSpellsAvailable GetMageSpell call, GetNumPriestSpells-bounded priest calls.
SPLW="--const IEX.spellLists.schoolSite=0x2b718e --const IEX.spellLists.countedPriest.0=0x2a9280 --const IEX.spellLists.countedPriest.1=0x2b7810 --const IEX.spellLists.countedPriest.2=0x348bf0 --const IEX.spellLists.countedPriest.3=0x348e10"
SPLL="--const IEX.spellLists.schoolSite=0x34e445 --const IEX.spellLists.countedPriest.0=0x331c63 --const IEX.spellLists.countedPriest.1=0x331fb4 --const IEX.spellLists.countedPriest.2=0x35f624 --const IEX.spellLists.countedPriest.3=0x35f874 --const IEX.spellLists.countedPriest.4=0x49ecba --const IEX.spellLists.countedPriest.5=0x49f091"
# Engine fixes (src/core/engine_fixes.cpp, docs/ENGINE_FIXES.md): Swing speed-factor max() call and its registers
# (sprite | item << 8 | ability << 16, RegIndex), CGameEffect::CheckAdd immunity-string store, AddXPObject FeedBack call,
# CGameEffectXP vtable ApplyEffect slot. Each site is byte-checked at install.
FIXW="--const IEX.fix.swingMaxSite=0x3b8975 --const IEX.fix.swingRegs=0x0c0401 --const IEX.fix.checkAddSite=0x1cd011 --const IEX.fix.xpFeedbackSite=0x15fd47 --const IEX.fix.slot.xpApply=0x593cf0"
FIXL="--const IEX.fix.swingMaxSite=0x44dcd5 --const IEX.fix.swingRegs=0x0e0c0d --const IEX.fix.checkAddSite=0x1ef098 --const IEX.fix.xpFeedbackSite=0x171ec3 --const IEX.fix.slot.xpApply=0xcbfbc0"
python -I tools/engine/build_desc.py "$DATA/engine/types/win64-bg2ee-2.7.3.types.json" engine/win64-bg2ee-2.7.3.iexd \
  --binary "$DATA/win-2.7.3/bg2ee/Baldur.exe" --symbols "$DATA/engine/win64-bg2ee-2.7.3.symbols.json" \
  --hooks engine/hook_targets.txt --methods engine/methods.txt $VERIFIED \
  --symbol g_pBaldurChitin=0x667548 --symbol g_lua=0x667910 \
  --symbol menuSrc=0x717a50 --symbol g_backgroundMenu=0x717a38 --symbol g_overlayMenu=0x717a40 \
  --symbol g_tooltipSnd=0x717a20 \
  --symbol SDL_PollEvent=0x451e30 --symbol SDL_GetKeyFromName=0x449f80 \
  --symbol SDL_GetKeyboardState=0x44a250 --symbol SDL_GetScancodeFromKey=0x44a280 \
  --symbol SDL_malloc=0x3db720 --symbol SDL_free=0x3d6020 \
  --symbol _ZTV11CGameEffect=0x58f020 --const CGameEffect.vtable.header=0 --const CGameEffect.vtable.slots=11 \
  --const CChitin.Update.delaySite=0x41ccf6 --const CChitin.inSyncFlag=0xfb0 --const CChitin.framesPerSecond=0x1c8 --const CChitin.ticksPerSecond=0x1bc \
  --const CGameEffect.vtable.apply=0x10 --const IEX.vt.EffectDelete=0x0 --const IEX.vt.AddEffect=0xe8 \
  --const CGameEffect.vtable.copy=0x8 --const CGameEffect.vtable.onRemove=0x50 --const CGameAIBase.vtable.setScript=0x120 $VIS $PATHW $OBJW $SPLW $FIXW   --const IEX.vis.prologue.AddCharacter=0x74894818245c8948 --const IEX.vis.prologue.RemoveCharacter=0x74894808245c8948   --const IEX.vis.prologue.UpDate=0x74894808245c8948 --const IEX.vis.prologue.IsCharacterIdOnMap=0x3942c0bf0f4cc033   --const IEX.native.reprocessFlag=0x4ba4 --const IEX.native.stealthHidden=0x4e50 --const IEX.vis.prologue.PrivateAddCharacter=0x57565518245c8948 --const IEX.vis.removeFromAreaIsOnMapSite=0x36a4d0 --const CScreenStart.TimerAsynchronousUpdate.size=0x733
python -I tools/engine/build_desc.py "$DATA/engine/types/linux64-bg2ee-2.7.3.types.json" engine/linux64-bg2ee-2.7.3.iexd \
  --binary "$DATA/linux-2.7.3/bg2ee/BaldursGateII" --symbols "$DATA/engine/linux64-bg2ee-2.7.3.symbols.json" \
  --hooks engine/hook_targets.txt --methods engine/methods.txt $VERIFIED \
  --symbol _ZTV11CGameEffect=0xcbccc0 --const CGameEffect.vtable.header=2 --const CGameEffect.vtable.slots=12 \
  --const CChitin.Update.delaySite=0x5933a4 --const CChitin.inSyncFlag=0x1000 --const CChitin.framesPerSecond=0x1c8 --const CChitin.ticksPerSecond=0x1bc \
  --const CGameEffect.vtable.apply=0x18 --const IEX.vt.EffectDelete=0x8 --const IEX.vt.AddEffect=0xe8 \
  --const CGameEffect.vtable.copy=0x10 --const CGameEffect.vtable.onRemove=0x58 --const CGameAIBase.vtable.setScript=0x128 $VIS $PATHL $OBJL $SPLL $FIXL   --const IEX.vis.prologue.AddCharacter=0x0f455641fa1e0ff3 --const IEX.vis.prologue.RemoveCharacter=0x0f455741fa1e0ff3   --const IEX.vis.prologue.UpDate=0x0f455741fa1e0ff3 --const IEX.vis.prologue.IsCharacterIdOnMap=0x7420773bfa1e0ff3   --const IEX.native.reprocessFlag=0x4b8c --const IEX.native.stealthHidden=0x4e38 --const IEX.vis.prologue.PrivateAddCharacter=0x0f455741fa1e0ff3 --const IEX.vis.checkIfVisibleJmp.0=0x4b7ed8 \n  --const IEX.vis.removeFromAreaIsOnMapSite=0x4a9044 --const CScreenStart.TimerAsynchronousUpdate.size=0x511
