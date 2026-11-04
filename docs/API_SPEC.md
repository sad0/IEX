# IEX Tier 1 API spec (EEex-compatible surface used by SadoEE)

> Status: spec, 2026-10-27. Target build: BG2EE/EET 2.7.3, linux64 first, win64 second.
> Clean room: behavior below comes from (a) how SadoEE calls each function and what it expects back,
> (b) the public EEex user docs (eeex-docs.readthedocs.io; most Tier 1 entries are marked "undocumented"
> there, so SadoEE usage is the main source), (c) our engine data (`IEX-data/engine/*.symbols.json`,
> `types/linux64-bg2ee-2.7.3.types.json`, `docs/sadoee_fields.md`). No EEex source was read.
> Where behavior is inferred from callers only, it is marked **[inf]**.

## 0. Conventions

**Impl class** (several can apply):

| Code | Meaning |
|---|---|
| **P** | pure Lua over IEX primitives: `IEX_ToObject(addr, type)`, `IEX_Address(ud)`, `IEX_TypeName(ud)`, typed field access (`ud.m_x`, `:get()/:set()`, `:get(i)`), `IEX_Log` |
| **E** | calls one or more engine functions (C++ thunk in IEX, exposed to Lua) |
| **H** | needs a new engine hook (IEX `callsite_hook` or function-entry/exit detour) |
| **F** | needs struct fields not yet in `sadoee_fields.md` / types json (listed) |

**Win conf** = confidence of the Windows match for the Linux symbol in `win64-bg2ee-2.7.3.symbols.json`
(`high` / `med` / `low` / `none` = Linux function has no Windows match yet). Linux addresses are ELF VAs (PIE base 0).

**Effort**: S ≤ ½ day, M 1–3 days, L ≥ 1 week (incl. testing in game).

**Sites** = textual occurrences in SadoEE (`E:/Enhanced Edition/SadoEE/SadoEE`, Lua + .d), comments included;
paths relative to that folder.

**ABI rule for E**: every engine call that takes or returns `CString` / `CResRef` / `CPoint` by value goes
through a per-platform shim (Itanium passes non-trivial classes by hidden reference; MSVC x64 passes 8-byte
classes in a register). Prefer engine functions with POD/pointer arguments, or reimplement in C++ from fields.

### Totals

| Group | Count |
|---|---|
| High-level `EEex_*` functions (game, sprite, area, action, trigger, resource, menu, key, utility) | 51 |
| Listener registrations + overridable hook globals | 8 + 2 (`EEex_Key_Hook_AfterEventsPoll`, `EEex_Actionbar_Private_ButtonsUpdatedListeners`) |
| `EEex_Options_*` | 8 |
| BCS extensions (action, trigger, object + 2 `_Object` globals) | 5 |
| Engine-bound userdata methods called directly | 7 (`getName`, `CheckLOS`, `virtual_GetVisibleTerrainTable`, `OnActionButtonClickGround`, `getAtPoint`, `getAtLabels`, stack-manager `getUD`) |
| Opcodes | 1 (403) |
| EEex.ini toggles | 1 (`[Empty Container Module] Enable=1`) |
| Low-level memory/asm | 35 (§9) |

---

## 1. Lifecycle listeners (first milestone)

All listeners: `EEex_X_AddYListener(fn)` appends `fn` to a Lua list; IEX calls each with `pcall`, logs errors
through `IEX_Log`, never lets one listener break the next. Registration may happen at any time (SadoEE guards
with `T.listenersAdded`); listeners added during dispatch run from the next event.

