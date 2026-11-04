// Action bar hooks. The engine rebuilds the bar in two steps:
//   CInfButtonArray::SetState(int)  picks the 12 button kinds of a state (class bar, spell list...), then calls
//   CInfButtonArray::UpdateButtons() which turns the kinds into buttons (icons, tooltips, grey-out, selection).
// UpdateButtons is also called on its own (modal state change, inventory, every few frames from the world screen).
// IEX runs the "state" listeners between the two steps, so a kind a mod writes is drawn by the same update.
#include "actionbar.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "events.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kUpdateButtons = "_ZN15CInfButtonArray13UpdateButtonsEv";
constexpr const char* kSetState = "_ZN15CInfButtonArray8SetStateEi";

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

bool g_stateSet = false;  // a SetState is running: its UpdateButtons call fires the state listeners
int g_depth = 0;          // nesting of UpdateButtons (listeners may trigger updates themselves)

Word HookUpdateButtons(Word self)
{
    const bool fireState = g_stateSet && g_depth == 0;
    g_stateSet = false;
    ++g_depth;
    if (fireState)
        DispatchEvent("ActionbarStateChanged");
    const Word result = Engine<Word (*)(Word)>(kUpdateButtons)(self);
    if (g_depth == 1)
        DispatchEvent("ActionbarButtonsUpdated");
    --g_depth;
    return result;
}

// `state` is an int (edx / esi); passed through as a full register.
Word HookSetState(Word self, Word state)
{
    g_stateSet = true;
    const Word result = Engine<Word (*)(Word, Word)>(kSetState)(self, state);
    g_stateSet = false;
    return result;
}

bool HookAll(const char* target, const void* replacement)
{
    const std::uint32_t targetRva = engineTypes.Symbol(target);
    const auto sites = engineTypes.CallSitesOf(target);
    if (!targetRva || sites.empty()) {
        Log("Action bar hook skipped, no call site known for %s", target);
        return false;
    }
    int hooked = 0;
    for (std::uint32_t site : sites)
        hooked += HookCallSite(EngineImageBase() + site, EngineImageBase() + targetRva, replacement) ? 1 : 0;
    Log("Action bar hook %s: %d/%zu call sites", target, hooked, sites.size());
    return hooked > 0;
}

Word CheckArray(lua_State* L, const char* fn)
{
    const Word array = ToObjectAddress(L, 1);
    if (!array)
        LuaError(L, "%s: CInfButtonArray expected", fn);
    return array;
}

// IEX_ActionbarSetState(array, state): engine SetState (state listeners and buttons-updated listeners run).
int LuaSetState(lua_State* L)
{
    const Word array = CheckArray(L, "IEX_ActionbarSetState");
    if (!engineTypes.Symbol(kSetState))
        LuaError(L, "IEX_ActionbarSetState: not available for this game build");
    HookSetState(array, static_cast<Word>(static_cast<std::uint32_t>(lua.tointegerx(L, 2, nullptr))));
    return 0;
}

// IEX_ActionbarUpdate(array): engine UpdateButtons (buttons-updated listeners run).
int LuaUpdate(lua_State* L)
{
    const Word array = CheckArray(L, "IEX_ActionbarUpdate");
    if (!engineTypes.Symbol(kUpdateButtons))
        LuaError(L, "IEX_ActionbarUpdate: not available for this game build");
    HookUpdateButtons(array);
    return 0;
}

} // namespace

void InstallActionbarHooks()
{
    HookAll(kSetState, reinterpret_cast<const void*>(&HookSetState));
    HookAll(kUpdateButtons, reinterpret_cast<const void*>(&HookUpdateButtons));
}

void OpenLuaActionbar(lua_State* L)
{
    lua.pushcclosure(L, LuaSetState, 0);
    lua.setglobal(L, "IEX_ActionbarSetState");
    lua.pushcclosure(L, LuaUpdate, 0);
    lua.setglobal(L, "IEX_ActionbarUpdate");
}

} // namespace iex
