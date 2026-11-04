// Render frame rate decoupled from the logic tick rate (docs/FRAMERATE.md).
//
// CChitin::Update = one logic tick (AsynchronousUpdate) + one rendered frame (SynchronousUpdate), then
// SDL_Delay(1000 / TIMER_UPDATES_PER_SECOND - time spent). IEX replaces that one SDL_Delay call: the idle time
// is cut into slots of 1000 / target fps ms, and the engine's own render path (CBaldurChitin::SynchronousUpdate:
// clear, active screen's TimerSynchronousUpdate + RenderUI, flip) runs once per slot. No logic code runs in the
// extra frames, so the game speed is unchanged. When the target is below the tick rate, Update's own frame is
// skipped until the next one is due (CBaldurChitin vtable slot 0), so a vsync'd flip never slows the logic down.
// Ticks are paced on a fixed schedule (a late tick shortens the next waits), so the average tick rate is exact.
#include "framerate.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "platform_memory.h"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <unordered_map>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kDelay = "SDL_Delay";
constexpr const char* kPerfCounter = "SDL_GetPerformanceCounter";
constexpr const char* kPerfFrequency = "SDL_GetPerformanceFrequency";
constexpr const char* kDesktopMode = "SDL_GetDesktopDisplayMode";
constexpr const char* kSyncUpdate = "_ZN13CBaldurChitin17SynchronousUpdateEv";  // CBaldurChitin::SynchronousUpdate()
constexpr const char* kTicksPerSecond = "_ZN7CChitin24TIMER_UPDATES_PER_SECONDE";  // uint, "Maximum Frame Rate"
constexpr const char* kChitin = "g_pBaldurChitin";                                 // CBaldurChitin*

constexpr const char* kRenderSlot = "IEX_VtSlot_ChitinSynchronousUpdate";  // CBaldurChitin vtable slot 0
constexpr const char* kGetSwap = "SDL_GL_GetSwapInterval";
constexpr const char* kSetSwap = "SDL_GL_SetSwapInterval";

constexpr int kMaxFrameRate = 1000;  // also "no limit" (EEex 'Uncap FPS' with VSync and the limit off)

void (*g_delay)(std::uint32_t) = nullptr;
std::uint64_t (*g_counter)() = nullptr;
double g_ticksPerMs = 0;
void (*g_render)(Word) = nullptr;
const std::uint32_t* g_tps = nullptr;
const Word* g_chitin = nullptr;
std::uint64_t g_inSyncFlag = 0;     // CChitin field the engine sets to 1 around its render call
std::uint64_t g_fpsField = 0;       // CChitin: frames drawn in the last second (engine counter)
std::uint64_t g_tpsField = 0;       // CChitin: logic ticks in the last second (engine counter)
bool g_hooked = false;

int g_target = 0;          // requested render rate, 0 = off (engine default: one frame per tick)
int g_floor = 0;           // render rate mods asked for through TIMER_UPDATES_PER_SECOND (Keep Game Speed)
double g_paceStart = 0;    // scheduled start of the current tick (ms), 0 = not pacing
double g_nextFrame = 0;    // when Update's own frame is next due (target below the tick rate)
double g_busyWaitMs = 1;   // the last part of a wait is spun ('Uncap FPS Busy Wait Threshold')
std::uint64_t g_skipped = 0;  // Update frames skipped (target below the tick rate)
Word g_origRender = 0;     // original CBaldurChitin vtable slot 0
int (*g_getSwap)() = nullptr;
int (*g_setSwap)(int) = nullptr;
int g_vsyncWanted = -1;    // -1: the engine's own swap interval, 0 / 1: forced ('VSync Enabled')
int g_vsyncOriginal = -2;  // swap interval before IEX changed it (-2: never changed)
bool g_refreshMode = false;  // g_target follows the window display's refresh rate (IEX_SetFrameRate(-1))
int g_refreshCap = 0;
double g_refreshChecked = 0;
int DesktopRefreshRate();

