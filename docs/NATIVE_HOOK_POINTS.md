# Native hook points

IEX has no assembler, no JIT and no code-injection engine, and will not get one. Mods written for EEex's x64 asm
API (`EEex_HookBeforeCallWithLabels`, `EEex_JITAt`...) patch the engine with Windows machine code; IEX gives them the
same behaviour from C++ instead, on Windows and Linux. This page is the catalogue of those patches and the design of
the shared implementation: one **hook point** per engine moment, implemented once, used by every mod that needs it.

Sources: the mods' own code only (docs/CLEAN_ROOM.md). The per-mod catalogues
(`IEX-data/inventory/asm_catalogue/cat_*.json`) list every patch request with its address, hook kind, the Lua
callback its `EEex_GenLuaCall` names, the callback's arguments and result, and what the patch does, as the mod's
code and comments say. `tools/compat/asm_sites.py` maps each address to its engine function (Windows function
ranges from Ghidra, Windows/Linux symbol matches, `verified_*.json`), assigns its hook point and writes
`IEX-data/inventory/asm_sites.json`, the router table `lua/IEX_AsmSites.lua` and the tables at the end of this page:

    python tools/compat/asm_sites.py --lua lua/IEX_AsmSites.lua --md docs/NATIVE_HOOK_POINTS.md

## Library (src/core/hook_points.h)

- **Registry.** `hp::Point` lists every point once; `kPoints` gives its Lua name, category, kind and result rule.
  An engine module implements its points and registers them: `SetInstaller(point, install, available)` for points
  installed on demand (the first listener), `MarkInstalled(point, ok, sites)` for points its module installs at
  startup. Every installer checks the bytes of its sites first and changes nothing when a site holds foreign code.
- **Kinds.** *listener*: Lua listeners per call. *switch*: on / off with arguments, no Lua per call (SadoEE's lasting
  modes, small footprint...). *feature*: a whole behaviour installed at startup by its module and only reported here
  (party vision, Pathfinding Redux allied pass-through, the Empty Container module hook).
- **Calls.** A point's C++ hook calls Lua only while the point is active (installed and listened to):
  `IEX_NativeHook_Fire(point, ...)` with typed arguments (engine objects as userdata, numbers as integers), through
  `hp::FireVoid / FireBool / FireValue`.
- **Results.** *none*: every listener runs. *anyTrue*: every listener runs, one true is the point's yes (keep the
  ammo, cancel the attack, the button is handled). *value*: the engine value is the last argument; each listener may
  return a number (nil keeps it) that the next listener receives; the last number replaces the engine value.
- **Lua side** (lua/IEX_NativeHooks.lua): `IEX_NativeHook_AddListener(point, fn)`, `IEX_NativeHook_RemoveListener`,
  `IEX_NativeHook_Enable(point [, a, b])` (switches), `IEX_NativeHook_Install / Installed / Sites`,
  `IEX_NativeHook_Points()` (every point with its state), `IEX_Features.nativeHooks[point]` (sites present on this
  build). The per-point listener signatures are at the top of that file.
- Implementations: combat and UI points in `native_stick.cpp` (call-site and register-context call-site hooks:
  `callsite_hook.h`, `reg_hook.h`), SadoEE behaviours in `native_hooks.cpp` / `native_hooks_sado.cpp` (call sites
  plus small fixed per-site thunks of literal bytes), features in `vision.cpp`, `pathfinding.cpp`, `modules.cpp`.

## Router (lua/IEX_HookRequests.lua)

Every address-taking `EEex_Hook*` kind and `EEex_JITAt` is an inert stand-in: nothing is assembled, written or run.
`EEex_GenLuaCall` returns a text that only carries the function name; that name is the one thing read from the asm.

1. The request's address (a 2.7.3 Windows x64 address; on Windows an address computed from another image base is
   brought back to 0x140000000) is looked up in `IEX_AsmSites`, or in `IEX_AsmLabelSites` for sites given as
   `EEex_Label(name) + offset`.
