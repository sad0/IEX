#pragma once

// Native hook-point registry (docs/NATIVE_HOOK_POINTS.md).
//
// A hook point is one engine moment that mods used to patch in Windows x64 machine code (an EEex_Hook* / JIT
// request, or raw bytes): the d20 attack roll, a ground move click, the death drop of the inventory... Each point
// is implemented once here in C++ (call-site redirections and fixed per-site thunks, after checking the site's
// bytes, on Windows and Linux), and every mod that needs it reaches it through one Lua API:
//
//   IEX_NativeHook_AddListener(point, fn)     lua/IEX_NativeHooks.lua; installs the point with its first listener
//   IEX_NativeHook_Enable(point [, a, b])     a point without Lua (a switch): installs and turns it on
//   IEX_NativeHook_Install(point [, a, b])    installs the engine side only (a, b: point arguments)
//   IEX_NativeHook_Installed(point) -> bool    IEX_NativeHook_Sites(point) -> patched engine sites
//   IEX_NativeHook_Points() -> { [point] = {kind=, result=, available=, installed=, active=, sites=, why=} }
//   IEX_Features.nativeHooks[point] = true    the point's sites exist on this build
//
// Calls from the engine: the point's C++ hook calls the Lua dispatcher IEX_NativeHook_Fire(point, ...) only while
// the point is active (installed + listening), with its typed arguments (engine objects as userdata, numbers as
// integers). Results (Result):
//   None     every listener runs, nothing returned
//   AnyTrue  every listener runs; true from any of them = the point's "yes" (keep ammo, handled...)
//   Value    the engine value is the last argument; each listener may return a new number (nil keeps it), which
//            the next listener receives; the final number replaces the engine value
//
// Points are listed once in kPoints (hook_points.cpp). An engine module implements its points and registers their
// installers (SetInstaller) or reports eager ones (MarkInstalled).
#include <cstdint>
#include <string>

struct lua_State;

namespace iex::hp {

enum Point : int {
    // combat (native_stick.cpp)
    kHitRoll, kToHitTotal, kCritThreshold, kCritBlocked, kAttackResult, kDamageRoll, kCritMultiplier,
    kAttackIndex, kAttackCancel, kHideInSight, kCasterSchoolSpell, kCasterSchoolItem, kTargetSchool,
    kActionButtonL, kActionButtonR, kClassDone, kProfMaxUI, kProfMax,
    // SadoEE behaviours (native_hooks.cpp, native_hooks_sado.cpp)
    kKeepAmmo, kGroundMoveClick, kDeathDrop, kRespecGear, kCampMarker, kCampSameArea, kGroundContainer,
    kSmallFootprint, kContainerMarker, kLastingModes, kFindTrapsButton, kStealthReveals,
    // spell lists (spell_slots.cpp, spell_lists.cpp)
    kSpellSlots99, kSpellLists,
    // rendering (hd_tiles.cpp)
    kHdTiles,
    // engine features (whole behaviours installed at startup)
    kPartyVision, kAlliedPassThrough, kEmptyContainerOutline,
    kCount
};

enum class Result { None, AnyTrue, Value };

// Kind: how a point is driven. Listener = Lua listeners per call; Switch = on/off (+ arguments), no Lua per call;
// Feature = installed at startup by its module (settings decide), reported here.
enum class Kind { Listener, Switch, Feature };

struct Info {
    const char* name;      // Lua name
    const char* category;  // docs grouping (attack, swing, ui, world...)
    Kind kind;
    Result result;
    const char* moment;    // engine moment, one line
};

const Info& InfoOf(Point p);
Point Find(const char* name);  // kCount when unknown

// Installer: true = installed; `why` = reason otherwise. a, b: IEX_NativeHook_Install arguments (0 if absent).
using Installer = bool (*)(std::string& why, std::uintptr_t a, std::uintptr_t b);
// Availability: the point's sites exist in this build's engine description.
using Available = bool (*)();

void SetInstaller(Point p, Installer install, Available available);
// Eager points (installed by their module at startup): the result and the number of engine sites patched.
void MarkInstalled(Point p, bool installed, int sites = 1, const char* why = nullptr);
void SetSites(Point p, int sites);
bool Install(Point p, std::uintptr_t a, std::uintptr_t b, std::string& why);
bool Installed(Point p);

// True while the point is installed and something listens (a Lua listener or an Enable).
inline bool g_active[kCount] = {};
inline bool Active(Point p) { return g_active[p]; }

// Calls IEX_NativeHook_Fire(name, <args>) on the engine Lua state. `push` pushes the arguments and returns their
// number. Errors are logged. FireBool: the dispatcher's truth. FireValue: true when a listener gave a number, then
// `value` holds it (Lua integer conversion: lua_tointegerx, 0 for a non-number).
template <typename P> void FireVoid(Point p, P&& push);
template <typename P> bool FireBool(Point p, P&& push);
template <typename P> bool FireValue(Point p, P&& push, std::int64_t& value);

// Shared helpers (for the template bodies below).
lua_State* State();
bool BeginFire(Point p, int& top);                // pushes the dispatcher and the point name
bool EndFire(Point p, int nargs, int top);        // pcall; false (logged) on a Lua error
void Finish(int top);
bool ResultBool();
bool ResultInteger(std::int64_t& value);

// Registers IEX_NativeHook_Install / Installed / Sites / Points / SetListening / Enable, IEX_Features.platform and
// IEX_Features.nativeHooks.
void OpenLua(lua_State* L);

template <typename P>
void FireVoid(Point p, P&& push)
{
    int top = 0;
    if (!BeginFire(p, top))
        return;
    EndFire(p, push(State()), top);
    Finish(top);
}

template <typename P>
bool FireBool(Point p, P&& push)
{
    int top = 0;
    if (!BeginFire(p, top))
        return false;
    const bool r = EndFire(p, push(State()), top) && ResultBool();
    Finish(top);
    return r;
}

template <typename P>
bool FireValue(Point p, P&& push, std::int64_t& value)
{
    int top = 0;
    if (!BeginFire(p, top))
        return false;
    const bool r = EndFire(p, push(State()), top) && ResultInteger(value);
    Finish(top);
    return r;
}

} // namespace iex::hp
