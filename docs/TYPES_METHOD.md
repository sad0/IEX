# How IEX derives engine struct layouts

Clean-room: every offset comes from our own analysis of the game binary plus public file-format docs
(IESDP). No EEex/InfinityLoader source, header or generated binding is read. Field *names* follow the
public Lua API names that mods use (taken from our own SadoEE code, see `sadoee_fields.md`).

Game-derived outputs (decompiled code, offsets) stay out of this repo, in `IEX-data/`:
- `IEX-data/engine/types/linux64-bg2ee-2.7.3.types.json` (layouts, built by `build_types.py` next to it)
- `IEX-data/engine/re/` (Ghidra dumps, `rtti.json`, `sizes.txt`, `derived_stats_by_id.json`)

## Inputs

- Linux BG2EE 2.7.3 `BaldursGateII`: ELF x86_64 PIE, GCC 13.3, full `.symtab` (no DWARF).
  Itanium C++ ABI, LP64: offsets differ from Windows x64 builds, which is expected.
- `linux64-bg2ee-2.7.3.symbols.json` from `tools/elfsyms/elfsyms.py` (demangled functions and objects).
- Ghidra 12.1.4 project, analyzed once, opened **read-only** by the scripts.

## Tools (this repo)

| Tool | Purpose |
|---|---|
| `tools/ghidra/run.sh Script.java args [-- Script2.java args]` | headless wrapper (`-noanalysis -readOnly`) |
| `tools/ghidra/FixNoReturn.java` | in-memory fix: auto-analysis flagged `operator new`, `memcpy`, `CAIObjectType::CAIObjectType`... as *noreturn*, which truncates every caller. Clears the flag, disassembles fall-throughs, drops bogus `FUN_` stubs. Run it first. |
| `tools/ghidra/DecompileList.java list outDir` | decompile functions (symtab VA or name) to `<VA>_<name>.c`; also repairs missing CALL fall-throughs in each function before decompiling |
| `tools/ghidra/CtorSizes.java ctorList out` | for every call to a constructor, walk back to the preceding `operator new(N)` and print N |
| `tools/ghidra/Disasm.java list out` | raw disassembly + function body ranges |
| `tools/elfsyms/rtti.py elf symbols.json Class...` | vtable address/size and base classes from Itanium typeinfo (`__si`/`__vmi_class_type_info`, resolved through `.rela.dyn`) |

Addresses in list files and outputs are **ELF symtab VAs** (image base 0). Ghidra loads the PIE at
0x100000; the scripts add/remove that delta.

## Procedure per type

1. **Size**: `CtorSizes` histogram of `operator new(N)` before ctor calls (most frequent N; outliers are
   wrapper structs). Embedded types: spacing between members in the owner's constructor.
2. **vtable / bases**: `rtti.py` (`_ZTV`/`_ZTI` objects). Constructors store `vtable + 16`.
3. **Fields**, strongest evidence first:
   - one-line getters/setters (`GetObjectType`, `SetFlags`, `SetTrapDetected`, `SetVisibleArea`...);
   - constructors that copy a public file record field by field (ARE container/region, CRE header, ITM/EFF),
     cross-checked with IESDP offsets;
   - `Marshal`/`Unmarshal` (e.g. `CGameSprite::Marshal` memcpy of the CRE header gives `m_baseStats`);
   - `CDerivedStats::GetAtOffset(statId)` (stat id → offset switch) and `Reload(CCreatureFileHeader*)`;
   - `UpdateLuaStats` and similar, which push values to Lua under readable keys ("HP", "current", "str"...).
4. **Confidence**:
   - *high*: a named function reads/writes the field with unambiguous meaning, or two independent sources agree;
   - *medium*: one indirect source (layout order, file-format mapping only, name chosen among similar fields);
   - *low*: plausible guess; must be verified at runtime before use.
   Each field carries `evidence: "function@VA: reason"`.

## Re-running

```sh
cd E:/Dev/IEX-data/engine/re
sh E:/Dev/IEX/tools/ghidra/run.sh FixNoReturn.java -- DecompileList.java 'E:\...\list.txt' 'E:\...\dec'
python -I E:/Dev/IEX/tools/elfsyms/rtti.py <elf> <symbols.json> CGameSprite CItem ... > rtti.json
python -I E:/Dev/IEX-data/engine/types/build_types.py
```

Ghidra's `analyzeHeadless.bat` breaks on paths containing parentheses.

Ghidra's project lock: when another headless run holds `IEX_linux273`/`IEX_win273`, copy the project
(`*.gpr` + `*.rep`, without lock files) to another folder and run with `GPROJ_DIR=<copy>`; the scripts are read-only.