| API | Sig | Behavior (own words) | Sites | Impl | Engine hook / symbols (Linux addr; Win conf) | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_Menu_AddMainFileLoadedListener` | `(fn())` | Fires after the main UI menu file (`UI.MENU`) has been parsed, at startup; the place where mods load extra `.menu` files and inject templates. Docs mark it deprecated in favor of an "AfterMainFileLoaded" variant; keep both names. | 21; `qol/M_SQFPS.lua:65`, `camp/M_SQCAMP.lua:448` | H | Post-hook on `uiLoadMenu(CResText*)` 0x4d9490 (W high), fire when the CResText is `UI`. Fallback: post-hook of the first `uiLoadFunctions()` 0x4d7d80 (W high) caller. | M | Must fire **before** the first menu is drawn and after `uiStrings` exist; a listener that loads a menu with a missing style aborts the load (SadoEE comment M_SQCAMP:450). |
| `EEex_Menu_AddAfterMainFileReloadedListener` | `(fn())` | Fires after the UI is reloaded at runtime (debug UI reload, language switch), when every injected menu is gone; SadoEE re-loads its menus, re-injects, re-pushes its tick menu. | 15; `camp/M_SQCAMP.lua:453`, `camp/M_SQNECR.lua:692` | H | Same `uiLoadMenu("UI")` hook, 2nd+ call → fire after the reload finished. Candidates for "finished": return of `restoreMenuStack` 0x4e7ce0 (W none) or of the caller of `clearMenus` 0x4e8270 (W med). | M | Telling first load vs reload apart; Windows has no match for `restoreMenuStack`. |
| `EEex_Menu_AddTranslationLoadedListener` | `(fn())` | Fires after the language strings (`uiStrings`) are (re)built, so mod labels put into `uiStrings` survive a language change. | 1; `qol/M_SQMB.lua:76` | H | Post-hook `retranslateMenus` 0x4e80d0 (W low) and/or `dimmChangeLanguage(char const*)` 0x58a5e0 (W med). | S | Low (one site; SadoEE also calls `labels()` directly). |
| `EEex_GameState_AddInitializedListener` | `(fn())` | Fires once when the engine's game state is ready, after all `M_*.lua` files have run (SadoEE `M_SQMODE.lua:244` relies on "every M_ file has run"). | 21; `qol/M_SQFPS.lua:67`, `camp/M_SQCAMP.lua:459` | H | Post-hook `CBaldurChitin::Init()` 0x132070 (W med) if M_ files are already loaded there; otherwise first `CChitin::Update()` 0x593090 (W high) tick after the main menu file loaded. | S | Ordering vs M_ file loading must be verified in game. |
| `EEex_Sprite_AddLoadedListener` | `(fn(sprite))` | Fires whenever a creature object is created from file/save (area load, save load, summon). SadoEE ignores the argument and uses it as "a game/area just loaded → re-push my tick menu". | 16; `qol/M_SQFPS.lua:66`, `camp/M_SQWAIT.lua:184` | H | Post-hook `CGameSprite::CGameSprite(uchar*, int, ushort, uint, ushort, ushort, uint…)` 0x4b3170 (W high) or `CGameObjectArray::Add(int*, CGameObject*, int)` 0x2dab70 (W high) filtered on `m_objectType==0x31`. Pass the sprite userdata. | S | Fires many times per load; fine for SadoEE (idempotent). Do not fire from inside the ctor before `m_id` is set: prefer the `Add` hook. |
| `EEex_Key_AddPressedListener` | `(fn(key) -> bool?)` | Called on each key-down with the SDL keycode; a truthy return consumes the key (engine never sees it). | 2; `qol/M_SQFPS.lua:69`, `M_PSTASH.lua:2598` | H | Shared SDL event hook (§1.1). | S | Key repeat: deliver only non-repeat downs **[inf]**. |
| `EEex_Action_AddSpriteStartedActionListener` | `(fn(sprite, action))` | Called when a sprite starts a new action; listener may edit the action in place (SadoEE sets `action.m_actionID = 0` to cancel it, `qol/M_SQMODE.lua:257`). | 2; `qol/M_SQAUTO.lua:467`, `qol/M_SQMODE.lua:263` | H, F | Post-hook `CGameSprite::SetCurrAction(CAIAction const&)` 0x454260 (W high, vtable) then pass `sprite.m_curAction` (so edits land in the live action). Skip `NoAction` (id 0). Alt: entry of `CGameSprite::ExecuteAction()` 0x45c650 (W low) when the action changed. | M | `SetCurrAction` also runs on clears/restores; must not re-enter when the listener queues actions. |
| `EEex_Actionbar_AddButtonsUpdatedListener` | `(fn())` | Called after the action bar rebuilt its buttons, so a mod can restyle them. | 1; `qol/M_SQMODE.lua:240` | H | Post-hook `CInfButtonArray::UpdateButtons()` 0x2d0a90 (W high). | S | — |
| `EEex_Actionbar_Private_ButtonsUpdatedListeners` | Lua array | The listener list itself; SadoEE swaps its own entry for hot reload (`qol/M_SQMODE.lua:235`). | 1 | P | Expose the list table under this global name. | S | — |

### 1.1 SDL event hook (keys, mouse, `EEex_Key_Hook_AfterEventsPoll`)

`EEex_Key_Hook_AfterEventsPoll(event) -> bool` is a **replaceable global**: SadoEE chains it (save `orig`,
install a wrapper, call `orig(event)` at the end; `camp/M_SQCAMP.lua:496`, `qol/M_SQMB.lua:127`,
`M_PSXP7.lua:1010`). IEX calls it for every polled SDL event; `true` = drop the event.
`event` is an `SDL_Event` userdata with `type`, `button.button`, `wheel.y`, `key.keysym.sym`
(SDL2 layout, identical on both OS); `SDL_EventType` must exist as a global enum table (`SDL_MOUSEBUTTONDOWN`…).

- **Hook**: IEX `callsite_hook` on the `SDL_PollEvent` call(s) inside `CChitin::ProcessEvents()` 0x591bc0 (W high);
  `SDL_PollEvent` 0x97c650 (W high, PE export). Wrapper: call real poll; if it returned 1, update key state,
  run `EEex_Key_Hook_AfterEventsPoll`, then on `SDL_KEYDOWN` the pressed listeners; if consumed, poll again.
- Effort M; risk: inlined/duplicated poll loops (check every call site in the binary, `hook_targets.txt`).

## 2. Key / menu helpers

| API | Sig | Behavior | Sites | Impl | Symbols / fields | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_Key_GetFromName` | `(name) -> keycode` | SDL keycode from an SDL key name (`'F12'`, `'Left Alt'`). | 14; `qol/M_SQFPS.lua:70`, `M_PSTASH.lua:1749` | E | `SDL_GetKeyFromName` 0x97ed30 (W high, export) | S | — |
| `EEex_Key_IsDown` | `(keycode) -> bool` | Whether the key is held now. | 11; `camp/M_SQCAMP.lua:476`, `qol/M_SQMB.lua:105` | E or P | `SDL_GetKeyboardState` 0x97ea50 + `SDL_GetScancodeFromKey` 0x97eb00 (both W high); or a Lua set kept by §1.1 | S | Focus loss leaves keys "down" with the event-set approach; use SDL state. |
| `EEex_Menu_LoadFile` | `(name)` | Loads `<name>.MENU` from the resource system and adds its menus to the UI. | 20; `qol/M_SQFPS.lua:65`, `camp/M_SQCAMP.lua:450` | E | `uiLoadMenu(CResText*)` 0x4d9490 (W high); get the CResText via `dimmGetResObject(CResRef const&, int, bool)` 0x586730 (W med) + `CRes::Demand()` 0x580080 (W high); MENU resource type code to confirm from engine data | M | `CResRef` by-ref arg OK; must run on the UI thread inside a listener; bridge hot-load crashed EET before (memory note) → only call from listeners. |
| `EEex_Menu_GetArea` | `(menuItemName) -> x, y, w, h` | Screen rect of a named menu (or item). | 1; `camp/M_SQCAMP.lua:53` | E, F | `findMenu` 0x4e7120 (W low) + `uiMenu` fields (area/offset) | M | `uiMenu` layout not in types json yet. Try `Infinity_GetArea` if the native UI exposes it **[inf]**. |
| `EEex_Menu_GetMousePos` | `() -> x, y` | Cursor in screen coordinates (`Infinity_GetScreenSize` space): the engine pointer `CBaldurChitin.m_ptPointer` (W +0xf98 / L +0xfe8), as EEex (observed 2026-10-29: EEex's value is that field, not `Infinity_GetMousePosition`). | 2; `camp/M_SQCAMP.lua:471`, `qol/M_SQATKM.lua:97` | P | field read; `Infinity_GetMousePosition()` fallback | S | SadoEE: `nNewX + x * rViewPort.right / screenWidth` = world point under the cursor (`CInfinity.rViewPort` = +0x78, the zoomed world view, as EEex). |
| `EEex_Menu_IsCursorWithinRect` | `(x, y, w, h) -> bool` | Cursor inside rect. | 1; `camp/M_SQCAMP.lua:54` | P | on top of GetMousePos | S | — |
| `EEex_Menu_InjectTemplateInstance` | `(menuName, templateName, id, x, y, w, h)` | Creates one instance of a template item (defined in a mod menu) inside another, existing menu (here the vanilla `WORLD_MAP`). | 3; `camp/M_SQCAMP.lua:441-443` | E, F | `uiCreateFromTemplate(CString, CPoint, int, int, int)` 0x4dd500 (W **none**) targets the current menu only; IEX must temporarily switch the target menu or append to `uiMenu` item list (fields of `uiMenu`, `uiItem`) | L | Highest UI risk; CString/CPoint by value; no Windows match. |

## 3. Game objects, globals, areas

| API | Sig | Behavior | Sites | Impl | Symbols / fields | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_EngineGlobal_CBaldurChitin` | global userdata | The `CBaldurChitin` singleton (`.m_pObjectGame`, `.m_pEngineWorld`…). Also `EngineGlobals.g_pBaldurChitin` (4 sites, M_PSXP7/M_SQRECR). | 26; `camp/M_SQCAMP.lua:467`, `M_PSXP7.lua:28` | P, F | Data symbol `g_pBaldurChitin` (not in the functions json: take from ELF `.symtab` objects / Windows by xref from `main`) → `IEX_ToObject(ptr,'CBaldurChitin')` | S | Must exist **before** M_ files run (M_PSXP7 comment). |
| `EEex_GameObject_Get` | `(id) -> CGameObject?` | Object by id, nil if invalid/deleted. | 40; `camp/M_SQCAIN.lua:125`, `camp/M_SQCAMP.lua:484` | E | `CGameObjectArray::GetShare(int, CGameObject**, bool)` 0x2d9fe0 (W **none**) or `GetDeny` 0x2da050 (W none); alternative: reimplement the id→slot lookup in C++ from the array fields | M | No Windows match: find by callers (`ChangeEntry`/`Delete` are matched) or go field-based. |
| `EEex_GameObject_CastUserType` | `(obj) -> typed ud` | Re-types a base object to its real class by `m_objectType` (0x31 sprite, trigger, container…). | 32; `camp/M_SQCAIN.lua:127` | P | `IEX_ToObject(IEX_Address(o), map[o.m_objectType])` | S | Type code table to confirm from engine data. |
| `EEex_UDEqual` | `(a, b) -> bool` | Same engine address. | 5; `qol/M_SQAUTO.lua:60` | P | `IEX_Address(a)==IEX_Address(b)` (IEX `==` already compares addresses) | S | — |
| `EEex_Area_GetVisible` | `() -> CGameArea?` | Area currently shown. | 17; `camp/M_SQCAIN.lua:138` | P | `game.m_gameAreas:get(game.m_visibleArea)` (both fields high) | S | — |
| `EEex_GameState_GetGlobalInt` / `SetGlobalInt` | `(name) -> int` / `(name, v)` | GLOBAL script variable (0 if unset; set creates). | 12 / 10; `camp/M_SQNECR.lua:118`, `M_PSTASH.lua:249` | E or P, F | `CVariableHash::FindKey(CString)` 0x2be340 (W high), `AddKey(CVariable&)` 0x2bef40 (W med) on `CInfGame.m_variables`; or `CGameAIBase::GetVariableReference(CString const&, CString const&)` 0x15edc0 (W high) with scope `GLOBAL`. Preferred: C++ reimplementation of the hash probe from `CVariableHash::Hash` 0x2be580 (avoids CString by value). | M | Fields: `CInfGame.m_variables`, `CVariableHash` (table ptr, size), `CVariable` (`m_name[32]`, `m_intValue`, string value). |
| `EEex_GameState_GetGlobalString` / `SetGlobalString` | `(name) -> str?` / `(name, s)` | Same, string value (≤8 chars, resref-like). | 1 / 1; `M_PSTASH.lua:279`, `:291` | same | same + `CVariable` string field | S (after ints) | Exact string field semantics **[inf]**. |
| `EEex_Area_GetVariableInt` / `SetVariableInt` | `(area, name)` / `(area, name, v)` | Area-scoped variable. | 3 / 2; `qol/M_SQTRAP.lua:46,65` | same | `CGameArea` variable hash field | S | Field offset to find (`CGameArea` ctor). |
| `EEex_Sprite_GetLocalInt` / `SetLocalInt` / `GetLocalString` / `SetLocalString` | `(sp, name)` / `(sp, name, v)` | LOCALS variables of a creature (saved with it). Get returns 0 / "" when unset. | 21 / 17 / 5 / 4; `camp/M_SQCAMP.lua:104-113` | same | `CGameSprite` local variable hash ptr (`m_pLocalVariables` **[inf]**) | S | Same hash code as globals. |
| `EEex_Area_GetAllOfTypeStringInRange` | `(area, x, y, aiType, range, checkLOS) -> {sprite}` | All objects matching an object-type string (`'[FAMILIAR]'`) within range of a point. | 1; `M_PSTASH.lua:717` | E | `CAIScriptFile::ParseObjectType(CString&)` 0x52c9a0 (W high) → `CAIObjectType`; `CGameArea::GetAllInRange(CPoint const&, CAIObjectType const&, short, uchar const*, CTypedPtrList&, …)` 0x17cb10 (W med) | M | Needs a CAIScriptFile instance (ctor not named in json); terrain table arg. |
| `EEex_Object_AddToArea` | `(obj, area, x, y)` | Places an object in an area at a point. | 1; `camp/M_SQRECR.lua:590` | E | `CGameSprite::AddToArea(CGameArea*, CPoint const&, int, uchar)` 0x46ecc0 (W high, vtable) via vtable call | S | Meaning of the int/uchar args (listType, face) **[inf]**. |
| `EEex_Utility_IterateCPtrList` | `(list, fn(data) -> stop?)` | Walks an MFC CPtrList head→tail, passes each node's data; `true` stops. | 27; `camp/M_SQCAIN.lua:96` | P | `m_pNodeHead`, `pNext`, `data` (in fields doc). Data is a pointer or an int id depending on list (lists of ids: `m_lVertSort`). | S | Typed data needs the list's element type from the registry. |

## 4. Sprites

| API | Sig | Behavior | Sites | Impl | Symbols / fields | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_Sprite_GetInPortrait` | `(slot 0-5) -> sp?` | Party member in portrait slot, nil if empty (docs). | 89; `camp/M_SQCAIN.lua:29` | E or P, F | `CInfGame::GetCharacterSlot(int)` 0x2eef40 (W high) → id → GameObject_Get; or `CInfGame` portrait id array field | S | Big party (#40) extends slots past 5: keep it a plain Lua global so M_PSXP7 can wrap it. |
| `EEex_Sprite_GetInPortraitID` | `(slot) -> id / -1` | Same, id only (docs). | 2; `M_PSXP7.lua:768` | same | same | S | — |
| `EEex_Sprite_GetPortraitIndex` | `(sp) -> slot / -1` | Portrait slot of a sprite, -1 if not in party (docs). | 20; `camp/M_SQNECR.lua:274` | E | `CInfGame::GetCharacterPortraitNum(int id)` 0x2e4d70 (W med) | S | SadoEE **replaces** it and `CGameSprite.getPortraitIndex` (`M_PSXP7.lua:786`): IEX internals must call through the global, never cache. |
| `EEex_Sprite_GetCharacterIndex` | `(sp) -> index / -1` | Index in the fixed party order (vs on-screen portrait order) **[inf]**. | 3; `M_PSXP7.lua:769` | E | `CInfGame::GetCharacterSlotFromId(int)` 0x2eef50 (W high) or `GetFixedOrderCharacterPortraitNum(int)` 0x2e4de0 (W med) | S | Which of the two matches EEex: verify against a 6-member party with reordered portraits. Also replaced by M_PSXP7. |
| `EEex_Sprite_GetSelected` / `GetSelectedID` | `() -> sp? / id` | Selection "leader": highest-priority portrait among selected, else first selected; nil / -1 if none (docs). | 5 / 1; `camp/M_SQNECR.lua:402`, `M_PSXPG.lua:168` | P, F | `CInfGame` selection group (`CAIGroup`) member id list; `CAIGroup::GetGroupList()` 0x512030 (W med) | S | Group field offset to add. |
| `EEex_Sprite_GetAllSelected` / `GetAllSelectedIDs` | `() -> {sp}` / `{id}` | All selected controllable sprites (docs). | 4 / 1; `qol/M_SQATKM.lua:145`, `M_PSTASH.lua:3550` | P, F | same | S | — |
| `EEex_Sprite_GetStat` | `(sp, statId) -> int` | Current effective stat by STATS.IDS id (SadoEE uses vanilla ids: 1 MAXHP, 7, 8, 26, 28, 34, 36, 37, 68, 147, 152, VISUALRANGE, TRAPS). | 40; `camp/M_SQNECR.lua:211` | E | `CDerivedStats::GetAtOffset(short)` 0x15be10 (W **low**) on the active stats (`m_derivedStats`; or temp stats while effects are being applied) | M | Low Windows confidence; fallback = C++ table stat id → `CDerivedStats` field (the function is a big switch, readable in Ghidra). |
| `EEex_Sprite_GetName` / `sp:getName()` | `(sp) -> string` | Display name. | 6 + 13; `camp/M_SQNECR.lua:534`, `camp/M_SQRECR.lua:495` | E | `CGameSprite::GetName(int)` 0x4a1a30 (W med) returns a CString → shim; or `m_baseStats` name strref + `Infinity_FetchString` (P) | S | Renamed PCs keep their name elsewhere: test on a player char. |
| `EEex_Sprite_GetKnownMageSpellsIterator` / `…PriestSpellsIterator` | `(sp) -> iterator (level, index, resref)` | Iterates every known wizard / priest spell. | 3 / 1; `camp/M_SQRESP.lua:368`, `M_PSXP7.lua:893` | P, F | Per-level known-spell lists on `CGameSprite` (`CTypedPtrList<CCreatureFileKnownSpell*>` ×9 / ×7) + `CCreatureFileKnownSpell.m_knownSpellId` (resref) | S | Level base (0 or 1) **[inf]**: SadoEE only uses the resref and treats level as display. |
| `EEex_Sprite_DisplayTextRef` | `(sp, strref, {overHead=bool})` | Shows a string over the creature's head (or in the log). | 1; `qol/M_SQMODE.lua:72` | E or P | `CGameSprite::DisplayTextRef(uint, uint, uint, uint)` 0x4a5fc0 (W high); P fallback: instant `DisplayStringHead(Myself, strref)` | S | Arg meanings **[inf]**. |

## 5. Actions, triggers, effects

| API | Sig | Behavior | Sites | Impl | Symbols / fields | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_Action_QueueResponseStringOnAIBase` | `(actionsText, aiBase)` | Parses a BCS response string (`'JumpToPoint([x.y])'`, several actions) and appends the actions to the object's queue. | 25; `camp/M_SQCAMP.lua:91,144` | E | `CAIScriptFile::ParseResponseString(CString)` 0x540aa0 (W med) → `CAIResponse`; per action `CGameAIBase::InsertAction`/`AddAction(CAIAction const&)` 0x175490 (W **none**) — or `CAIResponse` list walk + `CMessageAddAction` | M | Needs a parser instance (CAIScriptFile ctor), CString by value, `AddAction` unmatched on Windows. |
| `EEex_Action_ExecuteResponseStringOnAIBaseInstantly` | `(actionsText, aiBase)` | Parses and runs the actions now, in order, on that object, without touching its queue (SadoEE: `TakePartyGold`, `DestroyItem`, `ChangeAIScript`, `ChangeEnemyAlly`…). One action per line (the engine parser reads one action per line, like a BAF; `"A() B()"` keeps only `A()`). | 31; `camp/M_SQCAIN.lua:114` | **done** | Same parse; `IEX_ExecuteResponseInstantly` (src/core/lua_scripting.cpp): current action moved out, per action: `CAIAction` copy ctor (L 0x4c5940, W 0x116930) into `m_curAction`, SetCurrAction field setup (+0x3e8/+0x3ec = 0, +0x4ba = -1), `CAIAction::Decode` (L 0x50fc60, W 0x116170) unless in the CInfGame+0xa8 id list (`CAIIdList::Find` L 0x519960, W 0x11b480), `ExecuteAction` vtable slot (L +0x108, W +0x100); then the action is destroyed and the old current action / state restored. Evidence: verified_instant.json | M | Multi-tick actions (moves, attacks, spells) run one step and are dropped. No `OnActionRemoval` of the interrupted action, no sprite modal-state reset. Actions that clear or replace the current action (ClearActions...) are undone by the restore. |
| `EEex_Trigger_ParseConditionalString` | `(triggersText) -> condition` | Compiles trigger text (`'PartyGoldGT(4)'`, `'See(EEex_LuaObject)'`) once; result cached by caller. | 4; `camp/M_SQCAIN.lua:58`, `qol/M_SQATKM.lua:40` | E | `CAIScriptFile::ParseConditionalString(CString)` 0x5408c0 (W high) → `CAICondition` (keep owned userdata, freed on GC) | M | Lifetime of the parsed object. |
| `EEex_Trigger_EvalScriptFileConditionalAsAIBase` | `(condition, aiBase) -> bool` | Evaluates the compiled triggers as that object. | 4; `camp/M_SQCAIN.lua:59` | E | `CAICondition::Hold(CTypedPtrList<CPtrList,CAITrigger*>&, CGameAIBase*)` 0x56c390 (W med) | S | Trigger list arg = the object's pending triggers (pass an empty list for status triggers) **[inf]**. |
| `EEex_GameObject_ApplyEffect` | `(obj, t)` | Builds an effect from a Lua table and applies it to the object. Keys used: `effectID, durationType, effectAmount, dwFlags, res, duration, sourceID, sourceTarget, m_sourceRes, targetType, spellLevel, probabilityUpper`. Missing keys = 0/"" except probability (100) **[inf]**. | 11; `camp/M_SQCAMP.lua:332`, `camp/M_SQNECR.lua:80` | E, F | Fill an `Item_effect_st` buffer, `CGameEffect::DecodeEffect(Item_effect_st*, CPoint const&, int, CPoint const&, int)` 0x1d5c20 (W med), then the object's virtual `AddEffect(CGameEffect*, uchar, int, int)` (`CGameSprite::AddEffect` 0x42ab20, W low/folded) | M | Fields: `Item_effect_st` layout (V2 effect, 0x110). Memory note: no permanent effects in the maintainer's live game during tests. |
| Opcode **403** (Screen Effects) | effect `res = 'SQDMGSCR'` (Lua global ≤8 chars, upper case), `durationType 9` | While the 403 effect is on a creature, every effect about to be added to it is first passed to `FN(op403Effect, incomingEffect, sprite)`; returning true blocks it (docs). SadoEE only reads `e.m_effectId`, `e.m_sourceId` and returns false. | 3; `camp/M_SQNECR.lua:236,520` | H, F | Entry hook on the add-effect path: `CGameSprite::AddEffect` 0x42ab20 (Linux; W low) — scan `m_timedEffectList` for effects with `m_effectId==403`, call the named global. Make sure `DecodeEffect` keeps opcode 403 as a plain inert `CGameEffect` (no "unknown opcode" drop) | M | Hot path (every effect): keep a per-sprite "has 403" flag in C++. Fields: `CGameEffect.m_effectId/m_res/m_sourceId/m_sourceRes`. |

## 6. Resources

| API | Sig | Behavior | Sites | Impl | Symbols / fields | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_Resource_Demand` | `(resref, ext) -> header ud?` | Loads and locks a resource, returns its file header typed (`ITM` → item header: `itemType, genericName, maxStackable, itemFlags`; `SPL` → spell header: `spellLevel, abilityOffset`; `STO`). nil if missing. | 26; `camp/M_SQCAIN.lua:197`, `camp/M_SQPRST.lua:72` | E | `dimmGetResObject(CResRef const&, int, bool)` 0x586730 (W med) + `CRes::Demand()` 0x580080 (W high); data ptr → `IEX_ToObject(p, 'Item_Header_st' / 'Spell_Header_st' / …)`. Type codes: standard IE ids (ITM 0x3ED, SPL 0x3EE, STO 0x3F6, 2DA 0x3F4, BMP 0x001) | M | Never released by SadoEE → keep the lock (resource stays cached; same as EEex use pattern). |
| `EEex_Resource_Fetch` | `(resref, ext) -> ud?` | Like Demand without keeping it; used as "does it exist" (nil = missing). | 2; `camp/M_SQCAIN.lua:80`, `camp/M_SQNECR.lua:485` | E | `dimmResourceExists(char const*, int)` 0x586a20 (W med) then Demand | S | — |
| `EEex_Resource_GetSpellAbility` | `(splHeader, i) -> Spell_ability_st` | i-th ability of a demanded spell. | 1; `camp/M_SQRESP.lua:475` | P | `header + abilityOffset + i*0x28` → `IEX_ToObject(…,'Spell_ability_st')` | S | — |
| `EEex_Resource_Load2DA` | `(resref) -> 2da ud` | Loads a 2DA table. Methods used: `a:getAtPoint(col,row)`, `a:getAtLabels(colName,rowName)`. | 14; `camp/M_SQPRST.lua:126`, `camp/M_SQRECR.lua:760` | E, F | allocate `C2DArray`, `C2DArray::Load(CResRef const&)` 0x50d960 (W high) | S | Fields for P lookups: `C2DArray` names X/Y, cell array, size X/Y, default. |
| `EEex_Resource_GetAt2DALabels` | `(a, col, row) -> string` | Cell by column/row labels (default value when missing). | 16; `camp/M_SQPRST.lua:128` | P (fields) or E | P: label search over `C2DArray` fields; E: `C2DArray::GetAt(CString const&, CString const&) const` 0x50ecb0 (W high) | S | Prefer P: no CString. |
| `EEex_Resource_Free2DA` | `(a)` | Frees a loaded 2DA. | 4; `camp/M_SQPRST.lua:130` | E | `C2DArray::~C2DArray()` 0x137400 (W none) + IEX free | S | Win dtor unmatched: do it in C++ from fields or never free (tiny leak). |

## 7. EEex_Options_* (only `qol/M_SQMB.lua:61-100`)

SadoEE registers 4 options (mouse buttons B4/B5/wheel…), each an int 0..3 stored in `Baldur.ini` section
`SadoQoL`, shown on a tab with a 4-way toggle. **Impl: P** (pure Lua + an IEX options `.menu`), effort **M**,
risk low. Stage 1 = data model only (Register/Get work, tab kept but not drawn); stage 2 = the options screen.

| API | Behavior needed |
|---|---|
| `EEex_Options_Option.new{default, accessor, storage}` | Option object; value starts from storage, else default. |
| `EEex_Options_ClampedAccessor.new{min, max}` | Clamps the stored number. |
| `EEex_Options_NumberLuaStorage.new{section, key}` | Number persisted through `Infinity_GetINIValue` / `Infinity_SetINIValue`. |
| `EEex_Options_Register(id, option)` | Global registry by id. |
| `EEex_Options_Get(id):get()` | Current value (SadoEE wraps it in pcall). |
| `EEex_Options_AddTab(labelStrKey, fn -> {{rows}})` | Adds a tab to the options screen; `fn` builds the rows lazily. Label keys are `uiStrings` keys. |
| `EEex_Options_DisplayEntry.new{optionID, label, description, widget}` | One row. |
| `EEex_Options_HorizontalMultiToggleWidget.new{toggles={{label, data={toggleValue}}}}` | Radio-like toggle writing `toggleValue`. |

## 8. BCS extensions

| Item | Used as | Behavior | Sites | Impl | Engine | Eff | Risk |
|---|---|---|---|---|---|---|---|
| `EEex_LuaAction(S:Chunk)` (ACTION.IDS) | dialog actions, e.g. `EEex_LuaAction("SQCain_Identify()")` | Runs the Lua chunk; global `EEex_LuaAction_Object` = the acting object during the call. | 22 in 7 .d files; `camp/dlg/SQCAIN.d:17`, `quests/PSXQCAIN.d` | H, F | Entry hook `CGameAIBase::ExecuteAction()` 0x16ded0 (W high) + sprite override 0x45c650 (W low): if `m_curAction.m_actionID == LUA_ACTION_ID` run `m_string1`, report "done" | M | Dialog actions run through the same path? verify (dialog uses `CGameSprite` queue). |
| `EEex_LuaTrigger(S:Chunk)` (TRIGGER.IDS) | dialog conditions `EEex_LuaTrigger("return(SQCain_Ok())")` | Runs the chunk, truthy result = trigger true; `EEex_LuaTrigger_Object` = the evaluating object. | 23 in .d; `camp/dlg/SQCAIN.d:6` | H | Entry hook `CGameSprite::EvaluateStatusTrigger(CAITrigger const&)` 0x4556a0 (W high) and `CGameAIBase::…` 0x161ca0 (W low) for non-sprites | M | Dialog trigger evaluation may go through another path (`CAICondition::TriggerHolds` 0x56c6c0, W none). |
| `EEex_LuaAction_Object` / `EEex_LuaTrigger_Object` | Lua globals | Set to the object userdata for the duration of the chunk, restored after (nesting). | 5 / 1; `camp/M_SQWAIT.lua:90-112` | P | — | S | — |
| `EEex_LuaObject` (OBJECT.IDS object function) | Lua sets the global to a sprite, then a script string uses `EEex_LuaObject` as a target: `'StartDialogNoSet(EEex_LuaObject)'`, `'See(EEex_LuaObject)'` | Triggers / object strings evaluated now: the object the Lua global holds at evaluation. Actions queued or run instantly from Lua: the object it held when they were queued. | 16; `camp/M_SQNECR.lua:186`, `qol/M_SQATKM.lua:40` | **done** | Hook `CAIObjectType::Decode(CGameAIBase*)` call sites (E8 calls only): our object functions resolved, others passed through unchanged. Queue / instant: every action object using 115/117 is decoded for the receiving object before `InsertResponse` copies the actions (concrete type + instance id, object functions cleared, NOONE when no target), then the parsed response gets its original objects back | M | BCS-compiled scripts using `EEex_LuaObject` still resolve lazily; the third object of an action (actee2) is decoded by a tail jump in `CAIAction::Decode`, not hooked. |
| IDS entries | — | IEX's installer appends the three names to ACTION.IDS / TRIGGER.IDS / OBJECT.IDS with the **same numeric ids as an EEex install**, so DLGs compiled by SadoEE (at its own install) bind either way. Ids to read from an EEex-installed game's IDS files (data), not from EEex code. | — | data | `CAIIdList::LoadList(int)` 0x519430 (W high) loads them | S | Must be installed before SadoEE (WeiDU order). |
| `REQUIRE_PREDICATE MOD_IS_INSTALLED ~EEex.tp2~ … B3-EEex-Main` | 31 components of `SadoEE.tp2` | Either IEX ships a tp2 answering that label, or SadoEE gets an `EEex OR IEX` predicate. | — | data | — | S | Decision for the maintainer. |

## 8b. Engine-bound userdata methods called directly

| Call | Sites | IEX plan |
|---|---|---|
| `area:CheckLOS(a, b, terrainTable, 0, 0)` | 2; `qol/M_SQTRAP.lua:123`, `qol/M_SQCHST.lua:30` | E: `CGameArea::CheckLOS(CPoint const&, CPoint const&, uchar const*, uchar, short)` 0x178b10 (W low) |
| `sp:virtual_GetVisibleTerrainTable()` | 2; same lines | E: `CGameSprite::GetVisibleTerrainTable()` 0x194da0 (W high, vtable) |
| `area:OnActionButtonClickGround(pt)` | 1; `qol/M_SQATKM.lua:136` | E: `CGameArea::OnActionButtonClickGround(CPoint const&)` 0x186d70 (W med) |
| `EEex_RunWithStackManager(defs, fn(m))` + `m:getUD(name)` | 3; `qol/M_SQTRAP.lua:119` | P/E: allocate temp structs (`CPoint` fromXY) in IEX scratch memory, pass typed ud, free after `fn` |
| `a:getAtPoint`, `pdialog:getAtLabels` | 6; `camp/M_SQRECR.lua:763`, `M_PSXP7.lua:1207` | P over `C2DArray` fields (§6) |
| `sp:getName()` | 13 | = `EEex_Sprite_GetName` |
| `EEex_NewUD('CItem' / 'CResRef')` | 2; `M_PSXGM.lua:279` | E: zeroed engine-heap block of the type size (+ ctor `CItem::CItem()` 0x23a920, W med) |

Generic method binding (calling any engine method by name) is **not** Tier 1: bind exactly these.

---

## 9. Low-level memory / asm API used by SadoEE

| API | Sites | Used for | IEX plan |
|---|---|---|---|
| `EEex_ReadU8/U16/U32/U64`, `ReadS16`, `Read16`, `Read32`, `ReadPtr`, `ReadLString(p, n)` | 45/27/55/2, 1, 2, 18, 1, 2 | raw field reads at hard-coded offsets, byte checks before patches | P-level C primitives, trivial on both OS (S). **But every offset in SadoEE is Win64-2.7.3** → wrong on Linux. |
| `EEex_WriteU8/U16/U32`, `Write16/32/64`, `WritePtr` | 43/2/33, 1/52/2, 1 | field writes (stash, party), code patching | same (S); same offset problem |
| `EEex_BAnd/BOr/BNot` | 46/6/1 | flags | P via `bit32` (S) |
| `EEex_Malloc(n)` / `EEex_Free(p)` | 14 / 1 | flags, scratch buffers, colors read by asm | C: engine allocator (`SDL_malloc` 0x9811a0 W high, or the CRT `malloc` the engine imports) (S) |
| `EEex_AllocNear(n)` | 5 | executable memory within ±2 GB of the exe for JIT code | Win-compat layer only |
| `EEex_UDToPtr(ud)` / `EEex_PtrToUD(p, type)` | 53 / 6 | address of userdata / typed view of an address | = `IEX_Address` / `IEX_ToObject` (S) |
| `EEex_DisableCodeProtection` / `EnableCodeProtection` | 15 / 15 | make `.text` writable around patches | `mprotect` / `VirtualProtect` (S) — only meaningful with the compat layer |
| `EEex_JITNear(asmText or table)` | 11 | assemble x64 Intel-syntax text (with EEex macros `#MAKE_SHADOW_SPACE`, `#ENDL`, `#$(n)`) | Win-compat layer only (needs an assembler: L) |
| `EEex_FlattenTable`, `EEex_GenLuaCall(fnName, {args, returnType})`, `EEex_LuaCallReturnType` | 5, 5, 2 | build asm that calls a Lua global from a hook | Win-compat only |
| `EEex_HookBeforeCallWithLabels(addr, labels, asm)`, `EEex_HookIntegrityWatchdogRegister`, `EEex_HookIntegrityWatchdog_IgnoreStackSizes` | 2, 4, 1 | detour a `call` site, run asm first | Win-compat only |
| `EEex_Label(name)` | 4 | address of an EEex-internal label (`Hardcoded_lua_tointegerx`, `Hook-CGameContainer::Render()-B3EmptyContainer`, `Hook-CGameSprite::ProcessEffectList()-FirstRandCall`) | Not reproducible (EEex internals). Replace each use (§11). |
| `EEex_ExposeToLua(addr, name)` | 2 | publish a JIT'd C function as a Lua global (`PStash_Eng_*`, `SQRespec_Eng_*`) | Replace by native IEX Lua functions |

---

## 10. Order of implementation

**Chosen first component: #23 FPS counter (`qol/M_SQFPS.lua` + `SQFPS.menu`)** — the only EEex-dependent
component made of nothing but lifecycle listeners + 2 helpers (no fields, no asm, no BCS):
`Menu_AddMainFileLoadedListener`, `Menu_LoadFile`, `Sprite_AddLoadedListener`, `GameState_AddInitializedListener`,
`Menu_AddAfterMainFileReloadedListener`, `Key_AddPressedListener`, `Key_GetFromName` (+ native `Infinity_*`).
(#32 Auto-roller uses no EEex at all, so it proves nothing.)

| Milestone | Content | Unlocks SadoEE components |
|---|---|---|
| **T1-A** "it draws" | §1 listeners (menu loaded/reloaded, game init, sprite loaded), SDL poll hook + `Key_AddPressedListener`, `Key_GetFromName`, `Key_IsDown`, `Menu_LoadFile`, `IEX_Log` error reporting | **#23 FPS counter** |
| **T1-B** objects | `EngineGlobal_CBaldurChitin`, `GameObject_Get/CastUserType`, `UDEqual`, `UDToPtr/PtrToUD`, `Area_GetVisible`, `Utility_IterateCPtrList`, `BAnd/BOr/BNot`, Sprite portrait/selection/stat/name/locals, Area variables, `RunWithStackManager` + `CheckLOS`, `Resource_Demand` | #20 passive traps (also needs Action Execute), #1 sorted loot (+ `WritePtr` with Linux offset) |
| **T1-C** scripting | Action Queue/ExecuteInstantly, Trigger Parse/Eval, `Action_AddSpriteStartedActionListener`, `EEex_LuaObject`, `GameState_*Global*`, `Area_GetAllOfTypeStringInRange` | #22 auto-disarm |
| **T1-D** BCS + effects | `EEex_LuaAction/LuaTrigger` (+ `_Object`), IDS install, `GameObject_ApplyEffect`, opcode 403, 2DA + Fetch/GetSpellAbility, `Object_AddToArea`, `DisplayTextRef`, known-spell iterators, `NewUD` | #12 scholar, #13 waiting, #16 chronicle, #17 necromancer, #50-53 priest prices — **but all need #10 camp** (asm, T1-F) |
| **T1-E** UI | `Menu_InjectTemplateInstance`, `Menu_GetArea`, mouse helpers, translation listener, `Actionbar_*` listener + `GetArray`, `Key_Hook_AfterEventsPoll`, Options (data then screen) | #29 mouse buttons; UI parts of #10 |
| **T1-F** native ports | §11 | #0-7 stash, #10 camp, #11, #14, #15, #21, #24-28, #30, #31, #40 |

Critical path: #10 camp is asm-bound (world-map JIT stubs in `M_SQCAMP.lua:181-216`), and #11-17 require it —
so porting the camp's two patches early (T1-F first item) unlocks most of the "camp" family.

## 11. Low-level API on IEX: proposal

**Problem.** ~16 SadoEE Lua files bind to Win64-2.7.3 addresses (`M_SQ0BLD.lua` address table + v2.6.6 remap) and
x64 MSVC-ABI asm. None of it can run on Linux (different binary, SysV ABI, other layouts), and the asm DSL
(`JITNear`, `HookBeforeCallWithLabels`, EEex macros, `EEex_Label` of EEex-internal hook points) cannot be
reproduced clean-room without becoming EEex.

**Recommendation: portable C++ hooks in IEX, exposed as small, named Lua events; rewrite SadoEE's patch
files against them. Do NOT build a Windows-only asm compat layer for SadoEE** (keep that idea for
third-party T3 mods only, milestone M8 of the phase 1 plan).

- Every SadoEE patch is one "decision point" inside one engine function. IEX gives each a typed Lua hook
  resolved per build from the engine description (Linux symbols; Windows matches), e.g.
  `IEX_Hook_AddListener('CGameSprite::Swing.keepAmmo', fn(sprite, item) -> bool)`.
- Hooks are written once in C++ (entry/exit detours or IEX `callsite_hook`), so they work on both OS and on
  2.6.6/2.7.3 as long as the function is matched — no more address tables, no byte probes.
- SadoEE keeps a thin `M_SQ0BLD.lua`-style shim: `if IEX then use IEX hook else old EEex asm` during transition.
- Field offsets used through `EEex_Read*/Write*` (`MODAL_OFF = 0x3A29`, `BUTTON_SIZE`, `OFF_NODE_DATA`…) become
  typed fields in the types json (one-time conversion, mechanical).

| SadoEE feature (file) | Engine function patched (Linux sym; Win conf) | Native IEX hook to offer | Eff |
|---|---|---|---|
| #24 endless ammo (`qol/M_SQAMMO.lua`) | `CGameSprite::Swing(CGameSprite*)` 0x44d800 (W none), call to `CItem::SetUsageCount(int, ushort)` 0x231a80 (W med) | before use-count decrement: `fn(sprite, item) -> keep` | M |
| #21 valuable containers (`qol/M_SQCONT.lua`, EEex.ini Empty Container Module) | `CGameContainer::Render(CGameArea*, CVidMode*)` 0x19f190 (W med) | outline color per container: `fn(container) -> color?` (replaces the EEex module + label) | M |
| #25/26 footprint (`qol/M_SQFOOT.lua`) | `CSearchBitmap::AddObject/RemoveObject/SnapshotRemoveObject` 0x2b68a0/0x2b6a50/0x2b7370 (W med) | config value: personal-space size (0/1/3) | S |
| #27 lasting modes (`qol/M_SQMODE.lua`) | `CGameSprite::CheckModal()` 0x42d630 (W high), `ForceVisible()` 0x41fd10 (W none), `SetModalState(uchar,int)` 0x47ed20 (W med), `SetCurrAction` | `fn(sprite, oldMode) -> keepMode` | M |
| #28 attack-move (`qol/M_SQATKM.lua`) | `CGameArea::OnActionButtonClickGround(CPoint const&)` 0x186d70 (W med), `OnFormationButtonUp`, `AIUpdate()` 0x18e5e0 (W high) | ground-click listener `fn(area, x, y) -> consumed` + area tick | M |
| #30 keep gear (`qol/M_SQKEEP.lua`) | `CGameEffectDeath::ApplyEffect(CGameSprite*)` 0x1f0020 (W high) → `CGameSprite::DropInventory(uchar,int)` 0x419b50 (W high) | `fn(sprite) -> skipDrop` | S |
| #31 chests in ground bar (`qol/M_SQCHST.lua`) | `CGameSprite::UpdateVisibleGroundItems()` 0x46ddd0 (W high) | `fn(sprite, list)` to append containers | M |
| #10 camp (`camp/M_SQCAMP.lua`) | `CScreenWorldMap::OnAreaMouseClick(uint)` 0x3b3a40, `DrawMap(CRect const&)` 0x3aefd0 (W med), `CGameArea::OnActionButtonClickTravel(CPoint const&)` 0x187140 (W none) | world-map click/draw listeners; travel-button listener | M |
| #14 respec (`camp/M_SQRESP.lua`) | `CScreenCreateChar::RemoveAbilities(CGameSprite*, int, int)` 0x34c920 (W none) + JIT'd Lua C functions | native `IEX_*` functions replacing `SQRespec_Eng_*` | M |
| #11 merchant (`M_PSXGM.lua`) | `CStore::AddItem(CItem&)` 0x2bb120, `CompressItems()` 0x2bb720, `GetItemBuyValue(CItem&, uchar, short)` 0x2ba9a0, `CInfGame::AddItemToStore` 0x2e4350 | store item add/price listeners | M |
| #0-7 Party Stash (`M_PSTASH.lua`, `M_PSXENG.lua`) | `CGameSprite::ProcessEffectList(int)` 0x427370, `CInfGame::SwapItemPersonalInventory` 0x30e990, `AddPartyGold(int)` 0x2f0780, `CScreenStore::UpdateBuySellPanel()` 0x389850 + `PStash_Eng_*` JIT functions | native stash functions + item-swap / gold listeners | L |
| #40 big party (`M_PSXP7*.lua`, `lib/party.tpa`) | ~30 functions (`CInfGame::Marshal` 0x2dc8a0, `CAIGroup::Sort()` 0x512290, `RemoveCharacterFromParty`, `GetCharacterCriteria`, `CScreenWorld::OnKeyDown` 0x39ed00, `CGameAIBase::EvaluateStatusTrigger`…; site table `M_PSXP7S.lua`) | dedicated C++ "party size" module in IEX (array growth, save format) — not a Lua hook set | L |

**Risks of this route**: SadoEE must be edited (two code paths for a while); every hook needs a Windows match
(several targets are `W none`: `Swing`, `ForceVisible`, `OnActionButtonClickTravel`, `RemoveAbilities` → match them
by callers/strings first); #40 is a full engine feature.
**Risk of the rejected route** (Win asm compat): reimplementing the EEex asm DSL + labels is large, clean-room
fragile, and still leaves Linux broken.

## 12. Top risks (Tier 1)

1. **Windows matches missing/low** on core calls: `CGameObjectArray::GetShare` (none), `CGameAIBase::AddAction` (none),
   `CDerivedStats::GetAtOffset` (low), `CGameSprite::AddEffect` (low), `uiCreateFromTemplate` (none),
   `CGameAIBase::EvaluateStatusTrigger` (low). Plan C++ field-based fallbacks.
2. **CString/CResRef/CPoint by-value ABI** differs (Itanium vs MSVC) → per-platform call shims; prefer field-based reimplementation (variables, 2DA).
3. **Event ordering** (menu loaded vs M_ files vs game init) — SadoEE depends on it (styles before menus, "every M_ file has run").
4. **BCS dispatch paths**: dialog triggers/actions may not pass through the hooked virtuals; IDS numbers must equal EEex's.
5. **SadoEE monkey-patches EEex globals** (`EEex_Sprite_GetPortraitIndex`, `EEex_Key_Hook_AfterEventsPoll`, listener list): IEX internals must always look these up by global name.
6. **Hard-coded Win64 offsets** in `Read*/Write*` code: silently wrong on Linux — guard with build detection and move to typed fields.

## 13. IEX extensions (no EEex equivalent)

Own API for mods that target IEX directly (first user: the First Person mod). Lua side in `lua/IEX_Camera.lua`.

| Function / event | Behavior | Engine |
|---|---|---|
| `IEX_Camera_AddRenderListener(fn)` (event `AreaRender`) | `fn(area)` every frame just before the area is drawn, on every screen that shows it; a camera moved there is drawn in the same frame. | call-site hook on `CGameArea::RenderZoomed()` (Win 0x189e20 high, 6 sites) |
| `IEX_Camera_GetView(area)` → `x, y, w, h` | Top-left world point (`nNewX/nNewY`) and world size of the view (`rViewPortZoomed`). | fields |
| `IEX_Camera_SetView(area, x, y)` / `IEX_Camera_CenterOn(area, x, y)` | Moves the view; the engine clamps it to the area. | `CInfinity::SetViewPosition(int,int,uchar)` (verified, t1e) |
| `IEX_Camera_GetZoom(area)` → `zoom, enabled` | 1 = none, smaller = closer (world pixels per screen pixel). | `m_fZoom` +0x484, `m_bZoomEnabled` +0x48c |
| `IEX_Camera_SetZoom(area, zoom)` | Clamped to the limits, keeps the view centre; ignored when zoom is disabled. | `CInfinity::SetZoom(float)` (verified, t1e) |
| `IEX_Camera_ZoomLimits([closest, farthest])` → `closest, farthest` | Engine-wide range (defaults 0.5 / 1.4; the game recomputes the closest one on area load). | globals `CInfinity::MAXZOOM_IN/OUT` (.data floats, verified) |

Primitives (C++): `IEX_CameraSetView(infinity, x, y)`, `IEX_CameraSetZoom(infinity, zoom)`, `IEX_CameraZoomLimits(...)`.

Keyboard and actions (same section, added for First Person movement):

| Function | Behavior | Engine |
|---|---|---|
| `IEX_ScancodeIsDown(scancode)` → bool | Physical key held (SDL scancode, layout independent: 26/4/22/7 = WASD on QWERTY = ZQSD on AZERTY). | `SDL_GetKeyboardState` |
| `IEX_ScancodeFromKey(keycode)` → scancode | Physical key that types `keycode` in the current layout. | `SDL_GetScancodeFromKey` |
| `EEex_Key_Hook_AfterEventsPoll(event)` | The event view now also has `event.key.repeat` and `event.key.keysym.scancode`. | SDL2 event layout |
| `IEX_SpriteSetAction(sprite, actionId, x, y)` | Makes a point action (ACTION.IDS: 23 MoveToPoint, 0 NoAction) the current action now, replacing the one in progress (queue kept). No voice, no destination marker. Built as a copy of the current `CAIAction` (shared CString buffers are left alone by `CString::operator=`). | `CGameSprite::SetCurrAction(CAIAction const&)` (verified, t1f) |

Network bridge (for external clients such as the Infinity 3D renderer), `src/core/lua_net.cpp` + `platform_net.h`:

| Function | Behavior |
|---|---|
| `IEX_NetListen(port)` → bool | Listens on 127.0.0.1:port only (never other interfaces). Once per session. |
| `IEX_NetPoll()` → `connected, {lines}` | Accepts one client, flushes queued output, returns the complete lines received (newline-delimited). Call every frame. |
| `IEX_NetSend(text)` → bool | Queues text for the client (non-blocking; the client is dropped past 8 MB of backlog). |

Sprite fields added: `m_nDirection` / `m_nNewDirection` (facing 0-15, 0 = south, 4 = west, 8 = north, 12 = east).

Skip Intro Movies (`src/core/startup_movies.cpp`, no Lua side): the movies the start screen plays when the game starts (logo, then the intro / blackpit / SoD intro of the SoD start menu) are skipped; the main menu shows at once. Movies played later (new game intro, cutscenes, resting, the Movies screen) still play. Off by default.

| Switch | Behavior | Engine |
|---|---|---|
| Baldur.lua `SetPrivateProfileString('IEX','Skip Intro Movies','1')` | Default 0. Read with `BGGetPrivateProfileInt` when the start screen asks for the movies. | call-site hooks on `CBaldurProjector::PlayMovie(CResRef const&)` (Win 0x14bce0) and `PlayMovieNext` (Win 0x14c1d0) inside `CScreenStart::TimerAsynchronousUpdate()` only (1 + 3 sites, both platforms; verified_intro) |
| Environment variable `IEX_SKIP_INTRO=1` | Same, for test runners (Baldur.lua untouched). | |

The engine's own Baldur.lua `'Program Options','Disable Movies'` (`CBaldurChitin`+0x17c4 on Windows, tested first by `PlayMovie`) turns off every movie, startup and story ones alike; it works without IEX (EEex runs).

## 14. Spell lists and menu templates (Bubb's Spell Menu Extended, after 0.2.0)

Lua side `lua/EEex_Spells.lua`, `lua/EEex_MenuUI.lua`, `lua/EEex_Listeners.lua`; engine records in
`engine/methods.txt`, hooks in `src/core/event_hooks.cpp`, helpers in `src/core/lua_scripting.cpp`.

| Function / event | Behavior | Engine |
|---|---|---|
| `sprite:GetQuickButtons(kind, 0)` / `sprite:GetInternalButtonList()` → `CGameButtonList` | New list of `CButtonData` (kind 2 spells, 4 innates); iterate with `EEex_Utility_IterateCPtrList`, free with `EEex_Utility_FreeCPtrList`. | `CGameSprite::GetQuickButtons(ushort,uchar)`, `GetInternalButtonList()` |
| `sprite:ReadySpell(buttonData, 0/1)` / `sprite:ReadyOffInternalList(buttonData, 0)` | Readies the spell of a button (cursor targeting), struct passed by value. | `ReadySpell(CButtonData,uchar)`, `ReadyOffInternalList(CButtonData,uchar)` |
| `EEex_CInfButtonArray.SetQuickSlot(buttonData, slot, kind)` | Puts a button in quick slot `slot` (kind 1 weapon, 2 spell, 3 item). | static `CInfButtonArray::SetQuickSlot` |
| `EEex_Utility_FreeCPtrList(list)` | Deletes the records, empties and deletes the list. | engine `operator delete`, `CPtrList::RemoveAll` |
| `CButtonData` / `CAbilityId` fields | `m_icon m_name m_launcherIcon m_launcherName m_count m_abilityId{m_itemType m_itemNum m_abilityNum m_res m_targetType m_targetCount m_toolTip} m_bDisabled m_bDisplayCount`; scratch records start with the engine defaults. | `GetQuickButtons` record writes |
| `EEex_Sprite_AddQuickListCountsResetListener(fn(sprite))` | All memorized spells castable again (rest). | after `CGameSprite::SetAllSpellsMemorized` |
| `EEex_Sprite_AddQuickListNotifyRemovedListener(fn(sprite, resref))` | A spell left the creature's lists. | after `CGameSprite::RemoveSpellFromQuickList` |
| `EEex_Sprite_AddSpellDisableStateChangedListener(fn(sprite))` | Disabled spell types (op 145) or buttons (op 144) of the active stats changed after effects were evaluated. | `OpcodeListsResolved` + compare |
| `EEex_GameState_AddDestroyedListener(fn())` | Game session destroyed. | after `CInfGame::DestroyGame` |
| `EEex_Menu_AddWindowSizeChangedListener(fn(w, h))` | UI size changed; also once at game state init. | after `CChitin::OnResizeWindow` |
| `EEex_Once(key, fn)` | Runs `fn` once per session per key. | Lua |
| `EEex_PlayerCastResrefNoDec(resref)` | Selected creature readies the spell from a scratch button (approximation: the engine's own decrement rule applies). | `ReadySpell` |
| `EEex_Menu_StoreTemplateInstance(menu, template, id, name)` | `nameToItem[name]` = that instance (Infinity_GetArea/SetArea by name). | nameToItem |
| `EEex_Menu_DestroyAllTemplates(menu)`, `EEex_Menu_DestroyInjectedTemplate(menu, template, id)` | Unlinks instances; frees them one call later (never the captured item). | engine `free` |
| `EEex_Menu_CreateTemplateFromCopy(menu, template, item)` | New template (kind 11 item, prototype = copy of `item`) usable by `EEex_Menu_InjectTemplateInstance`. | `uiCreateFromTemplate` layout |
| `EEex_UDToLightUD(obj)`, `EngineGlobals.capture.item` | Light userdata of an object; item under the mouse capture. | UI capture struct |
| `item.button.portrait`, `item.button.actionBar` | `.menu` button portrait / actionBar values (nil when absent). | `drawItem` reads |
| `EEex_DerivedStats_DisabledButtonType`, `stats.m_disabledButtons`, `stats.m_disabledSpellTypes` | Opcode 144 indexes (CheckActivation mapping), op 145 types. | `CDerivedStats` |
| `object:isSprite()`, `sprite:getClass()`, `game:SetState(state, 0)`, `game:SetIconIndex(i)`, `CButtonType.*` | as EEex. | `CInfGame::SetState`; icon fields |
| `EEex_Options_Set(id, value)`, `EEex_Options_Open()`, `EEex_Options_Close()` | Set an option (nil = default); open/close the options menu (no IEX options screen yet). | Lua |
| `EEex.RegisterSlicedRect`, `EEex.DrawSlicedRect` | Definitions kept, drawing not supported yet (gap). | - |

`m_pEngineWorld:TogglePauseGame(visual, message, playerId, log, hostUnpause)` is a native record with the full C++
signature (the engine's tolua function takes one boolean); on IEX objects native records are now looked up before the
engine's tolua functions. Embedded lists (`m_group.m_memberList`) also read as their CPtrList (`m_nCount`,
`m_pNodeHead.data`).

Action bar listeners (`EEex_Actionbar_AddListener`) now run only once the game state is initialized: the engine sets
bar states during startup, before the UI globals (`e`, `worldScreen`) exist. `EEex_Sprite_GetActiveStats` follows
the engine rule (`m_useDerivedStats` ? `m_derivedStats` : `m_tempStats`).

Tested 2026-10-29 (Windows `win-spell`, save `Sauvegarde-Rapide-2`; Linux `linux-spell`, save `Chapter 1 Start`;
IEX + Bubb's Spell Menu Extended #0 + SadoEE #23): the Cast Spell button opens the menu with Imoen's 10 memorized
spells (icon, slot, text and action instances, the 6 portrait templates copied from RIGHT_SIDEBAR), the game pauses
and unpauses with it, a spell readies the targeting cursor and closes the menu, reopening works, no Lua error,
no missing EEex name. Not exercised at runtime: CountsReset (rest), SpellDisableStateChanged (opcode 144/145),
NotifyRemoved (forgetting a spell), the quick spell configuration mode and the options screens.
Crash found while testing (most likely cause, fixed): `B3Spell_GetTextWidthHeight` scales its point size by
`cVideo.pCurrentMode.nHeight / CVidMode.SCREENHEIGHT`; a stand-in UI height gave 1 where the engine computes 0, and
`Infinity_GetContentHeight` crashed (dump 0011, `Baldur.exe+0x447846`, font measure). The real window size fields are
now described.

## 15. Fog of war: unlimited viewers (party vision, after 0.2.1)

Behaviour (on by default, Windows and Linux 2.7.3): every viewer the engine puts on an area's visibility map clears
fog of war and sees creatures, whatever their number: party members (big-party mods such as SadoEE #40 / PSXP7, up
to 32 and more), clairvoyance objects (`CGameArea::AddClairvoyanceObject`, id 0x7ffffffe, one entry per effect), and
anything else that goes through `CVisibilityMap::AddCharacter`. No hard cap: memory is a tile list per viewer
position and a counter per tile, tested with 17 party members.

The engine alone keeps 15 viewer ids per map and an 8-bit viewer mask per tile, so viewer slots 8-14 reveal nothing
(mask truncated to 0), viewers past the 15th are not on the map at all (no fog clearing, no "seen" checks in
`CGameSprite::CheckIfVisible`), and `CGameSprite::RemoveFromArea` lowers the area's party count (area +0x201) only
for viewers on the map, so with 16+ members areas never unload and the 12 area slots fill up.

| Feature flag / function | Behavior |
|---|---|
| `IEX_Features.partyVision` | `true` when the hooks are installed. Mods test it to skip their own visibility patches (SadoEE #40 does). `false` when a site was already patched by something else (IEX then changes nothing and logs it), or with the environment variable `IEX_NO_PARTY_VISION=1`. |
| `IEX_VisionInfo([map])` → table or list | Counters of one visibility map (`map` = CGameArea + 0xbb0) or of every map IEX knows: `viewers`, `tableSlots` (of the engine's 15), `overflow` (viewers past them), `detached`, `stamps`, `visibleTiles`, `captures`, `width`, `height`. |
| `IEX_VisionViewer(map, id)` → `onMap, slot, stamps, tiles` | `slot` 0-14 = engine table slot, -1 = IEX overflow viewer. `false` if `id` never was a viewer there. |
| `IEX_VisionTile(map, x, y)` → `value, viewers` | Tile under area pixel (x, y): engine u16 (bit 15 explored, bits 0-14 visible) and the number of viewer stamps that see it. |
| `IEX_VisionCheck()` → `mismatches, maps` | Tiles whose visible bits disagree with the viewer counts (0 expected). |

How (all from our analysis of both binaries, see `E:/Dev/IEX-data/engine/win/verified_vision.json`):

- Every reader of the tile array tests `tile & VISIBILITY_MASK` (0x7fff) or uses `CVisibilityMap::GetSubTileCode`
  (same mask): creature, door, container, projectile and VEF renders, `CGameArea::CheckLOS`, `CheckWalkable`, nearest
  door / transition searches, spawning, `CInfGame::ShowCreatureTooltips`, `CGameArea::AIUpdate`, fog and minimap
  (`CInfinity::RenderFog`, `RenderEdgeFade`, `CScreenMap::RenderFogOfWar` through `GetTileCode`). None reads a
  per-viewer bit, so IEX owns bits 0-14: bit 0 is set while at least one viewer sees the tile.
- The writers are `CVisibilityMap::AddCharacter` (Win 0x255b40, Lin 0x2c3c70), `RemoveCharacter` (0x256aa0 /
  0x2c1bc0), `UpDate` (0x257330 / 0x2c3f60) and, through them, `PrivateAddCharacter` (0x2568c0 / 0x2c3a70) ->
  `TraverseTree` -> `ClimbWall`. `IsCharacterIdOnMap` (0x256780 / 0x2c0a90) answers "is this id a viewer".
  These four are replaced (jmp at the function entry, after checking the game's own first 8 bytes):
  - Add: the viewer is registered (first free engine slot, else IEX overflow), then the engine's own
    `PrivateAddCharacter` runs on a scratch tile array; the tiles it marks become the viewer's stamp, the explored
    bit is set on exactly those tiles, and each tile's viewer count goes up.
  - Remove / UpDate: the engine's clear box (range + 1 tiles around the old position) is applied to that viewer's
    stamps only, so a viewer never clears tiles another one sees. `removeId` unregisters; a freed engine slot is
    given to the oldest overflow viewer.
  - IsCharacterIdOnMap: true for every registered viewer, so `RemoveFromArea` (and `AIUpdateWalk`, `JumpToPoint`,
    death / resurrection / petrification effects, multiplayer `CMessageVisibilityMapMove`) treat all of them the
    same way: area party counts go back to 0 and areas unload as with 6 members.
- `CGameSprite::CheckIfVisible` (Win 0x34dc30, 9 call sites; Lin 0x463790, 8 calls + 1 tail jump) loops over the 15
  table slots only. Its call sites are hooked: when the creature was not seen, it runs again with the overflow
  viewers swapped into the table 15 at a time (the table is restored after), so the engine's own LOS test, "seen"
  flags and trigger message are used for every viewer.
- `CVisibilityMap::Init` / `Uninit` call sites (area load / clear) reset IEX's state for that map.
- Coexistence: the older Lua stopgaps (`psxp7_fog_hotfix.lua` patches bytes inside AddCharacter / RemoveCharacter /
  UpDate, now never reached; `psxp7_area_hotfix.lua` patches the `je` after the `IsCharacterIdOnMap` call in
  RemoveFromArea) can still run without harm, but are not needed.

Limits: a viewer that the engine never adds is not a viewer (vanilla rule: `AddToArea` adds living portrait members
only). The table swap means `GetCharacterId(i)` read by other code during `CheckIfVisible` sees the batch.

Tests 2026-10-29 (test copies only, never saved):
- Windows EET 2.7.3 + SadoEE #40, 17-member save (BG3800): 17 viewers = 15 engine slots + 2 IEX overflow,
  `IEX_VisionCheck` 0. Each member alone, jumped next to a creature far (> 1100 px) from the rest: 220-225 of the
  225 tiles around it visible (0 before), 430-484 tiles per viewer, creature "seen" countdown 0 -> 6..8 for every
  member including slots 8-14 and the 2 overflow viewers (two rounds, BG3800 and BG3100).
- 40 scripted `LeaveAreaLUA` transitions of the 17 members: 1-2 of the 12 area slots used at every step (old areas
  unload), vision check 0 at every step, no crash over 14 minutes.
- Normal parties: Windows `Chapter 2 Start` (4 members) and Linux BG2EE `Chapter 1 Start` (2 members): all viewers in
  engine slots, check 0, fog cleared and creatures seen (the creature starts its dialogue on sight).

Area party count (CGameArea + 0x201) after a load, 2026-10-29: loading a save made in an interior (BOT save in
BG4806, Nashkel inn) also loads its master area BG4800 with the count at 255. That is the engine's own sentinel,
not an underflow: `CGameArea::Unmarshal` (and `AIUpdate` while a game counter at +0x95b8 is set) stores 0xff =
"loaded, nobody counted yet"; the first `AddToArea` turns it into 1; every decrement (RemoveFromArea,
ClearCharacterSlot, CMessageVisibilityMapMove) keeps the old value when `count - 1 >= 0xfe`, so the count never
wraps. Same 255 with IEX party vision off (`IEX_NO_PARTY_VISION=1`). Door test BG4806 <-> BG4800, 6 transitions,
17 members: with IEX the counts are 17 / 0 at every step; with party vision off they leak by 2 per transition
(BG4800 21, BG4806 23 after 6). IEX hooks the IsCharacterIdOnMap call of RemoveFromArea (Win 0x36a4d0, Lin
0x4a9044) only to log when a viewer leaves an area whose count is already 0 or 255.

## 16. Native hook points (SadoEE engine patches, Windows + Linux, after 0.2.2)

IEX has no EEex asm / JIT API (removed in f91b019, not coming back). Mods that patch the engine in Windows x64
code therefore never install those patches under IEX: on Windows the asm calls reach the missing-API stand-ins
(IEX_Missing.lua), on Linux the mods' byte checks against Windows addresses fail first. IEX reproduces each
decision point as a portable C++ hook (`src/core/native_hooks.cpp`, `lua/IEX_NativeHooks.lua`), resolved per build
from the engine description; evidence in `E:/Dev/IEX-data/engine/win/verified_native.json`. Hooks are installed
on demand (never at startup), after checking the site still holds the game's own code.

| Hook point | Engine site (Linux / Windows 2.7.3) | Lua contract |
|---|---|---|
| `keepAmmo` | `CGameSprite::Swing` (L 0x44d800): its only call of `CItem::SetUsageCount(item, ability, (u16)(count - 1))` after `count = GetUsageCount(item, ability)`, L 0x44e28d / W 0x3b902a, taken when the attacker byte +0x4b90 (W +0x4ba8) is set and the ability has charges (+0x22): the charge / ammo a shot uses up. The attacker is in r14 (L) / rbx (W); a 2-instruction thunk passes it as an extra argument. | `fn(sprite, item) -> keep`: any `true` makes it `SetUsageCount(item, ability, count)`. |
| `groundMoveClick` | `CGameArea::OnActionButtonClickGround(CPoint const&)` (L 0x186d70 / W 0x1868e0) starts with a switch on `CInfGame::m_nState` (+0x4030), 0 = move the selection to the point. Its 6 callers per build are redirected (L calls 0x188701 0x18897c 0x1890f8 0x3a176f, tail jumps 0x22252e 0x2e5796; W calls 0x187654 0x187916 0x18846d 0x2f4607, tail jumps 0x1ece33 0x285270); the hook reads the state, then calls the original. Lua's `area:OnActionButtonClickGround(pt)` calls the function directly and is not reported. | `fn(area, x, y)` before a move click is handled. |
| `deathDrop` | `CGameEffectDeath::ApplyEffect` (L 0x1f0020): its call of `CGameSprite::DropInventory` (L 0x1f2325 / W 0x1b0452). | `fn(sprite) -> keep`: any `true` skips the drop (inventory stays on the corpse). |
| `respecGear` (byte) | `CScreenCreateChar::CompleteCharacterSkills`: calls of `CRuleTables::GetStartingGold(sprite)` (L 0x342721 / W 0x2b386b, result stored to sprite +0x574) and `GetStartWeapon(class)` (L 0x34277c / W 0x2b38c4). | `IEX_NativeHook_Install('respecGear', flagAddress)`: while the byte is not 0 the sprite keeps its gold and gets no starting weapon (empty resref: the weapon block is skipped on both builds). |
| `campMarker` (byte) | `CScreenWorldMap::DrawMap`: call of `GetMarkerPosition(CPoint&)` (L 0x3af54e / W 0x2fe8e5). | `IEX_NativeHook_Install('campMarker', flagAddress)`: while the byte is not 0 the party marker is moved to (-20000, -20000) (not drawn). |
| `campSameArea` | `CScreenWorldMap::OnAreaMouseClick`: clicked area == current area. L: the `StopWorldMap(this, 0)` call reached only on that path (0x3b3d24). W: the `je` at 0x301f1d (after `cmp r8d, r12d`) is retargeted to a fixed thunk that calls the hook then the engine's close block 0x302620 (the call there is shared with a post-travel path). | `fn()` before the map closes. |

Engine functions callable from Lua (integer / pointer arguments, one integer result: the shape of the call stubs
mods used to build in machine code): `IEX_Eng_RemoveAbilities(screen, sprite, newClass, flag)`,
`IEX_Eng_SwapItemPersonal(game, portrait, slot, CItem** hand, uint* err, maxCount, uchar, sprite)`,
`IEX_Eng_AddItemToStore(game, CResRef*, CItem*, uint* err)`, `IEX_Eng_SwapItemPersonalInventory(game, portrait,
CItem**, slot, uint* err, max, uchar, int, int)`, `IEX_Eng_AddDisposableItem(game, CItem*)`,
`IEX_Eng_DemandServerStore(game, CResRef*, int)`, `IEX_Eng_GetServerStore(game, CResRef*)`,
`IEX_Eng_ReleaseServerStore(game, CResRef*)`, `IEX_Eng_TakeItemFromStore(game, CResRef* bag, CResRef* item, n)`,
`IEX_Eng_ProcessEffectList(sprite)` (sets the re-evaluation flag, L +0x4b8c / W +0x4ba4, then
`ProcessEffectList(1)`, as the engine does after an inventory change).

| Function / flag | Behavior |
|---|---|
| `IEX_NativeHook_AddListener(name, fn)` → `true` / `false, reason` | Installs the hook on first use, then adds `fn` (keepAmmo, groundMoveClick, deathDrop, campSameArea). Errors in listeners are caught and logged once per message. |
| `IEX_NativeHook_Install(name [, flagAddress])`, `IEX_NativeHook_Installed(name)`, `IEX_NativeHook_Sites(name)` | Install without a listener (byte-driven hooks take the byte address) / state / number of patched sites. |
| `IEX_Features.nativeHooks` = `{ keepAmmo, groundMoveClick, deathDrop, respecGear, campMarker, campSameArea, groundContainer, smallFootprint, containerMarker, lastingModes, findTrapsButton, stealthReveals, spellSlots99, spellLists }` | Set at IEX start (before any `M_*.lua`): the hook point exists on this build. |
| `IEX_Features.platform` | `'win64'` / `'linux64'`. |
| `IEX_Features.sadoAmmo`, `sadoAttackMove`, `sadoKeepGear`, `sadoRespec`, `sadoCamp`, `sadoStash` | `true` once IEX runs that SadoEE component natively (set at `GameStateInitialized`; `sadoStash` Linux only, see below). |

### SadoEE bridge (no change to SadoEE)

At `GameStateInitialized` (every `M_*.lua` has run), when no EEex-style asm API exists, IEX connects each installed
component and sets the state its own Lua checks:

| Component (file) | What the mod's asm did | IEX | Mod state set |
|---|---|---|---|
| #24 endless ammo (`qol/M_SQAMMO.lua`) | Swing: `SQAmmo_Hook_Keep(sprite, item)` → count + 1 | `keepAmmo` → `SQAmmo_Hook_Keep` | `SQAmmo.status = 'hooked'` |
| #28 attack-move (`qol/M_SQATKM.lua`) | state-0 `je move` → `SQAttackMove_Cancel()` first | `groundMoveClick` → `SQAttackMove_Cancel` | `SQAtkM.status = 'patched'` |
| #30 keep gear (`qol/M_SQKEEP.lua`) | death `DropInventory` skipped for EA 2 | `deathDrop` → `sprite.m_typeAI.m_EnemyAlly == 2` | `SQKeep.status = 'patched'` |
| #14 respec (`camp/M_SQRESP.lua`) | skills step skips gold + weapon while `SQRespec.flag`; JIT'd `SQRespec_Eng_RemoveAbilities` / `_SwapItem` | `respecGear` on `SQRespec.flag` (allocated if missing); `SQRespec_Eng_*` = `IEX_Eng_RemoveAbilities` / `IEX_Eng_SwapItemPersonal` | `SQRespec.status = 'patched'` (required by `SQRespec_Begin`) |
| #10 camp (`camp/M_SQCAMP.lua`) | marker hidden while `SQCamp.flag`; same-area click → `SQCamp_SameAreaClicked()` | `campMarker` on `SQCamp.flag`, `campSameArea` → `SQCamp_SameAreaClicked` | `SQCamp.patchStatus = 'patched'` |
| #0-7 Party Stash (`M_PSTASH.lua`) | no engine patch: 7 Windows call stubs built byte by byte (`EEex_AllocNear` + `EEex_ExposeToLua`, still provided) | Windows: the mod's own stubs run. Linux: `PStash_Eng_*` = the `IEX_Eng_*` functions above | Linux: `PStash.ready = true`, `PStash.build = '2.7.3.0'`, `PStash.scratch` (64 bytes) |
| #31 chests in the ground bar (`qol/M_SQCHST.lua`) | `cmp ax, 4 / jne` after `GetContainerType` in UpdateVisibleGroundItems → `SQChest_Allowed(c, sprite)` | `groundContainer` → `SQChest_Allowed` | `SQChest.status = 'patched'` |
| #21 valuable containers (`qol/M_SQCONT.lua`) | permanent outline color from `SQCont.colorPtr` when `m_drawPoly == 401` | `containerMarker(SQCont.colorPtr, 401)` (allocated + filled with `SQCont.COLOR` if missing) | `SQCont.polyHooked = true` |
| #25 / #26 small footprint (`qol/M_SQFOOT.lua`) | CSearchBitmap Add / Remove / SnapshotRemove entry stubs | `smallFootprint(SQFoot.MODE)` | `SQFoot.status = 'patched, mode N'` |
| #27 lasting modes (`qol/M_SQMODE.lua`) | ~25 sites (patches 1-8 of the file) | `lastingModes`, `stealthReveals`, `findTrapsButton` → `SQMode_ToggleTraps(sprite)` (with #20 `SQTrap` only); Linux: `SQMode_OnStartedAction` reads `sprite.m_nModalState` (the file's local `MODAL_OFF = 0x3A29` is the Windows offset) | `SQMode.status`, `SQMode.stealthStatus` as the file sets them |
| #11 camp merchant (`M_PSXGM.lua`) | Windows stubs of `_wfopen`, `fread`, `fseek`, `fclose`, `dimmResolveFileName`, `CStore::AddItem`, `CStore::CompressItems` (`PStash.buildStub`) | Windows: the mod's own stubs. Linux: `PStash_Eng_GM_*` = `IEX_File_WOpen / Read / Seek / Close` (UTF-16 path → UTF-8 `fopen`), `IEX_Eng_ResolveFileName`, `IEX_Eng_StoreAddItem`, `IEX_Eng_StoreCompressItems` | Linux: `PSXGM.fileReady = true` |

New hook points (`src/core/native_hooks_sado.cpp`, evidence `IEX-data/engine/win/verified_sado2.json`):

| Hook point | Engine sites | Contract |
|---|---|---|
| `groundContainer` | UpdateVisibleGroundItems' call of `CInfGame::GetContainerType` (L 0x46dfea / W 0x386629), through a 3-instruction thunk adding the sprite (L `[rbp-0xa0]`, W r15) and the object (L `[rbp-0x88]`, W `[rsp+0x50]`) | `fn(container, sprite) -> list`: true makes a non-pile container count as a pile (its items are listed). |
| `smallFootprint` (mode) | every call of `CSearchBitmap::AddObject` (L 28 / W 29), `RemoveObject` (19 / 22), `SnapshotRemoveObject` (3 / 3) | bumpable creature (last argument != 0): size capped at 1 (mode 1) or nothing stamped (mode 0). Install before an area loads. |
| `containerMarker` (colorAddress, marker) | modules.cpp OutlinePoly hook in `CGameContainer::Render` | the red permanent outline of a container with `m_drawPoly == marker` takes the u32 color at colorAddress. |
| `lastingModes` | SetModalState(0) calls: SetCurrAction, action-bar clicks, OnRButtonPressed, spell hotkey, ground item pickup (L 11 / W 14 calls: Linux has none in 3 button cases); CheckModal stealth failure path → jmp to the end (L 0x42f876 + 0x42ff59 / W 0x38dbc8); opcode 363 `je` → `jmp` (L 0x1bc56f / W 0x1ba85f); CheckModal FeedBack 0x39 / 0x36 calls | permanent once installed (no listener). |
| `findTrapsButton` | Find Traps case of `CInfButtonArray::OnLButtonPressed` (L 0x2d5e85 / W 0x264916) | `fn(sprite) -> handled`: true skips the engine's toggle (selection 100, buttons updated). |
| `stealthReveals` | CGameEffectForceVisible::ApplyEffect vtable slot; reveal calls in PlayerDialog / UseContainer / OnGroundButtonClick (W 4 calls; L 2 calls of the ForceVisible core, 1 ForceVisible call, UseContainer's inlined test NOPed); hostile-cast reveals (W 4 ForceVisible + 4 RemoveSanctuary calls; L ForceSpell's 2 calls, Spell's two and UseItem's inlined `& 0x600` tests through a thunk); target recorded by hooks on the one call of `Spell`, `UseItem`, `ForceSpell` | stealth "already hidden" flag (L +0x4e38 / W +0x4e50) cleared when an opcode 136 effect applies to a sprite in stealth; no reveal for talk / container / ground item; hostile casts reveal only when the target is not the caster nor an ally. |

Also added for these files: `CGameAIBase:virtual_GetVisibleTerrainTable()` and `CGameArea:CheckLOS(a, b, terrain, u8, i16)` (methods.txt), `cstring.m_pchData:get()`, `EEex_NewUD('CResRef')` (`:set` / `:get`), `CItem:Construct_Overload_Manual(resref, u1, u2, u3, wear, flags)` (`IEX_Eng_ConstructItem`), `EEex_Sprite_DisplayTextRef` (log line only).

Behaviour = what the mods intend. SadoEE ≤ v1.0.2's ammo asm saved rdx / r8 in the shadow slots its
`GenLuaCall` used for the Lua arguments, so `SetUsageCount` got a bogus ability index and changed nothing: no ammo
was ever used up, enemies and excluded arrows included (fixed in SadoEE's dev copy with `#MAKE_SHADOW_SPACE(72)`).
The native hook keeps party ammo only, as intended.

Not native yet:
- #40 big party (`M_PSXP7*.lua`). Windows: the file's own patches (EEex_Write* + EEex_AllocNear stubs, no JIT) run
  under IEX unchanged (earlier session; not retested here). Linux scope (2026-10-29): the file moves `CInfGame::m_characters` / `m_charactersPortrait`
  (+0x6600 / +0x6618, same offsets on both builds, `m_nCharacters` +0x6630) to larger arrays by redirecting every
  instruction that addresses them (414 on Windows, generated from the Windows binary) and raising the reviewed
  `cmp x, 6` bounds. The Linux binary has about 700 disp32 references into 0x6600..0x662f (Windows: 450 for 414 real
  sites), and GCC unrolls many of the 6-member loops into 6 fixed-offset accesses: redirecting them cannot add a 7th
  iteration. A Linux version is therefore a C++ party-size module, not a site list: replacement functions for the
  party walkers the file's bounds list names (AddCharacterToParty, GetCharacterPortraitNum, the slot / portrait
  lookups, save / load of the party, selection, DestroyGame), each checked against its Linux body, plus the array
  move for the non-unrolled accesses. Not started; IEX's party vision part is already native
  (`IEX_Features.partyVision`).

**Linux memory probes**: SadoEE's `M_SQ0BLD.lua` (and Party Stash, camp merchant) read Windows code addresses in
`pcall` to find the build. On Linux these are unmapped: `EEex_Read*` / `EEex_Write*` / `EEex_ReadString` check the
address range against `/proc/self/maps` (cached, re-read on a miss) and raise a Lua error instead of crashing.

**What SadoEE could do (optional)**: test `IEX_Features.nativeHooks.<name>` and use `IEX_NativeHook_AddListener`
directly. Attack-move's press-and-drag facing (`dragFacingSupported()`) checks Windows bytes through `SQ_Addr` and
errors on Linux (`SQ_Addr` returns `nil`): the drag does nothing there, although the fields it writes
(`CGameArea` +0x4d0 / +0x4d4 / +0x4d8, `CInfGame` +0x4041) have the same offsets on Linux.
## 17. Native hooks for EEex x64-hook mods (StickLuaFunctions, after 0.2.2)

IEX has no assembler / JIT and never will. A mod that patches the engine through EEex's hook API
(`EEex_HookBeforeRestoreWithLabels(address, ...)`, `EEex_HookAfterCallWithLabels`, `EEex_HookConditionalJump*`, ...)
gets the *behaviour* of each patch from IEX's own C++ hooks instead (`src/core/native_stick.cpp`, call-site hooks
and register-context call-site hooks `src/core/reg_hook.h`, sites in `IEX-data/engine/win/verified_stick.json`),
on Windows and Linux alike. The mod's Lua runs unchanged:

- `lua/IEX_HookRequests.lua` defines the hook functions StickLuaFunctions calls as stand-ins that assemble nothing: each passes the patch
  address the mod names (its EEex 2.7 x64 address, used only as a key) and the Lua function its `EEex_GenLuaCall`
  names to `IEX_NativeHookRequest(address, name)`, which switches the matching native behaviour on. Unknown
  requests are logged once (`[hooks] ... no native IEX hook for this patch, ignored`) and do nothing.
  `EEex_GenLuaCall` returns a text carrying the name, `EEex_FlattenTable` flattens texts, `EEex_LuaCallReturnType`
  and `EEex_HookIntegrityWatchdogRegister` are plain tables.
- `EEex_Label('Hook-CAIGroup::IsPartyLeader()-Override')` (StickLuaFunctions' 2.6 / 2.7 test) gives 0x14011AC1A on
  linux64 too (`IEX_AsmAbsoluteLabels`); on win64 the engine address, its bytes checked (`IEX_AsmEngineLabels`), both set by lua/IEX_HookRequests.lua.
  `EEex_Label` reads these two tables after the engine symbols (`IEX_Platform`, `IEX_ImageBase` are defined).
- API the mod's callbacks need, now as EEex: `EEex_Resource_Fetch(res, 'ITM'|'SPL')` returns the resource object
  (`pHeader`, `pAbilities`, `pEffects`; header fields also read through it); the nodes of typed lists
  (`sprite.m_equipedEffectList.m_pNodeHead`, list fields such as `m_cCriticalEntryList`) are typed: `node.data` is
  the element object, `node.pNext` the next typed node; `sprite.m_persistantEffects` (W +0x4a50, L +0x4a38).
- `IEX_Features.stickHooks` = number of behaviours installed on the running build (16 of 24 on both 2.7.3 builds).
- Callbacks get clean integers: ids, the d20 roll (0..19), signed to-hit / damage totals, the attack index
  (frame type - 9). Under EEex several of these arrive with garbage upper bits or as unsigned 16-bit values (seen
  in the probe: rolls as 64-bit garbage, a -1 to-hit total as 65535). Callback values are written back the way
  EEex's hook writes them (16-bit totals, low byte of school / frame type). A Lua error keeps the engine value.

| Mod request (address) | Lua callback | When IEX calls it | Effect of the result |
|---|---|---|---|
| 0x14039E115 HitRoll | `(attackerId, targetId, roll0to19)` | `CGameSprite::Hit`, right after the d20 roll | new roll (critical check uses it) |
| 0x14039E634 HitMod | `(attackerId, targetId, total)` | Hit, right-hand attacks: total so far (roll, AC vs damage type, hit bonus, opportunity, berserk, right-hand bonus) | new total |
| 0x14039EBC3 CriticalHitMod | `(attackerId, targetId, threshold)` | Hit, `CDerivedStats::GetCriticalValue(...,0)` | new threshold (critical when roll+1 >= 20 - it) |
| 0x14039EC58 CriticalHit | - | a critical stopped by a helmet | critical flag 2 instead of 0 (Damage sees it) |
| 0x1403912B2 CriticalHitMultiplier | `(attackerId, targetId, multiplier)` | Damage of a critical (multiplier 2, or 1 for flag 2) | the damage is multiplied by the result |
| 0x14039EEEF AttackResult | `(hit 0/1)` | end of Hit's normal to-hit path | - |
| 0x140390530 AttackDamMod | `(attackerId, targetId, damage)` | Damage: dice roll + damage bonus | new value (hand bonus added after) |
| 0x14039DE77 HideInPlainSight | `(spriteId)` -> boolean | Hide, an enemy sees the hider | true: hiding goes on as unseen; false: the engine's rule (Shadowdancer only) |
| 0x1403B8A79 AttackCancel | `(attackerId, targetId)` -> boolean | each Swing tick, when the attack frame type is read | true: frame type 6 (no attack) |
| 0x1403B9B87 AttackIndex | `(attackerId, targetId, frameType - 9)` | same tick, frames that lead to the engine's attack-number code | (the callback may set `m_leftAttack`) |
| 0x140263641 / 0x140264DEF Button / RButton | `(buttonIndex)` | `CInfButtonArray::OnL/RButtonPressed`, index 0..12, before the engine's checks | - |
| 0x14024EF66 / 0x1401FB552 SaveDCMod | `(casterId, effectAddress)` | `CSpell` / `CItem::GetAbilityEffect`: caster's specialization -> school | school number (2 more to the save penalty when it is the effect's school) |
| 0x1401CD85B SaveMod | `(targetId, effectAddress)` | `CGameEffect::CheckSave`: target's school | school number (+2 to the save on a match) |
| 0x1402B92FA CharGenClassDone | `(spriteId)` | character creation, after `CompleteCharacterClass` | - |

Not provided yet (requests are accepted, logged as NOT AVAILABLE, and do nothing): the backstab decision chain
(0x140390C45 / 0x140390CF0 / 0x140390D12 / 0x140390D88 / 0x140390DD4 / 0x140390DE3: the engine's backstab checks
in Damage are plain compares without a call to hook; plan: decide in a Damage call-site context and steer the
engine's inputs, then call the success callback from the multiplier's `max()` call), the proficiency maximum of the
character creation panels (0x1402C7C41 / 0x1402BE2B1, stack slots around `lua_pushnumber` /
`GetInactiveProficiency`), `HitStrMod` (StickLuaFunctions v0.11 does not register it). AttackCancel on linux64:
Swing inlines `GetAttackFrameType`, so frames for which the engine reads no pixel (frame > 10 or sequence > 100,
frame type 0 / 15) do not ask the callback (they never lead to the attack-number code either).
`EEex_Opcode_Hook_OnAfterSwingCheckedOp248` (StickLuaFunctions' melee listeners) is an EEex opcode hook IEX does not
call yet.

Test: `tools/stick/run.ps1 -Side eeex|iex` (Windows) and `tools/stick/run_linux.sh` (WSL): private game copy,
StickLuaFunctions installed by WeiDU, probe `tools/stick/probe` (listeners of the mod's own API, phases that force
hits / misses / cancels through them). Results 2026-10-29 in the commit message of this section.
## 18. Allied pass-through movement (BG Pathfinding Redux, native, after 0.2.2)

BG Pathfinding Redux (Zach Hopkins, MIT) makes allies (EA 2-30: party, familiars, allied summons) walk through one
another; walls, doors, neutrals and enemies keep blocking. Its runtime is Lua plus 24 x64 assembly hooks through
EEex's asm API, which IEX does not provide. IEX runs the mod's movement policy natively instead (Windows and Linux
2.7.3, `src/core/pathfinding.cpp`), and the mod's loader `override/M_BGREDX.lua` returns at once (IEX sets
`MRIP_DispatchLoaded` and `MRIP_CompatibilityStatus = {supported = true, provider = 'IEX native'}`).

| Setting / function | Behavior |
|---|---|
| Baldur.lua `[IEX] 'Pathfinding Redux'` | 1 on, 0 off. Default: on when `override/M_BGREDX.lua` exists (the mod is installed). IEX options, "Movement" tab. `IEX_PATHFINDING=0/1` overrides it (tests); `IEX_NO_PATHFINDING=1` installs no hook. |
| `bg-redux-movement.ini [Movement] OutOfCombatOnly` | The mod's own switch (and IEX options): allies block one another while any loaded area has a positive battle-song or damage counter (`CGameArea::CanSaveGame`'s combat test), and pass again after 3 s of game time without one. |
| Left Ctrl + Left Shift + F1 / F2 | As the mod: allied passage for the session / out-of-combat-only mode (saved). |
| `IEX_Features.pathfindingRedux` | `true` while the native policy is on. |
| `IEX_PathfindingRedux([{enabled, combatOnly, reset}])` → table | `installed`, `enabled`, `combatOnly`, `combatBlocked`, `modInstalled`, and statistics: `scopes` / `scopeCells` (movement calls with allies lifted, cells changed), `searches`, `snapshotSearches` / `snapshotCells`, `searchMs` / `maxSearchMs` (CPathSearch::FindPath time), `overheadMs` / `maxOverheadMs` (IEX's own time). |
| `IEX_PathfindingCheck(spritePtr)` → `mismatches, cells, first` | Test tool: cells of the sprite's area whose creature counts differ from the painted footprints (0 expected). |

How (engine knowledge from both binaries, `E:/Dev/IEX-data/engine/win/verified_path.json`): CSearchBitmap
(CGameArea + 0xa60) keeps per 16x12 cell bit 0 / bit 7 (non-creature obstruction) and two 3-bit creature counters
(bits 1-3, 4-6; AddObject / RemoveObject over a creature's footprint, modulo 8). For a normal-sized allied mover:

- `CGameSprite::AIUpdateWalk` and `CGameSprite::SetTarget(CSearchRequest*)` call sites: while the call runs, the other
  allies' footprints are subtracted from the live counters on the cells they account for completely (every painted
  creature covering the cell is the mover or an eligible ally and the counts match), then added back (modulo 8, so
  exact whatever the engine changed meanwhile). Covers the walk step, the moving-creature wait, the bump trigger,
  the destination check and the direct-line walkability test.
- The `CPathSearch::FindPath` call in `SearchThreadMain` (run by `CChitin::Update`, main thread): the same cells are
  cleared in the request's private snapshot (bitmap + 0x128), idempotent like the mod.

Not yet native (the mod's optional features): attack spacing, gentle settle, visual route preference, enemy
cooperation, overlap escape out of neutral / enemy footprints, the mod's F3-F6 keys and its diagnostic recording.

## 19. Object ids that never run out (after 0.3.1)

Behaviour (on by default, Windows and Linux 2.7.3, single player; `IEX_OBJECT_IDS=0` keeps the engine's ids): a long
session no longer runs out of game object ids. Engine bug (both builds): `CGameObjectArray` (id = slot << 16 | key)
never reuses a slot while the key is below 15000, and its i16 key (`m_nextObjectId`, also the limit `GetShare`
accepts) only grows. After ~30000 object creations since the last load (one AR0500 load is ~330) `Add` fails
("Too many objects!", id -1, slot -1 written before the table) or the key wraps negative. The next creature added to
an area then crashes `CGameArea::SortLists` (+0x24f reading object + 0x48 when `m_lVertSort` is empty, +0x26c
otherwise): it only skips stale ids (GetShare 2), not invalid ones (3). Seen on the BOT, 2026-11-01: 10-member EET
party, world-map travel AR1000 -> AR0500 (`LeaveAreaLUA` -> `CInfGame::LoadArea` -> `SortLists`), after hours of play.

IEX (`src/core/object_ids.cpp`, through the `CGameObjectArray::Add` call-site hook of `event_hooks.cpp`): before each
Add a free slot (entry key -1) below `m_maxArrayIndex` goes into `m_deletedListHead` (rotating scan, 512 entries, all
of them when the table is nearly full) and `m_nextObjectId` gets IEX's key, cycling 2000..14999; after it
`m_nextObjectId` is pinned at 15000 (validity limit, below the engine's "critical" paths). The Windows statics
(`0x68f8f0`..`0x68f910`) are in `win64-*.iexd`, Linux has them in `.symtab`; `IEX.objid.mpFlag` = the CChitin
multiplayer byte Add tests. Lua: `IEX_Features.objectIdRecycling`, `IEX_ObjectIdInfo()` -> `{active, adds, reused,
wraps, nextKey, maxIndex, nextObjectId, deletedHead}`.

Test: `tools/objidtest/run.ps1` (private copy with the BOT's 10-member save; ClearActions + queued LeaveAreaLUA on
every member, AR1000 <-> AR0500). `-Config 'P10_POKE = 32600'` (table about to run out): `IEX_OBJECT_IDS=0` ->
access violation in SortLists on the first travel; default -> 6 travels fine. 6 plain travels: highest slot 3360
without, 2457 with. `P10_POKEKEY = 14800` exercises the key cycle. `run_linux.sh on` (WSL): on, 6 travels.

## 20. Class spell lists past the SPWI/SPPR slots (native switch `spellLists`, after 0.3.1)

Study and reverse engineering: `docs/SPELL_LIST_UNLIMITED.md`. Code: `src/core/spell_lists.cpp`, `lua/IEX_SpellLists.lua`.

Every call of `CRuleTables::GetMageSpell` / `GetPriestSpell` (3 + 6 call sites on Windows 2.7.3, 3 + 7 on Linux) and
`GetNumPriestSpells` (4 + 4) is redirected (call rel32 only; the getters stay intact, so `spellSlots99` works with the
switch on or off). For a list type / level: index below the engine's own bound (50, or 99 with `spellSlots99`) = the
engine's answer; index `base + k` = entry `k` of the IEX list; past the list = empty resref (ends the engine loops).
`GetNumPriestSpells` returns `min(SPELLS.2DA, base) + list size` while the list is not empty, and the priest calls
it bounds (`AddNewSpellsPriest`, `MakeDualClass`) put the list right after `min(SPELLS.2DA, base)`: a SPELLS.2DA
value below the bound keeps limiting the automatic priest spells. `MageSchoolSpellsAvailable` (specialist bonus
slot) scans engine slots and the list (register hook on its GetMageSpell call, build constants
`IEX.spellLists.schoolSite` / `IEX.spellLists.countedPriest.N`).

| Lua | |
|---|---|
| `IEX_SpellList_Add(type, level, resref)` -> `true` / `false` (already listed) | type 1 priest (levels 1-7), 2 wizard (1-9); turns the switch on |
| `IEX_SpellList_Remove(type, level, resref)`, `IEX_SpellList_Get(type, level)` -> `{resref...}`, `IEX_SpellList_Count(type, level)`, `IEX_SpellList_Clear([type [, level]])` | |
| `IEX_SpellLists_Load2DA([resref])` -> rows added | `IEXSPLST.2DA` by default, read at `GameStateInitialized` |
| `IEX_SpellLists_Status` | `'off'`, `'on'`, or why the switch did not install |

`IEXSPLST.2DA`: `2DA V1.0`, a default line, the header `TYPE LEVEL`, then one row per spell (`<resref> <type> <level>`,
type `1`/`PRIEST` or `2`/`WIZARD`/`MAGE`), in list order. WeiDU: `APPEND ~iexsplst.2da~ ~MYSPL01 2 3~`.
