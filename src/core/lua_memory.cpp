// EEex raw memory API: heap blocks, typed reads and writes at any address, C strings, game code protection,
// executable memory near the image, engine Lua API labels and machine code exposed as Lua functions.
// Addresses are Lua numbers (Lua 5.2 doubles: exact for every user-space address). Only addresses in the
// first 64 KiB are rejected (a Lua error instead of a crash): that range is never mapped on Windows or Linux
// (vm.mmap_min_addr), and it is what a field offset added to a null object gives
// (EEex_ReadPointer(EEex_UDToPtr(nil) + 0x18)). On Linux, typed reads / writes and strings also check that the
// address is mapped (platform::MemoryReadable): mods probe Windows code addresses (SadoEE's M_SQ0BLD.lua build
// check reads 0x140374940 in a pcall), which are unmapped there. Any other bad address still crashes the game,
// as with EEex.
#include "lua_memory.h"

#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "platform_memory.h"

#include <chrono>
#include <map>
#include <string>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>

namespace iex {

namespace {

// Lowest address accepted: below it is the never-mapped null page range.
constexpr std::uintptr_t kMinAddress = 0x10000;

std::uintptr_t CheckAddress(lua_State* L, int index, const char* fn, std::size_t size = 1)
{
    int isNumber = 0;
    const auto address = static_cast<std::uintptr_t>(lua.tointegerx(L, index, &isNumber));
    if (!isNumber)
        LuaError(L, "%s: address expected (got no number)", fn);
    if (address < kMinAddress)
        LuaError(L, "%s: null address (0x%llx, a field of a null object?)", fn,
                 static_cast<unsigned long long>(address));
    if (!platform::MemoryReadable(address, size))
        LuaError(L, "%s: unmapped address 0x%llx", fn, static_cast<unsigned long long>(address));
    return address;
}

std::uint64_t ArgBits(lua_State* L, int index)
{
    return static_cast<std::uint64_t>(lua.tointegerx(L, index, nullptr));
}

template <typename T>
T Load(std::uintptr_t address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

template <typename T>
void Store(std::uintptr_t address, T value)
{
    std::memcpy(reinterpret_cast<void*>(address), &value, sizeof(T));
}

// EEex_Read<T>(address) -> value (signed types sign-extend, unsigned ones zero-extend).
template <typename T>
int LuaRead(lua_State* L)
{
    lua.pushinteger(L, static_cast<lua_Integer>(Load<T>(CheckAddress(L, 1, "EEex_Read", sizeof(T)))));
    return 1;
}

// EEex_Write<N>(address, value): stores the low N bits of value (64-bit and pointer writes).
template <typename T>
int LuaWrite(lua_State* L)
{
    Store<T>(CheckAddress(L, 1, "EEex_Write", sizeof(T)), static_cast<T>(ArgBits(L, 2)));
    return 0;
}

// EEex_Write8/16/32 and EEex_WriteU8/U16/U32(address, value): the value must fit the type, like EEex
// ("arg #2 (200) too large (max: 127)", "arg #2 (-1) too small (min: 0)").
template <typename T>
int LuaWriteChecked(lua_State* L)
{
    const std::uintptr_t address = CheckAddress(L, 1, "EEex_Write");
    const auto value = static_cast<long long>(lua.tointegerx(L, 2, nullptr));
    const auto lo = static_cast<long long>(std::numeric_limits<T>::min());
    const auto hi = static_cast<long long>(std::numeric_limits<T>::max());
    if (value > hi)
        LuaError(L, "arg #2 (%lld) too large (max: %lld)", value, hi);
    if (value < lo)
        LuaError(L, "arg #2 (%lld) too small (min: %lld)", value, lo);
    Store<T>(address, static_cast<T>(value));
    return 0;
}

// EEex_Memcpy(destination, source, size) / EEex_Memset(address, byte, size).
int LuaMemcpy(lua_State* L)
{
    const std::uintptr_t dst = CheckAddress(L, 1, "EEex_Memcpy");
    const std::uintptr_t src = CheckAddress(L, 2, "EEex_Memcpy");
    const lua_Integer n = lua.tointegerx(L, 3, nullptr);
    if (n > 0)
        std::memmove(reinterpret_cast<void*>(dst), reinterpret_cast<const void*>(src), static_cast<std::size_t>(n));
    return 0;
}

int LuaMemset(lua_State* L)
{
    const std::uintptr_t dst = CheckAddress(L, 1, "EEex_Memset");
    const auto value = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    const lua_Integer n = lua.tointegerx(L, 3, nullptr);
    if (n > 0)
        std::memset(reinterpret_cast<void*>(dst), value & 0xFF, static_cast<std::size_t>(n));
    return 0;
}

// EEex_Malloc(size) -> address of `size` zeroed bytes, kept until EEex_Free.
int LuaMalloc(lua_State* L)
{
    const lua_Integer size = lua.tointegerx(L, 1, nullptr);
    if (size <= 0)
        LuaError(L, "EEex_Malloc: positive size expected");
    void* p = std::calloc(1, static_cast<std::size_t>(size));
    if (!p)
        LuaError(L, "EEex_Malloc: out of memory (%lld bytes)", static_cast<long long>(size));
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<std::uintptr_t>(p)));
    return 1;
}

// EEex_Free(address): releases an EEex_Malloc block (nil / 0 is ignored).
int LuaFree(lua_State* L)
{
    std::free(reinterpret_cast<void*>(static_cast<std::uintptr_t>(lua.tointegerx(L, 1, nullptr))));
    return 0;
}

// EEex_ReadString(address) -> text up to the first NUL.
int LuaReadString(lua_State* L)
{
    lua.pushstring(L, reinterpret_cast<const char*>(CheckAddress(L, 1, "EEex_ReadString")));
    return 1;
}

// EEex_ReadLString(address, maxLen) -> text up to the first NUL or maxLen bytes.
int LuaReadLString(lua_State* L)
{
    const auto* p = reinterpret_cast<const char*>(CheckAddress(L, 1, "EEex_ReadLString"));
    const lua_Integer max = lua.tointegerx(L, 2, nullptr);
    std::size_t len = 0;
    while (static_cast<lua_Integer>(len) < max && p[len])
        ++len;
    lua.pushlstring(L, p, len);
    return 1;
}

// EEex_WriteString(address, text): writes text and its NUL terminator.
int LuaWriteString(lua_State* L)
{
    const std::uintptr_t address = CheckAddress(L, 1, "EEex_WriteString");
    std::size_t len = 0;
    const char* text = lua.tolstring(L, 2, &len);
    if (!text)
        LuaError(L, "EEex_WriteString: string expected");
    std::memcpy(reinterpret_cast<void*>(address), text, len + 1);
    return 0;
}

// EEex_WriteLString(address, text, len): writes exactly len bytes, text truncated or NUL-padded (no terminator
// when text fills them all).
int LuaWriteLString(lua_State* L)
{
    const std::uintptr_t address = CheckAddress(L, 1, "EEex_WriteLString");
    std::size_t textLen = 0;
    const char* text = lua.tolstring(L, 2, &textLen);
    if (!text)
        LuaError(L, "EEex_WriteLString: string expected");
    const lua_Integer len = lua.tointegerx(L, 3, nullptr);
    if (len <= 0)
        return 0;
    const auto n = static_cast<std::size_t>(len);
    auto* dst = reinterpret_cast<char*>(address);
    const std::size_t copied = textLen < n ? textLen : n;
    std::memcpy(dst, text, copied);
    std::memset(dst + copied, 0, n - copied);
    return 0;
}

// EEex_DisableCodeProtection() / EEex_EnableCodeProtection(): the game's code is writable between the two.
// Calls nest: protection comes back with the last Enable.
int g_unprotectDepth = 0;

int LuaDisableCodeProtection(lua_State*)
{
    if (g_unprotectDepth++ == 0 && !platform::SetImageCodeWritable(true))
        Log("Memory: cannot make the game code writable");
    return 0;
}

int LuaEnableCodeProtection(lua_State*)
{
    if (g_unprotectDepth > 0 && --g_unprotectDepth == 0 && !platform::SetImageCodeWritable(false))
        Log("Memory: cannot restore the game code protection");
    return 0;
}

// EEex_AllocNear(size) -> address of executable (and writable) memory within rel32 reach of the game code.
int LuaAllocNear(lua_State* L)
{
    const lua_Integer size = lua.tointegerx(L, 1, nullptr);
    if (size <= 0)
        LuaError(L, "EEex_AllocNear: positive size expected");
    void* p = platform::AllocExecNear(EngineImageBase(), static_cast<std::size_t>(size));
    if (!p)
        LuaError(L, "EEex_AllocNear: no executable memory near the game image (%lld bytes)",
                 static_cast<long long>(size));
    std::memset(p, 0xCC, static_cast<std::size_t>(size));  // int3 filler, like an unpatched code cave
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<std::uintptr_t>(p)));
    return 1;
}

