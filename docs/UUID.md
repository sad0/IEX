# Per-creature UUIDs (EEex_Sprite_GetUUID & co.)

Requested by Endarire. IEX 0.4.2+. Clean room: everything below about EEex was observed by
running EEex 1.3.1 in IEX's own test copies (return values, Lua tables, save files it writes) with the probe
tools/uuidtest; no EEex code was read. Engine facts come from Baldur.exe / BaldursGateII (own RE).

## EEex behaviour (observed 2026-11-22, EET 2.7.3 Windows)

| API | Observed |
|---|---|
| `EEex_Sprite_GetUUID(sprite)` | One value, a plain Lua number (integer). Errors on `nil` (index of a nil value). |
| `EEex_Sprite_GetFromUUID(uuid)` | The live creature (a new userdata for the same object: same `m_id`, not rawequal), or `nil` for an unknown number, `0`, `-1`. Any loaded creature is found, also creatures of other loaded areas (game-wide creatures). The argument must be a number (or boolean); `nil` / a string raise an error. A fraction is cut (`uuid + 0.5` finds `uuid`). |
| `EEex_Sprite_LoadedWithUUIDCallback(sourceSprite, uuid, func)` | Parameter names from `debug.getlocal`. `func` is appended to a list, then, if the creature `uuid` is loaded, `func(sourceSprite, target)` runs at once (only the new `func`); an error in it reaches the caller (the function stays registered). It stays registered and runs again with `(source, target)` when a creature with that number is created later (spawn), before the mods' loaded listeners. The same function registered twice runs twice. A `nil` source raises an error. `func` is not checked (a string or `nil` is stored as is). |
| `EEex_Sprite_Private_LoadedWithUUIDCallbacks` | `[targetUUID][sourceUUID] = { func, ... }` |
| `EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource` | `[sourceUUID][<the [targetUUID] table>] = true` |
| Source destroyed (`DestroySelf`) | Its entries are removed from both tables; a target table left empty is removed. A destroyed target keeps its entries. |
| Save / load | Callback tables are not saved (empty after a load). |

Numbers:

- Stored in the creature's local variable `EEEX_UUID` (low 32 bits in `m_intValue`, high 32 bits in `m_dWValue`;
  every value seen fits in 32 bits). The engine saves locals as op187 records in the creature's effect list (name at
  record + 0xa0, `m_intValue` at + 0x14, `m_dWValue` at + 0x18), in the GAM for party / global creatures and in the
  area files; so the number survives saves and area changes without a marshal handler.
- Handed out in sequence. The global `EEEX_NEXTUUID` (saved in the GAM) holds the last number handed out; the next
  creature gets last + 1.
- Set when the creature is created, before `EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled` and the loaded
  listeners (the local is already readable there). A creature with no number (spawn, new area creature, old save)
  gets the next one; a saved creature keeps its own.
- A copy (`CGameSprite::Copy`: op236 simulacrum / project image) gets a new number, also after a save/reload.
- A summon (op67) gets the next number.
- EEex also registers a marshal handler named `EEex` (seen in `EEex_Sprite_Private_MarshalHandlers`); its purpose
  was not looked into and IEX has no equivalent (saves still move both ways, see below).

`EEex::bNoUUID` / `EEex::bStripUUID` are internal EEex labels that only chriz-bg-modpack research code (not its
shipped mods) resolves to patch EEex itself; no IEX equivalent is needed.

## IEX implementation

- `lua/EEex_Sprite.lua`: the three functions, the two private tables, `CVariableHash:find(name)` (mods read
  `sprite.m_pLocalVariables:find("EEEX_UUID").m_intValue / m_dWValue`), `IEX_UUID_OnLoaded` (numbering),
  `IEX_UUID_RunCallbacks`, the `IEX_SpriteDestroyed` listener (source cleanup) and a uuid -> object id map for
  `GetFromUUID` (checked on every lookup).
- `src/core/marshal.cpp` (effect list unmarshal hook): the `EEEX_UUID` op187 record is cut out of the creature's
  effect list and handed to Lua (`IEX_UUID_FromEffects`), which writes the local before the loaded listeners. Left in
  the list, the engine would apply it later and bring the old number back on a copy. The engine writes the record
  again from the local when it saves the creature, as under EEex.
