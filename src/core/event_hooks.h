#pragma once

#include <cstdint>

namespace iex {

// The sprite whose SpriteLoaded listeners are running from inside its constructor (0 otherwise): its name and
// most derived data are not set yet (IEX_SpriteName gives "" for it, like EEex).
extern std::uintptr_t g_spriteUnderConstruction;

// Installs the engine hooks that feed IEX events (menu loaded, game state ready, sprite loaded, keys).
// Each hook is skipped (and logged) when the engine description has no call site for it.
void InstallEventHooks();

// True once the CGameObjectArray::Add call sites go through IEX (the objectIdRecycling engine fix needs it).
bool ObjectArrayAddHooked();

} // namespace iex