std::map<std::string, std::uintptr_t>& RuntimeLabels()
{
    static std::map<std::string, std::uintptr_t> labels;
    return labels;
}

// EEex_Label(name) -> address. 'Hardcoded_<symbol>' names an engine function by its unmangled C name
// (Hardcoded_lua_tointegerx, Hardcoded_luaL_checkudata...); any other name is looked up as a symbol of the
// engine description.
int LuaLabel(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name)
        LuaError(L, "EEex_Label: label name expected");
    const auto runtime = RuntimeLabels().find(name);
    if (runtime != RuntimeLabels().end()) {
        lua.pushinteger(L, static_cast<lua_Integer>(runtime->second));
        return 1;
    }
    std::string symbol = name;
    constexpr const char kPrefix[] = "Hardcoded_";
    if (symbol.rfind(kPrefix, 0) == 0)
        symbol.erase(0, sizeof(kPrefix) - 1);
    std::uint32_t rva = engineTypes.Symbol(symbol);
    if (!rva && symbol.find("::") != std::string::npos)
        rva = engineTypes.SymbolByQualifiedName(symbol);
    if (!rva) {
        // Engine code labels of lua/IEX_AsmLabelTable.lua: image-relative (IEX_AsmEngineLabels) or a fixed value
        // a mod compares with (IEX_AsmAbsoluteLabels).
        const char* tables[2] = {"IEX_AsmEngineLabels", "IEX_AsmAbsoluteLabels"};
        for (int i = 0; i < 2; ++i) {
            const int top = lua.gettop(L);
            lua.getglobal(L, tables[i]);
            if (lua.type(L, -1) == LUA_TTABLE) {
                lua.getfield(L, -1, name);
                int isNum = 0;
                const lua_Integer v = lua.tointegerx(L, -1, &isNum);
                lua.settop(L, top);
                if (isNum) {
                    lua.pushinteger(L, i == 0 ? static_cast<lua_Integer>(EngineImageBase() + v) : v);
                    return 1;
                }
            }
            lua.settop(L, top);
        }
        LuaError(L, "EEex_Label: unknown label '%s' (no symbol '%s' in the engine description)", name,
                 symbol.c_str());
    }
    lua.pushinteger(L, static_cast<lua_Integer>(EngineImageBase() + rva));
    return 1;
}

