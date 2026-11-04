# HD creature sprites at their original in-world size (study, no implementation)

Date: 2026-11-03. Branch `feature/hd-tiles`. Status: **for the maintainer's review**. Companion of `docs/HD_TILES.md` and of
the HD feasibility study (draw layer, texture table, renderer backends). Clean room: own analysis of
`BaldursGateII` (symbols, Ghidra) and `Baldur.exe`, public BAM / PLT format docs (IESDP). Linux VAs unless noted.

## Summary

- **Recommendation:** HD frames stored as **8-bit palette indices at N x the size** (a sidecar resource next to the
  1x BAM, the BAM itself unchanged), uploaded once per frame as a single-channel (R8) GPU texture, and drawn with a
  **palette-lookup shader**: the engine keeps realising its 256-colour palette on the CPU exactly as today (colour
  ranges, tint, light, add, effects), IEX uploads those 256 entries as a 256x1 texture per draw and the fragment
  shader does `palette[index]`. Same quad, same world rectangle, same frame centre (in 1x units) as the engine's.
- Why: creature colours come from the palette path (`CVidPalette::Realize` / `RealizeRange`: MPALETTE colour
  ranges of the CRE, op 7 / 8 / 50-52 tints and glows, light, day/night), and that path works on indices. A plain
  RGBA PVRZ (what TIS / MOS V2 do) cannot be recoloured per creature. Indices keep every colour feature for free,
  because the palette code is not touched.
- **Cost:** VRAM 1 byte per HD texel (2x frame of 128x128 1x = 64 KB) instead of the engine's per-draw 32-bit CPU
  expansion; CPU per draw drops from `w*h` palette lookups (`Blt8To32`) to one 1 KB palette upload. GPU cost: one
  dependent texture read per pixel. Disk: about N^2 x the BAM's frame data (compressible, RLE / zlib).
- **Main risks:** the CPU-side wall cover (`CVidPoly::FillPoly` writes a mask colour into the expanded frame), every
  shader variant the engine uses for sprites (tone, blur, outline, translucency) needs a palette twin, the 512 px
  frame cap and staging texture size, and **art**: there are no HD sources for the BG2 creature animations.
- Linux parity: the same `_GL` draw functions and shaders on both builds; only Direct3D 9 (Windows `Backend 1`) is
  out (stays 1x, as for tiles).

## 1. How a creature frame is drawn today (2.7.3)

1. `CGameSprite::Render` (0x4bb000, Win 0x36ba50) -> the animation class `Render` (`CGameAnimationTypeCharacter::Render`
   0x401650, `...Monster::Render` 0x3fe060, `...MonsterLayered` 0x4000d0, 16 classes in all) -> for each layer
   (body, weapon, shield, helmet; character paperdolls are several BAMs) `CVidCell::Render3d` / `FXRender3d`
   (0x5b78d0 / 0x5b84e0) or `CInfinity::FXRender` (0x31b760) for blur / translucent / mirror images.
