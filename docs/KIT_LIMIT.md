# Unlimited single-class kits (feature `kitLimit`)

IEX 0.4.1, BG2EE / EET 2.7.3, Windows x64 and Linux x64. Source: `src/core/kit_limit.cpp`. Study (addresses, other
kit paths checked): `IEX-data/studies/KIT_LIMIT_STUDY.md`. Only the game binaries were read (docs/CLEAN_ROOM.md).

## The engine limit

`CRuleTables` keeps the CLAB table of each kit in a fixed array of 256 `C2DArray*` (`+0x2648`), filled by its
constructor for KITLIST rows 1..256 only. `CRuleTables::GetClassAbilityTable(class, kit)` returns `array[row - 1]`
for a kit whose KITLIST `CLASS` is the class asked, with no upper bound. A single-class kit on row 257 or higher
(KIT.IDS 0x4101 and up) therefore hands the next `CRuleTables` members to the engine as a CLAB table: crash or wrong
abilities at chargen, level-up, `AddKit` / `AddSuperKit`, dual-class, the fall / regain of paladins and rangers and
the rebuild when a creature joins the party. Everything else about kits
(CRE 0x244, the kit stat, `Kit()`, op319, the chargen kit list, CLASTEXT, WEAPPROF) is already 32-bit or 16-bit.
True multiclass kits (CLASS 7..18) never read the array.

## What IEX does

The two callers of `GetClassAbilityTable`, `CGameSprite::AddClassAbilities` and `RemoveClassAbilities` (the only
direct calls on both builds; no tail jump, no pointer to the function in data), call IEX instead:

| kit | result |
|---|---|
| no 0x4000 flag, row 0, row ≤ 256, row past KITLIST, KITLIST `CLASS` ≠ class | the engine's own answer |
| otherwise | IEX's CLAB table for that row |

IEX's table is a `C2DArray` built as the engine's constructor builds its own (0x38 bytes, empty CString default),
filled on first use by the engine's `C2DArray::Load` from KITLIST's `ABILITIES` column, and kept for the session
(the engine never frees its own either). A missing CLAB or `*` gives an empty table, as for rows ≤ 256. IEX.log
gets one line per row loaded.

New limit: KITLIST row **16383** (KIT.IDS 0x7FFF: the kit value is `0x4000 | row` in its low word). No CRE, CHR,
GAM or save format change.

Install: at the first Lua state (Baldur.lua is read by then, no character exists yet). Each call site is checked
(`E8` to the getter) and the getter's bytes must still read the expected `CRuleTables` offsets; otherwise nothing is
patched and IEX.log says why. Startup line: `Kit limit: 2 call sites redirected ...`.

## Switch and Lua

- On by default. Baldur.lua `SetPrivateProfileString('IEX','Unlimited Kits','0')` turns it off (read at start;
  also on the Engine Fixes tab of the options screen). Environment `IEX_KIT_LIMIT=0 / 1` takes precedence.
- `IEX_Features.kitLimit`: patched call sites (2), 0 when off.
- `IEX_KitLimit()` -> `{installed, sites, engineSlots = 256, maxRow = 16383 (256 when off), tables, why}`;
  `tables` = IEX CLAB tables loaded so far.
- Native hook registry: feature point `kitLimit` (`IEX_NativeHook_Points()`).

## Installing kits past row 256 (WeiDU)

WeiDU's `ADD_KIT` refuses a kit past row 256 unless it finds GemRB (`gemrb_path.txt`) or ToBEx
(`tobex_ini/tobexver.txt`), and stops at row 1280 in any case. IEX does not fake those markers (other mods read
them to use ToBEx / GemRB features). IEX ships instead (in `IEX/lib/`):

- `iex_kits.tpa`: `iex_kit_limit` (RET `kit_limit` = 16383 with IEX core installed, else 256; `iex`).
- `a7#add_kit_ex.tpa`: Argent77's `ADD_KIT_EX` (public domain, unmodified copy), a full ADD_KIT replacement that
  takes the limit as `__kits_limit_override`.