// Render rate actually used: the player's setting; without one (EEex 'Uncap FPS' off, no IEX 'Frame Rate'), the
// rate a mod asked for when it is above the tick rate; else 0 = the engine's one frame per tick.
int Target()
{
    if (g_target > 0)
        return g_target;
    const std::uint32_t tps = g_tps ? *g_tps : 0;
    return static_cast<std::uint32_t>(g_floor) > tps ? g_floor : 0;
}

// Frame clock: when the next frame is due (ms, 0 = now). Update's own frame and the frames drawn while a tick
// waits all follow it, so the frame rate is the target whatever its ratio to the tick rate (45 fps at 30 ticks/s).
void AdvanceFrameClock(double now, double interval)
{
    g_nextFrame = (g_nextFrame <= 0 || now - g_nextFrame > interval) ? now + interval : g_nextFrame + interval;
}

// --- Motion interpolation state (see the "Motion interpolation" section below) ---
constexpr const char* kGetShare = "_ZN16CGameObjectArray8GetShareEiPP11CGameObjectb";
constexpr int kSnapDistance = 128;   // px: a larger move between two ticks is a jump (teleport, area change)
constexpr int kMaxSpan = 2;          // ticks: longest interval a position change is spread over
constexpr std::uint64_t kForgetTicks = 8;  // an object unseen for longer starts again without interpolation

std::uint8_t (*g_getShare)(int, Word*, bool) = nullptr;
std::uint32_t g_posOffset = 0;       // CGameObject.m_pos (CPoint x, y)
std::uint32_t g_posZOffset = 0;      // CGameObject.m_posZ
std::uint32_t g_areaOffset = 0;      // CGameObject.m_pArea
std::uint32_t g_listOffsets[4] = {};  // CGameArea vertical lists drawn by CGameArea::Render (CPtrList of ids)
bool g_interpReady = false;
bool g_interpOption = true;          // IEX_SetFrameInterpolation / Baldur.lua [IEX] "Frame Interpolation"
std::uint64_t g_serial = 0;          // logic ticks run (CChitin::Update calls)
double g_phase = 0;                  // position of the frame being drawn inside the tick: 0 = tick frame
bool g_inExtraFrame = false;

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

double NowMs()
{
    return static_cast<double>(g_counter()) / g_ticksPerMs;
}

void WaitUntil(double t)
{
    for (;;) {
        const double left = t - NowMs();
        if (left <= 0)
            return;
        // SDL_Delay has ~1 ms granularity: sleep whole ms, yield-spin the last g_busyWaitMs.
        g_delay(left >= g_busyWaitMs + 0.5 ? static_cast<std::uint32_t>(left - g_busyWaitMs) : 0);
    }
}

void RenderExtraFrame(double phase)
{
    const Word chitin = *g_chitin;
    if (!chitin)
        return;
    auto* inSync = reinterpret_cast<std::int32_t*>(chitin + g_inSyncFlag);
    const std::int32_t saved = *inSync;
    *inSync = 1;
    g_phase = phase;
    g_inExtraFrame = true;
    g_render(chitin);
    g_inExtraFrame = false;
    g_phase = 0;
    *inSync = saved;
}

// Replaces SDL_Delay(ms) at the end of CChitin::Update; `ms` is what is left of the current tick.
void HookUpdateDelay(std::uint32_t ms)
{
    const std::uint32_t tps = *g_tps;
    const int target = Target();
    if (target <= 0 || tps == 0 || g_paceStart <= 0 || !*g_chitin) {
        g_delay(ms);
        return;
    }
    const double tick = 1000.0 / tps;
    // The tick ends on its schedule: time earlier ticks ran late (a vsync'd flip blocking until the next vblank,
    // a long frame) is taken off this wait, so the average tick rate stays exact.
    const double tickStart = g_paceStart;
    const double deadline = tickStart + tick;
    const double interval = 1000.0 / target;
    // Frames due before the tick ends (a frame due within 1 ms of the end is left to the next Update).
    while (g_nextFrame > 0 && g_nextFrame < deadline - 1.0) {
        const double at = g_nextFrame;
        if (NowMs() > at + interval * 0.5) {  // behind (long tick, blocking flip): drop this frame
            g_nextFrame = at + interval;
            continue;
        }
        WaitUntil(at);
        g_nextFrame = at + interval;
        RenderExtraFrame((at - tickStart) / tick);
    }
    WaitUntil(deadline);
}