2. `CVidCell::Render3d(x, y, clip, coverPolys, nPolys, flags, alpha)`:
   - frame header (`this + 0x128`: width, height, centre x / y); **`0x200 < w || 0x200 < h` -> not drawn**;
   - a BAM V2 / PVR frame (`res + 0x70` set) goes to its own textured path (`FUN_006b6ec0`), no palette;
   - else `CVidPalette::SetPalette` (the BAM's 256 entries) and `CVidPalette::Realize(rgbTempPal, flags | 0x4001,
     affect = this + 0x38, alpha)` (0x5bd2f0 -> `RealizeRange` 0x5bd6f0: colour ranges, `GetTint` / `GetAdd` /
     `GetLight` 0x5bd3c0 / 0x5bd4d0 / 0x5bd5c0); entry 0 transparent, entry 1 = shadow (alpha); "colour blind" debug
     fill when `g_pChitin + 0x198`;
   - `DrawLockSurface(w + 2, h + 2, NEAREST or LINEAR)` = one of the two 1024x1024 staging textures, then
     **`CVidCell::Blt8To32`** (0x5ccb10): every index of the RLE frame through `rgbTempPal` into 32-bit texels;
   - **wall cover**: `CVidPoly::FillPoly(..., 0xff00ff00)` paints each cover polygon (from
     `CGameSprite::RenderSpriteCover` 0x46c440, WED wall polygons in front of the sprite) as transparent into the
     expanded frame;
   - `CVidCell::RenderTexture` (0x5b7410 / 0x5b7600): one quad in world units with the frame size, colour / alpha in
     the vertex colour, tone (`DrawColorTone`: grey for petrification / stoneskin-like effects, the sprite shaders
     `fpSprite` with blur offsets, `fpSELECT` outline for selection highlights).
3. Selection circles, markers, health bars: `CGameSprite::RenderMarkers` (0x465d20) -> `CVidMode::DrawEllipse` and
   friends: untextured geometry in world units, **not** part of the frame (unchanged by HD sprites).
4. Effect animations on the sprite (`CGameSprite::RenderSpriteEffect` 0x46d360, `CGameAnimationTypeEffect::Render`
   0x3d1140): the same `CVidCell` path with their own BAMs (VVC / BAM effects can use the same HD mechanism later).

## 2. Hook points

| Point | Purpose | Kind |
|---|---|---|
| `CVidCell::Render3d` / `FXRender3d` entry (or their callers in the animation classes) | detect "this frame has an HD sidecar", take over the draw | function or call-site hook, same arguments |
| After the engine's `CVidPalette::Realize` in that call | take `rgbTempPal` (256 x 32-bit) as the palette texture | IEX calls `Realize` itself with the same arguments (it is a plain function), the engine code is not modified |
| `CVidCell::Blt8To32` | skipped for HD frames (the expensive part) | not called by the HD path |
| `CVidPoly::FillPoly` (cover polygons) | wall cover for HD: render the same polygons, scaled by N, into an HD R8 mask (or draw them into the stencil buffer before the quad) | IEX code, polygons from the engine's arguments |
| `CVidCell::RenderTexture` | the quad: same world rect / centre / clip, texture coordinates over the HD frame (`u * N`, as for tiles) | IEX draws it with the engine's Draw* functions |
| `DrawCreateProgram_GL` (0x56f390) | add palette twins of `fpDraw`, `fpTone`, `fpSprite`, `fpSELECT` (`texture2D(uPal, vec2(texture2D(uIdx, vTc).r * 255/256 + 1/512, 0.5))`) | IEX program sources, only when the feature is on |
| BAM loading (`CResCell::Parse` 0x576440, `CResCell::GetFrame` 0x5814d0) | find the sidecar for a BAM resref, map BAM frame index -> HD frame | resource lookup, no change to the BAM |
| `CVidCell::FrameSet` / sequence | unchanged: the HD frame index is the BAM's frame index | - |

All draw-side and C++ (no asm API). The palette path, the animation classes, the frame / sequence logic, the
bounding boxes (`CalculateFxRect`), click detection (`CGameSprite::IsOver` uses the 1x frame) stay engine code.

## 3. Format proposal

- **Sidecar resource `<BAM>.HDB`** (new extension, resource type number to choose, read from `override/` or the
  future hash-checked HD store), one per 1x BAM:
  - header: signature `HDB `, version, **scale N** (2 / 4 / 8), frame count (= the BAM's), CRC32 of the 1x BAM's
    frame table (stale sidecar -> ignored, 1x drawn), flags;
  - per frame: width / height in HD texels (= 1x size x N, so centre and size stay exact in 1x units), data offset,
    compression (none / RLE of index 0 like BAM V1 / zlib);
  - pixel data: **8-bit indices into the BAM's own palette** (the BAM V1 palette and colour-range convention, so
    MPALETTE ranges 4-11 etc. keep working), index 0 transparent, 1 shadow.
- Optional per-frame alpha plane (8-bit) for soft edges; without it edges are as hard as today.
- Paperdolls: one sidecar per layer BAM (body, weapon, shield, helmet), so armour / weapon changes keep working.
- PLT (paperdoll in the inventory): out of scope; it is a UI asset.
- No change to BAM, CRE, ANI or 2DA files: a mod never sees the sidecar.

## 4. Memory and draw cost

| | Engine today (1x) | HD index path (2x) | HD RGBA path (2x, rejected) |
|---|---|---|---|
| CPU per drawn frame | palette realise (256 entries) + `Blt8To32` w*h + cover fill | palette realise + 1 KB upload (+ cover polys) | none, but no colour ranges |
| VRAM per cached frame | 0 (staging texture reused) | w*h*4 bytes (R8, N=2) | w*h*16 bytes |
| GPU per pixel | 1 texture read | 2 reads (index, palette) | 1 |
| Disk | BAM | + about 4x the frame data (compressed) | + 16x |

Order of magnitude: a character with 4 layers, 8 directions x ~10 sequences x ~10 frames, average 1x frame 60x90:
~3200 frames x 5400 texels x 4 (2x) = ~70 MB of R8 if all were resident. Only the frames drawn recently need to be
on the GPU: an LRU texture cache sized in MB (and the 512-slot texture table of the draw layer is the hard limit: an
atlas per animation, not one texture per frame).

## 5. Risks

1. **Cover polygons** are applied on the CPU to the expanded frame. The HD path must reproduce them exactly (scaled
   polygons into a mask, or stencil); a mismatch shows sprites through walls or cut wrongly.
2. **Shader variants**: grey tone (petrify), blur (`fpSprite` offsets), the outline / highlight (`fpSELECT`, in
   logical texels: keep 1x units), translucency / invisibility alpha, mirror images, additive effects. Each needs its
   palette twin; a missed one draws the 1x look or the wrong colours. The D3D9 `DX*` effects have no twin (stays 1x).
3. **512 px cap / staging textures**: the HD path does not use the staging textures, so the 1x cap stays the
   engine's decision (an HD frame of a 1x frame > 512 is not drawn either, same as today).
4. **Animation classes**: 16 `CGameAnimationType*::Render` variants, some with their own palette tricks (Icewind
   monsters, layered spells). Hooking at `CVidCell` level keeps them unchanged, but each must be checked in game.
5. **Art availability**: no HD sources exist for BG2's creature renders; upscalers on 8-bit palette art need a
   re-quantisation to the BAM palette (and to the colour-range slots), which is the hardest part for creators.
6. **Palette uploads**: one 256x1 texture update per drawn layer; with many creatures that is many small uploads per
   frame (a palette atlas of 256 x 64 rows per frame batch avoids stalls).

## 6. Linux parity

Same draw layer (`Draw*_GL`), same shaders (game resources `fpDraw`, `fpSprite`...), same `CVidCell` code and symbols
on Linux, where the functions are named; Windows addresses come from the matching tables plus checks like the tile
work. Expected effort per platform the same; tests on both (WSLg runs the same OpenGL path).

## 7. Suggested next step

A one-creature prototype behind a switch (`hdSprites`), one animation (e.g. a monster without paperdoll layers),
sidecar made by a script (index-preserving 2x of the 1x frames, i.e. visually identical, plus a marked variant as
for tiles), to measure the cost and check the cover / tone / outline paths before any format freeze.
