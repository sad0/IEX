# Mod scan: EEex usage vs IEX

IEX defines 163 EEex names/methods; descriptions know 406 field names.

| Mod | EEex names | missing in IEX | fields | unknown fields | EEex opcodes | hard (asm/raw memory) |
|---|---|---|---|---|---|---|
| Bardic-Wonders | 6 | 0 | 1 | 0 | 401 | - |
| Shadow-Magic | 6 | 0 | 1 | 0 | 401 | - |
| The-Artisan-s-Kitpack | 8 | 4 | 1 | 0 | - | - |
| aura | 5 | 1 | 1 | 0 | - | - |
| bg-eeex-buffbot | 80 | 47 | 63 | 26 | - | - |
| candlekeep-revisited | 0 | 0 | 0 | 0 | - | - |
| caster-crafting | 0 | 0 | 0 | 0 | - | - |
| diablofication | 8 | 5 | 2 | 1 | - | - |
| eet-tweaks | 3 | 3 | 0 | 0 | 402 | - |
| high-power-bg | 264 | 240 | 24 | 3 | 400, 401, 402, 403, 407, 408, 409 | 286 |
| house-rule-tweaks | 12 | 4 | 0 | 0 | 401 | - |
| iui | 34 | 25 | 31 | 4 | - | 7 |
| olvynspells | 263 | 239 | 24 | 3 | 400, 401, 402, 403, 408, 409 | 285 |
| pathfinding-redux | 66 | 51 | 29 | 8 | - | 581 |
| poisoned-pathways | 6 | 2 | 3 | 0 | - | - |
| sod2bg2-iu | 3 | 3 | 0 | 0 | - | - |
| tweaks | 101 | 40 | 181 | 30 | - | - |
| wares-of-the-planes | 0 | 0 | 0 | 0 | - | - |
| warlock | 13 | 1 | 3 | 2 | 401 | - |
| SadoEE | 120 | 57 | 93 | 0 | - | 235 |

## Missing EEex names across all scanned mods

`EEex_ReadDword`(4299), `EEex_ApplyEffectToActor`(885), `EEex_ReadLString`(840), `EEex_WriteDword`(744), `EEex_GetActorStat`(631), `EEex_ReadWord`(476), `EEex_LuaTrigger`(365), `EEex_GetActorShare`(350), `EEex_Read32`(324), `EEex_IsSprite`(310), `EEex_WriteWord`(309), `EEex_Write32`(225), `EEex_GetActorFullResistance`(223), `EEex_ProjectileType`(220), `EEex_IterateActorEffects`(200), `EEex_ReadByte`(194), `EEex_ReadQword`(168), `EEex_ReadU8`(165), `EEex_ReadSignedWord`(148), `EEex_ReadPtr`(145), `EEex_WriteByte`(136), `EEex_RecordSpell`(134), `EEex_DemandResData`(132), `EEex_GetActorIDShare`(124), `EEex_Label`(119), `EEex_GetGameTick`(110), `EEex_DS`(88), `EEex_FlattenTable`(84), `EEex_ReadU32`(77), `EEex_GetActorName`(72), `EEex_GetActorIDCharacter`(70), `EEex_GetDistance`(68), `EEex_GetSpellData`(60), `EEex_Sprite`(54), `EEex_GetActorCasterLevel`(54), `EEex_Action_QueueResponseStringOnAIBase`(53), `EEex_GenLuaCall`(51), `EEex_LuaAction`(50), `EEex_GetActorAreaRes`(50), `EEex_LuaObject`(49), `EEex_GetActorSpellRES`(48), `EEex_HookBeforeRestoreWithLabels`(48), `EEex_ReadU16`(45), `EEex_Read16`(45), `EEex_WriteLString`(45), `EEex_WriteU8`(45), `EEex_ProjectileHookSource`(44), `EEex_Flags`(44), `EEex_Malloc`(44), `EEex_GetActionID`(42), `EEex_scripts`(41), `EEex_WriteU32`(41), `EEex_Action_ExecuteResponseStringOnAIBaseInstantly`(40), `EEex_GetActorIDPortrait`(40), `EEex_GetActorLocation`(40), `EEex_SetActionID`(40), `EEex_Active`(37), `EEex_GetActorAllegiance`(36), `EEex_LuaCallReturnType`(35), `EEex_CompareActorAllegiances`(34), `EEex_GetActorClass`(32), `EEex_EnableCodeProtection`(32), `EEex_IterateIDs`(32), `EEex_WritePtr`(32), `EEex_HookIntegrityWatchdogRegister`(31), `EEex_AddActionHookOpcode`(30), `EEex_GetDistanceIsometric`(30), `EEex_IsImmuneToOpcode`(30), `EEex_Options`(28), `EEex_GetActorRequiredDirection`(28), `EEex_ModifyTerrainTable`(28), `EEex_Modules`(27), `EEex_DisableCodeProtection`(27), `EEex_ReadSignedByte`(25), `EEex_Write8`(24), `EEex_LuaDecode_Object`(23), `EEex_Target`(22), `EEex_AddActionHookGlobal`(20), `EEex_GetActorAnimation`(20), `EEex_GetActorSpellState`(20), `EEex_HookAfterRestoreWithLabels`(20), `EEex_GetActorIDArea`(18), `EEex_effOff`(18), `EEex_JITNear`(18), `EEex_Sprite_GetExtendedStat`(17), `EEex_HookBeforeAndAfterCallWithLabels`(17), `EEex_Object_ParseString`(17), `EEex_IterateCPtrList`(16), `EEex_GetActorDirection`(16), `EEex_WithinCyclicRange`(16), `EEex_ProcessClericMemorization`(16), `EEex_ProcessWizardMemorization`(16), `EEex_ToHex`(16), `EEex_Resource_GetAt2DALabels`(16), `EEex_AddScreenEffectsGlobal`(15), `EEex_DefineAssemblyLabel`(15), `EEex_JITNearAsLuaFunction`(15), `EEex_GetActorKit`(14), `EEex_GetActorAreaSize`(14), `EEex_AlterActorEffect`(14), `EEex_GetActionPointX`(14), `EEex_GetActionPointY`(14), `EEex_GetBitmapPixelIndex`(14), `EEex_IsFlying`(14), `EEex_RollEffectDice`(14), `EEex_Memcpy`(14), `EEex_GetActorAlignment`(13), `EEex_Trigger_ParseConditionalString`(13), `EEex_HasState`(12), `EEex_DemandRes`(12), `EEex_ConstantID`(12), `EEex_PostLaunchMutatorOpcodeFunctions`(12), `EEex_RunWithStack`(12), `EEex_Projectile_IsOfType`(11), `EEex_Projectile_Type`(11), `EEex_Sprite_GetAnyStat`(11), `EEex_Area_GetAllOfTypeInRange`(11), `EEex_RunWithStackManager`(10), `EEex_Menu_AddBeforeUIItemRenderListener`(10), `EEex_Action_Hook_OpcodeFunctions`(10), `EEex_GetGlobal`(10), `EEex_GetGameData`(10), `EEex_GetActorGeneral`(10), `EEex_GetActorRace`(10), `EEex_GetActorScriptName`(10), `EEex_CyclicBound`(10), `EEex_ToString`(10), `EEex_GetActorMovementRate`(10), `EEex_GetActorCurrentAction`(10), `EEex_Memset`(10), `EEex_CChitin`(9), `EEex_Menu_Find`(9), `EEex_ScreenEffectsGlobalFunctions`(8), `EEex_SetGlobal`(8), `EEex_IsValidBackstabDirection`(8), `EEex_GetActionString1`(8), `EEex_SpellIDSType`(8), `EEex_CheckTimeStopOnActor`(8), `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`(8), `EEex_Reset_Search_Map`(8), `EEex_MatchObject`(8), `EEex_PostLaunchMutatorGlobalFunctions`(8), `EEex_IsPartyMember`(8), `EEex_GetAreaName`(8), `EEex_RecordAttack`(8), `EEex_HookBeforeCallWithLabels`(8), `EEex_Sprite_AddQuickListsCheckedListener`(7), `EEex_GameObject_GetUnderCursorID`(7), `EEex_ReadString`(7), `EEex_JITAt`(7), `EEex_HookRemoveCallWithLabels`(7), `EEex_Sprite_GetAllOfTypeInRange`(7), `EEex_Area_GetAllOfTypeStringInRange`(7), `EEex_Actionbar`(6), `EEex_Sprite_GetKnownInnateSpellsIterator`(6), `EEex_Action_Hook_GlobalFunctions`(6), `EEex_TypeMutatorGlobalFunctions`(6), `EEex_ProjectileMutatorGlobalFunctions`(6), `EEex_AddProjectileMutatorGlobal`(6), `EEex_EffectMutatorGlobalFunctions`(6), `EEex_DecodeProjectileSources`(6), `EEex_AccessComplexStat`(6), `EEex_ProjectileMutatorList`(6), `EEex_HookAfterRestore`(6), `EEex_WriteStringAuto`(6), `EEex_ReadU64`(6), `EEex_Read64`(6), `EEex_Write64`(6), `EEex_GetActorIDSelected`(6), `EEex_IterateAreas`(6), `EEex_GetActorIDLoaded`(6), `EEex_Sprite_GetState`(6), `EEex_GetActorPortraitSlot`(6), `EEex_JumpActorToPoint`(6), `EEex_DoInstantAction`(6), `EEex_CheckForInfiniteLoop`(6), `EEex_Call`(6), `EEex_SetActionbarButton`(6), `EEex_ACTIONBAR_TYPE`(6), `EEex_EvalObjectStringAsActor`(6), `EEex_GetActorLevel`(6), `EEex_LuaTriggerActorID`(6), `EEex_ObjectData`(6), `EEex_Sprite_GetCasterLevel`(6), `EEex_Sprite_GetSpellRES`(6), `EEex_GetImageBase`(6), `EEex_OffsetOf`(6), `EEex_CInfGame`(6), `EEex_GameState_AddDestroyedListener`(5), `EEex_Utility_FreeCPtrList`(5), `EEex_Sprite_GetCastTimer`(5), `EEex_Opcode_AddScreenEffectsGlobal`(5), `EEex_Sprite_GetSpellState`(5), `EEex_Menu_IsCursorWithin`(5), `EEex_Action_ParseResponseString`(5), `EEex_HookAfterCallWithLabels`(5), `EEex_Trigger_EvalScriptFileConditionalAsAIBase`(5), `EEex_AllocNear`(5), `EEex_Sprite_GetKnownInnateSpellsWithAbilityIterator`(4), `EEex_NewUD`(4), `EEex_Options_Private_Storage`(4), `EEex_GameObject_GetUnderCursor`(4), `EEex_Sprite_IterateEffects`(4), `EEex_IsProjectileOfType`(4), `EEex_AddEffectToProjectileSources`(4), `EEex_ProjectileInheritance`(4), `EEex_ProjectileVFTableToType`(4), `EEex_GetProjectileType`(4), `EEex_OnDecodeProjectile`(4), `EEex_OnPostProjectileCreation`(4), `EEex_OnAddEffectToProjectile`(4), `EEex_Write16`(4), `EEex_WriteQword`(4), `EEex_GetAllActorIDSelected`(4), `EEex_GetIDArea`(4), `EEex_GetActorCurrentHP`(4), `EEex_GetActorModalState`(4), `EEex_IsImmuneToSpellLevel`(4), `EEex_GetActorGender`(4), `EEex_GetActorTargetID`(4), `EEex_GetActionTarget`(4), `EEex_SetActionPointX`(4), `EEex_SetActionPointY`(4), `EEex_ProcessInnateMemorization`(4), `EEex_Menu_SetTemplateArea`(4), `EEex_HeightMod`(4), `EEex_GetSpellName`(4), `EEex_CheckActorLOS`(4), `EEex_Sprite_ForAllOfTypeStringInRange`(4), `EEex_Action_ExecuteScriptFileResponseAsAIBaseInstantly`(4), `EEex_AddActionHook`(4), `EEex_RunBCSAsActor`(4), `EEex_IsInAir`(4), `EEex_IsIncorporeal`(4), `EEex_IsEthereal`(4), `EEex_IterateActorIDs`(4), `EEex_GetBitmapPixelColor`(4), `EEex_IterateDoors`(4), `EEex_IsKeyDown`(4), `EEex_AddPostLaunchMutatorGlobal`(4), `EEex_VolatileStorageDefinitions`(4), `EEex_Sprite_GetAllOfTypeStringInRange`(4), `EEex_CBaldurChitin`(4), `EEex_Sprite_GetPersonalSpace`(4), `EEex_Sprite_AddAlterBaseWeaponDamageListener`(4), `EEex_Sprite_AddBlockWeaponHitListener`(4), `EEex_Utility_MapItrValues`(4), `EEex_Menu_InjectTemplateInstance`(4), `EEex_Resource_Free2DA`(4), `EEex_Sprite_DisplayTextRef`(3), `EEex_Options_Widget`(3), `EEex_GetCurrentArea`(3), `EEex_Area_GetCurrent`(3), `EEex_Menu_GetItemFunction`(3), `EEex_Menu_SetItemFunction`(3), `EEex_Menu_GetItemArea`(3), `EEex_Cra`(3), `EEex_DamageAbsorption`(3), `EEex_Read8`(3), `EEex_Free`(3), `EEex_LuaDecode`(3), `EEex_SpellObjectOffset`(3), `EEex_Sprite_GetKnownMageSpellsIterator`(3), `EEex_Resource_IterateUnpackedIDSEntries`(2), `EEex_Menu_AddBeforeListRendersItemListener`(2), `EEex_Menu_GetItem`(2), `EEex_Menu_GetArea`(2), `EEex_GameState_GetCurrentArea`(2), `EEex_GameObject_GetCurrentArea`(2), `EEex_GetChitin`(2), `EEex_Sprite_IterateSelected`(2), `EEex_Action`(2), `EEex_Action_Hook_OnEvaluatingUnknown`(2), `EEex_Opcode`(2), `EEex_Opcode_Hook_ApplyScreenEffects`(2), `EEex_Crashing`(2), `EEex_AddTypeMutatorGlobal`(2), `EEex_AddEffectMutatorGlobal`(2), `EEex_FetchBCS`(2), `EEex_Action_AddEnabledSpriteStartedActionListener`(2), `EEex_ReadSignedQword`(2), `EEex_GGD`(2), `EEex_GetWorldMapData`(2), `EEex_IsTimeStopped`(2), `EEex_GetActorIDCursor`(2), `EEex_GIDC`(2), `EEex_GIDS`(2), `EEex_GS`(2), `EEex_GSC`(2), `EEex_GSS`(2), `EEex_GetImageMasterID`(2), `EEex_GetLocal`(2), `EEex_SetLocal`(2), `EEex_GetActorState`(2), `EEex_GetActorSpecifics`(2), `EEex_GetActorDialogue`(2), `EEex_GetActorItemRes`(2), `EEex_GetActorItemCharges`(2), `EEex_SetActorItemCharges`(2), `EEex_IterateActorItems`(2), `EEex_IsActorFacing`(2), `EEex_SetActionTarget`(2), `EEex_GetActionParameter2`(2), `EEex_SetActionParameter2`(2), `EEex_SetActionString1`(2), `EEex_AIBase_JumpToPoint`(2), `EEex_Opcode_Hook_OnCheckAdd`(2), `EEex_ScreenEffects`(2), `EEex_Sprite_Hook_OnDestruct`(2), `EEex_Search_Change`(2), `EEex_Search`(2), `EEex_PrintData`(2), `EEex_GetActorLocal`(2), `EEex_GetActorWizardLevel`(2), `EEex_GetActorPriestLevel`(2), `EEex_MatchObjectEx`(2), `EEex_Projectile_RegisterGlobalMutator`(2), `EEex_AddPostLaunchMutatorOpcode`(2), `EEex_GameObjectAdded`(2), `EEex_VolatileStorageSpace`(2), `EEex_GameObjectBeingDeleted`(2), `EEex_Split`(2), `EEex_Assembly_Private_MacroSwitch`(2), `EEex_Sprite_GetCasterLevelForSpell`(2), `EEex_WriteUDArgs`(2), `EEex_SpellObjectOffsetNoDec`(2), `EEex_ForceSpellObjectOffset`(2), `EEex_ReallyForceSpellObjectOffset`(2), `EEex_ExposeToLua`(2), `EEex_WriteU16`(2), `EEex_ReadS16`(2), `EEex_Options_Private_FindItemByText`(2), `EEex_Actionbar_Hook_HasFullThieving`(1), `EEex_FreeUD`(1), `EEex_Trigger_EvalConditionalStringAsAIBase`(1), `EEex_Sprite_AddMarshalHandlers`(1), `EEex_Sprite_GetKnownMageSpellsWithAbilityIterator`(1), `EEex_Sprite_GetKnownPriestSpellsWithAbilityIterator`(1), `EEex_Options_Private_UnpackColor`(1), `EEex_Sprite_AddQuickListCountsResetListener`(1), `EEex_Sprite_AddQuickListNotifyRemovedListener`(1), `EEex_Menu_AddWindowSizeChangedListener`(1), `EEex_LightUDToPtr`(1), `EEex_GameObject_IsSpriteID`(1), `EEex_Stats_FirstExtendedStatID`(1), `EEex_ReadPointer`(1), `EEex_WritePointer`(1), `EEex_WriteString`(1), `EEex_Sprite_GetNumCharacters`(1), `EEex_GetUTBaseclassMetadata`(1), `EEex_Assembly`(1), `EEex_Assembly_Private_FindOffsetOf`(1), `EEex_PreprocessAssemblyStr`(1), `EEex_HookConditionalJumpWithLabels`(1), `EEex_Once`(1), `EEex_RoundUp`(1), `EEex_DistanceToMultiple`(1), `EEex_Assembly_x86`(1), `EEex_Assembly_Private_InitState`(1), `EEex_PreprocessAssembly`(1), `EEex_HookIntegrityWatchdog_Load`(1), `EEex_RunWithAssemblyLabels`(1), `EEex_TryLabel`(1), `EEex_WriteStringCache`(1), `EEex_SpellObjectOffsetRES`(1), `EEex_Utility_TryFinally`(1), `EEex_Sprite_GetLauncher`(1), `EEex_Sprite_GetModalState`(1), `EEex_Sprite_GetModalTimer`(1), `EEex_Resource_GetAt2DAPoint`(1), `EEex_Key_AddReleasedListener`(1), `EEex_Sprite_GetKnownPriestSpellsIterator`(1), `EEex_Object_AddToArea`(1), `EEex_HookIntegrityWatchdog_IgnoreStackSizes`(1), `EEex_Options_Set`(1), `EEex_Options_`(1), `EEex_Menu_`(1), `EEex_Options_Close`(1)