// CBaldurChitin vtable slot 0 (SynchronousUpdate), called once per CChitin::Update. With a render target, the
// frame is drawn only when the frame clock says it is due, so the logic keeps its rate when frames are rarer than
// ticks (EEex 'Uncap FPS': 120 ticks/s with 60 frames/s) and the frame rate is exact when they are more frequent.
void HookChitinRender(Word chitin)
{
    const std::uint32_t tps = g_tps ? *g_tps : 0;
    const int target = Target();
    if (target > 0 && tps > 0 && g_paceStart > 0) {
        const double now = NowMs();
        if (g_nextFrame > 0 && now < g_nextFrame - 1.0) {
            ++g_skipped;  // not due yet: drawn later, while the tick waits, or by a later Update
            return;
        }
        AdvanceFrameClock(now, 1000.0 / target);
    } else {
        g_nextFrame = 0;
    }
    reinterpret_cast<void (*)(Word)>(g_origRender)(chitin);
}

// Keeps the GL swap interval the 'VSync Enabled' option asks for (the engine may set it again on a video mode
// change); restores the engine's own value once the option is released.
void EnforceVSync()
{
    if (!g_getSwap || !g_setSwap)
        return;
    if (g_vsyncWanted < 0) {
        if (g_vsyncOriginal != -2) {
            g_setSwap(g_vsyncOriginal);
            Log("VSync: engine setting restored (%d)", g_vsyncOriginal);
            g_vsyncOriginal = -2;
        }
        return;
    }
    const int current = g_getSwap();
    if (current == g_vsyncWanted || (g_vsyncWanted == 1 && current == -1))  // -1 = adaptive vsync: on
        return;
    if (g_vsyncOriginal == -2)
        g_vsyncOriginal = current;
    const int rc = g_setSwap(g_vsyncWanted);
    Log("VSync: swap interval %d -> %d (%s)", current, g_vsyncWanted, rc == 0 ? "ok" : "refused");
    if (rc != 0)
        g_vsyncWanted = -1;  // not supported by the driver: leave it to the engine
}

// --- Motion interpolation ---
//
// Objects move once per logic tick (CGameObject::m_pos, written by AIUpdate): the extra frames would draw them at
// the same place. While an area is drawn (CGameArea::RenderZoomed, hooked in event_hooks.cpp), every object of
// its four vertical lists gets m_pos / m_posZ set to a point between its last two logic positions, and the real
// values are written back as soon as RenderZoomed returns, before any other engine code runs. Logic (AI, search
// map, saving, the next AsynchronousUpdate) therefore never sees an interpolated value.
//
// Per object: when its position changes at tick S, the drawn point moves from where it was drawn at S to the new
// position over `span` ticks (the interval since its previous change, 1..kMaxSpan, so an object moving every
// other tick glides at constant speed). The drawn world is one change behind the logic (1-2 ticks, 33-66 ms).
// New objects, area changes and jumps above kSnapDistance are drawn at their real position.

struct Track {
    Word object = 0;
    Word area = 0;
    int fromX = 0, fromY = 0, fromZ = 0;
    int toX = 0, toY = 0, toZ = 0;
    std::uint64_t changed = 0;  // tick of the last position change
    int span = 1;
    std::uint64_t seen = 0;     // tick of the last capture (0 = never)
};

struct Applied {
    int id;
    Word object;
    int x, y, z;     // real position (restored)
    int dx, dy, dz;  // drawn position
};

std::unordered_map<int, Track> g_tracks;
std::vector<Applied> g_applied;
std::vector<Applied> g_lastRestored;  // checked against the objects at the start of the next tick
std::uint64_t g_lastPurge = 0;

