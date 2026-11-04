// libiex.so entry: loaded into the game process through LD_PRELOAD (Steam launch option:
//   LD_PRELOAD="$PWD/libiex.so:$LD_PRELOAD" %command%).
#include "iex_core.h"

#include <elf.h>
#include <link.h>
#include <unistd.h>

#include <climits>
#include <cstdint>
#include <cstdio>
#include <string>

namespace {

struct MainImage {
    std::uintptr_t base = 0;
    std::string buildId;
};

int ReadMainImage(dl_phdr_info* info, size_t, void* out)
{
    // The first entry is the main executable (PIE: its load bias is the image base).
    auto* image = static_cast<MainImage*>(out);
    image->base = info->dlpi_addr;
    for (int i = 0; i < info->dlpi_phnum; ++i) {
        const ElfW(Phdr)& ph = info->dlpi_phdr[i];
        if (ph.p_type != PT_NOTE)
            continue;
        auto p = info->dlpi_addr + ph.p_vaddr;
        const auto end = p + ph.p_memsz;
        while (p + sizeof(ElfW(Nhdr)) <= end) {
            const auto* note = reinterpret_cast<const ElfW(Nhdr)*>(p);
            const auto name = p + sizeof(ElfW(Nhdr));
            const auto desc = name + ((note->n_namesz + 3) & ~3u);
            if (note->n_type == NT_GNU_BUILD_ID) {
                const auto* bytes = reinterpret_cast<const unsigned char*>(desc);
                char hex[3];
                for (unsigned j = 0; j < note->n_descsz; ++j) {
                    std::snprintf(hex, sizeof(hex), "%02x", bytes[j]);
                    image->buildId += hex;
                }
                return 1;
            }
            p = desc + ((note->n_descsz + 3) & ~3u);
        }
    }
    return 1;
}

__attribute__((constructor)) void IexPreloadInit()
{
    char exe[PATH_MAX] = {};
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0)
        return;
    std::string path(exe, static_cast<size_t>(n));
    // Only attach to the game itself, not to helper processes started with the same environment.
    std::string name = path.substr(path.find_last_of('/') + 1);
    if (name != "BaldursGate" && name != "BaldursGateII" && name != "SiegeOfDragonspear")
        return;
    static std::string gameDir = path.substr(0, path.find_last_of('/'));
    static MainImage image;
    dl_iterate_phdr(ReadMainImage, &image);

    iex::HostInfo host;
    host.platform = "linux64";
    host.imageBase = image.base;
    host.gameDir = gameDir.c_str();
    host.buildId = image.buildId.c_str();
    iex::Startup(host);
}

} // namespace