2. A site whose point IEX implements carries a **binding**: the point, how the mod's callback gets its arguments
   from the point's (`idN` object id, `argN` as is, `ptrN` address, `objN` engine object), how its result is read
   (`number`: a non-number counts 0 as EEex's GenLuaCall reads it, an error or a missing function keeps the engine
   value; `boolean`; `none`), the callback's default name, or `switch` (a pure asm patch: the point is turned on),
   or `bridge` (the point needs data the request does not carry; a bridge in IEX_NativeHooks.lua binds it).
3. The router adds a listener that calls the mod's global by name at each call (so a mod may redefine it later).
4. Unknown sites, and known sites whose point is not implemented, are logged once
   (`[hooks] not supported natively: <mod> <address> (<kind>, <callback>): <why>`) and written to
   `IEX/missing_api.txt`.

`EEex_JITNear` and `EEex_JITNearAsLuaFunction` stay undefined (the missing-API trap returns nil): what they return is
code a mod would jump to or call, and IEX has none to give. Mods that build their own Windows stubs or write raw
jumps (SadoEE, chriz's DLL-backed XP bank) cannot be routed by address; their behaviours are reached by a bridge
that connects the mod's Lua side to the same points (SadoEE bridge, lua/IEX_NativeHooks.lua).

## Migration status

- **StickLuaFunctions v0.11**: all 16 implemented points go through the router (before: an address table in
  native_stick.cpp calling the named globals). Behaviour unchanged: tools/stick/run.ps1 and run_linux.sh give the
  same listener calls and results per phase as before (forced hits all hit, forced misses all miss, cancel, save
  schools), `IEX_Features.stickHooks = 16` on both platforms.
- **SadoEE**: its two `EEex_HookBeforeCallWithLabels` requests reach the router (endless ammo binds
  `SQAmmo_Hook_Keep` to `keepAmmo`; the valuable-containers outline is left to its bridge, which supplies the color
  and the marker). Its other patches (JIT stubs, raw writes) stay on the SadoEE bridge, now on the registry. Same 11
  components native on Linux and Windows as before.
- **Pathfinding Redux**: covered as one feature (`alliedPassThrough`): IEX stops the mod's own loader and runs its
  movement policy natively; its sites are in the table so a request that still arrives (IEX option off) is reported
  as covered by that feature. Attack spacing, the route-preference planner and gentle settle are not implemented.

## Not done / limits

- Not implemented yet (status `todo` below): Stick backstab checks and proficiency maximum, the EEex Lua hook
  `EEex_Opcode_Hook_OnAfterSwingCheckedOp248` that Stick wraps, SadoEE's big party (#40: 536 raw patches of the party
  array and MAX_CHARACTERS), Pathfinding Redux attack spacing / route preference / settle, and all chriz patches
  (bard spell table, kit proficiency column, Time Stop clocks, extra race strings, layered animation weapon,
  unidentified icons, XP bank and dual-class progression through the mods' own DLLs).
- `n/a`: Olvyn's `EEex_Pro.lua` (legacy 32-bit EEex asm, cannot run on x64 2.7.3), bgee-graphics-enhanced's own DLL
  detours (not an EEex request), SadoEE's build probe (a byte read, no patch), Stick's HitStrMod (never registered).
- Engine-function names come from IEX's symbol matching; a few mid-function sites in unmatched functions keep
  Ghidra's `FUN_` name, and matches marked low confidence in the symbol file can name a sibling function.

## Tables

<!-- GENERATED by tools/compat/asm_sites.py: begin -->

Corpus: 839 patch requests (819 shipped) from 8 mods, 738 distinct Windows addresses; 791 mapped to their engine function, 650 of those to the matching Linux function.

| status | points | requests |
|---|---|---|
| native | 31 | 128 |
| feature | 3 | 38 |
| todo | 15 | 637 |
| n/a | 3 | 10 |

### Hook points (most requested first)

| point | category | status | requests | addresses | mods | engine function (Windows rva / Linux) | moment |
|---|---|---|---|---|---|---|---|
| `bigParty` | party | todo | 536 | 535 | SadoEE | CAIObjectType::Decode (0x11bba0 / 0x51a840); FUN_140138170 (0x138170 / -); CBaldurMessage::BroadcastUpdateCharacterSlot (0x1383a0 / 0x14eb40) +251 | party array / MAX_CHARACTERS past 6 members (SadoEE #40) |
| `dualClassProgression` | xp | todo | 30 | 30 | chriz-bg-modpack | CScreenCreateChar::ResetLevelUpPanel (0x2bf8e0 / 0x3499d0); FUN_1402b6f70 (0x2b6f70 / -); CScreenCreateChar::CancelLevelUp (0x2b1e10 / 0x34d900) +7 | dual-class progression detours into the mod DLLs |
| `callStub` | engine | native | 20 | 19 | SadoEE | _ZN17CScreenCreateChar15RemoveAbilitiesEP11CGameSpriteii (0x2ac8d0 / -); CInfGame::SwapItemPersonal (0x28ff20 / -); CInfGame::AddItemToStore (0x26d680 / 0x2e4350) +16 | Lua-callable engine functions a mod builds Windows stubs for |
| `alliedPassThrough` | path | feature | 19 | 19 | pathfinding-redux | SearchThreadMain (0x24d5e0 / 0x2b8860); CGameSprite::AIUpdateWalk (0x3467c0 / 0x47c8e0); FUN_140215750 (0x215750 / -) +5 | Pathfinding Redux movement policy: allies pass through allies (search map, walk step, bump, route cost, background search snapshot) |
| `partyVision` | party | feature | 18 | 17 | SadoEE | CVisibilityMap::AddCharacter (0x255b40 / 0x2c3c70); CVisibilityMap::RemoveCharacter (0x256aa0 / 0x2c1bc0); _ZN14CVisibilityMap6UpDateERK6CPointS2_iPhhPih (0x257330 / 0x2c3f60) +8 | fog of war for more than the engine viewer cap |
| `lastingModes` | modal | native | 16 | 16 | SadoEE | CInfButtonArray::OnLButtonPressed (0x2635e0 / 0x2d4580); CInfButtonArray::OnRButtonPressed (0x264d90 / 0x2d7180); CScreenWorld::OnKeyDown (0x2f3b10 / 0x39ed00) +3 | modal states not cancelled by actions / buttons / moving; no per-round feedback |
| `backstabCheck` | attack | todo | 15 | 5 | stick-lua-functions | CGameSprite::Damage (0x390230 / 0x433290) | CGameSprite::Damage backstab: invisibility / position / immunity checks + decision |
| `xpBank` | xp | todo | 14 | 12 | chriz-bg-modpack | CGameSprite::Copy (0x351240 / 0x4b5bd0); CGameSprite::Marshal (0x360ff0 / 0x472000); CInfGame::CharacterExport (0x2703d0 / 0x2fc740) +9 | XP bank: identity, award, writer, cap, reset, party (mod DLLs) |
| `pathPreference` | path | todo | 13 | 11 | pathfinding-redux | CPathSearch::FindPath (0x2258b0 / 0x276110); CGameSprite::SetTarget (0x375cb0 / 0x47b8d0); FUN_140374cd0 (0x374cd0 / -) +2 | Pathfinding Redux route preference planner (optional install) |
| `stealthReveals` | modal | native | 11 | 11 | SadoEE | CGameSprite::SetCurrAction (0x3b3740 / 0x454260); CGameSprite::CheckModal (0x38cf00 / 0x42d630); _ZN11CGameSprite12ForceVisibleEv (0x39c510 / 0x41fd10) +6 | stealth reveal rules |
| `timeStopClock` | effects | todo | 8 | 8 | chriz-bg-rebalance | CGameSprite::ProcessEffectList (0x3ab9d0 / 0x427370); CPersistantEffectListRegenerated::AIUpdate (0x226500 / 0x276bb0); FUN_1401bec50 (0x1bec50 / -) +8 | effect timers under Time Stop / Haste (chriz CBRTC gates) |
| `hideInSight` | stealth | native | 7 | 1 | stick-lua-functions | CGameSprite::Hide (0x39dbb0 / 0x444d10) | CGameSprite::Hide: hiding while seen |
| `hitRoll` | attack | native | 6 | 1 | stick-lua-functions | CGameSprite::Hit (0x39e090 / 0x431800) | CGameSprite::Hit: d20 attack roll (0..19) |
| `toHitTotal` | attack | native | 6 | 1 | stick-lua-functions | CGameSprite::Hit (0x39e090 / 0x431800) | CGameSprite::Hit: right-hand to-hit total, final |
| `damageRoll` | attack | native | 6 | 1 | stick-lua-functions | CGameSprite::Damage (0x390230 / 0x433290) | CGameSprite::Damage: weapon damage roll + bonus |
| `actionButtonL` | ui | native | 6 | 1 | stick-lua-functions | CInfButtonArray::OnLButtonPressed (0x2635e0 / 0x2d4580) | CInfButtonArray::OnLButtonPressed(index) |
| `casterSchoolSpell` | save | native | 6 | 1 | stick-lua-functions | CSpell::GetAbilityEffect (0x24ee30 / 0x2b9be0) | CSpell::GetAbilityEffect: caster school (save penalty) |
| `casterSchoolItem` | save | native | 6 | 1 | stick-lua-functions | CItem::GetAbilityEffect (0x1fb410 / 0x2329d0) | CItem::GetAbilityEffect: caster school (save penalty) |
| `afterSwingOp248` | swing | todo | 6 | 0 | stick-lua-functions | - | EEex Lua hook EEex_Opcode_Hook_OnAfterSwingCheckedOp248 (Lua override, no patch) |
| `pathAttackSpacing` | path | todo | 5 | 5 | pathfinding-redux | FUN_140388d40 (0x388d40 / -); FUN_140389710 (0x389710 / -) | Pathfinding Redux attack spacing: approach slots in Attack / AttackReevaluate |
| `targetSchool` | save | native | 5 | 1 | stick-lua-functions | CGameEffect::CheckSave (0x1cd330 / 0x1d2cb0) | CGameEffect::CheckSave: target school (save bonus) |
| `unidentifiedIcon` | item | todo | 4 | 0 | chriz-bg-modpack | - | CItem icon / ground icon / PushToLua resref of an unidentified item |
| `modDll` | legacy | n/a | 4 | 0 | bgee-graphics-enhanced | - | the mod's own DLL detours (MinHook), not an EEex request |
| `legacyX86` | legacy | n/a | 3 | 0 | olvynspells | - | legacy 32-bit EEex patch (2.5 x86 asm): cannot run on x64 2.7.3 |
| `buildProbe` | engine | n/a | 3 | 3 | SadoEE | CGameSprite::SetModalState (0x374940 / 0x47ed20); CGameArea::OnActionButtonClickGround (0x1868e0 / 0x186d70); CInfGame::AddPartyGold (0x26dac0 / 0x2f0780) | build detection by reading code bytes (no patch) |
| `smallFootprint` | search | native | 3 | 3 | SadoEE | CSearchBitmap::AddObject (0x24c420 / 0x2b68a0); CSearchBitmap::RemoveObject (0x24d090 / 0x2b6a50); CSearchBitmap::SnapshotRemoveObject (0x24e900 / 0x2b7370) | CSearchBitmap Add/RemoveObject: bumpable creature footprint |
| `attackIndex` | swing | native | 3 | 1 | stick-lua-functions | _ZN11CGameSprite5SwingEPS_ (0x3b8610 / 0x44d800) | CGameSprite::Swing: attack index of the attack frame |
| `attackCancel` | swing | native | 2 | 1 | stick-lua-functions | _ZN11CGameSprite5SwingEPS_ (0x3b8610 / 0x44d800) | CGameSprite::Swing: cancel the attack frame |
| `critThreshold` | attack | native | 2 | 1 | stick-lua-functions | CGameSprite::Hit (0x39e090 / 0x431800) | CGameSprite::Hit: critical threshold (CDerivedStats::GetCriticalValue) |
| `critBlocked` | attack | native | 2 | 1 | stick-lua-functions | CGameSprite::Hit (0x39e090 / 0x431800) | CGameSprite::Hit: helmet-stopped critical keeps flag 2 |
| `critMultiplier` | attack | native | 2 | 1 | stick-lua-functions | CGameSprite::Damage (0x390230 / 0x433290) | CGameSprite::Damage: critical multiplier |
| `attackResult` | attack | native | 2 | 1 | stick-lua-functions | CGameSprite::Hit (0x39e090 / 0x431800) | CGameSprite::Hit: hit / miss |
| `actionButtonR` | ui | native | 2 | 1 | stick-lua-functions | CInfButtonArray::OnRButtonPressed (0x264d90 / 0x2d7180) | CInfButtonArray::OnRButtonPressed(index) |
| `classDone` | chargen | native | 2 | 1 | stick-lua-functions | CScreenCreateChar::OnDoneButtonClick (0x2b9020 / 0x3600d0) | CScreenCreateChar: class step completed |
| `profMaxUI` | chargen | native | 2 | 1 | stick-lua-functions | CScreenCreateChar::UpdateProficienciesPanel (0x2c7800 / 0x33dde0) | UpdateProficienciesPanel: maximum shown (the tables max field) |
| `profMax` | chargen | native | 2 | 1 | stick-lua-functions | CScreenCreateChar::OnProficiencyPlusMinusButtonClick (0x2be0a0 / 0x347f30) | OnProficiencyPlusMinusButtonClick: maximum a + may reach (GetClassProficiency) |
| `bardSpellTable` | rules | todo | 1 | 1 | chriz-bg-rebalance | CRuleTables::GetMaxMemorizedSpellsMage (0x241f30 / 0x297b20) | bard spell progression table chosen per kit (CRuleTables) |
| `kitProfColumn` | rules | todo | 1 | 1 | chriz-bg-rebalance | CRuleTables::GetProficiencyClassIndex (0x2456c0 / 0x291c80) | CRuleTables::GetProficiencyClassIndex: multiclass kit weapon column |
| `raceString` | rules | todo | 1 | 1 | chriz-playable-races | CRuleTables::GetRaceString (0x246440 / 0x291320) | CRuleTables::GetRaceString: extra races |
| `layeredAnimResRef` | anim | todo | 1 | 1 | chriz-playable-races | CGameAnimationTypeAmbient::GetAnimationResRef (0x326a10 / 0x3d6210) | CGameAnimationTypeMonsterLayered::GetAnimationResRef: weapon shown |
| `pathSettle` | path | todo | 1 | 1 | pathfinding-redux | FUN_1402a7440 (0x2a7440 / -) | Pathfinding Redux gentle settle (CMessageStopActions from Lua) |
| `keepAmmo` | swing | native | 1 | 1 | SadoEE | _ZN11CGameSprite5SwingEPS_ (0x3b8610 / 0x44d800) | CGameSprite::Swing: CItem::SetUsageCount after a shot |
| `deathDrop` | world | native | 1 | 1 | SadoEE | CGameEffectDeath::ApplyEffect (0x1ae9b0 / 0x1f0020) | death effect: inventory dropped |
| `groundMoveClick` | world | native | 1 | 1 | SadoEE | CGameArea::OnActionButtonClickGround (0x1868e0 / 0x186d70) | CGameArea::OnActionButtonClickGround: move click |
| `groundContainer` | world | native | 1 | 1 | SadoEE | CGameSprite::UpdateVisibleGroundItems (0x3864c0 / 0x46ddd0) | CGameSprite::UpdateVisibleGroundItems: container in range |
| `containerMarker` | world | native | 1 | 0 | SadoEE | - | CGameContainer::Render: permanent outline color by marker |
| `emptyContainerOutline` | world | feature | 1 | 0 | SadoEE | - | EEex B3EmptyContainer module hook (highlight outline) |
| `findTrapsButton` | modal | native | 1 | 1 | SadoEE | CInfButtonArray::OnLButtonPressed (0x2635e0 / 0x2d4580) | Find Traps action bar button |
| `campMarker` | worldmap | native | 1 | 1 | SadoEE | CScreenWorldMap::DrawMap (0x2fe2d0 / 0x3aefd0) | world map: party marker |
| `campSameArea` | worldmap | native | 1 | 1 | SadoEE | CScreenWorldMap::OnAreaMouseClick (0x301d50 / 0x3b3a40) | world map: current area clicked |
| `respecGear` | chargen | native | 1 | 1 | SadoEE | CScreenCreateChar::CompleteCharacterSkills (0x2b37e0 / 0x3426b0) | CompleteCharacterSkills: starting gold / weapon |
| `backstabSuccess` | attack | todo | 1 | 1 | stick-lua-functions | CGameSprite::Damage (0x390230 / 0x433290) | CGameSprite::Damage backstab applied |

### Mods

| mod | points | covered | missing points |
|---|---|---|---|
| SadoEE | 17 | no | `bigParty` |
| bgee-graphics-enhanced | 1 | yes | - |
| chriz-bg-modpack | 3 | no | `dualClassProgression`, `unidentifiedIcon`, `xpBank` |
| chriz-bg-rebalance | 3 | no | `bardSpellTable`, `kitProfColumn`, `timeStopClock` |
| chriz-playable-races | 2 | no | `layeredAnimResRef`, `raceString` |
| olvynspells | 1 | yes | - |
| pathfinding-redux | 4 | no | `pathAttackSpacing`, `pathPreference`, `pathSettle` |
| stick-lua-functions | 21 | no | `afterSwingOp248`, `backstabCheck`, `backstabSuccess` |

### Routed sites (lua/IEX_AsmSites.lua bindings)

| address | point | mod callback | args | ret |
|---|---|---|---|---|
| 0x14039DE77 | `hideInSight` | ST_Hook_HideInPlainSight | arg1 | boolean |
| 0x1403B9B87 | `attackIndex` | ST_Hook_AttackIndex | id1 id2 arg3 | none |
| 0x1403B8A79 | `attackCancel` | ST_Hook_ShouldCancelAttack | id1 id2 | boolean |
| 0x14039E115 | `hitRoll` | ST_Hook_HitRoll | id1 id2 arg3 | number |
| 0x14039E634 | `toHitTotal` | ST_Hook_HitMod | id1 id2 arg3 | number |
| 0x140390530 | `damageRoll` | ST_Hook_AttackDamMod | id1 id2 arg3 | number |
| 0x14039EBC3 | `critThreshold` | ST_Hook_CriticalHitMod | id1 id2 arg3 | number |
| 0x14039EC58 | `critBlocked` | - | - | switch |
| 0x1403912B2 | `critMultiplier` | ST_Hook_CriticalHitMultiplier | id1 id2 arg3 | number |
| 0x14039EEEF | `attackResult` | ST_Hook_AttackResult | arg3 | none |
| 0x140263641 | `actionButtonL` | ST_Hook_ButtonPressed | arg1 | none |
| 0x140264DEF | `actionButtonR` | ST_Hook_RButtonPressed | arg1 | none |
| 0x14024EF66 | `casterSchoolSpell` | ST_Hook_SaveDCMod | id1 ptr2 | number |
| 0x1401FB552 | `casterSchoolItem` | ST_Hook_SaveDCMod | id1 ptr2 | number |
| 0x1401CD85B | `targetSchool` | ST_Hook_SaveMod | id1 ptr2 | number |
| 0x1402B92FA | `classDone` | ST_Hook_CharGenClassDone | id1 | none |
| 0x1402C7C41 | `profMaxUI` | ST_Hook_ProficiencyMax | arg1 arg2 | number |
| 0x1402BE2B1 | `profMax` | ST_Hook_ProficiencyMax | arg1 arg2 | number |
| 0x1403B902A | `keepAmmo` | SQAmmo_Hook_Keep | obj1 obj2 | boolean |
| EEex_Label(Hook-CGameContainer::Render()-B3EmptyContainer)+0x39 | `containerMarker` | - | - | bridge |

<!-- GENERATED: end -->
