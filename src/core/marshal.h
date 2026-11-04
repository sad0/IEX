#pragma once

// Per-creature mod data saved with the game (EEex_Sprite_AddMarshalHandlers, Lua side in lua/EEex_Marshal.lua),
// written where EEex 1.3.1 writes it so saves move between EEex and IEX both ways:
//   - CGameSprite::Marshal (save, area store, character export, creature copy): after the engine marshalled the
//     creature's effect list, IEX_Marshal_Export(sprite) -> byte string (or nil); the bytes are appended to the
//     list as pseudo effect records (0x108 bytes each), the first one starting with "X-BIV1.0";
//   - CGameSprite::Unmarshal (V2 effect records): the records from the "X-BIV1.0" one on are cut off the list
//     before the engine decodes it, and IEX_Marshal_Import(sprite, bytes or nil) runs (inside the creature's
//     constructor, before the loaded listeners).
//   - IEX_IsMarshallingCopy(): true while CGameSprite::Copy marshals a creature to clone it (EEex.IsMarshallingCopy).
struct lua_State;

namespace iex {

void OpenLuaMarshal(lua_State* L);
void InstallMarshalHooks();

} // namespace iex
