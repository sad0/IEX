#pragma once

// The engine's statically linked Lua 5.2 C API, as function pointers filled by the platform layer
// from the engine description of the running build.
#include <cstddef>
#include <cstdint>

struct lua_State;

namespace iex {

using lua_CFunction = int (*)(lua_State*);
using lua_Integer = std::ptrdiff_t;  // Lua 5.2 default
using lua_Number = double;

constexpr int LUA_REGISTRYINDEX = -1001000;  // -LUAI_MAXSTACK - 1000
constexpr int LuaUpvalueIndex(int i) { return LUA_REGISTRYINDEX - i; }
constexpr int LUA_MULTRET = -1;
constexpr int LUA_TNIL = 0;
constexpr int LUA_TBOOLEAN = 1;
constexpr int LUA_TLIGHTUSERDATA = 2;
constexpr int LUA_TNUMBER = 3;
constexpr int LUA_TSTRING = 4;
constexpr int LUA_TTABLE = 5;
constexpr int LUA_TFUNCTION = 6;
constexpr int LUA_TUSERDATA = 7;

// X(name, return type, parameter list). The platform layer resolves `name` as lua_<name>,
// or luaL_<rest> for names starting with "L_".
#define IEX_LUA_API(X)                                                                        \
    X(gettop, int, (lua_State*))                                                             \
    X(settop, void, (lua_State*, int))                                                       \
    X(pushvalue, void, (lua_State*, int))                                                    \
    X(insert, void, (lua_State*, int))                                                       \
    X(type, int, (lua_State*, int))                                                          \
    X(tolstring, const char*, (lua_State*, int, std::size_t*))                               \
    X(tointegerx, lua_Integer, (lua_State*, int, int*))                                      \
    X(tonumberx, lua_Number, (lua_State*, int, int*))                                        \
    X(toboolean, int, (lua_State*, int))                                                     \
    X(touserdata, void*, (lua_State*, int))                                                  \
    X(iscfunction, int, (lua_State*, int))                                                   \
    X(tocfunction, lua_CFunction, (lua_State*, int))                                         \
    X(pushnil, void, (lua_State*))                                                           \
    X(pushinteger, void, (lua_State*, lua_Integer))                                          \
    X(pushnumber, void, (lua_State*, lua_Number))                                            \
    X(pushboolean, void, (lua_State*, int))                                                  \
    X(pushstring, const char*, (lua_State*, const char*))                                    \
    X(pushlstring, const char*, (lua_State*, const char*, std::size_t))                      \
    X(pushcclosure, void, (lua_State*, lua_CFunction, int))                                  \
    X(pushlightuserdata, void, (lua_State*, void*))                                          \
    X(createtable, void, (lua_State*, int, int))                                             \
    X(newuserdata, void*, (lua_State*, std::size_t))                                         \
    X(setmetatable, int, (lua_State*, int))                                                  \
    X(getmetatable, int, (lua_State*, int))                                                  \
    X(rawequal, int, (lua_State*, int, int))                                                 \
    X(getfield, void, (lua_State*, int, const char*))                                        \
    X(setfield, void, (lua_State*, int, const char*))                                        \
    X(rawseti, void, (lua_State*, int, int))                                                 \
    X(rawget, void, (lua_State*, int))                                                       \
    X(rawset, void, (lua_State*, int))                                                       \
    X(getglobal, void, (lua_State*, const char*))                                            \
    X(setglobal, void, (lua_State*, const char*))                                            \
    X(pcallk, int, (lua_State*, int, int, int, int, lua_CFunction))                          \
    X(error, int, (lua_State*))                                                              \
    X(L_loadbufferx, int, (lua_State*, const char*, std::size_t, const char*, const char*)) \
    X(L_newmetatable, int, (lua_State*, const char*))                                        \
    X(L_checkudata, void*, (lua_State*, int, const char*))

struct LuaApi {
#define IEX_LUA_FIELD(name, ret, params) ret(*name) params = nullptr;
    IEX_LUA_API(IEX_LUA_FIELD)
#undef IEX_LUA_FIELD

    bool Complete() const
    {
#define IEX_LUA_CHECK(name, ret, params) \
    if (!name)                           \
        return false;
        IEX_LUA_API(IEX_LUA_CHECK)
#undef IEX_LUA_CHECK
        return true;
    }
};

extern LuaApi lua;

// Raises a Lua error with a formatted message (never returns).
[[noreturn]] void LuaError(lua_State* L, const char* fmt, ...);

} // namespace iex
