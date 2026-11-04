#pragma once

// Call-site hooks: redirect one `call rel32` (E8) instruction of the engine to our function.
// The original callee is left untouched, so a hook simply calls it through its address.
// This avoids relocating function prologues, and works the same on every x86-64 platform.
#include <cstdint>

namespace iex {

// `site` is the address of the E8 opcode; `expectedTarget` is the function it must currently call.
// Returns false (and changes nothing) if the bytes don't match.
bool HookCallSite(std::uintptr_t site, std::uintptr_t expectedTarget, const void* replacement);

// Same for a tail jump (`jmp rel32`, E9) to `expectedTarget`: the jump to our function keeps the caller's return
// address, so the same replacement as for a call works.
bool HookJumpSite(std::uintptr_t site, std::uintptr_t expectedTarget, const void* replacement);

// Function replacement: true if the first 8 bytes of the function at `fn` still equal `expectedPrologue`
// (little-endian u64 taken from the unmodified game binary). A jmp or any other foreign patch makes it false.
bool FunctionEntryIntact(std::uintptr_t fn, std::uint64_t expectedPrologue);

// Writes `jmp replacement` over the first 5 bytes of the function at `fn` (through a thunk near the image).
// Every caller, direct or indirect, then runs `replacement`; the original body is no longer callable.
// Returns false (and changes nothing) when FunctionEntryIntact fails.
bool HookFunctionEntry(std::uintptr_t fn, std::uint64_t expectedPrologue, const void* replacement);

} // namespace iex