Patch scripts run after the builders, in order: `add_t1b.py`, `add_res.py`, `add_bar.py`/`add_views.py`, `add_typ.py`
(fields the installed test mods use, list in `IEX-data/engine/types/needed_fields.md`), ..., `add_bgbot.py`, `add_bgbm.py`,
`add_bgbf.py` (BGBot fields: doors, walk-to points, trigger names, AI script slots, spell slot tables, search map),
`add_spell.py` (Bubb's Spell Menu: CButtonData, CAbilityId, CGameButtonList, disabled buttons, uiItem.button, UI capture, video mode),
`add_values.py` (difftest fixes: CRE kit words, SPL identifiedName / ability damage fields, EEex ITM header names),
then `tools/engine/gen_all.sh`.

Script names: containers and sprites keep theirs in `CGameAIBase.m_scriptName` (+0x488); doors (+0x5f0) and trigger
regions (+0x59c) keep their ARE name in their own field, which shadows the base one (`CGameDoor/CGameTrigger.m_scriptName`).
`CGameTrigger.m_ptWalkToUse` is only set for info regions with flag 0x400 (otherwise uninitialised memory).

## Next checks (runtime)

Low/medium fields should be validated on a running Linux game (read a known party member and compare
with the UI / CRE file): `m_armorClass`, `m_liveTypeAI` vs `m_startTypeAI`, `CInfinity.rViewPort`,
`CInfGame.m_nState`, `CGameEffect.m_sourceId`, `CRes.resref` (pointer), trigger `m_scriptName`.

## Windows x64 (MSVC) layouts

Output: `IEX-data/engine/types/win64-bg2ee-2.7.3.types.json` (built by `build_types_win.py` next to it,
diff notes in `win_vs_linux.md`). Same schema as Linux, plus `linux_offset` per field; addresses are
image RVAs. Method:

1. Name the Windows functions with the matcher (`MATCHING_METHOD.md`), then decompile the same evidence
   functions on both sides (`Win_DecompileRVAs.java` on project `IEX_win273`, program `Baldur.exe`:
   `GPROJ_NAME=IEX_win273 GPROGRAM=Baldur.exe sh tools/ghidra/run.sh ...`).
2. `tools/ghidra/offdiff.py win.c param_1 linux.c this [lo:delta ...]` lists offsets seen on one side
   only; with a shift model it validates a whole function at once.
3. Sizes: `tools/match/newsites.py <exe> win_functions.jsonl <operatorNewRVA>` lists every
   `operator new(N)` site with the ctor called on the result (or the vtable stored when the ctor is
   inlined); `Win_CtorSizes.java` does the same from a ctor list inside Ghidra.
4. vtables: the RVA the ctor stores into `[this]`. No RTTI for game classes: when a ctor is unmatched,
   find a matched virtual method in `.rdata` qword arrays and grep `lea reg,[rip+vtable]`
   (`tools/match/pegrep.py`, `tools/match/pedis.py --q`).
5. Check the matcher's pair before trusting it (one ctor in the 2.7.3 table was another class's ctor).

ABI differences that actually matter for these engine types:
- **Tail padding**: Itanium reuses a non-POD base's tail padding for the next member; MSVC does not.
  A member right after a `CPtrList`-derived object (0x38 bytes, int last) moves +8 on Windows.
- Platform base classes (`CChitin`) can differ in size: derived members shift as a block.
- `long` is 4 bytes on Windows, but the engine structs seen so far use fixed-width members; pointers and
  `CString` are 8 bytes on both.

## Engine methods (`method` records)

Engine member functions callable as Lua methods (`game:UnselectAll()`, `area:OnActionButtonClickGround(pt)`,
`obj:virtual_OnActionButton(pt)`) are declared in `engine/methods.txt` (class, Lua name, Linux mangled symbol or
`vt:<symbol>` holding a vtable byte offset, result kind, argument kinds). `build_desc.py --methods` resolves each
target against the symbol table of the build (Windows: hand-verified in `verified_*.json`) and writes
`method <Class> <name> fn:<rva>|vt:<offset> <ret> <args...>`; `src/core/lua_methods.cpp` binds one C closure per
record. Only integer-class arguments/results are supported, which makes one call path valid on both ABIs.
Methods the engine binds itself through tolua (`worldScreen:StepDialog()`, `game:GetPartyGold()`...) need no
record: on an IEX object they are found in the tolua class table and called through a bridge that hands the
tolua function a tolua userdata of the same address (`lua_objects.cpp`, ToluaBridge).
