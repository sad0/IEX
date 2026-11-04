# API inventory: everything EEex-using mods depend on (2026-10-29)

Static inventory of the EEex surface used by every EEex-dependent mod found, per mod and per component, compared
with what IEX provides. Tool: `tools/compat/inventory.py` (companion of `scan_mods.py`, rules v5, no verdict change).
Machine-readable output: `E:/Dev/IEX-data/inventory/inventory.json` (per API item: mods, uses, argument shapes,
string arguments, example lines; per mod and per component: every item it uses with IEX status). Nothing was
installed or run; downloaded mods were read as data only (`python -I`). Clean room: only the mods' own code was
read (what they call), never EEex / InfinityLoader / EEex-Torment sources.

```
python -I tools/compat/inventory.py --corpus E:/Dev/IEX-data/inventory/corpus.json --mods E:/Dev/IEX-data/mods \
    --json E:/Dev/IEX-data/inventory/inventory.json --md docs/API_INVENTORY.md
```

## Corpus (49 mods)

- The 39 mods of the 2026-10-29 static scan (maintainer test data, not in this repository).
- **SadoEE**: text sources of `EET 2.7.3 (dev)/PartyStash` + `SadoQoL` copied read-only to
  `E:/Dev/IEX-data/mods/SadoEE/src` (lua, menu, tp2/tpa/tph, baf/d, 2da/ids, tra, md/txt/ini; no binaries).
