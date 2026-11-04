#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "platform_memory.h"

#include <cstring>

namespace iex::platform {

namespace {

// Thunks are small: carve them out of 64 KiB blocks allocated near the image.
std::uint8_t* g_block = nullptr;
std::size_t g_used = 0;
constexpr std::size_t kBlockSize = 0x10000;

std::uint8_t* AllocBlockNear(std::uintptr_t nearAddr)
{
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    const std::uintptr_t gran = si.dwAllocationGranularity;
    const std::uintptr_t start = nearAddr & ~(gran - 1);
    // Search downwards then upwards, within 1.5 GiB so rel32 always reaches.
    for (std::uintptr_t delta = gran; delta < 0x60000000; delta += gran) {
        const std::uintptr_t candidates[2] = {start - delta, start + delta};
        for (std::uintptr_t candidate : candidates) {
            void* p = VirtualAlloc(reinterpret_cast<void*>(candidate), kBlockSize, MEM_RESERVE | MEM_COMMIT,
                                   PAGE_EXECUTE_READWRITE);
            if (p)
                return static_cast<std::uint8_t*>(p);
        }
    }
    return nullptr;
}

} // namespace

void* AllocExecNear(std::uintptr_t nearAddr, std::size_t size)
{
    size = (size + 15) & ~std::size_t(15);
    const auto inReach = [nearAddr](std::uint8_t* p) {
        const auto addr = reinterpret_cast<std::intptr_t>(p);
        const auto dist = addr - static_cast<std::intptr_t>(nearAddr);
        return dist > -0x70000000LL && dist < 0x70000000LL;
    };
    if (!g_block || g_used + size > kBlockSize || !inReach(g_block)) {
        g_block = AllocBlockNear(nearAddr);
        g_used = 0;
        if (!g_block)
            return nullptr;
    }
    void* p = g_block + g_used;
    g_used += size;
    return p;
}

bool PatchCode(void* dst, const void* src, std::size_t size)
{
    DWORD old;
    if (!VirtualProtect(dst, size, PAGE_EXECUTE_READWRITE, &old))
        return false;
    std::memcpy(dst, src, size);
    VirtualProtect(dst, size, old, &old);
    FlushInstructionCache(GetCurrentProcess(), dst, size);
    return true;
}

bool SetImageCodeWritable(bool writable)
{
    const auto base = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
    bool ok = true;
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
        if (!(section->Characteristics & IMAGE_SCN_MEM_EXECUTE))
            continue;
        const DWORD size = section->Misc.VirtualSize ? section->Misc.VirtualSize : section->SizeOfRawData;
        const bool alsoWritable = section->Characteristics & IMAGE_SCN_MEM_WRITE;
        const DWORD protect = writable || alsoWritable ? PAGE_EXECUTE_READWRITE : PAGE_EXECUTE_READ;
        DWORD old;
        if (!VirtualProtect(base + section->VirtualAddress, size, protect, &old))
            ok = false;
        else if (!writable)
            FlushInstructionCache(GetCurrentProcess(), base + section->VirtualAddress, size);
    }
    return ok;
}

bool MemoryReadable(std::uintptr_t, std::size_t)
{
    return true;  // as EEex: a bad address crashes (every address SadoEE / EEex mods probe is mapped on Windows)
}

void* LoadModule(const char* path)
{
    return LoadLibraryA(path);
}

void* ModuleSymbol(void* module, const char* name)
{
    return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(module), name));
}

void* GlProc(const char* name)
{
    HMODULE gl = GetModuleHandleW(L"opengl32.dll");
    if (!gl)
        return nullptr;
    if (void* p = reinterpret_cast<void*>(GetProcAddress(gl, name)))
        return p;
    using WglGet = PROC(WINAPI*)(LPCSTR);
    auto wglGet = reinterpret_cast<WglGet>(reinterpret_cast<void*>(GetProcAddress(gl, "wglGetProcAddress")));
    if (!wglGet)
        return nullptr;
    void* p = reinterpret_cast<void*>(wglGet(name));
    // wglGetProcAddress may return small error values instead of nullptr
    const auto v = reinterpret_cast<std::uintptr_t>(p);
    return v <= 3 || v == static_cast<std::uintptr_t>(-1) ? nullptr : p;
}

} // namespace iex::platform
