// Lua functions that call engine code (UI, keyboard, camera). The EEex-compatible names are bound in lua/EEex_*.lua.
#include "lua_engine.h"

#include "event_hooks.h"

#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstring>
#include <string>

namespace iex {

namespace {

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

std::uintptr_t* EngineGlobal(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? reinterpret_cast<std::uintptr_t*>(EngineImageBase() + rva) : nullptr;
}

constexpr int kResTypeMenu = 0x408;

// IEX_MenuLoadFile(name) -> bool: parses <name>.MENU and adds its menus to the UI.
// uiLoadMenu() is the engine's loader for UI.MENU; it also records the file as the one to re-parse on a UI
// reload and resets the background/overlay menus, so those are restored afterwards: the main UI stays in
// charge, and mods load their files again from the MainFileReloaded event.
int LuaMenuLoadFile(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const auto makeResRef = Engine<void (*)(void*, const char*)>("_ZN7CResRefC1EPKc");
    const auto getResObject = Engine<void* (*)(const void*, int, bool)>("_Z16dimmGetResObjectRK7CResRefib");
    const auto loadMenu = Engine<void (*)(void*)>("_Z10uiLoadMenuP8CResText");
    std::uintptr_t* menuSrc = EngineGlobal("menuSrc");
    std::uintptr_t* background = EngineGlobal("g_backgroundMenu");
    std::uintptr_t* overlay = EngineGlobal("g_overlayMenu");
    if (!name || !makeResRef || !getResObject || !loadMenu || !menuSrc || !background || !overlay)
        LuaError(L, "IEX_MenuLoadFile: not available for this game build");

    alignas(8) char resRef[8];
    makeResRef(resRef, name);
    void* res = getResObject(resRef, kResTypeMenu, false);
    if (!res) {
        Log("Menu file not found: %s.MENU", name);
        lua.pushboolean(L, 0);
        return 1;
    }
    const std::uintptr_t savedSrc = *menuSrc, savedBackground = *background, savedOverlay = *overlay;
    loadMenu(res);
    *menuSrc = savedSrc;
    if (!*background)
        *background = savedBackground;
    if (!*overlay)
        *overlay = savedOverlay;
    lua.pushboolean(L, 1);
    return 1;
}

// IEX_KeyFromName(name) -> SDL keycode (0 if unknown).
int LuaKeyFromName(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const auto fromName = Engine<std::int32_t (*)(const char*)>("SDL_GetKeyFromName");
    if (!fromName)
        LuaError(L, "IEX_KeyFromName: not available for this game build");
    lua.pushinteger(L, name ? fromName(name) : 0);
    return 1;
}

// IEX_KeyName(keycode) -> SDL's name of the key in the current keyboard layout ('Left Shift', 'D', '\'),
// '' if unknown.
int LuaKeyName(lua_State* L)
{
    const auto key = static_cast<std::int32_t>(lua.tointegerx(L, 1, nullptr));
    const auto getName = Engine<const char* (*)(std::int32_t)>("SDL_GetKeyName");
    const char* name = getName ? getName(key) : nullptr;
    lua.pushstring(L, name ? name : "");
    return 1;
}

// IEX_KeyIsDown(keycode) -> bool
int LuaKeyIsDown(lua_State* L)
{
    const auto key = static_cast<std::int32_t>(lua.tointegerx(L, 1, nullptr));
    const auto scancodeFromKey = Engine<std::int32_t (*)(std::int32_t)>("SDL_GetScancodeFromKey");
    const auto keyboardState = Engine<const std::uint8_t* (*)(int*)>("SDL_GetKeyboardState");
    if (!scancodeFromKey || !keyboardState)
        LuaError(L, "IEX_KeyIsDown: not available for this game build");
    int count = 0;
    const std::uint8_t* state = keyboardState(&count);
    const std::int32_t scancode = scancodeFromKey(key);
    lua.pushboolean(L, state && scancode > 0 && scancode < count && state[scancode]);
    return 1;
}

// IEX_ScancodeIsDown(scancode) -> bool: physical key held (SDL scancode, independent of the keyboard layout).
int LuaScancodeIsDown(lua_State* L)
{
    const auto scancode = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    const auto keyboardState = Engine<const std::uint8_t* (*)(int*)>("SDL_GetKeyboardState");
    if (!keyboardState)
        LuaError(L, "IEX_ScancodeIsDown: not available for this game build");
    int count = 0;
    const std::uint8_t* state = keyboardState(&count);
    lua.pushboolean(L, state && scancode > 0 && scancode < count && state[scancode]);
    return 1;
}

// IEX_ScancodeFromKey(keycode) -> scancode of the physical key that types `keycode` in the current layout.
int LuaScancodeFromKey(lua_State* L)
{
    const auto scancodeFromKey = Engine<std::int32_t (*)(std::int32_t)>("SDL_GetScancodeFromKey");
    if (!scancodeFromKey)
        LuaError(L, "IEX_ScancodeFromKey: not available for this game build");
    lua.pushinteger(L, scancodeFromKey(static_cast<std::int32_t>(lua.tointegerx(L, 1, nullptr))));
    return 1;
}

// --- Game objects ---

// IEX_GetObject(id) -> CGameObject or nil (invalid or deleted id).
int LuaGetObject(lua_State* L)
{
    const auto id = static_cast<int>(lua.tointegerx(L, 1, nullptr));
    const auto getShare = Engine<std::uint8_t (*)(int, std::uintptr_t*, bool)>("_ZN16CGameObjectArray8GetShareEiPP11CGameObjectb");
    if (!getShare)
        LuaError(L, "IEX_GetObject: not available for this game build");
    std::uintptr_t object = 0;
    if (id == -1 || getShare(id, &object, false) != 0)
        object = 0;
    PushObject(L, object, engineTypes.Get("CGameObject"));
    return 1;
}

// IEX_GetStat(derivedStats, statId) -> int: value of a STATS.IDS stat in a CDerivedStats object.
int LuaGetStat(lua_State* L)
{
    const std::uintptr_t stats = ToObjectAddress(L, 1);
    const auto stat = static_cast<short>(lua.tointegerx(L, 2, nullptr));
    const auto getAtOffset = Engine<int (*)(std::uintptr_t, short)>("_ZN13CDerivedStats11GetAtOffsetEs");
    if (!stats || !getAtOffset)
        LuaError(L, "IEX_GetStat: CDerivedStats object expected");
    lua.pushinteger(L, getAtOffset(stats, stat));
    return 1;
}

// IEX_SpriteName(sprite) -> string: display name (TLK name, or the custom name of a renamed character).
int LuaSpriteName(lua_State* L)
{
    const std::uintptr_t sprite = ToObjectAddress(L, 1);
    // Returns a reference to the sprite's own CString member: read its buffer, nothing to free.
    const auto getName = Engine<const char* const* (*)(std::uintptr_t, int)>("_ZN11CGameSprite7GetNameEi");
    // Only for creatures: GetName on another object (an action, an effect...) reads garbage and crashes.
    static const TypeDesc* spriteType = engineTypes.Get("CGameSprite");
    static const TypeDesc* aiBaseType = engineTypes.Get("CGameAIBase");
    static const TypeDesc* objectType = engineTypes.Get("CGameObject");
    static const std::uint32_t typeOffset = [] {
        std::uint32_t o = 0;
        return objectType && objectType->Find("m_objectType", o) ? o : 0u;
    }();
    const TypeDesc* pushed = ToObjectType(L, 1);
    const bool isSprite = sprite && (pushed == spriteType ||
        ((pushed == aiBaseType || pushed == objectType) && typeOffset &&
         *reinterpret_cast<const std::uint8_t*>(sprite + typeOffset) == 0x31));
    if (!isSprite || !getName)
        LuaError(L, "IEX_SpriteName: CGameSprite expected");
    if (sprite == g_spriteUnderConstruction) {
        lua.pushstring(L, "");
        return 1;
    }
    const char* const* name = getName(sprite, 0);
    lua.pushstring(L, name && *name ? *name : "");
    return 1;
}

// --- Camera (CInfinity: the view of an area) ---

std::uintptr_t CheckInfinity(lua_State* L, const char* fn)
{
    const std::uintptr_t infinity = ToObjectAddress(L, 1);
    if (!infinity)
        LuaError(L, "%s: CInfinity object expected", fn);
    return infinity;
}

// IEX_CameraSetView(infinity, x, y): moves the top-left corner of the view to world point (x, y). The engine
// clamps it to the area (FitViewPosition) and drops any smooth scroll in progress.
int LuaCameraSetView(lua_State* L)
{
    const std::uintptr_t infinity = CheckInfinity(L, "IEX_CameraSetView");
    const auto setView = Engine<int (*)(std::uintptr_t, int, int, unsigned char)>("_ZN9CInfinity15SetViewPositionEiih");
    if (!setView)
        LuaError(L, "IEX_CameraSetView: not available for this game build");
    setView(infinity, static_cast<int>(lua.tonumberx(L, 2, nullptr)), static_cast<int>(lua.tonumberx(L, 3, nullptr)), 1);
    return 0;
}

// IEX_CameraSetZoom(infinity, zoom): world pixels per screen pixel (1 = none, smaller = closer). The engine
// clamps it to [MAXZOOM_IN, ...] and keeps the view centre; it ignores the call when zoom is disabled.
int LuaCameraSetZoom(lua_State* L)
{
    const std::uintptr_t infinity = CheckInfinity(L, "IEX_CameraSetZoom");
    const auto setZoom = Engine<void (*)(std::uintptr_t, float)>("_ZN9CInfinity7SetZoomEf");
    if (!setZoom)
        LuaError(L, "IEX_CameraSetZoom: not available for this game build");
    setZoom(infinity, static_cast<float>(lua.tonumberx(L, 2, nullptr)));
    return 0;
}

// IEX_CameraZoomLimits([closest, farthest]) -> closest, farthest: the engine-wide zoom range (defaults 0.5,
// 1.4), changed first when arguments are given. They are plain floats in the engine's data section.
int LuaCameraZoomLimits(lua_State* L)
{
    auto* closest = reinterpret_cast<float*>(EngineGlobal("_ZN9CInfinity10MAXZOOM_INE"));
    auto* farthest = reinterpret_cast<float*>(EngineGlobal("_ZN9CInfinity11MAXZOOM_OUTE"));
    if (!closest || !farthest)
        LuaError(L, "IEX_CameraZoomLimits: not available for this game build");
    if (lua.type(L, 1) == LUA_TNUMBER)
        *closest = static_cast<float>(lua.tonumberx(L, 1, nullptr));
    if (lua.type(L, 2) == LUA_TNUMBER)
        *farthest = static_cast<float>(lua.tonumberx(L, 2, nullptr));
    lua.pushnumber(L, *closest);
    lua.pushnumber(L, *farthest);
    return 2;
}

// --- Actions ---

// IEX_SpriteSetAction(sprite, actionId, x, y): makes a point action (ACTION.IDS number, e.g. 23 MoveToPoint,
// 0 NoAction) the sprite's current action right away, replacing the one in progress; queued actions are kept.
// The action is a copy of the current one with a new id, destination and specifics: its CStrings are the same
// buffers, which CString::operator= leaves alone when assigning a string to itself, so nothing is allocated.
int LuaSpriteSetAction(lua_State* L)
{
    const std::uintptr_t sprite = ToObjectAddress(L, 1);
    const auto setCurrAction = Engine<void (*)(std::uintptr_t, const void*)>("_ZN11CGameSprite13SetCurrActionERK9CAIAction");
    static const TypeDesc* aiBase = engineTypes.Get("CGameAIBase");
    static const TypeDesc* action = engineTypes.Get("CAIAction");
    std::uint32_t current = 0, id = 0, dest = 0, specific = 0;
    if (!sprite || !setCurrAction || !aiBase || !action || !aiBase->Find("m_curAction", current) ||
        !action->Find("m_actionID", id) || !action->Find("m_dest", dest) || !action->Find("m_specificID", specific))
        LuaError(L, "IEX_SpriteSetAction: not available for this game build (or not a sprite)");
    alignas(16) std::uint8_t buffer[0x100];
    if (action->size > sizeof(buffer))
        LuaError(L, "IEX_SpriteSetAction: unexpected CAIAction size");
    std::memcpy(buffer, reinterpret_cast<const void*>(sprite + current), action->size);
    const auto actionId = static_cast<std::int16_t>(lua.tointegerx(L, 2, nullptr));
    const std::int32_t point[2] = {static_cast<std::int32_t>(lua.tonumberx(L, 3, nullptr)),
                                   static_cast<std::int32_t>(lua.tonumberx(L, 4, nullptr))};
    const std::int32_t specifics[3] = {0, 0, 0};
    std::memcpy(buffer + id, &actionId, 2);
    std::memcpy(buffer + dest, point, 8);
    std::memcpy(buffer + specific, specifics, 12);
    setCurrAction(sprite, buffer);
    return 0;
}

// --- Script variables (GLOBAL, area, LOCALS) ---
//
// A CVariableHash is an open-addressing table of CVariable entries. Lookups scan it directly (the engine's
// FindKey takes a CString by value, which differs between ABIs); new variables go through AddKey, which
// takes a CVariable by reference and copies it.

struct VariableLayout {
    std::uint32_t entries, count, size, name, intValue, stringValue;
    bool ok = false;
};

const VariableLayout& Layout()
{
    static VariableLayout layout = [] {
        VariableLayout v{};
        const TypeDesc* hash = engineTypes.Get("CVariableHash");
        const TypeDesc* var = engineTypes.Get("CVariable");
        v.ok = hash && var && hash->Find("m_hashEntries", v.entries) && hash->Find("m_nTableEntries", v.count) &&
               var->Find("m_name", v.name) && var->Find("m_intValue", v.intValue) &&
               var->Find("m_stringValue", v.stringValue);
        v.size = var ? var->size : 0;
        return v;
    }();
    return layout;
}

// Engine variable names: spaces removed, upper case, at most 32 chars.
std::string NormalizeVariableName(const char* name)
{
    std::string out;
    for (const char* c = name; *c && out.size() < 32; ++c) {
        if (*c != ' ')
            out += static_cast<char>(*c >= 'a' && *c <= 'z' ? *c - 'a' + 'A' : *c);
    }
    return out;
}

std::uintptr_t FindVariable(std::uintptr_t hash, const std::string& name)
{
    const VariableLayout& v = Layout();
    std::uintptr_t entries;
    std::int32_t count;
    std::memcpy(&entries, reinterpret_cast<const void*>(hash + v.entries), 8);
    std::memcpy(&count, reinterpret_cast<const void*>(hash + v.count), 4);
    for (std::int32_t i = 0; entries && i < count; ++i) {
        const std::uintptr_t entry = entries + static_cast<std::uintptr_t>(i) * v.size;
        const char* entryName = reinterpret_cast<const char*>(entry + v.name);
        if (entryName[0] && std::strncmp(entryName, name.c_str(), 32) == 0)
            return entry;
    }
    return 0;
}

std::uintptr_t CheckHash(lua_State* L)
{
    const std::uintptr_t hash = ToObjectAddress(L, 1);
    if (!hash || !Layout().ok)
        LuaError(L, "IEX: CVariableHash object expected");
    return hash;
}

// IEX_VariableGet(hash, name) -> int, string (0, "" when the variable does not exist)
int LuaVariableGet(lua_State* L)
{
    const std::uintptr_t hash = CheckHash(L);
    const char* name = lua.tolstring(L, 2, nullptr);
    const std::uintptr_t entry = name ? FindVariable(hash, NormalizeVariableName(name)) : 0;
    if (!entry) {
        lua.pushinteger(L, 0);
        lua.pushstring(L, "");
        return 2;
    }
    std::int32_t value;
    std::memcpy(&value, reinterpret_cast<const void*>(entry + Layout().intValue), 4);
    lua.pushinteger(L, value);
    const char* text = reinterpret_cast<const char*>(entry + Layout().stringValue);
    lua.pushlstring(L, text, strnlen(text, 32));
    return 2;
}

// IEX_VariableSet(hash, name, intValue or nil, stringValue or nil): creates the variable if needed.
int LuaVariableSet(lua_State* L)
{
    const std::uintptr_t hash = CheckHash(L);
    const char* rawName = lua.tolstring(L, 2, nullptr);
    if (!rawName)
        LuaError(L, "IEX_VariableSet: name expected");
    const std::string name = NormalizeVariableName(rawName);
    const bool setInt = lua.type(L, 3) == LUA_TNUMBER;
    const char* text = lua.type(L, 4) == LUA_TSTRING ? lua.tolstring(L, 4, nullptr) : nullptr;
    const VariableLayout& v = Layout();

    const auto write = [&](std::uintptr_t entry) {
        if (setInt) {
            const auto value = static_cast<std::int32_t>(lua.tointegerx(L, 3, nullptr));
            std::memcpy(reinterpret_cast<void*>(entry + v.intValue), &value, 4);
        }
        if (text) {
            char buffer[32] = {};
            std::strncpy(buffer, text, sizeof(buffer) - 1);
            std::memcpy(reinterpret_cast<void*>(entry + v.stringValue), buffer, sizeof(buffer));
        }
    };

    if (const std::uintptr_t entry = FindVariable(hash, name)) {
        write(entry);
        return 0;
    }
    const auto addKey = Engine<int (*)(std::uintptr_t, void*)>("_ZN13CVariableHash6AddKeyER9CVariable");
    if (!addKey)
        LuaError(L, "IEX_VariableSet: not available for this game build");
    std::uint8_t variable[0x100] = {};
    if (v.size > sizeof(variable))
        LuaError(L, "IEX_VariableSet: unexpected CVariable size");
    std::memcpy(variable + v.name, name.data(), name.size());
    write(reinterpret_cast<std::uintptr_t>(variable));
    addKey(hash, variable);
    return 0;
}

} // namespace

void OpenLuaEngine(lua_State* L)
{
    lua.pushcclosure(L, LuaGetObject, 0);
    lua.setglobal(L, "IEX_GetObject");
    lua.pushcclosure(L, LuaGetStat, 0);
    lua.setglobal(L, "IEX_GetStat");
    lua.pushcclosure(L, LuaSpriteName, 0);
    lua.setglobal(L, "IEX_SpriteName");
    lua.pushcclosure(L, LuaVariableGet, 0);
    lua.setglobal(L, "IEX_VariableGet");
    lua.pushcclosure(L, LuaVariableSet, 0);
    lua.setglobal(L, "IEX_VariableSet");
    lua.pushcclosure(L, LuaMenuLoadFile, 0);
    lua.setglobal(L, "IEX_MenuLoadFile");
    lua.pushcclosure(L, LuaKeyFromName, 0);
    lua.setglobal(L, "IEX_KeyFromName");
    lua.pushcclosure(L, LuaKeyName, 0);
    lua.setglobal(L, "IEX_KeyName");
    lua.pushcclosure(L, LuaKeyIsDown, 0);
    lua.setglobal(L, "IEX_KeyIsDown");
    lua.pushcclosure(L, LuaScancodeIsDown, 0);
    lua.setglobal(L, "IEX_ScancodeIsDown");
    lua.pushcclosure(L, LuaScancodeFromKey, 0);
    lua.setglobal(L, "IEX_ScancodeFromKey");
    lua.pushcclosure(L, LuaSpriteSetAction, 0);
    lua.setglobal(L, "IEX_SpriteSetAction");
    lua.pushcclosure(L, LuaCameraSetView, 0);
    lua.setglobal(L, "IEX_CameraSetView");
    lua.pushcclosure(L, LuaCameraSetZoom, 0);
    lua.setglobal(L, "IEX_CameraSetZoom");
    lua.pushcclosure(L, LuaCameraZoomLimits, 0);
    lua.setglobal(L, "IEX_CameraZoomLimits");
}

} // namespace iex
