# Third-party notices

IEX bundles no third-party source code or libraries. It runs inside the game process and uses the game's own
statically linked Lua.

Behaviour reproduced from other projects:

- **BG Pathfinding Redux** 0.1.11, (c) 2026 Zach Hopkins, MIT licence
  (https://github.com/zach-hopkins/bg-pathfinding-redux). `src/core/pathfinding.cpp` reimplements its allied
  pass-through movement natively, from the mod's own Lua and documentation.
- **EEex** (Bubb13) defines the Lua API that IEX provides. IEX reproduces only the API surface mods use (names,
  signatures, behaviour) and contains none of EEex's code; see `docs/CLEAN_ROOM.md`.

File formats follow the IESDP (https://gibberlings3.github.io/iesdp/).