## Bardic-Wonders

**Missing EEex names:** none

**Unknown fields:** none

**Engine-object methods called:** `getActiveStats`(5)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 2 compatible, 0 partial, 0 unsupported, 24 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| Setup-BardicWonders.tp2 | 1001 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1002 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1003 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1004 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1005 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1006 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1007 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1008 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1009 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1010 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1011 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 1012 |  | 1 | compatible |  |
| Setup-BardicWonders.tp2 | 2001 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2002 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2007 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2008 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2003 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2004 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2005 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2012 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2013 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2006 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2009 |  | 1 | compatible |  |
| Setup-BardicWonders.tp2 | 2010 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 2011 |  | 0 | unknown |  |
| Setup-BardicWonders.tp2 | 3001 |  | 0 | unknown |  |

## Shadow-Magic

**Missing EEex names:** none

**Unknown fields:** none

**Engine-object methods called:** `getActiveStats`(6)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 8 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 1 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| shadowadept.tp2 | 0000 |  | 0 | no_lua |  |
| shadowadept.tp2 | 0001 |  | 0 | unknown |  |
| shadowadept.tp2 | 0002 |  | 0 | unknown |  |
| shadowadept.tp2 | 0003 |  | 0 | unknown |  |
| shadowadept.tp2 | 0004 |  | 0 | unknown |  |
| shadowadept.tp2 | 0005 |  | 0 | unknown |  |
| shadowadept.tp2 | 0006 |  | 0 | unknown |  |
| shadowadept.tp2 | 0007 |  | 0 | unknown |  |
| shadowadept.tp2 | 0008 |  | 0 | unknown |  |

## The-Artisan-s-Kitpack

**Missing EEex names:** `EEex_Actionbar`(5), `EEex_GetActorClass`(2), `EEex_GetActorKit`(2), `EEex_GetActorAlignment`(2)

**Unknown fields:** none

**Engine-object methods called:** `getActiveStats`(9)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 9 compatible, 0 partial, 0 unsupported, 56 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 4 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| ArtisansKitpack.TP2 | 0001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 0002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 0003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 8001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 8101 |  | 0 | no_lua |  |
| ArtisansKitpack.TP2 | 5 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 8102 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 8002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 8003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 10002 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 10001 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 10003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1006 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1004 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1005 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1007 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1101 |  | 0 | no_lua |  |
| ArtisansKitpack.TP2 | 1000 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1102 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1103 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1104 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1105 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1008 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1009 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1100 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 2000 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 2010 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 2011 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 2012 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 2001 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 2002 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 3000 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3010 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3011 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3004 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3101 |  | 0 | no_lua |  |
| ArtisansKitpack.TP2 | 3002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 3005 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5100 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5110 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5111 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5101 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 5002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 50 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7004 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7006 |  | 1 | compatible |  |
| ArtisansKitpack.TP2 | 7001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7101 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7002 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7003 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7102 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7103 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7005 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7104 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 9001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 9101 |  | 0 | no_lua |  |
| ArtisansKitpack.TP2 | 20000 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 20001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 21001 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 12012 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 1209 |  | 0 | unknown |  |
| ArtisansKitpack.TP2 | 7203 |  | 0 | unknown |  |

## aura

**Missing EEex names:** `EEex_Actionbar_Hook_HasFullThieving`(1)

**Unknown fields:** none

**Engine-object methods called:** `getActiveStats`(2), `getClass`(1)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 4 partial, 0 unsupported, 8 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 3 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| Setup-Aura_BG1_2_EET.tp2 | 0 |  | 0 | no_lua |  |
| Setup-Aura_BG1_2_EET.tp2 | 1 |  | 0 | no_lua |  |
| Setup-Aura_BG1_2_EET.tp2 | 2 |  | 0 | no_lua |  |
| Setup-Aura_BG1_2_EET.tp2 | 3 |  | 1 | partial | EEex_Actionbar_Hook_HasFullThieving |
| Setup-Aura_BG1_2_EET.tp2 | 4 |  | 1 | partial | EEex_Actionbar_Hook_HasFullThieving |
| Setup-Aura_BG1_2_EET.tp2 | 5 |  | 1 | partial | EEex_Actionbar_Hook_HasFullThieving |
| Setup-Aura_BG1_2_EET.tp2 | 6 |  | 1 | partial | EEex_Actionbar_Hook_HasFullThieving |
| Setup-Aura_BG1_2_EET.tp2 | 7 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 8 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 9 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 10 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 11 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 12 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 13 |  | 0 | unknown |  |
| Setup-Aura_BG1_2_EET.tp2 | 14 |  | 0 | unknown |  |

## bg-eeex-buffbot

**Missing EEex names:** `EEex_Sprite`(54), `EEex_scripts`(39), `EEex_Options`(28), `EEex_Action_QueueResponseStringOnAIBase`(27), `EEex_LuaAction`(14), `EEex_Menu_AddBeforeUIItemRenderListener`(10), `EEex_ReadU16`(9), `EEex_ReadU8`(9), `EEex_Menu_Find`(8), `EEex_Sprite_GetKnownInnateSpellsIterator`(6), `EEex_Utility_FreeCPtrList`(5), `EEex_Sprite_GetKnownInnateSpellsWithAbilityIterator`(4), `EEex_ReadU32`(4), `EEex_Options_Private_Storage`(4), `EEex_CChitin`(3), `EEex_GameState_AddDestroyedListener`(3), `EEex_Options_Widget`(3), `EEex_GetCurrentArea`(3), `EEex_Area_GetCurrent`(3), `EEex_Menu_GetItemArea`(3), `EEex_Resource_IterateUnpackedIDSEntries`(2), `EEex_Sprite_DisplayTextRef`(2), `EEex_Menu_AddBeforeListRendersItemListener`(2), `EEex_Menu_GetItem`(2), `EEex_Menu_GetItemFunction`(2), `EEex_Menu_SetItemFunction`(2), `EEex_GameState_GetCurrentArea`(2), `EEex_GameObject_GetCurrentArea`(2), `EEex_GetChitin`(2), `EEex_Sprite_IterateSelected`(2), `EEex_NewUD`(1), `EEex_RunWithStackManager`(1), `EEex_FreeUD`(1), `EEex_Trigger_EvalConditionalStringAsAIBase`(1), `EEex_Sprite_AddMarshalHandlers`(1), `EEex_Sprite_GetKnownMageSpellsWithAbilityIterator`(1), `EEex_Sprite_GetKnownPriestSpellsWithAbilityIterator`(1), `EEex_Options_Private_UnpackColor`(1), `EEex_Action_ExecuteResponseStringOnAIBaseInstantly`(1), `EEex_Sprite_AddQuickListsCheckedListener`(1), `EEex_Sprite_AddQuickListCountsResetListener`(1), `EEex_Sprite_AddQuickListNotifyRemovedListener`(1), `EEex_Menu_AddWindowSizeChangedListener`(1), `EEex_Menu_GetArea`(1), `EEex_Active`(1), `EEex_Sprite_GetCastTimer`(1), `EEex_LightUDToPtr`(1)

**Unknown fields:** `m_nCopyParent`(9), `m_multiPlayerSettings`(6), `m_bConnectionEstablished`(5), `m_pnCharacterControlledByPlayer`(5), `m_abilityId`(4), `m_idLocalPlayer`(3), `m_count`(3), `m_icon`(3), `m_sex`(3), `m_nLocalPlayer`(2), `m_bInCopy`(2), `m_objectID`(2), `m_wFileType`(1), `m_overHead`(1), `m_gameSave`(1), `m_inputMode`(1), `m_bIsHost`(1), `m_nTotalPlayers`(1), `m_nHostPlayer`(1), `m_pPlayerID`(1), `m_pnLoadGameControlledByPlayer`(1), `m_quickItemResRef`(1), `m_liveStats`(1), `m_data`(1), `m_pNext`(1), `m_sourceTarget`(1)

**Engine-object methods called:** `get`(75), `getAbility`(28), `getStat`(12), `getAbilityForLevel`(10), `getAtPoint`(9), `getName`(8), `getSpellState`(5), `getDimensions`(4), `getRowLabel`(3), `flush`(3), `getCasterLevelForSpell`(3), `findColumnLabel`(3), `countAllOfTypeStringInRange`(2), `accessible`(2), `getColumnLabel`(1), `getLine`(1), `getUD`(1), `getReference`(1), `string`(1), `slot`(1), `findRowLabel`(1), `traps`(1), `offensive`(1), `stances`(1), `done`(1), `build`(1), `getArea`(1), `checkbox`(1)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 3 partial, 0 unsupported, 5 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| setup-buffbot.tp2 | 1 |  | 0 | unknown |  |
| setup-buffbot.tp2 | 1 | BuffBot-LuaJIT | 0 | unknown |  |
| setup-buffbot.tp2 | 0 | BuffBot-Main | 16 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Action_QueueResponseStringOnAIBase, EEex_Active, EEex_Area_GetCurrent, m_abilityId, m_bConnectionEstablished |
| setup-buffbot-map-backed-v1.7.4-alpha.tp2 | 1 |  | 0 | unknown |  |
| setup-buffbot-map-backed-v1.7.4-alpha.tp2 | 1 | BuffBot-LuaJIT | 0 | unknown |  |
| setup-buffbot-map-backed-v1.7.4-alpha.tp2 | 0 | BuffBot-Main | 13 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Action_QueueResponseStringOnAIBase, EEex_Active, EEex_Area_GetCurrent, m_abilityId, m_bConnectionEstablished |
| setup-buffbot-v1.7.0-alpha.tp2 | 0 | BuffBot-Main | 12 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Action_QueueResponseStringOnAIBase, EEex_Active, EEex_Area_GetCurrent, m_abilityId, m_bConnectionEstablished |
| setup-buffbot-v1.7.0-alpha.tp2 | 1 | BuffBot-LuaJIT | 0 | unknown |  |

## candlekeep-revisited

**Missing EEex names:** none

**Unknown fields:** none

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 5 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| candlekeep_revisited.tp2 | 0 |  | 0 | unknown |  |
| candlekeep_revisited.tp2 | 1 |  | 0 | unknown |  |
| candlekeep_revisited.tp2 | 2 |  | 0 | unknown |  |
| candlekeep_revisited.tp2 | 3 |  | 0 | unknown |  |
| candlekeep_revisited.tp2 | 4 |  | 0 | unknown |  |