```
OUTER_SET iex_kit_limit = 0                 // 0: ADD_KIT_EX detects the limit itself (256)
ACTION_IF FILE_EXISTS ~IEX/lib/iex_kits.tpa~ BEGIN
  INCLUDE ~IEX/lib/iex_kits.tpa~
  LAF iex_kit_limit RET iex_kit_limit = kit_limit END
END
INCLUDE ~mymod/lib/a7#add_kit_ex.tpa~       // or ~IEX/lib/a7#add_kit_ex.tpa~
LAF ADD_KIT_EX
  INT_VAR kit_class = 2 mixed = RESOLVE_STR_REF(@1) help = RESOLVE_STR_REF(@2) __kits_limit_override = iex_kit_limit
  STR_VAR kit_name = ~MYKIT~ clab_path = ~mymod/kit/myclab.2da~
  RET kit_id
END
```

A mod whose kits may land past row 256 needs IEX at play time: `REQUIRE_PREDICATE (MOD_IS_INSTALLED ~IEX/IEX.TP2~
~0~)`. Kit mods that use plain `ADD_KIT` are unchanged: they install as before while KITLIST has room, and their
kits keep working; past row 256 they still stop at WeiDU's check until their author switches to the helper.

## Removing IEX

A save with a single-class kit on a row past 256 still loads without IEX (the kit value and the abilities already
granted are in the CRE), but the next level-up, `AddKit`, dual-class or fall / regain of that character reads past the
engine array again. Kit mods that use rows past 256 must require IEX.

## Tests

`tools/kitlimit/make_mod.py` writes `KitLimitTest`: 300 kits through `iex_kits.tpa` + `ADD_KIT_EX` on a vanilla
BG2EE (rows 42-341; 85 of them past 256); probe kits grant innate `K<nnn>L<ll>` at each CLAB level, so the innates a
character knows show which kit's CLAB the engine applied and for which levels. `tools/kitlimit/run.ps1` /
`run_linux.sh`: chargen with a kit past 256 (`createCharScreen` driven from Lua), level-up through the character
screen, `AddKit` to a control kit (row ≤ 256) and back, save, dual-class to mage, then a second run that loads the
save and levels up. Results: `IEX-data/kitlimit/`.

Results 2026-11-04 (`IEX-data/kitlimit/*.txt`, same on Windows and Linux):

| case | feature on | feature off (`IEX_KIT_LIMIT=0`) |
|---|---|---|
| chargen, fighter kit row 301 (KLT260) | K260 levels 1-7 granted | no kit abilities |
| level-up 7 -> 14 | levels 8-14 added | none |
| `AddKit` row 249 control, then back to 301 | K208 1-14 replace K260, then K260 1-14 back | K208 works (engine row), K260 nothing |
| save, reload in a new session, level-up 14 -> 16 | kit 0x412D and 14 innates kept, 15-16 added (table reloaded) | - |
| dual-class to mage | old kit innates removed (class 7, XP 0), same as the control kit on row 249 | same |
| chargen, row 257 (KLT216, first row past the array) | K216 1-7, level-up, AddKit as above | Windows: crash at chargen accept (access violation, AddNewSpecialAbilities); Linux: no abilities |
| Linux row 301, getter not patched | - | one run: SIGSEGV in `RemoveClassAbilities` (kit Done in chargen) |

## Limits

- BG2EE / EET 2.7.3 only (BGEE / IWDEE / 2.6 need their own addresses).
- Multiplayer: every player needs IEX (the rules tables are local).
- The chargen kit list shows every kit of a class in one scrolling list.
- Level drain (op216, the permanent level change effect) never reads the CLAB tables: no effect opcode calls
  `AddClassAbilities` / `RemoveClassAbilities` (callers checked on both builds, 2026-11-07: chargen, level-up,
  dual-class, `AddKit` / `AddSuperKit` actions, paladin / ranger fall and regain (`CheckReputation`), `JoinParty`).
  Nothing to test there for kits.
- Not tested: `AddSuperKit`, kits of other classes than fighter in chargen, EET.
- Adding 300 kits with `ADD_KIT_EX` took 31 min on a vanilla BG2EE (each kit rewrites ~30 tables).
- 16383 rows: going further would need a new kit-value encoding that every 32-bit reader agrees on.
