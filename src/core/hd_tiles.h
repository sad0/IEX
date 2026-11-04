#pragma once

// HD area tiles (native switch "hdTiles", docs/HD_TILES.md).
//
// Area tiles of a PVRZ-based TIS (TIS V1 with 12-byte tile entries: PVRZ page, x, y) are drawn by
// CVidTile::RenderTexture as a 64x64 world-space quad whose texture coordinates are x .. x+64, y .. y+64 texels of
// the page. The draw layer normalises texture coordinates by the size of the uploaded texture, so a bigger PVRZ page
// needs no change there.
//
// Format (public convention of InfinityEngine-Enhancer): the tile size of the TIS header (+0x14) is 64, 128, 256
// or 512 = 1x, 2x, 4x, 8x. The entries' x / y are texel positions in the (bigger) PVRZ pages. ARE / WED and every
// world coordinate stay 1x.
//
// With the switch, the CVidTile::RenderTexture calls of CInfTileSet::Render go through IEX. For a tile whose TIS
// says 64 (every vanilla TIS) or anything other than 128/256/512, the engine function runs unchanged with the same
// arguments. For an HD tile, the engine function still runs (same quad, state, tone, alpha), and only its six
// DrawTexCoord calls are scaled around the tile origin: x + (u - x) * scale. The engine's tile seam shader (fpSEAM,
// "Use Nearest Neighbour Scaling" off) assumes 64-texel tiles: IEX rewrites its sources at build time (1x path unchanged,
// HD path = clamped trilinear sampling of a mip chain IEX builds for HD pages); fallback: the plain tone (see
// the doc); its pages get GL_LINEAR instead of the engine's GL_NEAREST (CResTileSet::SetTile hook) unless the player
// chose "Use Nearest Neighbour Scaling". OpenGL only: with the Direct3D 9 backend (Windows Baldur.lua Graphics/Backend 1) tiles stay 1x.

struct lua_State;

namespace iex {

// Registers the "hdTiles" installer.
void InstallHdTileHooks();

// IEX_HdTiles_Stats().
void OpenLuaHdTiles(lua_State* L);

} // namespace iex