## caster-crafting

**Missing EEex names:** none

**Unknown fields:** none

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 14 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| mod-caster-crafting.tp2 | 11 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 12 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 13 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 20 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 31 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 32 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 33 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 40 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 50 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 60 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 70 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 81 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 82 |  | 0 | unknown |  |
| mod-caster-crafting.tp2 | 83 |  | 0 | unknown |  |

## diablofication

**Missing EEex names:** `EEex_LuaAction`(6), `EEex_Active`(3), `EEex_GameObject_GetUnderCursorID`(1), `EEex_GameObject_IsSpriteID`(1), `EEex_GameObject_GetUnderCursor`(1)

**Unknown fields:** `m_scrollLockId`(3)

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 10 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| Diablofication.tp2 | 0 | db-diablofication-town_portal | 0 | unknown |  |
| Diablofication.tp2 | 1 | db-diablofication-identification | 0 | unknown |  |
| Diablofication.tp2 | 2 | db-diablofication-party_revive | 0 | unknown |  |
| Diablofication.tp2 | 3 | db-diablofication-character_respawn | 0 | unknown |  |
| Diablofication.tp2 | 4 | db-diablofication-party_xp | 0 | unknown |  |
| Diablofication.tp2 | 5 | db-diablofication-identified_ammo | 0 | unknown |  |
| Diablofication.tp2 | 6 | db-diablofication-spells_regen | 0 | unknown |  |
| Diablofication.tp2 | 7 | db-diablofication-level1_hp | 0 | unknown |  |
| Diablofication.tp2 | 8 | db-diablofication-proficiency | 0 | unknown |  |
| Diablofication.tp2 | 9 | db-diablofication-camera_lock | 0 | unknown |  |

## eet-tweaks

**Missing EEex names:** `EEex_LuaObject`(3), `EEex_ReadDword`(1), `EEex_GetActorStat`(1)

**Unknown fields:** none

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 1 partial, 0 unsupported, 73 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 3 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| EET_Tweaks.tp2 | 1000 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1001 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1010 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1011 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1012 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1020 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1021 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1030 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1031 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1040 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1041 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1042 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 1050 |  | 0 | no_lua |  |
| EET_Tweaks.tp2 | 1060 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2000 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2001 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2002 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2003 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2010 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2011 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2012 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2013 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2020 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2021 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2022 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2023 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2030 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2031 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2032 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2033 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2040 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2041 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2042 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2043 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2044 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2050 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2051 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2052 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2053 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2054 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2055 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2056 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2060 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2061 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2062 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2063 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2064 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2065 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2066 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2070 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 2080 |  | 1 | partial | EEex_GetActorStat, EEex_LuaObject, EEex_ReadDword |
| EET_Tweaks.tp2 | 3000 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 3010 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 53 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 54 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 55 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 56 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 57 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 58 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 59 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 60 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 61 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 62 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 63 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 64 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 3020 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 3021 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 3022 |  | 0 | no_lua |  |
| EET_Tweaks.tp2 | 3040 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 3050 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4020 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4040 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4050 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4060 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4070 |  | 0 | no_lua |  |
| EET_Tweaks.tp2 | 4080 |  | 0 | unknown |  |
| EET_Tweaks.tp2 | 4081 |  | 0 | unknown |  |

## high-power-bg

**Missing EEex names:** `EEex_ReadDword`(2162), `EEex_ApplyEffectToActor`(449), `EEex_ReadLString`(412), `EEex_WriteDword`(377), `EEex_GetActorStat`(322), `EEex_ReadWord`(240), `EEex_GetActorFullResistance`(220), `EEex_GetActorShare`(176), `EEex_IsSprite`(157), `EEex_WriteWord`(155), `EEex_ProjectileType`(110), `EEex_IterateActorEffects`(102), `EEex_ReadByte`(100), `EEex_ReadQword`(84), `EEex_ReadSignedWord`(74), `EEex_WriteByte`(68), `EEex_RecordSpell`(67), `EEex_DemandResData`(66), `EEex_GetActorIDShare`(62), `EEex_GetGameTick`(55), `EEex_Label`(50), `EEex_DS`(44), `EEex_GetActorName`(37), `EEex_GetActorIDCharacter`(35), `EEex_GetDistance`(34), `EEex_GetSpellData`(30), `EEex_GetActorCasterLevel`(27), `EEex_GetActorAreaRes`(25), `EEex_GetActorSpellRES`(24), `EEex_ProjectileHookSource`(22), `EEex_Flags`(22), `EEex_WriteLString`(22), `EEex_GetActionID`(21), `EEex_GetActorIDPortrait`(20), `EEex_GetActorLocation`(20), `EEex_SetActionID`(20), `EEex_GetActorAllegiance`(18), `EEex_CompareActorAllegiances`(17), `EEex_IterateIDs`(16), `EEex_AddActionHookOpcode`(15), `EEex_GetActorClass`(15), `EEex_GetDistanceIsometric`(15), `EEex_GetActorRequiredDirection`(14), `EEex_ModifyTerrainTable`(14), `EEex_LuaObject`(14), `EEex_ReadSignedByte`(13), `EEex_AddActionHookGlobal`(10), `EEex_GetActorAnimation`(10), `EEex_GetActorSpellState`(10), `EEex_GetActorIDArea`(9), `EEex_effOff`(9), `EEex_AddScreenEffectsGlobal`(8), `EEex_IterateCPtrList`(8), `EEex_Sprite_GetExtendedStat`(8), `EEex_GetActorDirection`(8), `EEex_WithinCyclicRange`(8), `EEex_ProcessClericMemorization`(8), `EEex_ProcessWizardMemorization`(8), `EEex_ToHex`(8), `EEex_Modules`(7), `EEex_GetActorAreaSize`(7), `EEex_AlterActorEffect`(7), `EEex_GetActionPointX`(7), `EEex_GetActionPointY`(7), `EEex_GetBitmapPixelIndex`(7), `EEex_IsFlying`(7), `EEex_RollEffectDice`(7), `EEex_GetActorKit`(6), `EEex_HasState`(6), `EEex_DemandRes`(6), `EEex_ConstantID`(6), `EEex_PostLaunchMutatorOpcodeFunctions`(6), `EEex_Action_Hook_OpcodeFunctions`(5), `EEex_GetActorAlignment`(5), `EEex_GetGlobal`(5), `EEex_GetGameData`(5), `EEex_IsImmuneToOpcode`(5), `EEex_GetActorGeneral`(5), `EEex_GetActorRace`(5), `EEex_GetActorScriptName`(5), `EEex_CyclicBound`(5), `EEex_ToString`(5), `EEex_GetActorMovementRate`(5), `EEex_GetActorCurrentAction`(5), `EEex_Projectile_IsOfType`(5), `EEex_Projectile_Type`(5), `EEex_ScreenEffectsGlobalFunctions`(4), `EEex_SetGlobal`(4), `EEex_IsValidBackstabDirection`(4), `EEex_GetActionString1`(4), `EEex_SpellIDSType`(4), `EEex_CheckTimeStopOnActor`(4), `EEex_Action_ExecuteResponseStringOnAIBaseInstantly`(4), `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`(4), `EEex_Reset_Search_Map`(4), `EEex_MatchObject`(4), `EEex_PostLaunchMutatorGlobalFunctions`(4), `EEex_IsPartyMember`(4), `EEex_GetAreaName`(4), `EEex_RecordAttack`(4), `EEex_Action_Hook_GlobalFunctions`(3), `EEex_Cra`(3), `EEex_TypeMutatorGlobalFunctions`(3), `EEex_ProjectileMutatorGlobalFunctions`(3), `EEex_AddProjectileMutatorGlobal`(3), `EEex_EffectMutatorGlobalFunctions`(3), `EEex_DecodeProjectileSources`(3), `EEex_AccessComplexStat`(3), `EEex_ProjectileMutatorList`(3), `EEex_ReadString`(3), `EEex_HookAfterRestore`(3), `EEex_WriteStringAuto`(3), `EEex_GameObject_GetUnderCursorID`(3), `EEex_GetActorIDSelected`(3), `EEex_IterateAreas`(3), `EEex_GetActorIDLoaded`(3), `EEex_Sprite_GetState`(3), `EEex_GetActorPortraitSlot`(3), `EEex_JumpActorToPoint`(3), `EEex_DoInstantAction`(3), `EEex_CheckForInfiniteLoop`(3), `EEex_Call`(3), `EEex_SetActionbarButton`(3), `EEex_ACTIONBAR_TYPE`(3), `EEex_EvalObjectStringAsActor`(3), `EEex_GetActorLevel`(3), `EEex_LuaTriggerActorID`(3), `EEex_ObjectData`(3), `EEex_Sprite_GetCasterLevel`(3), `EEex_Sprite_GetSpellRES`(3), `EEex_Sprite_IterateEffects`(2), `EEex_DamageAbsorption`(2), `EEex_IsProjectileOfType`(2), `EEex_AddEffectToProjectileSources`(2), `EEex_ProjectileInheritance`(2), `EEex_ProjectileVFTableToType`(2), `EEex_GetProjectileType`(2), `EEex_OnDecodeProjectile`(2), `EEex_OnPostProjectileCreation`(2), `EEex_OnAddEffectToProjectile`(2), `EEex_Opcode_AddScreenEffectsGlobal`(2), `EEex_WriteQword`(2), `EEex_GetAllActorIDSelected`(2), `EEex_GetIDArea`(2), `EEex_GetActorCurrentHP`(2), `EEex_GetActorModalState`(2), `EEex_IsImmuneToSpellLevel`(2), `EEex_GetActorGender`(2), `EEex_GetActorTargetID`(2), `EEex_GetActionTarget`(2), `EEex_SetActionPointX`(2), `EEex_SetActionPointY`(2), `EEex_ProcessInnateMemorization`(2), `EEex_Menu_SetTemplateArea`(2), `EEex_HeightMod`(2), `EEex_GetSpellName`(2), `EEex_CheckActorLOS`(2), `EEex_Sprite_ForAllOfTypeStringInRange`(2), `EEex_AddActionHook`(2), `EEex_RunBCSAsActor`(2), `EEex_IsInAir`(2), `EEex_IsIncorporeal`(2), `EEex_IsEthereal`(2), `EEex_IterateActorIDs`(2), `EEex_GetBitmapPixelColor`(2), `EEex_IterateDoors`(2), `EEex_IsKeyDown`(2), `EEex_AddPostLaunchMutatorGlobal`(2), `EEex_VolatileStorageDefinitions`(2), `EEex_Action`(1), `EEex_Action_Hook_OnEvaluatingUnknown`(1), `EEex_Opcode`(1), `EEex_Opcode_Hook_ApplyScreenEffects`(1), `EEex_Crashing`(1), `EEex_AddTypeMutatorGlobal`(1), `EEex_AddEffectMutatorGlobal`(1), `EEex_DisableCodeProtection`(1), `EEex_EnableCodeProtection`(1), `EEex_FetchBCS`(1), `EEex_Action_AddEnabledSpriteStartedActionListener`(1), `EEex_ReadU8`(1), `EEex_Read8`(1), `EEex_ReadU16`(1), `EEex_Read16`(1), `EEex_Read32`(1), `EEex_ReadU64`(1), `EEex_ReadSignedQword`(1), `EEex_Read64`(1), `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_GGD`(1), `EEex_GetWorldMapData`(1), `EEex_IsTimeStopped`(1), `EEex_GetActorIDCursor`(1), `EEex_GIDC`(1), `EEex_GIDS`(1), `EEex_GS`(1), `EEex_GSC`(1), `EEex_GSS`(1), `EEex_GetImageMasterID`(1), `EEex_GetLocal`(1), `EEex_SetLocal`(1), `EEex_GetActorState`(1), `EEex_Sprite_GetSpellState`(1), `EEex_GetActorSpecifics`(1), `EEex_GetActorDialogue`(1), `EEex_GetActorItemRes`(1), `EEex_GetActorItemCharges`(1), `EEex_SetActorItemCharges`(1), `EEex_IterateActorItems`(1), `EEex_IsActorFacing`(1), `EEex_SetActionTarget`(1), `EEex_GetActionParameter2`(1), `EEex_SetActionParameter2`(1), `EEex_SetActionString1`(1), `EEex_AIBase_JumpToPoint`(1), `EEex_Opcode_Hook_OnCheckAdd`(1), `EEex_ScreenEffects`(1), `EEex_GameObject_GetUnderCursor`(1), `EEex_Menu_IsCursorWithin`(1), `EEex_GameState_AddDestroyedListener`(1), `EEex_Sprite_Hook_OnDestruct`(1), `EEex_Search_Change`(1), `EEex_Search`(1), `EEex_PrintData`(1), `EEex_Action_ParseResponseString`(1), `EEex_Action_ExecuteScriptFileResponseAsAIBaseInstantly`(1), `EEex_GetActorLocal`(1), `EEex_GetActorWizardLevel`(1), `EEex_GetActorPriestLevel`(1), `EEex_MatchObjectEx`(1), `EEex_Projectile_RegisterGlobalMutator`(1), `EEex_AddPostLaunchMutatorOpcode`(1), `EEex_GameObjectAdded`(1), `EEex_Malloc`(1), `EEex_VolatileStorageSpace`(1), `EEex_GameObjectBeingDeleted`(1), `EEex_Free`(1)

**Unknown fields:** `m_nTimeStop`(2), `m_pEngineWorldMap`(1), `m_cContingencyList`(1)

**Engine-object methods called:** `isValid`(6), `getData`(6), `free`(6), `getActiveStats`(2), `get`(2), `isSprite`(1), `getCastTimerPercentage`(1), `getModalState`(1)

**Hard usage:** `EEex_WriteWord`(155), `EEex_WriteByte`(68), `EEex_Label`(50), `EEex_HookAfterRestore`(3), `EEex_WriteStringAuto`(3), `EEex_DisableCodeProtection`(1), `EEex_EnableCodeProtection`(1), `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_Malloc`(1)

**Declares IEX support:** no

