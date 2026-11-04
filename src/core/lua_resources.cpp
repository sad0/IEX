// Lua functions that read game resources through the engine's resource manager (dimm). Generic: a resource is
// named by its resref and its numeric resource type (IE type codes: ITM 0x3ED, SPL 0x3EE, IDS 0x3F0, 2DA 0x3F4...).
// The EEex_Resource_* API (typed headers, 2DA / IDS objects) is built on these in lua/EEex_Resource.lua.
#include "lua_resources.h"

#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <cstdint>
#include <cstring>

namespace iex {

namespace {

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

// CRes fields, same offsets on both builds (verified_t1a.json "CRes type"): loaded data pointer and size.
constexpr std::uintptr_t kResData = 0x40;
constexpr std::uintptr_t kResSize = 0x48;

struct Demanded {
    const std::uint8_t* data = nullptr;
    std::uint32_t size = 0;
    std::uintptr_t res = 0;  // the engine's CRes object (CSpell / CItem wrappers hold it)
};

// Finds the resource and demands it. The demand is never released: the data stays loaded at the same address,
// so the pointers handed to Lua stay valid (same lifetime as the engine's own cached resources).
Demanded DemandResource(lua_State* L, const char* fnName)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const auto type = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    const auto makeResRef = Engine<void (*)(void*, const char*)>("_ZN7CResRefC1EPKc");
    const auto getResObject = Engine<void* (*)(const void*, int, bool)>("_Z16dimmGetResObjectRK7CResRefib");
    const auto demand = Engine<void* (*)(void*)>("_ZN4CRes6DemandEv");
    if (!makeResRef || !getResObject || !demand)
        LuaError(L, "%s: not available for this game build", fnName);
    Demanded out;
    if (!name || !*name || type <= 0)
        return out;
    alignas(8) char resRef[8];
    makeResRef(resRef, name);
    void* res = getResObject(resRef, type, false);  // false: look up only, never create an entry
    if (!res)
        return out;
    demand(res);
    const auto base = reinterpret_cast<std::uintptr_t>(res);
    out.res = base;
    std::memcpy(&out.data, reinterpret_cast<const void*>(base + kResData), sizeof(out.data));
    std::memcpy(&out.size, reinterpret_cast<const void*>(base + kResSize), sizeof(out.size));
    if (!out.data)
        out.size = 0;
    return out;
}

// IEX_ResourceData(resref, type) -> address, size, CRes object address (nil if the resource does not exist or
// failed to load).
int LuaResourceData(lua_State* L)
{
    const Demanded d = DemandResource(L, "IEX_ResourceData");
    if (!d.data) {
        lua.pushnil(L);
        return 1;
    }
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<std::uintptr_t>(d.data)));
    lua.pushinteger(L, static_cast<lua_Integer>(d.size));
    lua.pushinteger(L, static_cast<lua_Integer>(d.res));
    return 3;
}

// IEX_ResourceText(resref, type) -> file contents as a Lua string (nil if missing). For text resources
// (2DA, IDS...). Files in the old encrypted form (0xFF 0xFF prefix) are not decoded: nil and a log line.
int LuaResourceText(lua_State* L)
{
    const Demanded d = DemandResource(L, "IEX_ResourceText");
    if (!d.data) {
        lua.pushnil(L);
        return 1;
    }
    if (d.size >= 2 && d.data[0] == 0xFF && d.data[1] == 0xFF) {
        const char* name = lua.tolstring(L, 1, nullptr);
        Log("IEX_ResourceText: %s is encrypted, not supported", name ? name : "?");
        lua.pushnil(L);
        return 1;
    }
    lua.pushlstring(L, reinterpret_cast<const char*>(d.data), d.size);
    return 1;
}

// IEX_ResourceExists(resref, type) -> bool, without loading it.
int LuaResourceExists(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const auto type = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    const auto exists = Engine<bool (*)(const char*, int)>("_Z18dimmResourceExistsPKci");
    if (!exists)
        LuaError(L, "IEX_ResourceExists: not available for this game build");
    lua.pushboolean(L, name && *name && type > 0 && exists(name, type));
    return 1;
}

} // namespace

void OpenLuaResources(lua_State* L)
{
    lua.pushcclosure(L, LuaResourceData, 0);
    lua.setglobal(L, "IEX_ResourceData");
    lua.pushcclosure(L, LuaResourceText, 0);
    lua.setglobal(L, "IEX_ResourceText");
    lua.pushcclosure(L, LuaResourceExists, 0);
    lua.setglobal(L, "IEX_ResourceExists");
}

} // namespace iex