// Counters (IEX_GetFrameInterpolation): frames drawn interpolated, objects moved in the last one, snaps, and
// mismatches found by the restore checks (must stay 0).
std::uint64_t g_statFrames = 0;
int g_statLastMoved = 0;
std::uint64_t g_statSnaps = 0;
std::uint64_t g_statMismatch = 0;

// Trace (IEX_TraceFrameInterpolation): one log line per drawn frame for one object.
int g_traceId = -1;
int g_traceLeft = 0;

int* PosX(Word o) { return reinterpret_cast<int*>(o + g_posOffset); }
int* PosY(Word o) { return reinterpret_cast<int*>(o + g_posOffset + 4); }
int* PosZ(Word o) { return reinterpret_cast<int*>(o + g_posZOffset); }

bool InterpolationActive()
{
    return g_interpReady && g_interpOption && g_hooked && Target() > 0 && g_tps &&
           static_cast<std::uint32_t>(Target()) > *g_tps;
}

void Drawn(const Track& t, double now, int& x, int& y, int& z)
{
    double a = (now - static_cast<double>(t.changed)) / t.span;
    if (a >= 1) {
        x = t.toX, y = t.toY, z = t.toZ;
        return;
    }
    if (a < 0)
        a = 0;
    x = t.fromX + static_cast<int>(std::lround((t.toX - t.fromX) * a));
    y = t.fromY + static_cast<int>(std::lround((t.toY - t.fromY) * a));
    z = t.fromZ + static_cast<int>(std::lround((t.toZ - t.fromZ) * a));
}

void Reset(Track& t, Word object, Word area, int x, int y, int z)
{
    t.object = object;
    t.area = area;
    t.fromX = t.toX = x;
    t.fromY = t.toY = y;
    t.fromZ = t.toZ = z;
    t.changed = g_serial;
    t.span = 1;
}

// First sight of the object in this tick: record its new logic position.
void Capture(Track& t, Word object, Word area, int x, int y, int z)
{
    if (t.seen == 0 || t.object != object || t.area != area || g_serial - t.seen > kForgetTicks) {
        Reset(t, object, area, x, y, z);
    } else if (x != t.toX || y != t.toY || z != t.toZ) {
        int cx, cy, cz;
        Drawn(t, static_cast<double>(g_serial), cx, cy, cz);
        if (std::abs(x - cx) > kSnapDistance || std::abs(y - cy) > kSnapDistance ||
            std::abs(z - cz) > kSnapDistance) {
            Reset(t, object, area, x, y, z);
            ++g_statSnaps;
        } else {
            const std::uint64_t since = g_serial - t.changed;
            t.span = since < 1 ? 1 : since > static_cast<std::uint64_t>(kMaxSpan) ? kMaxSpan : static_cast<int>(since);
            t.fromX = cx, t.fromY = cy, t.fromZ = cz;
            t.toX = x, t.toY = y, t.toZ = z;
            t.changed = g_serial;
        }
    }
    t.seen = g_serial;
}

void InterpolateList(Word area, std::uint32_t listOffset, double now)
{
    // CPtrList: head node pointer at +8; node: next +0, prev +8, data (object id) +0x10.
    for (Word node = *reinterpret_cast<const Word*>(area + listOffset + 8); node;
         node = *reinterpret_cast<const Word*>(node)) {
        const int id = *reinterpret_cast<const int*>(node + 0x10);
        Word object = 0;
        if (g_getShare(id, &object, false) != 0 || !object ||
            *reinterpret_cast<const Word*>(object + g_areaOffset) != area)
            continue;
        const int x = *PosX(object), y = *PosY(object), z = *PosZ(object);
        Track& t = g_tracks[id];
        if (t.seen != g_serial)
            Capture(t, object, area, x, y, z);
        else if (t.object != object)
            continue;  // id reused within the tick: leave it alone
        int dx, dy, dz;
        Drawn(t, now, dx, dy, dz);
        if (id == g_traceId && g_traceLeft > 0) {
            --g_traceLeft;
            const Word inf = area + 0x5c8;  // CGameArea.m_cInfinity: view position nNewX/Y at +0x60/+0x64
            Log("Interp trace tick=%llu phase=%.3f extra=%d id=%d logic=(%d,%d) drawn=(%d,%d) span=%d view=(%d,%d)",
                static_cast<unsigned long long>(g_serial), g_phase, g_inExtraFrame ? 1 : 0, id, x, y, dx, dy, t.span,
                *reinterpret_cast<const int*>(inf + 0x60), *reinterpret_cast<const int*>(inf + 0x64));
        }
        if (dx == x && dy == y && dz == z)
            continue;
        g_applied.push_back({id, object, x, y, z, dx, dy, dz});
        *PosX(object) = dx;
        *PosY(object) = dy;
        *PosZ(object) = dz;
    }
}

