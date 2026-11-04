#pragma once

#include <cstddef>
#include <cstdint>

namespace iex {

// Makes the engine decode effects with unknown opcodes (EEex opcodes 400-409 in modded saves) as inert effects
// instead of crashing. See docs/EFFECTS_DECODE.md.
void InstallEffectHooks();

// Decodes an effect like the engine does, with unknown opcodes decoded as inert effects (after InstallEffectHooks).
std::uintptr_t DecodeEffectAny(std::uintptr_t item, std::uintptr_t source, std::uintptr_t sourceId,
                               std::uintptr_t target, std::uintptr_t arg5);
// Replaces one slot (byte offset from the address point) of the inert effects' vtable (e.g. ApplyEffect).
bool SetInertSlot(std::size_t slotOffset, const void* fn);
// Current function of that slot (0 if the inert vtable is not built).
std::uintptr_t GetInertSlot(std::size_t slotOffset);

} // namespace iex
