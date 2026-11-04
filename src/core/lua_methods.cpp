// Native engine methods bound from the engine description's `method` records (see lua_methods.h).
//
// Calling convention: every bound function takes `this` plus at most 5 integer-class arguments and returns an
// integer-class value (or nothing), so one C++ call through a pointer typed with uintptr_t parameters lands the
// values in the right registers on both ABIs (Windows x64: rcx, rdx, r8, r9, then stack; SysV: rdi, rsi, rdx,
// rcx, r8, r9). Arguments the callee does not declare are ignored by it (caller-cleaned stack, scratch registers).
// A CPoint by value is 8 bytes of two ints: one integer register on both ABIs (MSVC passes 8-byte aggregates in a
// register, SysV classifies it INTEGER). `CPoint const&` is a pointer. Narrow kinds (bool / uchar / short / int)
// are passed widened; callees read only the low bits, and narrow results are masked here.
// A struct by value (`data:<Type>`, only as the first argument) goes through a 64-byte aggregate parameter, so the
// compiler applies its own ABI rule, the same the engine was built with: MSVC passes a pointer to a caller copy,
// SysV copies the bytes to the stack (MEMORY class, no register used). The struct must fit in 64 bytes and be
// trivially copyable in the engine (checked per function: CButtonData, 0x34 bytes, read from the stack on Linux).
// A `static` first argument kind marks a function without `this` (called as Class.Name(...)).
#include "lua_methods.h"

#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstdint>
#include <cstring>
#include <deque>
#include <string>