// IEX_SetFrameInterpolation(on): draw moving objects between their logic positions in the extra frames (on by
// default; only has an effect while IEX_SetFrameRate is above the tick rate). Returns the setting.
int LuaSetFrameInterpolation(lua_State* L)
{
    const bool on = lua.toboolean(L, 1) != 0;
    if (on != g_interpOption)
        Log("Frame interpolation: %s", on ? "on" : "off");
    g_interpOption = on;
    if (!on)
        g_tracks.clear();
    lua.pushboolean(L, on);
    return 1;
}

// IEX_GetFrameInterpolation() -> setting, active now, frames drawn interpolated, objects moved in the last frame,
// snaps (jumps drawn without interpolation), mismatches (positions not restored: must stay 0).
int LuaGetFrameInterpolation(lua_State* L)
{
    lua.pushboolean(L, g_interpOption);
    lua.pushboolean(L, InterpolationActive());
    lua.pushinteger(L, static_cast<long long>(g_statFrames));
    lua.pushinteger(L, g_statLastMoved);
    lua.pushinteger(L, static_cast<long long>(g_statSnaps));
    lua.pushinteger(L, static_cast<long long>(g_statMismatch));
    return 6;
}

// IEX_TraceFrameInterpolation(objectId, frames): logs the logic and drawn position of one object for the next
// `frames` drawn frames (test tool).
int LuaTraceFrameInterpolation(lua_State* L)
{
    g_traceId = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    g_traceLeft = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    return 0;
}

void InstallInterpolation()
{
    g_getShare = Engine<std::uint8_t (*)(int, Word*, bool)>(kGetShare);
    const TypeDesc* object = engineTypes.Get("CGameObject");
    const TypeDesc* area = engineTypes.Get("CGameArea");
    const char* lists[4] = {"m_lVertSort", "m_lVertSortBack", "m_lVertSortFlight", "m_lVertSortAdd"};
    bool ok = g_getShare && object && area && object->Find("m_pos", g_posOffset) &&
              object->Find("m_posZ", g_posZOffset) && object->Find("m_pArea", g_areaOffset);
    for (int i = 0; ok && i < 4; ++i)
        ok = area->Find(lists[i], g_listOffsets[i]) != nullptr;
    g_interpReady = ok;
    Log("Frame interpolation: %s", ok ? "available" : "engine description incomplete, disabled");
}

int DesktopRefreshRate()
{
    // The display the game window is on (several monitors can have different rates), else the first one.
    int display = 0;
    const auto currentWindow = Engine<void* (*)()>("SDL_GL_GetCurrentWindow");
    const auto displayIndex = Engine<int (*)(void*)>("SDL_GetWindowDisplayIndex");
    if (currentWindow && displayIndex) {
        if (void* window = currentWindow()) {
            const int index = displayIndex(window);
            if (index >= 0)
                display = index;
        }
    }
    const auto current = Engine<int (*)(int, void*)>("SDL_GetCurrentDisplayMode");
    const auto mode = Engine<int (*)(int, void*)>(kDesktopMode);
    // SDL_DisplayMode: Uint32 format, int w, int h, int refresh_rate, void* driverdata.
    alignas(8) std::uint8_t buffer[32] = {};
    if (!(current && current(display, buffer) == 0) && !(mode && mode(display, buffer) == 0))
        return 0;
    std::int32_t rate;
    std::memcpy(&rate, buffer + 12, 4);
    return rate;
}