- **Candlekeep catalog** (E:/Dev/IEModManager/catalog/catalog.json, 99 entries, read only): the 7 entries that name
  EEex (Artisan's Kitpack, Spell Menu Extended, Tweaks Anthology, EET Tweaks, Tactics Remix, Party Stash / SadoEE)
  are in the corpus; for the other 92, `gh search code "EEex user:<owner>"` over all 18 catalog owners found no
  other EEex reference.
- **Public search** (2026-10-29): GitHub code search (`EEex_` in .lua/.tp2/.tph/.tpa, `EEex.tp2`, `B3-EEex`,
  `EEEX/EEEX.TP2`, `EEex.dll`, `InfinityLoader` in tp2/tph, `EEex_Options`, `EEex_Opcode`, `EEex_Sprite`, `EEex_Key_`,
  `EEex_LuaTrigger`, `EEex_LuaAction`, `EEex` in .menu/.baf/.tpp/.tra/.txt/.md), per-author searches (36 known EE
  mod authors / orgs), the BWS-NG dependency rules (Selphira/BigWorldSetup-Next-Generation) and the chriz-bg-collection
  install order; Beamdog forum threads for mods named there. **10 new mods kept** (official GitHub source, release
  if any, else default branch): EEex Remote Console, Spells and Magic, A7 ADD_KIT_EX, InfinityEngine Enhancer, BGEE
  Graphics Enhanced, EEex Hotkey Prev/Next Character, BG2 Narrator, Random Graion Magic, Sword Coast Infinity (+
  SadoEE). Excluded after reading: see the generated list below (Thieving Skills for Bards: repo gone, merged into
  Skills and Abilities; Polymorph fixes for IWDEE: comment only; installers and catalogs).
- Gibberlings3 / Spellhold / Weasel mods / morpheus-mart: no EEex mod beyond the ones above (morpheus-mart's three
  are in the corpus; Spellhold's Generalized Biffing only lists EEex files not to biff; no Weasel mod references EEex).
- **PST:EE (EEex-Torment)**: no public mod targets EEex-Torment (code search: only the port itself, not opened).
  the maintainer's own PSTEE mods live in game folders and were not read (out of scope).

Metadata (name, author, URL, how obtained) is in `E:/Dev/IEX-data/inventory/corpus.json`; version / games are read
from each tp2 (`VERSION`, `GAME_IS`).

## Method (what is extracted)

Per file, comments blanked with scan_mods' v5 rules (offsets kept for line numbers), then:

| category | how |
|---|---|
| EEex functions / tables / constants | scan_mods `RX_EEEX`; use kind = call (argument shapes from a balanced-paren parse: `num str bool nil table{keys} fn(params) var field concat expr call:Name`), member (`.FIELD`), assign, ref; string-literal arguments kept per position |
| internal hooks replaced | names the mod assigns itself that look like EEex internals (`_Hook_`, `_Private_`, `...Listeners`, `EEex_On...`): EEex calls them, the mod replaces them |
| listeners | `EEex_*Add*Listener` (call or alias), callback parameter names |
| methods | `recv:method(` in Lua (not self / std libs / methods the mod defines); class from an `EEex_<Prefix>_Get...` assignment (strong), receiver name (weak) or IEX's own method table |
| fields | `.m_xxx` chains; class from the receiver, followed through `engine/*.iexd` field types (bases and subclasses) |
| opcodes 400-409 | `opcode / match_opcode / effectID = 40x` in WeiDU and Lua, with the parameters of the enclosing LPF / table |
| IDS | script names in .baf/.d, tp2 strings and Lua strings; IDS / 2DA appends (STATS.IDS, X-*, SPLSTATE > 255, EEex rows) |
| data files | X-*.2DA/IDS, `*EEex*.lua/menu`, `B3*.lua`, EEex.dll/db/exe/ini, InfinityLoader.*, with the WeiDU operation (FILE_EXISTS, COPY_EXISTING, FILE_CONTAINS...) |
| menus | menu names given to `EEex_Menu_*` / `Infinity_*Menu*`; marked when the mod defines them |
| EEex_Modules | `EEex_Modules["X"]` reads / writes, and `["X"] = true` in EEex_Modules.lua patches |
| settings | `Infinity_Get/SetINIValue(section, key, default)` (also through pcall), `EEex_Options_Register` (id, default, range, storage section/key), EEex.ini / InfinityLoader.ini lines written or searched by tp2 code, Baldur.lua `SetPrivateProfileString` in tp2 |
| hard usage | scan_mods `HARD`, with the Lua function it sits in and the labels it passes; engine labels named in strings |
| requirements | REQUIRE_COMPONENT / MOD_IS_INSTALLED / FORBID_COMPONENT / FILE_EXISTS / FILE_CONTAINS on EEex files, Lua `EEex_Active`..., EEex versions named in readmes; whether `patch_mod.py` rewrites the check |

IEX side: `scan_mods.iex_defined()` (lua/*.lua + C++ `Register`), IDS names of weidu/IEX/IEX.tp2, `engine/*.iexd`
fields / types / symbols, `engine/methods.txt`, opcodes handled in src/core/opcodes.cpp, data files IEX.tp2 installs,
whether src/ or lua/ read EEex.ini / InfinityLoader.ini. **partial** = defined, but the comment above it says it is
incomplete (`not drawn yet`, `does nothing`, ...). Status is static: a provided name can still behave differently.

## Findings

**Coverage** (distinct items; mod-uses = sum over mods): EEex functions/tables 369 distinct, 229 provided (734 of 947
mod-uses); listeners 23/28; engine fields 233/291; opcodes 3/8 (401 402 403); script IDS entries all provided except
one; hard-usage names 12/40 provided (raw memory writes, code protection, EEex_Label, Malloc). 1980 tp2 components,
327 touch EEex, 59 of them use at least one missing / unsupported item. 29 of 49 mods use no missing or unsupported
code item (requirement checks aside).

**Top gaps (by number of mods)**

1. x64 hook / JIT API (`EEex_FlattenTable` 6, `EEex_GenLuaCall` 5, `EEex_JITNear` 5, `EEex_HookIntegrityWatchdogRegister`
   5, `EEex_Hook*WithLabels` 2-4, `EEex_JITAt` 3, `EEex_LuaCallReturnType` 5, `EEex_TryLabel` / `EEex_GetImageBase` /
   `EEex_DefineAssemblyLabel` 3): Pathfinding Redux, StickLuaFunctions, the chriz mods, SadoEE's EEex branch.
   Native-IEX candidates (from the hooked functions / labels): pathfinding and bump/attack movement
   (`CGameSprite::JumpToPoint`, `ClearBumpPath`, `CGameObjectArray::GetShare`, `CMessageHandler::AddMessage`); XP
   banking, dual-class and HLA rules (`CDerivedStats::Get/SetLevel`, `CGameSprite::AddNewSpecialAbilities`,
   `CRuleTables::*`, `CScreenCreateChar::*` in chriz-bg-modpack); Tempus APR, time stop, projectile type
   (`CProjectileArea::VFTable`) in chriz-bg-rebalance; StickLuaFunctions' 25 `ST_RegisterHook_*` combat hooks (hit
   roll, criticals, backstab, saves, proficiency caps, party leader); SadoEE's container render, effect-list random
   call and visibility map hooks (already native in IEX through IEX_Features for #40).
2. `M___EEex.lua` probe (7 mods: BuffBot, BG2 Narrator, the 4 chriz mods, Remote Console): `FILE_EXISTS
   ~override/M___EEex.lua~` is EEex's bootstrap file; IEX has none and patch_mod.py does not rewrite it.
   Also unpatched: `M__EEex.lua` (B_Kits, Proficiencies), `EEex.dll` / `InfinityLoader.db` / `EEex.exe` /
   `InfinityLoader.ini` probes, `FILE_CONTAINS EEex_scripts/<file>.lua ^function EEex_X` (chriz: tests for a
   function in EEex's sources), `MOD_IS_INSTALLED EEex.tp2 1 / 2` (LuaJIT / timer modules: High Power, Olvyn,
   Tweaks Anthology, ZS Tweaks, XGT).
3. EEex internal hooks replaced by mods (9 missing): projectile hooks `EEex_OnDecodeProjectile` /
   `EEex_OnPostProjectileCreation` / `EEex_OnAddEffectToProjectile`, `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`,
   `EEex_Sprite_Hook_OnDestruct` (High Power, Olvyn); `EEex_Actionbar_Hook_HasFullThieving` (Aura, Skills and
   Abilities); `EEex_Menu_Hook_OnBeforeUIItemRender` / `EEex_Menu_Hook_BeforeListRenderingItem` (BG2 Narrator);
   `EEex_Opcode_Hook_OnAfterSwingCheckedOp248` (StickLuaFunctions). IEX must call these globals at the same moments.
4. Opcodes 400, 404-409 missing (High Power, Olvyn, Improved HoF, Tweaks Anthology: 408 x3, 406 x3, 400 x3, 407 x3,
   409 x2); parameters seen are in the opcode table below.
5. `EEex_Sprite_AddMarshalHandlers` (BuffBot, chriz-bg-modpack, chriz-bg-rebalance; plus
   `EEex_Sprite_Private_MarshalHandlers`, `EEex_Sprite_FallbackMarshalStorage`): per-creature data saved in the game.
6. Projectile class (`EEex_Projectile_Type`, `EEex_Projectile_IsOfType`: High Power, Olvyn, Tweaks Anthology) and
   fields `m_sourceTarget` (BuffBot, chriz-bg-rebalance, Tweaks Anthology), `m_bConfirmDialog` / `m_bRenderFrameTimes`
   (IUI++, Bubb's IUI, chriz-bg-rebalance).
7. Listeners: `EEex_AIBase_AddScriptingObjectUpdatedListener` (Radar Overlay, chriz-bg-modpack),
   `EEex_Menu_AddBeforeListRendersItemListener` (BuffBot, BG2 Narrator), `EEex_Action_AddEnabledSpriteStartedActionListener`
   (High Power, Olvyn), `EEex_Opcode_AddDeferredListsResolvedListener`, `EEex_Menu_AddBeforeMainFileLoadedListener`.
8. `EEex_Modules` switches: `B3Scale` read by IUI++ / Bubb's IUI (32 uses), `ME_DAMAB` / `B3Invis` written by High
   Power / Olvyn; IEX has no EEex_Modules table content.
9. chriz-bg-modpack's own use of EEex internals: `EEex_Keybinds_*`, `EEex_LoadLibrary`, `EEex_GetProcAddressInternal`,
   `EEex_Get/SetLuaRegistryIndex`, `EEex_OpenLuaBindings`, `EEex_MessageBox`, `EEex_Menu_*FileLoadedListeners` tables.
10. Early-EEex x86 API (Improved HoF, EET Tweaks 2080): `EEex_ReadDword` 962 uses, `EEex_ApplyEffectToActor` 214,
    `EEex_GetActorShare`, `EEex_WriteDword`...: raw x86 offsets, broken on current EEex too.

## Settings

Where each mod keeps its settings, under EEex and under IEX (full table in the generated section).

| store | under EEex | under IEX |
|---|---|---|
| `Infinity_GetINIValue` / `Infinity_SetINIValue` (85 keys, 7 mods) | engine INI (Baldur.lua) | the same engine functions: identical |
| `EEex_Options_*` (SadoQoL 17, BuffBot 5) | option objects; `EEex_Options_NumberLuaStorage{section, key}` = Baldur.lua `[section] key` (SadoQoL); BuffBot uses its own storage subclass | lua/EEex_Options.lua: same Baldur.lua key, EEex's storage / option shapes (BuffBot's subclass works); options screen lua/EEex_OptionsUI.lua (2026-10-29) |
| EEex.ini `[Empty Container Module] Enable=1` (SadoQoL.tp2) | read by EEex's installer and its options screen (Modules tab); under EEex 1.3.1 `EEex_Modules` stays all false at run time | read at start (src/core/settings.cpp): `EEex_Modules` all false (IEX has none of the modules; an enabled one is logged), shown in the options screen's Modules tab |
| InfinityLoader.ini `[General] LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL`, `LuaLibrary`, `LuaVersionExternal` (BuffBot, Remote Console: tp2 checks / writes them to get LuaJIT and the io/os libraries) | InfinityLoader | read at start: `LuaPatchMode` EXTERNAL / REPLACE_INTERNAL_WITH_EXTERNAL opens io / os / bit; IEX.tp2 component 2 writes the lines; Remote Console and BuffBot install and run (2026-10-29) |
| Baldur.lua `SetPrivateProfileString` from tp2 | engine | identical |

SadoQoL's options (M_SQOPT.lua, section `SadoQoL` of Baldur.lua, ids `SQOPT_<id>`): `Stash Tints`, `Stash Upgrade
Mark`, `Stash DPS Line`, `Passive Traps`, `Auto Disarm`, `Auto Open`, `Valuable Containers`, `Endless Ammo`, `Basic Ammo
Quiver`, `Attack Move`, `Mode Spam Filter`, `Sorted Loot`, `Chests In Ground Bar`, `Camp Waiting`, `FPS` (switches 0..1,
default 1), `Auto Stash` (choice 0..2, default 0), `Options Page Line` (always 0); plus Infinity_*INIValue keys
`SadoQoL/FPS` (default 1), `SadoQoL/Bind <key>` and `SadoQoL/Mouse <old key>` (default -999), `AutoRoller/StrWeight`,
`AutoRoller/Duration`, `AutoRoller/<key>`, `Party Stash/Camp Merchant Board`.

Why SadoEE settings could change after EEex -> IEX (static reading):

1. Until commit c3c5da9 (today), IEX's `NumberLuaStorage:read()` called `Infinity_GetINIValue(section, key, nil)`;
   the engine gives 0 for an absent key, so every SadoQoL switch never saved under EEex (default 1) read as 0 = off.
   c3c5da9 detects absent keys (two sentinel defaults) and returns the option's default.
2. Also before c3c5da9, `EEex_Options_Register` did not call `onChange(option, nil)` at registration, so SadoQoL's
   `apply(row)` never copied the stored values into the features' fields at startup.
3. Done 2026-10-29: the options screen (EEex_Options_Open, ESC menu button, \ key; SadoQoL's tab line opens its page
   through toggleWarning); EEex.ini is read (EEex_Modules, Modules tab). The Empty Container module itself (gray
   outline of empty containers, `B3EmptyContainer_Hook_OnBeforeContainerOutlineRender`) is not implemented.
4. Done 2026-10-29, BuffBot: storages are called read(option) / write(option, value), `option:_getDefault()`,
   `_read` / `_set(value, noWrite)` / `_setWorkingValue`, `canReadEarly()`; `EEex_Options_Private_Storage` and
   `EEex_Options_Widget` exist, so its tab registers (5 options, 3 columns, theme bridge checked live).

## Notes and limits

- Static and textual: names built at runtime (`_G['EEex_' .. x]`) and Lua loaded from `%variable%` paths are not seen;
  `IEX/missing_api.txt` (written while playing) completes it.
- Method classes are inferred (strong only from an `EEex_<X>_Get...` assignment); uppercase methods on game objects
  (`worldScreen:...`, `game:GetPartyGold()`) are tolua engine bindings that exist without an extender ("tolua").
- Shapes count every textual occurrence, including duplicated files (IUI++ and Bubb's fork share a commit, Olvyn Spells
  and High Power share M__MEFUN.LUA, StickLuaFunctions ships 6 versions, Pathfinding Redux ships tests).
- inventory.json is the input for the differential test harness (`tools/difftest/`, other agent) and for Candlekeep
  (`api.<category>.<item>.shapes / strargs / examples`).


<!-- generated by tools/compat/inventory.py: everything below this line is rewritten -->

Generated 2026-10-29 by `tools/compat/inventory.py` (IEX 0.2.2, scan rules v5), corpus 49 mods.

## Coverage summary

| category | distinct items | provided | partial | missing | unsupported | other | mod-uses covered (provided / all) |
|---|---|---|---|---|---|---|---|
| EEex functions, tables and constants | 369 | 229 | 1 | 111 | 28 | 0 | 734 / 947 |
| EEex internal hook functions the mod replaces | 10 | 1 | 0 | 9 | 0 | 0 | 1 / 16 |
| Listeners registered | 28 | 23 | 0 | 5 | 0 | 0 | 80 / 88 |
| Engine-object methods | 297 | 50 | 1 | 11 | 0 | 235 | 121 / 626 |
| Engine fields | 291 | 233 | 0 | 58 | 0 | 0 | 592 / 662 |
| EEex opcodes 400-409 | 8 | 3 | 0 | 5 | 0 | 0 | 23 / 37 |
| Script IDS entries and IDS / 2DA appends | 79 | 77 | 0 | 1 | 0 | 1 | 101 / 103 |
| EEex data and Lua files | 28 | 2 | 5 | 16 | 0 | 5 | 2 / 50 |
| Menus used | 653 | 0 | 0 | 16 | 0 | 637 | 0 / 1211 |
| EEex_Modules switches | 3 | 0 | 0 | 3 | 0 | 0 | 0 / 5 |
| Settings (option keys) | 97 | 0 | 7 | 5 | 0 | 85 | 134 / 146 |
| Hard usage (asm / hooks / raw memory) | 40 | 12 | 0 | 0 | 28 | 0 | 58 / 122 |
| Engine symbols / hook labels named in strings | 67 | 0 | 38 | 0 | 29 | 0 | 0 / 75 |
| EEex requirement checks | 80 | 1 | 0 | 0 | 0 | 79 | 54 / 173 |

"other": script (IEX IDS entry), same (engine INI), patched (patch_mod.py), mod data, info, unknown (method receiver not inferred: tolua engine method or mod code), unpatched.

## Corpus

| mod | name | author | version | games | source | EEex names | missing | hard | components using EEex |
|---|---|---|---|---|---|---|---|---|---|
| Bardic-Wonders | Bardic Wonders | TheArtisan |  | bg2ee bgee eet | https://github.com/TheArtisanBG/Bardic-Wonders (github default branch) | 6 | 0 | - | 3/26 |
| Shadow-Magic | Shadow Magic | TheArtisan |  | bg2ee bgee eet | https://github.com/TheArtisanBG/Shadow-Magic (github default branch) | 6 | 0 | - | 7/9 |
| SpellMenuExtended | Bubb's Spell Menu Extended | Bubb | v5.2 | bg2ee bgee eet iwdee | https://github.com/Bubb13/Bubbs-Spell-Menu-Extended (github release) | 37 | 0 | - | 1/2 |
| The-Artisan-s-Kitpack | The Artisan's Kitpack | TheArtisan | 4.8 | bg2ee bgee eet | https://github.com/TheArtisanBG/The-Artisan-s-Kitpack (github default branch) | 4 | 0 | - | 10/69 |
| aura | Aura NPC (BG1/BG2/EET) | TheArtisan |  | bg2ee bgee eet | https://github.com/TheArtisanBG/Aura_BG1_BG2_EET (github default branch) | 4 | 0 | - | 4/15 |
| autodescription | AutoDescription | Selphira | 0.9.37 | bg2ee bgee eet | https://github.com/Selphira/AutoDescription (github release 0.9.37) | 0 | 0 | - | 0/4 |
| b-kits | B_Kits | Grammarsalad | 0.02.01 | bg2ee bgee eet iwdee | https://github.com/Grammarsalad/B_Kits (github default branch) | 6 | 0 | - | 8/43 |
| bg-eeex-buffbot | BuffBot (EEex) | Chrizhermann | v1.12.1, v1.7.0-alpha, v1.7.4- | bg2ee bgee eet iwdee | https://github.com/Chrizhermann/bg-eeex-buffbot (github default branch) | 70 | 27 | - | 8/8 |
| bg2-radar-overlay | BG2 Radar Overlay | tapahob |  | ? | https://github.com/tapahob/BG2RadarOverlay (github release 2.6.2.0) | 11 | 2 | 7 | 0/0 |
| bubb-infinityui | InfinityUI (Bubb's fork) | Bubb / Renegade0 | v1.31 | bg2ee bgee eet iwdee | https://github.com/Bubb13/InfinityUI (github default branch (same commit as iui)) | 17 | 4 | - | 1/9 |
| candlekeep-revisited | Candlekeep Revisited | TheArtisan |  | bgee eet | https://github.com/TheArtisanBG/Candlekeep-Revisited (github default branch) | 0 | 0 | - | 1/5 |
| caster-crafting | Caster Crafting | BardezAnAvatar | v0.7.6 | ? | https://github.com/BardezAnAvatar/BGEE-Caster-Crafting (github default branch) | 0 | 0 | - | 0/11 |
| chriz-bg-modpack | chriz-bg-modpack | Chrizhermann | v0.2.0-alpha.14 | bg2ee bgee eet | https://github.com/Chrizhermann/chriz-bg-modpack (github default branch) | 80 | 39 | 330 | 6/67 |
| chriz-bg-rebalance | chriz-bg-rebalance | Chrizhermann | private-2026-10-06, private-oc | bg2ee eet iwdee | https://github.com/Chrizhermann/chriz-bg-rebalance (github default branch) | 66 | 25 | 98 | 16/81 |
| chriz-playable-races | chriz-bg-playable-races | Chrizhermann | v0.3.0-proto | ? | https://github.com/Chrizhermann/chriz-bg-playable-races (github default branch) | 20 | 2 | 22 | 2/2 |
| chriz-sod-rebalance | chriz-sod-rebalance | Chrizhermann | ground-probe-1, v0.6.16 | eet | https://github.com/Chrizhermann/chriz-sod-rebalance (github default branch) | 11 | 0 | - | 3/52 |
| diablofication | Diablofication | m-architek | v0.8 | bgee (NOT GAME_INCLUDES sod) | https://github.com/m-architek/Diablofication (github default branch) | 7 | 0 | - | 0/10 |
| eet-tweaks | EET Tweaks | K4thos | 1.12 | bg1 bg2ee bgee bgt ca eet how iwd iwd2 i | https://github.com/K4thos/EET_Tweaks (github default branch) | 2 | 1 | - | 1/77 |
| epic-thieving | Epic Thieving | OlvynChuru |  | bg1 bg2 bg2ee bgee bgt eet how iwd iwdee | https://github.com/OlvynChuru/Epic-Thieving (github default branch) | 5 | 0 | - | 1/22 |
| high-power-bg | High Power Baldur's Gate | OlvynChuru | 2.5.0 | bgee eet iwdee | https://github.com/OlvynChuru/High-Power-Baldurs-Gate (github default branch) | 66 | 21 | 59 | 3/71 |
| house-rule-tweaks | House Rule Tweaks | TheArtisan |  | bg2ee bgee eet iwdee | https://github.com/TheArtisanBG/House-Rule-Tweaks (github default branch) | 10 | 0 | - | 3/52 |
| ie-skillz | IE Skillz | Grammarsalad | 0.00.01 | bg bg2 bg2ee bgee bgt eet iwdee | https://github.com/Grammarsalad/IE_Skillz (github default branch) | 3 | 0 | - | 0/9 |
| improved-hof | Improved Heart of Fury Mode | OlvynChuru | 4.0.2 | ? | https://github.com/OlvynChuru/Improved-Heart-Of-Fury-Mode (github default branch) | 59 | 37 | 45 | 2/19 |
| iui | Infinity UI++ | Renegade0 | v1.31 | bg2ee bgee eet iwdee | https://github.com/Renegade0/InfinityUI (github default branch) | 17 | 4 | - | 1/9 |
| morpheus562-kitpack | Morpheus562's Kitpack | morpheus562 | v5.11 | bg2ee bgee eet iwdee | https://morpheus-mart.com (Dropbox package 5.11 (setup exe never run)) | 3 | 0 | - | 0/29 |
| olvynspells | Olvyn Spells (MESpells) | OlvynChuru | 2.6.0 | bg2ee bgee eet iwdee | https://github.com/OlvynChuru/OlvynSpells (github default branch) | 67 | 21 | 59 | 11/77 |
| pathfinding-redux | BG Pathfinding Redux | zach-hopkins | 0.1.11-preview | bg2ee bgee eet | https://github.com/zach-hopkins/bg-pathfinding-redux (github default branch) | 64 | 27 | 581 | 1/1 |
| poisoned-pathways | Poisoned Pathways | AciferBG | v1.8 | bg2ee eet | https://github.com/AciferBG/Poisoned-Pathways (github release v1.8) | 4 | 0 | - | 1/1 |
| proficiencies | Proficiencies | Grammarsalad | 0.06.04 | bg2ee bgee eet iwdee | https://github.com/Grammarsalad/Proficiencies (github default branch) | 0 | 0 | - | 21/62 |
| skills-and-abilities | Skills and Abilities | morpheus562 | v5.3, v5.4 | bg2ee bgee eet iwdee | https://morpheus-mart.com (Dropbox package 5.4 (setup exe never run)) | 7 | 0 | - | 32/65 |
| sod2bg2-iu | SoD to BG2EE Item Upgrade | Gibberlings3 | v2.0.5 | bg1 bg2ee bgee eet how iwd iwd2 iwd_in_b | https://github.com/Gibberlings3/SoD-to-BG2EE-Item-Upgrade (github default branch) | 3 | 0 | - | 2/38 |
| stick-lua-functions | StickLuaFunctions | xbigxiangx-dot | v0.10.0, v0.11.0-Alpha, v0.8.0 | ? | https://github.com/xbigxiangx-dot/StickLuaFunctions (github release v0.11.0-Alpha) | 35 | 5 | 608 | 6/6 |
| tactics-remix | Tactics Remix | morpheus562 | v8.2 | bg2ee bgee eet iwdee | https://morpheus-mart.com (Dropbox package 8.2 (setup exe never run)) | 8 | 0 | - | 84/113 |
| tweaks | Tweaks Anthology | Gibberlings3 (CamDawg et al.) | v18 | bg1 bg2 bg2ee bgee bgt ca eet how iwd iw | https://github.com/Gibberlings3/Tweaks-Anthology (github default branch) | 86 | 19 | - | 54/446 |
| wares-of-the-planes | Wares of the Planes | Argent77 | 2.7 | bg2ee bgee eet | https://github.com/Argent77/A7-WaresOfThePlanes (github release v2.7) | 0 | 0 | - | 0/3 |
| warlock | Warlock | TheArtisan |  | bgee eet iwdee | https://github.com/TheArtisanBG/Warlock (github default branch) | 13 | 0 | - | 1/1 |
| workshop-kitpack | The Workshop Kitpack | D2-mods | 5.29 | bg2ee bgee eet iwdee | https://github.com/D2-mods/The-Workshop-Kitpack (github release v5.29) | 0 | 0 | - | 0/11 |
| xgt-xp-gain | XGT Customizable XP Gain | Xgatt | v0.6.0-alpha | bg2ee bgee eet iwdee | https://github.com/Xgatt/XGTCustomizableXPGain (github release v0.6.0-alpha) | 3 | 0 | - | 1/1 |
| zstweaks | ZS Tweaks | szaumoor | 1.7.0c | bg2ee bgee eet iwdee | https://github.com/szaumoor/ZSTweaks (github release 1.7.0c) | 0 | 0 | - | 0/357 |
| SadoEE | SadoEE (Party Stash + SadoQoL) | sad0 | proto, v0.1, v1.2.1 | bg2ee bgee eet | https://github.com/sad0/SadoEE (local dev sources (EET 2.7.3 (dev)/PartyStash + SadoQoL), text files only) | 112 | 6 | 252 | 28/38 |
| eeex-remote-console | EEex Remote Console | Chrizhermann | v0.2.1 | bg2ee bgee eet iwdee | https://github.com/Chrizhermann/eeex-remote-console (github default branch (master 2026-10-22)) | 8 | 0 | - | 1/1 |
| spells-and-magic | Spells and Magic | Grammarsalad | 0.00.01 | bg bg2 bg2ee bgee bgt eet iwdee | https://github.com/Grammarsalad/Spells_and_Magic (github default branch (main 2025-12-02)) | 5 | 0 | - | 0/5 |
| a7-add-kit-ex | A7 ADD_KIT_EX library | Argent77 | 2.0 | bg2ee bgee eet iwdee | https://github.com/Argent77/A7-add_kit_ex (github default branch (master 2026-05-18)) | 0 | 0 | - | 0/4 |
| ie-enhancer | InfinityEngine Enhancer | TheForgotten69 |  | ? | https://github.com/TheForgotten69/InfinityEngine-Enhancer (github release v0.1.0) | 3 | 1 | 2 | 0/0 |
| bgee-graphics-enhanced | BGEE Graphics Enhanced | TheForgotten69 | v0.1.0 | bg2ee bgee eet iwdee | https://github.com/TheForgotten69/BGEE-Graphics-Enhanced (github release v0.2.0) | 3 | 1 | 2 | 0/2 |
| hotkey-prevnext-char | EEex Hotkey Prev/Next Character | snaphat |  | ? | https://github.com/snaphat/InfinityEngineEEexHotkeyPrevNextChar (github default branch (main 2025-01-15)) | 4 | 0 | - | 0/0 |
| bg2narrator | BG2 Narrator | MariusTBjercke | v0.1.1 | bg2ee eet | https://github.com/MariusTBjercke/bg2narrator (github release v0.1.1) | 8 | 4 | - | 1/1 |
| random-graion-magic | Random Graion Magic | GraionDilach | 0.12 | bg2ee bgee eet iwdee | https://github.com/GraionDilach/RandomGraionMagic (github release 0.12) | 2 | 0 | - | 2/5 |
| sword-coast-infinity | Sword Coast Infinity | DataForInfinity | v1.0, v1.2, v2.1 | bg2ee bgee eet iwdee | https://github.com/DataForInfinity/Sword-Coast-Infinity (github default branch (main 2025-04-19)) | 2 | 0 | - | 0/41 |

**Excluded after checking:**

- weidu, weidu-win: WeiDU binaries, not mods
- Thieving Skills for Bards (morpheus562): requires EEex, but github.com/Gibberlings3/Thieving-Skills-For-Bards is gone (404); merged into Skills and Abilities
- Polymorph fixes for IWDEE (D2-mods): EEex only in a comment (nymph.BCS crash fix)
- Bubb13/EEex, Bubb13/InfinityLoader, Bubb13/EEex-Docs, sad0/EEex-Torment: the extenders themselves (clean room: not opened)
- chriz-bg-collection, chriz-easy-iwd, Born2BSalty Infinity Orchestrator, BWS-NG, arnaudpourbaix installer, krion64 catalog, ChitownWillie lists, InfinityExpress: installers / catalogs / install lists, not mods (used only to find mods)
- B_Spells, Temporary_B_Spells, Trollkiller's kitpack: ClassSpellTool copy with the EEex code commented out (2026-10-29 scan)
- Generalized Biffing (Spellhold): EEex only in its blacklist of files not to biff
- EET (Gibberlings3): lib/macros.tph mentions EEex only to skip its files
- BG2 Improved GUI (Spellhold): original-engine (non-EE) project, 'eeex' substring match only

## EEex functions, tables and constants (369)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `EEex_GameObject_Get` | 21 | 331 | provided | Bardic-Wonders, SadoEE, Shadow-Magic, bg-eeex-buffbot, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, epic-thieving, high-power-bg, house-rule-tweaks, olvynspells, pathfinding-redux, poisoned-pathways, random-graion-magic, spells-and-magic, stick-lua-functions, sword-coast-infinity, tactics-remix, tweaks, warlock | `(var)`×243, `(field)`×60, `ref`×11 |  |
| `EEex_Sprite_GetStat` | 15 | 191 | provided | Bardic-Wonders, SadoEE, Shadow-Magic, chriz-bg-rebalance, chriz-sod-rebalance, epic-thieving, high-power-bg, house-rule-tweaks, olvynspells, random-graion-magic, spells-and-magic, stick-lua-functions, sword-coast-infinity, tweaks, warlock | `(var, num)`×144, `(call:EEex_GameObject_Get, num)`×16, `(var, var)`×15 |  |
| `EEex_UDToPtr` | 11 | 497 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, iui, olvynspells, pathfinding-redux, stick-lua-functions, tweaks | `(var)`×295, `(field)`×174, `ref`×12 |  |
| `EEex_GameObject_ApplyEffect` | 11 | 116 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, epic-thieving, high-power-bg, house-rule-tweaks, iui, olvynspells, stick-lua-functions, tweaks | `(var, table)`×83, `ref`×10, `assign`×3 |  |
| `EEex_Sprite_GetInPortrait` | 11 | 83 | provided | bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, eeex-remote-console, high-power-bg, iui, olvynspells, pathfinding-redux, tweaks, xgt-xp-gain | `(var)`×55, `(num)`×20, `(expr)`×4 |  |
| `EEex_Actionbar_AddListener` | 11 | 44 | provided | Bardic-Wonders, Shadow-Magic, SpellMenuExtended, The-Artisan-s-Kitpack, aura, high-power-bg, house-rule-tweaks, olvynspells, skills-and-abilities, tweaks, warlock | `(var)`×43, `(fn(config,state))`×1 |  |
| `EEex_Read32` | 10 | 398 | provided | SadoEE, bg2-radar-overlay, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, iui, olvynspells, pathfinding-redux | `(expr)`×358, `ref`×16, `(field)`×8 |  |
| `EEex_Resource_Demand` | 10 | 150 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, high-power-bg, iui, olvynspells, stick-lua-functions, tweaks | `(var, str)`×71, `(expr, str)`×38, `ref`×29 |  |
| `EEex_Active` | 10 | 99 | provided | bg-eeex-buffbot, bg2narrator, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, diablofication, eeex-remote-console, iui, xgt-xp-gain | `ref`×97, `assign`×2 |  |
| `EEex_EnableCodeProtection` | 10 | 83 | provided | SadoEE, bgee-graphics-enhanced, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, ie-enhancer, olvynspells, pathfinding-redux, stick-lua-functions | `()`×71, `ref`×11, `assign`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Actionbar_SetButton` | 10 | 81 | provided | Bardic-Wonders, Shadow-Magic, The-Artisan-s-Kitpack, aura, high-power-bg, house-rule-tweaks, olvynspells, skills-and-abilities, tweaks, warlock | `(num, field)`×73, `(var, field)`×6, `(var, var)`×2 |  |
| `EEex_DisableCodeProtection` | 10 | 76 | provided | SadoEE, bgee-graphics-enhanced, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, ie-enhancer, olvynspells, pathfinding-redux, stick-lua-functions | `()`×64, `ref`×11, `assign`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Utility_IterateCPtrList` | 9 | 164 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, chriz-playable-races, iui, pathfinding-redux, tweaks | `(field, var)`×19, `(field, fn(effect))`×17, `ref`×16 |  |
| `EEex_Actionbar_ButtonType` | 9 | 93 | provided | Bardic-Wonders, Shadow-Magic, SpellMenuExtended, The-Artisan-s-Kitpack, aura, house-rule-tweaks, skills-and-abilities, tweaks, warlock | `.FIND_TRAPS`×23, `.QUICK_SPELL_1`×11, `.STEALTH`×11 |  |
| `EEex_ReadU8` | 8 | 275 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, olvynspells, pathfinding-redux | `(expr)`×205, `(var)`×44, `ref`×16 |  |
| `EEex_BAnd` | 8 | 166 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-rebalance, chriz-playable-races, chriz-sod-rebalance, pathfinding-redux, stick-lua-functions, tweaks | `(field, var)`×37, `(field, num)`×33, `(expr, num)`×25 |  |
| `EEex_GameState_AddInitializedListener` | 8 | 60 | provided | SadoEE, bg2-radar-overlay, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, pathfinding-redux, tweaks | `(var)`×19, `ref`×10, `(fn(), concat)`×8 |  |
| `EEex_Resource_Load2DA` | 8 | 60 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, stick-lua-functions, tweaks, warlock | `(str)`×40, `ref`×12, `(var)`×8 |  |
| `EEex_Sprite_SetLocalInt` | 8 | 45 | provided | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, high-power-bg, olvynspells, stick-lua-functions, tweaks | `(var, str, num)`×19, `(var, concat, var)`×12, `(var, var, num)`×3 |  |
| `EEex_Action_AddSpriteStartedActionListener` | 8 | 43 | provided | SadoEE, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux, tweaks | `(fn(sprite,action))`×13, `ref`×10, `(var)`×6 |  |
| `EEex_GameObject_GetSelected` | 8 | 40 | provided | Bardic-Wonders, Shadow-Magic, SpellMenuExtended, The-Artisan-s-Kitpack, aura, house-rule-tweaks, skills-and-abilities, warlock | `()`×40 |  |
| `EEex_GetActorClass` | 8 | 22 | provided | b-kits, ie-skillz, improved-hof, morpheus562-kitpack, skills-and-abilities, sod2bg2-iu, spells-and-magic, tactics-remix | `(var)`×22 |  |
| `EEex_Write32` | 7 | 288 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux | `(expr, num)`×96, `(expr, var)`×49, `(expr, expr)`×34 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Label` | 7 | 128 | provided | SadoEE, chriz-bg-rebalance, high-power-bg, improved-hof, olvynspells, pathfinding-redux, stick-lua-functions | `(str)`×123, `ref`×4, `assign`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_EngineGlobal_CBaldurChitin` | 7 | 75 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux | `.m_pObjectGame`×50, `ref`×10, `assign`×6 |  |
| `EEex_Key_GetFromName` | 7 | 72 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, iui, pathfinding-redux, tweaks | `(str)`×68, `(var)`×2, `assign`×1 |  |
| `EEex_Read16` | 7 | 55 | provided | SadoEE, bubb-infinityui, chriz-bg-rebalance, high-power-bg, iui, olvynspells, pathfinding-redux | `(expr)`×50, `ref`×3, `(var)`×2 |  |
| `EEex_Sprite_GetLocalInt` | 7 | 55 | provided | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, stick-lua-functions, tweaks | `(var, str)`×32, `(var, concat)`×12, `(var, var)`×5 |  |
| `EEex_GetActorKit` | 7 | 16 | provided | ie-skillz, improved-hof, morpheus562-kitpack, skills-and-abilities, sod2bg2-iu, spells-and-magic, tactics-remix | `(var)`×16 |  |
| `EEex_GetActorAlignment` | 7 | 14 | provided | ie-skillz, improved-hof, morpheus562-kitpack, skills-and-abilities, sod2bg2-iu, spells-and-magic, tactics-remix | `(var)`×14 |  |
| `EEex_Key_AddPressedListener` | 7 | 14 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, iui, pathfinding-redux, tweaks | `(fn(key), concat)`×4, `(var)`×3, `(fn(key))`×3 |  |
| `EEex_ReadLString` | 6 | 984 | provided | SadoEE, bubb-infinityui, high-power-bg, improved-hof, iui, olvynspells | `(expr, num)`×939, `(var, num)`×22, `(call:EEex_ReadQword, num)`×6 |  |
| `EEex_FlattenTable` | 6 | 206 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, pathfinding-redux, stick-lua-functions | `(table)`×139, `(...)`×38, `(table{args,labelSuffix,returnType})`×10 | x64 asm / hooks / raw memory |
| `EEex_LuaTrigger_Object` | 6 | 96 | provided | SadoEE, high-power-bg, olvynspells, poisoned-pathways, tactics-remix, tweaks | `ref`×41, `.m_baseStats`×17, `.m_id`×9 |  |
| `EEex_ReadU16` | 6 | 93 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells | `(expr)`×58, `(var)`×29, `ref`×5 |  |
| `EEex_Action_ExecuteResponseStringOnAIBaseInstantly` | 6 | 43 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-sod-rebalance, high-power-bg, olvynspells | `(str, var)`×20, `(expr, var)`×10, `ref`×3 |  |
| `EEex_GameState_GetGlobalInt` | 6 | 31 | provided | SadoEE, chriz-bg-modpack, chriz-sod-rebalance, high-power-bg, olvynspells, tweaks | `(str)`×22, `(var)`×5, `(expr)`×2 |  |
| `EEex_Menu_LoadFile` | 6 | 30 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bg2-radar-overlay, chriz-bg-modpack, eeex-remote-console | `(str)`×27, `(var)`×2, `ref`×1 |  |
| `EEex_Sprite_GetName` | 6 | 28 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-rebalance, high-power-bg, olvynspells, stick-lua-functions | `(var)`×25, `(call:EEex_GameObject_Get)`×2, `(call:EEex_GameObject_CastUserType)`×1 |  |
| `EEex_Sprite_GetSelected` | 6 | 24 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, diablofication, hotkey-prevnext-char, tweaks | `()`×19, `ref`×3, `.returned`×1 |  |
| `EEex_GameState_AddDestroyedListener` | 6 | 18 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells | `ref`×6, `(fn())`×5, `(var)`×3 |  |
| `EEex_RunWithStackManager` | 6 | 18 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance, pathfinding-redux, tweaks | `ref`×6, `(table, fn(manager))`×4, `(table{args,constructor,name,noDestruct,struct}, fn(manager)`×4 |  |
| `EEex_HookIntegrityWatchdogRegister` | 5 | 382 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `.RAX`×87, `.RDX`×59, `.R8`×58 | x64 asm / hooks / raw memory |
| `EEex_GameObject_IsSprite` | 5 | 154 | provided | bg-eeex-buffbot, chriz-sod-rebalance, pathfinding-redux, tactics-remix, tweaks | `(var, bool)`×75, `(var)`×75, `assign`×4 |  |
| `EEex_GenLuaCall` | 5 | 143 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(str, table)`×84, `(str, table{args,returnType})`×32, `ref`×7 | x64 asm / hooks / raw memory |
| `EEex_GetUDAux` | 5 | 119 | provided | chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, tweaks | `(var)`×110, `ref`×7, `assign`×2 |  |
| `EEex_LuaCallReturnType` | 5 | 110 | missing | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `.Number`×57, `.Boolean`×50, `ref`×2 |  |
| `EEex_PtrToUD` | 5 | 90 | provided | SadoEE, bg-eeex-buffbot, pathfinding-redux, stick-lua-functions, tweaks | `(var, str)`×74, `(expr, str)`×9, `(call:EEex_UDToPtr, str)`×5 |  |
| `EEex_JITNear` | 5 | 81 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(table)`×28, `(expr)`×26, `(call:EEex_FlattenTable)`×18 | x64 asm / hooks / raw memory |
| `EEex_Malloc` | 5 | 75 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `(expr)`×34, `(num)`×32, `ref`×4 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Write8` | 5 | 26 | provided | bg2-radar-overlay, chriz-bg-modpack, high-power-bg, olvynspells, pathfinding-redux | `(expr, var)`×8, `(expr, num)`×5, `(expr, field)`×5 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_GameState_SetGlobalInt` | 5 | 17 | provided | SadoEE, chriz-sod-rebalance, high-power-bg, olvynspells, tweaks | `(var, var)`×5, `(str, num)`×3, `(str, expr)`×3 |  |
| `EEex_Menu_Find` | 5 | 16 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, eeex-remote-console | `(str)`×9, `ref`×4, `(var)`×3 |  |
| `EEex_Menu_GetItemFunction` | 5 | 13 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, eeex-remote-console | `(field)`×9, `(var)`×2, `ref`×2 |  |
| `EEex_Menu_SetItemFunction` | 5 | 13 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, eeex-remote-console | `(field, field)`×4, `(var, fn())`×2, `(field, expr)`×2 |  |
| `EEex_Read64` | 5 | 12 | provided | bubb-infinityui, chriz-bg-modpack, high-power-bg, iui, olvynspells | `(var)`×8, `(expr)`×4 |  |
| `EEex_Sprite_GetPortraitIndex` | 5 | 11 | provided | chriz-bg-rebalance, diablofication, high-power-bg, hotkey-prevnext-char, olvynspells | `(var)`×6, `ref`×2, `(call:EEex_GameObject_Get)`×2 |  |
| `EEex_Resource_LoadIDS` | 5 | 10 | provided | bg-eeex-buffbot, bubb-infinityui, chriz-playable-races, iui, tweaks | `(str)`×7, `(str, bool)`×1, `ref`×1 |  |
| `EEex_GameObject_GetUnderCursor` | 5 | 5 | provided | bubb-infinityui, diablofication, high-power-bg, iui, olvynspells | `()`×5 |  |
| `EEex_ReadU32` | 4 | 202 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance | `(expr)`×163, `(var)`×26, `ref`×7 |  |
| `EEex_LuaAction_Object` | 4 | 59 | provided | SadoEE, chriz-bg-modpack, tweaks, xgt-xp-gain | `.m_id`×26, `.applyEffect`×13, `ref`×9 |  |
| `EEex_WriteLString` | 4 | 47 | provided | chriz-bg-modpack, high-power-bg, improved-hof, olvynspells | `(expr, var, num)`×20, `(expr, str, num)`×12, `(var, call:EEex_ReadLString, num)`×6 |  |
| `EEex_Write64` | 4 | 45 | provided | SadoEE, chriz-bg-modpack, high-power-bg, olvynspells | `(expr, var)`×20, `(expr, expr)`×6, `(expr, num)`×6 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Resource_Fetch` | 4 | 40 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, stick-lua-functions | `(var, str)`×25, `ref`×13, `(var, var)`×2 |  |
| `EEex_Modules` | 4 | 38 | provided | bubb-infinityui, high-power-bg, iui, olvynspells | `[]`×36, `assign`×2 |  |
| `EEex_Key_IsDown` | 4 | 33 | provided | SadoEE, high-power-bg, olvynspells, pathfinding-redux | `(call:EEex_Key_GetFromName)`×20, `(var)`×12, `assign`×1 |  |
| `EEex_Sprite_AddLoadedListener` | 4 | 33 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-playable-races | `(fn())`×16, `ref`×7, `(fn(sprite), concat)`×3 |  |
| `EEex_Menu_AddMainFileLoadedListener` | 4 | 26 | provided | SadoEE, SpellMenuExtended, bg2-radar-overlay, eeex-remote-console | `(fn())`×22, `(var)`×1, `(fn(), expr)`×1 |  |
| `EEex_BOr` | 4 | 23 | provided | SadoEE, chriz-bg-rebalance, chriz-playable-races, stick-lua-functions | `(call:EEex_LShift, call:EEex_BAnd)`×6, `ref`×4, `(field, num)`×4 |  |
| `EEex_Menu_AddAfterMainFileLoadedListener` | 4 | 20 | provided | bg-eeex-buffbot, chriz-bg-modpack, chriz-playable-races, eeex-remote-console | `ref`×11, `(var)`×4, `(expr)`×2 |  |
| `EEex_Sprite_GetExtendedStat` | 4 | 16 | provided | epic-thieving, high-power-bg, house-rule-tweaks, olvynspells | `(call:EEex_Sprite_GetInPortrait, num)`×12, `(var, var)`×2, `(call:EEex_GameObject_Get, var)`×2 |  |
| `EEex_HookBeforeCallWithLabels` | 4 | 11 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `(expr, table, var)`×5, `ref`×1, `(field, table, table)`×1 | x64 asm / hooks / raw memory |
| `EEex_UDEqual` | 4 | 11 | provided | SadoEE, poisoned-pathways, tactics-remix, tweaks | `(field, var)`×4, `(var, var)`×2, `(var, call:EEex_Sprite_GetSelected)`×2 |  |
| `EEex_NewUD` | 4 | 10 | provided | SadoEE, bg-eeex-buffbot, stick-lua-functions, tweaks | `(str)`×10 |  |
| `EEex_Sprite_GetSelectedID` | 4 | 9 | provided | SadoEE, diablofication, high-power-bg, olvynspells | `()`×8, `ref`×1 |  |
| `EEex_Sprite_GetAllSelectedIDs` | 4 | 5 | provided | SadoEE, high-power-bg, hotkey-prevnext-char, olvynspells | `()`×4, `ref`×1 |  |
| `EEex_Sprite_GetNumCharacters` | 4 | 5 | provided | bubb-infinityui, chriz-bg-modpack, hotkey-prevnext-char, iui | `()`×5 |  |
| `EEex_ReadPtr` | 3 | 155 | missing | SadoEE, chriz-bg-rebalance, pathfinding-redux | `(expr)`×144, `(call:EEex_UDToPtr)`×4, `ref`×3 |  |
| `EEex_HookBeforeRestoreWithLabels` | 3 | 86 | unsupported | chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(expr, num, num, num, table, var)`×20, `(num, num, num, num, table, call:EEex_FlattenTable)`×19, `(expr, num, num, num, table, call:EEex_FlattenTable)`×12 | x64 asm / hooks / raw memory |
| `EEex_Action_QueueResponseStringOnAIBase` | 3 | 60 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-rebalance | `(str, var)`×23, `(expr, var)`×16, `(var, var)`×13 |  |
| `EEex_Sprite_GetActiveStats` | 3 | 55 | provided | chriz-bg-modpack, chriz-bg-rebalance, tweaks | `(var)`×52, `ref`×2, `assign`×1 |  |
| `EEex_TryLabel` | 3 | 43 | missing | chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `(var)`×20, `(str)`×10, `ref`×8 |  |
| `EEex_GetImageBase` | 3 | 39 | missing | chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `()`×29, `ref`×8, `assign`×2 |  |
| `EEex_WritePtr` | 3 | 38 | unsupported | SadoEE, chriz-bg-rebalance, pathfinding-redux | `(expr, var)`×22, `ref`×5, `(expr, expr)`×4 | x64 asm / hooks / raw memory |
| `EEex_Object_ParseString` | 3 | 37 | provided | poisoned-pathways, tactics-remix, tweaks | `(str)`×37 |  |
| `EEex_DefineAssemblyLabel` | 3 | 36 | missing | chriz-bg-modpack, pathfinding-redux, stick-lua-functions | `ref`×8, `(str, expr)`×8, `(var, var)`×7 |  |
| `EEex_HookAfterRestoreWithLabels` | 3 | 29 | unsupported | chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(expr, num, num, num, table, call:EEex_FlattenTable)`×9, `(expr, num, num, num, table, var)`×7, `ref`×4 | x64 asm / hooks / raw memory |
| `EEex_Menu_AddAfterMainFileReloadedListener` | 3 | 22 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack | `(var)`×16, `(fn())`×4, `ref`×2 |  |
| `EEex_Area_GetVisible` | 3 | 21 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot | `()`×20, `ref`×1 |  |
| `EEex_Sprite_AddMarshalHandlers` | 3 | 19 | missing | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance | `ref`×8, `(field, field, field)`×4, `(var, var, var)`×3 |  |
| `EEex_LShift` | 3 | 16 | provided | chriz-bg-rebalance, chriz-playable-races, stick-lua-functions | `(var, num)`×6, `ref`×4, `(num, expr)`×4 |  |
| `EEex_Sprite_GetState` | 3 | 16 | provided | chriz-bg-rebalance, high-power-bg, olvynspells | `(var)`×8, `(call:EEex_GameObject_Get)`×4, `ref`×3 |  |
| `EEex_ToHex` | 3 | 15 | provided | high-power-bg, improved-hof, olvynspells | `(var, num, bool)`×15 |  |
| `EEex_Menu_AddBeforeUIItemRenderListener` | 3 | 13 | provided | SpellMenuExtended, bg-eeex-buffbot, bg2narrator | `(str, var)`×10, `ref`×2, `(var, fn(it))`×1 |  |
| `EEex_JITAt` | 3 | 12 | unsupported | chriz-bg-modpack, pathfinding-redux, stick-lua-functions | `(expr, field)`×7, `(field, field)`×2, `assign`×2 | x64 asm / hooks / raw memory |
| `EEex_GetActorCurrentAction` | 3 | 11 | provided | high-power-bg, improved-hof, olvynspells | `(var)`×11 |  |
| `EEex_Projectile_IsOfType` | 3 | 11 | missing | high-power-bg, olvynspells, tweaks | `(field, field)`×10, `(var, field)`×1 |  |
| `EEex_Projectile_Type` | 3 | 11 | missing | high-power-bg, olvynspells, tweaks | `.CProjectileArea`×10, `[]`×1 |  |
| `EEex_Actionbar_GetArray` | 3 | 10 | provided | SadoEE, SpellMenuExtended, tweaks | `()`×10 |  |
| `EEex_Area_GetAllOfTypeStringInRange` | 3 | 9 | provided | SadoEE, chriz-bg-rebalance, tweaks | `(field, field, field, expr, num, bool, nil, nil)`×6, `(field, var, var, str, var, num, num)`×2, `(field, field, field, str, num, bool)`×1 |  |
| `EEex_EvalObjectStringAsActor` | 3 | 9 | missing | high-power-bg, improved-hof, olvynspells | `(str, var)`×9 |  |
| `EEex_ReadString` | 3 | 8 | provided | bg2-radar-overlay, high-power-bg, olvynspells | `(call:EEex_ReadDword)`×6, `(expr)`×2 |  |
| `EEex_Sprite_AddQuickListCountsResetListener` | 3 | 8 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance | `ref`×3, `(var)`×2, `(concat)`×1 |  |
| `EEex_Sprite_AddQuickListsCheckedListener` | 3 | 8 | provided | SpellMenuExtended, bg-eeex-buffbot, tweaks | `(fn(sprite,resref,changeAmount))`×3, `(...)`×3, `(var)`×1 |  |
| `EEex_GameObject_GetUnderCursorID` | 3 | 7 | provided | diablofication, high-power-bg, olvynspells | `()`×7 |  |
| `EEex_AddActionHook` | 3 | 6 | missing | high-power-bg, improved-hof, olvynspells | `(fn(actionData), expr)`×3, `(fn(actionData))`×3 |  |
| `EEex_Assembly_x86` | 3 | 5 | missing | chriz-bg-rebalance, chriz-playable-races, pathfinding-redux | `ref`×5 |  |
| `EEex_Menu_IsCursorWithin` | 3 | 5 | provided | SadoEE, high-power-bg, olvynspells | `(str, str)`×4, `ref`×1 |  |
| `EEex_ReadU64` | 3 | 5 | provided | SadoEE, high-power-bg, olvynspells | `(var)`×2, `(expr)`×2, `(field)`×1 |  |
| `EEex_Sprite_GetAllOfTypeStringInRange` | 3 | 5 | provided | bubb-infinityui, iui, tweaks | `(var, expr, expr, nil, nil, nil)`×3, `(var, str, var, bool)`×2 |  |
| `EEex_Sprite_GetSpellState` | 3 | 5 | provided | high-power-bg, olvynspells, tweaks | `(call:EEex_GameObject_Get, var)`×2, `(var, field)`×2, `(var, num)`×1 |  |
| `EEex_Action_ParseResponseString` | 3 | 3 | provided | high-power-bg, olvynspells, tweaks | `(str)`×2, `(var)`×1 |  |
| `EEex_GetActorLocal` | 3 | 3 | provided | high-power-bg, improved-hof, olvynspells | `(var, str)`×3 |  |
| `EEex_Write16` | 3 | 3 | provided | SadoEE, high-power-bg, olvynspells | `(var, var)`×2, `(expr, num)`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_ReadDword` | 2 | 962 | missing | eet-tweaks, improved-hof | `(expr)`×908, `(call:EEex_GetActorShare)`×49, `(call:EEex_Label)`×2 |  |
| `EEex_GetActorStat` | 2 | 127 | provided | eet-tweaks, improved-hof | `(var, num)`×121, `(var, var)`×2, `(var, field)`×2 |  |
| `EEex_Opcode_AddListsResolvedListener` | 2 | 97 | provided | chriz-bg-rebalance, tweaks | `(...)`×49, `(fn(sprite))`×20, `ref`×16 |  |
| `EEex_WriteU8` | 2 | 87 | provided | SadoEE, chriz-bg-modpack | `(expr, num)`×18, `(expr, expr)`×16, `(expr, field)`×15 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_CastUD` | 2 | 85 | provided | pathfinding-redux, tweaks | `(var, str)`×75, `assign`×4, `(field, str)`×4 |  |
| `EEex_HookAfterCallWithLabels` | 2 | 50 | unsupported | pathfinding-redux, stick-lua-functions | `(num, table, call:EEex_FlattenTable)`×31, `(expr, table, call:EEex_FlattenTable)`×7, `(var, table, call:EEex_FlattenTable)`×6 | x64 asm / hooks / raw memory |
| `EEex_GameObject_CastUserType` | 2 | 45 | provided | SadoEE, bg-eeex-buffbot | `(var)`×45 |  |
| `EEex_ExposeToLua` | 2 | 44 | provided | SadoEE, chriz-bg-modpack | `(var, str)`×22, `(expr, str)`×12, `(concat, var)`×2 |  |
| `EEex_Flags` | 2 | 44 | missing | high-power-bg, olvynspells | `(table)`×44 |  |
| `EEex_WriteU32` | 2 | 42 | provided | SadoEE, chriz-bg-rebalance | `(expr, field)`×17, `(expr, num)`×13, `(expr, var)`×4 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_JITNearAsLuaFunction` | 2 | 39 | unsupported | chriz-bg-modpack, pathfinding-redux | `(str, table)`×27, `ref`×6, `(var, var)`×4 | x64 asm / hooks / raw memory |
| `EEex_WriteFailType` | 2 | 39 | provided | stick-lua-functions, tweaks | `.NOTHING`×18, `.DEFAULT`×14, `.ERROR`×7 |  |
| `EEex_Error` | 2 | 34 | provided | pathfinding-redux, tweaks | `(str)`×32, `assign`×2 |  |
| `EEex_Resource_GetAt2DALabels` | 2 | 28 | provided | SadoEE, stick-lua-functions | `(var, str, expr)`×14, `(var, str, var)`×5, `(field, str, expr)`×4 |  |
| `EEex_Options_DisplayEntry` | 2 | 14 | provided | SadoEE, bg-eeex-buffbot | `.new`×13, `ref`×1 |  |
| `EEex_Options_Get` | 2 | 13 | provided | SadoEE, bg-eeex-buffbot | `(expr)`×5, `ref`×4, `(var)`×2 |  |
| `EEex_Options_ToggleWidget` | 2 | 12 | provided | SadoEE, bg-eeex-buffbot | `.new`×11, `ref`×1 |  |
| `EEex_RShift` | 2 | 11 | provided | stick-lua-functions, tweaks | `(var, num)`×6, `(field, num)`×5 |  |
| `EEex_Free` | 2 | 10 | provided | SadoEE, chriz-bg-modpack | `(var)`×9, `ref`×1 |  |
| `EEex_CChitin` | 2 | 9 | provided | bg-eeex-buffbot, tweaks | `.TIMER_UPDATES_PER_SECOND`×8, `ref`×1 |  |
| `EEex_Options_Option` | 2 | 9 | provided | SadoEE, bg-eeex-buffbot | `.new`×7, `ref`×1, `._setWorkingValue`×1 |  |
| `EEex_HookShimFunctionMaintainOriginal` | 2 | 8 | unsupported | chriz-bg-modpack, chriz-playable-races | `ref`×7, `(var, num, str, expr)`×1 | x64 asm / hooks / raw memory |
| `EEex_OffsetOf` | 2 | 8 | missing | chriz-bg-rebalance, pathfinding-redux | `ref`×7, `(var)`×1 |  |
| `EEex_Options_ClampedAccessor` | 2 | 8 | provided | SadoEE, bg-eeex-buffbot | `.new`×7, `ref`×1 |  |
| `EEex_Options_Register` | 2 | 8 | provided | SadoEE, bg-eeex-buffbot | `(str, expr)`×6, `ref`×1, `(expr, expr)`×1 |  |
| `EEex_Options_ToggleType` | 2 | 8 | provided | SadoEE, bg-eeex-buffbot | `.new`×7, `ref`×1 |  |
| `EEex_SetBit` | 2 | 8 | provided | chriz-sod-rebalance, tweaks | `(var, num)`×6, `(field, var)`×1, `(field, num)`×1 |  |
| `EEex_WriteUDArgs` | 2 | 8 | provided | stick-lua-functions, tweaks | `(field, var, var)`×6, `(var, var, table)`×2 |  |
| `EEex_ACTIONBAR_TYPE` | 2 | 7 | provided | b-kits, improved-hof | `.FIND_TRAPS`×4, `.THIEVING`×2, `.STEALTH`×1 |  |
| `EEex_Menu_GetItemVariant` | 2 | 7 | missing | SadoEE, chriz-bg-modpack | `(field)`×3, `(var)`×2, `ref`×2 |  |
| `EEex_SetActionbarButton` | 2 | 7 | provided | b-kits, improved-hof | `(num, field)`×7 |  |
| `EEex_Trigger_EvalConditionalStringAsAIBase` | 2 | 7 | provided | bg-eeex-buffbot, chriz-bg-rebalance | `ref`×4, `(str, var)`×2, `(var, var)`×1 |  |
| `EEex_Trigger_ParseConditionalString` | 2 | 7 | provided | SadoEE, tweaks | `(str)`×6, `(var)`×1 |  |
| `EEex_Utility_FreeCPtrList` | 2 | 7 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var)`×4, `ref`×3 |  |
| `EEex_AccessComplexStat` | 2 | 6 | missing | high-power-bg, olvynspells | `(var, str)`×6 |  |
| `EEex_Actionbar_GetOp214ButtonDataItr` | 2 | 6 | provided | tweaks, warlock | `(expr)`×4, `(...)`×1, `(call:EEex_Utility_SelectItr)`×1 |  |
| `EEex_HookAfterRestore` | 2 | 6 | unsupported | high-power-bg, olvynspells | `(call:EEex_Label, num, num, table)`×6 | x64 asm / hooks / raw memory |
| `EEex_ProjectileMutatorList` | 2 | 6 | missing | high-power-bg, olvynspells | `ref`×6 |  |
| `EEex_Utility_FilterItr` | 2 | 6 | provided | tweaks, warlock | `(call:EEex_Utility_ApplyItr, fn(spellResRef))`×4, `(...)`×1, `(call:EEex_Utility_ChainItrs, fn(spellLevel,knownSpellIndex,`×1 |  |
| `EEex_WriteStringAuto` | 2 | 6 | unsupported | high-power-bg, olvynspells | `(str)`×6 | x64 asm / hooks / raw memory |
| `EEex_AIBase_AddScriptingObjectUpdatedListener` | 2 | 5 | missing | bg2-radar-overlay, chriz-bg-modpack | `(var)`×3, `ref`×2 |  |
| `EEex_Actionbar_GetState` | 2 | 5 | provided | SpellMenuExtended, tweaks | `()`×5 |  |
| `EEex_GetActorIDSelected` | 2 | 5 | provided | b-kits, improved-hof | `()`×5 |  |
| `EEex_Menu_InjectTemplateInstance` | 2 | 5 | provided | SadoEE, SpellMenuExtended | `(str, str, num, var, var, var, var)`×2, `(var, var, var, var, var, var, var)`×1, `(str, str, num, expr, expr, num, num)`×1 |  |
| `EEex_Sprite_AddBlockWeaponHitListener` | 2 | 5 | provided | chriz-bg-rebalance, tweaks | `(...)`×3, `(fn(context), expr, expr)`×1, `(fn(args))`×1 |  |
| `EEex_Sprite_GetCastTimer` | 2 | 5 | provided | bg-eeex-buffbot, tweaks | `(var)`×5 |  |
| `EEex_Utility_ApplyItr` | 2 | 5 | provided | tweaks, warlock | `(expr, fn(spellResRef,castType))`×5 |  |
| `EEex_Utility_ChainItrs` | 2 | 5 | provided | tweaks, warlock | `(expr, expr)`×4, `(expr)`×1 |  |
| `EEex_Utility_MutateItr` | 2 | 5 | provided | tweaks, warlock | `(call:EEex_Actionbar_GetOp214ButtonDataItr, fn(buttonData))`×4, `(...)`×1 |  |
| `EEex_WriteStringCache` | 2 | 5 | unsupported | chriz-playable-races, pathfinding-redux | `ref`×2, `(field)`×2, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_Actionbar_SetState` | 2 | 4 | provided | house-rule-tweaks, tweaks | `(num)`×2, `(field)`×2 |  |
| `EEex_Menu_AddBeforeListRendersItemListener` | 2 | 4 | missing | bg-eeex-buffbot, bg2narrator | `ref`×2, `(var, fn(_list,cell))`×1, `(str, var)`×1 |  |
| `EEex_Menu_SetTemplateArea` | 2 | 4 | provided | high-power-bg, olvynspells | `(var, var, field, var, field, nil, field)`×2, `(var, str, field, expr, field, expr, field)`×2 |  |
| `EEex_Sprite_ForAllOfTypeStringInRange` | 2 | 4 | missing | high-power-bg, olvynspells | `(call:EEex_GameObject_Get, str, num, fn(object), bool, bool)`×4 |  |
| `EEex_Sprite_GetCasterLevel` | 2 | 4 | missing | high-power-bg, olvynspells | `(var, field)`×4 |  |
| `EEex_Sprite_GetKnownMageSpellsIterator` | 2 | 4 | provided | SadoEE, chriz-sod-rebalance | `(var)`×2, `(var, num, num)`×1, `ref`×1 |  |
| `EEex_Sprite_GetSpellRES` | 2 | 4 | missing | high-power-bg, olvynspells | `(var)`×4 |  |
| `EEex_WriteU16` | 2 | 4 | provided | SadoEE, chriz-bg-rebalance | `ref`×2, `(var, var)`×1, `(expr, num)`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_HookBeforeConditionalJumpWithLabels` | 2 | 3 | unsupported | chriz-bg-rebalance, stick-lua-functions | `(...)`×2, `(var, num, table, var)`×1 | x64 asm / hooks / raw memory |
| `EEex_Object_EvalStringAsAIBase` | 2 | 3 | provided | chriz-bg-rebalance, chriz-sod-rebalance | `(str, var)`×3 |  |
| `EEex_Options_AddTab` | 2 | 3 | provided | SadoEE, bg-eeex-buffbot | `(str, fn())`×2, `ref`×1 |  |
| `EEex_Utility_NewScope` | 2 | 3 | provided | SpellMenuExtended, tweaks | `(fn(), expr, expr)`×1, `(fn(), expr, expr, expr, expr)`×1, `(fn(), expr)`×1 |  |
| `EEex_Action_AddEnabledSpriteStartedActionListener` | 2 | 2 | missing | high-power-bg, olvynspells | `(var, var)`×2 |  |
| `EEex_Actionbar_AddButtonsUpdatedListener` | 2 | 2 | provided | SadoEE, tweaks | `(fn(), expr)`×1, `(var)`×1 |  |
| `EEex_HookConditionalJumpWithLabels` | 2 | 2 | unsupported | pathfinding-redux, stick-lua-functions | `assign`×1, `(var, num, table, table, call:EEex_FlattenTable)`×1 | x64 asm / hooks / raw memory |
| `EEex_InitLuaBindings` | 2 | 2 | missing | bgee-graphics-enhanced, ie-enhancer | `(str)`×2 |  |
| `EEex_Menu_AddWindowSizeChangedListener` | 2 | 2 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var)`×1, `(expr)`×1 |  |
| `EEex_Menu_GetArea` | 2 | 2 | provided | SadoEE, bg-eeex-buffbot | `(str)`×2 |  |
| `EEex_Once` | 2 | 2 | provided | SpellMenuExtended, pathfinding-redux | `(str, fn())`×1, `assign`×1 |  |
| `EEex_Read8` | 2 | 2 | provided | high-power-bg, olvynspells | `(var)`×2 |  |
| `EEex_Sprite_AddQuickListNotifyRemovedListener` | 2 | 2 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var)`×1, `(concat)`×1 |  |
| `EEex_Sprite_GetInPortraitID` | 2 | 2 | provided | high-power-bg, olvynspells | `(var)`×2 |  |
| `EEex_Stats_FirstExtendedStatID` | 2 | 2 | provided | epic-thieving, house-rule-tweaks | `ref`×2 |  |
| `EEex_ApplyEffectToActor` | 1 | 214 | missing | improved-hof | `(var, table)`×204, `(...)`×10 |  |
| `EEex_IsBitUnset` | 1 | 87 | provided | tweaks | `(var, num)`×65, `(field, num)`×17, `(expr, num)`×5 |  |
| `EEex_WriteDword` | 1 | 67 | missing | improved-hof | `(expr, num)`×27, `(expr, var)`×15, `(expr, expr)`×10 |  |
| `EEex_GetActorShare` | 1 | 66 | missing | improved-hof | `(var)`×65, `(call:EEex_GetActorIDPortrait)`×1 |  |
| `EEex_IsBitSet` | 1 | 63 | provided | tweaks | `(field, num)`×31, `(var, num)`×24, `(expr, num)`×6 |  |
| `EEex_ReadWord` | 1 | 62 | missing | improved-hof | `(expr, num)`×52, `(call:EEex_ReadDword, num)`×7, `(call:EEex_GetSpellData, num)`×3 |  |
| `EEex_LoadLibrary` | 1 | 36 | missing | chriz-bg-modpack | `(field)`×30, `ref`×6 |  |
| `EEex_WriteWord` | 1 | 36 | unsupported | improved-hof | `(expr, expr)`×15, `(expr, var)`×12, `(expr, num)`×5 | x64 asm / hooks / raw memory |
| `EEex_IterateActorEffects` | 1 | 33 | missing | improved-hof | `(var, fn(eData))`×27, `(...)`×4, `(var, fn(iData))`×1 |  |
| `EEex_Projectile_DecodeSource` | 1 | 28 | provided | tweaks | `.CGameSprite_Spell`×6, `.CGameSprite_SpellPoint`×6, `.CGameAIBase_ForceSpell`×6 |  |
| `EEex_GetProcAddressInternal` | 1 | 24 | missing | chriz-bg-modpack | `(var, var)`×20, `(expr, var)`×2, `ref`×2 |  |
| `EEex_GetActorName` | 1 | 23 | provided | improved-hof | `(var)`×23 |  |
| `EEex_GetGameTick` | 1 | 23 | provided | improved-hof | `()`×23 |  |
| `EEex_LuaDecode_Object` | 1 | 23 | provided | tweaks | `ref`×13, `.m_typeAI`×5, `.m_pos`×2 |  |
| `EEex_ReadByte` | 1 | 20 | missing | improved-hof | `(expr, num)`×16, `(call:EEex_GetSpellData, num)`×3, `(call:EEex_GetActorShare, num)`×1 |  |
| `EEex_Resource_KitIDSToSymbol` | 1 | 20 | provided | tweaks | `(field)`×17, `(expr)`×3 |  |
| `EEex_ReadSignedWord` | 1 | 19 | missing | improved-hof | `(expr, num)`×19 |  |
| `EEex_Resource_ItemCategoryIDSToSymbol` | 1 | 18 | provided | tweaks | `(field)`×11, `(expr)`×7 |  |
| `EEex_HookBeforeAndAfterCallWithLabels` | 1 | 17 | unsupported | pathfinding-redux | `(expr, var, field, field)`×12, `(expr, var, call:EEex_FlattenTable, call:EEex_FlattenTable)`×4, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_Sprite_GetCharacterIndex` | 1 | 16 | provided | chriz-bg-modpack | `(var)`×16 |  |
| `EEex_Memcpy` | 1 | 14 | unsupported | pathfinding-redux | `ref`×5, `(var, var, num)`×4, `(var, var, expr)`×4 | x64 asm / hooks / raw memory |
| `EEex_Projectile_AddEffectSource` | 1 | 14 | provided | tweaks | `.CGameSprite_Spell`×3, `.CGameSprite_SpellPoint`×3, `.CGameAIBase_ForceSpell`×3 |  |
| `EEex_StoreBytesAssembly` | 1 | 14 | missing | chriz-bg-modpack | `(var, var)`×6, `(expr, field)`×4, `ref`×2 |  |
| `EEex_GetSpellData` | 1 | 13 | missing | improved-hof | `(var)`×13 |  |
| `EEex_Menu_AfterMainFileLoadedListeners` | 1 | 12 | missing | chriz-bg-modpack | `ref`×10, `[]`×2 |  |
| `EEex_RunWithStack` | 1 | 12 | missing | pathfinding-redux | `(num, fn(storage), expr)`×4, `ref`×4, `(...)`×4 |  |
| `EEex_Area_GetAllOfTypeInRange` | 1 | 11 | provided | tweaks | `(field, field, field, field, num, bool, nil, nil)`×9, `(var, field, field, field, num, bool, nil, nil)`×2 |  |
| `EEex_GetActorAllegiance` | 1 | 11 | provided | improved-hof | `(var)`×11 |  |
| `EEex_SetActionID` | 1 | 11 | missing | improved-hof | `(var, num)`×10, `(var, var)`×1 |  |
| `EEex_HookReplaceFunctionMaintainOriginal` | 1 | 10 | unsupported | chriz-bg-modpack | `ref`×4, `(var, var, str, var)`×4, `(field, field, str, field)`×2 | x64 asm / hooks / raw memory |
| `EEex_Memset` | 1 | 10 | missing | pathfinding-redux | `ref`×5, `(var, num, expr)`×4, `assign`×1 |  |
| `EEex_Sprite_Private_MarshalHandlers` | 1 | 10 | missing | chriz-bg-modpack | `[]`×6, `ref`×2, `.CBMBank`×2 |  |
| `EEex_GetActorSpellRES` | 1 | 9 | missing | improved-hof | `(var)`×9 |  |
| `EEex_IsMaskSet` | 1 | 9 | provided | tweaks | `(field, field)`×7, `(field, num)`×2 |  |
| `EEex_TryGetUDAux` | 1 | 9 | missing | chriz-bg-rebalance | `(var)`×6, `ref`×2, `assign`×1 |  |
| `EEex_UnsetBit` | 1 | 9 | provided | tweaks | `(var, num)`×7, `(field, num)`×2 |  |
| `EEex_Action_Private_SpriteStartedActionListeners` | 1 | 8 | missing | chriz-bg-modpack | `ref`×8 |  |
| `EEex_GetActorAnimation` | 1 | 8 | missing | improved-hof | `(var)`×8 |  |
| `EEex_Keybinds_Private_Definitions` | 1 | 8 | missing | chriz-bg-modpack | `ref`×4, `.CBMBank_Status`×4 |  |
| `EEex_Opcode_AddDeferredListsResolvedListener` | 1 | 8 | missing | chriz-bg-rebalance | `ref`×6, `(var)`×1, `assign`×1 |  |
| `EEex_GetActionID` | 1 | 7 | missing | improved-hof | `(var)`×7 |  |
| `EEex_HookRemoveCallWithLabels` | 1 | 7 | unsupported | pathfinding-redux | `(expr, table, expr)`×4, `(expr, table, var)`×2, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_LabelDefault` | 1 | 7 | missing | chriz-playable-races | `ref`×4, `(str, nil)`×3 |  |
| `EEex_AddActionHookOpcode` | 1 | 6 | missing | improved-hof | `(str, fn(originatingEffectData,actionData,creatureData))`×3, `(...)`×3 |  |
| `EEex_AllocNear` | 1 | 6 | provided | SadoEE | `(expr)`×4, `(num)`×2 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_AlterActorEffect` | 1 | 6 | missing | improved-hof | `(var, table, table, num)`×6 |  |
| `EEex_CInfGame` | 1 | 6 | missing | pathfinding-redux | `.m_charactersPortrait`×5, `ref`×1 |  |
| `EEex_Menu_StoreTemplateInstance` | 1 | 6 | provided | SpellMenuExtended | `(str, str, field, str)`×4, `(str, str, field, concat)`×1, `(str, str, field, var)`×1 |  |
| `EEex_Resource_GetItemAbility` | 1 | 6 | provided | tweaks | `(var, num)`×5, `(field, field)`×1 |  |
| `EEex_SetLuaRegistryIndex` | 1 | 6 | missing | chriz-bg-modpack | `(field, field)`×4, `ref`×2 |  |
| `EEex_Sprite_GetAllOfTypeInRange` | 1 | 6 | provided | tweaks | `(var, field, expr, nil, nil, nil)`×4, `(var, field, num, nil, nil, nil)`×2 |  |
| `EEex_Sprite_GetKnownInnateSpellsIterator` | 1 | 6 | provided | bg-eeex-buffbot | `(var)`×4, `ref`×1, `.nil`×1 |  |
| `EEex_GetActorIDPortrait` | 1 | 5 | provided | improved-hof | `(num)`×3, `(var)`×2 |  |
| `EEex_Sprite_GetLocalString` | 1 | 5 | provided | SadoEE | `(var, str)`×5 |  |
| `EEex_AddActionbarListener` | 1 | 4 | provided | b-kits | `(var)`×4 |  |
| `EEex_AddResetListener` | 1 | 4 | provided | b-kits | `(fn())`×4 |  |
| `EEex_CBaldurChitin` | 1 | 4 | missing | pathfinding-redux | `.m_pObjectGame`×4 |  |
| `EEex_ClearAssemblyLabel` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(var)`×2 |  |
| `EEex_FunctionLog` | 1 | 4 | provided | bg2-radar-overlay | `(expr)`×2, `(str)`×2 |  |
| `EEex_GameState_DestroyedListeners` | 1 | 4 | missing | chriz-bg-modpack | `ref`×4 |  |
| `EEex_GameState_Private_AlreadyInitialized` | 1 | 4 | missing | chriz-bg-modpack | `ref`×4 |  |
| `EEex_GetLuaRegistryIndex` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(field)`×2 |  |
| `EEex_HookAfterCall` | 1 | 4 | unsupported | chriz-bg-modpack | `ref`×2, `(var, expr)`×2 | x64 asm / hooks / raw memory |
| `EEex_IsImmuneToOpcode` | 1 | 4 | missing | improved-hof | `(var, num)`×2, `(var, var)`×2 |  |
| `EEex_Keybinds_Get` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(str)`×2 |  |
| `EEex_Keybinds_Reset` | 1 | 4 | missing | chriz-bg-modpack | `(str)`×2, `ref`×2 |  |
| `EEex_Keybinds_Update` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(str, table{callback,fireType,keys,modifierKeys})`×2 |  |
| `EEex_Menu_AddBeforeMainFileLoadedListener` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(var)`×2 |  |
| `EEex_MessageBox` | 1 | 4 | missing | chriz-bg-modpack | `ref`×4 |  |
| `EEex_OpenLuaBindings` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(str)`×2 |  |
| `EEex_Resource_Free2DA` | 1 | 4 | provided | SadoEE | `(var)`×4 |  |
| `EEex_Resource_Get2DARowTableIterator` | 1 | 4 | provided | chriz-bg-rebalance | `(var, bool)`×2, `ref`×2 |  |
| `EEex_Sprite_AddAlterBaseWeaponDamageListener` | 1 | 4 | provided | tweaks | `(...)`×2, `(fn(context))`×2 |  |
| `EEex_Sprite_GetAllSelected` | 1 | 4 | provided | SadoEE | `()`×3, `ref`×1 |  |
| `EEex_Sprite_GetKnownInnateSpellsWithAbilityIterator` | 1 | 4 | provided | bg-eeex-buffbot | `(var)`×2, `ref`×2 |  |
| `EEex_Sprite_GetPersonalSpace` | 1 | 4 | provided | tweaks | `(var)`×4 |  |
| `EEex_Sprite_LoadedListeners` | 1 | 4 | missing | chriz-bg-modpack | `ref`×4 |  |
| `EEex_Sprite_SetLocalString` | 1 | 4 | provided | SadoEE | `(var, str, expr)`×2, `(var, str, field)`×1, `(var, str, var)`×1 |  |
| `EEex_Trigger_EvalScriptFileConditionalAsAIBase` | 1 | 4 | provided | SadoEE | `(field, call:EEex_Sprite_GetInPortrait)`×2, `(var, var)`×1, `(field, var)`×1 |  |
| `EEex_Utility_MapItrValues` | 1 | 4 | provided | warlock | `(num, call:EEex_Utility_ChainItrs)`×4 |  |
| `EEex_WithinCyclicRange` | 1 | 4 | missing | improved-hof | `(var, var, var, num, num)`×2, `(var, var, expr, num, num)`×2 |  |
| `EEex_Area_GetVariableInt` | 1 | 3 | provided | SadoEE | `(var, str)`×3 |  |
| `EEex_Call` | 1 | 3 | missing | improved-hof | `(call:EEex_Label, table, var, num)`×3 |  |
| `EEex_DemandResData` | 1 | 3 | missing | improved-hof | `(call:EEex_GetActorSpellRES, str)`×1, `(var, str)`×1, `(concat, str)`×1 |  |
| `EEex_GetActionPointX` | 1 | 3 | missing | improved-hof | `(var)`×3 |  |
| `EEex_GetActionPointY` | 1 | 3 | missing | improved-hof | `(var)`×3 |  |
| `EEex_Menu_GetItemArea` | 1 | 3 | provided | bg-eeex-buffbot | `(str)`×2, `ref`×1 |  |
| `EEex_Options_Private_Storage` | 1 | 3 | missing | bg-eeex-buffbot | `ref`×3 |  |
| `EEex_Options_Widget` | 1 | 3 | missing | bg-eeex-buffbot | `ref`×3 |  |
| `EEex_Actionbar_GetLastState` | 1 | 2 | provided | tweaks | `()`×2 |  |
| `EEex_Area_GetCurrent` | 1 | 2 | missing | bg-eeex-buffbot | `()`×2 |  |
| `EEex_Area_SetVariableInt` | 1 | 2 | provided | SadoEE | `(var, str, num)`×2 |  |
| `EEex_Assembly_Private_MacroSwitch` | 1 | 2 | missing | pathfinding-redux | `[]`×2 |  |
| `EEex_CInfButtonArray` | 1 | 2 | provided | SpellMenuExtended | `.SetQuickSlot`×2 |  |
| `EEex_GameObject_GetCurrentArea` | 1 | 2 | missing | bg-eeex-buffbot | `()`×2 |  |
| `EEex_GameState_GetCurrentArea` | 1 | 2 | missing | bg-eeex-buffbot | `()`×2 |  |
| `EEex_GetActorAreaSize` | 1 | 2 | missing | improved-hof | `(var)`×2 |  |
| `EEex_GetActorDirection` | 1 | 2 | provided | improved-hof | `(var)`×2 |  |
| `EEex_GetActorGeneral` | 1 | 2 | provided | improved-hof | `(var)`×2 |  |
| `EEex_GetActorLocation` | 1 | 2 | provided | improved-hof | `(var)`×2 |  |
| `EEex_GetActorScriptName` | 1 | 2 | provided | improved-hof | `(var)`×2 |  |
| `EEex_GetChitin` | 1 | 2 | missing | bg-eeex-buffbot | `()`×2 |  |
| `EEex_GetCurrentArea` | 1 | 2 | missing | bg-eeex-buffbot | `()`×2 |  |
| `EEex_HookConditionalJumpOnSuccess` | 1 | 2 | unsupported | chriz-bg-rebalance | `(var, num, var)`×1, `[]`×1 | x64 asm / hooks / raw memory |
| `EEex_Keybinds_FireType` | 1 | 2 | missing | chriz-bg-modpack | `.UP`×2 |  |
| `EEex_Menu_BeforeMainFileLoadedListeners` | 1 | 2 | missing | chriz-bg-modpack | `ref`×2 |  |
| `EEex_Menu_GetItem` | 1 | 2 | provided | bg-eeex-buffbot | `ref`×1, `(str)`×1 |  |
| `EEex_Menu_GetMousePos` | 1 | 2 | provided | SadoEE | `()`×2 |  |
| `EEex_Options_NumberLuaStorage` | 1 | 2 | provided | SadoEE | `.new`×2 |  |
| `EEex_Options_Private_FindItemByText` | 1 | 2 | provided | SadoEE | `ref`×1, `(var, expr)`×1 |  |
| `EEex_PlayerCastResrefNoDec` | 1 | 2 | provided | SpellMenuExtended | `ref`×2 |  |
| `EEex_ReadS16` | 1 | 2 | missing | SadoEE | `ref`×1, `(expr)`×1 |  |
| `EEex_Resource_GetCItemAbility` | 1 | 2 | provided | tweaks | `(var, num)`×1, `(field, expr)`×1 |  |
| `EEex_Resource_IterateUnpackedIDSEntries` | 1 | 2 | provided | bg-eeex-buffbot | `(var, fn(id,line,start), expr)`×1, `(var, fn(id,line,start))`×1 |  |
| `EEex_Split` | 1 | 2 | missing | pathfinding-redux | `assign`×1, `(var)`×1 |  |
| `EEex_Sprite_FallbackMarshalStorage` | 1 | 2 | missing | chriz-bg-modpack | `ref`×2 |  |
| `EEex_Sprite_GetCasterLevelForSpell` | 1 | 2 | provided | tweaks | `(var, var, bool)`×1, `(var, expr, bool)`×1 |  |
| `EEex_Sprite_IterateSelected` | 1 | 2 | provided | bg-eeex-buffbot | `(fn(sprite), concat)`×1, `.NOT`×1 |  |
| `EEex_WriteByte` | 1 | 2 | unsupported | improved-hof | `(expr, expr)`×2 | x64 asm / hooks / raw memory |
| `EEex_Actionbar_IsThievingHotkeyOpeningSpecialAbilities` | 1 | 1 | partial | SpellMenuExtended | `()`×1 | EEex_Actionbar.lua: True while the THIEVING hotkey opened the special abilities list (thief kind not on the main bar). IEX does not track that hotkey yet: alway |
| `EEex_Actionbar_Private_ButtonsUpdatedListeners` | 1 | 1 | provided | SadoEE | `ref`×1 |  |
| `EEex_Actionbar_RestoreLastState` | 1 | 1 | provided | SpellMenuExtended | `()`×1 |  |
| `EEex_Assembly_Private_FindOffsetOf` | 1 | 1 | missing | pathfinding-redux | `.?`×1 |  |
| `EEex_Assembly_Private_InitState` | 1 | 1 | missing | pathfinding-redux | `(var)`×1 |  |
| `EEex_BNot` | 1 | 1 | provided | SadoEE | `(num)`×1 |  |
| `EEex_DamageAbsorption` | 1 | 1 | missing | olvynspells | `(var, var)`×1 |  |
| `EEex_DerivedStats_DisabledButtonType` | 1 | 1 | provided | SpellMenuExtended | `.BUTTON_THIEVING`×1 |  |
| `EEex_DistanceToMultiple` | 1 | 1 | missing | pathfinding-redux | `assign`×1 |  |
| `EEex_FreeUD` | 1 | 1 | provided | bg-eeex-buffbot | `(var)`×1 |  |
| `EEex_GameObject_IsSpriteID` | 1 | 1 | provided | diablofication | `(var)`×1 |  |
| `EEex_GameState_GetGlobalString` | 1 | 1 | provided | SadoEE | `(str)`×1 |  |
| `EEex_GameState_SetGlobalString` | 1 | 1 | provided | SadoEE | `(str, var)`×1 |  |
| `EEex_GameState_TogglePause` | 1 | 1 | missing | chriz-bg-rebalance | `(bool, bool, bool, num, bool)`×1 |  |
| `EEex_GetActionTarget` | 1 | 1 | missing | improved-hof | `(var)`×1 |  |
| `EEex_GetActorModalState` | 1 | 1 | provided | improved-hof | `(var)`×1 |  |
| `EEex_GetActorMovementRate` | 1 | 1 | missing | improved-hof | `(var, bool)`×1 |  |
| `EEex_GetActorRace` | 1 | 1 | provided | improved-hof | `(var)`×1 |  |
| `EEex_GetActorRequiredDirection` | 1 | 1 | missing | improved-hof | `(var, var, var)`×1 |  |
| `EEex_GetSpellName` | 1 | 1 | missing | improved-hof | `(expr)`×1 |  |
| `EEex_GetUTBaseclassMetadata` | 1 | 1 | missing | pathfinding-redux | `assign`×1 |  |
| `EEex_HookConditionalJumpOnSuccessWithLabels` | 1 | 1 | unsupported | stick-lua-functions | `(expr, num, table, call:EEex_FlattenTable)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookIntegrityWatchdog_IgnoreStackSizes` | 1 | 1 | unsupported | SadoEE | `(var, table)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookIntegrityWatchdog_Load` | 1 | 1 | unsupported | pathfinding-redux | `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_IsImmuneToSpellLevel` | 1 | 1 | missing | improved-hof | `(var, var, bool)`×1 |  |
| `EEex_IsMaskUnset` | 1 | 1 | provided | tweaks | `(field, field)`×1 |  |
| `EEex_IterateActorIDs` | 1 | 1 | missing | improved-hof | `(var, fn(actorID))`×1 |  |
| `EEex_Key_AddReleasedListener` | 1 | 1 | provided | tweaks | `(fn(key), expr, expr)`×1 |  |
| `EEex_LightUDToPtr` | 1 | 1 | missing | bg-eeex-buffbot | `(var)`×1 |  |
| `EEex_Menu_AddTranslationLoadedListener` | 1 | 1 | provided | SadoEE | `(var)`×1 |  |
| `EEex_Menu_BeforeListRendersItemListeners` | 1 | 1 | missing | bg2narrator | `[]`×1 |  |
| `EEex_Menu_BeforeUIItemRenderListeners` | 1 | 1 | missing | bg2narrator | `[]`×1 |  |
| `EEex_Menu_CreateTemplateFromCopy` | 1 | 1 | provided | SpellMenuExtended | `(str, var, var)`×1 |  |
| `EEex_Menu_DestroyAllTemplates` | 1 | 1 | provided | SpellMenuExtended | `(var)`×1 |  |
| `EEex_Menu_GetUIMenuArea` | 1 | 1 | provided | SadoEE | `(var)`×1 |  |
| `EEex_Menu_IsCursorWithinRect` | 1 | 1 | provided | SadoEE | `(expr, expr, var, var)`×1 |  |
| `EEex_Object_AddToArea` | 1 | 1 | missing | SadoEE | `(var, field, field, field)`×1 |  |
| `EEex_Options_Close` | 1 | 1 | provided | SadoEE | `ref`×1 |  |
| `EEex_Options_Set` | 1 | 1 | provided | SadoEE | `ref`×1 |  |
| `EEex_PreprocessAssembly` | 1 | 1 | missing | pathfinding-redux | `assign`×1 |  |
| `EEex_PreprocessAssemblyStr` | 1 | 1 | missing | pathfinding-redux | `ref`×1 |  |
| `EEex_ProcessClericMemorization` | 1 | 1 | missing | improved-hof | `(...)`×1 |  |
| `EEex_ProcessWizardMemorization` | 1 | 1 | missing | improved-hof | `(...)`×1 |  |
| `EEex_Projectile_RegisterGlobalMutator` | 1 | 1 | missing | chriz-bg-rebalance | `ref`×1 |  |
| `EEex_Resource_GetAt2DAPoint` | 1 | 1 | provided | tweaks | `(var, num, var)`×1 |  |
| `EEex_Resource_GetSpellAbility` | 1 | 1 | provided | SadoEE | `(var, num)`×1 |  |
| `EEex_Resource_GetSpellAbilityForLevel` | 1 | 1 | provided | tweaks | `(var, var)`×1 |  |
| `EEex_RoundUp` | 1 | 1 | missing | pathfinding-redux | `assign`×1 |  |
| `EEex_RunWithAssemblyLabels` | 1 | 1 | missing | pathfinding-redux | `assign`×1 |  |
| `EEex_SetActionPointX` | 1 | 1 | missing | improved-hof | `(var, var)`×1 |  |
| `EEex_SetActionPointY` | 1 | 1 | missing | improved-hof | `(var, var)`×1 |  |
| `EEex_Sprite_AddSpellDisableStateChangedListener` | 1 | 1 | provided | SpellMenuExtended | `(var)`×1 |  |
| `EEex_Sprite_ApplyEffect` | 1 | 1 | missing | chriz-bg-rebalance | `assign`×1 |  |
| `EEex_Sprite_DisplayTextRef` | 1 | 1 | missing | SadoEE | `(var, var, table{overHead})`×1 |  |
| `EEex_Sprite_GetKnownMageSpellsWithAbilityIterator` | 1 | 1 | provided | bg-eeex-buffbot | `ref`×1 |  |
| `EEex_Sprite_GetKnownPriestSpellsIterator` | 1 | 1 | provided | SadoEE | `ref`×1 |  |
| `EEex_Sprite_GetKnownPriestSpellsWithAbilityIterator` | 1 | 1 | provided | bg-eeex-buffbot | `ref`×1 |  |
| `EEex_Sprite_GetLauncher` | 1 | 1 | provided | tweaks | `(var, expr)`×1 |  |
| `EEex_Sprite_GetModalState` | 1 | 1 | provided | tweaks | `(var)`×1 |  |
| `EEex_Sprite_GetModalTimer` | 1 | 1 | provided | tweaks | `(var)`×1 |  |
| `EEex_UDToLightUD` | 1 | 1 | provided | SpellMenuExtended | `(var)`×1 |  |
| `EEex_Utility_SelectItr` | 1 | 1 | provided | tweaks | `(num, call:EEex_Utility_FilterItr)`×1 |  |
| `EEex_Utility_TryFinally` | 1 | 1 | provided | tweaks | `(...)`×1 |  |

## EEex internal hook functions the mod replaces (10)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `EEex_Opcode_Private_ScreenEffectsGlobalFunctions` | 2 | 6 | missing | high-power-bg, olvynspells | `assign`×2, `[]`×2, `ref`×2 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_OnAddEffectToProjectile` | 2 | 4 | missing | high-power-bg, olvynspells | `(var, var, var)`×2, `ref`×2 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_OnDecodeProjectile` | 2 | 4 | missing | high-power-bg, olvynspells | `(var)`×2, `ref`×2 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_OnPostProjectileCreation` | 2 | 4 | missing | high-power-bg, olvynspells | `(var, var)`×2, `ref`×2 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_Actionbar_Hook_HasFullThieving` | 2 | 3 | missing | aura, skills-and-abilities | `(var)`×3 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_Sprite_Hook_OnDestruct` | 2 | 2 | missing | high-power-bg, olvynspells | `(var)`×2 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_Opcode_Hook_OnAfterSwingCheckedOp248` | 1 | 12 | missing | stick-lua-functions | `ref`×6, `(var, var, var)`×6 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_Key_Hook_AfterEventsPoll` | 1 | 9 | provided | SadoEE | `ref`×6, `assign`×3 | IEX defines it: check IEX calls it at the same moment |
| `EEex_Menu_Hook_BeforeListRenderingItem` | 1 | 2 | missing | bg2narrator | `ref`×1, `assign`×1 | EEex internal hook the mod replaces; IEX never calls it |
| `EEex_Menu_Hook_OnBeforeUIItemRender` | 1 | 2 | missing | bg2narrator | `ref`×1, `assign`×1 | EEex internal hook the mod replaces; IEX never calls it |

## Listeners registered (28)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `EEex_Actionbar_AddListener` | 11 | 44 | provided | Bardic-Wonders, Shadow-Magic, SpellMenuExtended, The-Artisan-s-Kitpack, aura, high-power-bg, house-rule-tweaks, olvynspells, skills-and-abilities, tweaks, warlock | `(var)`×43, `(fn(config,state))`×1 |  |
| `EEex_GameState_AddInitializedListener` | 8 | 57 | provided | SadoEE, bg2-radar-overlay, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, pathfinding-redux, tweaks | `(var)`×19, `ref`×10, `(fn(), concat)`×8 |  |
| `EEex_Action_AddSpriteStartedActionListener` | 8 | 42 | provided | SadoEE, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux, tweaks | `(fn(sprite,action))`×13, `ref`×10, `(var)`×6 |  |
| `EEex_Key_AddPressedListener` | 7 | 13 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, iui, pathfinding-redux, tweaks | `(fn(key), concat)`×4, `(var)`×3, `(fn(key))`×3 |  |
| `EEex_GameState_AddDestroyedListener` | 6 | 18 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells | `ref`×6, `(fn())`×5, `(var)`×3 |  |
| `EEex_Sprite_AddLoadedListener` | 4 | 33 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-playable-races | `(fn())`×16, `ref`×7, `(fn(sprite), concat)`×3 |  |
| `EEex_Menu_AddMainFileLoadedListener` | 4 | 26 | provided | SadoEE, SpellMenuExtended, bg2-radar-overlay, eeex-remote-console | `(fn())`×22, `(var)`×1, `(fn(), expr)`×1 |  |
| `EEex_Menu_AddAfterMainFileLoadedListener` | 4 | 20 | provided | bg-eeex-buffbot, chriz-bg-modpack, chriz-playable-races, eeex-remote-console | `ref`×11, `(var)`×4, `(expr)`×2 |  |
| `EEex_Menu_AddAfterMainFileReloadedListener` | 3 | 22 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack | `(var)`×16, `(fn())`×4, `ref`×2 |  |
| `EEex_Menu_AddBeforeUIItemRenderListener` | 3 | 13 | provided | SpellMenuExtended, bg-eeex-buffbot, bg2narrator | `(str, var)`×10, `ref`×2, `(var, fn(it))`×1 |  |
| `EEex_Sprite_AddQuickListCountsResetListener` | 3 | 8 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance | `ref`×3, `(var)`×2, `(concat)`×1 |  |
| `EEex_Sprite_AddQuickListsCheckedListener` | 3 | 8 | provided | SpellMenuExtended, bg-eeex-buffbot, tweaks | `(fn(sprite,resref,changeAmount))`×3, `(...)`×3, `(var)`×1 |  |
| `EEex_Opcode_AddListsResolvedListener` | 2 | 94 | provided | chriz-bg-rebalance, tweaks | `(...)`×49, `(fn(sprite))`×20, `ref`×16 |  |
| `EEex_AIBase_AddScriptingObjectUpdatedListener` | 2 | 5 | missing | bg2-radar-overlay, chriz-bg-modpack | `(var)`×3, `ref`×2 |  |
| `EEex_Sprite_AddBlockWeaponHitListener` | 2 | 5 | provided | chriz-bg-rebalance, tweaks | `(...)`×3, `(fn(context), expr, expr)`×1, `(fn(args))`×1 |  |
| `EEex_Menu_AddBeforeListRendersItemListener` | 2 | 4 | missing | bg-eeex-buffbot, bg2narrator | `ref`×2, `(var, fn(_list,cell))`×1, `(str, var)`×1 |  |
| `EEex_Action_AddEnabledSpriteStartedActionListener` | 2 | 2 | missing | high-power-bg, olvynspells | `(var, var)`×2 |  |
| `EEex_Actionbar_AddButtonsUpdatedListener` | 2 | 2 | provided | SadoEE, tweaks | `(fn(), expr)`×1, `(var)`×1 |  |
| `EEex_Menu_AddWindowSizeChangedListener` | 2 | 2 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var)`×1, `(expr)`×1 |  |
| `EEex_Sprite_AddQuickListNotifyRemovedListener` | 2 | 2 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var)`×1, `(concat)`×1 |  |
| `EEex_Opcode_AddDeferredListsResolvedListener` | 1 | 7 | missing | chriz-bg-rebalance | `ref`×6, `(var)`×1 |  |
| `EEex_AddActionbarListener` | 1 | 4 | provided | b-kits | `(var)`×4 |  |
| `EEex_AddResetListener` | 1 | 4 | provided | b-kits | `(fn())`×4 |  |
| `EEex_Menu_AddBeforeMainFileLoadedListener` | 1 | 4 | missing | chriz-bg-modpack | `ref`×2, `(var)`×2 |  |
| `EEex_Sprite_AddAlterBaseWeaponDamageListener` | 1 | 4 | provided | tweaks | `(...)`×2, `(fn(context))`×2 |  |
| `EEex_Key_AddReleasedListener` | 1 | 1 | provided | tweaks | `(fn(key), expr, expr)`×1 |  |
| `EEex_Menu_AddTranslationLoadedListener` | 1 | 1 | provided | SadoEE | `(var)`×1 |  |
| `EEex_Sprite_AddSpellDisableStateChangedListener` | 1 | 1 | provided | SpellMenuExtended | `(var)`×1 |  |

## Engine-object methods (297)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `getName` | 10 | 44 | provided | SadoEE, bg-eeex-buffbot, bg2narrator, bubb-infinityui, eeex-remote-console, iui, skills-and-abilities, tactics-remix, tweaks, xgt-xp-gain | `()`×44 | class CGameObject/CGameSprite |
| `get` | 9 | 596 | provided | SadoEE, bg-eeex-buffbot, bg2narrator, bubb-infinityui, chriz-bg-modpack, chriz-playable-races, iui, stick-lua-functions, tweaks | `()`×446, `(var)`×94, `(num)`×28 | class ?/CAIAction/CBaldurChitin/CGameArea/CGameEffect/CGameObject/CGameSprite/CInfGame/CItem |
| `GetActiveEngine` | 7 | 478 | tolua | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, high-power-bg, iui, olvynspells | `()`×478 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `Eval` | 7 | 77 | tolua | bubb-infinityui, diablofication, eet-tweaks, high-power-bg, improved-hof, iui, olvynspells | `(str, var)`×33, `(str, num)`×24, `(str)`×18 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `isSprite` | 6 | 16 | provided | SpellMenuExtended, bubb-infinityui, chriz-bg-rebalance, high-power-bg, iui, olvynspells | `()`×10, `(bool)`×6 | class CGameObject |
| `CheckIfPaused` | 6 | 15 | tolua | SadoEE, SpellMenuExtended, bubb-infinityui, high-power-bg, iui, olvynspells | `()`×15 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getStat` | 5 | 93 | provided | bg-eeex-buffbot, bubb-infinityui, iui, skills-and-abilities, tactics-remix | `(var)`×75, `(num)`×17, `(field)`×1 | class CGameSprite |
| `getUD` | 5 | 19 | unknown | SadoEE, SpellMenuExtended, bg-eeex-buffbot, pathfinding-redux, tweaks | `(str)`×19 | class ?; receiver class not inferred (mod code or engine object) |
| `getDimensions` | 5 | 14 | provided | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, tweaks | `()`×14 | class ? |
| `GetButtonType` | 4 | 103 | tolua | SpellMenuExtended, bubb-infinityui, iui, tweaks | `(num)`×96, `(var)`×7 | class CButtonData; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getActiveStats` | 4 | 74 | provided | SpellMenuExtended, high-power-bg, olvynspells, tweaks | `()`×74 | class CGameObject/CGameSprite |
| `TogglePauseGame` | 4 | 46 | provided | SadoEE, SpellMenuExtended, bubb-infinityui, iui | `(bool)`×45, `(bool, bool, num, bool, bool)`×1 | class CScreenWorld |
| `set` | 4 | 43 | provided | SadoEE, chriz-playable-races, stick-lua-functions, tweaks | `(str)`×9, `(var, nil)`×8, `(var, var)`×8 | class ?/CGameEffect/CGameObject/CGameSprite/CItem |
| `getAbility` | 4 | 31 | provided | bg-eeex-buffbot, bubb-infinityui, iui, tweaks | `(num)`×27, `(var)`×2, `(field)`×2 | class CItem |
| `getReference` | 4 | 24 | unknown | bg-eeex-buffbot, chriz-bg-modpack, stick-lua-functions, tweaks | `(expr)`×15, `(num)`×5, `(var)`×3 | class ?/CGameObject; on CGameObject objects; receiver class not inferred (mod code or engine object) |
| `getAtLabels` | 4 | 22 | provided | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races | `(str, var)`×16, `(expr, field)`×3, `(expr, var)`×1 | class ? |
| `getRowLabel` | 4 | 12 | provided | bg-eeex-buffbot, chriz-bg-modpack, chriz-playable-races, tweaks | `(var)`×12 | class ? |
| `OnCancelButtonClick` | 3 | 357 | tolua | SadoEE, bubb-infinityui, iui | `()`×357 | class ?/CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDoneButtonClick` | 3 | 305 | tolua | SadoEE, bubb-infinityui, iui | `()`×305 | class ?/CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `applyEffect` | 3 | 256 | provided | chriz-sod-rebalance, tweaks, xgt-xp-gain | `(table)`×254, `(table{duration,durationType,dwFlags,effectAmount,effectID,s`×1, `(table{durationType,effectID,res,sourceID})`×1 | class CGameObject/CGameSprite |
| `OnMenuButtonClick` | 3 | 236 | tolua | SadoEE, bubb-infinityui, iui | `()`×236 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMainBackButtonClick` | 3 | 145 | tolua | SadoEE, bubb-infinityui, iui | `()`×145 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectEngine` | 3 | 110 | tolua | SadoEE, bubb-infinityui, iui | `(var)`×110 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetTopGroundItem` | 3 | 74 | tolua | SadoEE, bubb-infinityui, iui | `()`×74 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnImportCharacterButtonClick` | 3 | 65 | tolua | SadoEE, bubb-infinityui, iui | `()`×65 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetEngineState` | 3 | 57 | tolua | bubb-infinityui, chriz-bg-rebalance, iui | `()`×57 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMainCancelButtonClick` | 3 | 49 | tolua | SadoEE, bubb-infinityui, iui | `()`×49 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetCurrentStep` | 3 | 41 | tolua | bubb-infinityui, chriz-bg-rebalance, iui | `()`×41 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnClassSelectButtonClick` | 3 | 33 | tolua | SadoEE, bubb-infinityui, iui | `(expr)`×32, `(field)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetStoreItemCount` | 3 | 33 | tolua | SadoEE, bubb-infinityui, iui | `(expr, var)`×32, `(var, var)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsContainer` | 3 | 30 | tolua | SadoEE, bubb-infinityui, iui | `()`×30 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectStoreItem` | 3 | 27 | tolua | SadoEE, bubb-infinityui, iui | `(expr, var)`×16, `(expr, bool)`×9, `(var, bool)`×2 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StartGroundItems` | 3 | 25 | tolua | SadoEE, bubb-infinityui, iui | `()`×25 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StopGroundItems` | 3 | 18 | tolua | SadoEE, bubb-infinityui, iui | `()`×18 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getAtPoint` | 3 | 18 | provided | SadoEE, bg-eeex-buffbot, tweaks | `(num, var)`×9, `(field, var)`×4, `(var, var)`×4 | class ? |
| `OnAbilityReRollButtonClick` | 3 | 17 | tolua | SadoEE, bubb-infinityui, iui | `()`×17 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMainDoneButtonClick` | 3 | 17 | tolua | SadoEE, bubb-infinityui, iui | `()`×17 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectAll` | 3 | 17 | tolua | bubb-infinityui, diablofication, iui | `()`×17 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnGroundButtonClick` | 3 | 12 | tolua | SadoEE, bubb-infinityui, iui | `(field, field, field)`×12 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateBuySellPanel` | 3 | 12 | tolua | SadoEE, bubb-infinityui, iui | `()`×12 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getAbilityForLevel` | 3 | 12 | unknown | bg-eeex-buffbot, bubb-infinityui, iui | `(var)`×6, `(num)`×4, `(expr)`×2 | class ?; receiver class not inferred (mod code or engine object) |
| `OnBuyItemButtonClick` | 3 | 9 | tolua | SadoEE, bubb-infinityui, iui | `()`×9 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SwapPortraits` | 3 | 9 | tolua | SadoEE, bubb-infinityui, iui | `(var, var)`×9 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `evalAsAIBase` | 3 | 9 | missing | poisoned-pathways, tactics-remix, tweaks | `(var)`×9 | class CGameObject; on CGameObject objects |
| `getColumnLabel` | 3 | 6 | provided | bg-eeex-buffbot, chriz-bg-modpack, tweaks | `(var)`×4, `(expr)`×2 | class ? |
| `setStoredScriptingTarget` | 3 | 6 | provided | chriz-bg-rebalance, tactics-remix, tweaks | `(var, var)`×3, `(str, var)`×3 | class CGameObject/CGameSprite |
| `getLine` | 3 | 5 | provided | bg-eeex-buffbot, bubb-infinityui, iui | `(var)`×4, `(expr)`×1 | class ? |
| `OnDialogReplyClick` | 2 | 192 | tolua | bubb-infinityui, iui | `(expr)`×192 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetCampaign` | 2 | 128 | tolua | bubb-infinityui, iui | `()`×128 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnContainerScroll` | 2 | 128 | tolua | bubb-infinityui, iui | `(num)`×128 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UnmemorizeSpell` | 2 | 128 | tolua | bubb-infinityui, iui | `(expr, expr)`×128 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `CheckGUISong` | 2 | 120 | tolua | bubb-infinityui, iui | `()`×120 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnThiefSkillPlusMinusButtonClick` | 2 | 112 | tolua | bubb-infinityui, iui | `(expr, bool)`×112 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getLocalInt` | 2 | 107 | provided | tweaks, xgt-xp-gain | `(str)`×107 | class CGameObject/CGameSprite |
| `OnCreateDeleteButtonClick` | 2 | 104 | tolua | bubb-infinityui, iui | `(num)`×96, `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `setLocalInt` | 2 | 104 | provided | tweaks, xgt-xp-gain | `(str, num)`×87, `(str, var)`×14, `(str, expr)`×2 | class CGameObject/CGameSprite |
| `OnCampaignButtonClick` | 2 | 96 | tolua | bubb-infinityui, iui | `(str, bool)`×88, `(expr, bool)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnGroupScroll` | 2 | 96 | tolua | bubb-infinityui, iui | `(num)`×96 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnContainerButtonClick` | 2 | 80 | tolua | bubb-infinityui, iui | `(num)`×80 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SequenceSpell` | 2 | 74 | tolua | bubb-infinityui, iui | `(expr, expr)`×74 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnSoAButtonClick` | 2 | 72 | tolua | bubb-infinityui, iui | `(bool)`×72 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetGroupItemCount` | 2 | 72 | tolua | bubb-infinityui, iui | `(expr, var)`×72 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnColorChoice` | 2 | 64 | tolua | bubb-infinityui, iui | `(num)`×64 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnModifyButtonClick` | 2 | 64 | tolua | bubb-infinityui, iui | `()`×64 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPortraitButtonClick` | 2 | 64 | tolua | bubb-infinityui, iui | `(num)`×48, `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnProficiencyPlusMinusButtonClick` | 2 | 64 | tolua | bubb-infinityui, iui | `(expr, bool)`×64 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetCurrentPortrait` | 2 | 48 | tolua | bubb-infinityui, iui | `()`×48 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IncCurrentPortrait` | 2 | 48 | tolua | bubb-infinityui, iui | `()`×48 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsDoneButtonClickable` | 2 | 48 | tolua | bubb-infinityui, iui | `(var)`×32, `()`×16 | class ?/CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsThiefSkillPlusMinusButtonClickable` | 2 | 48 | tolua | bubb-infinityui, iui | `()`×48 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsTouchUI` | 2 | 48 | tolua | bubb-infinityui, iui | `()`×48 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnAbilityPlusMinusButtonClick` | 2 | 48 | tolua | bubb-infinityui, iui | `(var, bool)`×40, `(num, bool)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnGenderSelectButtonClick` | 2 | 40 | tolua | bubb-infinityui, iui | `(num)`×40 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnQuickSaveButtonClick` | 2 | 40 | tolua | bubb-infinityui, iui | `(bool)`×40 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnRaceSelectButtonClick` | 2 | 40 | tolua | bubb-infinityui, iui | `(expr)`×40 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnTBPButtonClick` | 2 | 40 | tolua | bubb-infinityui, iui | `(bool)`×40 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SaveGame` | 2 | 40 | tolua | bubb-infinityui, iui | `(num)`×24, `(expr, var)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectGroupItem` | 2 | 40 | tolua | bubb-infinityui, iui | `(expr, var)`×32, `(expr, bool)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetRoomType` | 2 | 40 | tolua | bubb-infinityui, iui | `(num)`×40 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnAppearanceButtonClick` | 2 | 36 | tolua | bubb-infinityui, iui | `()`×36 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnCusomizeBiographyButtonClick` | 2 | 36 | tolua | bubb-infinityui, iui | `()`×36 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnHairSkinButtonClick` | 2 | 36 | tolua | bubb-infinityui, iui | `()`×36 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnScriptButtonClick` | 2 | 36 | tolua | bubb-infinityui, iui | `()`×36 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnSoundsButtonClick` | 2 | 36 | tolua | bubb-infinityui, iui | `()`×36 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SpellAllowedForContingency` | 2 | 36 | tolua | bubb-infinityui, iui | `(field, field)`×36 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetMenuName` | 2 | 32 | tolua | bubb-infinityui, iui | `(var)`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `HasMoreMageLevels` | 2 | 32 | tolua | bubb-infinityui, iui | `()`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsCloseBagButtonClickable` | 2 | 32 | tolua | bubb-infinityui, iui | `()`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `LoadGame` | 2 | 32 | tolua | bubb-infinityui, iui | `(expr)`×24, `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMapMouseDown` | 2 | 32 | tolua | bubb-infinityui, iui | `(var, var)`×24, `(num, num)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMapMouseMove` | 2 | 32 | tolua | bubb-infinityui, iui | `(var, var)`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnReplayButtonClick` | 2 | 32 | tolua | bubb-infinityui, iui | `()`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnToBButtonClick` | 2 | 32 | tolua | bubb-infinityui, iui | `(bool)`×32 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetModifiedCharacterSlot` | 2 | 32 | tolua | bubb-infinityui, iui | `(expr)`×24, `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UnSequenceSpell` | 2 | 26 | tolua | bubb-infinityui, iui | `(expr, expr)`×26 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `AcceptCharacter` | 2 | 24 | tolua | bubb-infinityui, iui | `(num)`×16, `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetMissionPackInfo` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetMissionPackInfoTBP` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsMultiplayer` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `MemorizeSpell` | 2 | 24 | tolua | bubb-infinityui, iui | `(expr, expr)`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnCreatePartyButtonClick` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnKitSelectButtonClick` | 2 | 24 | tolua | bubb-infinityui, iui | `(expr)`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnReadyButtonClick` | 2 | 24 | tolua | bubb-infinityui, iui | `(expr)`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetHighlightEnabled` | 2 | 24 | tolua | bubb-infinityui, iui | `(expr)`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StepDialog` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `TravelToSelected` | 2 | 24 | tolua | bubb-infinityui, iui | `()`×24 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ToggleAI` | 2 | 20 | tolua | bubb-infinityui, iui | `()`×20 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `CenterOnGroupLeader` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ContainerScrollEnabled` | 2 | 16 | tolua | bubb-infinityui, iui | `(num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `DeleteGame` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `DismissChooseCampaignPopup` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `EraseKnownSpell` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetHardPaused` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetInControlOfDialog` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetMissionPackInfo25` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetTopContainerItem` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetTopGroupItem` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetVersionString` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class CBaldurChitin; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GroundScrollEnabled` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×8, `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GroupScrollEnabled` | 2 | 16 | tolua | bubb-infinityui, iui | `(num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `HasServiceProvider` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsHosting` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnBackButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnBuyButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDispellButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `(var)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnGroundScroll` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×8, `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnHLAButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `(var, num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnHighLevelAbilitiesButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnLearnMageSpellButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `(var)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMemorizeMageSpellButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `(var, num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMemorizePriestSpellButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `(var, num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnNewGameButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPlayerSelection` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnQuitButtonClick` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnSoundItemSelect` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `QuitGame` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetEngineState` | 2 | 16 | tolua | bubb-infinityui, iui | `(num)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetSpellLevel` | 2 | 16 | tolua | bubb-infinityui, iui | `(expr)`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateModifyCharacterPanel` | 2 | 16 | tolua | bubb-infinityui, iui | `()`×16 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `CancelSequencingSpells` | 2 | 14 | tolua | bubb-infinityui, iui | `()`×14 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `DoneSequencingSpells` | 2 | 14 | tolua | bubb-infinityui, iui | `()`×14 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetQuickButtons` | 2 | 10 | provided | SpellMenuExtended, bg-eeex-buffbot | `(var, bool)`×5, `(var, num)`×3, `(num, bool)`×2 | class CGameObject/CGameSprite |
| `findColumnLabel` | 2 | 9 | provided | bg-eeex-buffbot, chriz-bg-rebalance | `(str)`×8, `(expr)`×1 | class ? |
| `CancelJoinGame` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ClearSessions` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `DecrementDLCIndex` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `DisplayExploredMap` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetColorChoice` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCBought` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCCount` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCDescription` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCIndex` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCState` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDLCTitle` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetDownloadString` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetImportState` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetImportableCharacters` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetPanelButtonId` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetPanelButtonPanelId` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetPanelButtonToolTip` | 2 | 8 | tolua | bubb-infinityui, iui | `(num)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetPartyAI` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetTempSmartScriptLocal` | 2 | 8 | tolua | bubb-infinityui, iui | `(field)`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `HasDirectX` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `HasGameToContinue` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IncrementDLCIndex` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsClient` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsIOS` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsInGame` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsNoteVisible` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr, expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsSpriteOrderable` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `JoinGameIPAddress` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `KickPlayer` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `Logout` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ModifyCharacters` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnAlignmentSelectButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnBuyDrinkButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnBuySpellButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnCharacterExportItemSelect` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnCloseBagButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnCustomizeButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDeathLoad` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDeathQuit` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDonateButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnDualClassButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnErrorButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnExportButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnIdentifyItemButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnKickPlayerButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnLoadGameButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnModifyCharacterDelete` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMovieItemSelect` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnMultiPlayerButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnOptionsButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPermissionButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr, field)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPickPartyDoneButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPlayButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnPrerollCharacterPick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnRacialEnemySelectButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnRentRoomButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnSellItemButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnStealItemButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnTutorialButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnUserNoteClick` | 2 | 8 | tolua | bubb-infinityui, iui | `(var, expr, expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnUserNoteDeleteButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnUserNoteDoneButtonClick` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OpenBag` | 2 | 8 | tolua | bubb-infinityui, iui | `(field)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `RemoveCharacterFromParty` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `RestParty` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `RestorePurchases` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectIdentifyItem` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr, var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectServiceProvider` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SelectSpellItem` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr, var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetAbilityHelpInfo` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetImportSetting` | 2 | 8 | tolua | bubb-infinityui, iui | `(expr)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetPlayerName` | 2 | 8 | tolua | bubb-infinityui, iui | `(var)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetTempSmartScriptLocal` | 2 | 8 | tolua | bubb-infinityui, iui | `(field, field)`×8 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SpellSwappedInContingency` | 2 | 8 | tolua | bubb-infinityui, iui | `(field)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StartWorldMap` | 2 | 8 | tolua | bubb-infinityui, iui | `(num)`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StopConnectingToProvider` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `StopDialogHistory` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `TakeAllFromContainer` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ToggleAllowReformParty` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ToggleListenToJoin` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateBuyDrinksPanel` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateDonatePanel` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateIdentifyPanel` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `UpdateRentRoomPanel` | 2 | 8 | tolua | bubb-infinityui, iui | `()`×8 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `AddTail` | 2 | 7 | tolua | SadoEE, stick-lua-functions | `(var)`×6, `(call:EEex_PtrToUD)`×1 | class ?/CGameContainer; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `findRowLabel` | 2 | 7 | provided | bg-eeex-buffbot, chriz-bg-modpack | `(str)`×6, `(expr)`×1 | class ? |
| `free` | 2 | 7 | provided | chriz-bg-modpack, tweaks | `()`×7 | class CAIObjectType\|Conditional |
| `getRowColumnsItr` | 2 | 5 | provided | tweaks, warlock | `(nil, num, num)`×5 | class ? |
| `getValidSpellsWithAbilityItr` | 2 | 5 | provided | tweaks, warlock | `(call:EEex_Utility_FilterItr)`×4, `(...)`×1 | class CGameSprite |
| `GetCurrentHour` | 2 | 4 | tolua | bubb-infinityui, iui | `()`×4 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `hasID` | 2 | 4 | provided | bubb-infinityui, iui | `(var)`×4 | class ? |
| `getArea` | 2 | 3 | provided | SpellMenuExtended, bg-eeex-buffbot | `()`×3 | class uiItem |
| `AddMessage` | 2 | 2 | partial | bg-eeex-buffbot, tweaks | `(var, bool)`×2 | class CMessageHandler; EEex_TA.lua: if getmetatable(message) == MessageProxy and message.iexType == 'CMessageDisplayText' and message.args then local a = messag |
| `Construct` | 2 | 2 | provided | bg-eeex-buffbot, tweaks | `(field, expr, var, var, num, var, var)`×1, `(expr, expr, expr, expr, num, var, var)`×1 | class ? |
| `GetCurrentTime` | 2 | 2 | tolua | bubb-infinityui, iui | `()`×2 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getCastTimerPercentage` | 2 | 2 | missing | high-power-bg, olvynspells | `()`×2 | class CGameSprite; on CGameSprite objects |
| `getClass` | 2 | 2 | provided | SpellMenuExtended, aura | `()`×2 | class CGameObject/CGameSprite |
| `getModalState` | 2 | 2 | provided | high-power-bg, olvynspells | `()`×2 | class CGameSprite |
| `GetPartyGold` | 1 | 13 | tolua | SadoEE | `()`×13 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetCost` | 1 | 12 | tolua | pathfinding-redux | `(var, var, num, var, num)`×12 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `virtual_GetTerrainTable` | 1 | 8 | missing | pathfinding-redux | `()`×8 | class CGameSprite; on CGameSprite objects |
| `virtual_GetVisualRange` | 1 | 8 | provided | tweaks | `()`×8 | class CGameObject |
| `AddEffect` | 1 | 6 | provided | tweaks | `(expr)`×6 | class CGameSprite/CProjectile |
| `evalConditionalAsAIBase` | 1 | 5 | provided | tweaks | `(var)`×5 | class Conditional |
| `getSpellState` | 1 | 5 | provided | bg-eeex-buffbot | `(var)`×5 | class CGameSprite |
| `ParseResponseString` | 1 | 4 | tolua | pathfinding-redux | `(expr)`×4 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `getKnownInnateSpellsItr` | 1 | 4 | provided | warlock | `(num, num)`×4 | class CGameSprite |
| `getKnownMageSpellsItr` | 1 | 4 | provided | warlock | `(num, num)`×4 | class CGameSprite |
| `getLocalString` | 1 | 4 | provided | tweaks | `(str)`×4 | class CGameSprite |
| `virtual_InsertAction` | 1 | 4 | missing | pathfinding-redux | `(var)`×4 | class CGameSprite; on CGameSprite objects |
| `SelectCharacter` | 1 | 3 | provided | SadoEE | `(var, bool)`×2, `(field, bool)`×1 | class CInfGame |
| `UnselectAll` | 1 | 3 | provided | SadoEE | `()`×3 | class CInfGame |
| `flush` | 1 | 3 | unknown | bg-eeex-buffbot | `()`×3 | class ?; receiver class not inferred (mod code or engine object) |
| `getCasterLevelForSpell` | 1 | 3 | missing | bg-eeex-buffbot | `(var, bool)`×3 | class CGameSprite; on CGameSprite objects |
| `CheckLOS` | 1 | 2 | missing | SadoEE | `(expr, expr, expr, num, num)`×2 | class CGameArea; on CGameArea objects |
| `Demand` | 1 | 2 | tolua | chriz-bg-modpack | `()`×2 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetAtOffset` | 1 | 2 | tolua | chriz-bg-modpack | `(var)`×2 | class CDerivedStats; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetInternalButtonList` | 1 | 2 | provided | SpellMenuExtended | `()`×2 | class CGameObject |
| `OnAbilityRecallButtonClick` | 1 | 2 | tolua | SadoEE | `()`×2 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ReadySpell` | 1 | 2 | provided | SpellMenuExtended | `(var, num)`×2 | class CGameObject/CGameSprite |
| `SetCursor` | 1 | 2 | missing | SadoEE | `(num, bool, num)`×2 | class CGameSprite; on CGameSprite objects |
| `SetFromChars` | 1 | 2 | tolua | chriz-bg-modpack | `(field)`×1, `(var)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `countAllOfTypeStringInRange` | 1 | 2 | missing | bg-eeex-buffbot | `(str, num)`×2 | class CGameSprite; on CGameSprite objects |
| `getAllOfTypeInRange` | 1 | 2 | provided | tweaks | `(var, var, var, var, expr, var, var)`×1, `(var, var, expr, var, var)`×1 | class ?/CGameSprite |
| `setLocalString` | 1 | 2 | provided | tweaks | `(str, var)`×1, `(str, str)`×1 | class CGameSprite |
| `virtual_GetVisibleTerrainTable` | 1 | 2 | missing | SadoEE | `()`×2 | class ?/CGameSprite; on CGameSprite objects |
| `Construct_Overload_Manual` | 1 | 1 | tolua | SadoEE | `(var, field, field, field, num, num)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `CreateCreature` | 1 | 1 | tolua | bg2-radar-overlay | `(var)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetName` | 1 | 1 | provided | tweaks | `(bool)`×1 | class CGameSprite |
| `GetPickPartyCharacterId` | 1 | 1 | tolua | SadoEE | `(var)`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `GetStoreName` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsAbilityRecallButtonClickable` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsAppearanceButtonClickable` | 1 | 1 | tolua | SadoEE | `()`×1 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsBuyItemButtonClickable` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsChargenComplete` | 1 | 1 | tolua | chriz-bg-rebalance | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsLevelUpButtonClickable` | 1 | 1 | tolua | SadoEE | `()`×1 | class CGameSprite; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsMainBackButtonClickable` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `IsTravelButtonVisible` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnAbilityStoreButtonClick` | 1 | 1 | tolua | SadoEE | `()`×1 | class ?; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `OnActionButtonClickGround` | 1 | 1 | provided | SadoEE | `(expr)`×1 | class CGameArea |
| `OnLButtonPressed` | 1 | 1 | tolua | SpellMenuExtended | `(var)`×1 | class CButtonData; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `ReadyOffInternalList` | 1 | 1 | provided | SpellMenuExtended | `(var, num)`×1 | class CGameSprite |
| `SetIconIndex` | 1 | 1 | tolua | SpellMenuExtended | `(num)`×1 | class CInfGame; engine tolua method (game binding: works without an extender on game objects such as worldScreen / game / e) |
| `SetState` | 1 | 1 | provided | SpellMenuExtended | `(num, bool)`×1 | class CInfGame |
| `_getDefault` | 1 | 1 | unknown | bg-eeex-buffbot | `()`×1 | class ?; receiver class not inferred (mod code or engine object) |
| `_read` | 1 | 1 | unknown | bg-eeex-buffbot | `()`×1 | class ?; receiver class not inferred (mod code or engine object) |
| `_set` | 1 | 1 | unknown | bg-eeex-buffbot | `(var, bool)`×1 | class ?; receiver class not inferred (mod code or engine object) |
| `executeResponseAsAIBaseInstantly` | 1 | 1 | provided | tweaks | `(var)`×1 | class ? |
| `getKnownPriestSpellsWithAbilityIterator` | 1 | 1 | provided | tweaks | `(num, num)`×1 | class CGameSprite |
| `getLauncher` | 1 | 1 | provided | tweaks | `(expr)`×1 | class CGameSprite |
| `getStartingPos` | 1 | 1 | missing | tweaks | `(var, table)`×1 | class CProjectile; on CProjectile objects |
| `getValue` | 1 | 1 | unknown | bg2narrator | `()`×1 | class ?; receiver class not inferred (mod code or engine object) |
| `iterateUnpackedEntries` | 1 | 1 | provided | tweaks | `(fn(id,symbol,_))`×1 | class ? |
| `virtual_Destruct` | 1 | 1 | missing | tweaks | `(bool)`×1 | class CProjectile; on CProjectile objects |

## Engine fields (291)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `m_typeAI` | 18 | 289 | provided | Bardic-Wonders, SadoEE, Shadow-Magic, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, epic-thieving, high-power-bg, house-rule-tweaks, olvynspells, pathfinding-redux, random-graion-magic, spells-and-magic, stick-lua-functions, sword-coast-infinity, tweaks, warlock |  | class ?/CGameObject/CGameSprite |
| `m_Class` | 18 | 61 | provided | Bardic-Wonders, SadoEE, Shadow-Magic, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-sod-rebalance, epic-thieving, high-power-bg, house-rule-tweaks, iui, olvynspells, random-graion-magic, spells-and-magic, stick-lua-functions, sword-coast-infinity, tweaks, warlock |  | class ?/CAIObjectType |
| `m_id` | 14 | 975 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, high-power-bg, iui, olvynspells, pathfinding-redux, stick-lua-functions, tweaks, xgt-xp-gain |  | class ?/CGameObject/CGameSprite |
| `m_Alignment` | 12 | 32 | provided | Bardic-Wonders, SadoEE, Shadow-Magic, bg-eeex-buffbot, high-power-bg, olvynspells, random-graion-magic, spells-and-magic, stick-lua-functions, sword-coast-infinity, tweaks, warlock |  | class ?/CAIObjectType |
| `m_baseStats` | 11 | 207 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, chriz-sod-rebalance, iui, pathfinding-redux, tactics-remix, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_timedEffectList` | 11 | 116 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, iui, olvynspells, stick-lua-functions, tweaks |  | class ?/CGameEffectList/CGameObject/CGameSprite |
| `m_effectId` | 10 | 191 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, iui, stick-lua-functions, tweaks, xgt-xp-gain |  | class ?/CGameEffect |
| `m_EnemyAlly` | 8 | 172 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, iui, pathfinding-redux, stick-lua-functions, tweaks |  | class ?/CAIObjectType |
| `m_actionID` | 8 | 161 | provided | SadoEE, bg-eeex-buffbot, bg2narrator, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux, tweaks |  | class ?/CAIAction/CGameObject |
| `m_effectAmount` | 8 | 89 | provided | bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, iui, stick-lua-functions, tweaks, xgt-xp-gain |  | class ?/CGameEffect |
| `m_dWFlags` | 8 | 82 | provided | bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, iui, tweaks, xgt-xp-gain |  | class ?/CGameEffect |
| `m_nKit` | 8 | 63 | provided | Bardic-Wonders, Shadow-Magic, The-Artisan-s-Kitpack, aura, skills-and-abilities, stick-lua-functions, tweaks, warlock |  | class ?/CDerivedStats |
| `m_pNodeHead` | 8 | 61 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, stick-lua-functions |  | class ?/CGameEffect/CGameEffectList |
| `m_resref` | 8 | 37 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, iui, pathfinding-redux, tweaks |  | class ?/CGameArea/CGameObject/CGameSprite |
| `m_equipedEffectList` | 8 | 32 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, stick-lua-functions, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_durationType` | 8 | 26 | provided | bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, iui, tweaks, xgt-xp-gain |  | class ?/CGameEffect |
| `m_pos` | 7 | 316 | provided | SadoEE, bubb-infinityui, chriz-bg-rebalance, iui, pathfinding-redux, stick-lua-functions, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_derivedStats` | 7 | 183 | provided | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, pathfinding-redux, stick-lua-functions, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_equipment` | 7 | 170 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, iui, stick-lua-functions, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_flags` | 7 | 122 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, stick-lua-functions, tweaks |  | class ?/CCreatureFileHeader/CGameEffect/CGameSprite/CItem |
| `m_sourceRes` | 7 | 120 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, iui, tweaks |  | class ?/CGameEffect |
| `m_items` | 7 | 110 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, iui, stick-lua-functions, tweaks |  | class ?/CGameSpriteEquipment |
| `m_pObjectGame` | 7 | 78 | provided | SadoEE, SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux |  | class ?/CBaldurChitin |
| `m_selectedWeapon` | 7 | 46 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, iui, stick-lua-functions, tweaks |  | class ?/CGameSpriteEquipment |
| `m_pArea` | 6 | 289 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, tweaks |  | class ?/CGameArea/CGameObject/CGameSprite |
| `m_gameTime` | 6 | 47 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux |  | class ?/CTimerWorld |
| `m_Race` | 6 | 36 | provided | SadoEE, bg-eeex-buffbot, bubb-infinityui, iui, stick-lua-functions, tweaks |  | class ?/CAIObjectType |
| `m_worldTime` | 6 | 22 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux |  | class ?/CInfGame |
| `m_sourceId` | 5 | 117 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, tweaks |  | class ?/CGameEffect |
| `m_generalState` | 5 | 96 | provided | SadoEE, bg-eeex-buffbot, pathfinding-redux, stick-lua-functions, tweaks |  | class ?/CCreatureFileHeader/CDerivedStats/CGameSprite |
| `m_res` | 5 | 68 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-rebalance, stick-lua-functions, tweaks |  | class ?/CAbilityId/CGameEffect |
| `m_sourceType` | 5 | 67 | provided | bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, iui, tweaks |  | class ?/CGameEffect |
| `m_scriptName` | 5 | 42 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, tweaks |  | class ?/CGameEffect/CGameObject/CGameSprite |
| `m_duration` | 5 | 32 | provided | bg-eeex-buffbot, bubb-infinityui, chriz-bg-rebalance, iui, tweaks |  | class ?/CGameEffect |
| `m_hitPoints` | 5 | 32 | provided | SadoEE, bubb-infinityui, chriz-bg-rebalance, iui, tweaks |  | class ?/CCreatureFileHeader |
| `m_pchData` | 5 | 32 | provided | SadoEE, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, tweaks |  | class ? |
| `m_nCount` | 5 | 31 | provided | SadoEE, SpellMenuExtended, high-power-bg, olvynspells, stick-lua-functions |  | class ? |
| `m_Instance` | 5 | 27 | provided | SadoEE, bg2narrator, high-power-bg, olvynspells, tweaks |  | class ?/CAIObjectType |
| `m_level1` | 5 | 23 | provided | SadoEE, chriz-bg-modpack, chriz-sod-rebalance, tactics-remix, tweaks |  | class ?/CCreatureFileHeader |
| `m_level2` | 5 | 23 | provided | SadoEE, chriz-bg-modpack, chriz-sod-rebalance, tactics-remix, tweaks |  | class ?/CCreatureFileHeader |
| `m_acteeID` | 5 | 22 | provided | SadoEE, bg2narrator, high-power-bg, olvynspells, tweaks |  | class ?/CAIAction/CGameArea/CGameObject; known on CAIAction, not on CGameArea |
| `m_curAction` | 4 | 109 | provided | SadoEE, chriz-bg-rebalance, pathfinding-redux, tweaks |  | class ?/CGameObject/CGameSprite |
| `m_dest` | 4 | 55 | provided | SadoEE, high-power-bg, olvynspells, pathfinding-redux |  | class ?/CAIAction |
| `m_spellId` | 4 | 27 | provided | bg-eeex-buffbot, chriz-bg-rebalance, stick-lua-functions, tweaks |  | class ? |
| `m_abilityId` | 4 | 13 | provided | SpellMenuExtended, bg-eeex-buffbot, tweaks, warlock |  | class ?/CButtonData |
| `m_casterLevel` | 4 | 8 | provided | bubb-infinityui, chriz-bg-rebalance, iui, tweaks |  | class ?/CGameEffect |
| `m_sourceTarget` | 3 | 83 | missing | bg-eeex-buffbot, chriz-bg-rebalance, tweaks |  | class ?/CGameEffect |
| `m_bConfirmDialog` | 3 | 77 | missing | bubb-infinityui, chriz-bg-rebalance, iui |  | class ? |
| `m_xp` | 3 | 63 | provided | SadoEE, chriz-bg-modpack, chriz-sod-rebalance |  | class ?/CCreatureFileHeader |
| `m_queuedActions` | 3 | 36 | provided | SadoEE, chriz-bg-rebalance, pathfinding-redux |  | class ?/CGameObject/CGameSprite |
| `m_selectedWeaponAbility` | 3 | 22 | provided | bg-eeex-buffbot, stick-lua-functions, tweaks |  | class ?/CGameSpriteEquipment |
| `m_string1` | 3 | 22 | provided | bg2narrator, chriz-bg-rebalance, tweaks |  | class ?/CAIAction |
| `m_secondaryType` | 3 | 19 | provided | bubb-infinityui, iui, tweaks |  | class CGameEffect |
| `m_level3` | 3 | 17 | provided | SadoEE, chriz-bg-modpack, tactics-remix |  | class ?/CCreatureFileHeader |
| `m_liveTypeAI` | 3 | 15 | provided | SadoEE, bubb-infinityui, iui |  | class CGameSprite |
| `m_animation` | 3 | 13 | provided | SadoEE, bubb-infinityui, iui |  | class ?/CGameAnimation/CGameSprite |
| `m_targetId` | 3 | 11 | provided | poisoned-pathways, tactics-remix, tweaks |  | class CGameObject/CGameSprite |
| `m_done` | 3 | 7 | provided | chriz-bg-modpack, chriz-bg-rebalance, tweaks |  | class ?/CGameEffect |
| `m_effectAmount5` | 3 | 7 | provided | bubb-infinityui, iui, tweaks |  | class CGameEffect |
| `m_itemType` | 3 | 7 | provided | chriz-bg-rebalance, tweaks, warlock |  | class ?/CAbilityId |
| `m_animationID` | 3 | 6 | provided | SadoEE, bubb-infinityui, iui |  | class ?/CGameAnimationType |
| `m_count` | 3 | 5 | provided | SpellMenuExtended, bg-eeex-buffbot, tweaks |  | class ?/CButtonData |
| `m_name` | 3 | 5 | provided | SpellMenuExtended, bg-eeex-buffbot, chriz-bg-modpack |  | class ?/CButtonData/CCreatureFileHeader |
| `m_objectType` | 2 | 33 | provided | SadoEE, pathfinding-redux |  | class ?/CGameObject |
| `m_attackType` | 2 | 32 | provided | stick-lua-functions, tweaks |  | class ? |
| `m_slot` | 2 | 32 | provided | stick-lua-functions, tweaks |  | class ? |
| `m_spellStates` | 2 | 28 | provided | chriz-bg-rebalance, chriz-playable-races |  | class ?/CDerivedStats |
| `m_leftAttack` | 2 | 25 | provided | stick-lua-functions, tweaks |  | class CGameObject |
| `m_special` | 2 | 25 | provided | chriz-playable-races, tweaks |  | class CGameEffect |
| `m_Specifics` | 2 | 16 | provided | stick-lua-functions, tweaks |  | class ?/CAIObjectType |
| `m_hitOrMiss` | 2 | 16 | provided | stick-lua-functions, tweaks |  | class ? |
| `m_nBattleSongCounter` | 2 | 16 | provided | pathfinding-redux, tweaks |  | class CGameArea |
| `m_nHatedRace` | 2 | 16 | provided | stick-lua-functions, tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_cCriticalEntryList` | 2 | 15 | provided | stick-lua-functions, tweaks |  | class ?/CDerivedStats |
| `m_bonus` | 2 | 13 | provided | stick-lua-functions, tweaks |  | class ? |
| `m_inCutScene` | 2 | 13 | provided | pathfinding-redux, tweaks |  | class CGameSprite |
| `m_nBackstabDamageMultiplier` | 2 | 13 | provided | stick-lua-functions, tweaks |  | class ?/CDerivedStats |
| `m_gameAreas` | 2 | 12 | provided | SadoEE, pathfinding-redux |  | class CInfGame |
| `m_DamageBonusRight` | 2 | 10 | provided | stick-lua-functions, tweaks |  | class CDerivedStats/CGameSprite |
| `m_Gender` | 2 | 10 | provided | stick-lua-functions, tweaks |  | class ?/CAIObjectType |
| `m_General` | 2 | 10 | provided | stick-lua-functions, tweaks |  | class ?/CAIObjectType |
| `m_nDamageBonus` | 2 | 10 | provided | stick-lua-functions, tweaks |  | class CDerivedStats/CGameSprite |
| `m_useCount1` | 2 | 10 | provided | SadoEE, tweaks |  | class ?/CGameSprite/CItem |
| `m_lVertSort` | 2 | 9 | provided | SadoEE, bg-eeex-buffbot |  | class CGameArea |
| `m_nNumberOfAttacks` | 2 | 9 | provided | chriz-bg-rebalance, stick-lua-functions |  | class ?/CDerivedStats |
| `m_startTypeAI` | 2 | 9 | provided | SadoEE, chriz-bg-modpack |  | class CGameSprite |
| `m_bRenderFrameTimes` | 2 | 8 | missing | bubb-infinityui, iui |  | class ? |
| `m_mageSpecUpperWord` | 2 | 8 | provided | SadoEE, chriz-bg-modpack |  | class ?/CCreatureFileHeader |
| `m_memorizedSpellsMage` | 2 | 8 | provided | chriz-bg-rebalance, tweaks |  | class ?/CGameSprite |
| `m_specificID` | 2 | 8 | provided | chriz-bg-rebalance, tweaks |  | class CAIAction |
| `m_DamageBonusLeft` | 2 | 7 | provided | stick-lua-functions, tweaks |  | class CDerivedStats/CGameSprite |
| `m_resRef` | 2 | 7 | provided | SadoEE, stick-lua-functions |  | class ?/CGameSprite; known on CStore, not on CGameSprite |
| `m_tempStats` | 2 | 7 | provided | chriz-bg-rebalance, pathfinding-redux |  | class ? |
| `m_nResistCrushing` | 2 | 6 | provided | chriz-bg-rebalance, tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_nResistSlashing` | 2 | 6 | provided | chriz-bg-rebalance, tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_sName` | 2 | 6 | provided | bg-eeex-buffbot, chriz-bg-modpack |  | class CGameObject/CGameSprite |
| `m_sourceFlags` | 2 | 6 | provided | chriz-bg-rebalance, tweaks |  | class ?/CGameEffect |
| `m_bAllowEffectListCall` | 2 | 5 | missing | chriz-bg-rebalance, pathfinding-redux |  | class ? |
| `m_gameSave` | 2 | 5 | missing | bg-eeex-buffbot, pathfinding-redux |  | class ?/CInfGame |
| `m_inputMode` | 2 | 5 | missing | bg-eeex-buffbot, pathfinding-redux |  | class ? |
| `m_nResistMissile` | 2 | 5 | provided | chriz-bg-rebalance, tweaks |  | class ?/CGameSprite |
| `m_icon` | 2 | 4 | provided | SpellMenuExtended, bg-eeex-buffbot |  | class ?/CButtonData |
| `m_maxHitPointsBase` | 2 | 4 | provided | SadoEE, chriz-bg-modpack |  | class ?/CCreatureFileHeader |
| `m_memorizedSpellsPriest` | 2 | 4 | provided | chriz-bg-rebalance, tweaks |  | class CGameSprite |
| `m_nTimeStop` | 2 | 4 | missing | high-power-bg, olvynspells |  | class CInfGame |
| `m_sCurrentCampaign` | 2 | 4 | provided | SadoEE, chriz-bg-modpack |  | class CInfGame |
| `m_wFileType` | 2 | 3 | missing | bg-eeex-buffbot, tweaks |  | class ? |
| `m_buttonTypes` | 2 | 2 | provided | SadoEE, tweaks |  | class ? |
| `m_cContingencyList` | 2 | 2 | missing | high-power-bg, olvynspells |  | class ? |
| `m_characters` | 2 | 2 | provided | chriz-bg-modpack, chriz-playable-races |  | class CInfGame |
| `m_colors` | 2 | 2 | provided | bg-eeex-buffbot, tweaks |  | class CCreatureFileHeader |
| `m_nMaxHitPoints` | 2 | 2 | provided | chriz-bg-rebalance, tweaks |  | class ? |
| `m_nTimeStopCaster` | 2 | 2 | provided | high-power-bg, olvynspells |  | class CInfGame |
| `m_pEngineWorldMap` | 2 | 2 | provided | high-power-bg, olvynspells |  | class CBaldurChitin |
| `m_spellLevelq` | 2 | 2 | missing | bubb-infinityui, iui |  | class CGameEffect |
| `m_nLevel1` | 1 | 39 | provided | tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_type` | 1 | 21 | provided | tweaks |  | class ? |
| `m_specificID3` | 1 | 16 | provided | pathfinding-redux |  | class ?/CAIAction |
| `m_school` | 1 | 15 | provided | tweaks |  | class CGameEffect |
| `m_attackFrame` | 1 | 12 | provided | tweaks |  | class CGameSprite |
| `m_bHardPaused` | 1 | 12 | missing | chriz-bg-rebalance |  | class ? |
| `m_bPaused` | 1 | 12 | missing | chriz-bg-rebalance |  | class ? |
| `m_effectAmount2` | 1 | 12 | provided | stick-lua-functions |  | class CGameEffect |
| `m_pNodeFree` | 1 | 12 | provided | stick-lua-functions |  | class ? |
| `m_projectileType` | 1 | 12 | provided | tweaks |  | class CGameEffect |
| `m_nDamageCounter` | 1 | 11 | missing | pathfinding-redux |  | class CGameArea |
| `m_nSTR` | 1 | 11 | provided | tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_dwFlags` | 1 | 10 | provided | SadoEE |  | class ? |
| `m_memorizedSpellsInnate` | 1 | 10 | provided | tweaks |  | class CGameSprite |
| `m_charactersPortrait` | 1 | 9 | missing | pathfinding-redux |  | class ?/CInfGame |
| `m_nCopyParent` | 1 | 9 | missing | bg-eeex-buffbot |  | class ?/CGameSprite |
| `m_nSequence` | 1 | 9 | provided | tweaks |  | class CGameSprite |
| `m_pEngineWorld` | 1 | 9 | provided | chriz-bg-rebalance |  | class CBaldurChitin |
| `m_pTempItem` | 1 | 9 | provided | SadoEE |  | class ? |
| `m_res2` | 1 | 9 | provided | tweaks |  | class CGameEffect |
| `m_spellLevel` | 1 | 9 | provided | tweaks |  | class CGameEffect |
| `m_bSeeInvisible` | 1 | 8 | provided | tweaks |  | class ?/CGameSprite |
| `m_res3` | 1 | 8 | provided | tweaks |  | class CGameEffect |
| `m_slotNum` | 1 | 8 | provided | tweaks |  | class CGameEffect |
| `m_areaType` | 1 | 7 | provided | tweaks |  | class CAreaFileHeader |
| `m_header` | 1 | 7 | provided | tweaks |  | class CGameArea |
| `m_lstItems` | 1 | 7 | provided | SadoEE |  | class ?/CGameContainer |
| `m_nSelectedButton` | 1 | 7 | provided | SpellMenuExtended |  | class ?/CAIAction |
| `m_savingThrow` | 1 | 7 | provided | tweaks |  | class CGameEffect |
| `m_bGameLoaded` | 1 | 6 | missing | chriz-bg-rebalance |  | class CInfGame |
| `m_bSanctuary` | 1 | 6 | provided | tweaks |  | class ?/CGameSprite |
| `m_drawPoly` | 1 | 6 | provided | SadoEE |  | class ? |
| `m_nDEX` | 1 | 6 | provided | tweaks |  | class ?/CDerivedStats/CGameSprite |
| `m_nHitBonus` | 1 | 6 | missing | stick-lua-functions |  | class CDerivedStats |
| `m_nINT` | 1 | 6 | provided | tweaks |  | class ?/CDerivedStats |
| `m_nLevel2` | 1 | 6 | provided | tweaks |  | class ?/CDerivedStats |
| `m_nLuck` | 1 | 6 | provided | tweaks |  | class ?/CGameSprite |
| `m_pNodeTail` | 1 | 6 | provided | stick-lua-functions |  | class ? |
| `m_persistantEffects` | 1 | 6 | missing | stick-lua-functions |  | class CGameObject |
| `m_THAC0BonusRight` | 1 | 5 | provided | tweaks |  | class CGameSprite |
| `m_lSummonedBy` | 1 | 5 | provided | tweaks |  | class CGameObject/CGameSprite |
| `m_multiPlayerSettings` | 1 | 5 | missing | bg-eeex-buffbot |  | class CInfGame |
| `m_nArmorClass` | 1 | 5 | provided | tweaks |  | class CGameSprite |
| `m_nCHR` | 1 | 5 | provided | tweaks |  | class CDerivedStats/CGameSprite |
| `m_nSTRExtra` | 1 | 5 | provided | tweaks |  | class CDerivedStats/CGameSprite |
| `m_nTHAC0` | 1 | 5 | provided | tweaks |  | class CGameSprite |
| `m_pEngineInventory` | 1 | 5 | provided | SadoEE |  | class CBaldurChitin |
| `m_quickButtonToConfigure` | 1 | 5 | provided | SpellMenuExtended |  | class ?/CAIAction |
| `m_saveMod` | 1 | 5 | provided | tweaks |  | class CGameEffect |
| `m_actionList` | 1 | 4 | missing | pathfinding-redux |  | class ? |
| `m_bInLoadArea` | 1 | 4 | missing | chriz-bg-rebalance |  | class CInfGame |
| `m_bInLoadGame` | 1 | 4 | missing | chriz-bg-rebalance |  | class CInfGame |
| `m_curResponse` | 1 | 4 | provided | pathfinding-redux |  | class ? |
| `m_dWValue` | 1 | 4 | provided | chriz-bg-modpack |  | class ? |
| `m_effectAmount4` | 1 | 4 | provided | tweaks |  | class CGameEffect |
| `m_intValue` | 1 | 4 | provided | chriz-bg-modpack |  | class ? |
| `m_lVertSortBack` | 1 | 4 | provided | SadoEE |  | class CGameArea |
| `m_mageSpecialization` | 1 | 4 | provided | chriz-bg-modpack |  | class ?/CCreatureFileHeader |
| `m_nACCrushingMod` | 1 | 4 | provided | tweaks |  | class CDerivedStats |
| `m_nXP` | 1 | 4 | missing | chriz-bg-modpack |  | class CDerivedStats |
| `m_pArray` | 1 | 4 | missing | chriz-bg-modpack |  | class ? |
| `m_pEngineStart` | 1 | 4 | provided | chriz-bg-rebalance |  | class CBaldurChitin |
| `m_pLocalVariables` | 1 | 4 | provided | chriz-bg-modpack |  | class CGameSprite |
| `m_pnCharacterControlledByPlayer` | 1 | 4 | missing | bg-eeex-buffbot |  | class ? |
| `m_bAuraCleansing` | 1 | 3 | provided | tweaks |  | class ?/CGameSprite |
| `m_bImmunityToBackStab` | 1 | 3 | provided | tweaks |  | class ? |
| `m_equippedEffectList` | 1 | 3 | missing | chriz-bg-rebalance |  | class ? |
| `m_lInventory` | 1 | 3 | provided | SadoEE |  | class ? |
| `m_nACPiercingMod` | 1 | 3 | provided | tweaks |  | class CDerivedStats |
| `m_nACSlashingMod` | 1 | 3 | provided | tweaks |  | class CDerivedStats |
| `m_nAssassinate` | 1 | 3 | missing | tweaks |  | class ? |
| `m_nHalfSwingCounter` | 1 | 3 | missing | stick-lua-functions |  | class CGameObject |
| `m_nMeleeDamageBonus` | 1 | 3 | provided | tweaks |  | class CGameSprite |
| `m_nResistPiercing` | 1 | 3 | provided | tweaks |  | class CDerivedStats/CGameSprite |
| `m_nTurnUndeadLevel` | 1 | 3 | provided | tweaks |  | class CDerivedStats/CGameSprite |
| `m_startedSwing` | 1 | 3 | provided | tweaks |  | class CGameSprite |
| `m_trapDetected` | 1 | 3 | provided | SadoEE |  | class ? |
| `m_useCount2` | 1 | 3 | provided | tweaks |  | class CGameSprite/CItem |
| `m_useCount3` | 1 | 3 | provided | tweaks |  | class CGameSprite/CItem |
| `m_CONBase` | 1 | 2 | provided | SadoEE |  | class ?/CCreatureFileHeader |
| `m_bGreyOut` | 1 | 2 | provided | tweaks |  | class ? |
| `m_bInCasting` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_bInCopy` | 1 | 2 | missing | bg-eeex-buffbot |  | class CGameSprite |
| `m_buttonArray` | 1 | 2 | provided | tweaks |  | class ? |
| `m_cInfinity` | 1 | 2 | provided | SadoEE |  | class ? |
| `m_curProjectile` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_deleted` | 1 | 2 | missing | chriz-bg-rebalance |  | class CGameEffect |
| `m_dialog` | 1 | 2 | provided | SadoEE |  | class ?/CGameObject |
| `m_gold` | 1 | 2 | provided | SadoEE |  | class CCreatureFileHeader |
| `m_lHitter` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_magicResistRoll` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_nCON` | 1 | 2 | provided | tweaks |  | class ?/CGameSprite |
| `m_nCharacters` | 1 | 2 | provided | chriz-bg-modpack |  | class CInfGame |
| `m_nDirection` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_nResistFire` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_nSaveVSBreath` | 1 | 2 | provided | tweaks |  | class CGameSprite |
| `m_nSizeX` | 1 | 2 | missing | chriz-bg-modpack |  | class ? |
| `m_nSizeY` | 1 | 2 | missing | chriz-bg-modpack |  | class ? |
| `m_nState` | 1 | 2 | provided | SadoEE |  | class CInfGame |
| `m_nStoneSkins` | 1 | 2 | provided | tweaks |  | class ?/CDerivedStats |
| `m_newEffect` | 1 | 2 | missing | tweaks |  | class CGameSprite |
| `m_objectID` | 1 | 2 | missing | bg-eeex-buffbot |  | class ? |
| `m_portraitLarge` | 1 | 2 | provided | SadoEE |  | class CCreatureFileHeader |
| `m_portraitSmall` | 1 | 2 | provided | SadoEE |  | class CCreatureFileHeader |
| `m_proficiencies` | 1 | 2 | missing | chriz-bg-modpack |  | class ? |
| `m_rBounding` | 1 | 2 | provided | SadoEE |  | class ? |
| `m_ruleTables` | 1 | 2 | missing | chriz-bg-modpack |  | class CInfGame |
| `m_sex` | 1 | 2 | missing | bg-eeex-buffbot |  | class CDerivedStats |
| `m_tXPBonus` | 1 | 2 | missing | chriz-bg-modpack |  | class ? |
| `m_trapActivated` | 1 | 2 | provided | SadoEE |  | class ? |
| `m_visibleArea` | 1 | 2 | provided | SadoEE |  | class CInfGame |
| `m_CHRBase` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_DEXBase` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_INTBase` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_STRBase` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_WISBase` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_abilityNum` | 1 | 1 | provided | SpellMenuExtended |  | class CAbilityId |
| `m_animationType` | 1 | 1 | provided | chriz-playable-races |  | class CCreatureFileHeader |
| `m_armorClass` | 1 | 1 | provided | SadoEE |  | class CCreatureFileHeader |
| `m_bDisabled` | 1 | 1 | provided | SpellMenuExtended |  | class CButtonData |
| `m_bDisplayCount` | 1 | 1 | provided | tweaks |  | class CButtonData |
| `m_bGrease` | 1 | 1 | provided | tweaks |  | class CDerivedStats |
| `m_bPolymorphed` | 1 | 1 | missing | tweaks |  | class CDerivedStats |
| `m_bWeb` | 1 | 1 | provided | tweaks |  | class ? |
| `m_cDamageBonusList` | 1 | 1 | provided | tweaks |  | class ? |
| `m_cProtectionList` | 1 | 1 | provided | tweaks |  | class ? |
| `m_cToHitBonusList` | 1 | 1 | provided | tweaks |  | class ? |
| `m_castCounter` | 1 | 1 | provided | tweaks |  | class CGameSprite |
| `m_coneSize` | 1 | 1 | missing | tweaks |  | class ? |
| `m_containerType` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_data` | 1 | 1 | missing | bg-eeex-buffbot |  | class ? |
| `m_diceSize` | 1 | 1 | provided | tweaks |  | class CGameEffect |
| `m_disabledButtons` | 1 | 1 | provided | SpellMenuExtended |  | class ? |
| `m_dwAreaFlags` | 1 | 1 | missing | tweaks |  | class ? |
| `m_explosionRange` | 1 | 1 | missing | tweaks |  | class ? |
| `m_followCount` | 1 | 1 | missing | tweaks |  | class CGameObject |
| `m_iContainer` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_iContainerSprite` | 1 | 1 | provided | SadoEE |  | class CInfGame |
| `m_idSelf` | 1 | 1 | missing | chriz-bg-rebalance |  | class CGameSprite |
| `m_itemId` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_liveStats` | 1 | 1 | missing | bg-eeex-buffbot |  | class CGameSprite |
| `m_maxLevel` | 1 | 1 | provided | tweaks |  | class CGameEffect |
| `m_minLevel` | 1 | 1 | provided | tweaks |  | class CGameEffect |
| `m_nACMissileMod` | 1 | 1 | provided | tweaks |  | class CDerivedStats |
| `m_nId` | 1 | 1 | missing | chriz-bg-rebalance |  | class CGameSprite |
| `m_nInStock` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_nLastDamageTaken` | 1 | 1 | missing | tweaks |  | class CGameSprite |
| `m_nLevel3` | 1 | 1 | provided | tweaks |  | class CDerivedStats |
| `m_nLevelDrain` | 1 | 1 | missing | tweaks |  | class CDerivedStats |
| `m_nLore` | 1 | 1 | provided | tweaks |  | class CGameSprite |
| `m_nMissileDamageBonus` | 1 | 1 | provided | tweaks |  | class CGameSprite |
| `m_nProficiency2Weapon` | 1 | 1 | provided | tweaks |  | class CDerivedStats |
| `m_nReputation` | 1 | 1 | provided | SadoEE |  | class CInfGame |
| `m_nResistCold` | 1 | 1 | provided | tweaks |  | class ? |
| `m_nSpellFailureInnate` | 1 | 1 | missing | tweaks |  | class CGameSprite |
| `m_nSpellFailureMage` | 1 | 1 | missing | tweaks |  | class CGameSprite |
| `m_nSpellFailurePriest` | 1 | 1 | missing | tweaks |  | class CGameSprite |
| `m_nWIS` | 1 | 1 | provided | tweaks |  | class CDerivedStats |
| `m_numDice` | 1 | 1 | provided | tweaks |  | class CGameEffect |
| `m_overHead` | 1 | 1 | missing | bg-eeex-buffbot |  | class ? |
| `m_pEngineStore` | 1 | 1 | provided | SadoEE |  | class CBaldurChitin |
| `m_pKeymap` | 1 | 1 | provided | SadoEE |  | class CInfGame |
| `m_pNext` | 1 | 1 | missing | bg-eeex-buffbot |  | class ? |
| `m_pObjectCursor` | 1 | 1 | provided | SadoEE |  | class CBaldurChitin |
| `m_pStore` | 1 | 1 | provided | SadoEE |  | class CScreenStore |
| `m_pnLoadGameControlledByPlayer` | 1 | 1 | missing | bg-eeex-buffbot |  | class ? |
| `m_quickItemResRef` | 1 | 1 | missing | bg-eeex-buffbot |  | class ? |
| `m_sSaveGame` | 1 | 1 | provided | SadoEE |  | class CInfGame |
| `m_saveVSBreathRoll` | 1 | 1 | provided | tweaks |  | class CGameSprite |
| `m_scriptRes` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_secondaryProjectile` | 1 | 1 | missing | tweaks |  | class ? |
| `m_source` | 1 | 1 | provided | bg2narrator |  | class CAIAction |
| `m_string2` | 1 | 1 | provided | bg2narrator |  | class CAIAction |
| `m_terrainTable` | 1 | 1 | missing | tweaks |  | class CProjectile |
| `m_usageCount` | 1 | 1 | provided | SadoEE |  | class ? |
| `m_xpValue` | 1 | 1 | provided | SadoEE |  | class CCreatureFileHeader |

## EEex opcodes 400-409 (8)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `401` | 11 | 227 | provided | Bardic-Wonders, Shadow-Magic, b-kits, epic-thieving, high-power-bg, house-rule-tweaks, improved-hof, olvynspells, proficiencies, tweaks, warlock | `parameter1=1 parameter2=1 special=IDS_OF_SYMBOL target=1 tim`×43, `parameter1=1 parameter2=1 special=IDS_OF_SYMBOL target=2 tim`×40, `-`×37 | via ADD_CRE_EFFECT, ADD_EXTENDED_SKILL, ADD_ITEM_EQEFFECT, ADD_SPELL_EFFECT, ALTER_EFFECT, ALTER_SPELL_EFFECT |
| `402` | 6 | 219 | provided | chriz-bg-rebalance, high-power-bg, improved-hof, olvynspells, tweaks, workshop-kitpack | `parameter1=20 resource=MEMODSTA special=79 target=1 timing=9`×7, `power=2 resource=MESTATPR target=2 timing=0`×6, `parameter1=1 parameter2=spellLevel resource=EXMODMEM savingt`×6 | via ADD_CRE_EFFECT, ADD_ITEM_EFFECT, ADD_ITEM_EQEFFECT, ADD_SPELL_CFEFFECT, ADD_SPELL_EFFECT, ALTER_EFFECT |
| `403` | 6 | 53 | provided | SadoEE, high-power-bg, improved-hof, olvynspells, tweaks, xgt-xp-gain | `duration=duration resource=spellRes target=2 timing=timing`×6, `parameter1=0 parameter2=121 savingthrow=0 special=0`×3, `resource=MECIDSET target=2 timing=9`×3 | via ADD_CRE_EFFECT, ADD_ITEM_EQEFFECT, ALTER_EFFECT, ALTER_ITEM_EFFECT, CLONE_EFFECT, DELETE_EFFECT |
| `408` | 3 | 9 | missing | high-power-bg, olvynspells, tweaks | `special=1`×4, `special=(i`×2, `durationtype=9 m_sourceres=%SPELLCASTER_SPELL_PENETRATION% r`×1 | via ALTER_SPELL_EFFECT, lua |
| `406` | 3 | 7 | missing | high-power-bg, improved-hof, olvynspells | `duration=60 target=1 timing=0`×4, `duration=15 target=2 timing=10`×3 | via lua |
| `400` | 3 | 5 | missing | high-power-bg, improved-hof, olvynspells | `-`×2, `dicenumber=EEex_ReadDw duration=EEex_ReadDword(effectData pa`×2, `dicenumber=EEex_ReadDword(effect duration=EEex_ReadDword(eff`×1 | via ALTER_EFFECT, lua |
| `407` | 3 | 3 | missing | high-power-bg, improved-hof, olvynspells | `duration=1 parameter1=casterlvl parameter2=2 resource=MEUNST`×3 | via lua |
| `409` | 2 | 3 | missing | high-power-bg, olvynspells | `parameter1=1 resource=MEFAMILT target=1 timing=9`×2, `parameter1=1 resource=EXBERSER`×1 | via ADD_SPELL_EFFECT, CLONE_EFFECT |

## Script IDS entries and IDS / 2DA appends (79)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `EEex_LuaAction` | 7 | 80 | provided | SadoEE, bg-eeex-buffbot, chriz-bg-modpack, chriz-sod-rebalance, diablofication, tweaks, xgt-xp-gain | `(str)`×76, `ref`×2, `(expr, var, field)`×1 |  |
| `EEex_LuaTrigger` | 5 | 6781 | provided | SadoEE, chriz-playable-races, poisoned-pathways, tactics-remix, tweaks | `(str)`×6573, `(...)`×136, `ref`×71 |  |
| `EEex_LuaObject` | 5 | 17 | provided | SadoEE, eet-tweaks, high-power-bg, improved-hof, olvynspells | `ref`×17 |  |
| `EEex_Target` | 2 | 22 | provided | chriz-bg-rebalance, tweaks | `(str)`×22 |  |
| `EEex_MatchObject` | 2 | 6 | provided | high-power-bg, olvynspells | `ref`×6 |  |
| `STATS.IDS READ_SCROLLS` | 2 | 4 | provided | b-kits, proficiencies | `append`×4 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS MAGE_LEVEL` | 2 | 3 | provided | b-kits, proficiencies | `append`×3 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS PRIEST_LEVEL` | 2 | 3 | provided | b-kits, proficiencies | `append`×3 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS USE_POISON` | 2 | 3 | provided | b-kits, proficiencies | `append`×3 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS %code%` | 2 | 2 | provided | morpheus562-kitpack, tactics-remix | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS BARDIC_KNOWLEDGE` | 2 | 2 | provided | b-kits, proficiencies | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS BARTER` | 2 | 2 | provided | b-kits, proficiencies | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS PERFORMANCE` | 2 | 2 | provided | b-kits, proficiencies | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `EEex_SpellObjectOffsetNoDec` | 1 | 426 | provided | tactics-remix | `(expr, var, expr)`×360, `ref`×66 |  |
| `EEex_SpellObjectOffset` | 1 | 172 | provided | tactics-remix | `(expr, var, expr)`×146, `ref`×26 |  |
| `EEex_ForceSpellObjectOffset` | 1 | 156 | provided | tactics-remix | `(expr, var, expr)`×119, `ref`×37 |  |
| `EEex_ReallyForceSpellObjectOffset` | 1 | 142 | provided | tactics-remix | `(expr, var, expr)`×112, `ref`×30 |  |
| `EEex_IsImmuneToOpcode` | 1 | 19 | provided | tweaks | `(var, num)`×19 |  |
| `EEex_ForceSpellObjectOffsetRES` | 1 | 4 | provided | tactics-remix | `(str, expr, expr)`×3, `ref`×1 |  |
| `EEex_LuaDecode` | 1 | 2 | provided | tweaks | `(str)`×2 |  |
| `EEex_SpellObjectOffsetNoDecRES` | 1 | 2 | provided | tactics-remix | `(str, expr, expr)`×1, `ref`×1 |  |
| `STATS.IDS ARCHERY` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS ARMOR_PROF` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS AXE` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS BLUNT` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS BOW` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CONCENTRATION` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CONDITIONING` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS DEVOTION` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS EXOTIC_SWORD` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS LARGE_SWORD` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS MISSILE` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS POLEARM` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS POWER` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SMALL_SWORD` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SPELLCRAFT` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SPELLPEN` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SPIKED` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SWIFTBLADE` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS THROWN` | 1 | 2 | provided | skills-and-abilities | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS TREAT_AFFLICTION` | 1 | 2 | provided | proficiencies | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS TREAT_WOUND` | 1 | 2 | provided | proficiencies | `append`×2 | X-STATS.2DA + opcode 401 (IEX) |
| `EEex_LuaAction_Object` | 1 | 1 | missing | chriz-bg-modpack | `ref`×1 | no IDS entry in IEX.tp2 |
| `EEex_SpellObjectOffsetRES` | 1 | 1 | provided | tweaks | `(str, call:EEex_Target, expr)`×1 |  |
| `STATS.IDS %value%` | 1 | 1 | provided | tweaks | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_ARMOR_OF_FAITH` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_BLADE_BARRIER` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_CHAOTIC_COMMANDS` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_DEFENSIVE_HARMONY` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_FREE_ACTION` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_INSECT_PLAGUE` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_PHYSICAL_MIRROR` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_REGENERATION` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS CLERIC_SHIELD_OF_THE_ARCHONS` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS PROTECTION_FROM_EVIL` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS SCRIPTINGSTATE6` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS THIEF_LEVEL` | 1 | 1 | provided | b-kits | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS TRUE_SIGHT` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS USE_INSTRUMENT` | 1 | 1 | provided | proficiencies | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_FIRE_SHIELD` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_GREATER_MALISON` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_IMPROVED_ALACRITY` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_KHELBENS_WARDING_WHIP` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_MISLEAD` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_ENERGY` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_MAGIC_ENERGY` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_MAGIC_WEAPONS` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_NORMAL_MISSILES` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_NORMAL_WEAPONS` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_PETRIFICATION` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_PROTECTION_FROM_THE_ELEMENTS` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_RESIST_FEAR` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_SPELL_DEFLECTION` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_SPELL_IMMUNITY` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_SPELL_SHIELD` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_SPELL_TRAP` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_SPELL_TURNING` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `STATS.IDS WIZARD_TENSERS_TRANSFORMATION` | 1 | 1 | provided | tactics-remix | `append`×1 | X-STATS.2DA + opcode 401 (IEX) |
| `X-STATS.2DA %identifier%` | 1 | 1 | mod data | tweaks | `append`×1 | the mod appends it |

## EEex data and Lua files (28)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `M___EEEX.LUA` | 7 | 30 | missing | bg-eeex-buffbot, bg2narrator, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, chriz-sod-rebalance, eeex-remote-console | `FILE_EXISTS_IN_GAME`×18, `FILE_EXISTS`×12 |  |
| `EEEX_MODULES.LUA` | 4 | 9 | missing | bubb-infinityui, chriz-bg-modpack, high-power-bg, iui | `FILE_EXISTS`×3, `COPY_EXISTING`×3, `COPY`×2 |  |
| `INFINITYLOADER.INI` | 3 | 32 | missing | bg-eeex-buffbot, eeex-remote-console, pathfinding-redux | `COPY`×22, `FILE_EXISTS`×8, `MENTION`×2 | IEX does not read it |
| `M__EEEX.LUA` | 2 | 32 | missing | b-kits, proficiencies | `FILE_EXISTS_IN_GAME`×32 |  |
| `EEEX_BRD.LUA` | 2 | 7 | missing | b-kits, proficiencies | `COPY_EXISTING`×5, `FILE_EXISTS_IN_GAME`×2 |  |
| `EEEX.DLL` | 2 | 6 | missing | chriz-bg-modpack, pathfinding-redux | `FILE_EXISTS`×3, `LUA`×2, `MENTION`×1 | EEex binary probe (IEX has IEX.dll / IEXLauncher.exe) |
| `EEEX_ACTIONBAR.LUA` | 2 | 6 | partial | The-Artisan-s-Kitpack, house-rule-tweaks | `FILE_EXISTS_IN_GAME`×6 | IEX ships it in IEX/, not override (probes need patch_mod.py) |
| `EEEX_RESOURCE.LUA` | 2 | 6 | partial | chriz-bg-rebalance, chriz-playable-races | `FILE_CONTAINS_EVALUATED`×6 | IEX ships it in IEX/, not override (probes need patch_mod.py) |
| `INFINITYLOADER.DB` | 2 | 6 | missing | chriz-bg-modpack, wares-of-the-planes | `FILE_EXISTS`×3, `FILE_CONTAINS`×2, `MENTION`×1 | EEex binary probe (IEX has IEX.dll / IEXLauncher.exe) |
| `B3CONRED.LUA` | 2 | 4 | missing | b-kits, workshop-kitpack | `COPY`×4 |  |
| `EEEX_ASSEMBLY.LUA` | 2 | 3 | missing | chriz-playable-races, pathfinding-redux | `FILE_CONTAINS_EVALUATED`×2, `LUA`×1 | named only in Lua code (runtime file or module name) |
| `INFINITYLOADER.EXE` | 2 | 3 | missing | bg2narrator, pathfinding-redux | `MENTION`×1, `FILE_EXISTS`×1, `LUA`×1 | EEex binary probe (IEX has IEX.dll / IEXLauncher.exe) |
| `EEEX.EXE` | 2 | 2 | missing | bg2narrator, pathfinding-redux | `FILE_EXISTS`×1, `LUA`×1 | EEex binary probe (IEX has IEX.dll / IEXLauncher.exe) |
| `EEEX_INI.LUA` | 2 | 2 | missing | improved-hof, olvynspells | `COPY_EXISTING`×2 |  |
| `EEEX_SPRITE.LUA` | 1 | 54 | partial | bg-eeex-buffbot | `FILE_EXISTS`×27, `MENTION`×27 | IEX ships it in IEX/, not override (probes need patch_mod.py) |
| `EEEX_OPTIONS.LUA` | 1 | 27 | partial | bg-eeex-buffbot | `FILE_EXISTS`×27 | IEX ships it in IEX/, not override (probes need patch_mod.py) |
| `EEEX.INI` | 1 | 6 | missing | SadoEE | `COPY`×4, `FILE_EXISTS`×1, `MENTION`×1 | IEX does not read it |
| `EEEX_CRA.LUA` | 1 | 3 | mod data | high-power-bg | `COPY`×2, `FILE_EXISTS_IN_GAME`×1 | file of the mod itself |
| `EEEX_REMOTE_CMD.LUA` | 1 | 3 | info | eeex-remote-console | `LUA`×3 | named only in Lua code (runtime file or module name) |
| `EEEX_GAMESTATE.LUA` | 1 | 2 | missing | chriz-playable-races | `FILE_CONTAINS_EVALUATED`×2 |  |
| `EEEX_MENU.LUA` | 1 | 2 | partial | chriz-playable-races | `FILE_CONTAINS_EVALUATED`×2 | IEX ships it in IEX/, not override (probes need patch_mod.py) |
| `X-STATS.2DA` | 1 | 2 | provided | tweaks | `APPEND`×1, `COPY_EXISTING`×1 | IEX.tp2 installs it |
| `B3SPELEX.LUA` | 1 | 1 | missing | warlock | `COPY_EXISTING`×1 |  |
| `EEEX.DB` | 1 | 1 | missing | eet-tweaks | `FILE_EXISTS`×1 | EEex binary probe (IEX has IEX.dll / IEXLauncher.exe) |
| `EEEXRC.MENU` | 1 | 1 | mod data | eeex-remote-console | `COPY`×1 | file of the mod itself |
| `M_C0SASP__EEEX.LUA` | 1 | 1 | mod data | Shadow-Magic | `COPY`×1 | file of the mod itself |
| `M_EEEXRC.LUA` | 1 | 1 | mod data | eeex-remote-console | `COPY`×1 | file of the mod itself |
| `X-CLSERG.2DA` | 1 | 1 | provided | tweaks | `COPY_EXISTING`×1 | IEX.tp2 installs it |

## Menus used (653)

136 defined by the mods themselves, 501 game UI menus (or created at runtime); only the others are listed (all are in inventory.json).

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `B3Identify_Menu` | 2 | 6 | missing | b-kits, workshop-kitpack | `Infinity_PopMenu`×4, `Infinity_PushMenu`×2 | EEex menu (IEX ships no .menu) |
| `B3EffectMenu_Menu` | 2 | 2 | missing | high-power-bg, olvynspells | `EEex_Menu_IsCursorWithin`×2 | EEex menu (IEX ships no .menu) |
| `B3Spell_StoredInstance` | 1 | 4 | missing | SpellMenuExtended | `Infinity_SetArea`×4 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_Rect` | 1 | 2 | missing | SpellMenuExtended | `EEex_Menu_AddBeforeUIItemRenderListener`×1, `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell` | 1 | 1 | missing | SpellMenuExtended | `EEex_Menu_LoadFile`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_ExitBackground` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_ExitBackgroundDark` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_Options_ExitBackground` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_Options_ExitBackgroundDark` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_Options_OptionsBackground` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_Options_SelectSlotArea` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_Accept` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_BottomHandle` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_LeftHandle` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_RightHandle` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |
| `B3Spell_Menu_SelectSlotArea_TopHandle` | 1 | 1 | missing | SpellMenuExtended | `Infinity_SetArea`×1 | EEex menu (IEX ships no .menu) |

## EEex_Modules switches (3)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `B3Scale` | 2 | 32 | missing | bubb-infinityui, iui | `read`×32 | IEX has no EEex_Modules switches |
| `ME_DAMAB` | 2 | 7 | missing | high-power-bg, olvynspells | `read`×4, `write true`×3 | IEX has no EEex_Modules switches |
| `B3Invis` | 1 | 3 | missing | high-power-bg | `write true`×3 | IEX has no EEex_Modules switches |

## Settings (option keys) (97)

| store | section | key | mods | ops | default / value | IEX status | notes |
|---|---|---|---|---|---|---|---|
| Baldur.lua | Program Options | Display Subtitles | bubb-infinityui, iui, tweaks | gets | -1, 1 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgLoadColumns | bubb-infinityui, iui | gets, sets | 1, rgLoadColumns | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgLoadSort | bubb-infinityui, iui | gets, sets | 0, rgLoadSort | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Graphics | RgSettingEEexZoomUI | bubb-infinityui, iui | gets, sets | 0, RgSettingEEexZoomUI | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Program Options | Active Campaign | bubb-infinityui, iui | gets, sets | -, buttonNum, const.START_CAMPAIGN_BG1 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgQuicklootFilterJunk | bubb-infinityui, iui | gets, sets | 0, RgQuicklootFilterJunk | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgHotkeyButtonsVisibility | bubb-infinityui, iui | gets, sets | 0, RgHotkeyButtonsVisibility | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgInventoryMode | bubb-infinityui, iui | gets, sets | 0, rgInventoryMode | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgIsModernHud | bubb-infinityui, iui | gets, sets | 0, RgIsModernHud | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgLoadName | bubb-infinityui, iui | sets | rgLoadName | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgMessageboxUnlocked | bubb-infinityui, iui | gets, sets | 0, RgMessageboxUnlocked | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgModernHudRight | bubb-infinityui, iui | gets, sets | 0, RgModernHudRight | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgQuicklootBottom | bubb-infinityui, iui | gets, sets | 0, RgQuicklootBottom | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgQuicklootRows | bubb-infinityui, iui | gets, sets | 3, RgQuicklootRows | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgSpaceAdvanceDialog | bubb-infinityui, iui | gets, sets | 0, RgSpaceAdvanceDialog | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgStoreMode | bubb-infinityui, iui | gets, sets | 0, rgStoreMode | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgUISkin | bubb-infinityui, iui | gets, sets | 0, RgUISkin | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgBestiaryKoef | bubb-infinityui, iui | gets, sets | 1, RgBestiaryKoef | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgInvPartyModeHover | bubb-infinityui, iui | gets, sets | 0, 1, RgInvPartyModeHover | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgLargePortraits | bubb-infinityui, iui | gets, sets | 0, RgLargePortraits | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgQuicklootCenter | bubb-infinityui, iui | gets, sets | 0, RgQuicklootCenter | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowAlwaysOn | bubb-infinityui, iui | gets, sets | 0, rgRadarShowAlwaysOn | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowCreaturesB | bubb-infinityui, iui | gets, sets | 0, rgRadarShowCreaturesB | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowCreaturesG | bubb-infinityui, iui | gets, sets | 0, rgRadarShowCreaturesG | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowCreaturesR | bubb-infinityui, iui | gets, sets | 0, rgRadarShowCreaturesR | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowExtendRadius | bubb-infinityui, iui | gets, sets | 0, rgRadarShowExtendRadius | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowHitPoints | bubb-infinityui, iui | gets, sets | 0, rgRadarShowHitPoints | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowMinimizedBar | bubb-infinityui, iui | gets, sets | 0, rgRadarShowMinimizedBar | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowNames | bubb-infinityui, iui | gets, sets | 0, rgRadarShowNames | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowNpcEffects | bubb-infinityui, iui | gets, sets | 0, rgRadarShowNpcEffects | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowPcEffects | bubb-infinityui, iui | gets, sets | 0, RgRadarShowPcEffects, rgRadarShowPcEffects | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowSingleCre | bubb-infinityui, iui | gets, sets | 1, rgRadarShowSingleCre | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowTresholds | bubb-infinityui, iui | gets, sets | 0, rgRadarShowTresholds | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowWeapons | bubb-infinityui, iui | gets, sets | 0, rgRadarShowWeapons | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarShowMetaInfo | bubb-infinityui, iui | gets, sets | 0, rgRadarShowMetaInfo | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | <'RgHotkeyButton' .. i> | bubb-infinityui, iui | sets | RgHotkeyButtonsTable[i][1] .. ',' .. RgH | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgMessUnlockedCoor | bubb-infinityui, iui | sets | x .. ',' .. y .. ',' .. w .. ',' .. h | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Lua Edit | <"String"..i-1> | bubb-infinityui, iui | sets | luaEditHistory[i] | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Multiplayer | Player Name | bubb-infinityui, iui | sets | connectionPlayerNameEdit | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Multiplayer | Session Name | bubb-infinityui, iui | sets | connectionSessionNameEdit | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Multiplayer | Session Password | bubb-infinityui, iui | sets | connectionSessionPasswordEdit | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Program Options | EET Installation State | bubb-infinityui, iui | gets | - | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Program Options | Use Touch Actionbar | bubb-infinityui, iui | gets | default | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgFullBodyPortrait | bubb-infinityui, iui | gets, sets | 0, rgFullBodyPortrait | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgInvPaperdolls | bubb-infinityui, iui | gets, sets | 0, RgInvPaperdolls | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarKey | bubb-infinityui, iui | sets | RgRadarKey | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgInvPartyFastLoad | bubb-infinityui, iui | sets | RgInvPartyFastLoad | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Game Options | RgRadarMetaInfo | bubb-infinityui, iui | sets | rgRadarMetaInfo | same | engine INI (Baldur.lua), identical under EEex and IEX |
| InfinityLoader.ini | General | LuaLibrary | bg-eeex-buffbot | tp2 reads, tp2 writes | ?, [^%WNL%%MNL%%LNL%]*, lua51[.]dll, lua51[.]dll[^%WNL%%MNL% | missing | IEX does not read InfinityLoader.ini |
| InfinityLoader.ini | General | LuaPatchMode | bg-eeex-buffbot | tp2 reads, tp2 writes | ?, REPLACE_INTERNAL_WITH_EXTERNAL, REPLACE_INTERNAL_WITH_EXT | missing | IEX does not read InfinityLoader.ini |
| InfinityLoader.ini | General | LuaVersionExternal | bg-eeex-buffbot | tp2 reads, tp2 writes | %lua_version_pattern%, %lua_version_pattern%[^%WNL%%MNL%%LNL | missing | IEX does not read InfinityLoader.ini |
| Baldur.lua | <Infinity_GetINIValue> | BuffBot | bg-eeex-buffbot | gets | "BB_LabProbeAbsent", "BB_LabProbeNeg", "BB_LabProbeNum", "BB | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | <Infinity_SetINIValue> | BuffBot | bg-eeex-buffbot | sets | "BB_LabProbeEmpty", "BB_LabProbeNeg", "BB_LabProbeNum", "BB_ | same | engine INI (Baldur.lua), identical under EEex and IEX |
| EEex.ini | Empty Container Module | Enable | SadoEE | tp2 writes | 1 | missing | IEX does not read EEex.ini |
| Baldur.lua | BuffBot | <key> | bg-eeex-buffbot | gets, sets | default, value | same | engine INI (Baldur.lua), identical under EEex and IEX |
| InfinityLoader.ini | - | LuaPatchMode | eeex-remote-console | tp2 reads | REPLACE_INTERNAL_WITH_EXTERNAL | missing | IEX does not read InfinityLoader.ini |
| Baldur.lua | Bubbs Spell Menu Extended | Always Open | SpellMenuExtended | gets, sets | 0, B3Spell_AlwaysOpen | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Auto-Pause | SpellMenuExtended | gets, sets | 1, B3Spell_AutoPause | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Automatically Focus Search Bar | SpellMenuExtended | gets, sets | 1, B3Spell_AutoFocusSearchBar | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Automatically Optimize Slot Size | SpellMenuExtended | gets, sets | 1, B3Spell_AutomaticallyOptimizeSlotSize | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Darken Background | SpellMenuExtended | gets, sets | 0, B3Spell_DarkenBackground | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Disable Control Bar | SpellMenuExtended | gets, sets | 0, B3Spell_DisableControlBar | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Disable Search Bar | SpellMenuExtended | gets, sets | 0, B3Spell_DisableSearchBar | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Horizontal Alignment | SpellMenuExtended | gets, sets | 1, B3Spell_HorizontalAlignment | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Ignore Special Abilities | SpellMenuExtended | gets, sets | 0, B3Spell_IgnoreSpecialAbilities | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Keep Portraits Functional | SpellMenuExtended | gets, sets | 1, B3Spell_KeepPortraitsFunctional | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Modal | SpellMenuExtended | gets, sets | 1, B3Spell_Modal | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Monolithic Display Mode | SpellMenuExtended | gets, sets | 0, B3Spell_MonolithicDisplayMode | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Monolithic Display Sort Mode | SpellMenuExtended | gets, sets | B3Spell_MonolithicDisplaySortModes.Innat, B3Spell_Monolithic | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Move Slot Headers To The Right | SpellMenuExtended | gets, sets | 0, B3Spell_MoveSlotHeadersToTheRight | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Preferred Slot Size | SpellMenuExtended | gets, sets | B3Spell_SlotSizeHardMaximum, B3Spell_PreferredSlotSize | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Show Key Bindings | SpellMenuExtended | gets, sets | 1, B3Spell_ShowKeyBindings | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Slots Area H | SpellMenuExtended | gets, sets | -1, B3Spell_SlotsAreaH | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Slots Area W | SpellMenuExtended | gets, sets | -1, B3Spell_SlotsAreaW | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Slots Area X | SpellMenuExtended | gets, sets | -1, B3Spell_SlotsAreaX | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Slots Area Y | SpellMenuExtended | gets, sets | -1, B3Spell_SlotsAreaY | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Bubbs Spell Menu Extended | Vertical Alignment | SpellMenuExtended | gets, sets | 1, B3Spell_VerticalAlignment | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | BuffBot | Debug | bg-eeex-buffbot | gets, sets | 0, BfBot._debugMode | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | SadoQoL | <'Bind ' .. key> | SadoEE | gets, sets | -999, code | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | SadoQoL | FPS | SadoEE | gets, sets | 1, T.on and 1 or 0 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Script | IntervalSaveCombat | tweaks | tp2 writes | %combat%, 0 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Script | IntervalSaveEnabled | tweaks | tp2 writes | %enabled%, 1 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | <BG2Narrator.ipcProfileSection> | <slot> | bg2narrator | sets | escapeIniValue(line) | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | <BG2Narrator.ipcProfileSection> | LastSeq | bg2narrator | sets | tostring(BG2Narrator.ipcSeq) | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | AutoRoller | <key> | SadoEE | gets | default | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | AutoRoller | Duration | SadoEE | sets | autoRoller.duration | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | AutoRoller | StrWeight | SadoEE | sets | autoRoller.weight | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Party Stash | Camp Merchant Board | SadoEE | sets | G.skin | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | SadoQoL | <'Mouse ' .. OLD[key]> | SadoEE | gets | -999 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| Baldur.lua | Script | %baldur_lua_setting% | tweaks | tp2 writes | 1 | same | engine INI (Baldur.lua), identical under EEex and IEX |
| EEex_Options | (custom storage) | BuffBot_Accent | bg-eeex-buffbot | registers | 1 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | (custom storage) | BuffBot_DarkMode | bg-eeex-buffbot | registers | 0 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | (custom storage) | BuffBot_ItemUseMode | bg-eeex-buffbot | registers | 1 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | (custom storage) | BuffBot_RefreshBelow | bg-eeex-buffbot | registers | 1 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | (custom storage) | BuffBot_TextSize | bg-eeex-buffbot | registers | 2 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | SadoQoL | Options Page Line | SadoEE | registers | 0 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |
| EEex_Options | SadoQoL | row[2] | SadoEE | registers | row.default or 1 | partial | IEX: Baldur.lua [section] key through Infinity_GetINIValue / Infinity_SetINIValue (lua/EEex_Options.lua; storage:read()  |

## Hard usage (asm / hooks / raw memory) (40)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `EEex_EnableCodeProtection` | 10 | 83 | provided | SadoEE, bgee-graphics-enhanced, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, ie-enhancer, olvynspells, pathfinding-redux, stick-lua-functions | `()`×71, `ref`×11, `assign`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_DisableCodeProtection` | 10 | 76 | provided | SadoEE, bgee-graphics-enhanced, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, high-power-bg, ie-enhancer, olvynspells, pathfinding-redux, stick-lua-functions | `()`×64, `ref`×11, `assign`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Write32` | 7 | 288 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack, chriz-bg-rebalance, high-power-bg, olvynspells, pathfinding-redux | `(expr, num)`×96, `(expr, var)`×49, `(expr, expr)`×34 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Label` | 7 | 128 | provided | SadoEE, chriz-bg-rebalance, high-power-bg, improved-hof, olvynspells, pathfinding-redux, stick-lua-functions | `(str)`×123, `ref`×4, `assign`×1 | labels: CBaldurChitin::m_pObjectGame, CGameAIBase::FireSpell()_DecodeProjectile, CGameAIBase::FireSpellPoint()_DecodeProjectile, CGameAIBase::ForceSpell()_CProj |
| `EEex_FlattenTable` | 6 | 206 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, pathfinding-redux, stick-lua-functions | `(table)`×139, `(...)`×38, `(table{args,labelSuffix,returnType})`×10 | x64 asm / hooks / raw memory |
| `EEex_HookIntegrityWatchdogRegister` | 5 | 382 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `.RAX`×87, `.RDX`×59, `.R8`×58 | x64 asm / hooks / raw memory |
| `EEex_GenLuaCall` | 5 | 143 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(str, table)`×84, `(str, table{args,returnType})`×32, `ref`×7 | x64 asm / hooks / raw memory |
| `EEex_JITNear` | 5 | 81 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(table)`×28, `(expr)`×26, `(call:EEex_FlattenTable)`×18 | x64 asm / hooks / raw memory |
| `EEex_Malloc` | 5 | 75 | provided | SadoEE, bg2-radar-overlay, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `(expr)`×34, `(num)`×32, `ref`×4 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Write8` | 5 | 26 | provided | bg2-radar-overlay, chriz-bg-modpack, high-power-bg, olvynspells, pathfinding-redux | `(expr, var)`×8, `(expr, num)`×5, `(expr, field)`×5 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_Write64` | 4 | 45 | provided | SadoEE, chriz-bg-modpack, high-power-bg, olvynspells | `(expr, var)`×20, `(expr, expr)`×6, `(expr, num)`×6 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_HookBeforeCallWithLabels` | 4 | 11 | unsupported | SadoEE, chriz-bg-modpack, chriz-bg-rebalance, pathfinding-redux | `(expr, table, var)`×5, `ref`×1, `(field, table, table)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookBeforeRestoreWithLabels` | 3 | 86 | unsupported | chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(expr, num, num, num, table, var)`×20, `(num, num, num, num, table, call:EEex_FlattenTable)`×19, `(expr, num, num, num, table, call:EEex_FlattenTable)`×12 | x64 asm / hooks / raw memory |
| `EEex_WritePtr` | 3 | 38 | unsupported | SadoEE, chriz-bg-rebalance, pathfinding-redux | `(expr, var)`×22, `ref`×5, `(expr, expr)`×4 | x64 asm / hooks / raw memory |
| `EEex_HookAfterRestoreWithLabels` | 3 | 29 | unsupported | chriz-bg-rebalance, pathfinding-redux, stick-lua-functions | `(expr, num, num, num, table, call:EEex_FlattenTable)`×9, `(expr, num, num, num, table, var)`×7, `ref`×4 | x64 asm / hooks / raw memory |
| `EEex_JITAt` | 3 | 12 | unsupported | chriz-bg-modpack, pathfinding-redux, stick-lua-functions | `(expr, field)`×7, `(field, field)`×2, `assign`×2 | x64 asm / hooks / raw memory |
| `EEex_Write16` | 3 | 3 | provided | SadoEE, high-power-bg, olvynspells | `(var, var)`×2, `(expr, num)`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_WriteU8` | 2 | 87 | provided | SadoEE, chriz-bg-modpack | `(expr, num)`×18, `(expr, expr)`×16, `(expr, field)`×15 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_HookAfterCallWithLabels` | 2 | 50 | unsupported | pathfinding-redux, stick-lua-functions | `(num, table, call:EEex_FlattenTable)`×31, `(expr, table, call:EEex_FlattenTable)`×7, `(var, table, call:EEex_FlattenTable)`×6 | x64 asm / hooks / raw memory |
| `EEex_WriteU32` | 2 | 42 | provided | SadoEE, chriz-bg-rebalance | `(expr, field)`×17, `(expr, num)`×13, `(expr, var)`×4 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_JITNearAsLuaFunction` | 2 | 39 | unsupported | chriz-bg-modpack, pathfinding-redux | `(str, table)`×27, `ref`×6, `(var, var)`×4 | x64 asm / hooks / raw memory |
| `EEex_HookShimFunctionMaintainOriginal` | 2 | 8 | unsupported | chriz-bg-modpack, chriz-playable-races | `ref`×7, `(var, num, str, expr)`×1 | labels: CBMXPProbe::Original104 |
| `EEex_HookAfterRestore` | 2 | 6 | unsupported | high-power-bg, olvynspells | `(call:EEex_Label, num, num, table)`×6 | x64 asm / hooks / raw memory |
| `EEex_WriteStringAuto` | 2 | 6 | unsupported | high-power-bg, olvynspells | `(str)`×6 | x64 asm / hooks / raw memory |
| `EEex_WriteStringCache` | 2 | 5 | unsupported | chriz-playable-races, pathfinding-redux | `ref`×2, `(field)`×2, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_WriteU16` | 2 | 4 | provided | SadoEE, chriz-bg-rebalance | `ref`×2, `(var, var)`×1, `(expr, num)`×1 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_HookBeforeConditionalJumpWithLabels` | 2 | 3 | unsupported | chriz-bg-rebalance, stick-lua-functions | `(...)`×2, `(var, num, table, var)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookConditionalJumpWithLabels` | 2 | 2 | unsupported | pathfinding-redux, stick-lua-functions | `assign`×1, `(var, num, table, table, call:EEex_FlattenTable)`×1 | x64 asm / hooks / raw memory |
| `EEex_WriteWord` | 1 | 36 | unsupported | improved-hof | `(expr, expr)`×15, `(expr, var)`×12, `(expr, num)`×5 | x64 asm / hooks / raw memory |
| `EEex_HookBeforeAndAfterCallWithLabels` | 1 | 17 | unsupported | pathfinding-redux | `(expr, var, field, field)`×12, `(expr, var, call:EEex_FlattenTable, call:EEex_FlattenTable)`×4, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_Memcpy` | 1 | 14 | unsupported | pathfinding-redux | `ref`×5, `(var, var, num)`×4, `(var, var, expr)`×4 | x64 asm / hooks / raw memory |
| `EEex_HookReplaceFunctionMaintainOriginal` | 1 | 10 | unsupported | chriz-bg-modpack | `ref`×4, `(var, var, str, var)`×4, `(field, field, str, field)`×2 | labels: CBMR::original_CreateMakeDualClass, CBMR::original_MakeDualClass |
| `EEex_HookRemoveCallWithLabels` | 1 | 7 | unsupported | pathfinding-redux | `(expr, table, expr)`×4, `(expr, table, var)`×2, `assign`×1 | x64 asm / hooks / raw memory |
| `EEex_AllocNear` | 1 | 6 | provided | SadoEE | `(expr)`×4, `(num)`×2 | IEX has it (raw memory / code protection / symbol lookup); addresses and offsets the mod passes are its own |
| `EEex_HookAfterCall` | 1 | 4 | unsupported | chriz-bg-modpack | `ref`×2, `(var, expr)`×2 | x64 asm / hooks / raw memory |
| `EEex_HookConditionalJumpOnSuccess` | 1 | 2 | unsupported | chriz-bg-rebalance | `(var, num, var)`×1, `[]`×1 | x64 asm / hooks / raw memory |
| `EEex_WriteByte` | 1 | 2 | unsupported | improved-hof | `(expr, expr)`×2 | x64 asm / hooks / raw memory |
| `EEex_HookConditionalJumpOnSuccessWithLabels` | 1 | 1 | unsupported | stick-lua-functions | `(expr, num, table, call:EEex_FlattenTable)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookIntegrityWatchdog_IgnoreStackSizes` | 1 | 1 | unsupported | SadoEE | `(var, table)`×1 | x64 asm / hooks / raw memory |
| `EEex_HookIntegrityWatchdog_Load` | 1 | 1 | unsupported | pathfinding-redux | `assign`×1 | x64 asm / hooks / raw memory |

## Engine symbols / hook labels named in strings (67)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `CBaldurChitin::m_pObjectGame` | 3 | 4 | partial | high-power-bg, improved-hof, olvynspells | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameAIBase::ForceSpell()_CProjectile::AddEffect()` | 2 | 2 | partial | high-power-bg, olvynspells | `string`×2 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameAIBase::ForceSpellPoint()_CProjectile::AddEffect()` | 2 | 2 | partial | high-power-bg, olvynspells | `string`×2 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::Spell()_CProjectile::AddEffect()` | 2 | 2 | partial | high-power-bg, olvynspells | `string`×2 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::SpellPoint()_CProjectile::AddEffect()` | 2 | 2 | partial | high-power-bg, olvynspells | `string`×2 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CProjectile::AddEffect` | 2 | 2 | unsupported | high-power-bg, olvynspells | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CProjectile::DecodeProjectile` | 2 | 2 | partial | high-power-bg, olvynspells | `string`×2 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CDerivedStats::SetLevel` | 1 | 8 | partial | chriz-bg-modpack | `string`×8 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameObjectArray::GetShare` | 1 | 6 | partial | pathfinding-redux | `string`×6 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `EEex::Sprite_Hook_OnConstruct` | 1 | 6 | unsupported | chriz-bg-modpack | `string`×6 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `EEex::Sprite_Hook_OnDestruct` | 1 | 6 | unsupported | chriz-bg-modpack | `string`×6 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CMessageHandler::AddMessage` | 1 | 5 | partial | pathfinding-redux | `string`×5 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `C2DArray::GetAt` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CAIObjectType::GetActiveInactiveClasses` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CAIObjectType::IsUsableSubClass` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CAbilityData::CAbilityData` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMBank::CheckStatsChangeGetXPCap` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMBank::GetXPCap` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMI::original_` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CDWordArray::CDWordArray` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CDerivedStats::CDerivedStats` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CDerivedStats::GetLevel` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CDerivedStats::~CDerivedStats` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameAnimationType::GetMoveScale` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameEffect::DecodeEffectFromBase` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameEffectBase::CGameEffectBase` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameObject::GetAIType` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::AddNewSpecialAbilities` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::CombineAllActiveInactiveProficiencies` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::GetActiveProficiency` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::GetInactiveProficiency` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::ProcessEffectList` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameSprite::SetActiveProficiency` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::SetInactiveProficiency` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CObArray::SetAtGrow` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CObList::AddTail` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CObList::RemoveAt` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CResRef::CResRef` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CRuleTables::GetClassString` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CRuleTables::GetHitPoints` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CRuleTables::GetLevelUpAbilities` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CRuleTables::GetNextLevel` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CRuleTables::GetNumLevelUpAbilities` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CScreenCreateChar::CheckAbilityEnabled` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CScreenCreateChar::CompleteCharacterHighLevelAbilities` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CScreenCreateChar::ResetLevelUpPanel` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CScreenCreateChar::UpdateHighLevelAbilitiesPanel` | 1 | 4 | partial | chriz-bg-modpack | `string`×4 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CString::CString` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CString::~CString` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `Hook-CDerivedStats::Construct()-FirstCall` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `Hook-CDerivedStats::Destruct()-FirstCall` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `Hook-CDerivedStats::operator_equ()-FirstCall` | 1 | 4 | unsupported | chriz-bg-modpack | `string`×4 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameSprite::Shatter` | 1 | 3 | partial | improved-hof | `string`×3 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CBMA::original_ApplyEffect` | 1 | 2 | unsupported | chriz-bg-modpack | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMR::original_CreateMakeDualClass` | 1 | 2 | unsupported | chriz-bg-modpack | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMR::original_MakeDualClass` | 1 | 2 | unsupported | chriz-bg-modpack | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `EEex::bNoUUID` | 1 | 2 | unsupported | chriz-bg-modpack | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `EEex::bStripUUID` | 1 | 2 | unsupported | chriz-bg-modpack | `string`×2 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMXPProbe::Opcode104Apply` | 1 | 1 | unsupported | chriz-bg-modpack | `string`×1 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CBMXPProbe::Original104` | 1 | 1 | unsupported | chriz-bg-modpack | `string`×1 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `CGameSprite::ClearBumpPath` | 1 | 1 | partial | pathfinding-redux | `string`×1 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CGameSprite::JumpToPoint` | 1 | 1 | partial | pathfinding-redux | `string`×1 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `CProjectileArea::VFTable` | 1 | 1 | unsupported | chriz-bg-rebalance | `string`×1 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `Hook-CAIGroup::IsPartyLeader()-Override` | 1 | 1 | partial | stick-lua-functions | `string`×1 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `Hook-CGameContainer::Render()-B3EmptyContainer` | 1 | 1 | partial | SadoEE | `string`×1 | engine function known to IEX (engine description); EEex hook / label semantics not provided |
| `Hook-CGameSprite::ProcessEffectList()-FirstRandCall` | 1 | 1 | unsupported | SadoEE | `string`×1 | EEex label (hook site, vftable or EEex-internal name): needs a native IEX equivalent |
| `Hook-CVisibilityMap::IsCharacterIdOnMap()-FirstInstruction` | 1 | 1 | partial | SadoEE | `string`×1 | engine function known to IEX (engine description); EEex hook / label semantics not provided |

## EEex requirement checks (80)

| item | mods | uses | IEX status | used by | argument shapes (top) | notes |
|---|---|---|---|---|---|---|
| `MOD_IS_INSTALLED EEex.tp2 ~0~` | 19 | 133 | patched | Bardic-Wonders, Shadow-Magic, SpellMenuExtended, autodescription, bubb-infinityui, diablofication, high-power-bg, ie-skillz, improved-hof, iui, morpheus562-kitpack, olvynspells, random-graion-magic, skills-and-abilities, sod2bg2-iu, spells-and-magic, sword-coast-infinity, tactics-remix, warlock | `MOD_IS_INSTALLED`×133 | tools/compat/patch_mod.py rewrites it |
| `Lua: EEex_Active` | 10 | 99 | provided | bg-eeex-buffbot, bg2narrator, bubb-infinityui, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, diablofication, eeex-remote-console, iui, xgt-xp-gain | `ref`×97, `assign`×2 |  |
| `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` | 6 | 50 | patched | SadoEE, morpheus562-kitpack, poisoned-pathways, skills-and-abilities, tactics-remix, wares-of-the-planes | `MOD_IS_INSTALLED`×50 | tools/compat/patch_mod.py rewrites it |
| `doc: EEex v1.2.0` | 6 | 44 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, chriz-sod-rebalance, eeex-remote-console |  | EEex to v1.2.0 |
| `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` | 6 | 28 | patched | Bardic-Wonders, Shadow-Magic, aura, candlekeep-revisited, house-rule-tweaks, warlock | `MOD_IS_INSTALLED`×28 | tools/compat/patch_mod.py rewrites it |
| `doc: EEex v1.3.1` | 5 | 65 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-playable-races, eeex-remote-console |  | EEex v1.3.1 |
| `doc: EEex 1.2.0` | 5 | 35 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance, pathfinding-redux |  | EEex **1.2.0 |
| `REQUIRE_COMPONENT EEex.tp2 0` | 5 | 15 | patched | epic-thieving, high-power-bg, improved-hof, olvynspells, stick-lua-functions | `REQUIRE_COMPONENT`×15 | tools/compat/patch_mod.py rewrites it |
| `doc: EEex v0.11.0-alpha` | 4 | 42 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance, eeex-remote-console |  | EEex **v0.11.0-alpha |
| `FILE_EXISTS M___EEex.lua` | 4 | 18 | unpatched | bg2narrator, chriz-bg-rebalance, chriz-playable-races, chriz-sod-rebalance | `FILE_EXISTS`×18 | not rewritten by patch_mod.py |
| `doc: EEex 1.3.1` | 3 | 36 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance |  | EEex **1.3.1 |
| `doc: EEex v1.0.0` | 3 | 32 | info | bg-eeex-buffbot, chriz-bg-rebalance, eeex-remote-console |  | EEex **v1.0.0 |
| `doc: EEex v1.2` | 3 | 32 | info | bg-eeex-buffbot, chriz-bg-rebalance, eeex-remote-console |  | EEex component numbers: v1.2 |
| `doc: EEex 1.2` | 3 | 13 | info | bg-eeex-buffbot, chriz-bg-modpack, chriz-bg-rebalance |  | EEex 1.2 |
| `FILE_EXISTS override/M___EEex.lua` | 3 | 12 | unpatched | bg-eeex-buffbot, chriz-bg-modpack, eeex-remote-console | `FILE_EXISTS`×12 | not rewritten by patch_mod.py |
| `FILE_EXISTS InfinityLoader.ini` | 3 | 8 | unpatched | bg-eeex-buffbot, eeex-remote-console, pathfinding-redux | `FILE_EXISTS`×8 | not rewritten by patch_mod.py |
| `doc: EEex v2.7.3.0` | 3 | 7 | info | SadoEE, chriz-bg-modpack, chriz-bg-rebalance |  | EEex-v2.7.3.0 |
| `doc: EEex 2.7.3.0` | 3 | 6 | info | chriz-bg-modpack, chriz-bg-rebalance, chriz-sod-rebalance |  | EEex (BG2:EE 2.7.3.0 |
| `MOD_IS_INSTALLED EEex.tp2 0` | 2 | 63 | patched | a7-add-kit-ex, tweaks | `MOD_IS_INSTALLED`×63 | tools/compat/patch_mod.py rewrites it |
| `FILE_EXISTS M__EEex.lua` | 2 | 32 | unpatched | b-kits, proficiencies | `FILE_EXISTS`×32 | not rewritten by patch_mod.py |
| `doc: EEex v0.11` | 2 | 20 | info | bg-eeex-buffbot, chriz-bg-modpack |  | EEex v0.11 |
| `doc: EEex 1.3.0` | 2 | 19 | info | chriz-bg-rebalance, pathfinding-redux |  | EEex 1.3.0 |
| `FILE_EXISTS EEex_Actionbar.lua` | 2 | 6 | patched | The-Artisan-s-Kitpack, house-rule-tweaks | `FILE_EXISTS`×6 | tools/compat/patch_mod.py rewrites it |
| `doc: EEex v0.10.0-alpha` | 2 | 5 | info | bg-eeex-buffbot, workshop-kitpack |  | EEex (v0.10.0-alpha |
| `FILE_CONTAINS EEex_scripts/EEex_Resource.lua ^function[ %TAB%]+EEex_Resource_Load2DA` | 2 | 4 | unpatched | chriz-bg-rebalance, chriz-playable-races | `FILE_CONTAINS`×4 | not rewritten by patch_mod.py |
| `doc: EEex v0.10` | 2 | 4 | info | bg-eeex-buffbot, eeex-remote-console |  | EEex v0.10 |
| `doc: EEex v2.6.6.0` | 2 | 4 | info | chriz-bg-modpack, chriz-bg-rebalance |  | EEex/EEex/loader/v2.6.6.0 |
| `FILE_EXISTS EEex.dll` | 2 | 3 | unpatched | chriz-bg-modpack, pathfinding-redux | `FILE_EXISTS`×3 | not rewritten by patch_mod.py |
| `FILE_EXISTS InfinityLoader.db` | 2 | 3 | unpatched | chriz-bg-modpack, wares-of-the-planes | `FILE_EXISTS`×3 | not rewritten by patch_mod.py |
| `doc: EEex 0.11.0-alpha` | 2 | 3 | info | chriz-bg-rebalance, chriz-sod-rebalance |  | EEex 0.11.0-alpha |
| `doc: EEex 1.3` | 2 | 3 | info | chriz-bg-rebalance, pathfinding-redux |  | EEex 1.3 |
| `FILE_EXISTS override/EEex_Modules.lua` | 2 | 2 | unpatched | bubb-infinityui, iui | `FILE_EXISTS`×2 | not rewritten by patch_mod.py |
| `MOD_IS_INSTALLED EEex.tp2 ~1~` | 2 | 2 | unpatched | high-power-bg, olvynspells | `MOD_IS_INSTALLED`×2 | not rewritten by patch_mod.py |
| `REQUIRE_COMPONENT EEex.tp2 2` | 2 | 2 | unpatched | high-power-bg, olvynspells | `REQUIRE_COMPONENT`×2 | not rewritten by patch_mod.py |
| `doc: EEex 0.11` | 2 | 2 | info | chriz-bg-modpack, chriz-bg-rebalance |  | EEex 0.11 |
| `FILE_CONTAINS override/EEex_Sprite.lua EEex_Sprite_GetCharacterIndex` | 1 | 15 | unpatched | bg-eeex-buffbot | `FILE_CONTAINS`×15 | not rewritten by patch_mod.py |
| `FILE_EXISTS override/EEex_Options.lua` | 1 | 15 | patched | bg-eeex-buffbot | `FILE_EXISTS`×15 | tools/compat/patch_mod.py rewrites it |
| `FILE_EXISTS override/EEex_Sprite.lua` | 1 | 15 | patched | bg-eeex-buffbot | `FILE_EXISTS`×15 | tools/compat/patch_mod.py rewrites it |
| `MOD_IS_INSTALLED EEEX.TP2 ~0~` | 1 | 14 | patched | caster-crafting | `MOD_IS_INSTALLED`×14 | tools/compat/patch_mod.py rewrites it |
| `FILE_CONTAINS EEex_scripts/EEex_Sprite.lua EEex_Sprite_GetCharacterIndex` | 1 | 12 | unpatched | bg-eeex-buffbot | `FILE_CONTAINS`×12 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex_scripts/EEex_Options.lua` | 1 | 12 | unpatched | bg-eeex-buffbot | `FILE_EXISTS`×12 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex_scripts/EEex_Sprite.lua` | 1 | 12 | unpatched | bg-eeex-buffbot | `FILE_EXISTS`×12 | not rewritten by patch_mod.py |
| `doc: EEex v1.3.0` | 1 | 7 | info | chriz-bg-rebalance |  | EEex **v1.3.0 |
| `doc: EEex v0.10.3` | 1 | 4 | info | bg-eeex-buffbot |  | EEex v0.10.3 |
| `FILE_EXISTS EEex/loader/LuaJIT/LuaProvider.dll` | 1 | 3 | unpatched | bg-eeex-buffbot | `FILE_EXISTS`×3 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex/loader/LuaJIT/lua51.dll` | 1 | 3 | unpatched | bg-eeex-buffbot | `FILE_EXISTS`×3 | not rewritten by patch_mod.py |
| `doc: EEex 5.1` | 1 | 3 | info | bg-eeex-buffbot |  | EEex.tp2 \| Fallback: `5.1 |
| `doc: EEex v0.11.0` | 1 | 3 | info | bg-eeex-buffbot |  | EEex v0.11.0 |
| `doc: EEex v0.9.0` | 1 | 3 | info | bg-eeex-buffbot |  | EEex v0.9.0 |
| `FILE_CONTAINS EEex_scripts/EEex_Assembly.lua ^function[ %TAB%]+EEex_LabelDefault` | 1 | 2 | unpatched | chriz-playable-races | `FILE_CONTAINS`×2 | not rewritten by patch_mod.py |
| `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookShimFunctionMaintainOriginal` | 1 | 2 | unpatched | chriz-playable-races | `FILE_CONTAINS`×2 | not rewritten by patch_mod.py |
| `FILE_CONTAINS EEex_scripts/EEex_GameState.lua ^function[ %TAB%]+EEex_GameState_AddInitializedListener` | 1 | 2 | unpatched | chriz-playable-races | `FILE_CONTAINS`×2 | not rewritten by patch_mod.py |
| `FILE_CONTAINS EEex_scripts/EEex_Menu.lua ^function[ %TAB%]+EEex_Menu_AddAfterMainFileLoadedListener` | 1 | 2 | unpatched | chriz-playable-races | `FILE_CONTAINS`×2 | not rewritten by patch_mod.py |
| `FILE_CONTAINS EEex_scripts/EEex_Resource.lua ^function[ %TAB%]+EEex_Resource_Get2DARowTableIterator` | 1 | 2 | unpatched | chriz-bg-rebalance | `FILE_CONTAINS`×2 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex_Brd.lua` | 1 | 2 | unpatched | b-kits | `FILE_EXISTS`×2 | not rewritten by patch_mod.py |
| `doc: EEex 0.10` | 1 | 2 | info | eeex-remote-console |  | EEex 0.10 |
| `doc: EEex 1.0` | 1 | 2 | info | chriz-bg-rebalance |  | EEex 1.0 |
| `doc: EEex v0.10.1.1-alpha` | 1 | 2 | info | bg-eeex-buffbot |  | EEex v0.10.1.1-alpha |
| `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookAfterRestoreWithLabels` | 1 | 1 | unpatched | chriz-bg-rebalance | `FILE_CONTAINS`×1 | not rewritten by patch_mod.py |
| `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookConditionalJumpOnSuccess[ %TAB%]*(` | 1 | 1 | unpatched | chriz-bg-rebalance | `FILE_CONTAINS`×1 | not rewritten by patch_mod.py |
| `FILE_CONTAINS InfinityLoader.db Hook-CDerivedStats::SetSpellState()` | 1 | 1 | unpatched | wares-of-the-planes | `FILE_CONTAINS`×1 | not rewritten by patch_mod.py |
| `FILE_CONTAINS InfinityLoader.db \[CBMID::` | 1 | 1 | unpatched | chriz-bg-modpack | `FILE_CONTAINS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex.db` | 1 | 1 | unpatched | eet-tweaks | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex.exe` | 1 | 1 | unpatched | pathfinding-redux | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex.ini` | 1 | 1 | unpatched | SadoEE | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex_Cra.lua` | 1 | 1 | unpatched | high-power-bg | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS EEex_scripts/EEex_Modules.lua` | 1 | 1 | unpatched | chriz-bg-modpack | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS InfinityLoader.exe` | 1 | 1 | unpatched | pathfinding-redux | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `FILE_EXISTS InfinityLoaderDLL.dll` | 1 | 1 | unpatched | chriz-bg-modpack | `FILE_EXISTS`×1 | not rewritten by patch_mod.py |
| `MOD_IS_INSTALLED EEex.tp2 "1"` | 1 | 1 | unpatched | zstweaks | `MOD_IS_INSTALLED`×1 | not rewritten by patch_mod.py |
| `MOD_IS_INSTALLED EEex.tp2 1` | 1 | 1 | unpatched | tweaks | `MOD_IS_INSTALLED`×1 | not rewritten by patch_mod.py |
| `MOD_IS_INSTALLED EEex/EEex.tp2 ~0~` | 1 | 1 | patched | xgt-xp-gain | `MOD_IS_INSTALLED`×1 | tools/compat/patch_mod.py rewrites it |
| `MOD_IS_INSTALLED EEex/EEex.tp2 ~1~` | 1 | 1 | unpatched | xgt-xp-gain | `MOD_IS_INSTALLED`×1 | not rewritten by patch_mod.py |
| `doc: EEex 0.9` | 1 | 1 | info | eeex-remote-console |  | EEex 0.9 |
| `doc: EEex 2.6.6` | 1 | 1 | info | chriz-bg-rebalance |  | EEex's 2.6.6 |
| `doc: EEex 5.3` | 1 | 1 | info | chriz-bg-rebalance |  | EEex surface under EET's Lua 5.3 |
| `doc: EEex v0.10.3-alpha` | 1 | 1 | info | bg-eeex-buffbot |  | EEex v0.10.3-alpha |
| `doc: EEex v0.2.0` | 1 | 1 | info | chriz-sod-rebalance |  | EEex Remote Console v0.2.0 |
| `doc: EEex v0.9.19-alpha` | 1 | 1 | info | diablofication |  | EEex version v0.9.19-alpha |
| `doc: EEex v1.0` | 1 | 1 | info | bg-eeex-buffbot |  | EEex v1.0 |

## Per mod

### Bardic-Wonders (Bardic Wonders)

https://github.com/TheArtisanBG/Bardic-Wonders (github default branch); version ?; games bg2ee bgee eet; 64 Lua/WeiDU files; 26 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 6
- **Listeners registered**: 1
- **Engine fields**: 4
- **EEex opcodes 400-409**: 1

### Shadow-Magic (Shadow Magic)

https://github.com/TheArtisanBG/Shadow-Magic (github default branch); version ?; games bg2ee bgee eet; 97 Lua/WeiDU files; 9 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 6
- **Listeners registered**: 1
- **Engine fields**: 4
- **EEex opcodes 400-409**: 1
- **EEex data and Lua files**: 1

### SpellMenuExtended (Bubb's Spell Menu Extended)

https://github.com/Bubb13/Bubbs-Spell-Menu-Extended (github release); version v5.2; games bg2ee bgee eet iwdee; 5 Lua/WeiDU files; 2 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 37; not covered: `EEex_Actionbar_IsThievingHotkeyOpeningSpecialAbilities`
- **Listeners registered**: 10
- **Engine-object methods**: 16
- **Engine fields**: 14
- **Menus used**: 20; not covered: `B3Spell`, `B3Spell_Menu_ExitBackground`, `B3Spell_Menu_ExitBackgroundDark`, `B3Spell_Menu_Options_ExitBackground`, `B3Spell_Menu_Options_ExitBackgroundDark`, `B3Spell_Menu_Options_OptionsBackground`, `B3Spell_Menu_Options_SelectSlotArea`, `B3Spell_Menu_SelectSlotArea_Accept`, `B3Spell_Menu_SelectSlotArea_BottomHandle`, `B3Spell_Menu_SelectSlotArea_LeftHandle`, `B3Spell_Menu_SelectSlotArea_Rect`, `B3Spell_Menu_SelectSlotArea_RightHandle`, `B3Spell_Menu_SelectSlotArea_TopHandle`, `B3Spell_StoredInstance`
- **Settings (option keys)**: 21

### The-Artisan-s-Kitpack (The Artisan's Kitpack)

https://github.com/TheArtisanBG/The-Artisan-s-Kitpack (github default branch); version 4.8; games bg2ee bgee eet; 77 Lua/WeiDU files; 69 components.

- **EEex version / detection**: `FILE_EXISTS EEex_Actionbar.lua` (patched)
- **EEex functions, tables and constants**: 4
- **Listeners registered**: 1
- **Engine fields**: 1
- **EEex data and Lua files**: 1; not covered: `EEEX_ACTIONBAR.LUA`

### aura (Aura NPC (BG1/BG2/EET))

https://github.com/TheArtisanBG/Aura_BG1_BG2_EET (github default branch); version ?; games bg2ee bgee eet; 377 Lua/WeiDU files; 15 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched)
- **EEex functions, tables and constants**: 4
- **EEex internal hook functions the mod replaces**: 1; not covered: `EEex_Actionbar_Hook_HasFullThieving`
- **Listeners registered**: 1
- **Engine-object methods**: 1
- **Engine fields**: 1

### autodescription (AutoDescription)

https://github.com/Selphira/AutoDescription (github release 0.9.37); version 0.9.37; games bg2ee bgee eet; 124 Lua/WeiDU files; 4 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)

### b-kits (B_Kits)

https://github.com/Grammarsalad/B_Kits (github default branch); version 0.02.01; games bg2ee bgee eet iwdee; 123 Lua/WeiDU files; 43 components.

- **EEex version / detection**: `FILE_EXISTS EEex_Brd.lua` (unpatched), `FILE_EXISTS M__EEex.lua` (unpatched)
- **EEex functions, tables and constants**: 6
- **Listeners registered**: 2
- **EEex opcodes 400-409**: 1
- **Script IDS entries and IDS / 2DA appends**: 8
- **EEex data and Lua files**: 3; not covered: `B3CONRED.LUA`, `EEEX_BRD.LUA`, `M__EEEX.LUA`
- **Menus used**: 4; not covered: `B3Identify_Menu`

### bg-eeex-buffbot (BuffBot (EEex))

https://github.com/Chrizhermann/bg-eeex-buffbot (github default branch); version v1.12.1, v1.7.0-alpha, v1.7.4-alpha; games bg2ee bgee eet iwdee; 24 Lua/WeiDU files; 8 components.

- **EEex version / detection**: `FILE_CONTAINS EEex_scripts/EEex_Sprite.lua EEex_Sprite_GetCharacterIndex` (unpatched), `FILE_CONTAINS override/EEex_Sprite.lua EEex_Sprite_GetCharacterIndex` (unpatched), `FILE_EXISTS EEex/loader/LuaJIT/LuaProvider.dll` (unpatched), `FILE_EXISTS EEex/loader/LuaJIT/lua51.dll` (unpatched), `FILE_EXISTS EEex_scripts/EEex_Options.lua` (unpatched), `FILE_EXISTS EEex_scripts/EEex_Sprite.lua` (unpatched), `FILE_EXISTS InfinityLoader.ini` (unpatched), `FILE_EXISTS override/EEex_Options.lua` (patched), `FILE_EXISTS override/EEex_Sprite.lua` (patched), `FILE_EXISTS override/M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided); readme mentions EEex 1.2, 1.2.0, 1.3.1, 5.1, v0.10, v0.10.0-alpha, v0.10.1.1-alpha, v0.10.3, v0.10.3-alpha, v0.11, v0.11.0, v0.11.0-alpha
- **EEex functions, tables and constants**: 70; not covered: `EEex_Area_GetCurrent`, `EEex_GameObject_GetCurrentArea`, `EEex_GameState_GetCurrentArea`, `EEex_GetChitin`, `EEex_GetCurrentArea`, `EEex_LightUDToPtr`, `EEex_Menu_AddBeforeListRendersItemListener`, `EEex_Options_Private_Storage`, `EEex_Options_Widget`, `EEex_Sprite_AddMarshalHandlers`
- **Listeners registered**: 10; not covered: `EEex_Menu_AddBeforeListRendersItemListener`
- **Engine-object methods**: 26; not covered: `AddMessage`, `countAllOfTypeStringInRange`, `getCasterLevelForSpell`
- **Engine fields**: 55; not covered: `m_bInCopy`, `m_data`, `m_gameSave`, `m_inputMode`, `m_liveStats`, `m_multiPlayerSettings`, `m_nCopyParent`, `m_objectID`, `m_overHead`, `m_pNext`, `m_pnCharacterControlledByPlayer`, `m_pnLoadGameControlledByPlayer`, `m_quickItemResRef`, `m_sex`, `m_sourceTarget`, `m_wFileType`
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 4; not covered: `EEEX_OPTIONS.LUA`, `EEEX_SPRITE.LUA`, `INFINITYLOADER.INI`, `M___EEEX.LUA`
- **Menus used**: 25
- **Settings (option keys)**: 12; not covered: `EEex_Options\|(custom storage)\|BuffBot_Accent`, `EEex_Options\|(custom storage)\|BuffBot_DarkMode`, `EEex_Options\|(custom storage)\|BuffBot_ItemUseMode`, `EEex_Options\|(custom storage)\|BuffBot_RefreshBelow`, `EEex_Options\|(custom storage)\|BuffBot_TextSize`, `InfinityLoader.ini\|General\|LuaLibrary`, `InfinityLoader.ini\|General\|LuaPatchMode`, `InfinityLoader.ini\|General\|LuaVersionExternal`
- **components with gaps**: setup-buffbot.tp2#0, setup-buffbot-map-backed-v1.7.4-alpha.tp2#0, setup-buffbot-v1.7.0-alpha.tp2#0

### bg2-radar-overlay (BG2 Radar Overlay)

https://github.com/tapahob/BG2RadarOverlay (github release 2.6.2.0); version ?; games ?; 2 Lua/WeiDU files; 0 components.

- **EEex functions, tables and constants**: 11; not covered: `EEex_AIBase_AddScriptingObjectUpdatedListener`
- **Listeners registered**: 4; not covered: `EEex_AIBase_AddScriptingObjectUpdatedListener`
- **Engine-object methods**: 1
- **Menus used**: 2
- **Hard usage (asm / hooks / raw memory)**: 3

### bubb-infinityui (InfinityUI (Bubb's fork))

https://github.com/Bubb13/InfinityUI (github default branch (same commit as iui)); version v1.31; games bg2ee bgee eet iwdee; 28 Lua/WeiDU files; 9 components.

- **EEex version / detection**: `FILE_EXISTS override/EEex_Modules.lua` (unpatched), `Lua: EEex_Active` (provided), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 17
- **Listeners registered**: 1
- **Engine-object methods**: 214
- **Engine fields**: 28; not covered: `m_bConfirmDialog`, `m_bRenderFrameTimes`, `m_spellLevelq`
- **EEex data and Lua files**: 1; not covered: `EEEX_MODULES.LUA`
- **Menus used**: 535
- **EEex_Modules switches**: 1; not covered: `B3Scale`
- **Settings (option keys)**: 48

### candlekeep-revisited (Candlekeep Revisited)

https://github.com/TheArtisanBG/Candlekeep-Revisited (github default branch); version ?; games bgee eet; 143 Lua/WeiDU files; 5 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched)

### caster-crafting (Caster Crafting)

https://github.com/BardezAnAvatar/BGEE-Caster-Crafting (github default branch); version v0.7.6; games ?; 215 Lua/WeiDU files; 11 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX.TP2 ~0~` (patched)

### chriz-bg-modpack (chriz-bg-modpack)

https://github.com/Chrizhermann/chriz-bg-modpack (github default branch); version v0.2.0-alpha.14; games bg2ee bgee eet; 163 Lua/WeiDU files; 67 components.

- **EEex version / detection**: `FILE_CONTAINS InfinityLoader.db \[CBMID::` (unpatched), `FILE_EXISTS EEex.dll` (unpatched), `FILE_EXISTS EEex_scripts/EEex_Modules.lua` (unpatched), `FILE_EXISTS InfinityLoader.db` (unpatched), `FILE_EXISTS InfinityLoaderDLL.dll` (unpatched), `FILE_EXISTS override/M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided); readme mentions EEex 0.11, 1.2, 1.2.0, 1.3.1, 2.7.3.0, v0.11, v0.11.0-alpha, v1.2.0, v1.3.1, v2.6.6.0, v2.7.3.0
- **EEex functions, tables and constants**: 80; not covered: `EEex_AIBase_AddScriptingObjectUpdatedListener`, `EEex_Action_Private_SpriteStartedActionListeners`, `EEex_ClearAssemblyLabel`, `EEex_DefineAssemblyLabel`, `EEex_FlattenTable`, `EEex_GameState_DestroyedListeners`, `EEex_GameState_Private_AlreadyInitialized`, `EEex_GenLuaCall`, `EEex_GetImageBase`, `EEex_GetLuaRegistryIndex`, `EEex_GetProcAddressInternal`, `EEex_HookAfterCall`, `EEex_HookBeforeCallWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookReplaceFunctionMaintainOriginal`, `EEex_HookShimFunctionMaintainOriginal`, `EEex_JITAt`, `EEex_JITNear`, `EEex_JITNearAsLuaFunction`, `EEex_Keybinds_FireType`, `EEex_Keybinds_Get`, `EEex_Keybinds_Private_Definitions`, `EEex_Keybinds_Reset`, `EEex_Keybinds_Update`, `EEex_LoadLibrary`, `EEex_LuaCallReturnType`, `EEex_Menu_AddBeforeMainFileLoadedListener`, `EEex_Menu_AfterMainFileLoadedListeners`, `EEex_Menu_BeforeMainFileLoadedListeners`, `EEex_Menu_GetItemVariant` ...
- **Listeners registered**: 8; not covered: `EEex_AIBase_AddScriptingObjectUpdatedListener`, `EEex_Menu_AddBeforeMainFileLoadedListener`
- **Engine-object methods**: 11
- **Engine fields**: 44; not covered: `m_nSizeX`, `m_nSizeY`, `m_nXP`, `m_pArray`, `m_proficiencies`, `m_ruleTables`, `m_tXPBonus`
- **Script IDS entries and IDS / 2DA appends**: 2; not covered: `EEex_LuaAction_Object`
- **EEex data and Lua files**: 4; not covered: `EEEX.DLL`, `EEEX_MODULES.LUA`, `INFINITYLOADER.DB`, `M___EEEX.LUA`
- **Menus used**: 5
- **Hard usage (asm / hooks / raw memory)**: 17; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookAfterCall`, `EEex_HookBeforeCallWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookReplaceFunctionMaintainOriginal`, `EEex_HookShimFunctionMaintainOriginal`, `EEex_JITAt`, `EEex_JITNear`, `EEex_JITNearAsLuaFunction`
- **Engine symbols / hook labels named in strings**: 50; not covered: `C2DArray::GetAt`, `CAIObjectType::GetActiveInactiveClasses`, `CAIObjectType::IsUsableSubClass`, `CAbilityData::CAbilityData`, `CBMA::original_ApplyEffect`, `CBMBank::CheckStatsChangeGetXPCap`, `CBMBank::GetXPCap`, `CBMI::original_`, `CBMR::original_CreateMakeDualClass`, `CBMR::original_MakeDualClass`, `CBMXPProbe::Opcode104Apply`, `CBMXPProbe::Original104`, `CDWordArray::CDWordArray`, `CDerivedStats::CDerivedStats`, `CDerivedStats::GetLevel`, `CDerivedStats::SetLevel`, `CDerivedStats::~CDerivedStats`, `CGameAnimationType::GetMoveScale`, `CGameEffect::DecodeEffectFromBase`, `CGameEffectBase::CGameEffectBase`, `CGameObject::GetAIType`, `CGameSprite::AddNewSpecialAbilities`, `CGameSprite::CombineAllActiveInactiveProficiencies`, `CGameSprite::GetActiveProficiency`, `CGameSprite::GetInactiveProficiency`, `CGameSprite::ProcessEffectList`, `CGameSprite::SetActiveProficiency`, `CGameSprite::SetInactiveProficiency`, `CObArray::SetAtGrow`, `CObList::AddTail` ...
- **components with gaps**: setup-chriz-bg-modpack.tp2#430, setup-chriz-bg-modpack.tp2#630

### chriz-bg-rebalance (chriz-bg-rebalance)

https://github.com/Chrizhermann/chriz-bg-rebalance (github default branch); version private-2026-10-06, private-oct20-immunity-windows, v0.8.8; games bg2ee eet iwdee; 93 Lua/WeiDU files; 81 components.

- **EEex version / detection**: `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookAfterRestoreWithLabels` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookConditionalJumpOnSuccess[ %TAB%]*(` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Resource.lua ^function[ %TAB%]+EEex_Resource_Get2DARowTableIterator` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Resource.lua ^function[ %TAB%]+EEex_Resource_Load2DA` (unpatched), `FILE_EXISTS M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided); readme mentions EEex 0.11, 0.11.0-alpha, 1.0, 1.2, 1.2.0, 1.3, 1.3.0, 1.3.1, 2.6.6, 2.7.3.0, 5.3, v0.11.0-alpha
- **EEex functions, tables and constants**: 66; not covered: `EEex_Assembly_x86`, `EEex_FlattenTable`, `EEex_GameState_TogglePause`, `EEex_GenLuaCall`, `EEex_GetImageBase`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeCallWithLabels`, `EEex_HookBeforeConditionalJumpWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpOnSuccess`, `EEex_HookIntegrityWatchdogRegister`, `EEex_JITNear`, `EEex_LuaCallReturnType`, `EEex_OffsetOf`, `EEex_Opcode_AddDeferredListsResolvedListener`, `EEex_Projectile_RegisterGlobalMutator`, `EEex_ReadPtr`, `EEex_Sprite_AddMarshalHandlers`, `EEex_Sprite_ApplyEffect`, `EEex_TryGetUDAux`, `EEex_TryLabel`, `EEex_WritePtr`
- **Listeners registered**: 7; not covered: `EEex_Opcode_AddDeferredListsResolvedListener`
- **Engine-object methods**: 8
- **Engine fields**: 63; not covered: `m_bAllowEffectListCall`, `m_bConfirmDialog`, `m_bGameLoaded`, `m_bHardPaused`, `m_bInLoadArea`, `m_bInLoadGame`, `m_bPaused`, `m_deleted`, `m_equippedEffectList`, `m_idSelf`, `m_nId`, `m_sourceTarget`
- **EEex opcodes 400-409**: 1
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 2; not covered: `EEEX_RESOURCE.LUA`, `M___EEEX.LUA`
- **Menus used**: 1
- **Hard usage (asm / hooks / raw memory)**: 17; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeCallWithLabels`, `EEex_HookBeforeConditionalJumpWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpOnSuccess`, `EEex_HookIntegrityWatchdogRegister`, `EEex_JITNear`, `EEex_WritePtr`
- **Engine symbols / hook labels named in strings**: 1; not covered: `CProjectileArea::VFTable`
- **components with gaps**: setup-chriz-bg-rebalance.tp2#121, setup-chriz-bg-rebalance.tp2#411, setup-chriz-bg-rebalance.tp2#420

### chriz-playable-races (chriz-bg-playable-races)

https://github.com/Chrizhermann/chriz-bg-playable-races (github default branch); version v0.3.0-proto; games ?; 11 Lua/WeiDU files; 2 components.

- **EEex version / detection**: `FILE_CONTAINS EEex_scripts/EEex_Assembly.lua ^function[ %TAB%]+EEex_LabelDefault` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Assembly_x86-64.lua ^function[ %TAB%]+EEex_HookShimFunctionMaintainOriginal` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_GameState.lua ^function[ %TAB%]+EEex_GameState_AddInitializedListener` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Menu.lua ^function[ %TAB%]+EEex_Menu_AddAfterMainFileLoadedListener` (unpatched), `FILE_CONTAINS EEex_scripts/EEex_Resource.lua ^function[ %TAB%]+EEex_Resource_Load2DA` (unpatched), `FILE_EXISTS M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided); readme mentions EEex v1.2.0, v1.3.1
- **EEex functions, tables and constants**: 20; not covered: `EEex_Assembly_x86`, `EEex_FlattenTable`, `EEex_HookShimFunctionMaintainOriginal`, `EEex_LabelDefault`, `EEex_WriteStringCache`
- **Listeners registered**: 3
- **Engine-object methods**: 5
- **Engine fields**: 10
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 5; not covered: `EEEX_ASSEMBLY.LUA`, `EEEX_GAMESTATE.LUA`, `EEEX_MENU.LUA`, `EEEX_RESOURCE.LUA`, `M___EEEX.LUA`
- **Hard usage (asm / hooks / raw memory)**: 5; not covered: `EEex_FlattenTable`, `EEex_HookShimFunctionMaintainOriginal`, `EEex_WriteStringCache`
- **components with gaps**: setup-chriz-bg-playable-races.tp2#100, setup-chriz-bg-playable-races.tp2#101

### chriz-sod-rebalance (chriz-sod-rebalance)

https://github.com/Chrizhermann/chriz-sod-rebalance (github default branch); version ground-probe-1, v0.6.16; games eet; 143 Lua/WeiDU files; 52 components.

- **EEex version / detection**: `FILE_EXISTS M___EEex.lua` (unpatched); readme mentions EEex 0.11.0-alpha, 1.2.0, 2.7.3.0, v0.2.0, v1.2.0
- **EEex functions, tables and constants**: 11
- **Engine-object methods**: 1
- **Engine fields**: 8
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 1; not covered: `M___EEEX.LUA`

### diablofication (Diablofication)

https://github.com/m-architek/Diablofication (github default branch); version v0.8; games bgee (NOT GAME_INCLUDES sod); 106 Lua/WeiDU files; 10 components.

- **EEex version / detection**: `Lua: EEex_Active` (provided), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched); readme mentions EEex v0.9.19-alpha
- **EEex functions, tables and constants**: 7
- **Engine-object methods**: 2
- **Script IDS entries and IDS / 2DA appends**: 1

### eet-tweaks (EET Tweaks)

https://github.com/K4thos/EET_Tweaks (github default branch); version 1.12; games bg1 bg2ee bgee bgt ca eet how iwd iwd2 iwd_in_bg2 iwdee soa tob totlm totsc tutu tutu_totsc; 6 Lua/WeiDU files; 77 components.

- **EEex version / detection**: `FILE_EXISTS EEex.db` (unpatched)
- **EEex functions, tables and constants**: 2; not covered: `EEex_ReadDword`
- **Engine-object methods**: 1
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 1; not covered: `EEEX.DB`
- **components with gaps**: EET_Tweaks.tp2#2080

### epic-thieving (Epic Thieving)

https://github.com/OlvynChuru/Epic-Thieving (github default branch); version ?; games bg1 bg2 bg2ee bgee bgt eet how iwd iwdee tob totlm totsc tutu tutu_totsc; 9 Lua/WeiDU files; 22 components.

- **EEex version / detection**: `REQUIRE_COMPONENT EEex.tp2 0` (patched)
- **EEex functions, tables and constants**: 5
- **Engine fields**: 2
- **EEex opcodes 400-409**: 1

### high-power-bg (High Power Baldur's Gate)

https://github.com/OlvynChuru/High-Power-Baldurs-Gate (github default branch); version 2.5.0; games bgee eet iwdee; 30 Lua/WeiDU files; 71 components.

- **EEex version / detection**: `FILE_EXISTS EEex_Cra.lua` (unpatched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched), `MOD_IS_INSTALLED EEex.tp2 ~1~` (unpatched), `REQUIRE_COMPONENT EEex.tp2 0` (patched), `REQUIRE_COMPONENT EEex.tp2 2` (unpatched)
- **EEex functions, tables and constants**: 66; not covered: `EEex_AccessComplexStat`, `EEex_Action_AddEnabledSpriteStartedActionListener`, `EEex_AddActionHook`, `EEex_EvalObjectStringAsActor`, `EEex_Flags`, `EEex_HookAfterRestore`, `EEex_ProjectileMutatorList`, `EEex_Projectile_IsOfType`, `EEex_Projectile_Type`, `EEex_Sprite_ForAllOfTypeStringInRange`, `EEex_Sprite_GetCasterLevel`, `EEex_Sprite_GetSpellRES`, `EEex_WriteStringAuto`
- **EEex internal hook functions the mod replaces**: 5; not covered: `EEex_OnAddEffectToProjectile`, `EEex_OnDecodeProjectile`, `EEex_OnPostProjectileCreation`, `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`, `EEex_Sprite_Hook_OnDestruct`
- **Listeners registered**: 4; not covered: `EEex_Action_AddEnabledSpriteStartedActionListener`
- **Engine-object methods**: 7; not covered: `getCastTimerPercentage`
- **Engine fields**: 19; not covered: `m_cContingencyList`, `m_nTimeStop`
- **EEex opcodes 400-409**: 8; not covered: `400`, `406`, `407`, `408`, `409`
- **Script IDS entries and IDS / 2DA appends**: 2
- **EEex data and Lua files**: 2; not covered: `EEEX_MODULES.LUA`
- **Menus used**: 2; not covered: `B3EffectMenu_Menu`
- **EEex_Modules switches**: 2; not covered: `B3Invis`, `ME_DAMAB`
- **Hard usage (asm / hooks / raw memory)**: 9; not covered: `EEex_HookAfterRestore`, `EEex_WriteStringAuto`
- **Engine symbols / hook labels named in strings**: 7; not covered: `CBaldurChitin::m_pObjectGame`, `CGameAIBase::ForceSpell()_CProjectile::AddEffect()`, `CGameAIBase::ForceSpellPoint()_CProjectile::AddEffect()`, `CGameSprite::Spell()_CProjectile::AddEffect()`, `CGameSprite::SpellPoint()_CProjectile::AddEffect()`, `CProjectile::AddEffect`, `CProjectile::DecodeProjectile`
- **components with gaps**: HighPower.tp2#28

### house-rule-tweaks (House Rule Tweaks)

https://github.com/TheArtisanBG/House-Rule-Tweaks (github default branch); version ?; games bg2ee bgee eet iwdee; 62 Lua/WeiDU files; 52 components.

- **EEex version / detection**: `FILE_EXISTS EEex_Actionbar.lua` (patched), `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched)
- **EEex functions, tables and constants**: 10
- **Listeners registered**: 1
- **Engine fields**: 2
- **EEex opcodes 400-409**: 1
- **EEex data and Lua files**: 1; not covered: `EEEX_ACTIONBAR.LUA`

### ie-skillz (IE Skillz)

https://github.com/Grammarsalad/IE_Skillz (github default branch); version 0.00.01; games bg bg2 bg2ee bgee bgt eet iwdee; 42 Lua/WeiDU files; 9 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 3

### improved-hof (Improved Heart of Fury Mode)

https://github.com/OlvynChuru/Improved-Heart-Of-Fury-Mode (github default branch); version 4.0.2; games ?; 5 Lua/WeiDU files; 19 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched), `REQUIRE_COMPONENT EEex.tp2 0` (patched)
- **EEex functions, tables and constants**: 59; not covered: `EEex_AddActionHook`, `EEex_AddActionHookOpcode`, `EEex_AlterActorEffect`, `EEex_ApplyEffectToActor`, `EEex_Call`, `EEex_DemandResData`, `EEex_EvalObjectStringAsActor`, `EEex_GetActionID`, `EEex_GetActionPointX`, `EEex_GetActionPointY`, `EEex_GetActionTarget`, `EEex_GetActorAnimation`, `EEex_GetActorAreaSize`, `EEex_GetActorMovementRate`, `EEex_GetActorRequiredDirection`, `EEex_GetActorShare`, `EEex_GetActorSpellRES`, `EEex_GetSpellData`, `EEex_GetSpellName`, `EEex_IsImmuneToOpcode`, `EEex_IsImmuneToSpellLevel`, `EEex_IterateActorEffects`, `EEex_IterateActorIDs`, `EEex_ProcessClericMemorization`, `EEex_ProcessWizardMemorization`, `EEex_ReadByte`, `EEex_ReadDword`, `EEex_ReadSignedWord`, `EEex_ReadWord`, `EEex_SetActionID` ...
- **Engine-object methods**: 1
- **EEex opcodes 400-409**: 6; not covered: `400`, `406`, `407`
- **Script IDS entries and IDS / 2DA appends**: 1
- **EEex data and Lua files**: 1; not covered: `EEEX_INI.LUA`
- **Hard usage (asm / hooks / raw memory)**: 3; not covered: `EEex_WriteByte`, `EEex_WriteWord`
- **Engine symbols / hook labels named in strings**: 2; not covered: `CBaldurChitin::m_pObjectGame`, `CGameSprite::Shatter`
- **components with gaps**: BetterHOF.TP2#10, BetterHOF.TP2#896

### iui (Infinity UI++)

https://github.com/Renegade0/InfinityUI (github default branch); version v1.31; games bg2ee bgee eet iwdee; 28 Lua/WeiDU files; 9 components.

- **EEex version / detection**: `FILE_EXISTS override/EEex_Modules.lua` (unpatched), `Lua: EEex_Active` (provided), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 17
- **Listeners registered**: 1
- **Engine-object methods**: 214
- **Engine fields**: 28; not covered: `m_bConfirmDialog`, `m_bRenderFrameTimes`, `m_spellLevelq`
- **EEex data and Lua files**: 1; not covered: `EEEX_MODULES.LUA`
- **Menus used**: 535
- **EEex_Modules switches**: 1; not covered: `B3Scale`
- **Settings (option keys)**: 48

### morpheus562-kitpack (Morpheus562's Kitpack)

https://morpheus-mart.com (Dropbox package 5.11 (setup exe never run)); version v5.11; games bg2ee bgee eet iwdee; 46 Lua/WeiDU files; 29 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 3
- **Script IDS entries and IDS / 2DA appends**: 1

### olvynspells (Olvyn Spells (MESpells))

https://github.com/OlvynChuru/OlvynSpells (github default branch); version 2.6.0; games bg2ee bgee eet iwdee; 23 Lua/WeiDU files; 77 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched), `MOD_IS_INSTALLED EEex.tp2 ~1~` (unpatched), `REQUIRE_COMPONENT EEex.tp2 0` (patched), `REQUIRE_COMPONENT EEex.tp2 2` (unpatched)
- **EEex functions, tables and constants**: 67; not covered: `EEex_AccessComplexStat`, `EEex_Action_AddEnabledSpriteStartedActionListener`, `EEex_AddActionHook`, `EEex_DamageAbsorption`, `EEex_EvalObjectStringAsActor`, `EEex_Flags`, `EEex_HookAfterRestore`, `EEex_ProjectileMutatorList`, `EEex_Projectile_IsOfType`, `EEex_Projectile_Type`, `EEex_Sprite_ForAllOfTypeStringInRange`, `EEex_Sprite_GetCasterLevel`, `EEex_Sprite_GetSpellRES`, `EEex_WriteStringAuto`
- **EEex internal hook functions the mod replaces**: 5; not covered: `EEex_OnAddEffectToProjectile`, `EEex_OnDecodeProjectile`, `EEex_OnPostProjectileCreation`, `EEex_Opcode_Private_ScreenEffectsGlobalFunctions`, `EEex_Sprite_Hook_OnDestruct`
- **Listeners registered**: 4; not covered: `EEex_Action_AddEnabledSpriteStartedActionListener`
- **Engine-object methods**: 7; not covered: `getCastTimerPercentage`
- **Engine fields**: 19; not covered: `m_cContingencyList`, `m_nTimeStop`
- **EEex opcodes 400-409**: 8; not covered: `400`, `406`, `407`, `408`, `409`
- **Script IDS entries and IDS / 2DA appends**: 2
- **EEex data and Lua files**: 1; not covered: `EEEX_INI.LUA`
- **Menus used**: 2; not covered: `B3EffectMenu_Menu`
- **EEex_Modules switches**: 1; not covered: `ME_DAMAB`
- **Hard usage (asm / hooks / raw memory)**: 9; not covered: `EEex_HookAfterRestore`, `EEex_WriteStringAuto`
- **Engine symbols / hook labels named in strings**: 7; not covered: `CBaldurChitin::m_pObjectGame`, `CGameAIBase::ForceSpell()_CProjectile::AddEffect()`, `CGameAIBase::ForceSpellPoint()_CProjectile::AddEffect()`, `CGameSprite::Spell()_CProjectile::AddEffect()`, `CGameSprite::SpellPoint()_CProjectile::AddEffect()`, `CProjectile::AddEffect`, `CProjectile::DecodeProjectile`
- **components with gaps**: MESpells.tp2#12091, MESpells.tp2#21231, MESpells.tp2#24081, MESpells.tp2#25151, MESpells.tp2#26151, MESpells.tp2#29111, MESpells.tp2#1000, MESpells.tp2#1001

### pathfinding-redux (BG Pathfinding Redux)

https://github.com/zach-hopkins/bg-pathfinding-redux (github default branch); version 0.1.11-preview; games bg2ee bgee eet; 28 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `FILE_EXISTS EEex.dll` (unpatched), `FILE_EXISTS EEex.exe` (unpatched), `FILE_EXISTS InfinityLoader.exe` (unpatched), `FILE_EXISTS InfinityLoader.ini` (unpatched); readme mentions EEex 1.2.0, 1.3, 1.3.0
- **EEex functions, tables and constants**: 64; not covered: `EEex_Assembly_Private_FindOffsetOf`, `EEex_Assembly_Private_InitState`, `EEex_Assembly_Private_MacroSwitch`, `EEex_Assembly_x86`, `EEex_CBaldurChitin`, `EEex_CInfGame`, `EEex_DefineAssemblyLabel`, `EEex_DistanceToMultiple`, `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_GetImageBase`, `EEex_GetUTBaseclassMetadata`, `EEex_HookAfterCallWithLabels`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeAndAfterCallWithLabels`, `EEex_HookBeforeCallWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookIntegrityWatchdog_Load`, `EEex_HookRemoveCallWithLabels`, `EEex_JITAt`, `EEex_JITNear`, `EEex_JITNearAsLuaFunction`, `EEex_LuaCallReturnType`, `EEex_Memcpy`, `EEex_Memset`, `EEex_OffsetOf`, `EEex_PreprocessAssembly`, `EEex_PreprocessAssemblyStr` ...
- **Listeners registered**: 3
- **Engine-object methods**: 5; not covered: `virtual_GetTerrainTable`, `virtual_InsertAction`
- **Engine fields**: 29; not covered: `m_actionList`, `m_bAllowEffectListCall`, `m_charactersPortrait`, `m_gameSave`, `m_inputMode`, `m_nDamageCounter`
- **EEex data and Lua files**: 5; not covered: `EEEX.DLL`, `EEEX.EXE`, `INFINITYLOADER.EXE`, `INFINITYLOADER.INI`
- **Menus used**: 1
- **Hard usage (asm / hooks / raw memory)**: 23; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookAfterCallWithLabels`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeAndAfterCallWithLabels`, `EEex_HookBeforeCallWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookIntegrityWatchdog_Load`, `EEex_HookRemoveCallWithLabels`, `EEex_JITAt`, `EEex_JITNear`, `EEex_JITNearAsLuaFunction`, `EEex_Memcpy`, `EEex_WritePtr`, `EEex_WriteStringCache`
- **Engine symbols / hook labels named in strings**: 4; not covered: `CGameObjectArray::GetShare`, `CGameSprite::ClearBumpPath`, `CGameSprite::JumpToPoint`, `CMessageHandler::AddMessage`
- **components with gaps**: bg-redux-movement.tp2#0

### poisoned-pathways (Poisoned Pathways)

https://github.com/AciferBG/Poisoned-Pathways (github release v1.8); version v1.8; games bg2ee eet; 210 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched)
- **EEex functions, tables and constants**: 4
- **Engine-object methods**: 1; not covered: `evalAsAIBase`
- **Engine fields**: 1
- **Script IDS entries and IDS / 2DA appends**: 1

### proficiencies (Proficiencies)

https://github.com/Grammarsalad/Proficiencies (github default branch); version 0.06.04; games bg2ee bgee eet iwdee; 110 Lua/WeiDU files; 62 components.

- **EEex version / detection**: `FILE_EXISTS M__EEex.lua` (unpatched)
- **EEex opcodes 400-409**: 1
- **Script IDS entries and IDS / 2DA appends**: 10
- **EEex data and Lua files**: 2; not covered: `EEEX_BRD.LUA`, `M__EEEX.LUA`

### skills-and-abilities (Skills and Abilities)

https://morpheus-mart.com (Dropbox package 5.4 (setup exe never run)); version v5.3, v5.4; games bg2ee bgee eet iwdee; 110 Lua/WeiDU files; 65 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 7
- **EEex internal hook functions the mod replaces**: 1; not covered: `EEex_Actionbar_Hook_HasFullThieving`
- **Listeners registered**: 1
- **Engine-object methods**: 2
- **Engine fields**: 1
- **Script IDS entries and IDS / 2DA appends**: 19

### sod2bg2-iu (SoD to BG2EE Item Upgrade)

https://github.com/Gibberlings3/SoD-to-BG2EE-Item-Upgrade (github default branch); version v2.0.5; games bg1 bg2ee bgee eet how iwd iwd2 iwd_in_bg2 iwdee pst pstee totlm; 282 Lua/WeiDU files; 38 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 3

### stick-lua-functions (StickLuaFunctions)

https://github.com/xbigxiangx-dot/StickLuaFunctions (github release v0.11.0-Alpha); version v0.10.0, v0.11.0-Alpha, v0.8.0, v0.8.1; games ?; 18 Lua/WeiDU files; 6 components.

- **EEex version / detection**: `REQUIRE_COMPONENT EEex.tp2 0` (patched)
- **EEex functions, tables and constants**: 35; not covered: `EEex_DefineAssemblyLabel`, `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookAfterCallWithLabels`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeConditionalJumpWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpOnSuccessWithLabels`, `EEex_HookConditionalJumpWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_JITAt`, `EEex_JITNear`, `EEex_LuaCallReturnType`
- **EEex internal hook functions the mod replaces**: 1; not covered: `EEex_Opcode_Hook_OnAfterSwingCheckedOp248`
- **Engine-object methods**: 4; not covered: `getReference`
- **Engine fields**: 45; not covered: `m_nHalfSwingCounter`, `m_nHitBonus`, `m_persistantEffects`
- **Hard usage (asm / hooks / raw memory)**: 14; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookAfterCallWithLabels`, `EEex_HookAfterRestoreWithLabels`, `EEex_HookBeforeConditionalJumpWithLabels`, `EEex_HookBeforeRestoreWithLabels`, `EEex_HookConditionalJumpOnSuccessWithLabels`, `EEex_HookConditionalJumpWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_JITAt`, `EEex_JITNear`
- **Engine symbols / hook labels named in strings**: 1; not covered: `Hook-CAIGroup::IsPartyLeader()-Override`
- **components with gaps**: Setup-StickLuaFunctions.tp2#0, Setup-StickLuaFunctions.tp2#0, Setup-StickLuaFunctions.tp2#0, Setup-StickLuaFunctions.tp2#0, Setup-StickLuaFunctions.tp2#0, Setup-StickLuaFunctions.tp2#0

### tactics-remix (Tactics Remix)

https://morpheus-mart.com (Dropbox package 8.2 (setup exe never run)); version v8.2; games bg2ee bgee eet iwdee; 1253 Lua/WeiDU files; 113 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 8
- **Engine-object methods**: 4; not covered: `evalAsAIBase`
- **Engine fields**: 5
- **Script IDS entries and IDS / 2DA appends**: 39

### tweaks (Tweaks Anthology)

https://github.com/Gibberlings3/Tweaks-Anthology (github default branch); version v18; games bg1 bg2 bg2ee bgee bgt ca eet how iwd iwd-in-bg2 iwd2 iwd_in_bg2 iwdee pst pstee soa tob totlm totsc tutu tutu_totsc; 1011 Lua/WeiDU files; 446 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 0` (patched), `MOD_IS_INSTALLED EEex.tp2 1` (unpatched)
- **EEex functions, tables and constants**: 86; not covered: `EEex_Projectile_IsOfType`, `EEex_Projectile_Type`
- **Listeners registered**: 10
- **Engine-object methods**: 35; not covered: `AddMessage`, `evalAsAIBase`, `getStartingPos`, `virtual_Destruct`
- **Engine fields**: 162; not covered: `m_bPolymorphed`, `m_coneSize`, `m_dwAreaFlags`, `m_explosionRange`, `m_followCount`, `m_nAssassinate`, `m_nLastDamageTaken`, `m_nLevelDrain`, `m_nSpellFailureInnate`, `m_nSpellFailureMage`, `m_nSpellFailurePriest`, `m_newEffect`, `m_secondaryProjectile`, `m_sourceTarget`, `m_terrainTable`, `m_wFileType`
- **EEex opcodes 400-409**: 4; not covered: `408`
- **Script IDS entries and IDS / 2DA appends**: 8
- **EEex data and Lua files**: 2
- **Settings (option keys)**: 4

### wares-of-the-planes (Wares of the Planes)

https://github.com/Argent77/A7-WaresOfThePlanes (github release v2.7); version 2.7; games bg2ee bgee eet; 315 Lua/WeiDU files; 3 components.

- **EEex version / detection**: `FILE_CONTAINS InfinityLoader.db Hook-CDerivedStats::SetSpellState()` (unpatched), `FILE_EXISTS InfinityLoader.db` (unpatched), `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched)
- **EEex data and Lua files**: 1; not covered: `INFINITYLOADER.DB`

### warlock (Warlock)

https://github.com/TheArtisanBG/Warlock (github default branch); version ?; games bgee eet iwdee; 34 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEEX/EEEX.TP2 ~0~` (patched), `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 13
- **Listeners registered**: 1
- **Engine-object methods**: 4
- **Engine fields**: 6
- **EEex opcodes 400-409**: 1
- **EEex data and Lua files**: 1; not covered: `B3SPELEX.LUA`

### workshop-kitpack (The Workshop Kitpack)

https://github.com/D2-mods/The-Workshop-Kitpack (github release v5.29); version 5.29; games bg2ee bgee eet iwdee; 164 Lua/WeiDU files; 11 components.

- **EEex version / detection**: no check; readme mentions EEex v0.10.0-alpha
- **EEex opcodes 400-409**: 1
- **EEex data and Lua files**: 1; not covered: `B3CONRED.LUA`
- **Menus used**: 4; not covered: `B3Identify_Menu`

### xgt-xp-gain (XGT Customizable XP Gain)

https://github.com/Xgatt/XGTCustomizableXPGain (github release v0.6.0-alpha); version v0.6.0-alpha; games bg2ee bgee eet iwdee; 4 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `Lua: EEex_Active` (provided), `MOD_IS_INSTALLED EEex/EEex.tp2 ~0~` (patched), `MOD_IS_INSTALLED EEex/EEex.tp2 ~1~` (unpatched)
- **EEex functions, tables and constants**: 3
- **Engine-object methods**: 4
- **Engine fields**: 5
- **EEex opcodes 400-409**: 1
- **Script IDS entries and IDS / 2DA appends**: 1

### zstweaks (ZS Tweaks)

https://github.com/szaumoor/ZSTweaks (github release 1.7.0c); version 1.7.0c; games bg2ee bgee eet iwdee; 413 Lua/WeiDU files; 357 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 "1"` (unpatched)

### SadoEE (SadoEE (Party Stash + SadoQoL))

https://github.com/sad0/SadoEE (local dev sources (EET 2.7.3 (dev)/PartyStash + SadoQoL), text files only); version proto, v0.1, v1.2.1; games bg2ee bgee eet; 99 Lua/WeiDU files; 38 components.

- **EEex version / detection**: `FILE_EXISTS EEex.ini` (unpatched), `MOD_IS_INSTALLED EEex.tp2 (ID_OF_LABEL ~EEex.tp2~ ~B3-EEex-Main~)` (patched); readme mentions EEex v2.7.3.0
- **EEex functions, tables and constants**: 112; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookBeforeCallWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookIntegrityWatchdog_IgnoreStackSizes`, `EEex_JITNear`, `EEex_LuaCallReturnType`, `EEex_Menu_GetItemVariant`, `EEex_Object_AddToArea`, `EEex_ReadPtr`, `EEex_ReadS16`, `EEex_Sprite_DisplayTextRef`, `EEex_WritePtr`
- **EEex internal hook functions the mod replaces**: 1
- **Listeners registered**: 8
- **Engine-object methods**: 48; not covered: `CheckLOS`, `SetCursor`, `virtual_GetVisibleTerrainTable`
- **Engine fields**: 90; not covered: `m_acteeID`, `m_resRef`
- **EEex opcodes 400-409**: 1
- **Script IDS entries and IDS / 2DA appends**: 3
- **EEex data and Lua files**: 1; not covered: `EEEX.INI`
- **Menus used**: 72
- **Settings (option keys)**: 10; not covered: `EEex.ini\|Empty Container Module\|Enable`, `EEex_Options\|SadoQoL\|Options Page Line`, `EEex_Options\|SadoQoL\|row[2]`
- **Hard usage (asm / hooks / raw memory)**: 18; not covered: `EEex_FlattenTable`, `EEex_GenLuaCall`, `EEex_HookBeforeCallWithLabels`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookIntegrityWatchdog_IgnoreStackSizes`, `EEex_JITNear`, `EEex_WritePtr`
- **Engine symbols / hook labels named in strings**: 3; not covered: `Hook-CGameContainer::Render()-B3EmptyContainer`, `Hook-CGameSprite::ProcessEffectList()-FirstRandCall`, `Hook-CVisibilityMap::IsCharacterIdOnMap()-FirstInstruction`
- **components with gaps**: PartyStash.tp2#1, PartyStash.tp2#40, SadoQoL.tp2#0, SadoQoL.tp2#1, SadoQoL.tp2#2, SadoQoL.tp2#3, SadoQoL.tp2#5, SadoQoL.tp2#6, SadoQoL.tp2#7, SadoQoL.tp2#8, SadoQoL.tp2#9, SadoQoL.tp2#10, SadoQoL.tp2#11, SadoQoL.tp2#12, SadoQoL.tp2#13, SadoQoL.tp2#14, SadoQoL.tp2#16, SadoQoL.tp2#17, SadoQoL.tp2#19

### eeex-remote-console (EEex Remote Console)

https://github.com/Chrizhermann/eeex-remote-console (github default branch (master 2026-10-22)); version v0.2.1; games bg2ee bgee eet iwdee; 6 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `FILE_EXISTS InfinityLoader.ini` (unpatched), `FILE_EXISTS override/M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided); readme mentions EEex 0.10, 0.9, v0.10, v0.11.0-alpha, v1.0.0, v1.2, v1.2.0, v1.3.1
- **EEex functions, tables and constants**: 8
- **Listeners registered**: 2
- **Engine-object methods**: 1
- **EEex data and Lua files**: 5; not covered: `INFINITYLOADER.INI`, `M___EEEX.LUA`
- **Menus used**: 1
- **Settings (option keys)**: 1; not covered: `InfinityLoader.ini\|-\|LuaPatchMode`

### spells-and-magic (Spells and Magic)

https://github.com/Grammarsalad/Spells_and_Magic (github default branch (main 2025-12-02)); version 0.00.01; games bg bg2 bg2ee bgee bgt eet iwdee; 147 Lua/WeiDU files; 5 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 5
- **Engine fields**: 3

### a7-add-kit-ex (A7 ADD_KIT_EX library)

https://github.com/Argent77/A7-add_kit_ex (github default branch (master 2026-05-18)); version 2.0; games bg2ee bgee eet iwdee; 7 Lua/WeiDU files; 4 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 0` (patched)

### ie-enhancer (InfinityEngine Enhancer)

https://github.com/TheForgotten69/InfinityEngine-Enhancer (github release v0.1.0); version ?; games ?; 1 Lua/WeiDU files; 0 components.

- **EEex functions, tables and constants**: 3; not covered: `EEex_InitLuaBindings`
- **Hard usage (asm / hooks / raw memory)**: 2

### bgee-graphics-enhanced (BGEE Graphics Enhanced)

https://github.com/TheForgotten69/BGEE-Graphics-Enhanced (github release v0.2.0); version v0.1.0; games bg2ee bgee eet iwdee; 2 Lua/WeiDU files; 2 components.

- **EEex functions, tables and constants**: 3; not covered: `EEex_InitLuaBindings`
- **Hard usage (asm / hooks / raw memory)**: 2

### hotkey-prevnext-char (EEex Hotkey Prev/Next Character)

https://github.com/snaphat/InfinityEngineEEexHotkeyPrevNextChar (github default branch (main 2025-01-15)); version ?; games ?; 1 Lua/WeiDU files; 0 components.

- **EEex functions, tables and constants**: 4

### bg2narrator (BG2 Narrator)

https://github.com/MariusTBjercke/bg2narrator (github release v0.1.1); version v0.1.1; games bg2ee eet; 2 Lua/WeiDU files; 1 components.

- **EEex version / detection**: `FILE_EXISTS M___EEex.lua` (unpatched), `Lua: EEex_Active` (provided)
- **EEex functions, tables and constants**: 8; not covered: `EEex_Menu_AddBeforeListRendersItemListener`, `EEex_Menu_BeforeListRendersItemListeners`, `EEex_Menu_BeforeUIItemRenderListeners`
- **EEex internal hook functions the mod replaces**: 2; not covered: `EEex_Menu_Hook_BeforeListRenderingItem`, `EEex_Menu_Hook_OnBeforeUIItemRender`
- **Listeners registered**: 4; not covered: `EEex_Menu_AddBeforeListRendersItemListener`
- **Engine-object methods**: 3
- **Engine fields**: 7
- **EEex data and Lua files**: 3; not covered: `EEEX.EXE`, `INFINITYLOADER.EXE`, `M___EEEX.LUA`
- **Menus used**: 2
- **Settings (option keys)**: 2
- **components with gaps**: BG2Narrator.tp2#0

### random-graion-magic (Random Graion Magic)

https://github.com/GraionDilach/RandomGraionMagic (github release 0.12); version 0.12; games bg2ee bgee eet iwdee; 4 Lua/WeiDU files; 5 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 2
- **Engine fields**: 3

### sword-coast-infinity (Sword Coast Infinity)

https://github.com/DataForInfinity/Sword-Coast-Infinity (github default branch (main 2025-04-19)); version v1.0, v1.2, v2.1; games bg2ee bgee eet iwdee; 11 Lua/WeiDU files; 41 components.

- **EEex version / detection**: `MOD_IS_INSTALLED EEex.tp2 ~0~` (patched)
- **EEex functions, tables and constants**: 2
- **Engine fields**: 3

