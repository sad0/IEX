# Class spell lists past 99 per level (native switch `spellLists`)

Date: 2026-11-01. Branch `feature/spell-list-unlimited`. Builds on `spellSlots99` (`src/core/spell_slots.cpp`,
`weidu/SpellSlots`) and on a study of (WeiDU `ADD_SPELL`, CST, SFO).
Clean room: only `Baldur.exe` / `BaldursGateII` were read (IEX Ghidra projects, `tools/match/xrefs.py`, `pedis.py`,
`pegrep.py`, capstone), plus the game's own `UI.MENU`, `SPELLS.2DA`, `HIDESPL.2DA`.

## TL;DR

- Every class spell list of the engine is built by asking `CRuleTables::GetMageSpell / GetPriestSpell(level, index)`
  for index 0, 1, 2... The getters only `sprintf("SPWI%d%02d", level, index + 1)` behind `index > 49 -> ""`. No
  caller keeps a fixed buffer of list entries: the lists go to Lua tables keyed by resref, to the sprite's known-spell
  `CPtrList`, or are only scanned. So the **only** hard limits are the getters' bound and the 2-digit numbering.
- Callers end their loop in three ways: until the getter returns `""` (chargen / level-up lists), at
  `GetNumPriestSpells(level)` (SPELLS.2DA `PRIEST` row: priests' automatic spells, dual-class), or at a hard-coded
  50 (`MageSchoolSpellsAvailable`, and the dead `AutoPickMageSpells`).
- **Prototype (this branch):** native switch `spellLists`. Every call of the two getters and of
  `GetNumPriestSpells` goes through IEX (13 call sites Windows, 14 Linux; only the call rel32 changes). Index below
  the engine's bound = engine answer (so slots 01-50, or 01-99 with `spellSlots99`, are unchanged); index
  `base + k` = entry `k` of an IEX list (any resref); past the list = `""`. Lists: `IEXSPLST.2DA` rows
  (`<resref> <type> <level>`, mods APPEND) and `IEX_SpellList_*` Lua. `GetNumPriestSpells` answers
  `min(2DA, base) + list` (SPELLS.2DA keeps limiting the engine slots of the priests' automatic spells).
  `MageSchoolSpellsAvailable` (specialist bonus slot) also sees slots 51-99 and the list (2026-11-02).
- **Real cap with the switch:** the callers' `int` counters, i.e. ~2^31 entries per type and level. In practice
  memory and load time (each chargen list entry demands its SPL; priests' auto-learn is O(list x known spells)).
  The CRE known-spell count is a dword. The spell.ids limit (99 per level) stays for everything that is
  *numbered*: `Spell()` by number, `ADD_SPELL`, IDS names in scripts.
- Built Windows (MSVC) and Linux (WSL GCC) at parity. **Tested in-game 2026-11-02** (section 8): Windows all cases pass;
  Linux: hook install and chargen lists pass, priest auto-learn not driven there.

## 1. The getters (2.7.3)

| | Linux VA | Windows RVA | 2.6.6 Windows RVA |
|---|---|---|---|
| `CRuleTables::GetMageSpell(int level, int index) const` | 0x298cb0 | 0x241ec0 | 0x241c60 |
| `CRuleTables::GetPriestSpell(int, int) const` | 0x298b60 | 0x2453c0 | 0x245160 |
| `CRuleTables::GetNumPriestSpells(int level) const` | 0x298aa0 | 0x245260 | 0x245000 |
| `CRuleTables::GetNumMageSpells(int level) const` | 0x298bf0 | (no copy: no caller, removed by LTCG) | - |

- ABI. Linux: `CResRef GetMageSpell(this=rdi, level=esi, index=edx)`, the 8-byte CResRef in `rax`. Windows:
  `CResRef* GetMageSpell(this=rcx, CResRef* out=rdx, level=r8d, index=r9d)` (hidden return pointer). Body:
  `cmp index, 0x31; ja -> CResRef("")` (unsigned: a negative index is empty too), else
  `sprintf(buf[8], "SPWI%d%02d", level, index + 1)`. The getters never read `this`.
- Index 99 would format `SPWI<l>100` (9 bytes with the NUL) into the 8-byte buffer: `__sprintf_chk` aborts on Linux,
  a stack overwrite on Windows. So no bound byte above 0x62 is safe; `spellSlots99` uses exactly 0x62.
- `GetNum*Spells`: `sprintf("%d", level)` as column name, `C2DArray` lookup in SPELLS.2DA (rules + 0xd58) on row
  `MAGE` / `PRIEST`, `sscanf("%d")` -> `int`. Vanilla 50 everywhere.
- `CResRef("")` is 8 zero bytes (`CResRef::CResRef(char const*)` zeroes, then copies upper-cased).
- Format strings `SPWI%d%02d` / `SPPR%d%02d` are referenced once each, by the getters (both builds): the getters are
  never inlined.

## 2. Every caller

Found with `xrefs.py` (direct E8/E9 calls, RIP-relative refs, raw E8 scan outside known functions) on Linux and
Windows 2.7.3, and an E8 scan of `.text` on Windows 2.6.6. No indirect use: the getters' addresses appear nowhere in
data (Linux: only `.symtab`).

| Caller (Linux name) | Getter calls Linux / Win 2.7.3 | Loop bound | Where the entries go | Notes |
|---|---|---|---|---|
| `CScreenCreateChar::ResetSpellTables(CGameSprite*)` (Lin 0x34ef90, Win 0x2c2ca0) | mage 0x34f0bf / 0x2c2d45 + 0x2c30fd; priest 0x34f287 / 0x2c31a6 + 0x2c34d7 | **until the getter returns `""`** (int counter), wizard levels 1-9, priest 1-7 | Lua globals `mageSpells[level]` / `priestSpells[level]`, keyed by resref (`pushSpell` + `lua_setfield`) | Chargen, level-up (called from `CompleteCharacterClass`, `ShowNextSpellScreen`, `OnDoneButtonClick`). Per entry: `dimmGetResObject`, `CSpell::GetLevel == level`, `IsSpellHidden`, `GetNotUsableBy & class mask`, kit / school (`IsSpellSchool`), `GetAutoSpellPick` (SPLAUTOP), alignment. Missing file = skipped, loop goes on. |
| `CGameSprite::AddNewSpellsPriest()` (0x49eb30 / 0x348a60) | priest 0x49ecba, 0x49f091 / 0x348bf0, 0x348e10 | `GetNumPriestSpells(level)` (int, stack), levels 1-7 | `AddKnownSpell` (sprite known-spell `CPtrList`) after a duplicate scan of the known list | The priests' automatic spells (cleric / druid / ranger / paladin paths). Called by `CScreenCharacter::LevelUp`, `CScreenCreateChar::LevelUp`, `CompleteCharacterSkills`, `OnDoneButtonClick`, both `MakeDualClass`. Skips `IsSpellHidden == 1`, `IsUsableByAlignment`. |
| `CScreenCharacter::MakeDualClass(CGameSprite*, uchar)` (0x330f50 / 0x2a8da0) | priest 0x331c63, 0x331fb4 / 0x2a9280 | `GetNumPriestSpells(1)` (0x331c08 / 0x2a9233) | `AddKnownSpellPriest` | Level-1 priest spells of the new class. |
| `CScreenCreateChar::MakeDualClass(CGameSprite*, uchar)` (0x35e870 / 0x2b7330) | priest 0x35f624, 0x35f874 / 0x2b7810 | `GetNumPriestSpells(1)` (0x35f528 / 0x2b77c3) | `AddKnownSpellPriest` (+ `IsSpellHidden`) | Same, chargen side. No mage getter call: the new wizard spells come from `ResetSpellTables`. |
| `CScreenCreateChar::MageSchoolSpellsAvailable(uchar level, CGameSprite*)` (0x34e340 / 0x2b7130) | mage 0x34e445 / 0x2b718e | **hard-coded 50**: `cmp ebx, 0x32` (Linux), `inc dil; cmp dil, 0x32` (Windows, byte counter) | nothing (bool) | "Does this level have a spell of the specialist's school?" for the bonus slot (`GetSpecialistBonusSpells`, `IsDoneButtonClickable`, `UpdateChooseMagePanel`, `ResetChooseMagePanel`). |
| `CScreenCreateChar::AutoPickMageSpells()` (Lin 0x362660) | mage 0x3631df | hard-coded 50 (`cmp r13d, 0x32` twice) | `CPtrList` of candidates | **Dead code**: no caller and no reference on Linux; absent from the Windows build. The UI's spell choice has no engine auto-pick. |

Callers that read the lists, never the getters (no limit found):
- `UpdateChooseMagePanel` / `UpdateMemorizeMagePanel` / `UpdateMemorizePriestPanel` walk `mageSpells[level]` /
  `priestSpells[level]` with `lua_next` and fill `chargen.choose_spell` (UI.MENU `list` with `table
  "chargen.choose_spell"`, scrolling, no row cap). `OnLearnMageSpellButtonClick(i)` reads `chargen.choose_spell[i]`
  (Lua number index). `AddChosenSpellsToKnown` walks the Lua table (`lua_next`) -> `AddKnownSpellMage/Priest`.
- Sorcerer / bard known-spell picks at chargen and level-up: the same `mageSpells` + `chargen.choose_spell` path.
- In-game spellbooks: `CGameSprite::UpdateLuaSpells` fills `characters[id].mageSpells/priestSpells` from the
  known-spell lists (only level bounds 7 / 9 in it).
- Scroll learning (`CGameEffectLearnSpell`, op 147, `CScreenInventory::DelayLearnSpellCheck`): resref only, no list.
- HIDESPL: `CRuleTables::IsSpellHidden(CString resref)` is a 2DA row lookup by resref (`IS_HIDDEN`), so any resref
  can be hidden; `IsSpellRemoved` / `IsFinalSpell` likewise.
- `GetMageExtraSpells` / `GetSorcExtraSpells` / ...: number of picks per level, not list length.

## 3. What stays bound to names / numbers

- **spell.ids numbering**: `CGameAIBase::DecodeSpell(int id, CString&)` (Lin 0x160fb0) = `"SP" + PR/WI/IN/CL +
  Format("%d", id % 1000)`; used by `Spell`, `SpellPoint`, `ForceSpell`, `ApplySpell`, `RemoveSpell`, `WildSpell`,
  `EvaluateStatusTrigger`. So `Spell(Myself, 2xyy)` can only reach `SPWI<l><nn>`, 99 per level (the study's TL;DR).
  AI scripts and dialogs must use the RES forms (`SpellRES`, `ReallyForceSpellRES`, `HaveSpellRES`...) for list
  spells.
- `CGameAIBase::EncodeSpell(CString& res, int level)` (Lin 0x161150), used when a spell is cast (`FireSpell`,
  `Spell`, `ForceSpell`...): `type base (SPPR 1000 / SPWI 2000 / SPIN 3000 / else 4000) + level * 100 +
  sscanf(Right(2), "%d")`. A resref outside the numbered scheme gets a made-up id: `SPWI1AA` -> 2100, `ABCDE07` at
  level 3 -> 4307. Triggers and stats that compare spell **numbers** of the last cast spell can then collide. Same
  as today with SFO extended spells and CST resrefs (not new with the switch).
- **WeiDU `ADD_SPELL`**: still slots 01-50 (99 with the proposal of the study). List spells need no IDS entry:
  `COPY` the SPL under its own resref, then `APPEND ~iexsplst.2da~ ~<resref> <type> <level>~`.
- IDS names in compiled scripts, `SPELL.IDS` lookups of mods at install time.
- Not affected: CRE known / memorized spells (resref), op 147 / 171 / 172, sequencers and contingencies (known
  spells), item abilities.

## 4. The cap

| Setup | Wizard list per level | Priest list per level |
|---|---|---|
| Vanilla | 50 (getter bound) | 50 (getter bound; SPELLS.2DA 50) |
| `spellSlots99` | 99 | 99 (with SPELLS.2DA 99, the SpellSlots mod) |
| `spellLists` | engine slots (50 / 99) + IEX list, int counters (~2^31) | same; `GetNumPriestSpells` raised to base + list |

Limits that remain with `spellLists`:
- `MageSchoolSpellsAvailable`: **fixed 2026-11-02** (section 9). It used to scan engine slots 0-49 only, so a
  specialist whose school only exists in slots 51-99 / list spells at some level got no bonus slot there.
- Cost: `ResetSpellTables` demands every SPL of every level each time the chargen spell screen is rebuilt;
  `AddNewSpellsPriest` scans the known list for each candidate (N x K). Thousands are fine; 10^5 would be slow.
- SPELLS.2DA values below the engine bound (a mod restricting priests to the first n slots of a level): **respected since 2026-11-02** (section 9) for the priests' automatic spells and dual-class; the chargen
  `priestSpells` table ignores SPELLS.2DA, as without IEX.

## 5. CST and SFO

- **CST** (ClassSpellTool): spells keep their own resref, no IDS, lists in `M_MEEXSP.lua` + UI.MENU injection;
  clerics / druids can't get them at chargen. With `spellLists`, the same resrefs could be registered natively
  (`IEX_SpellList_Add` from a small bridge reading CST's lists, or rows in IEXSPLST.2DA): priests then learn them
  through `AddNewSpellsPriest` at chargen and level-up. Class / kit filtering stays CST's job (the engine only checks
  the SPL's own exclusion flags). Risk: an entry injected by both CST's UI code and the engine list shows twice in
  `chargen.choose_spell` unless CST skips keys already in `mageSpells`. Not tested.
- **SFO `ui_extra_spells`** (`SPWI1AA`-style extended resrefs, `dw_ext_spell.ids`): the extended resrefs can be fed
  to the lists as they are (resref only). `dwUpdateChooseSpells()` injects spells >= 50 and extended spells into
  `chargen.choose_spells`; with the lists active the same spells already come from `mageSpells` -> duplicates
  unless SFO checks. Its priest grant spells (CLAB) would also overlap the native priest auto-learn (duplicates are
  harmless there: `AddNewSpellsPriest` skips known spells). Needs a test with SCS / IWDification, maybe a dedupe
  guard on the UI side.
- Design note: the list key is the resref, so `mageSpells[level]` (a Lua table keyed by resref) merges duplicates
  from engine slots and lists by itself; only UI code that appends to `chargen.choose_spell` directly can duplicate.

## 6. Implementation (`spellLists`)

- `src/core/spell_lists.cpp`: installer of hook point `spellLists` (kind switch). Checks every call site of the
  three functions first (E8 to the expected target), then redirects all of them (`HookCallSite`), all or nothing.
  The getters themselves are untouched, so `spellSlots99` (one byte inside each getter) works in any order, on or
  off. The base is read live: the getter answers every index up to its bound, so the first empty answer is found by
  bisection over 0..98 (<= 7 calls, only when the engine answer is empty). Index 99+ is never passed to the engine.
- Call sites in `engine/*.iexd` (`callsite` records, hand-appended with their source, like ConcentrationFailed), the
  Windows `GetNumPriestSpells` symbol also in `IEX-data/engine/win/verified_spelllist.json` (in `gen_all.sh`) and
  the three names in `engine/hook_targets.txt`, so a regeneration emits the same records.
- `lua/IEX_SpellLists.lua`: `IEX_SpellList_Add` wrapper (turns the switch on), `IEXSPLST.2DA` loader at
  `GameStateInitialized`, `IEX_SpellLists_Status`. `weidu/IEX/IEX.tp2` creates an empty `IEXSPLST.2DA`.
- Lua API and 2DA format: `docs/API_SPEC.md` section 20.
- Linux: same code, same hook mechanism; Linux call sites 14 (one more priest site in `CScreenCharacter::
  MakeDualClass`, and the dead AutoPick site). Built with WSL GCC (`~/iex-build-spellcap`), not run yet.
- 2.6.6: IEX has no 2.6.6 engine description, so the switch does not exist there. Same code shape (bound
  `cmp r9d, 0x31` at 0x241c78 / 0x245178, call sites: mage 0x2b6b0e 0x2c26c5 0x2c2a7d, priest 0x2a8c00 0x2b7190
  0x2c2b26 0x2c2e57 0x3485b0 0x3487d0, GetNumPriestSpells 0x2a8bb3 0x2b7143 0x34858d 0x3487af).

## 7. Test plan

Private copy `E:/Dev/IEX-data/testgame/spellcap-bg2ee` (BG2EE 2.7.3, `make_clean.py`), already prepared:
IEX core installed from this branch (`setup-IEX.exe`, `IEXSPLST.2DA` created), build deployed with
`tools/deploy_build.py`, and `tools/spelllists/SpellListTest` installed: 120 wizard level-1 list spells
`ZW1001-ZW1120` ("SLT Wizard 001.."), 20 priest level-1 list spells `ZP1001-ZP1020`, `SPWI160` ("SLT Slot 60",
visible only with `spellSlots99`), probe `M_SLTEST.lua` (writes `IEX/slt.txt` and `[SLT]` lines in `IEX.log`).

Run `tools/windows/mute_games.ps1`, keep `tools/windows/watch_popups.ps1` running, start `IEXLauncher.exe` of the copy.

| # | Setup | Steps | Expected |
|---|---|---|---|
| 1 | as installed (`spellLists` on, `spellSlots99` off) | IEX.log after the main menu | `[spellLists] IEXSPLST.2DA: 140 entries`, `switch on`, `Spell lists: 13 call sites redirected` (Linux: 14) |
| 2 | same | New game, single-class Mage, reach the spell choice | list scrolls past 99 entries; `SLT Wizard 001-120` present; `slt.txt`: `mageSpells[1]` >= 140, `ZW = 120`, `SPWI160 = false` |
| 3 | same | Pick an `SLT Wizard 1xx` spell (one past index 99), finish, open the spellbook | the spell is known and memorizable; log line `wizard level 1: engine slots 01-50, then 120 IEX entries` |
| 4 | same | New Sorcerer: chargen known-spell pick | `SLT Wizard` entries offered |
| 5 | same | New Cleric (and a Druid): finish chargen, priest spellbook level 1 | `SLT Priest 01-20` known; `priestSpells[1]` has `ZP = 20` |
| 6 | same | Level-up a mage from the saved game (CLUAConsole `C:AddExperienceParty(...)` or a save) | level-up spell choice shows the list spells |
| 7 | + `spellSlots99`: `setup-SpellSlots.exe` (dist/SpellSlots) | tests 2 and 5 again | `SPWI160 = true`; log `engine slots 01-99, then 120`; ZW and ZP entries still there |
| 8 | `spellSlots99` on, `spellLists` off (rename `override/IEXSPLST.2DA`) | test 2 | `SPWI160` offered, no ZW; `spellLists installed=false` |
| 9 | both off (uninstall SpellSlots, 2DA renamed) | test 2 | vanilla list, nothing from the test mod |
| 10 | dual-class: Fighter -> Cleric | dual at level 9 | `SLT Priest` spells known after the dual |
| 11 | Linux (WSL, private copy, `~/iex-build-spellcap/libiex.so`) | tests 1, 2, 5 | same; 14 call sites |

No crash in any test (watch IEX.log and popups). Then quit without saving.

## 8. Test results (2026-11-02, BG2EE 2.7.3, private copies)

Windows `IEX-data/testgame/spellcap-bg2ee`, build of commit 6b94f3b. Driven with background clicks plus the probe's
command channel (`IEX/slt_cmd.lua`, `SLT_Out` -> `IEX/slt_out.txt`, test copies only). No popup, no crash, no Lua error
from IEX in any run.

| # | Result | Evidence |
|---|---|---|
| 1 | pass | `IEXSPLST.2DA: 140 entries`, `Spell lists: 13 call sites redirected`, switch on |
| 2 | pass | chargen mage: `mageSpells[1]` 142 entries (ZW 120, SPWI160 absent); `chargen.choose_spell` 141 rows, ZW at rows 21-140; log `wizard level 1: engine slots 01-50, then 120 IEX entries` |
| 3 | pass | learned `ZW1110` / `ZW1105` (list index > 99) in the choice list, memorized "SLT Wizard 105" x4 at chargen; in game the sprite knows `ZW1105` |
| 4 | pass | sorcerer chargen pick: list of 141, `ZW1120` (row 140) picked and enabled |
| 5 | pass | cleric and druid chargen memorize lists (built from the known spells `AddNewSpellsPriest` gave): 31 / 27 rows, all 20 `ZP` |
| 6 | partial | mage level-up 7 -> 9 in game: no crash (BG2 mages pick no spells at level-up; the level-up list is the same `ResetSpellTables` as 2-4). Sorcerer level-up not run |
| 7 | pass | with SpellSlots: `SPWI160 = true`, 143 entries, ZW 120; log `engine slots 01-99, then 120`; cleric memorize list ZP 20 (GetNumPriestSpells raised past 99) |
| 8 | pass | `spellSlots99` on, `IEXSPLST.2DA` renamed: switch not installed, 23 entries, SPWI160 present, no ZW |
| 9 | pass | both off (SpellSlots uninstalled, 2DA renamed): 22 entries, nothing from the test mod |
| 10 | pass | in game, mage 9 dual-classed to cleric: known priest level 1 = 31 incl. all 20 `ZP` (`MakeDualClass` + `AddNewSpellsPriest`) |
| 11 | partial | Linux (`~/games/spellcap-linux`, WSL): `14 call sites redirected`; cleric chargen up to class: `mageSpells[1]` 142 (ZW 120), `priestSpells[1]` 33 (ZP 20), same base log lines. Lua-driven chargen stuck at alignment, so priest auto-learn / dual-class not run on Linux |

SFO / CST duplicate check (read from their sources, no game run):
- SFO `dwUpdateChooseSpells()` (sfo2e `lua/ui_extra_spells.tph`, `m_dw_sxf.lua`) adds a spell only when
  `spellBook[level][resref]` is nil. The engine sets `spellBook = mageSpells` when it fills the choose panel
  (`CScreenCreateChar::UpdateChooseMagePanel`, Lin 0x351161-0x351185: `lua_getglobal("mageSpells")`,
  `lua_setglobal("spellBook")`; shamans use their own branch). So a spell that comes from an IEX list is already in
  `spellBook` and SFO skips it: **no duplicate** in the wizard / sorcerer / bard choice. Priests: SFO gives its
  priest spells through CLAB grant spells, which `AddNewSpellsPriest` / `AddKnownSpell` deduplicate by resref.
  Shaman branch: the engine sets `spellBook = priestSpells` for shamans (Lin 0x351159 `cmp al, 0x15` ->
  0x351b50 `lua_getglobal("priestSpells")` -> the same `lua_setglobal("spellBook")`), and SFO's shaman path
  (`class == 21`: `dwExtraPriestSpells`, `list = 'priestSpells'`) checks the same `spellBook[level][k]`: no
  duplicate either.
- CST (`ClassSpellTool.TPA` UI patch) checks `me_isAlreadyAvailable` (key already in `chargen.choose_spell`) before
  inserting, mage and priest: no duplicate.

## 9. Follow-up 2026-11-02 (branch feature/spell-lists-2)

### Specialist bonus slot (MageSchoolSpellsAvailable)
Chosen option: the register call-site hook on its GetMageSpell call (`RegSchool`, `src/core/spell_lists.cpp`), not a
reimplementation. The engine keeps doing its own per-spell test (demand, `CSpell::GetSchool`, `IsSpellSchool`, kit
mask / `0x4000` flag), so the result is exactly the engine's; only the list it walks grows. The hook gives the call
the virtual index (0, 1, 2...; restarted when the engine counter is 0) and sets the counter register so that the
engine's own `counter + 1 == 50` exit comes right after the last engine slot / list entry (Windows: byte counter
`dil`, `inc dil; cmp dil, 0x32; jb`; Linux: `ebx`, `add ebx, 1; cmp ebx, 0x32`, twice). The code shape around the call
is checked first (`SchoolSiteShape`); if it differs, the check stays on slots 01-50 and the log says so. With 50
entries or fewer nothing changes. Early `return 1` (school found) is fine: the next call starts at counter 0.

### SPELLS.2DA below the engine bound
The priest getter calls of the loops bounded by `GetNumPriestSpells` (`AddNewSpellsPriest` x2, both `MakeDualClass`;
Windows 4 sites, Linux 6, build constants `IEX.spellLists.countedPriest.N`) use `ResolveCounted`: engine slots
`0 .. min(2DA, base) - 1`, then the list; `GetNumPriestSpells` answers `min(2DA, base) + list`. The chargen /
level-up lists (`ResetSpellTables`, read until the empty resref) are unchanged: the engine shows every slot up to its
bound there whatever SPELLS.2DA says.

### Tests (private copies: Windows `spellcap2-bg2ee` + test mod with ZW6001 and ZW2001-ZW5001; Linux
`~/games/spellcap-linux`). Chargen driven through the Lua the UI buttons call (alignment needs
`currentChargenAlignment` set first: that was the stuck Linux step). No popup, crash or IEX Lua error.

| Case | Windows | Linux |
|---|---|---|
| Log | `13 call sites redirected (...; 4 SPELLS.2DA-bounded priest calls; specialist check extended)` | `14 ...; 6 ...; extended` |
| Enchanter (ToB start), level 6: Vanilla has no level-6 Enchantment in 01-50; ZW6001 (Enchantment, level 6) in the list | 5 picks at level 6 (bonus slot); 4 with ZW6001 removed | 5 picks with ZW6001 |
| Cleric, SPELLS.2DA PRIEST level 1 = 10 | known level 1: SPPR101-110 (9 files) + 20 ZP = 29; SPPR111+ not given | - |
| Cleric chargen, priest auto-learn (2DA 50) | (previous run) | memorize list 31, ZP 20 |
| Dual-class mage 9 -> cleric (in game) | (previous run) | known priest level 1 = 31, ZP 20 |
| Sorcerer level-up 1 -> 10 (in game) | pages 2-5 each offered its ZWn001, all four learned, no duplicate in the book | - |
| Bard: chargen list 141 rows (list spells offered); level-up 1 -> 12 | no spell pick at level-up (BG2EE bards learn from scrolls), no crash | - |

Note from the tests: calling `createCharScreen:OnDoneButtonClick()` again after the last level-up page has closed adds
the chosen spells to the book once more (a script artefact of the test, seen once; the UI never does it).
