// UI menus. The engine keeps every parsed .menu menu in one array sorted by name (findMenu() looks a menu up),
// each menu holding a singly linked list of items. Field layouts come from the engine description (uiMenu, uiItem);
// the EEex-compatible functions are written in Lua on top of these helpers (lua/EEex_MenuUI.lua).
#include "lua_ui.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "events.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstring>
#include <string>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kFindMenu = "findMenu";  // uiMenu* findMenu(const char* name, int panel, int state)
constexpr const char* kDrawItem = "_Z8drawItemP6uiItemP8SDL_RectPKS1_iP6uiMenu";

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

// Names of the items with a BeforeUIItemRender listener (few: compared one by one).
std::vector<std::string> g_watched;
const TypeDesc* g_itemType = nullptr;
std::uint32_t g_itemNameOffset = 0;

bool Watched(const char* name)
{
    for (const std::string& w : g_watched) {
        if (w == name)
            return true;
    }
    return false;
}

// drawItem(item, menuRect, itemRect, alpha, menu): the fifth argument is on the stack on Windows, in r8 on Linux;
// declaring five integer parameters keeps both ABIs.
// The item whose drawItem is running: for a list, RenderListCallback draws its rows from inside it (drawItem hands
// the callback to the engine's clip renderer, which runs it at once), so it is the list of the rows drawn then.
Word g_drawingItem = 0;
lua_State* g_uiL = nullptr;

Word HookDrawItem(Word item, Word menuRect, Word itemRect, Word alpha, Word menu)
{
    if (item && !g_watched.empty() && g_itemType) {
        const char* name = *reinterpret_cast<const char* const*>(item + g_itemNameOffset);
        if (name && Watched(name))
            DispatchObjectEvent("BeforeUIItemRender", item, g_itemType);
    }
    const Word saved = g_drawingItem;
    g_drawingItem = item;
    const Word r = Engine<Word (*)(Word, Word, Word, Word, Word)>(kDrawItem)(item, menuRect, itemRect, alpha, menu);
    g_drawingItem = saved;
    return r;
}

// The drawItem call of RenderListCallback: one list row (a copy of the row's template item). Lua gets
// IEX_ListRenderingItem(list, item, window, clip, alpha, menu) first (EEex_Menu_LuaHook_BeforeListRenderingItem).
Word HookListRowDrawItem(Word item, Word window, Word clip, Word alpha, Word menu)
{
    if (g_uiL && item && g_drawingItem && g_itemType) {
        lua_State* L = g_uiL;
        const int top = lua.gettop(L);
        lua.getglobal(L, "IEX_ListRenderingItem");
        if (lua.type(L, -1) == LUA_TFUNCTION) {
            PushObject(L, g_drawingItem, g_itemType);
            PushObject(L, item, g_itemType);
            lua.pushlightuserdata(L, reinterpret_cast<void*>(window));
            lua.pushlightuserdata(L, reinterpret_cast<void*>(clip));
            lua.pushinteger(L, static_cast<std::int32_t>(alpha));
            PushObject(L, menu, engineTypes.Get("uiMenu"));
            if (lua.pcallk(L, 6, 0, 0, 0, nullptr) != 0) {
                const char* err = lua.tolstring(L, -1, nullptr);
                Log("IEX_ListRenderingItem failed: %s", err ? err : "(unknown)");
            }
        }
        lua.settop(L, top);
    }
    return HookDrawItem(item, window, clip, alpha, menu);
}

// IEX_MenuFind(name [, panel [, state]]) -> uiMenu object or nil.
int LuaMenuFind(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const auto find = Engine<Word (*)(const char*, int, int)>(kFindMenu);
    const TypeDesc* menuType = engineTypes.Get("uiMenu");
    if (!find || !menuType)
        LuaError(L, "IEX_MenuFind: not available for this game build");
    if (!name) {
        lua.pushnil(L);
        return 1;
    }
    const int panel = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    const int state = static_cast<int>(lua.tointegerx(L, 3, nullptr));
    PushObject(L, find(name, panel, state), menuType);
    return 1;
}