// IEX_SetFrameRate(n [, cap]): render n frames per second while the logic keeps "Maximum Frame Rate" ticks.
// n = 0 (or <= the tick rate): engine default. n = -1: the refresh rate of the window's display (followed when
// the window moves to another monitor), at most `cap` when given. Returns the applied rate.
int LuaSetFrameRate(lua_State* L)
{
    int n = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    g_refreshMode = n < 0;
    g_refreshCap = g_refreshMode && lua.type(L, 2) == LUA_TNUMBER ? static_cast<int>(lua.tointegerx(L, 2, nullptr)) : 0;
    if (n < 0) {
        n = DesktopRefreshRate();
        if (g_refreshCap > 0 && (n <= 0 || n > g_refreshCap))
            n = g_refreshCap;
    }
    if (n > kMaxFrameRate)
        n = kMaxFrameRate;
    if (n > 0 && !g_hooked) {
        Log("IEX_SetFrameRate(%d): frame rate hook not installed", n);
        n = 0;
    }
    if (n != g_target)
        Log("Render frame rate: %d (logic %u ticks/s)", n, g_tps ? *g_tps : 0);
    g_target = n;
    lua.pushinteger(L, n);
    return 1;
}

// IEX_SetFrameRateFloor(n): render at least n frames per second (0 = none). Used for the frame rate mods ask
// for through EEex_CChitin.TIMER_UPDATES_PER_SECOND while 'Keep Game Speed' is on (lua/EEex_TA.lua).
int LuaSetFrameRateFloor(lua_State* L)
{
    int n = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    n = n < 0 ? 0 : n > kMaxFrameRate ? kMaxFrameRate : n;
    if (!g_hooked)
        n = 0;
    if (n != g_floor)
        Log("Render frame rate asked by a mod: %d", n);
    g_floor = n;
    lua.pushinteger(L, n);
    return 1;
}

// IEX_SetVSync(v): -1 = the engine's own setting (default), 0 = off, 1 = on (GL swap interval).
int LuaSetVSync(lua_State* L)
{
    const int v = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    g_vsyncWanted = v < 0 ? -1 : v > 0 ? 1 : 0;
    lua.pushinteger(L, g_vsyncWanted);
    return 1;
}

// IEX_SetBusyWait(ms): the last ms of every frame / tick wait is spun instead of slept (0..10, default 1).
int LuaSetBusyWait(lua_State* L)
{
    const double v = lua.tonumberx(L, 1, nullptr);
    g_busyWaitMs = v < 0 ? 0 : v > 10 ? 10 : v;
    lua.pushnumber(L, g_busyWaitMs);
    return 1;
}

// IEX_GetFrameRate() -> requested render rate (0 = off), logic ticks per second ("Maximum Frame Rate"),
// render rate in use (the request raised to a mod's floor), mod floor, Update frames skipped so far
// (render rate below the tick rate), swap interval (-1 = unknown).
int LuaGetFrameRate(lua_State* L)
{
    lua.pushinteger(L, g_target);
    lua.pushinteger(L, g_tps ? *g_tps : 0);
    lua.pushinteger(L, Target());
    lua.pushinteger(L, g_floor);
    lua.pushinteger(L, static_cast<long long>(g_skipped));
    lua.pushinteger(L, g_getSwap ? g_getSwap() : -1);
    return 6;
}

// IEX_GetRenderRate() -> frames drawn and logic ticks run during the last second (the engine's own counters).
int LuaGetRenderRate(lua_State* L)
{
    const Word chitin = g_chitin ? *g_chitin : 0;
    const auto field = [chitin](std::uint64_t offset) {
        return chitin && offset ? *reinterpret_cast<const std::int32_t*>(chitin + offset) : 0;
    };
    lua.pushinteger(L, field(g_fpsField));
    lua.pushinteger(L, field(g_tpsField));
    return 2;
}

} // namespace