// EEex_ExposeToLua(address, name): global `name` calls the machine code at address as a lua_CFunction.
int LuaExposeToLua(lua_State* L)
{
    const std::uintptr_t address = CheckAddress(L, 1, "EEex_ExposeToLua");
    const char* name = lua.tolstring(L, 2, nullptr);
    if (!name)
        LuaError(L, "EEex_ExposeToLua: global name expected");
    lua.pushcclosure(L, reinterpret_cast<lua_CFunction>(address), 0);
    lua.setglobal(L, name);
    return 0;
}

// EEex_Utility_GetMicroseconds() -> microseconds from a monotonic clock (for timing, not wall time).
int LuaGetMicroseconds(lua_State* L)
{
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    lua.pushinteger(L, static_cast<lua_Integer>(std::chrono::duration_cast<std::chrono::microseconds>(now).count()));
    return 1;
}

// EEex_GetImageBase() -> load address of the game executable.
int LuaGetImageBase(lua_State* L)
{
    lua.pushinteger(L, static_cast<lua_Integer>(EngineImageBase()));
    return 1;
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

void OpenLuaMemory(lua_State* L)
{
    // Platform and image base for the engine label table (lua/IEX_AsmLabelTable.lua).
#if defined(_WIN32)
    lua.pushstring(L, "win64");
#else
    lua.pushstring(L, "linux64");
#endif
    lua.setglobal(L, "IEX_Platform");
    lua.pushinteger(L, static_cast<lua_Integer>(EngineImageBase()));
    lua.setglobal(L, "IEX_ImageBase");
    Register(L, "EEex_Malloc", LuaMalloc);
    Register(L, "EEex_Free", LuaFree);

    Register(L, "EEex_ReadU8", LuaRead<std::uint8_t>);
    Register(L, "EEex_ReadU16", LuaRead<std::uint16_t>);
    Register(L, "EEex_ReadU32", LuaRead<std::uint32_t>);
    Register(L, "EEex_ReadU64", LuaRead<std::uint64_t>);
    Register(L, "EEex_Read8", LuaRead<std::int8_t>);
    Register(L, "EEex_Read16", LuaRead<std::int16_t>);
    Register(L, "EEex_Read32", LuaRead<std::int32_t>);
    Register(L, "EEex_Read64", LuaRead<std::int64_t>);
    Register(L, "EEex_ReadPointer", LuaRead<std::uintptr_t>);
    Register(L, "EEex_ReadPtr", LuaRead<std::uintptr_t>);

    Register(L, "EEex_Write8", LuaWriteChecked<std::int8_t>);
    Register(L, "EEex_Write16", LuaWriteChecked<std::int16_t>);
    Register(L, "EEex_Write32", LuaWriteChecked<std::int32_t>);
    Register(L, "EEex_Write64", LuaWrite<std::uint64_t>);
    Register(L, "EEex_WriteU8", LuaWriteChecked<std::uint8_t>);
    Register(L, "EEex_WriteU16", LuaWriteChecked<std::uint16_t>);
    Register(L, "EEex_WriteU32", LuaWriteChecked<std::uint32_t>);
    Register(L, "EEex_WriteU64", LuaWrite<std::uint64_t>);
    Register(L, "EEex_WritePointer", LuaWrite<std::uintptr_t>);
    // Pre-1.x EEex names (not in EEex 1.3.1): low bits stored, no range check, as old mods expect
    Register(L, "EEex_WriteByte", LuaWrite<std::uint8_t>);
    Register(L, "EEex_WriteWord", LuaWrite<std::uint16_t>);
    Register(L, "EEex_WriteDword", LuaWrite<std::uint32_t>);
    Register(L, "EEex_WritePtr", LuaWrite<std::uintptr_t>);
    Register(L, "EEex_Memcpy", LuaMemcpy);
    Register(L, "EEex_Memset", LuaMemset);

    Register(L, "EEex_ReadString", LuaReadString);
    Register(L, "EEex_ReadLString", LuaReadLString);
    Register(L, "EEex_WriteString", LuaWriteString);
    Register(L, "EEex_WriteLString", LuaWriteLString);

    Register(L, "EEex_DisableCodeProtection", LuaDisableCodeProtection);
    Register(L, "EEex_EnableCodeProtection", LuaEnableCodeProtection);
    Register(L, "EEex_AllocNear", LuaAllocNear);
    Register(L, "EEex_Label", LuaLabel);
    Register(L, "EEex_GetImageBase", LuaGetImageBase);
    Register(L, "EEex_Utility_GetMicroseconds", LuaGetMicroseconds);
    Register(L, "EEex_ExposeToLua", LuaExposeToLua);
}

void RegisterRuntimeLabel(const char* name, std::uintptr_t address)
{
    RuntimeLabels()[name] = address;
}

} // namespace iex