// IEX_LuaRegistry() -> the Lua registry table (the .menu functions are stored there by reference).
int LuaRegistry(lua_State* L)
{
    lua.pushvalue(L, LUA_REGISTRYINDEX);
    return 1;
}

// IEX_PointerToObject(lightuserdata or address, typeName) -> object or nil. The engine's own UI functions
// (nameToItem, Infinity_FindUIItemByName...) hand out raw item pointers as light userdata.
int LuaPointerToObject(lua_State* L)
{
    Word address = 0;
    if (lua.type(L, 1) == LUA_TLIGHTUSERDATA)
        address = reinterpret_cast<Word>(lua.touserdata(L, 1));
    else if (lua.type(L, 1) == LUA_TNUMBER)
        address = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    else
        address = ToObjectAddress(L, 1);
    const char* typeName = lua.tolstring(L, 2, nullptr);
    const TypeDesc* type = typeName ? engineTypes.Get(typeName) : nullptr;
    if (!type)
        LuaError(L, "IEX_PointerToObject: unknown type '%s'", typeName ? typeName : "?");
    PushObject(L, address, type);
    return 1;
}

// IEX_MenuWatchItemRender(name, on): items named `name` fire BeforeUIItemRender before each draw.
int LuaWatchItemRender(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name)
        LuaError(L, "IEX_MenuWatchItemRender: item name expected");
    const bool on = lua.gettop(L) < 2 || lua.toboolean(L, 2) != 0;
    for (auto it = g_watched.begin(); it != g_watched.end(); ++it) {
        if (*it == name) {
            if (!on)
                g_watched.erase(it);
            return 0;
        }
    }
    if (on)
        g_watched.emplace_back(name);
    return 0;
}

} // namespace

void InstallUiHooks()
{
    g_itemType = engineTypes.Get("uiItem");
    std::uint32_t offset = 0;
    if (!g_itemType || !g_itemType->Find("name", offset)) {
        g_itemType = nullptr;
        Log("UI item render hook skipped: uiItem layout missing from the engine description");
        return;
    }
    g_itemNameOffset = offset;
    const std::uint32_t targetRva = engineTypes.Symbol(kDrawItem);
    const auto sites = engineTypes.CallSitesOf(kDrawItem);
    if (!targetRva || sites.empty()) {
        Log("UI item render hook skipped, no call site known for drawItem");
        return;
    }
    // The call site inside RenderListCallback (both builds: one, under 0x1000 bytes in) draws list rows.
    const std::uint32_t listRva = engineTypes.Symbol("_Z18RenderListCallbackPv");
    int hooked = 0, rows = 0;
    for (std::uint32_t site : sites) {
        const bool row = listRva && site > listRva && site < listRva + 0x1000;
        const void* fn = row ? reinterpret_cast<const void*>(&HookListRowDrawItem) : reinterpret_cast<const void*>(&HookDrawItem);
        const bool ok = HookCallSite(EngineImageBase() + site, EngineImageBase() + targetRva, fn);
        hooked += ok ? 1 : 0;
        rows += ok && row ? 1 : 0;
    }
    Log("UI item render hook drawItem: %d/%zu call sites (%d list row)", hooked, sites.size(), rows);
}

void OpenLuaUi(lua_State* L)
{
    g_uiL = L;
    lua.pushcclosure(L, LuaMenuFind, 0);
    lua.setglobal(L, "IEX_MenuFind");
    lua.pushcclosure(L, LuaRegistry, 0);
    lua.setglobal(L, "IEX_LuaRegistry");
    lua.pushcclosure(L, LuaPointerToObject, 0);
    lua.setglobal(L, "IEX_PointerToObject");
    lua.pushcclosure(L, LuaWatchItemRender, 0);
    lua.setglobal(L, "IEX_MenuWatchItemRender");
}

} // namespace iex
