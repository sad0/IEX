#pragma once

// Memory primitives each platform layer implements (VirtualProtect/VirtualAlloc on Windows, mprotect/mmap on Linux).
#include <cstddef>
#include <cstdint>

namespace iex::platform {

// Executable memory within +-2 GiB of `nearAddr` (so rel32 jumps and calls can reach it). Never freed.
void* AllocExecNear(std::uintptr_t nearAddr, std::size_t size);

// Writes `size` bytes over code at `dst`, handling page protection and the instruction cache.
bool PatchCode(void* dst, const void* src, std::size_t size);

// Makes every executable segment of the game image writable (true) or restores it to read + execute (false),
// flushing the instruction cache on restore. Returns false if a segment could not be changed.
bool SetImageCodeWritable(bool writable);

// True if [address, address + size) is mapped readable (Linux: /proc/self/maps, cached, re-read on a miss).
// Windows: always true (unchanged EEex behaviour). Used by EEex_Read* / EEex_Write* to turn reads of addresses that
// only exist in the Windows build (mods' Windows byte probes) into a Lua error instead of a crash.
bool MemoryReadable(std::uintptr_t address, std::size_t size);
// Native library loading for EEex_LoadLibrary / EEex_GetProcAddressInternal (nullptr on failure).
void* LoadModule(const char* path);
void* ModuleSymbol(void* module, const char* name);
// OpenGL entry point of the game's GL library (Windows: opengl32.dll export, else wglGetProcAddress; Linux: the
// process symbol, else glXGetProcAddressARB). Call with the game's GL context current. nullptr if not found.
void* GlProc(const char* name);

} // namespace iex::platform
