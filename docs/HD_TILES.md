# HD area tiles (native switch `hdTiles`)

Date: 2026-11-03. Branch `feature/hd-tiles`. Code: `src/core/hd_tiles.cpp`, `lua/IEX_HdTiles.lua`, engine records at the
end of `engine/*.iexd`, test tools `tools/hdtiles/`. Related: `docs/FRAMERATE.md` (render path), the parallel study
the HD feasibility study (draw layer, texture table, shaders), `docs/HD_SPRITES.md` (creatures).

Clean room: only `Baldur.exe` / `BaldursGateII` were read (IEX Ghidra project, `tools/match/xrefs.py`, `pedis.py`,
`pegrep.py`, capstone) plus the game's own GLSL resources. The file format is the public convention of
InfinityEngine-Enhancer (IEE), taken as a spec only: no IEE, EEex, InfinityLoader or EEex-Torment file was opened.

## Rule

Game data stays at 1x. ARE / WED, search / height / light maps, every world coordinate and every engine size stay
the same. Only drawing changes: each 64x64 world tile is drawn from more texels of a bigger PVRZ page.

## Format (IEE convention)

- TIS V1 with 12-byte PVRZ tile entries (`page, x, y`), header +0x14 = tile size: 64 / 128 / 256 / 512 = 1x / 2x / 4x
  / 8x. Entry `x`, `y` are texel positions in the HD page (vanilla positions times the scale). Header size stays 0x18
  (the engine assumes it: `CResTileSet::Parse` points the entries at data + 0x18 whatever +0x10 says).
- PVRZ pages keep their names (`A0602nn`: `CResTileSet::SetTile` builds `"%c%.6s%02d"` from the TIS name) and are
  simply bigger (2048 / 4096 / 8192), DXT1 = BC1 as vanilla (DXT5 also loads: the engine maps PVR formats 7..11).
- WED / ARE / MOS untouched. A TIS from a BIFF (no header in the BIFF) is never HD; an HD TIS lives in `override/`.

## How the engine draws a PVRZ tile (2.7.3, both builds)

| Step | Linux VA | Windows RVA |
|---|---|---|
| `CInfinity::Render` loops over the view's tiles: base layer and the overlay layers, door / overlay cells with their secondary index | 0x320180 | 0x2a04c0 |
| `CInfTileSet::Render` (cull in world units, `CRes::Demand`, `CResPVR::Demand`, water alpha pass) | 0x3188f0 | 0x2a4570 |
| `CVidTile::RenderTexture(this, texture, rect, x, y, flags)`: entry `x, y` from `CResTileSet +0x40` when `+0x48 == 12`, tone (0 / 1 grey / 8 seam), `DrawBegin(2)`, 6 vertices with `DrawTexCoord(x / x+0x40, y / y+0x40)` | 0x5b9170 | 0x4257c0 |
| Draw layer: texture coordinates are 16-bit texel counts; the batch flush sets `uTcScale = 1 / (slot width, height)` of the bound texture (slot sizes stored by `DrawCompressedTexImage2D_GL`) | 0x56cef0 | - |
| `DrawBeginScaled_GL`: 2.7.3 always takes the direct path (no world-size framebuffer; `DrawInit_GL` writes 0 to the post-processing flag), so HD texels reach the window | 0x56ddb0 | 0x427b80 |

`CVidTile::RenderTexture` is the only reader of the PVRZ entry: `cmp [set+0x48], 0xc` appears in it, in
`CInfTileSet::Render`, and in the VRAM bookkeeping that skips PVRZ sets (`AttachToVRam`, `DettachFromVRam`,
`DetachVRamRect`, `SwapVRamTiles`). Callers: Linux 4 (`CInfTileSet::Render`) + one jmp in the unused
`CInfTileSet::RenderTexture`; Windows 2 (tail-merged).

## IEX design

Three call-site hook families (only call rel32 bytes change; every site checked before patching, all or none):

1. **`CVidTile::RenderTexture` calls** (Lin 4, Win 2). `HookRenderTexture` reads the tile's set
   (`CVidTile +0x100` -> `CResTile` {set +0, index +8, `CResPVR*` +0x10}). If the set is not PVRZ, has no `TIS V1`
   header in memory (BIFF), or its tile size is not 128 / 256 / 512, the engine function is called with the same
   arguments: **byte-identical behaviour for every vanilla TIS**. Otherwise it records the tile origin (entry `x, y`)
   and the scale, calls the engine function, and clears it.