- `src/core/event_hooks.cpp`:
  - `SpriteLoaded` (loaded listeners, `OnAfterEffectListUnmarshalled`) now runs once the creature is in the object
    array AND its local variable table and effect list are in place. The engine's constructor adds the creature to
    the object array before it builds `m_pLocalVariables` on the save-load path (the field still holds garbage at
    `CGameObjectArray::Add`), so reading locals there crashed. Mods now also see marshal handler data before the
    loaded listeners, as under EEex. Fallback: creatures still waiting run after the engine tick.
  - New hook on the CGameSprite deleting-destructor vtable slot (`IEX_VtSlot_SpriteDestructor`, Windows
    0x598b68, Linux 0xcf9538, engine/win/verified_uuid.json) -> `IEX_SpriteDestroyed` event.
- `src/core/lua_engine.cpp`: `IEX_VariableFind(hash, name)` -> CVariable object; variable functions refuse a
  non-pointer hash instead of crashing.
- IEX extra: a creature created with a number another live creature already has (an imported character, a broken
  save) gets a new number, so numbers stay unique. Callbacks run under pcall when a creature loads (an error is
  logged and the load goes on).

## Tests (tools/uuidtest)

`run.ps1 -Side eeex|iex -Mode first|reload [-Save x] [-Extra probe/extra_*.lua] [-Quit]` (Windows, copies
IEX-data/testgame/uuid-eeex / uuid-iex made from difftest-release031 with make_copy.py, own Documents folders,
steam_appid.txt disabled), `run_linux.sh first|reload [filter] [extra] [tag]` (WSL, ~/games/uuidtest from
~/games/sadonative), `compare.py a.txt b.txt` (normalises ids, addresses, error text, pairs order).

| Check | Result (2026-11-22) |
|---|---|
| Same types / values as EEex: first mode (introspection, 21+ creatures, spawns, op236 clone, GetFromUUID cases, 10 callback registrations), reload, callbacks (order vs loaded listeners, duplicates, errors, source destroyed), summon | compare.py: same in every section; only difference: EEex's own `EEex` marshal handler |
| Save made under EEex (DIFFTEST) loaded under IEX | every creature keeps its number, the 60 load-time values in the same order |
| Save made under IEX loaded under EEex | same numbers, next number continues (148) |
| Save/reload under IEX (Windows, Linux) | all numbers kept, `EEEX_NEXTUUID` saved (147 on Windows) |
| Clone (op236) / summon (op67) / spawn | new numbers (147, 149 / 148 / 144-146), unchanged after a reload |
| Quit to start screen (every creature deleted with callbacks registered) then normal shutdown (`-Quit`, `UUID_QUIT=1`) | clean exit: EEex, IEX Windows (68 creature deletes through the destructor hook), IEX Linux (60, exit code 0) |
| Area leave / return (`extra_area.lua`: party to AR0700 and back to BG2100 with LeaveAreaLUA) | the 5 area creatures are unloaded while away (GetFromUUID nil), rebuilt with new object ids and the same numbers; a callback on one of them runs again on its second load in the session; EEex and IEX identical (compare.py: same) |
| Linux (WSL GCC build, vanilla BG2EE save with no numbers) | numbers handed out from 1, clone new, reload keeps all |

Not tested: character export / import (CHR), multiplayer, numbers above 2^32, `GetRatingWithItem`-style temporary
copies (they go through CGameSprite::Copy and take a number each, under IEX at least).

## Regression check against main 90b1be2 (2026-11-22)

`SpriteLoaded` moved later in the creature constructor, so the existing suites were run with the main build and
the feature/uuid build, same copies and saves, and compared main against branch:

| Suite | Runs (main / branch) | Result |
|---|---|---|
| tools/difftest (Windows, EET + SadoEE, difftest-release031 copies, IEX side; EEex side for reference) | 5 / 8 | no case that is the same in all main runs differs in the branch, apart from per-phase `ButtonsUpdated` event counts that shift in both directions (frame timing, also nondeterministic on main); one branch run in 8 saw creatures start actions during `op400wait` (game unpaused), not seen in the other 7; against EEex: 8 cases better (the UUID globals), none worse |
| tools/stack7 (Windows, full mod stack: TA, BuffBot, Stick, Pathfinding Redux, SadoEE...) | 5 / 5 | 0 diff, 0 missing, 0 extra; the nondeterministic keys (BuffBot state, spawned tableau count 41-44, fight hit actions) vary the same way on main; one TA Lua error (`M_GTTWKS.lua:672`, stoneskin feedback with no stoneskin left) in 1 branch run: a fight-timing race of the mod |
| tools/stack7/linux (WSL) | 2 / 2 | 1 diff: `party.after.p0.locals` has TA's `gtMakeGreaseIgnitable` in the branch runs only; it depends on whether the protagonist is greased in the fight, and EEex runs show both values (stack7/final) |
