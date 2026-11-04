#include "events.h"

#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstring>

namespace iex {

namespace {

lua_State* g_L = nullptr;

// Calls IEX_Dispatch(event, <nargs values already pushed>) and returns its boolean result.
// Expects the stack to hold: IEX_Dispatch, event, args...
bool Call(lua_State* L, int top, int nargs)
{
    bool consumed = false;
    if (lua.pcallk(L, nargs + 1, 1, 0, 0, nullptr) == 0) {
        consumed = lua.toboolean(L, -1) != 0;
    } else {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("IEX_Dispatch failed: %s", err ? err : "(unknown)");
    }
    lua.settop(L, top);
    return consumed;
}

// Pushes IEX_Dispatch and the event name. Returns false (stack unchanged) if Lua isn't ready.
bool Begin(const char* event, int& top)
{
    if (!g_L)
        return false;
    top = lua.gettop(g_L);
    lua.getglobal(g_L, "IEX_Dispatch");
    if (lua.type(g_L, -1) != LUA_TFUNCTION) {
        lua.settop(g_L, top);
        return false;
    }
    lua.pushstring(g_L, event);
    return true;
}

} // namespace

void SetEventLuaState(lua_State* L)
{
    g_L = L;
}

bool DispatchEvent(const char* event)
{
    int top;
    return Begin(event, top) && Call(g_L, top, 0);
}

bool DispatchObjectEvent(const char* event, std::uintptr_t address, const TypeDesc* type)
{
    int top;
    if (!Begin(event, top))
        return false;
    PushObject(g_L, address, type);
    return Call(g_L, top, 1);
}

bool DispatchObjectsEvent(const char* event, std::uintptr_t a, const TypeDesc* typeA, std::uintptr_t b,
                          const TypeDesc* typeB)
{
    int top;
    if (!Begin(event, top))
        return false;
    PushObject(g_L, a, typeA);
    PushObject(g_L, b, typeB);
    return Call(g_L, top, 2);
}

bool DispatchIntegerEvent(const char* event, std::int64_t value)
{
    int top;
    if (!Begin(event, top))
        return false;
    lua.pushinteger(g_L, static_cast<lua_Integer>(value));
    return Call(g_L, top, 1);
}

bool DispatchSdlEvent(const std::uint8_t* e)
{
    if (!g_L)
        return false;
    // Key up (SDL_KEYUP 0x301, not a repeat): KeyReleased listeners get the SDL keycode (keysym.sym @20).
    std::uint32_t eventType;
    std::memcpy(&eventType, e, 4);
    if (eventType == 0x301 && e[13] == 0) {
        std::int32_t sym;
        std::memcpy(&sym, e + 20, 4);
        DispatchIntegerEvent("KeyReleased", sym);
    }
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, "EEex_Key_Hook_AfterEventsPoll");
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return false;
    }
    const auto i32 = [e](std::size_t offset) {
        std::int32_t v;
        std::memcpy(&v, e + offset, 4);
        return v;
    };
    // SDL2 layouts: type @0; keyboard repeat @13, keysym.scancode @16, keysym.sym @20; mouse button: button @16;
    // mouse wheel: x @16, y @20.
    lua.createtable(L, 0, 4);
    lua.pushinteger(L, static_cast<std::uint32_t>(i32(0)));
    lua.setfield(L, -2, "type");
    lua.createtable(L, 0, 2);  // key = {repeat, keysym = {sym, scancode}}
    lua.pushinteger(L, e[13]);
    lua.setfield(L, -2, "repeat");
    lua.createtable(L, 0, 2);
    lua.pushinteger(L, i32(20));
    lua.setfield(L, -2, "sym");
    lua.pushinteger(L, i32(16));
    lua.setfield(L, -2, "scancode");
    lua.setfield(L, -2, "keysym");
    lua.setfield(L, -2, "key");
    lua.createtable(L, 0, 1);  // button = {button}
    lua.pushinteger(L, e[16]);
    lua.setfield(L, -2, "button");
    lua.setfield(L, -2, "button");
    lua.createtable(L, 0, 2);  // wheel = {x, y}
    lua.pushinteger(L, i32(16));
    lua.setfield(L, -2, "x");
    lua.pushinteger(L, i32(20));
    lua.setfield(L, -2, "y");
    lua.setfield(L, -2, "wheel");

    bool drop = false;
    if (lua.pcallk(L, 1, 1, 0, 0, nullptr) == 0) {
        drop = lua.toboolean(L, -1) != 0;
    } else {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("EEex_Key_Hook_AfterEventsPoll failed: %s", err ? err : "(unknown)");
    }
    lua.settop(L, top);
    return drop;
}

} // namespace iex
