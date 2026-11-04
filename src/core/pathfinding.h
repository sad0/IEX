#pragma once

// Pathfinding Redux, native (docs/API_SPEC.md, "Allied pass-through movement"): party members and other allies
// (EA 2-30) walk through one another. Re-implements, in IEX's own C++ hooks, the movement policy of the
// BG Pathfinding Redux mod (Zach Hopkins, MIT licence), whose own runtime needs EEex's x64 assembly API.
// Walls, doors, neutrals and enemies keep their native blocking.
//
// Engine model (both builds, from the binaries): CSearchBitmap (CGameArea + 0xa60) keeps one byte per 16x12
// search cell (m_pDynamicCost): bit 7 and bit 0 = non-creature obstruction, bits 1-3 / 4-6 = two 3-bit creature
// counts, incremented / decremented modulo 8 by AddObject / RemoveObject over a creature's footprint (the low
// counter for a non-zero creature category, the high one otherwise). GetCost / GetMobileCost and the walk step
// read those counts. Path searches run in SearchThreadMain, called from CChitin::Update on the main thread: it
// copies the counts into a private snapshot (CSearchBitmap + 0x128), removes the mover's own footprint, then
// calls CPathSearch::FindPath on it.
//
// IEX hooks, for an eligible mover (allied, normal-sized, in an area):
//  - CGameSprite::AIUpdateWalk and CGameSprite::SetTarget(CSearchRequest*) call sites: while the call runs, the
//    footprints of the other allies are subtracted from the live counts on the cells whose occupancy they account
//    for completely (every painted creature covering the cell is the mover or an eligible ally, and the counts
//    match), then added back. Additions and subtractions are modulo 8 like the engine's, so the restore is exact
//    whatever the engine itself changed in between. Covers the walk step cost, the moving-creature wait, the bump
//    trigger and the synchronous route checks (destination cost, direct-line walkability).
//  - CPathSearch::FindPath call in SearchThreadMain: the same fully-allied cells are cleared in the request's
//    private snapshot (idempotent: the engine's own removals are never subtracted twice).

struct lua_State;

namespace iex {

void InstallPathfindingHooks();

// Footprint size the search map really gets for a creature of personal space `size` (native_hooks_sado.cpp:
// SadoEE's small footprint shrinks or drops the footprint of bumpable creatures); 0 = nothing stamped.
int SearchFootprintSize(int size, bool bumpable);
void OpenLuaPathfinding(lua_State* L);

} // namespace iex