**Components:** 0 compatible, 1 partial, 1 unsupported, 39 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 32 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| HighPower.tp2 | 0 |  | 0 | unknown |  |
| HighPower.tp2 | 1 |  | 0 | no_lua |  |
| HighPower.tp2 | 2 |  | 0 | unknown |  |
| HighPower.tp2 | 3 |  | 0 | no_lua |  |
| HighPower.tp2 | 4 |  | 0 | unknown |  |
| HighPower.tp2 | 5 |  | 0 | unknown |  |
| HighPower.tp2 | 6 |  | 0 | unknown |  |
| HighPower.tp2 | 7 |  | 0 | unknown |  |
| HighPower.tp2 | 8 |  | 0 | unknown |  |
| HighPower.tp2 | 9 |  | 0 | unknown |  |
| HighPower.tp2 | 10 |  | 0 | unknown |  |
| HighPower.tp2 | 11 |  | 0 | unknown |  |
| HighPower.tp2 | 12 |  | 0 | unknown |  |
| HighPower.tp2 | 13 |  | 0 | unknown |  |
| HighPower.tp2 | 14 |  | 0 | unknown |  |
| HighPower.tp2 | 15 |  | 0 | unknown |  |
| HighPower.tp2 | 16 |  | 0 | unknown |  |
| HighPower.tp2 | 17 |  | 0 | unknown |  |
| HighPower.tp2 | 18 |  | 0 | unknown |  |
| HighPower.tp2 | 19 |  | 0 | unknown |  |
| HighPower.tp2 | 20 |  | 0 | unknown |  |
| HighPower.tp2 | 21 |  | 0 | unknown |  |
| HighPower.tp2 | 22 |  | 0 | unknown |  |
| HighPower.tp2 | 23 |  | 0 | unknown |  |
| HighPower.tp2 | 24 |  | 0 | unknown |  |
| HighPower.tp2 | 25 |  | 0 | unknown |  |
| HighPower.tp2 | 26 |  | 0 | unknown |  |
| HighPower.tp2 | 27 |  | 0 | unknown |  |
| HighPower.tp2 | 28 |  | 0 | no_lua |  |
| HighPower.tp2 | 29 |  | 0 | no_lua |  |
| HighPower.tp2 | 30 |  | 10 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| HighPower.tp2 | 128 |  | 0 | no_lua |  |
| HighPower.tp2 | 256 |  | 0 | no_lua |  |
| HighPower.tp2 | 384 |  | 0 | no_lua |  |
| HighPower.tp2 | 512 |  | 0 | unknown |  |
| HighPower.tp2 | 35 |  | 0 | no_lua |  |
| HighPower.tp2 | 640 |  | 0 | unknown |  |
| HighPower.tp2 | 768 |  | 0 | no_lua |  |
| HighPower.tp2 | 896 |  | 0 | no_lua |  |
| HighPower.tp2 | 1024 |  | 0 | no_lua |  |
| HighPower.tp2 | 1088 |  | 0 | unknown |  |
| HighPower.tp2 | 1120 |  | 0 | no_lua |  |
| HighPower.tp2 | 1152 |  | 0 | no_lua |  |
| HighPower.tp2 | 1280 |  | 0 | no_lua |  |
| HighPower.tp2 | 1408 |  | 0 | no_lua |  |
| HighPower.tp2 | 1536 |  | 0 | unknown |  |
| HighPower.tp2 | 1664 |  | 0 | no_lua |  |
| HighPower.tp2 | 1992 |  | 0 | unknown |  |
| HighPower.tp2 | 2120 |  | 0 | unknown |  |
| HighPower.tp2 | 2248 |  | 0 | no_lua |  |
| HighPower.tp2 | 2376 |  | 0 | no_lua |  |
| HighPower.tp2 | 2504 |  | 0 | no_lua |  |
| HighPower.tp2 | 2632 |  | 0 | no_lua |  |
| HighPower.tp2 | 2760 |  | 0 | no_lua |  |
| HighPower.tp2 | 2888 |  | 0 | no_lua |  |
| HighPower.tp2 | 3016 |  | 0 | no_lua |  |
| HighPower.tp2 | 3144 |  | 0 | no_lua |  |
| HighPower.tp2 | 3272 |  | 0 | no_lua |  |
| HighPower.tp2 | 3400 |  | 0 | no_lua |  |
| HighPower.tp2 | 3528 |  | 0 | no_lua |  |
| HighPower.tp2 | 3656 |  | 0 | no_lua |  |
| HighPower.tp2 | 3784 |  | 0 | no_lua |  |
| HighPower.tp2 | 3848 |  | 0 | no_lua |  |
| HighPower.tp2 | 3852 |  | 0 | unknown |  |
| HighPower.tp2 | 3912 |  | 0 | unknown |  |
| HighPower.tp2 | 4040 |  | 0 | unknown |  |
| HighPower.tp2 | 4168 |  | 0 | unknown |  |
| HighPower.tp2 | 4200 |  | 0 | unknown |  |
| HighPower.tp2 | 4232 |  | 0 | unknown |  |
| HighPower.tp2 | 4296 |  | 0 | unknown |  |
| HighPower.tp2 | 4424 |  | 0 | no_lua |  |
| HighPower.tp2 | 4552 |  | 0 | no_lua |  |
| HighPower.tp2 | 4680 |  | 2 | partial | EEex_FetchBCS |

## house-rule-tweaks

**Missing EEex names:** `EEex_Sprite_GetAnyStat`(11), `EEex_Stats_FirstExtendedStatID`(1), `EEex_Sprite_GetExtendedStat`(1), `EEex_Actionbar`(1)

**Unknown fields:** none

**Engine-object methods called:** `getClass`(4), `getModalState`(1)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 1 compatible, 0 partial, 0 unsupported, 45 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 6 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| HouseTweaks.TP2 | 0001 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0002 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0003 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0004 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0005 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0006 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0007 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0008 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0108 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0013 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0045 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0009 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0010 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0011 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0012 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0014 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0015 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0016 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0017 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0018 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0019 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0020 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0021 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0022 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0023 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0024 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0025 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0026 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0027 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0028 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0029 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0030 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0031 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0032 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0033 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0034 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 00341 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0035 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0036 |  | 0 | no_lua |  |
| HouseTweaks.TP2 | 0037 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0038 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0039 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0040 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0041 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0042 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0043 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0044 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0046 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0048 |  | 1 | compatible |  |
| HouseTweaks.TP2 | 0049 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0050 |  | 0 | unknown |  |
| HouseTweaks.TP2 | 0051 |  | 0 | unknown |  |

## iui

**Missing EEex names:** `EEex_Active`(33), `EEex_Modules`(18), `EEex_ReadLString`(17), `EEex_Read32`(10), `EEex_Read16`(9), `EEex_Read64`(4), `EEex_Read8`(1), `EEex_ReadU8`(1), `EEex_ReadU16`(1), `EEex_ReadU32`(1), `EEex_ReadU64`(1), `EEex_ReadPointer`(1), `EEex_ReadPtr`(1), `EEex_ReadString`(1), `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_WritePointer`(1), `EEex_WritePtr`(1), `EEex_WriteString`(1), `EEex_WriteLString`(1), `EEex_GameObject_GetUnderCursor`(1), `EEex_Sprite_GetNumCharacters`(1), `EEex_Sprite_GetAllOfTypeStringInRange`(1)

**Unknown fields:** `m_bConfirmDialog`(48), `m_bRenderFrameTimes`(12), `m_spellLevelq`(1), `m_Animation`(1)

**Engine-object methods called:** `getStat`(38), `getName`(4), `hasID`(3), `getLine`(3), `free`(3), `get`(2), `getAbilityForLevel`(1), `getAbility`(1), `getLocalInt`(1), `isSprite`(1)

**Hard usage:** `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_WritePointer`(1), `EEex_WritePtr`(1), `EEex_WriteString`(1)

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 2 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 7 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| infinity_ui.tp2 | 0 |  | 0 | unknown |  |
| infinity_ui.tp2 | 1 |  | 0 | unknown |  |
| infinity_ui.tp2 | 2 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 3 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 4 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 5 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 6 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 7 |  | 0 | no_lua |  |
| infinity_ui.tp2 | 8 |  | 0 | no_lua |  |

## olvynspells

**Missing EEex names:** `EEex_ReadDword`(2136), `EEex_ApplyEffectToActor`(436), `EEex_ReadLString`(409), `EEex_WriteDword`(367), `EEex_GetActorStat`(308), `EEex_ReadWord`(236), `EEex_GetActorShare`(174), `EEex_WriteWord`(154), `EEex_IsSprite`(153), `EEex_ProjectileType`(110), `EEex_IterateActorEffects`(98), `EEex_ReadByte`(94), `EEex_ReadQword`(84), `EEex_ReadSignedWord`(74), `EEex_WriteByte`(68), `EEex_RecordSpell`(67), `EEex_DemandResData`(66), `EEex_GetActorIDShare`(62), `EEex_GetGameTick`(55), `EEex_Label`(50), `EEex_DS`(44), `EEex_GetActorIDCharacter`(35), `EEex_GetActorName`(35), `EEex_GetDistance`(34), `EEex_GetSpellData`(30), `EEex_GetActorCasterLevel`(27), `EEex_GetActorAreaRes`(25), `EEex_GetActorSpellRES`(24), `EEex_ProjectileHookSource`(22), `EEex_Flags`(22), `EEex_WriteLString`(22), `EEex_GetActionID`(21), `EEex_GetActorIDPortrait`(20), `EEex_GetActorLocation`(20), `EEex_SetActionID`(20), `EEex_GetActorAllegiance`(18), `EEex_CompareActorAllegiances`(17), `EEex_IterateIDs`(16), `EEex_AddActionHookOpcode`(15), `EEex_GetDistanceIsometric`(15), `EEex_GetActorRequiredDirection`(14), `EEex_ModifyTerrainTable`(14), `EEex_LuaObject`(14), `EEex_GetActorClass`(13), `EEex_ReadSignedByte`(12), `EEex_AddActionHookGlobal`(10), `EEex_GetActorAnimation`(10), `EEex_GetActorSpellState`(10), `EEex_GetActorIDArea`(9), `EEex_effOff`(9), `EEex_IterateCPtrList`(8), `EEex_Sprite_GetExtendedStat`(8), `EEex_GetActorDirection`(8), `EEex_WithinCyclicRange`(8), `EEex_ProcessClericMemorization`(8), `EEex_ProcessWizardMemorization`(8), `EEex_ToHex`(8), `EEex_AddScreenEffectsGlobal`(7), `EEex_GetActorAreaSize`(7), `EEex_AlterActorEffect`(7), `EEex_GetActionPointX`(7), `EEex_GetActionPointY`(7), `EEex_GetBitmapPixelIndex`(7), `EEex_IsFlying`(7), `EEex_RollEffectDice`(7), `EEex_HasState`(6), `EEex_DemandRes`(6), `EEex_ConstantID`(6), `EEex_PostLaunchMutatorOpcodeFunctions`(6), `EEex_Action_Hook_OpcodeFunctions`(5), `EEex_GetGlobal`(5), `EEex_GetGameData`(5), `EEex_IsImmuneToOpcode`(5), `EEex_GetActorGeneral`(5), `EEex_GetActorRace`(5), `EEex_GetActorScriptName`(5), `EEex_CyclicBound`(5), `EEex_ToString`(5), `EEex_GetActorMovementRate`(5), `EEex_GetActorCurrentAction`(5), `EEex_Projectile_IsOfType`(5), `EEex_Projectile_Type`(5), `EEex_ScreenEffectsGlobalFunctions`(4), `EEex_SetGlobal`(4), `EEex_GetActorAlignment`(4), `EEex_GetActorKit`(4), `EEex_IsValidBackstabDirection`(4), `EEex_GetActionString1`(4), `EEex_SpellIDSType`(4), `EEex_CheckTimeStopOnActor`(4), `EEex_Action_ExecuteResponseStringOnAIBaseInstantly`(4), `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`(4), `EEex_Reset_Search_Map`(4), `EEex_MatchObject`(4), `EEex_PostLaunchMutatorGlobalFunctions`(4), `EEex_IsPartyMember`(4), `EEex_GetAreaName`(4), `EEex_RecordAttack`(4), `EEex_Action_Hook_GlobalFunctions`(3), `EEex_Opcode_AddScreenEffectsGlobal`(3), `EEex_TypeMutatorGlobalFunctions`(3), `EEex_ProjectileMutatorGlobalFunctions`(3), `EEex_AddProjectileMutatorGlobal`(3), `EEex_EffectMutatorGlobalFunctions`(3), `EEex_DecodeProjectileSources`(3), `EEex_AccessComplexStat`(3), `EEex_ProjectileMutatorList`(3), `EEex_ReadString`(3), `EEex_HookAfterRestore`(3), `EEex_WriteStringAuto`(3), `EEex_GameObject_GetUnderCursorID`(3), `EEex_GetActorIDSelected`(3), `EEex_IterateAreas`(3), `EEex_GetActorIDLoaded`(3), `EEex_Sprite_GetState`(3), `EEex_GetActorPortraitSlot`(3), `EEex_JumpActorToPoint`(3), `EEex_DoInstantAction`(3), `EEex_GetActorFullResistance`(3), `EEex_CheckForInfiniteLoop`(3), `EEex_Call`(3), `EEex_SetActionbarButton`(3), `EEex_ACTIONBAR_TYPE`(3), `EEex_EvalObjectStringAsActor`(3), `EEex_GetActorLevel`(3), `EEex_LuaTriggerActorID`(3), `EEex_ObjectData`(3), `EEex_Sprite_GetCasterLevel`(3), `EEex_Sprite_GetSpellRES`(3), `EEex_Sprite_IterateEffects`(2), `EEex_IsProjectileOfType`(2), `EEex_AddEffectToProjectileSources`(2), `EEex_ProjectileInheritance`(2), `EEex_ProjectileVFTableToType`(2), `EEex_GetProjectileType`(2), `EEex_OnDecodeProjectile`(2), `EEex_OnPostProjectileCreation`(2), `EEex_OnAddEffectToProjectile`(2), `EEex_WriteQword`(2), `EEex_GetAllActorIDSelected`(2), `EEex_GetIDArea`(2), `EEex_GetActorCurrentHP`(2), `EEex_GetActorModalState`(2), `EEex_IsImmuneToSpellLevel`(2), `EEex_GetActorGender`(2), `EEex_GetActorTargetID`(2), `EEex_GetActionTarget`(2), `EEex_SetActionPointX`(2), `EEex_SetActionPointY`(2), `EEex_ProcessInnateMemorization`(2), `EEex_Menu_SetTemplateArea`(2), `EEex_HeightMod`(2), `EEex_GetSpellName`(2), `EEex_Modules`(2), `EEex_CheckActorLOS`(2), `EEex_Sprite_ForAllOfTypeStringInRange`(2), `EEex_AddActionHook`(2), `EEex_RunBCSAsActor`(2), `EEex_IsInAir`(2), `EEex_IsIncorporeal`(2), `EEex_IsEthereal`(2), `EEex_IterateActorIDs`(2), `EEex_GetBitmapPixelColor`(2), `EEex_IterateDoors`(2), `EEex_IsKeyDown`(2), `EEex_AddPostLaunchMutatorGlobal`(2), `EEex_VolatileStorageDefinitions`(2), `EEex_Action`(1), `EEex_Action_Hook_OnEvaluatingUnknown`(1), `EEex_Opcode`(1), `EEex_Opcode_Hook_ApplyScreenEffects`(1), `EEex_Crashing`(1), `EEex_AddTypeMutatorGlobal`(1), `EEex_AddEffectMutatorGlobal`(1), `EEex_DisableCodeProtection`(1), `EEex_EnableCodeProtection`(1), `EEex_FetchBCS`(1), `EEex_Action_AddEnabledSpriteStartedActionListener`(1), `EEex_ReadU8`(1), `EEex_Read8`(1), `EEex_ReadU16`(1), `EEex_Read16`(1), `EEex_Read32`(1), `EEex_ReadU64`(1), `EEex_ReadSignedQword`(1), `EEex_Read64`(1), `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_GGD`(1), `EEex_GetWorldMapData`(1), `EEex_IsTimeStopped`(1), `EEex_GetActorIDCursor`(1), `EEex_GIDC`(1), `EEex_GIDS`(1), `EEex_GS`(1), `EEex_GSC`(1), `EEex_GSS`(1), `EEex_GetImageMasterID`(1), `EEex_GetLocal`(1), `EEex_SetLocal`(1), `EEex_GetActorState`(1), `EEex_Sprite_GetSpellState`(1), `EEex_GetActorSpecifics`(1), `EEex_GetActorDialogue`(1), `EEex_GetActorItemRes`(1), `EEex_GetActorItemCharges`(1), `EEex_SetActorItemCharges`(1), `EEex_IterateActorItems`(1), `EEex_IsActorFacing`(1), `EEex_SetActionTarget`(1), `EEex_GetActionParameter2`(1), `EEex_SetActionParameter2`(1), `EEex_SetActionString1`(1), `EEex_AIBase_JumpToPoint`(1), `EEex_Opcode_Hook_OnCheckAdd`(1), `EEex_ScreenEffects`(1), `EEex_GameObject_GetUnderCursor`(1), `EEex_Menu_IsCursorWithin`(1), `EEex_GameState_AddDestroyedListener`(1), `EEex_Sprite_Hook_OnDestruct`(1), `EEex_Search_Change`(1), `EEex_Search`(1), `EEex_PrintData`(1), `EEex_Action_ParseResponseString`(1), `EEex_Action_ExecuteScriptFileResponseAsAIBaseInstantly`(1), `EEex_GetActorLocal`(1), `EEex_GetActorWizardLevel`(1), `EEex_GetActorPriestLevel`(1), `EEex_MatchObjectEx`(1), `EEex_Projectile_RegisterGlobalMutator`(1), `EEex_AddPostLaunchMutatorOpcode`(1), `EEex_GameObjectAdded`(1), `EEex_Malloc`(1), `EEex_VolatileStorageSpace`(1), `EEex_GameObjectBeingDeleted`(1), `EEex_Free`(1), `EEex_DamageAbsorption`(1)