void FrameRateOnLogicTick()
{
    // The positions written back after the last drawn frame must still be the ones the logic starts from.
    for (const Applied& a : g_lastRestored) {
        Word object = 0;
        if (g_getShare(a.id, &object, false) != 0 || object != a.object)
            continue;
        if ((*PosX(object) != a.x || *PosY(object) != a.y || *PosZ(object) != a.z) && g_statMismatch++ < 10)
            Log("Frame interpolation: object %d at (%d,%d,%d) before tick %llu, restored (%d,%d,%d)", a.id,
                *PosX(object), *PosY(object), *PosZ(object), static_cast<unsigned long long>(g_serial + 1), a.x, a.y,
                a.z);
    }
    g_lastRestored.clear();
    ++g_serial;
    // Tick schedule: each tick starts one tick after the previous scheduled start, so a late tick (long frame,
    // vsync'd flip) is caught up by shorter waits. More than 3 ticks behind (loading, a stall): start again.
    const std::uint32_t tps = g_tps ? *g_tps : 0;
    if (g_hooked && Target() > 0 && tps > 0) {
        const double now = NowMs();
        const double tick = 1000.0 / tps;
        if (g_paceStart <= 0 || now - (g_paceStart + tick) > 3 * tick)
            g_paceStart = now;
        else
            g_paceStart += tick;
    } else {
        g_paceStart = 0;
    }
    EnforceVSync();
    // Refresh-rate mode: follow the window to a monitor with another rate (checked every 2 s).
    if (g_refreshMode && g_hooked) {
        const double now = NowMs();
        if (now - g_refreshChecked > 2000) {
            g_refreshChecked = now;
            int rate = DesktopRefreshRate();
            if (g_refreshCap > 0 && (rate <= 0 || rate > g_refreshCap))
                rate = g_refreshCap;
            if (rate > 0 && rate != g_target) {
                Log("Render frame rate: %d (window display refresh rate)", rate);
                g_target = rate > kMaxFrameRate ? kMaxFrameRate : rate;
            }
        }
    }
    if (g_serial - g_lastPurge > 64) {
        g_lastPurge = g_serial;
        for (auto it = g_tracks.begin(); it != g_tracks.end();)
            it = g_serial - it->second.seen > kForgetTicks ? g_tracks.erase(it) : std::next(it);
    }
}

bool FrameInterpolationBegin(std::uintptr_t area)
{
    if (!area || !InterpolationActive() || !g_applied.empty())
        return false;
    const Word chitin = *g_chitin;
    // Only frames of the render path (CChitin::Update's or our extra frames), not CScreenWorld::SaveScreen.
    if (!chitin || *reinterpret_cast<const std::int32_t*>(chitin + g_inSyncFlag) != 1)
        return false;
    const double now = static_cast<double>(g_serial) + g_phase;
    for (std::uint32_t list : g_listOffsets)
        InterpolateList(area, list, now);
    ++g_statFrames;
    g_statLastMoved = static_cast<int>(g_applied.size());
    return true;
}

void FrameInterpolationEnd()
{
    for (auto it = g_applied.rbegin(); it != g_applied.rend(); ++it) {
        // Nothing moves an object while the area is drawn: write back over our own value only.
        if (*PosX(it->object) == it->dx && *PosY(it->object) == it->dy && *PosZ(it->object) == it->dz) {
            *PosX(it->object) = it->x;
            *PosY(it->object) = it->y;
            *PosZ(it->object) = it->z;
        } else if (g_statMismatch++ < 10) {
            Log("Frame interpolation: object %d changed while drawn", it->id);
        }
    }
    g_lastRestored.insert(g_lastRestored.end(), g_applied.begin(), g_applied.end());
    g_applied.clear();
}

