# Mod scan rules (scan_mods.py, schema 1, rules_version 5)

Mod managers (Candlekeep) port these rules; keep them in sync with `tools/compat/scan_mods.py`.

## Files

- Lua side: `.lua`, `.menu` (EEex names, engine-object methods, fields).
- WeiDU side: `.tp2`, `.tpa`, `.tph`, `.tpp`, `.baf`, `.d` (EEex names, opcodes).
- Read as latin-1, every file of the mod folder recursively. Matching is textual (comments included).

## Patterns

| Category | Regex | Applies to |
|---|---|---|
| EEex names | `\b(EEex_[A-Za-z0-9_]*[A-Za-z0-9])\b` (rules_version 4: a match ending with `_`, e.g. `"EEex_Menu_" .. x`, is the prefix of a name built at runtime and is skipped) | all files |
| Engine-object methods | `[\w\]\)]\s*:\s*([a-z][A-Za-z0-9]+)\s*\(` minus Lua string/table/io methods (`format gsub match gmatch find sub upper lower len rep byte reverse insert remove concat sort unpack pack close read write lines seek char`) | Lua side |
| Engine fields | `\.(m_[A-Za-z0-9_]+)` | Lua side |
| EEex opcodes | `\b(?:opcode\|match_opcode\|effectID)\s*=\s*(40\d)\b` (case-insensitive) | WeiDU side |
| Hard usage | `\bEEex_(?:JIT\w*\|Hook\w*\|Label\|WriteU?\d+\|Write(?:Pointer\|Ptr\|String\|Byte\|Word\|DWord)\w*\|DisableCodeProtection\|EnableCodeProtection\|AllocNear\|Malloc\|Memcpy\|FlattenTable\|GenLuaCall)\b` | all files |

## Comparison with IEX (`iex_api.json`)