**Unknown fields:** `m_nTimeStop`(2), `m_pEngineWorldMap`(1), `m_cContingencyList`(1)

**Engine-object methods called:** `isValid`(6), `getData`(6), `free`(6), `getActiveStats`(2), `get`(2), `isSprite`(1), `getCastTimerPercentage`(1), `getModalState`(1)

**Hard usage:** `EEex_WriteWord`(154), `EEex_WriteByte`(68), `EEex_Label`(50), `EEex_HookAfterRestore`(3), `EEex_WriteStringAuto`(3), `EEex_DisableCodeProtection`(1), `EEex_EnableCodeProtection`(1), `EEex_Write8`(1), `EEex_Write16`(1), `EEex_Write32`(1), `EEex_Write64`(1), `EEex_Malloc`(1)

**Declares IEX support:** no

**Components:** 1 compatible, 3 partial, 5 unsupported, 51 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 18 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| MESpells.tp2 | 0 |  | 0 | unknown |  |
| MESpells.tp2 | 1 |  | 0 | unknown |  |
| MESpells.tp2 | 2 |  | 0 | no_lua |  |
| MESpells.tp2 | 3 |  | 0 | unknown |  |
| MESpells.tp2 | 4 |  | 0 | no_lua |  |
| MESpells.tp2 | 5 |  | 0 | unknown |  |
| MESpells.tp2 | 6 |  | 0 | unknown |  |
| MESpells.tp2 | 7 |  | 0 | unknown |  |
| MESpells.tp2 | 8 |  | 0 | unknown |  |
| MESpells.tp2 | 9 |  | 0 | unknown |  |
| MESpells.tp2 | 10 |  | 0 | unknown |  |
| MESpells.tp2 | 11 |  | 0 | unknown |  |
| MESpells.tp2 | 12 |  | 0 | unknown |  |
| MESpells.tp2 | 13 |  | 0 | unknown |  |
| MESpells.tp2 | 14 |  | 0 | unknown |  |
| MESpells.tp2 | 15 |  | 0 | unknown |  |
| MESpells.tp2 | 16 |  | 0 | unknown |  |
| MESpells.tp2 | 17 |  | 0 | unknown |  |
| MESpells.tp2 | 18 |  | 0 | unknown |  |
| MESpells.tp2 | 19 |  | 0 | unknown |  |
| MESpells.tp2 | 20 |  | 0 | unknown |  |
| MESpells.tp2 | 21 |  | 0 | unknown |  |
| MESpells.tp2 | 22 |  | 0 | unknown |  |
| MESpells.tp2 | 23 |  | 0 | unknown |  |
| MESpells.tp2 | 24 |  | 0 | unknown |  |
| MESpells.tp2 | 25 |  | 0 | unknown |  |
| MESpells.tp2 | 26 |  | 1 | compatible |  |
| MESpells.tp2 | 27 |  | 0 | unknown |  |
| MESpells.tp2 | 11011 |  | 0 | unknown |  |
| MESpells.tp2 | 11012 |  | 0 | unknown |  |
| MESpells.tp2 | 11013 |  | 0 | unknown |  |
| MESpells.tp2 | 11021 |  | 0 | unknown |  |
| MESpells.tp2 | 11051 |  | 0 | no_lua |  |
| MESpells.tp2 | 11052 |  | 0 | unknown |  |
| MESpells.tp2 | 11053 |  | 0 | no_lua |  |
| MESpells.tp2 | 11061 |  | 0 | no_lua |  |
| MESpells.tp2 | 12091 |  | 2 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| MESpells.tp2 | 14131 |  | 0 | no_lua |  |
| MESpells.tp2 | 14161 |  | 0 | unknown |  |
| MESpells.tp2 | 15031 |  | 0 | unknown |  |
| MESpells.tp2 | 15071 |  | 0 | no_lua |  |
| MESpells.tp2 | 17041 |  | 0 | no_lua |  |
| MESpells.tp2 | 14021 |  | 0 | unknown |  |
| MESpells.tp2 | 25011 |  | 0 | unknown |  |
| MESpells.tp2 | 25012 |  | 0 | unknown |  |
| MESpells.tp2 | 17261 |  | 0 | no_lua |  |
| MESpells.tp2 | 21111 |  | 0 | unknown |  |
| MESpells.tp2 | 21161 |  | 0 | unknown |  |
| MESpells.tp2 | 22201 |  | 0 | no_lua |  |
| MESpells.tp2 | 21151 |  | 0 | unknown |  |
| MESpells.tp2 | 21191 |  | 0 | unknown |  |
| MESpells.tp2 | 21231 |  | 0 | unknown |  |
| MESpells.tp2 | 22031 |  | 0 | unknown |  |
| MESpells.tp2 | 22211 |  | 0 | unknown |  |
| MESpells.tp2 | 23131 |  | 0 | unknown |  |
| MESpells.tp2 | 24041 |  | 0 | no_lua |  |
| MESpells.tp2 | 24042 |  | 0 | unknown |  |
| MESpells.tp2 | 24081 |  | 1 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| MESpells.tp2 | 24131 |  | 0 | unknown |  |
| MESpells.tp2 | 25031 |  | 0 | no_lua |  |
| MESpells.tp2 | 25151 |  | 2 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| MESpells.tp2 | 26071 |  | 0 | no_lua |  |
| MESpells.tp2 | 26111 |  | 0 | no_lua |  |
| MESpells.tp2 | 26151 |  | 1 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| MESpells.tp2 | 27121 |  | 0 | no_lua |  |
| MESpells.tp2 | 29111 |  | 1 | unsupported | EEex_Label, EEex_Malloc, EEex_Write16, EEex_Write32 |
| MESpells.tp2 | 29141 |  | 0 | unknown |  |
| MESpells.tp2 | 29221 |  | 0 | unknown |  |
| MESpells.tp2 | 26171 |  | 0 | no_lua |  |
| MESpells.tp2 | 14151 |  | 0 | no_lua |  |
| MESpells.tp2 | 23011 |  | 0 | no_lua |  |
| MESpells.tp2 | 980 |  | 0 | unknown |  |
| MESpells.tp2 | 990 |  | 0 | unknown |  |
| MESpells.tp2 | 1000 |  | 9 | partial | EEex_FetchBCS |
| MESpells.tp2 | 1001 |  | 9 | partial | EEex_FetchBCS |
| MESpells.tp2 | 1050 |  | 1 | partial | EEex_FetchBCS |
| MESpells.tp2 | 1100 |  | 0 | unknown |  |
| MESpells.tp2 | 1200 |  | 0 | unknown |  |

## pathfinding-redux

**Missing EEex names:** `EEex_Read32`(292), `EEex_Write32`(168), `EEex_ReadPtr`(143), `EEex_ReadU8`(95), `EEex_FlattenTable`(79), `EEex_HookBeforeRestoreWithLabels`(48), `EEex_GenLuaCall`(46), `EEex_LuaCallReturnType`(33), `EEex_Read16`(32), `EEex_WritePtr`(30), `EEex_Malloc`(26), `EEex_HookIntegrityWatchdogRegister`(24), `EEex_Write8`(21), `EEex_HookAfterRestoreWithLabels`(20), `EEex_HookBeforeAndAfterCallWithLabels`(17), `EEex_DefineAssemblyLabel`(15), `EEex_JITNearAsLuaFunction`(15), `EEex_EnableCodeProtection`(15), `EEex_Memcpy`(14), `EEex_Label`(13), `EEex_RunWithStack`(12), `EEex_Memset`(10), `EEex_DisableCodeProtection`(10), `EEex_JITNear`(7), `EEex_JITAt`(7), `EEex_HookRemoveCallWithLabels`(7), `EEex_GetImageBase`(6), `EEex_OffsetOf`(6), `EEex_HookBeforeCallWithLabels`(6), `EEex_CInfGame`(6), `EEex_HookAfterCallWithLabels`(5), `EEex_RunWithStackManager`(4), `EEex_CBaldurChitin`(4), `EEex_Split`(2), `EEex_scripts`(2), `EEex_Assembly_Private_MacroSwitch`(2), `EEex_GetUTBaseclassMetadata`(1), `EEex_Assembly`(1), `EEex_Assembly_Private_FindOffsetOf`(1), `EEex_PreprocessAssemblyStr`(1), `EEex_HookConditionalJumpWithLabels`(1), `EEex_Once`(1), `EEex_RoundUp`(1), `EEex_DistanceToMultiple`(1), `EEex_Assembly_x86`(1), `EEex_Assembly_Private_InitState`(1), `EEex_PreprocessAssembly`(1), `EEex_HookIntegrityWatchdog_Load`(1), `EEex_RunWithAssemblyLabels`(1), `EEex_TryLabel`(1), `EEex_WriteStringCache`(1)

**Unknown fields:** `m_nBattleSongCounter`(13), `m_inCutScene`(12), `m_nDamageCounter`(11), `m_charactersPortrait`(9), `m_gameSave`(4), `m_inputMode`(4), `m_actionList`(4), `m_bAllowEffectListCall`(4)

**Engine-object methods called:** `getPersonalSpace`(42), `getPortraitIndex`(29), `forAllOfTypeInRange`(26), `get`(20), `getState`(8), `getUD`(8), `getName`(4)

**Hard usage:** `EEex_Write32`(168), `EEex_FlattenTable`(79), `EEex_HookBeforeRestoreWithLabels`(48), `EEex_GenLuaCall`(46), `EEex_WritePtr`(30), `EEex_Malloc`(26), `EEex_HookIntegrityWatchdogRegister`(24), `EEex_Write8`(21), `EEex_HookAfterRestoreWithLabels`(20), `EEex_HookBeforeAndAfterCallWithLabels`(17), `EEex_JITNearAsLuaFunction`(15), `EEex_EnableCodeProtection`(15), `EEex_Memcpy`(14), `EEex_Label`(13), `EEex_DisableCodeProtection`(10), `EEex_JITNear`(7), `EEex_JITAt`(7), `EEex_HookRemoveCallWithLabels`(7), `EEex_HookBeforeCallWithLabels`(6), `EEex_HookAfterCallWithLabels`(5), `EEex_HookConditionalJumpWithLabels`(1), `EEex_HookIntegrityWatchdog_Load`(1), `EEex_WriteStringCache`(1)

**Declares IEX support:** no

**Components:** 0 compatible, 1 partial, 0 unsupported, 0 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| bg-redux-movement.tp2 | 0 |  | 1 | partial | EEex_GetImageBase, EEex_Read32 |

## poisoned-pathways

**Missing EEex names:** `EEex_LuaTrigger`(292), `EEex_Object_ParseString`(13)

**Unknown fields:** none

**Engine-object methods called:** `evalAsAIBase`(3)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 1 partial, 0 unsupported, 0 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| Setup-Poisoned_pathways.tp2 | 0 |  | 3 | partial | EEex_Object_ParseString |

## sod2bg2-iu

**Missing EEex names:** `EEex_GetActorClass`(2), `EEex_GetActorKit`(2), `EEex_GetActorAlignment`(2)

