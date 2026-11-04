# Naming the Windows exe from the symbolized Linux build

Goal: give names to functions of the stripped Windows x64 BG2EE 2.7.3 exe (MSVC) using the
Linux x86-64 build of the same version (GCC 13.3, full `.symtab`). Clean-room: only the two
game binaries are used, no EEex/InfinityLoader code or pattern databases.

Outputs (game-derived, kept in `IEX-data`, never committed here):
`IEX-data/engine/win64-bg2ee-2.7.3.symbols.json`:
`[{name, demangled, addr (RVA hex), confidence, method, linux_addr, aliases?}]`.

## Pipeline

```
Ghidra (headless, own project IEX_win273)
  import + auto-analysis of Baldur.exe
  Win_CreateFunctions.java   adds functions that analysis missed (non-chained .pdata entries,
                             16-aligned .rdata pointers into .text = leaf virtuals)
  Win_ExportFunctions.java   function list + body ranges + thunks -> win_functions.jsonl
tools/match/binfeat.py       per-function features for both binaries (capstone)
tools/match/match.py         matching phases, writes the symbol table
tools/match/coverage.py      coverage per class / Lua API
tools/match/consistency.py   call-graph agreement of every pair (error estimate)
tools/match/inspect_pair.py  side-by-side features of a pair
Win_DecompileRVAs.java       decompile a list of RVAs (manual validation)
```

Commands:

```
python -I tools/match/binfeat.py elf <BaldursGateII> <linux symbols.json> lin_feat.pkl
python -I tools/match/binfeat.py pe  <Baldur.exe> win_functions.jsonl win_feat.pkl
python -I tools/match/match.py lin_feat.pkl win_feat.pkl out.json [--overrides overrides.json] [--report r.txt]
```

### Features (binfeat.py)
Linear disassembly of each function body: ordered direct calls (function or import), string
literals (RIP-relative `lea`/`mov` to printable NUL-terminated data), function pointers taken,
other RIP-relative data refs, float/double constants, immediates, instruction and branch counts,
and the interleaved order of strings and function pointers.

Binary facts found on the way:
- Linux: PIE, pointers in data come from `R_X86_64_RELATIVE` relocations. Local (static)
  functions are absent from `.symtab`; they are recovered from `.eh_frame` FDEs as unnamed
  `sub_<addr>` pseudo-functions (not output, but they carry the call graph). `.cold` parts are
  merged into their parent.
- Windows: relocations stripped (fixed base 0x140000000), so data pointers are found by scanning
  8-aligned qwords. **No RTTI for game classes** (/GR-): only 13 std classes have type
  descriptors, so vtables cannot be named from RTTI. The exe **exports SDL2** (546 names).
- MSVC uses LTCG: small/one-caller functions are inlined (Lua API too) and identical functions
  are folded (ICF). One Windows address can stand for several Linux functions (`aliases`).
- No OpenSSL in the Windows build (SChannel), so the ~2000 OpenSSL symbols of Linux never match.

### Matching phases (match.py)
1. **PE exports**: SDL2 exports by name (ground truth).
2. **Unique strings**: a literal referenced by exactly one function on each side votes for the
   pair; mutual best + vote purity ≥ 0.5.
3. **Name tables**: `(char *name, fnptr)` pairs in data (luaL_Reg etc.), keyed by
   (name, previous name, next name).
4. **String-adjacent function pointers**: `lua_pushcclosure(L, fn); lua_setglobal(L, "name")`
   style registration code; key = string literal right after/before the `lea fn`.
5. Iterated propagation until no progress:
   - **callee alignment**: ordered callee lists of matched pairs aligned with difflib (matched
     callees/imports are anchors, unmatched ones are wildcards); also learns which static MSVC CRT
     function stands for a Linux import (`_Znwm`, `memcpy`...).
   - **callee sets**: order-free pairing of unmatched callees by call count (MSVC block layout
     differs from GCC, order is only a hint).
   - **caller sets / common callee**: unmatched functions whose matched callers map to the same set,
     or the single unmatched function called by all images of the callers.
   - **vtables**: Linux `_ZTV` (+16) vs Windows `.rdata` function-pointer arrays referenced by code.
     Pairing by the vtable refs of matched constructors/destructors, then by positional agreement
     of already-matched slots. Slot-by-slot naming after removing Itanium's complete-object
     destructor (D1) so D0 (deleting) faces MSVC's scalar deleting destructor.
   - **globals**: global data addresses paired through aligned data refs of matched pairs; a
     mapped global referenced by a single unmatched function on each side matches them.
   - **rarer strings**: idf-weighted string-set similarity, mutual best with margin.
   - **layout gaps**: between two anchors consecutive in both binaries, equal-size gaps of
     unmatched functions pair in address order (source order inside a TU).
   Every acceptance also needs a structural similarity score (instruction/branch/call counts,
   strings, constants) above a threshold.
6. **Overrides**: results of manual verification (decompiled code reading) in a JSON kept with the
   data: `set` (name -> RVA), `set_alias`, `reject_win`. Used for the Lua C API.

### Confidence
- `high`: unique-string with ≥2 votes or good similarity, exports, name tables, multi-vote call
  alignment, exact-length vtable slots with good similarity, manual verification.
- `medium`: single-vote propagation with good similarity, vtable prefix alignment.
- `low`: weak similarity or single half-votes; any ICF-folded address is capped at medium.

### Validation
- `consistency.py`: for each pair, the fraction of its matched callees+callers that map onto the
  Windows function's callees+callers. Pairs below 0.34 are suspects (~6-8% of high/medium, ~20%
  of low). It is pessimistic where MSVC inlined callees.
- Manual: decompile samples with `Win_DecompileRVAs.java` and compare to the Linux code.
  Lua API (lapi.c/lauxlib.c region at RVA 0xd5000-0xda000) was reviewed function by function.

## Known limits
- Inlining/ICF: many Linux functions have no standalone Windows body (e.g. `lua_getstack`,
  `luaL_checkany`, `luaL_checktype`, `luaL_checkoption`, `luaL_checkstack`, `luaL_checkversion_`
  are inlined everywhere on Windows). Coverage per class is therefore capped below 100 %.
- Statics competing with named functions, and tiny identical functions, cause most errors.
- Virtual functions only reachable through vtables whose vtable could not be paired stay unnamed.
