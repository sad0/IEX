# Install-time compatibility rules (EEex-dependent mods -> IEX)

Implemented by `tools/compat/patch_mod.py`; mod managers (Candlekeep) port them. Applied to every `.tp2`, `.tpa`,
`.tph`, `.tpp` file of a local copy of the mod, byte-preserving (latin-1 round trip); a file that already contains
the IEX alternative is skipped (idempotent). Only install-time checks change, never game content.
Rule numbers are stable (a new rule gets the next number); rules apply in this order.

| # | Matches (case-insensitive regex) | Rewritten to | Reason |
|---|---|---|---|
| 0 | `MOD_IS_INSTALLED\s+([~"])(?:EEEX/)?EEEX\.TP2\1\s+\(\s*ID_OF_LABEL\s+([~"])(?:EEEX/)?EEEX\.TP2\2\s+([~"])B3-EEex-Main\3\s*\)` | `(<match> OR MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~)` | EEex main component found by its label (SadoEE, Wares of the Planes, Poisoned Pathways). Applied before rule 1 |
| 1 | `MOD_IS_INSTALLED\s+([~"])(?:EEEX/)?EEEX\.TP2\1\s+(?:([~"])0\2\|0)` | `(<match> OR MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~)` | Mods require EEex component 0 (`~EEEX/EEEX.TP2~ ~0~`, `~EEex.tp2~ 0`, `"EEex.tp2" 0`) |
| 2 | `FILE_EXISTS_IN_GAME\s+([~"])EEex_(?!(?:Brd\|Cra\|Modules)\b)\w+\.lua\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | Mods probe an EEex Lua file to detect a feature level (e.g. `EEex_Actionbar.lua`). Not the early-EEex files `EEex_Brd` / `EEex_Cra` (mods then COPY_EXISTING / patch them) nor `EEex_Modules` |
| 3 | `FILE_EXISTS\s+([~"])override/EEex_(?!(?:Brd\|Cra\|Modules)\b)\w+\.lua\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | Same, by path. **Not** `EEex_Modules.lua`: mods that test it then edit EEex's module switches (Infinity UI++ B3Scale), which IEX does not have |
| 4 | `REQUIRE_COMPONENT\s+([~"])((?:EEEX/)?EEEX\.TP2)\1\s+([~"])0\3` | `REQUIRE_PREDICATE (MOD_IS_INSTALLED ~<file>~ ~0~ OR MOD_IS_INSTALLED ~IEX/IEX.TP2~ ~0~)` (the message after it is kept) | Olvyn's mods, Epic Thieving, StickLuaFunctions require EEex component 0 |
| 5 | `FILE_EXISTS(?:_IN_GAME)?\s+([~"])(?:override/)?M___EEex\.lua\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | EEex's start file (v0.10 and later): BuffBot, BG2 Narrator, the four chriz mods, EEex Remote Console |
| 6 | `FILE_EXISTS(?:_IN_GAME)?\s+([~"])(?:override/)?M__EEex\.lua\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | Start file of early EEex: B_Kits, Proficiencies (their `EEex_Brd.lua` branches stay off, rule 2) |
| 7 | `FILE_CONTAINS(?:_EVALUATED)?\s*(\()?\s*([~"])(?:EEex_scripts\|override)/EEex_[\w-]+\.lua\2\s+([~"])[^~"]*?\b(EEex_\w+)\b[^~"]*\3\s*(?(1)\))` | `(<match> OR FILE_CONTAINS_EVALUATED (~IEX/IEX_API.txt~ ~^<name>$~))` | A function looked up in EEex's Lua sources (chriz mods, BuffBot `EEex_Sprite_GetCharacterIndex`). `IEX/IEX_API.txt` lists every EEex name IEX defines, one per line (tools/compat/api_list.py, packaged): the check stays true only for functions IEX has |
| 8 | `FILE_EXISTS\s+([~"])(?:lua51\|LuaProvider)\.dll\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | EEex's LuaJIT mode DLLs (BuffBot). IEX gives the same Lua libraries when InfinityLoader.ini says `LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL` (IEX.tp2 component 2); the mods still read that line themselves |
| 9 | `FILE_EXISTS\s+([~"])EEex\.dll\1` | `(<match> OR FILE_EXISTS ~IEX/IEX_Main.lua~)` | EEex's loader library in the game folder (BG Pathfinding Redux "Install EEex first"). IEX is the loader; that mod's runtime itself is replaced by IEX's native Pathfinding Redux |

## Checks deliberately not rewritten

They test EEex native code that IEX does not load; the mods' own fallback (or refusal) is the right result.

| Check | Mods | Why |
|---|---|---|
| `FILE_EXISTS ~EEex.dll~`, `~InfinityLoader.exe~`, `~EEex.exe~`, `~InfinityLoaderDLL.dll~`, `~LuaBindings.dll~` | Pathfinding Redux, chriz-bg-modpack (XP banking, UAI caster level) | native patches / JIT on EEex's loader |
| `FILE_EXISTS ~InfinityLoader.db~`, `FILE_CONTAINS ~InfinityLoader.db~ ~Hook-...~ / ~[CBMID::~` | Wares of the Planes (`is_eeex` spell states), chriz-bg-modpack | EEex's pattern database (asm hook labels); Wares installs its non-EEex variant |
| `DIRECTORY_EXISTS ~EEex_scripts/extra_pattern_dbs~`, `APPEND_OUTER ~EEex_scripts/EEex_Modules.lua~` | chriz-bg-rebalance, chriz-playable-races, chriz-bg-modpack | EEex pattern files / EEex's own start-up list (the rule 7 checks next to them stay false through this one) |
| `FILE_EXISTS ~EEex.db~` | EET Tweaks 1501 | early x86 EEex |
| `MOD_IS_INSTALLED ~EEex.tp2~ ~1~` / `"1"`, `REQUIRE_COMPONENT ~EEex.tp2~ ~2~` | Tweaks Anthology 6340 ("Requires LuaJIT, component #1"), ZS Tweaks (`has_EEex`, info only), XGT (`~0~ OR ~1~`: rule 1 covers it), High Power / Olvyn (`NOT ~1~` = no LuaJIT: they turn `bit.` into `bit32.`, the right path under IEX; component 2 = Effect Menu module) | component numbers differ between EEex versions (v0.x: 1 = LuaJIT; v1.x: 1 = main); IEX has no Effect Menu module |
| `FILE_EXISTS ~override/EEex_Modules.lua~`, `COPY_EXISTING ~EEex_Modules.lua~` | Infinity UI++, Bubb's IUI, High Power | EEex's module file; IEX keeps `EEex_Modules` (all false, lua/IEX_Settings.lua) |
| `FILE_EXISTS ~EEex/loader/LuaJIT/*.dll~` | BuffBot LuaJIT helper | only reached when the LuaJIT state is missing: it then fails with BuffBot's own message (install IEX component 2 first) |

## Settings files IEX reads (what mods write)

| File | Key | Written / read by | IEX |
|---|---|---|---|
| `InfinityLoader.ini` | `[General] LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL` (or `EXTERNAL`) | BuffBot helper (writes), Remote Console / BuffBot (check) | Lua `io`, `os` (with `execute`, `exit`) and LuaJIT's `bit` library opened for mods (src/core/settings.cpp). IEX.tp2 component 2 writes the line; IEX keeps the game's Lua 5.2 |
| `InfinityLoader.ini` | `[General] LuaLibrary`, `LuaVersionExternal` | BuffBot (writes / checks) | kept for the mods' checks (component 2 writes `lua51.dll` / `5.1`); no other Lua is loaded |
| `InfinityLoader.ini` | `[General] LogFile` | Pathfinding Redux (writes `bg-redux-runtime.log`) | every Lua `print()` line is also written there (`INFO: LPRINT: <text>`, the line format of EEex's log) |
| `EEex.ini` | `[<name> Module] Enable` | SadoQoL (Empty Container = 1), the options screen's Modules tab | `EEex_Modules.<B3...>` is true only for a module IEX has and EEex.ini enables (none yet: an enabled Attack Info, Effect Menu, Empty Container, Scale, Time Step or Timer module is reported in IEX.log) |

IEX.tp2 core creates `InfinityLoader.ini` (IEX's own file: comments, `LuaPatchMode=INTERNAL`, empty `LuaLibrary=`,
`LuaVersionExternal=`, `LogFile=`) when there is none, so mods that test or edit it find it.

## Known cases that need more than these rules

- Data files EEex installs and mods APPEND to or COPY_EXISTING: `X-STATS.2DA` (extended stats), `x-clserg.2da`, the
  EEex IDS entries (ACTION/TRIGGER/OBJECT/STATS). Fixed on the IEX side (IEX.tp2 installs them), not by patching mods.
- Bardic Wonders #2009 (End_of_file) and Shadow Magic #5 (missing c0sa101.spl) (2026-10-29 compatibility test).

Detection: `~IEX/IEX.TP2~ #0 #0` in WeiDU.log; version in `IEX/VERSION` (one line, e.g. `0.0.1`); EEex names IEX
defines in `IEX/IEX_API.txt`.
Launch: Windows `IEXLauncher.exe` (next to the game exe); Linux `./iex-launch.sh` (LD_PRELOAD of `libiex.so`).
