#include "startup_movies.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>

namespace iex {

namespace {

constexpr const char* kPlayMovie = "_ZN16CBaldurProjector9PlayMovieERK7CResRef";
constexpr const char* kPlayMovieNext = "_ZN16CBaldurProjector13PlayMovieNextERK7CResRef";
constexpr const char* kStartUpdate = "_ZN12CScreenStart23TimerAsynchronousUpdateEv";
constexpr const char* kGetProfileInt = "_Z22BGGetPrivateProfileIntPKcS0_i";  // Baldur.lua, loaded by the engine

using PlayFn = void (*)(void*, const void*);
using GetIntFn = int (*)(const char*, const char*, int);

bool g_env = false;  // IEX_SKIP_INTRO=1
std::uintptr_t g_playMovie = 0;
std::uintptr_t g_playMovieNext = 0;
GetIntFn g_getInt = nullptr;

// Read at each call (only the start screen's first update calls these sites): Baldur.lua is loaded by then.
bool Skip(const void* resref)
{
    if (!g_env && !(g_getInt && g_getInt("IEX", "Skip Intro Movies", 0) != 0))
        return false;
    char name[9] = {};
    if (resref)
        std::memcpy(name, resref, 8);  // CResRef: 8 inline chars
    Log("Skip Intro Movies: %s not played", name);
    return true;
}

// Both functions take (CBaldurProjector* this, CResRef const&): the first two integer arguments on both ABIs.
void HookPlayMovie(void* projector, const void* resref)
{
    if (!Skip(resref))
        reinterpret_cast<PlayFn>(g_playMovie)(projector, resref);
}

void HookPlayMovieNext(void* projector, const void* resref)
{
    if (!Skip(resref))
        reinterpret_cast<PlayFn>(g_playMovieNext)(projector, resref);
}

// Hooks the calls of `target` that lie inside [begin, end) (image-relative).
int HookCallsIn(const char* target, std::uint32_t begin, std::uint32_t end, const void* replacement)
{
    const std::uint32_t rva = engineTypes.Symbol(target);
    int n = 0;
    for (std::uint32_t site : engineTypes.CallSitesOf(target)) {
        if (site < begin || site >= end)
            continue;
        if (HookCallSite(EngineImageBase() + site, EngineImageBase() + rva, replacement))
            ++n;
        else
            Log("Skip Intro Movies: call site 0x%x of %s does not match", site, target);
    }
    return n;
}

} // namespace

void InstallStartupMovieHooks()
{
    const char* env = std::getenv("IEX_SKIP_INTRO");
    g_env = env && *env && *env != '0';
    const std::uint32_t start = engineTypes.Symbol(kStartUpdate);
    const std::uint32_t play = engineTypes.Symbol(kPlayMovie);
    const std::uint32_t next = engineTypes.Symbol(kPlayMovieNext);
    const std::uint32_t getInt = engineTypes.Symbol(kGetProfileInt);
    std::uint64_t size = 0;
    if (!start || !play || !next || !getInt ||
        !engineTypes.Const("CScreenStart.TimerAsynchronousUpdate.size", size)) {
        Log("Skip Intro Movies: engine description incomplete, disabled");
        return;
    }
    g_playMovie = EngineImageBase() + play;
    g_playMovieNext = EngineImageBase() + next;
    g_getInt = reinterpret_cast<GetIntFn>(EngineImageBase() + getInt);
    const std::uint32_t end = start + static_cast<std::uint32_t>(size);
    const int n = HookCallsIn(kPlayMovie, start, end, reinterpret_cast<const void*>(&HookPlayMovie)) +
                  HookCallsIn(kPlayMovieNext, start, end, reinterpret_cast<const void*>(&HookPlayMovieNext));
    Log("Skip Intro Movies: %d start screen movie calls hooked%s", n, g_env ? ", on (IEX_SKIP_INTRO)" : "");
}

} // namespace iex