2. **The 6 `DrawTexCoord` calls of `CVidTile::RenderTexture`** (build constants `IEX.hdTiles.texCoord.0-5`):
   while an HD tile is drawn, `u = x + (u - x) * scale` (same for `v`), so the quad spans `64 * scale` texels; the
   vertices (world space) are not touched.
3. **HD-aware seam program (v2).** `fpSEAM` (program 8, used for tiles when "Use Nearest Neighbour Scaling" is
   off) filters by hand with 1-texel neighbours and finds tile borders with `mod(tc - ref, 64.0)`. IEX rewrites the
   engine's own sources while the engine compiles program 8 (`DrawInit_GL` -> `DrawCreateProgram_GL(8, "vpDraw",
   "fpSEAM")`, call-site hook Lin 0x56fe23 / Win 0x42c3f6; `glShaderSource` intercepted at its 2 Linux call sites,
   PLT 0xcb300, and on Windows through the engine's pointer RVA 0x756f90, swapped only for that one call):
   - the original `main()` is renamed and still runs whenever the texel / world-pixel ratio of the quad
     (`dFdx` of the texel coordinate over `dFdx` of the vertex position, `vIexPos = aPos` added to the vertex
     shader) is 1: **every 1x draw runs the engine's code unchanged** (tiles pixel-identical to v1, see tests);
   - ratio 2 / 4 / 8 = HD tile: span `64 * ratio` texels from the tile origin `vRef`, hardware trilinear sample of
     the mipmapped page, **sample point clamped half a texel (of the sampled level) inside the tile's texel rect**:
     no atlas-neighbour bleed at any zoom.
   Works on a shader mod's fpSEAM too as long as it keeps `void main()`, `vTc`, `vRef`, `uTcScale`, `uTex`,
   `uColorTone`, `vColor` (and `aPos` in vpDraw); otherwise (or if the program does not link) the engine program is
   rebuilt as is and the v1 fallback applies: the `DrawColorTone` call-site hooks (`IEX.hdTiles.tone.N`, Lin 3,
   Win 1) turn tone 8 into tone 0 (`fpDraw`) for HD tiles. If the switch is installed after `DrawInit_GL` (not the
   case in the tests: Lua installs it first), program 8 is rebuilt once at the first HD area load.
4. **The `CResTileSet::SetTile` calls of `CInfTileSet::SetResID`** (area load; Lin 2, Win 2): SetTile gives every page
   `GL_NEAREST` (`CResPVR +0x5c` Linux / `+0x60` Windows, the filter `CResPVR::Demand` passes to `DrawGenTexture`).
   For an HD set, IEX writes its mark there (`0x4945mmss`: mode, log2 scale) before the page texture exists.
5. **Mipmaps (v2).** The `DrawGenTexture` / `DrawCompressedTexImage2D` calls of `CResPVR::Demand` (Lin 0x5837b3 /
   0x58381c, Win 0x3f6eee / 0x3f6f58) and `CResPVR::CreateTexture` (Linux only, 0x58352b / 0x583597; no Windows copy):
   a marked filter is replaced by the real one (`GL_LINEAR`, or `GL_NEAREST` with "Use Nearest Neighbour Scaling"),
   and right after the engine uploads level 0 IEX builds levels 1..log2(scale)+1 on the CPU (`src/core/hd_mips.cpp`:
   BC1 / BC3 decode, alpha-weighted 2x2 box filter, bounding-box BC encoder) and uploads them into the bound texture
   (`glCompressedTexImage2D` with the level-0 internal format from `glGetTexLevelParameteriv`), then
   `GL_TEXTURE_MAX_LEVEL` and `GL_LINEAR_MIPMAP_LINEAR` (trilinear; `GL_NEAREST_MIPMAP_NEAREST` with nearest
   neighbour scaling). The chain stops one level below the 1x tile size (enough for the engine's zoom-out limit 1.4)
   and keeps every tile origin on whole texels down to level log2(scale). VRAM +33 % per HD page. GL entry points come
   from the GL library (`platform::GlProc`: opengl32 / wglGetProcAddress, dlsym / glXGetProcAddressARB), resolved at the
   first upload. A page whose level 0 the engine had to decompress on the CPU (no S3TC) gets no mips.

Direct3D 9 (Windows Baldur.lua `Graphics` / `Backend` 1, read through `DrawGetRenderer`): HD tiles are drawn at 1x
(engine path) and IEX.log says so once. OpenGL only, as decided.

Switch: hook point `hdTiles` (category `render`, kind switch). `lua/IEX_HdTiles.lua` enables it at start unless
Baldur.lua `SetPrivateProfileString('IEX','HD Area Tiles','0')`. Lua: `IEX_HdTiles_Status`, `IEX_HdTiles_Stats()` ->
HD tile draws, other tile draws, tile sets seen, SetTile filter writes, pages mipmapped, mip levels uploaded, HD seam
program active, pages left without mips. IEX.log: `HD tiles: <TIS> tile size 128 -> 2x`
once per tile set (and any non-64 size it ignores).

## Consumers checked

| Consumer | Uses tile size / PVRZ UVs? | Result |
|---|---|---|
| Base tiles, animated tiles | `CVidTile::RenderTexture` | HD (tested) |
| Door tiles (WED door cells: secondary tile index of the same TIS, `CInfinity::Render` flag 2) | same call, same set | HD; Door05 of AR0602 opened in game, marked tiles drawn closed and open (shots) |
| Overlays / water (`CInfinity +8..+0x20` layers, own TIS; base tile alpha pass with `WATER_ALPHA`) | same call, scale per set | each overlay TIS decides for itself (vanilla `WT*` TIS are palette-based, untouched). An HD base with a 1x overlay and the reverse both work by construction; the water pass was not driven in a test area |
| Palette TIS (tile length 0x1400, `CVidTile::ReadyTexture`) | 64 px fixed | not HD (IEE convention is PVRZ only) |
| Fog / explored overlay (`CInfinity::RenderFog` -> `BltFogOWar3d`, untextured 64 / 32 px quads in world units) | no | unchanged (shots) |
| Minimap / area map (MOS) | separate | unchanged |
| Zoom (`CInfinity` +0x484, `DrawBeginScaled` direct path) | world units | HD detail visible when zoomed in (shots at 0.25) |
| Culling, VRAM pool, `SwapVRamTiles`, search map, lighting | world units / skip PVRZ | unchanged |
| Save thumbnails (`CScreenWorld::SaveScreen`) | same render | HD pages drawn, then read back at thumbnail size |

## Tests (2026-11-03, private copies)

Windows `E:/Dev/IEX-data/testgame/hd-bg2ee` (vanilla BG2EE 2.7.3, `make_clean.py`, IEX 0.3.1 + this branch through
WeiDU), save "Chapter 1 Start", AR0602 (4399 tiles, 29 pages, 21 doors). Test assets: `tools/hdtiles/make_hd_area.py`
(own BC1 decoder, Pillow Lanczos upscale, etcpak BC1 encoder; `--mark` draws a 1-texel white / black frame, a
diagonal and the scale in every tile). Probe `tools/hdtiles/probe/M_HDTEST.lua` (command channel). Window 1280x800,
"Use Nearest Neighbour Scaling" 0, zoom set with `IEX_Camera_SetZoom` (limit lowered to 0.25 for the shots).
Screenshots `E:/Dev/IEX-data/hdtiles/shots/`:

| Shot | What it shows |
|---|---|
| `win_1x_zoom100.png`, `win_2x_zoom100.png`, `win_4x_zoom100.png` | same view, zoom 1: identical geometry, no seam, no garbage |
| `win_1x_zoom025.png`, `win_2x_zoom025.png`, `win_4x_zoom025.png` | same view at 4x magnification |
| `win_2x_nearest_zoom025.png` | first build (engine `GL_NEAREST` kept): blocky, hence hook 4 |
| `win_4x_marked_zoom100.png`, `win_4x_marked_zoom025.png` | marked 4x pages: every 64 px world tile shows its own 256-texel frame; the 1-texel lines are 1 screen pixel wide at zoom 0.25 (= 1/4 world pixel), the frame edge sits on the tile edge (UV origin and span exact, no atlas bleed) |
| `win_4x_marked_door05_closed_zoom050.png`, `..._open_zoom050.png` | door tiles before / after Door05 opened |
| `linux_*.png` | Linux, same save (see below) |

Counters: `hdDraws` ~430k after 20 s, `mismatch` n/a; no popup (watch_popups), no IEX.log error, vanilla run
(`win_1x_*`): `hdDraws=0`, no `HD tiles:` set line (BIFF TIS).

Linux (WSL2 / WSLg, `tools/hdtiles/run_linux.sh`, private copy `~/games/hd-linux` of the Linux BG2EE base, GCC
build `~/iex-build-hd`): `HD tiles: 15 call sites redirected` (4 RenderTexture, 6 DrawTexCoord, 3 DrawColorTone,
2 SetTile), same save and the same marked 4x override files: `linux_4x_marked_zoom100.png`,
`linux_4x_marked_zoom025.png` identical in layout to Windows; vanilla run (`linux_1x_zoom025.png`): `hdDraws=0`,
no set line. Windows: 11 sites (2 + 6 + 1 + 2). The Linux shots are cropped to the game's client area.

## v2 tests (2026-11-03: mipmaps, HD seam program, clamped sampling)

Same copies, save and view. IEX.log, Windows: `14 call sites redirected (...; HD pages: mipmapped, trilinear (...);
seam program: HD-aware)` then `seam program HD-aware (engine fpSEAM for 1x, clamped trilinear for HD tiles)` (built by
`DrawInit_GL` through the hook); Linux: 22 sites, same lines. Counters after load at 4x: 15 pages mipmapped, 45 levels
(3 each) on Windows; Linux 11 / 33 (pages are demanded as they come into view). No popup, no GL / IEX.log error.

| Shot (`_v2`) | Result |
|---|---|
| `win_{1x,2x,4x}_zoom{100,025,140}_v2.png` | same view at zoom 1, 0.25 (4x magnification) and 1.4 (engine zoom-out limit) |
| `win_1x_zoom100_v2.png` vs v1 `win_1x_zoom100.png` | **vanilla unchanged**: pixel diff only on the animated sprites, the message line and the clock; every tile pixel identical with the rewritten seam program (`hdDraws=0`) |
| `linux_1x_zoom025_v2.png` vs v1 | same on Linux: only sprites / UI differ, `hdDraws=0` |
| `win_4x_marked_zoom100_v2.png`, `cmp_4x_marked_zoom100_v1_left_v2_right.png` | zoom 1 (4:1 minification): v1 drew the 1-texel frame lines as a bright aliased white on one side (point-like sampling of level 0, the shimmer source); v2 averages them through the mips (a uniform faint line, the correct coverage). Still frames only: no scrolling flicker measurement was run |
| `win_4x_marked_zoom025_v2.png`, `cmp_4x_marked_tile_edge_v1_left_v2_right.png` | marked tiles still exact; at the tile edge v1 blended the white frame into the neighbour tile (grey 2-pixel band = the half-texel bleed), v2 keeps a crisp white line and the black inner line on both sides: the clamp works |
| `win_4x_marked_zoom140_v2.png` | zoomed out 1.4: no moiré on the grates / frame lines |
| `win_4x_marked_door05_{closed,open}_zoom050_v2.png` | Door05 opened in game: door tiles (secondary indices) drawn through the same HD path, closed and open |
| `linux_4x_marked_zoom{100,025,140}_v2.png` | Linux, same results |

Plain Lanczos-upscaled pages carry no detail above 1x, so their zoom-1 shots look the same with and without mips
(high-frequency energy 9.69 vs 9.70); the marked pages are the worst case and show the difference.

## v3 / v4: mips without a hitch (2026-11-03)

the maintainer's decision: stored mips are used when the PVRZ has them, else they are built off the render thread; GL stays on
the render thread; safe against area unload and texture-slot reuse.

- **Stored mips.** A PVR3 body longer than level 0 whose size is exactly levels 0..n is split: the engine uploads level
  0 only (the whole body would be refused by GL), levels 1..n are copied and queued, nothing is built.
  `tools/hdtiles/make_hd_area.py --mips` writes such pages.
- **Built mips.** Level 0 is copied (one memcpy) and a worker thread (one, started on the first HD page) builds the
  chain; level 0 is drawn meanwhile (the engine's own texture, untouched apart from a `GL_TEXTURE_MIN_LOD` stamp).
- **Attachment = texture swap.** Writing new levels into the texture the engine draws with made drivers wait or copy
  (measured: 33-400 ms steps on NVIDIA when levels were added after level 0 had data, up to 394 ms on WSLg when added
  while in use). IEX instead builds a **new** GL texture with every level allocated, fills it in bands of at most
  256 KB (one band per 4 ms, between tile draws), then writes its GL name into the engine's texture slot
  (`IEX.hdTiles.texSlots`: Win 0x757040, Lin 0xddde60, 512 x 0x28, GL name at +0; slot = the hooked DrawGenTexture's
  result), rebinds it on units 0/1 where the old one was bound, and deletes the old texture.
- **Safety.** Before the first band: the slot still holds the job's texture. Before the swap: the slot still holds it,
  `glIsTexture`, and the MIN_LOD stamp matches (a texture recreated on a reused name has GL's default -1000). Otherwise
  the new texture is deleted and the job dropped (`IEX_HdTiles_Stats` counts attached / dropped).
- GL state queries are made once per PVR format (internal format, filters, wrap), the GL name comes from the slot table.

Measured (AR0602 marked 4x, 29 pages up to 4096x4096, scroll 4 px / frame for 8 s at zoom 1, VSync off; the machine
was shared with other heavy jobs, so frame rates vary a lot between runs; IEX's own render-thread time per step is the
stable figure, logged as `HD tiles: longest IEX render-thread step so far`):

| Build | Windows (RTX 5080) | Linux (WSL2 / WSLg, Mesa d3d12) |
|---|---|---|
| v2 (mips built on the render thread) | 180 ms per 4096 page in one frame; longest frame 546-636 ms | not measured |
| v4 built mips | IEX max step 1.5 ms (quiet run, 885 fps, longest frame 171 ms) to 34 ms (loaded run); 21 swapped, 0 dropped | IEX max step 26-543 ms: allocating the new texture (`create step`) is slow on WSLg; fill / swap steps cheap |
| v4 stored mips | IEX max step 7.2 ms | as above |
| vanilla, same scroll | longest frame 28-563 ms depending on load | longest frame 150-300 ms |

What remains in the longest frames is the engine's own page load: `CResPVR::Demand` inflates the PVRZ before upload
(logged: 15-38 ms for a 4096x4096 BC1 page, 1-5 ms for small ones), several pages when a new column comes into view.
That is HD data size, not IEX; a page prefetch or async inflate would be a separate hook.
WSLg: the texture allocation cost is a property of that GL-over-D3D12 layer; a native Linux driver was not available
to test. Vanilla rendering is unchanged (pixel diff `win_1x_zoom100_v4.png` vs v1: only sprites, text, clock); marked
4x after the swap is exact (`win_4x_marked_zoom025_v4.png`, `linux_4x_marked_zoom025_v3.png`).

Linux runner: `tools/hdtiles/run_linux.sh <build> <files> [steps]` runs the steps file (e.g. `scroll_bench.steps`) and
always closes the game at the end (`HD_KEEP=1` keeps it for screenshots; `--stop` closes it).

## Limits and next steps

- Mips are built by a worker thread (one core; ~100-300 ms per 4096 page), or taken from the PVRZ when stored.
- The mip levels below log2(scale) mix tile edges that no longer fall on whole texels (only the last level); the clamp
  limits it to the sampled footprint.
- Nearest neighbour scaling mode keeps the engine's tone 0 / 1 (`fpDraw` / `fpTone`): mipmapped with nearest-mip
  filtering, but no clamp (nearest sampling of level 0 never crosses the edge; coarse levels may by one texel).
- VRAM: 2x = 4x the page memory + 33 % mips (AR0602: 29 pages, ~80 MB at 2x BC1, ~320 MB at 4x). Default tier 2x.
- 16-bit texture coordinates: pages up to 8192 (8x of 1024) fit; larger would overflow.
- The second storage layout (hash-checked HD store outside override) is not implemented: it fits the same hook 1
  (decide the scale from the store instead of the TIS header) plus a `CResPVR` source switch.