void InstallFrameRateHooks()
{
    g_delay = Engine<void (*)(std::uint32_t)>(kDelay);
    g_counter = Engine<std::uint64_t (*)()>(kPerfCounter);
    const auto frequency = Engine<std::uint64_t (*)()>(kPerfFrequency);
    g_render = Engine<void (*)(Word)>(kSyncUpdate);
    g_tps = Engine<const std::uint32_t*>(kTicksPerSecond);
    g_chitin = Engine<const Word*>(kChitin);
    std::uint64_t site = 0;
    engineTypes.Const("CChitin.inSyncFlag", g_inSyncFlag);
    engineTypes.Const("CChitin.framesPerSecond", g_fpsField);
    engineTypes.Const("CChitin.ticksPerSecond", g_tpsField);
    if (!g_delay || !g_counter || !frequency || !g_render || !g_tps || !g_chitin || !g_inSyncFlag ||
        !engineTypes.Const("CChitin.Update.delaySite", site)) {
        Log("Frame rate: engine description incomplete, IEX_SetFrameRate disabled");
        return;
    }
    g_ticksPerMs = static_cast<double>(frequency()) / 1000.0;
    InstallInterpolation();
    g_getSwap = Engine<int (*)()>(kGetSwap);
    g_setSwap = Engine<int (*)(int)>(kSetSwap);
    // Update's own frame: CBaldurChitin vtable slot 0, replaced so a frame can be skipped when the render rate
    // is below the tick rate.
    if (const std::uint32_t slotRva = engineTypes.Symbol(kRenderSlot)) {
        const Word slot = EngineImageBase() + slotRva;
        Word current = 0;
        std::memcpy(&current, reinterpret_cast<const void*>(slot), sizeof(current));
        const Word value = reinterpret_cast<Word>(&HookChitinRender);
        if (current == reinterpret_cast<Word>(g_render) &&
            platform::PatchCode(reinterpret_cast<void*>(slot), &value, sizeof(value)))
            g_origRender = current;
        Log("Frame rate: render slot hook %s", g_origRender ? "installed" : "FAILED (slot does not hold SynchronousUpdate)");
    }
    if (!g_origRender) {
        Log("Frame rate: no render slot, IEX_SetFrameRate disabled");
        return;
    }
    g_hooked = HookCallSite(EngineImageBase() + site, reinterpret_cast<Word>(g_delay),
                            reinterpret_cast<const void*>(&HookUpdateDelay));
    Log("Frame rate hook (CChitin::Update SDL_Delay at 0x%llx): %s", static_cast<unsigned long long>(site),
        g_hooked ? "installed" : "FAILED");
}

void OpenLuaFrameRate(lua_State* L)
{
    lua.pushcclosure(L, LuaSetFrameRate, 0);
    lua.setglobal(L, "IEX_SetFrameRate");
    lua.pushcclosure(L, LuaGetFrameRate, 0);
    lua.setglobal(L, "IEX_GetFrameRate");
    lua.pushcclosure(L, LuaGetRenderRate, 0);
    lua.setglobal(L, "IEX_GetRenderRate");
    lua.pushcclosure(L, LuaSetFrameRateFloor, 0);
    lua.setglobal(L, "IEX_SetFrameRateFloor");
    lua.pushcclosure(L, LuaSetVSync, 0);
    lua.setglobal(L, "IEX_SetVSync");
    lua.pushcclosure(L, LuaSetBusyWait, 0);
    lua.setglobal(L, "IEX_SetBusyWait");
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushboolean(L, g_hooked && g_interpReady);
    lua.setfield(L, -2, "frameInterpolation");
    lua.settop(L, -2);
    lua.pushcclosure(L, LuaSetFrameInterpolation, 0);
    lua.setglobal(L, "IEX_SetFrameInterpolation");
    lua.pushcclosure(L, LuaGetFrameInterpolation, 0);
    lua.setglobal(L, "IEX_GetFrameInterpolation");
    lua.pushcclosure(L, LuaTraceFrameInterpolation, 0);
    lua.setglobal(L, "IEX_TraceFrameInterpolation");
}

} // namespace iex