- Missing name: an EEex name not in `eeex_names`.
- Unknown field: an `m_` field not in `fields`.
- `iex_api.json` schema 1: `{"schema": 1, "version": "<IEX version>", "eeex_names": [...], "fields": [...], "features": [...], "hard_unsupported": "<text>"}`.
  `features` (since IEX 0.2.2's json, additive): capability flags IEX provides as `IEX_Features.<name>` (e.g. `partyVision`),
  taken from docs/API_SPEC.md. A flag can still be false at runtime (site already patched by another mod); mods test the Lua value.
  `eeex_names` also lists engine-object method names IEX defines (e.g. `getName`).

## Classification (suggested badges)

- **unsupported**: at least one hard-usage match (x64 code, hooks, labels or raw memory writes bound to one exe).
- **partial**: no hard usage, but missing names or unknown fields.
- **compatible**: nothing missing.

## Per-component verdict (rules_version 2)

- Components: every `BEGIN` block of every `.tp2` (up to the next `BEGIN`); id = `DESIGNATED n` (else block index),
  label = `LABEL ~...~`.
- Files of a component: the `.lua` / `.menu` paths quoted in the block (`[~"]...\.(lua|menu)[~"]`), plus those quoted
  in files it includes one level deep (`INCLUDE`, `ACTION_INCLUDE`, `PATCH_INCLUDE`, `REINCLUDE`); matched to the
  mod's files by file name, case-insensitive.
- Verdict when no file was found (rules_version 3): **unknown** (use the mod-level badge) if the block (plus its
  includes) has a quoted source that could hold Lua the scan cannot see — regex
  `[~"]([^~"\r\n]*%[^~"\r\n]*|[^~"\r\n]*/[^~"./\r\n]+/?)[~"]` (a `%variable%` path, or a folder path whose last
  segment has no extension) — or mentions `eeex` anywhere (case-insensitive: it may install Lua through a function);
  otherwise **no_lua** (pure WeiDU content, counts as compatible).
- Verdict with files: **unsupported** (hard usage in its files) > **partial** (missing names or unknown fields) >
  **compatible**.
- Mod badge: the mod-level result above; components refine it.

## Declares IEX support (rules_version 2)

- A mod "declares IEX support" when any of its files matches `IEX/IEX\.TP2|\bIEX_[A-Z][A-Za-z]+\s*\(` (case-insensitive):
  it tests for IEX or calls IEX functions. Report it; it does not by itself clear a hard-usage verdict (a catalog
  override `iex_support: native|partial` settles it). Scan the mod before applying install-time patches (the
  patcher adds `~IEX/IEX.TP2~` itself).
- `iex_api.json` carries `"rules_version": 5`.

## Fewer false positives (rules_version 5)

- **Comments do not count.** Before any pattern runs, comments are blanked: in `.lua` / `.menu`, `--` line comments
  and `--[[ ]]` / `--[==[ ]==]` blocks; in WeiDU files, `//` line comments and `/* */` blocks. Strings are kept
  (they hold Lua or script code), and a comment marker inside a string is not a comment. Regexes (Python, dot
  matches newlines): Lua `"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\[(=*)\[.*?\]\1\]|(--\[(=*)\[.*?\]\3\]|--[^\n]*)`
  (group 2 = comment); WeiDU `~~~~~.*?~~~~~|~[^~]*~|"[^"]*"|(/\*.*?\*/|//[^\n]*)` (group 1 = comment).
- **File and folder names are not API names.** An EEex name followed by `.lua .menu .dll .db .exe .ids .2da .tp2`
  (any case) or by `/` or `\` is a file probe (`FILE_EXISTS_IN_GAME ~EEex_Actionbar.lua~`, `EEex_scripts/...`):
  `\b(EEex_[A-Za-z0-9_]*[A-Za-z0-9])\b(?!\.(?i:lua|menu|dll|db|exe|ids|2da|tp2)\b|[/\\])`.
- **Script names.** `script_names` in `iex_api.json` (the EEex names of IEX.tp2's IDS entries: `EEex_LuaTrigger`,
  `EEex_LuaAction`, `EEex_LuaObject`, `EEex_Target`, `EEex_LuaDecode`, `EEex_SpellObjectOffset*`...) count as
  provided, unless the mod also uses the name in Lua code (outside strings and comments), where it is a Lua function.
- **Names a mod defines itself** are neither missing nor hard usage: matches of
  `(?:\bfunction\s+(EEex_\w+)|^\s*(?:local\s+)?(EEex_\w+)\s*=(?!=))` (multiline). Not counted: files under a
  `test(s)` / `spec(s)` / `mock(s)` folder (mocks of the real API) and guarded fallbacks `EEex_X = EEex_X or ...`
  (the extender's version is still used when there is one). The report lists them per mod.
- **IEX names built in loops** count as defined: `for name, x in pairs(T) do _G['EEex_Prefix_' .. name]` (the keys
  of table `T`), and method tables installed with `for name, fn in pairs(T) do CGameSprite[name] = fn` (plus the
  `...Iterator` spelling of `...Itr` keys).
- The summary table has a **badge** column, and a last section ranks missing names by the number of mods using
  them (with the hard-usage flag).

The scan is a guide: dynamic names (built at runtime) are not seen. `IEX/missing_api.txt`, written while playing,
lists the EEex names actually called and missing.

## Inventory (tools/compat/inventory.py, 2026-10-29)

A companion of scan_mods.py, not a rule change (no verdict changes, `rules_version` stays 5): it reuses the same file
reading, comment blanking (v5, but comments become spaces of the same length so line numbers stay right), RX_EEEX,
HARD, self-defined names and component blocks (`scan_mods.component_blocks()`, factored out of `components()` with
identical output, checked on the 49-mod corpus). It adds categories mod managers may show but must not use for the
badge: argument shapes and string arguments per EEex name, listeners, EEex internal hook names a mod replaces,
methods with inferred classes, field chains with classes, opcodes 400-409 with parameters, script IDS names and IDS /
2DA appends, EEex data files with the WeiDU operation, menus, EEex_Modules switches, settings (Baldur.lua keys,
EEex_Options ids, EEex.ini / InfinityLoader.ini lines), engine labels named in strings, EEex detection checks (with
whether patch_mod.py rewrites them). Output: docs/API_INVENTORY.md and inventory.json (schema 1); details in
docs/API_INVENTORY.md "Method".