**Unknown fields:** none

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 2 compatible, 0 partial, 0 unsupported, 5 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 31 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| sod2bg2_iu.tp2 | 0 |  | 1 | compatible |  |
| sod2bg2_iu.tp2 | 1 |  | 1 | compatible |  |
| sod2bg2_iu.tp2 | 2 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 3 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 4 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 5 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 6 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 7 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 8 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 9 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 10 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 11 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 12 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 13 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 14 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 15 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 16 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 17 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 18 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 19 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 20 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 21 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 22 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 23 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 24 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 25 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 26 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 27 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 28 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 29 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 30 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 31 |  | 0 | unknown |  |
| sod2bg2_iu.tp2 | 32 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 33 |  | 0 | no_lua |  |
| sod2bg2_iu.tp2 | 34 |  | 0 | unknown |  |
| sod2bg2_iu.tp2 | 35 |  | 0 | unknown |  |
| sod2bg2_iu.tp2 | 36 |  | 0 | unknown |  |
| sod2bg2_iu.tp2 | 37 |  | 0 | unknown |  |

## tweaks

**Missing EEex names:** `EEex_LuaTrigger`(44), `EEex_LuaDecode_Object`(23), `EEex_Target`(22), `EEex_IsImmuneToOpcode`(20), `EEex_Area_GetAllOfTypeInRange`(11), `EEex_Trigger_ParseConditionalString`(9), `EEex_Sprite_GetAllOfTypeInRange`(7), `EEex_Sprite_AddQuickListsCheckedListener`(6), `EEex_Area_GetAllOfTypeStringInRange`(6), `EEex_CChitin`(6), `EEex_LuaAction`(5), `EEex_Sprite_GetCastTimer`(4), `EEex_Object_ParseString`(4), `EEex_Sprite_GetPersonalSpace`(4), `EEex_Sprite_AddAlterBaseWeaponDamageListener`(4), `EEex_Sprite_AddBlockWeaponHitListener`(4), `EEex_LuaDecode`(3), `EEex_Sprite_GetAllOfTypeStringInRange`(3), `EEex_Sprite_GetSpellState`(3), `EEex_Action_ParseResponseString`(3), `EEex_SpellObjectOffset`(3), `EEex_Sprite_GetCasterLevelForSpell`(2), `EEex_Action_ExecuteScriptFileResponseAsAIBaseInstantly`(2), `EEex_RunWithStackManager`(2), `EEex_WriteUDArgs`(2), `EEex_SpellObjectOffsetNoDec`(2), `EEex_ForceSpellObjectOffset`(2), `EEex_ReallyForceSpellObjectOffset`(2), `EEex_SpellObjectOffsetRES`(1), `EEex_Utility_TryFinally`(1), `EEex_Trigger_EvalScriptFileConditionalAsAIBase`(1), `EEex_NewUD`(1), `EEex_Sprite_GetLauncher`(1), `EEex_LuaObject`(1), `EEex_Sprite_GetModalState`(1), `EEex_Sprite_GetModalTimer`(1), `EEex_Resource_GetAt2DAPoint`(1), `EEex_Key_AddReleasedListener`(1), `EEex_Projectile_IsOfType`(1), `EEex_Projectile_Type`(1)

**Unknown fields:** `m_sourceTarget`(78), `m_lSummonedBy`(6), `m_nAIIndex`(3), `m_nBattleSongCounter`(3), `m_nAssassinate`(3), `m_wFileType`(2), `m_newEffect`(2), `m_hatedRace`(2), `m_dwAreaFlags`(1), `m_explosionRange`(1), `m_terrainTable`(1), `m_coneSize`(1), `m_secondaryProjectile`(1), `m_nSpellFailureMage`(1), `m_nSpellFailurePriest`(1), `m_nSpellFailureInnate`(1), `m_followCount`(1), `m_bPartyAI`(1), `m_abilityId`(1), `m_itemType`(1), `m_bDisplayCount`(1), `m_count`(1), `m_options`(1), `m_b3ESneakAttack`(1), `m_bPolymorphed`(1), `m_nLastDamageTaken`(1), `m_bImmuneToTimeStop`(1), `m_inCutScene`(1), `m_nMissileTHAC0Bonus`(1), `m_nLevelDrain`(1)

