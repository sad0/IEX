# IEX (Infinity Extender)

IEX is an engine extender for **Baldur's Gate II: Enhanced Edition and EET 2.7.3**, on **Windows x64 and Linux x64**.
It provides the Lua API that EEex mods use, so those mods run unchanged, on both systems. It also adds features of
its own: frame interpolation, HD area tiles, engine fixes, unlimited class spell lists.

- Player downloads, install guide and feature docs: https://github.com/sad0/IEX-releases
- Bug reports: GitHub issues on this repository or on IEX-releases, or the Sado Mods Discord
  (https://discord.gg/3XzeQv7HeS). Please attach `IEX.log`, `IEX/missing_api.txt` and `WeiDU.log`.

Status: pre-release (0.4.0). Linux has only been tested under WSL2 so far; reports from native Linux desktops are
welcome.

## Clean room

IEX is written from scratch. It contains no code from EEex, InfinityLoader or EEex-Torment, and contributors must not
consult their sources. Only the API surface mods use (function names, signatures, observable behaviour) is
reproduced; engine knowledge comes from our own reverse engineering of the game binaries. See
[docs/CLEAN_ROOM.md](docs/CLEAN_ROOM.md). IEX is a separate project, not affiliated with EEex or Beamdog.

## Layout

| Path | Contents |
|---|---|
| `src/core/` | Portable core: Lua glue, EEex-compatible API, native features, engine fixes |
| `src/platform/win64/` | Windows: `IEX.dll` and `IEXLauncher.exe` |
| `src/platform/linux64/` | Linux: `libiex.so` (loaded with `LD_PRELOAD` by `iex-launch.sh`) |
| `lua/` | Lua runtime installed next to the game (`EEex_*.lua` API layer, `IEX_*.lua` features) |
| `engine/` | Engine descriptions (`.iexd`): addresses, symbols and layouts per game build |
| `ui/` | `.menu` files (options screen) |
| `weidu/` | WeiDU installer (`IEX/IEX.tp2`) and the `SpellSlots` companion mod |
| `docs/` | Design notes: API spec, hook points, matching method, engine fixes, HD tiles, spell lists |
| `tools/` | Generators and the maintainer's test harnesses (most need a private game copy, see `tools/README.md`) |

## Build

Requirements: CMake 3.20+, a C++17 compiler. Python 3 and `zip` for packaging.

Windows (Visual Studio 2022 or later, x64 developer prompt):

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Linux (GCC 13 or later):

```
cmake -S . -B ~/iex-build -DCMAKE_BUILD_TYPE=Release
cmake --build ~/iex-build
```

Package the WeiDU mod folders and the release zips (Windows binaries from `build/`, Linux `.so` from `IEX_LINUX_SO`):

```
IEX_LINUX_SO=~/iex-build/libiex.so tools/package.sh dist
```

Install: copy `dist/IEX` and `dist/SpellSlots` next to the game and run WeiDU on `IEX/IEX.tp2`; start the game with
`IEXLauncher.exe` (Windows) or `IEX/bin/linux64/iex-launch.sh` (Linux). Details:
https://github.com/sad0/IEX-releases/blob/main/docs/INSTALL.md

## How it's made

Ideas, design and testing are by sad0. Most of the code, reverse engineering and debugging is done with Claude
(Anthropic).

## License

GPL-3.0: see [LICENSE](LICENSE). Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Baldur's Gate and its Enhanced Editions are trademarks of their owners; no game files are included.