namespace iex {

namespace {

using Word = std::uintptr_t;

enum class Arg : std::uint8_t { Bool, I8, U8, I16, U16, I32, U32, I64, Ptr, Point, PointRef, Data };
enum class Ret : std::uint8_t { Void, Bool, I8, U8, I16, U16, I32, U32, I64, Ptr, Object };

constexpr int kMaxArgs = 5;  // + this

struct Bound {
    const MethodDesc* desc;
    const TypeDesc* owner;
    Word function;  // absolute address (direct calls)
    Ret ret;
    const TypeDesc* retType;  // Ret::Object
    int argCount;
    Arg args[kMaxArgs];
    const TypeDesc* argTypes[kMaxArgs];  // Arg::Data
    bool isStatic;
};

// Struct passed by value (see the header comment).
struct Aggregate {
    alignas(8) unsigned char bytes[64];
};

std::deque<Bound> g_bound;  // stable addresses: closures keep a light userdata to their entry

bool ParseArg(const std::string& s, Arg& a, const TypeDesc*& type)
{
    if (s.rfind("data:", 0) == 0) {
        type = engineTypes.Get(s.substr(5));
        a = Arg::Data;
        return type != nullptr && type->size > 0 && type->size <= sizeof(Aggregate);
    }
    static const std::pair<const char*, Arg> kinds[] = {
        {"bool", Arg::Bool}, {"i8", Arg::I8}, {"u8", Arg::U8}, {"i16", Arg::I16}, {"u16", Arg::U16},
        {"i32", Arg::I32}, {"u32", Arg::U32}, {"i64", Arg::I64}, {"ptr", Arg::Ptr}, {"point", Arg::Point},
        {"pointref", Arg::PointRef},
    };
    for (const auto& [name, kind] : kinds) {
        if (s == name) {
            a = kind;
            return true;
        }
    }
    return false;
}

bool ParseRet(const std::string& s, Ret& r, const TypeDesc*& type)
{
    static const std::pair<const char*, Ret> kinds[] = {
        {"void", Ret::Void}, {"bool", Ret::Bool}, {"i8", Ret::I8}, {"u8", Ret::U8}, {"i16", Ret::I16},
        {"u16", Ret::U16}, {"i32", Ret::I32}, {"u32", Ret::U32}, {"i64", Ret::I64}, {"ptr", Ret::Ptr},
    };
    for (const auto& [name, kind] : kinds) {
        if (s == name) {
            r = kind;
            return true;
        }
    }
    if (s.rfind("obj:", 0) == 0) {
        type = engineTypes.Get(s.substr(4));
        r = Ret::Object;
        return type != nullptr;
    }
    return false;
}

bool IsA(const TypeDesc* type, const TypeDesc* base)
{
    if (type == base)
        return true;
    for (const auto& [b, offset] : type->bases) {
        if (offset == 0 && IsA(b, base))
            return true;
    }
    return false;
}

// CPoint value from a CPoint object or a {x=, y=} table.
bool ReadPoint(lua_State* L, int index, std::int32_t& x, std::int32_t& y)
{
    if (const Word p = ToObjectAddress(L, index)) {
        std::memcpy(&x, reinterpret_cast<const void*>(p), 4);
        std::memcpy(&y, reinterpret_cast<const void*>(p + 4), 4);
        return true;
    }
    if (lua.type(L, index) != LUA_TTABLE)
        return false;
    lua.getfield(L, index, "x");
    lua.getfield(L, index, "y");
    int okX = 0, okY = 0;
    x = static_cast<std::int32_t>(lua.tointegerx(L, -2, &okX));
    y = static_cast<std::int32_t>(lua.tointegerx(L, -1, &okY));
    lua.settop(L, -3);
    return okX && okY;
}

Word Integer(lua_State* L, int index, const Bound& b, int n)
{
    if (lua.type(L, index) == LUA_TBOOLEAN)
        return lua.toboolean(L, index) ? 1 : 0;
    int ok = 0;
    const lua_Integer v = lua.tointegerx(L, index, &ok);
    if (!ok)
        LuaError(L, "IEX: %s:%s: argument %d must be a number", b.desc->className.c_str(), b.desc->luaName.c_str(), n);
    return static_cast<Word>(static_cast<std::int64_t>(v));
}

void PushResult(lua_State* L, const Bound& b, Word r)
{
    switch (b.ret) {
    case Ret::Void: break;
    case Ret::Bool: lua.pushboolean(L, (r & 0xff) != 0); break;
    case Ret::I8: lua.pushinteger(L, static_cast<std::int8_t>(r)); break;
    case Ret::U8: lua.pushinteger(L, static_cast<std::uint8_t>(r)); break;
    case Ret::I16: lua.pushinteger(L, static_cast<std::int16_t>(r)); break;
    case Ret::U16: lua.pushinteger(L, static_cast<std::uint16_t>(r)); break;
    case Ret::I32: lua.pushinteger(L, static_cast<std::int32_t>(r)); break;
    case Ret::U32: lua.pushinteger(L, static_cast<std::uint32_t>(r)); break;
    case Ret::I64:
    case Ret::Ptr: lua.pushinteger(L, static_cast<lua_Integer>(r)); break;
    case Ret::Object: PushObject(L, r, b.retType); break;
    }
}

} // namespace

int CallNativeMethod(lua_State* L)
{
    const auto* b = static_cast<const Bound*>(lua.touserdata(L, LuaUpvalueIndex(1)));
    Word self = 0;
    if (!b->isStatic) {
        self = ToObjectAddress(L, 1);
        if (!self)
            LuaError(L, "IEX: %s:%s: called without an engine object (use ':')", b->desc->className.c_str(),
                     b->desc->luaName.c_str());
        const TypeDesc* type = ToObjectType(L, 1);
        if (!type || !IsA(type, b->owner))
            LuaError(L, "IEX: %s:%s: object is a %s", b->desc->className.c_str(), b->desc->luaName.c_str(),
                     type ? type->name.c_str() : "handle");
    }
    const int first = b->isStatic ? 1 : 2;  // Lua index of the first argument

    Word a[kMaxArgs] = {};
    std::int32_t points[kMaxArgs][2] = {};
    Aggregate data{};
    bool hasData = false;
    for (int i = 0; i < b->argCount; ++i) {
        const int index = i + first;
        switch (b->args[i]) {
        case Arg::Bool:
            a[i] = lua.type(L, index) == LUA_TNUMBER ? (lua.tointegerx(L, index, nullptr) != 0) : (lua.toboolean(L, index) != 0);
            break;
        case Arg::I8: case Arg::U8: case Arg::I16: case Arg::U16: case Arg::I32: case Arg::U32: case Arg::I64:
            a[i] = Integer(L, index, *b, i + 1);
            break;
        case Arg::Ptr: {
            Word p = ToObjectAddress(L, index);
            if (!p && lua.type(L, index) == LUA_TNUMBER)
                p = static_cast<Word>(lua.tointegerx(L, index, nullptr));
            a[i] = p;
            break;
        }
        case Arg::Point:
        case Arg::PointRef: {
            std::int32_t x = 0, y = 0;
            const Word object = ToObjectAddress(L, index);
            if (b->args[i] == Arg::PointRef && object) {
                a[i] = object;
                break;
            }
            if (!ReadPoint(L, index, x, y))
                LuaError(L, "IEX: %s:%s: argument %d must be a CPoint or {x=, y=}", b->desc->className.c_str(),
                         b->desc->luaName.c_str(), i + 1);
            points[i][0] = x;
            points[i][1] = y;
            if (b->args[i] == Arg::PointRef) {
                a[i] = reinterpret_cast<Word>(points[i]);
            } else {
                std::uint64_t packed = 0;
                std::memcpy(&packed, points[i], 8);
                a[i] = static_cast<Word>(packed);
            }
            break;
        }
        case Arg::Data: {
            const Word p = ToObjectAddress(L, index);
            if (!p)
                LuaError(L, "IEX: %s:%s: argument %d must be a %s object", b->desc->className.c_str(),
                         b->desc->luaName.c_str(), i + 1, b->argTypes[i]->name.c_str());
            std::memcpy(data.bytes, reinterpret_cast<const void*>(p), b->argTypes[i]->size);
            hasData = true;
            break;
        }
        }
    }

    Word fn = b->function;
    if (b->desc->isVirtual) {
        Word vtable = 0;
        std::memcpy(&vtable, reinterpret_cast<const void*>(self), sizeof(vtable));
        std::memcpy(&fn, reinterpret_cast<const void*>(vtable + b->desc->target), sizeof(fn));
    }
    Word r = 0;
    if (hasData) {  // the struct is argument 1 (checked when bound)
        if (b->isStatic)
            r = reinterpret_cast<Word (*)(Aggregate, Word, Word, Word, Word)>(fn)(data, a[1], a[2], a[3], a[4]);
        else
            r = reinterpret_cast<Word (*)(Word, Aggregate, Word, Word, Word, Word)>(fn)(self, data, a[1], a[2], a[3], a[4]);
    } else if (b->isStatic) {
        r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(fn)(a[0], a[1], a[2], a[3], a[4]);
    } else {
        using Fn = Word (*)(Word, Word, Word, Word, Word, Word);
        r = reinterpret_cast<Fn>(fn)(self, a[0], a[1], a[2], a[3], a[4]);
    }
    PushResult(L, *b, r);
    return b->ret == Ret::Void ? 0 : 1;
}

bool PushNativeMethod(lua_State* L, const char* className, const char* key)
{
    lua.getfield(L, LUA_REGISTRYINDEX, "IEX.Methods");
    if (lua.type(L, -1) == LUA_TTABLE) {
        lua.getfield(L, -1, className);
        if (lua.type(L, -1) == LUA_TTABLE) {
            lua.getfield(L, -1, key);
            if (lua.type(L, -1) != LUA_TNIL) {
                lua.insert(L, -3);
                lua.settop(L, -3);
                return true;
            }
            lua.settop(L, -2);
        }
        lua.settop(L, -2);
    }
    lua.settop(L, -2);
    return false;
}

void OpenLuaMethods(lua_State* L)
{
    lua.createtable(L, 0, 8);
    lua.setfield(L, LUA_REGISTRYINDEX, "IEX.Methods");
    int bound = 0;
    for (const MethodDesc& m : engineTypes.Methods()) {
        Bound b{};
        b.desc = &m;
        b.owner = engineTypes.Get(m.className);
        std::vector<std::string> args = m.args;
        b.isStatic = !args.empty() && args[0] == "static";
        if (b.isStatic)
            args.erase(args.begin());
        bool ok = b.owner && ParseRet(m.ret, b.ret, b.retType) && args.size() <= kMaxArgs;
        b.argCount = static_cast<int>(args.size());
        for (int i = 0; ok && i < b.argCount; ++i) {
            ok = ParseArg(args[i], b.args[i], b.argTypes[i]);
            if (ok && b.args[i] == Arg::Data && i != 0)
                ok = false;  // only a leading struct argument is supported
        }
        if (!ok) {
            Log("Method %s:%s not bound: unknown class or argument kind", m.className.c_str(), m.luaName.c_str());
            continue;
        }
        if (b.isStatic && m.isVirtual)
            ok = false;
        if (!ok) {
            Log("Method %s:%s not bound: unsupported static/struct argument", m.className.c_str(), m.luaName.c_str());
            continue;
        }
        b.function = m.isVirtual ? 0 : EngineImageBase() + m.target;
        g_bound.push_back(b);
        lua.getglobal(L, m.className.c_str());
        if (lua.type(L, -1) != LUA_TTABLE) {
            lua.settop(L, -2);
            lua.createtable(L, 0, 0);
            lua.pushvalue(L, -1);
            lua.setglobal(L, m.className.c_str());
        }
        lua.pushlightuserdata(L, &g_bound.back());
        lua.pushcclosure(L, CallNativeMethod, 1);
        lua.pushvalue(L, -1);
        lua.setfield(L, -3, m.luaName.c_str());  // class table
        // registry["IEX.Methods"][class][name]
        lua.getfield(L, LUA_REGISTRYINDEX, "IEX.Methods");
        lua.getfield(L, -1, m.className.c_str());
        if (lua.type(L, -1) != LUA_TTABLE) {
            lua.settop(L, -2);
            lua.createtable(L, 0, 4);
            lua.pushvalue(L, -1);
            lua.setfield(L, -3, m.className.c_str());
        }
        lua.pushvalue(L, -3);
        lua.setfield(L, -2, m.luaName.c_str());
        lua.settop(L, -5);
        ++bound;
    }
    Log("Engine methods bound: %d", bound);
}

} // namespace iex