**Engine-object methods called:** `applyEffect`(253), `get`(244), `getLocalInt`(105), `setLocalInt`(102), `getActiveStats`(71), `getReference`(15), `set`(10), `free`(9), `getName`(7), `setStoredScriptingTarget`(5), `evalConditionalAsAIBase`(5), `getAtPoint`(4), `getUD`(4), `getLocalString`(4), `getDimensions`(3), `getRowLabel`(3), `getAbility`(3), `getAllOfTypeInRange`(2), `evalAsAIBase`(2), `setLocalString`(2), `getStartingPos`(1), `executeResponseAsAIBaseInstantly`(1), `getColumnLabel`(1), `iterateUnpackedEntries`(1), `getLauncher`(1), `getValidSpellsWithAbilityItr`(1), `getRowColumnsItr`(1), `getKnownPriestSpellsWithAbilityIterator`(1)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 58 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 392 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| setup-cdtweaks.tp2 | 0 | cd_tweaks_batch_install | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 10 | cd_tweaks_remove_helmets | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 20 | cd_tweaks_imoen_avatar_change | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 30 | cd_tweaks_nalia_avatar_change | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 40 | cd_tweaks_viconia_skin_color | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 50 | cd_tweaks_avatar_morphing_script | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 60 | cd_tweaks_weapon_animation_tweaks | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 70 | cd_tweaks_iwd_casting_graphics | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 72 | cd_tweaks_bg_casting_graphics | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 80 | cd_tweaks_restore_soa_loading_screen | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 82 | cd_tweaks_restore_iwd_loading_screen | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 90 | cd_tweaks_remove_portrait_icons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 100 | cd_tweaks_drab_commoners | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 110 | cd_tweaks_icon_improvements | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 120 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 130 | cd_tweaks_force_all_dialogue_to_pause | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 140 | cd_tweaks_fix_boo_squeak | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 150 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 160 | cd_tweaks_glowing_magical_shields | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 170 | cd_tweaks_unique_icons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 171 | cd_tweaks_unique_icons_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 180 | cd_tweaks_unique_containers_fixes_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 181 | cd_tweaks_unique_containers_fixes_and_icons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 182 | cd_tweaks_unique_containers_full | 0 | unknown |  |
| setup-cdtweaks.tp2 | 190 | cd_tweaks_char_colors_all_helms_shields | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 191 | cd_tweaks_char_colors_normal_helms_shields | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 192 | cd_tweaks_char_colors_all_helms | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 193 | cd_tweaks_char_colors_normal_helms | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 194 | cd_tweaks_char_colors_all_shields | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 195 | cd_tweaks_char_colors_normal_shields | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 200 | cd_tweaks_remove_equipped_blur_effects | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3150 | cd_tweaks_remove_equipped_spell_trap_effects | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3151 | cd_tweaks_remove_equipped_blur_spell_trap_effects | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2010 | cd_tweaks_replace_fire_cold_resist_icons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 220 | cd_tweaks_colorblind_overlays | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 230 | cd_tweaks_restore_iwd_tooltips | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 240 | cd_tweaks_outline_white_spell_icons_with_black | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 241 | cd_tweaks_outline_white_spell_icons_with_gray | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 250 | cd_tweaks_colorize_npc_names_brightness_normal | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 251 | cd_tweaks_colorize_npc_names_brightness_increased_slightly | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 252 | cd_tweaks_colorize_npc_names_brightness_increased_moderately | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 253 | cd_tweaks_colorize_npc_names_brightness_decreased_slightly | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 254 | cd_tweaks_colorize_npc_names_brightness_decreased_moderately | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 255 | cd_tweaks_colorize_npc_names_color_original | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 260 | cd_tweaks_hide_vfx_from_invisible_enemies | 0 | unknown |  |
| setup-cdtweaks.tp2 | 270 | cd_tweaks_static_pst_npc_portraits_status | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 271 | cd_tweaks_static_pst_npc_portraits_no_status | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1010 | cd_tweaks_more_interjections | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1020 | cd_tweaks_alter_wounded_triggers | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1030 | cd_tweaks_reveal_ch6_wilderness | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1035 | cd_tweaks_reveal_cloakwood_1 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1036 | cd_tweaks_reveal_cloakwood_4 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1040 | cd_tweaks_improved_athkatla_guard | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1050 | cd_tweaks_gradual_drow_item_disintegration | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1060 | cd_tweaks_breakable_armor_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1061 | cd_tweaks_breakable_armor_bg_degrade_once | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1062 | cd_tweaks_breakable_armor_bg_degrade_progressively | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1070 | cd_tweaks_mp_kickout_dialogue | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1075 | cd_tweaks_send_bg_npcs_to_inn | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1080 | cd_tweaks_add_bags_of_holding | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1085 | cd_tweaks_portable_containers | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1090 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1100 | cd_tweaks_reveal_city_areas | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1101 | cd_tweaks_do_not_reveal_city_areas | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1110 | cd_tweaks_add_map_notes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1120 | cd_tweaks_stores_sell_higher_stacks | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1125 | cd_tweaks_infinite_nonmagical_ammo | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1130 | cd_tweaks_rep_reset_in_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1140 | cd_tweaks_lore_for_gems_potions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1141 | cd_tweaks_lore_for_gems | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1142 | cd_tweaks_lore_for_potions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1150 | cd_tweaks_weimer_shapeshifter_rebalancing | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1160 | cd_tweaks_multi_stronghold_no_restriction | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1161 | cd_tweaks_multi_stronghold_class_restriction | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1340 | cd_tweaks_sole_stronghold_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1341 | cd_tweaks_sole_stronghold_fighter | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1342 | cd_tweaks_sole_stronghold_cleric | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1343 | cd_tweaks_sole_stronghold_thief | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1344 | cd_tweaks_sole_stronghold_bard | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1345 | cd_tweaks_sole_stronghold_paladin | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1346 | cd_tweaks_sole_stronghold_druid | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1347 | cd_tweaks_sole_stronghold_ranger | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1170 | cd_tweaks_bonus_merchants | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1180 | cd_tweaks_edwina | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1190 | cd_tweaks_eou_romance_fixes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1200 | cd_tweaks_tob_imoen_dialogue_fix | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1210 | cd_tweaks_use_bg_walking_speeds | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1220 | cd_tweaks_cromwell_updates_wk_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1225 | cd_tweaks_cromwell_forge_time_0 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1226 | cd_tweaks_cromwell_forge_time_8 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1227 | cd_tweaks_cromwell_forge_time_24 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1230 | cd_tweaks_cespenar_updates_soa_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1240 | cd_tweaks_fai_container_restoration | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1250 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1257 | cd_tweaks_move_bg_npcs_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1251 | cd_tweaks_move_bg_npcs_alora | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1252 | cd_tweaks_move_bg_npcs_eldoth | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1253 | cd_tweaks_move_bg_npcs_quayle | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1254 | cd_tweaks_move_bg_npcs_sharteel | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1255 | cd_tweaks_move_bg_npcs_tiax | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1256 | cd_tweaks_move_bg_npcs_viconia | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1260 | cd_tweaks_bardic_rep_adjustment | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1270 | cd_tweaks_change_cloakwood_trigger | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1280 | cd_tweaks_game_ends_with_player1 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1290 | cd_tweaks_protagonist_replacement | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1300 | cd_tweaks_how_accessible_at_l1 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1310 | cd_tweaks_restore_bg2_spells | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1320 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1330 | cd_tweaks_I_am_a_servant_of_the_Secret_Fire_wielder_of_the_flame_of_Anor_You_cannot_pass_The_dark_fire_will_not_avail_you_flame_of_Udun_Go_back_to_the_Shadow_You_cannot_pass | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1350 | cd_tweaks_karoug_plus_one | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1351 | cd_tweaks_karoug_plus_two | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1352 | cd_tweaks_karoug_wolfsbane | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1353 | cd_tweaks_karoug_plus_one_and_wolfsbane | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1354 | cd_tweaks_karoug_plus_two_and_wolfsbane | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1360 | cd_tweaks_iwd_to_how_transition_no_change | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1361 | cd_tweaks_iwd_to_how_transition_no_hjollder | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 1370 | cd_tweaks_monk_weapons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2020 | cd_tweaks_2h_bastard_swords | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2030 | cd_tweaks_2h_katanas | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2035 | cd_tweaks_2h_axes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2040 | cd_tweaks_universal_clubs | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2060 | cd_tweaks_weapon_styles_for_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2080 | cd_tweaks_delay_hlas | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2090 | cd_tweaks_remove_xp_cap | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2091 | cd_tweaks_cap_xp_at_l20 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2092 | cd_tweaks_cap_xp_at_l30 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2720 | cd_tweaks_yoshi_imoen_xp_transfer | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2570 | cd_tweaks_bgt_xp_cap_in_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2571 | cd_tweaks_bgt_xp_cap_in_soa | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2100 | cd_tweaks_thieving_in_heavy_armor | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2120 | cd_tweaks_casting_in_armor | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2140 | cd_tweaks_more_dual_classes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2150 | cd_tweaks_protection_items_pnp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2151 | cd_tweaks_protection_items_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2152 | cd_tweaks_protection_items_armor_plus_one | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2160 | cd_tweaks_alter_prof_rebalanced | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2161 | cd_tweaks_alter_prof_bg_with_styles | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2162 | cd_tweaks_alter_prof_bg_no_styles | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2163 | cd_tweaks_alter_prof_iwd_with_styles | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2164 | cd_tweaks_alter_prof_iwd_no_styles | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2170 | cd_tweaks_item_spells_at_char_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2190 | cd_tweaks_shopkeeper_id_mages | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2191 | cd_tweaks_shopkeeper_id_lore | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2192 | cd_tweaks_shopkeeper_id_hybrid | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2200 | cd_tweaks_multiclass_gm | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2210 | cd_tweaks_grandmastery_bonus_true | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2211 | cd_tweaks_grandmastery_bonus_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2220 | cd_tweaks_0_weight_created_weapons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2230 | cd_tweaks_consistent_x_y_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2231 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2240 | cd_tweaks_alter_thac0_table | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2250 | cd_tweaks_sorc_spell_progression | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2260 | cd_tweaks_mage_spell_progression_unnerfed | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2261 | cd_tweaks_mage_spell_progression_pnp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2270 | cd_tweaks_bard_spell_progression_unnerfed | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2271 | cd_tweaks_bard_spell_progression_pnp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2280 | cd_tweaks_cleric_spell_progression_unnerfed | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2281 | cd_tweaks_cleric_spell_progression_pnp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2288 | cd_tweaks_druid_spell_progression_cleric_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2289 | cd_tweaks_druid_spell_progression_cleric_unnerfed_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2290 | cd_tweaks_druid_spell_progression_unnerfed_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2291 | cd_tweaks_druid_spell_progression_pnp_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2292 | cd_tweaks_druid_spell_progression_unchanged_cleric_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2293 | cd_tweaks_druid_spell_progression_unnerfed_cleric_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2294 | cd_tweaks_druid_spell_progression_pnp_cleric_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2295 | cd_tweaks_druid_spell_progression_cleric_normal_cleric_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2296 | cd_tweaks_druid_spell_progression_cleric_unnerfed_cleric_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2730 | cd_tweaks_druid_spell_progression_unchanged_iwd_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2731 | cd_tweaks_druid_spell_progression_unnerfed_iwd_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2732 | cd_tweaks_druid_spell_progression_pnp_iwd_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2733 | cd_tweaks_druid_spell_progression_cleric_normal_iwd_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2734 | cd_tweaks_druid_spell_progression_cleric_unnerfed_iwd_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2735 | cd_tweaks_druid_spell_progression_unchanged_bg2_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2736 | cd_tweaks_druid_spell_progression_unnerfed_bg2_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2737 | cd_tweaks_druid_spell_progression_pnp_bg2_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2738 | cd_tweaks_druid_spell_progression_cleric_normal_bg2_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2739 | cd_tweaks_druid_spell_progression_cleric_unnerfed_bg2_druid_level | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2297 | cd_tweaks_druid_spell_progression_unchanged_cleric_level_obg_version | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2580 | cd_tweaks_alter_wisdom-based_divine_bonus_spell_table_pnp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2581 | cd_tweaks_alter_wisdom-based_divine_bonus_spell_table_bg_bg2_iwd | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2300 | cd_tweaks_triple_class_hla_table | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2310 | cd_tweaks_arcane_save_penalties | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2311 | cd_tweaks_divine_save_penalties | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2312 | cd_tweaks_arcane_divine_save_penalties | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2320 | cd_tweaks_trap_cap_removal | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2330 | cd_tweaks_remove_magical_trap_delay | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2339 | cd_tweaks_summoning_cap_removal | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2340 | cd_tweaks_celestial_cap_removal | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2360 | cd_tweaks_remove_class_racial_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2380 | cd_tweaks_remove_kit_racial_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2371 | cd_tweaks_alter_dualclass_humans_yes_nonhumans_yes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2370 | cd_tweaks_alter_dualclass_humans_no_nonhumans_no | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2372 | cd_tweaks_alter_dualclass_humans_no_nonhumans_yes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2350 | cd_tweaks_multiclass_allow_humans | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2351 | cd_tweaks_multiclass_allow_nonhumans_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2352 |  | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2353 | cd_tweaks_multiclass_allow_nonhumans_limited | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2357 | cd_tweaks_multiclass_allow_all_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2358 | cd_tweaks_multiclass_allow_all_limited | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2550 | cd_tweaks_gnome_multiclass_illusionist_kits_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2551 | cd_tweaks_gnome_multiclass_mage_kits_illusionist | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2552 | cd_tweaks_gnome_multiclass_mage_kits_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2390 | cd_tweaks_paladin_spell_progression_iwd | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2391 | cd_tweaks_paladin_spell_progression_alt | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2400 | cd_tweaks_ranger_spell_progression_iwd | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2401 | cd_tweaks_ranger_spell_progression_alt | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2410 | cd_tweaks_druids_use_3e_alignment | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2420 | cd_tweaks_cleric_multis_loosen_equipment_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2430 | cd_tweaks_druid_multis_loosen_equipment_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2431 | cd_tweaks_druid_multis_tighten_equipment_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2440 | cd_tweaks_specialization_apr_bonus_for_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2450 | cd_tweaks_pnp_prof_restrictions_for_dualclasses | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2500 | cd_tweaks_exceptional_strength_weight_limits | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2510 | cd_tweaks_level_locked_scrolls | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2520 | cd_tweaks_loosen_shield_restrictions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2530 | cd_tweaks_lightning_bolts_pls_no_bouncerino | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2540 | cd_tweaks_faster_dearnise_keep_timer | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2560 | cd_tweaks_allow_monks_to_wear_helmets | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2561 | cd_tweaks_allow_monks_to_use_staves | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2562 | cd_tweaks_allow_monks_to_use_helmets_and_staves | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2590 | cd_tweaks_thieves_backstab_uai | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2620 | cd_tweaks_backstab_immunity | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2630 | cd_tweaks_nwn_cure_cause_wounds | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2640 | cd_tweaks_pnp_potions | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2650 | cd_tweaks_make_grease_ignitable | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2660 | cd_tweaks_bears_and_boars | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2670 | cd_tweaks_limit_resting_mechanic | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2680 | cd_tweaks_infravision | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2690 | cd_tweaks_alternate_concentration_check_v1 | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2691 | cd_tweaks_alternate_concentration_check_v2 | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2692 | cd_tweaks_alternate_concentration_check_v3 | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2693 | cd_tweaks_alternate_concentration_check_v4 | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2700 | cd_tweaks_revised_troll_regeneration | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2710 | cd_tweaks_nwn_summons | 0 | unknown |  |
| setup-cdtweaks.tp2 | 2740 | cd_tweaks_shapeshifter_armor | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 2999 | cd_tweaks_max_hp_at_l1 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3000 | cd_tweaks_higher_hp_at_levelup_max | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3001 | cd_tweaks_higher_hp_at_levelup_nwn | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3002 | cd_tweaks_higher_hp_at_levelup_average | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3003 | cd_tweaks_higher_hp_at_levelup_small | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3008 | cd_tweaks_extend_hp_rolls_to_l20 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3010 | cd_tweaks_maximum_hp_npcs_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3011 | cd_tweaks_maximum_hp_npcs_nonjoinable | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3012 | cd_tweaks_maximum_hp_npcs_joinable | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3020 | cd_tweaks_id_all_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3030 | cd_tweaks_easy_spell_learning_capped | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3031 | cd_tweaks_easy_spell_learning_no_cap | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3040 | cd_tweaks_bottomless_bags | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3050 | cd_tweaks_restoration_no_fatigue | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3060 | cd_tweaks_remove_you_must_gather | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3070 | cd_tweaks_store_rep_low_rep_discount | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3071 | cd_tweaks_store_rep_no_rep_effect_100 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3072 | cd_tweaks_store_rep_no_rep_effect_80 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3073 | cd_tweaks_store_rep_no_rep_effect_60 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3080 | cd_tweaks_increase_ammo_stacks_infinite | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3081 | cd_tweaks_increase_ammo_stacks_40 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3082 | cd_tweaks_increase_ammo_stacks_80 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3083 | cd_tweaks_increase_ammo_stacks_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3090 | cd_tweaks_increase_gem_stacks_infinite | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3091 | cd_tweaks_increase_gem_stacks_40 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3092 | cd_tweaks_increase_gem_stacks_80 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3093 | cd_tweaks_increase_gem_stacks_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3100 | cd_tweaks_increase_potion_stacks_infinite | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3101 | cd_tweaks_increase_potion_stacks_40 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3102 | cd_tweaks_increase_potion_stacks_80 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3103 | cd_tweaks_increase_potion_stacks_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3110 | cd_tweaks_increase_scroll_stacks_infinite | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3111 | cd_tweaks_increase_scroll_stacks_40 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3112 | cd_tweaks_increase_scroll_stacks_80 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3113 | cd_tweaks_increase_scroll_stacks_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3115 | cd_tweaks_increase_pelt_stacks_infnite | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3120 | cd_tweaks_happy_patch_never_angry | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3121 | cd_tweaks_happy_patch_angry_never_leave | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3122 | cd_tweaks_happy_patch_always_neutral | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3123 | cd_tweaks_npcs_never_fight | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3124 | cd_tweaks_stop_hd_aerie_romance | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3125 | cd_tweaks_happy_neutrals | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3130 | cd_tweaks_no_traps_or_locks | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3131 | cd_tweaks_no_trap_effects_or_locks | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3132 | cd_tweaks_no_trap_effects_alarms_or_locks | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3140 | cd_tweaks_faster_ch1_cutscenes_eou | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3141 | cd_tweaks_faster_ch1_cutscenes_nonsilly | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3160 | cd_tweaks_disable_malchor | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3170 | cd_tweaks_no_drow_avatars_in_underdark | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3175 | cd_tweaks_disable_romances | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3176 | cd_tweaks_change_romance_speed | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3183 | cd_tweaks_romance_cheats | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3190 | cd_tweaks_rest_anywhere | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3191 | cd_tweaks_rest_spawns_alter_nonhostile_disable | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3194 | cd_tweaks_rest_spawns_alter_hostile_disable | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3195 | cd_tweaks_rest_spawns_alter_hostile_50 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3196 | cd_tweaks_rest_spawns_alter_hostile_150 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3197 | cd_tweaks_rest_spawns_alter_hostile_200 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3198 | cd_tweaks_rest_spawns_alter_hostile_400 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3200 | cd_tweaks_sellable_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3205 | cd_tweaks_stores_buy_all_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3210 | cd_tweaks_minimum_stats | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3220 | cd_tweaks_sensible_entrance_points | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3230 | cd_tweaks_taerom_makes_multiple_ankheg_armor | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3240 | cd_tweaks_friendly_random_drops_reload | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3241 | cd_tweaks_friendly_random_drops_tokens | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3242 | cd_tweaks_friendly_random_drops_merchant | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3250 | cd_tweaks_orrick_stock | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3260 | cd_tweaks_recover_ammo_25 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3261 | cd_tweaks_recover_ammo_50 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3262 | cd_tweaks_recover_ammo_75 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3263 | cd_tweaks_recover_ammo_100 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3264 | cd_tweaks_recover_ammo_25_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3265 | cd_tweaks_recover_ammo_50_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3266 | cd_tweaks_recover_ammo_75_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3267 | cd_tweaks_recover_ammo_100_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3270 | cd_tweaks_recover_throwing_weapons_25 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3271 | cd_tweaks_recover_throwing_weapons_50 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3272 | cd_tweaks_recover_throwing_weapons_75 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3273 | cd_tweaks_recover_throwing_weapons_100 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3274 | cd_tweaks_recover_throwing_weapons_25_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3275 | cd_tweaks_recover_throwing_weapons_50_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3276 | cd_tweaks_recover_throwing_weapons_75_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3277 | cd_tweaks_recover_throwing_weapons_100_enemy_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3280 | cd_tweaks_universal_four_weapon_slots | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3290 | cd_tweaks_personalize_savename_opt1 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3291 | cd_tweaks_personalize_savename_opt2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3292 | cd_tweaks_personalize_savename_opt3 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3293 | cd_tweaks_personalize_savename_opt4 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3294 | cd_tweaks_personalize_savename_opt5 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3295 | cd_tweaks_personalize_savename_opt6 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3300 | cd_tweaks_death_cam | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3310 | cd_tweaks_new_game_disable_party_ai | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3320 | cd_tweaks_no_store_depreciation | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3330 | cd_tweaks_reduced_party_chunking | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3340 | cd_tweaks_noncombat_speed_increase_50 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3341 | cd_tweaks_noncombat_speed_increase_100 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3342 | cd_tweaks_noncombat_speed_increase_150 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3343 | cd_tweaks_noncombat_speed_casting_increase_50 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3344 | cd_tweaks_noncombat_speed_casting_increase_100 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3345 | cd_tweaks_noncombat_speed_casting_increase_150 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3346 | cd_tweaks_noncombat_casting_increase_only | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3347 | cd_tweaks_noncombat_casting_increase_custom | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3350 | cd_tweaks_create_interval_one_save_15 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3351 | cd_tweaks_create_interval_one_save_30 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3352 | cd_tweaks_create_interval_one_save_60 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3353 | cd_tweaks_create_interval_one_save_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3354 | cd_tweaks_create_interval_four_saves_15 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3355 | cd_tweaks_create_interval_four_saves_30 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3356 | cd_tweaks_create_interval_four_saves_60 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3357 | cd_tweaks_create_interval_four_saves_120 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3358 | cd_tweaks_create_interval_save_custom | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3360 | cd_tweaks_reset_undersigil_fow | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3370 | cd_tweaks_chapter_saves_in_pstee | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3380 | cd_tweaks_sensible_regeneration_when_traveling | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3390 | cd_tweaks_automatic_ranger_tracking | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3400 | cd_tweaks_restored_loading_hints | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3410 | cd_tweaks_casting_warnings_mp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3411 | cd_tweaks_casting_warnings_mpi | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3412 | cd_tweaks_casting_warnings_all | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3490 | cd_tweaks_better_soa_start_300k | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3491 | cd_tweaks_better_soa_start_500k | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3492 | cd_tweaks_better_soa_start_300k_all_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3493 | cd_tweaks_better_soa_start_500k_all_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3494 | cd_tweaks_better_soa_start_tomes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3495 | cd_tweaks_better_soa_start_pantaloons | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3496 | cd_tweaks_better_soa_start_drizzt | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3497 | cd_tweaks_better_soa_start_balduran | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 3420 | cd_tweaks_more_sensible_cowled_wizards | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3430 | cd_tweaks_more_stoneskin_feedback | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3440 | cd_tweaks_extra_dispel_feedback | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3450 | cd_tweaks_more_sensible_fireshield | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3460 | cd_tweaks_more_sensible_blade_barrier | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3470 | cd_tweaks_dynamic_fps_change | 0 | unknown |  |
| setup-cdtweaks.tp2 | 3480 | cd_tweaks_more_sensible_morentherene | 0 | unknown |  |
| setup-cdtweaks.tp2 | 4000 | cd_tweaks_adjust_evil_npc_reactions | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4010 | cd_tweaks_improved_fate_spirit_summoning | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4020 | cd_tweaks_tob_style_npcs | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4025 | cd_tweaks_allow_npc_pairs_to_separate | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4030 | cd_tweaks_consistent_stats_edwin_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4031 | cd_tweaks_consistent_stats_edwin_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4040 | cd_tweaks_consistent_stats_jaheira_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4041 | cd_tweaks_consistent_stats_jaheira_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4050 | cd_tweaks_ng_jaheira | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4060 | cd_tweaks_consistent_stats_minsc_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4061 | cd_tweaks_consistent_stats_minsc_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4070 | cd_tweaks_consistent_stats_viconia_bg | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4071 | cd_tweaks_consistent_stats_viconia_bg2 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4080 | cd_tweaks_make_khalid_fighter_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4090 | cd_tweaks_make_montaron_assassin | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4100 | cd_tweaks_ne_korgan | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4110 | cd_tweaks_kagain_legal_con | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4120 | cd_tweaks_coran_legal_dex | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4130 | cd_tweaks_make_xan_generic_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4131 | cd_tweaks_make_dynaheir_generic_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4132 | cd_tweaks_make_xzar_generic_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4133 | cd_tweaks_make_edwin_generic_mage | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4150 | cd_tweaks_move_boo_into_inventory | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4160 | cd_tweaks_yeslick_can_use_axes | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4170 | cd_tweaks_protect_sharteel | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4140 | cd_tweaks_disable_joinable_ai_scripts | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4180 | cd_tweaks_removable_npc_items | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4190 | cd_tweaks_color_npc_names_pc_none | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4191 | cd_tweaks_color_npc_names_pc_gray | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4192 | cd_tweaks_color_npc_names_pc_brown | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4193 | cd_tweaks_color_npc_names_pc_red | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4194 | cd_tweaks_color_npc_names_pc_purple | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4195 | cd_tweaks_color_npc_names_pc_blue | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4196 | cd_tweaks_color_npc_names_pc_green | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4197 | cd_tweaks_color_npc_names_pc_yellow | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4198 | cd_tweaks_color_npc_names_pc_orange | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4200 | cd_tweaks_dorns_sword | 0 | unknown |  |
| setup-cdtweaks.tp2 | 4210 | cd_tweaks_nalia_thief_level_5 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4211 | cd_tweaks_nalia_thief_level_6 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4212 | cd_tweaks_nalia_thief_level_7 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4213 | cd_tweaks_nalia_thief_level_8 | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4220 | cd_tweaks_neera_delay_till_mines | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4221 | cd_tweaks_neera_delay_till_5k_xp | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 4230 | cd_tweaks_yoshimo_better_trapsetting | 0 | no_lua |  |
| setup-cdtweaks.tp2 | 6000 | cd_tweaks_nwn_disarm | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6010 | cd_tweaks_nwn_knockdown | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6020 | cd_tweaks_nwn_spellcraft_counterspell | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6030 | cd_tweaks_nwn_spontaneous_cast | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6040 | cd_tweaks_weapon_finesse | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6050 | cd_tweaks_dual_wield | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6060 | cd_tweaks_nwn-style_armor_vs_dex | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6070 | cd_tweaks_defensive_roll | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6080 | cd_tweaks_divine_grace_dark_blessing | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6090 | cd_tweaks_good_aim | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6100 | cd_tweaks_cleave | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6110 | cd_tweaks_sneakatt_blackguard | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6120 | cd_tweaks_fearless | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6130 | cd_tweaks_poison_save | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6140 | cd_tweaks_planar_turning | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6150 | cd_tweaks_nwn_circle_kick | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6160 | cd_tweaks_nwn_barbarian_rage | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6170 | cd_tweaks_nwn_revised_archer | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6180 | cd_tweaks_nwn_blind_fight | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6190 | cd_tweaks_nwn_dirty_fighting | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6200 | cd_tweaks_nwn_overwhelming_devastating_critical | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6210 | cd_tweaks_nwn_self_concealment | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6220 | cd_tweaks_nwn_parry | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6230 | cd_tweaks_nwn_armored_caster | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6240 | cd_tweaks_nwn_trackless_step | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6250 | cd_tweaks_nwn_nature_sense | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6260 | cd_tweaks_nwn_uncanny_dodge | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6270 | cd_tweaks_nwn_sneakatt_rogue | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6280 | cd_tweaks_nwn_evasion | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6290 | cd_tweaks_nwn_spell_penetration | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6300 | cd_tweaks_nwn_smite_evil_good | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6310 | cd_tweaks_nwn_woodland_stride | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6320 | cd_tweaks_nwn_bane_of_enemies | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6330 | cd_tweaks_nwn_cantrips | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6340 | cd_tweaks_nwn_animal_companion | 0 | unknown |  |
| setup-cdtweaks.tp2 | 6350 | cd_tweaks_nwn_opportunist | 0 | unknown |  |

