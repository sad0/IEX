#include "platform_memory.h"

#include <dlfcn.h>

#include <link.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <utility>
#include <vector>

namespace iex::platform {

namespace {

std::uint8_t* g_block = nullptr;
std::size_t g_used = 0;
constexpr std::size_t kBlockSize = 0x10000;

std::uint8_t* AllocBlockNear(std::uintptr_t nearAddr)
{
    const std::uintptr_t page = static_cast<std::uintptr_t>(sysconf(_SC_PAGESIZE));
    const std::uintptr_t start = nearAddr & ~(page - 1);
    // Probe hint addresses downwards then upwards, within 1.5 GiB so rel32 always reaches.
    for (std::uintptr_t delta = 0x100000; delta < 0x60000000; delta += 0x100000) {
        const std::uintptr_t candidates[2] = {start - delta, start + delta};
        for (std::uintptr_t candidate : candidates) {
            void* p = mmap(reinterpret_cast<void*>(candidate), kBlockSize, PROT_READ | PROT_WRITE | PROT_EXEC,
                           MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
            if (p != MAP_FAILED)
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
        const auto dist = reinterpret_cast<std::intptr_t>(p) - static_cast<std::intptr_t>(nearAddr);
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
    const std::uintptr_t page = static_cast<std::uintptr_t>(sysconf(_SC_PAGESIZE));
    const std::uintptr_t first = reinterpret_cast<std::uintptr_t>(dst) & ~(page - 1);
    const std::uintptr_t last = (reinterpret_cast<std::uintptr_t>(dst) + size + page - 1) & ~(page - 1);
    if (mprotect(reinterpret_cast<void*>(first), last - first, PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
        return false;
    std::memcpy(dst, src, size);
    mprotect(reinterpret_cast<void*>(first), last - first, PROT_READ | PROT_EXEC);
    __builtin___clear_cache(static_cast<char*>(dst), static_cast<char*>(dst) + size);
    return true;
}

bool SetImageCodeWritable(bool writable)
{
    struct Request {
        bool writable;
        bool ok;
    } request{writable, false};
    // The first object dl_iterate_phdr reports is the main executable.
    dl_iterate_phdr(
        [](dl_phdr_info* info, std::size_t, void* data) -> int {
            auto* r = static_cast<Request*>(data);
            const std::uintptr_t page = static_cast<std::uintptr_t>(sysconf(_SC_PAGESIZE));
            r->ok = true;
            for (int i = 0; i < info->dlpi_phnum; ++i) {
                const ElfW(Phdr)& ph = info->dlpi_phdr[i];
                if (ph.p_type != PT_LOAD || !(ph.p_flags & PF_X))
                    continue;
                const std::uintptr_t start = (info->dlpi_addr + ph.p_vaddr) & ~(page - 1);
                const std::uintptr_t end = (info->dlpi_addr + ph.p_vaddr + ph.p_memsz + page - 1) & ~(page - 1);
                const int prot = PROT_READ | PROT_EXEC | (r->writable || (ph.p_flags & PF_W) ? PROT_WRITE : 0);
                if (mprotect(reinterpret_cast<void*>(start), end - start, prot) != 0)
                    r->ok = false;
                else if (!r->writable)
                    __builtin___clear_cache(reinterpret_cast<char*>(start), reinterpret_cast<char*>(end));
            }
            return 1;  // main executable only
        },
        &request);
    return request.ok;
}

namespace {

// Readable regions of the process (merged runs of /proc/self/maps lines with 'r'), re-read on a miss.
std::mutex g_mapsMutex;
std::vector<std::pair<std::uintptr_t, std::uintptr_t>> g_readable;

void ReloadMaps()
{
    g_readable.clear();
    std::FILE* f = std::fopen("/proc/self/maps", "r");
    if (!f)
        return;
    char line[512];
    while (std::fgets(line, sizeof(line), f)) {
        unsigned long long start = 0, end = 0;
        char perms[8] = {};
        if (std::sscanf(line, "%llx-%llx %7s", &start, &end, perms) != 3 || perms[0] != 'r')
            continue;
        if (!g_readable.empty() && g_readable.back().second == start)
            g_readable.back().second = end;
        else
            g_readable.emplace_back(start, end);
    }
    std::fclose(f);
}

bool InReadable(std::uintptr_t address, std::size_t size)
{
    auto it = std::upper_bound(g_readable.begin(), g_readable.end(), address,
                               [](std::uintptr_t a, const auto& r) { return a < r.first; });
    if (it == g_readable.begin())
        return false;
    --it;
    return address >= it->first && address + size <= it->second && address + size >= address;
}

} // namespace

bool MemoryReadable(std::uintptr_t address, std::size_t size)
{
    std::lock_guard<std::mutex> lock(g_mapsMutex);
    if (InReadable(address, size))
        return true;
    ReloadMaps();
    return InReadable(address, size);
}

void* LoadModule(const char* path)
{
    return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}

void* ModuleSymbol(void* module, const char* name)
{
    return module ? dlsym(module, name) : nullptr;
}

void* GlProc(const char* name)
{
    if (void* p = dlsym(RTLD_DEFAULT, name))
        return p;
    using GlxGet = void* (*)(const unsigned char*);
    auto glxGet = reinterpret_cast<GlxGet>(dlsym(RTLD_DEFAULT, "glXGetProcAddressARB"));
    return glxGet ? glxGet(reinterpret_cast<const unsigned char*>(name)) : nullptr;
}

} // namespace iex::platform
