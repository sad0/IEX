#pragma once

// Party vision without the engine's 15-viewer cap (docs/API_SPEC.md, "Fog of war: unlimited viewers").
// The engine keeps 15 viewer ids per area visibility map and an 8-bit viewer mask per tile, so viewers past the
// 8th clear no fog and viewers past the 15th are not on the map at all. IEX replaces the visibility map's viewer
// functions with its own bookkeeping: every viewer (party member, clairvoyance object...) gets its visible tiles
// from the engine's own line-of-sight code, and each tile keeps a count of the viewers that see it.

struct lua_State;

namespace iex {

// Installs the CVisibilityMap / CheckIfVisible hooks (on by default). All-or-nothing: if one required site is
// missing from the engine description or was patched by something else, nothing is changed.
void InstallVisionHooks();

// True once the hooks are installed (IEX_Features.partyVision).
bool VisionActive();

// Registers IEX_Features.partyVision and the IEX_Vision* inspection functions.
void OpenLuaVision(lua_State* L);

} // namespace iex