## wares-of-the-planes

**Missing EEex names:** none

**Unknown fields:** none

**Engine-object methods called:** none

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 0 partial, 0 unsupported, 3 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| A7-WaresOfThePlanes.tp2 | 0 | A7-WARES_OF_THE_PLANES-MAIN | 0 | unknown |  |
| A7-WaresOfThePlanes.tp2 | 100 | A7-WARES_OF_THE_PLANES-IDENTIFY_ALL | 0 | unknown |  |
| A7-WaresOfThePlanes.tp2 | 200 | A7-WARES_OF_THE_PLANES-ALTERNATE_PORTRAIT-1 | 0 | unknown |  |

## warlock

**Missing EEex names:** `EEex_Utility_MapItrValues`(4)

**Unknown fields:** `m_abilityId`(4), `m_itemType`(4)

**Engine-object methods called:** `getKnownMageSpellsItr`(4), `getKnownInnateSpellsItr`(4), `getValidSpellsWithAbilityItr`(4), `getRowColumnsItr`(4), `getActiveStats`(1)

**Hard usage:** none

**Declares IEX support:** no

**Components:** 0 compatible, 1 partial, 0 unsupported, 0 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 0 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| Artisans_Warlock.TP2 | 0 |  | 1 | partial | EEex_Utility_MapItrValues, m_abilityId, m_itemType |

## SadoEE

**Missing EEex names:** `EEex_ReadU32`(72), `EEex_ReadU8`(58), `EEex_Write32`(54), `EEex_WriteU8`(45), `EEex_WriteU32`(41), `EEex_ReadU16`(33), `EEex_Action_ExecuteResponseStringOnAIBaseInstantly`(31), `EEex_LuaTrigger`(29), `EEex_Action_QueueResponseStringOnAIBase`(26), `EEex_LuaAction`(25), `EEex_Read32`(20), `EEex_LuaObject`(17), `EEex_Malloc`(16), `EEex_Resource_GetAt2DALabels`(16), `EEex_DisableCodeProtection`(15), `EEex_EnableCodeProtection`(15), `EEex_JITNear`(11), `EEex_HookIntegrityWatchdogRegister`(7), `EEex_Label`(6), `EEex_AllocNear`(5), `EEex_FlattenTable`(5), `EEex_GenLuaCall`(5), `EEex_Trigger_ParseConditionalString`(4), `EEex_Trigger_EvalScriptFileConditionalAsAIBase`(4), `EEex_Menu_InjectTemplateInstance`(4), `EEex_Resource_Free2DA`(4), `EEex_Write64`(3), `EEex_ReadU64`(3), `EEex_Sprite_GetKnownMageSpellsIterator`(3), `EEex_RunWithStackManager`(3), `EEex_Menu_IsCursorWithin`(3), `EEex_ExposeToLua`(2), `EEex_ReadLString`(2), `EEex_NewUD`(2), `EEex_WriteU16`(2), `EEex_ReadS16`(2), `EEex_Read16`(2), `EEex_HookBeforeCallWithLabels`(2), `EEex_LuaCallReturnType`(2), `EEex_Options_Private_FindItemByText`(2), `EEex_Area_GetAllOfTypeStringInRange`(1), `EEex_Free`(1), `EEex_Write16`(1), `EEex_Sprite_GetKnownPriestSpellsIterator`(1), `EEex_WritePtr`(1), `EEex_Menu_GetArea`(1), `EEex_ReadPtr`(1), `EEex_Object_AddToArea`(1), `EEex_HookIntegrityWatchdog_IgnoreStackSizes`(1), `EEex_Options_Set`(1), `EEex_Sprite_DisplayTextRef`(1), `EEex_Options_`(1), `EEex_Menu_`(1), `EEex_Menu_Find`(1), `EEex_Menu_GetItemFunction`(1), `EEex_Menu_SetItemFunction`(1), `EEex_Options_Close`(1)

**Unknown fields:** none

**Engine-object methods called:** `get`(168), `set`(25), `getName`(13), `getAtPoint`(5), `getUD`(5), `valuable`(3), `marks`(1), `collected`(1), `factorized`(1), `tighter`(1), `getAtLabels`(1), `onChar`(1), `done`(1), `search`(1), `unleash`(1), `dead`(1), `lockpicking`(1), `hand`(1)

**Hard usage:** `EEex_Write32`(54), `EEex_WriteU8`(45), `EEex_WriteU32`(41), `EEex_Malloc`(16), `EEex_DisableCodeProtection`(15), `EEex_EnableCodeProtection`(15), `EEex_JITNear`(11), `EEex_HookIntegrityWatchdogRegister`(7), `EEex_Label`(6), `EEex_AllocNear`(5), `EEex_FlattenTable`(5), `EEex_GenLuaCall`(5), `EEex_Write64`(3), `EEex_WriteU16`(2), `EEex_HookBeforeCallWithLabels`(2), `EEex_Write16`(1), `EEex_WritePtr`(1), `EEex_HookIntegrityWatchdog_IgnoreStackSizes`(1)

**Declares IEX support:** no

**Components:** 1 compatible, 7 partial, 20 unsupported, 1 unknown (Lua may come from a folder or %variable% copy: use the mod-level result), 9 no_lua (= compatible)

| tp2 | # | label | files | verdict | why |
|---|---|---|---|---|---|
| SadoEE.tp2 | 60 | SADOEE-SWITCHABLE-ALL | 20 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 61 | SADOEE-SWITCHABLE-NONE | 0 | no_lua |  |
| SadoEE.tp2 | 62 | SADOEE-SWITCHABLE-CHOOSE | 0 | no_lua |  |
| SadoEE.tp2 | 0 | SADOEE-MAIN | 2 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_Label |
| SadoEE.tp2 | 1 | SADOEE-SORTED-LOOT | 2 | unsupported | EEex_WritePtr |
| SadoEE.tp2 | 2 | SADOEE-MAIN-BG2-LOOK | 2 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_Label |
| SadoEE.tp2 | 3 | SADOEE-MAIN-BG1-LOOK-ON-BG2 | 2 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_Label |
| SadoEE.tp2 | 4 | SADOEE-MAIN-BG2-LOOK-ON-BGEE | 2 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_Label |
| SadoEE.tp2 | 5 | SADOEE-OPT-WEIGHTLESS | 0 | no_lua |  |
| SadoEE.tp2 | 6 | SADOEE-OPT-KEEPGOLD | 0 | no_lua |  |
| SadoEE.tp2 | 7 | SADOEE-OPT-LOSESTASH | 0 | no_lua |  |
| SadoEE.tp2 | 10 | SADOEE-CAMP | 4 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 11 | SADOEE-CAMP-MERCHANT | 4 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 12 | SADOEE-CAMP-SCHOLAR | 1 | unsupported | EEex_WriteU32, EEex_WriteU8 |
| SadoEE.tp2 | 13 | SADOEE-CAMP-WAITING | 4 | partial | EEex_Action_QueueResponseStringOnAIBase, EEex_LuaAction, EEex_LuaTrigger, EEex_Menu_ |
| SadoEE.tp2 | 14 | SADOEE-CAMP-WITHERS | 3 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_JITNear |
| SadoEE.tp2 | 15 | SADOEE-CAMP-WITHERS-RECRUIT | 2 | unsupported | EEex_WriteU32, EEex_WriteU8 |
| SadoEE.tp2 | 16 | SADOEE-QUEST-CHRONICLE | 5 | partial | EEex_LuaAction |
| SadoEE.tp2 | 17 | SADOEE-CAMP-NECROMANCER | 3 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Action_QueueResponseStringOnAIBase, EEex_LuaObject, EEex_LuaTrigger |
| SadoEE.tp2 | 50 | SADOEE-CAMP-PRIEST-PRICES-75 | 0 | no_lua |  |
| SadoEE.tp2 | 51 | SADOEE-CAMP-PRIEST-PRICES-50 | 0 | no_lua |  |
| SadoEE.tp2 | 52 | SADOEE-CAMP-PRIEST-PRICES-25 | 0 | no_lua |  |
| SadoEE.tp2 | 53 | SADOEE-CAMP-PRIEST-PRICES-0 | 0 | no_lua |  |
| SadoEE.tp2 | 20 | SADOEE-QOL-PASSIVE-TRAPS | 4 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Menu_, EEex_Menu_Find, EEex_Menu_GetItemFunction |
| SadoEE.tp2 | 21 | SADOEE-QOL-VALUABLE-CONTAINERS | 4 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_HookBeforeCallWithLabels, EEex_HookIntegrityWatchdogRegister |
| SadoEE.tp2 | 22 | SADOEE-QOL-AUTO-DISARM | 4 | partial | EEex_Action_ExecuteResponseStringOnAIBaseInstantly, EEex_Action_QueueResponseStringOnAIBase, EEex_LuaObject, EEex_Menu_ |
| SadoEE.tp2 | 23 | SADOEE-QOL-FPS-COUNTER | 4 | partial | EEex_Menu_, EEex_Menu_Find, EEex_Menu_GetItemFunction, EEex_Menu_InjectTemplateInstance |
| SadoEE.tp2 | 24 | SADOEE-QOL-ENDLESS-AMMO | 6 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 25 | SADOEE-QOL-FOOTPRINT-ONE | 2 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_JITNear, EEex_WriteU8 |
| SadoEE.tp2 | 26 | SADOEE-QOL-FOOTPRINT-NONE | 2 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_JITNear, EEex_WriteU8 |
| SadoEE.tp2 | 27 | SADOEE-QOL-LASTING-MODES | 4 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 28 | SADOEE-QOL-ATTACK-MOVE | 5 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 29 | SADOEE-QOL-MOUSE-BUTTONS | 3 | partial | EEex_Menu_, EEex_Menu_Find, EEex_Menu_GetItemFunction, EEex_Menu_InjectTemplateInstance |
| SadoEE.tp2 | 30 | SADOEE-QOL-KEEP-GEAR | 2 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_JITNear, EEex_WriteU8 |
| SadoEE.tp2 | 31 | SADOEE-QOL-CHESTS-IN-GROUND-BAR | 4 | unsupported | EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_FlattenTable, EEex_GenLuaCall |
| SadoEE.tp2 | 32 | SADOEE-QOL-AUTO-ROLLER | 1 | compatible |  |
| SadoEE.tp2 | 33 | SADOEE-QOL-PAIRS-SEPARATE | 0 | unknown |  |
| SadoEE.tp2 | 40 | SADOEE-PARTY-BIG | 6 | unsupported | EEex_AllocNear, EEex_DisableCodeProtection, EEex_EnableCodeProtection, EEex_Malloc |
