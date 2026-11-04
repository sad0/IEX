#include "lua_objects.h"

#include "engine_types.h"
#include "iex_core.h"
#include "lua_api.h"
#include "lua_methods.h"

#include <cstdio>
#include <cstring>
#include <string>

namespace iex {

namespace {

constexpr const char* kMeta = "IEX.Object";

// One userdata layout for both flavours:
//   object: `type` set, `kind` null    -> fields resolved through the type registry
//   handle: `kind` set (resref, string, array, list) -> :get() / :set()
struct Box {
    std::uintptr_t address;
    const TypeDesc* type;
    const FieldKind* kind;
};

void PushBox(lua_State* L, std::uintptr_t address, const TypeDesc* type, const FieldKind* kind)
{
    auto* box = static_cast<Box*>(lua.newuserdata(L, sizeof(Box)));
    *box = Box{address, type, kind};
    lua.L_newmetatable(L, kMeta);  // existing metatable after the first call
    lua.setmetatable(L, -2);
}

Box* CheckBox(lua_State* L, int index)
{
    return static_cast<Box*>(lua.L_checkudata(L, index, kMeta));
}

template <typename T>
T Read(std::uintptr_t address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

template <typename T>
void Write(std::uintptr_t address, T value)
{
    std::memcpy(reinterpret_cast<void*>(address), &value, sizeof(T));
}

void PushBoundedString(lua_State* L, std::uintptr_t address, std::size_t max)
{
    const char* s = reinterpret_cast<const char*>(address);
    std::size_t n = 0;
    while (n < max && s[n])
        ++n;
    lua.pushlstring(L, s, n);
}

// Pushes the value of a field of `kind` stored at `address`.
void PushValue(lua_State* L, std::uintptr_t address, const FieldKind* kind)
{
    switch (kind->kind) {
    case Kind::I8: lua.pushinteger(L, Read<std::int8_t>(address)); break;
    case Kind::U8: lua.pushinteger(L, Read<std::uint8_t>(address)); break;
    case Kind::I16: lua.pushinteger(L, Read<std::int16_t>(address)); break;
    case Kind::U16: lua.pushinteger(L, Read<std::uint16_t>(address)); break;
    case Kind::I32: lua.pushinteger(L, Read<std::int32_t>(address)); break;
    case Kind::U32: lua.pushinteger(L, Read<std::uint32_t>(address)); break;
    case Kind::I64: lua.pushinteger(L, static_cast<lua_Integer>(Read<std::int64_t>(address))); break;
    case Kind::U64: lua.pushinteger(L, static_cast<lua_Integer>(Read<std::uint64_t>(address))); break;
    case Kind::F32: lua.pushnumber(L, Read<float>(address)); break;
    case Kind::F64: lua.pushnumber(L, Read<double>(address)); break;
    case Kind::Bool: lua.pushboolean(L, Read<std::uint8_t>(address) != 0); break;
    case Kind::CharPtr: {
        const auto p = Read<std::uintptr_t>(address);
        if (p)
            lua.pushstring(L, reinterpret_cast<const char*>(p));
        else
            lua.pushnil(L);
        break;
    }
    case Kind::Struct: PushObject(L, address, kind->type); break;
    case Kind::Ptr: {
        const auto p = Read<std::uintptr_t>(address);
        if (!kind->type)
            lua.pushinteger(L, static_cast<lua_Integer>(p));
        else
            PushObject(L, p, kind->type);
        break;
    }
    case Kind::ResRef:
    case Kind::CString:
    case Kind::Chars:
    case Kind::Array:
    case Kind::List: PushBox(L, address, nullptr, kind); break;
    }
}

void WriteValue(lua_State* L, std::uintptr_t address, const FieldKind* kind, int valueIndex)
{
    const auto integer = [&] { return lua.tointegerx(L, valueIndex, nullptr); };
    switch (kind->kind) {
    case Kind::I8: case Kind::U8: Write<std::uint8_t>(address, static_cast<std::uint8_t>(integer())); break;
    case Kind::I16: case Kind::U16: Write<std::uint16_t>(address, static_cast<std::uint16_t>(integer())); break;
    case Kind::I32: case Kind::U32: Write<std::uint32_t>(address, static_cast<std::uint32_t>(integer())); break;
    case Kind::I64: case Kind::U64: Write<std::uint64_t>(address, static_cast<std::uint64_t>(integer())); break;
    case Kind::F32: Write<float>(address, static_cast<float>(lua.tonumberx(L, valueIndex, nullptr))); break;
    case Kind::F64: Write<double>(address, lua.tonumberx(L, valueIndex, nullptr)); break;
    case Kind::Bool: Write<std::uint8_t>(address, lua.toboolean(L, valueIndex) ? 1 : 0); break;
    case Kind::Ptr: {
        std::uintptr_t p = ToObjectAddress(L, valueIndex);
        if (!p && lua.type(L, valueIndex) == LUA_TNUMBER)
            p = static_cast<std::uintptr_t>(integer());
        Write<std::uintptr_t>(address, p);
        break;
    }
    case Kind::ResRef:
    case Kind::Chars: {
        const std::size_t max = kind->kind == Kind::ResRef ? 8 : kind->count;
        std::size_t len = 0;
        const char* s = lua.tolstring(L, valueIndex, &len);
        char* dst = reinterpret_cast<char*>(address);
        std::memset(dst, 0, max);
        std::memcpy(dst, s ? s : "", len < max ? len : max);
        break;
    }
    default: LuaError(L, "IEX: this field cannot be assigned");
    }
}

// handle:get([index])
int HandleGet(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    if (!box->kind)
        LuaError(L, "IEX: get() called on an object, not a field handle");
    const FieldKind* k = box->kind;
    switch (k->kind) {
    case Kind::ResRef: PushBoundedString(L, box->address, 8); break;
    case Kind::Chars: PushBoundedString(L, box->address, k->count); break;
    case Kind::CString: {
        const auto p = Read<std::uintptr_t>(box->address);
        lua.pushstring(L, p ? reinterpret_cast<const char*>(p) : "");
        break;
    }
    case Kind::I8: case Kind::U8: case Kind::I16: case Kind::U16: case Kind::I32: case Kind::U32: case Kind::I64:
    case Kind::U64: case Kind::F32: case Kind::F64: case Kind::Bool: case Kind::Ptr:
        PushValue(L, box->address, k);  // element reference of a primitive / pointer array (getReference)
        break;
    case Kind::Array: {
        // EEex: arrays have no value of their own, get() needs the (0-based) index
        int isNumber = 0;
        const lua_Integer i = lua.tointegerx(L, 2, &isNumber);
        if (!isNumber)
            LuaError(L, "IEX: array get(index): index expected");
        if (i < 0 || static_cast<std::uint32_t>(i) >= k->count) {
            lua.pushnil(L);  // EEex reads past the end (0 / nil there); IEX never reads outside the array
            break;
        }
        PushValue(L, box->address + static_cast<std::uintptr_t>(i) * k->element->Size(), k->element);
        break;
    }
    default: LuaError(L, "IEX: get() is not supported on this field");
    }
    return 1;
}

// array:getReference(index): the element itself (EEex). Embedded objects, lists (a CPtrList usable by
// EEex_Utility_IterateCPtrList), strings and sub-arrays come back as for get(); a pointer element as a reference
// whose .reference is the pointed-to object (nil for a null pointer); a primitive element as a reference with
// .value / :get() / :set(v). Out of range: nil (EEex).
int HandleGetReference(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    if (!box->kind || box->kind->kind != Kind::Array)
        LuaError(L, "IEX: getReference() is only defined on arrays");
    const FieldKind* k = box->kind;
    int isNumber = 0;
    const lua_Integer i = lua.tointegerx(L, 2, &isNumber);
    if (!isNumber)
        LuaError(L, "IEX: array getReference(index): index expected");
    if (i < 0 || static_cast<std::uint32_t>(i) >= k->count) {
        lua.pushnil(L);
        return 1;
    }
    const std::uintptr_t address = box->address + static_cast<std::uintptr_t>(i) * k->element->Size();
    switch (k->element->kind) {
    case Kind::Struct:
    case Kind::ResRef:
    case Kind::CString:
    case Kind::Chars:
    case Kind::Array:
    case Kind::List: PushValue(L, address, k->element); break;
    default: PushBox(L, address, nullptr, k->element); break;
    }
    return 1;
}

// handle:set([index,] value)
int HandleSet(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    if (!box->kind)
        LuaError(L, "IEX: set() called on an object, not a field handle");
    const FieldKind* k = box->kind;
    if (k->kind == Kind::Array) {
        const lua_Integer i = lua.tointegerx(L, 2, nullptr);
        if (i < 0 || static_cast<std::uint32_t>(i) >= k->count)
            LuaError(L, "IEX: array index %d out of range (0-%u)", static_cast<int>(i), k->count - 1);
        WriteValue(L, box->address + static_cast<std::uintptr_t>(i) * k->element->Size(), k->element, 3);
    } else {
        WriteValue(L, box->address, k, 2);
    }
    return 0;
}

// Box at `index` if the value is one of our userdata (no error otherwise).
const Box* TryBox(lua_State* L, int index)
{
    if (lua.type(L, index) != LUA_TUSERDATA)
        return nullptr;
    const int top = lua.gettop(L);
    const Box* box = nullptr;
    if (lua.getmetatable(L, index)) {
        lua.L_newmetatable(L, kMeta);  // returns the existing one
        if (lua.rawequal(L, -1, -2))
            box = static_cast<const Box*>(lua.touserdata(L, index));
    }
    lua.settop(L, top);
    return box;
}

int AbsIndex(lua_State* L, int index)
{
    return index > 0 || index <= LUA_REGISTRYINDEX ? index : lua.gettop(L) + index + 1;
}

// The engine binds part of its C++ API to Lua with tolua (worldScreen:StepDialog(), game:GetPartyGold()...).
// tolua keeps one metatable per class in the registry (registry["tolua.<name>"] = metatable, registry[metatable] =
// "<name>") and the class's methods in it; the class's global table is that metatable (checked in game: CInfGame,
// CScreenWorld...). True if the table at `index` is one.
bool IsToluaClass(lua_State* L, int index)
{
    index = AbsIndex(L, index);
    if (lua.type(L, index) != LUA_TTABLE)
        return false;
    lua.pushvalue(L, index);
    lua.rawget(L, LUA_REGISTRYINDEX);
    const bool tolua = lua.type(L, -1) == LUA_TSTRING;
    lua.settop(L, -2);
    return tolua;
}

// Pushes a tolua userdata of `address` for the tolua class of `type` (or of its first base that has one).
// The userdata gets a proxy metatable registered under the same class name (tolua's type checks read
// registry[metatable] and tolua_super[metatable]), without tolua's __gc: the object stays the engine's.
bool PushToluaObject(lua_State* L, std::uintptr_t address, const TypeDesc* type)
{
    lua.getfield(L, LUA_REGISTRYINDEX, ("tolua." + type->name).c_str());
    if (!IsToluaClass(L, -1)) {
        lua.settop(L, -2);
        for (const auto& [base, offset] : type->bases) {
            if (PushToluaObject(L, address + offset, base))
                return true;
        }
        return false;
    }
    const int real = lua.gettop(L);
    lua.getfield(L, LUA_REGISTRYINDEX, "IEX.ToluaProxy");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 0);
        lua.pushvalue(L, -1);
        lua.setfield(L, LUA_REGISTRYINDEX, "IEX.ToluaProxy");
    }
    lua.getfield(L, -1, type->name.c_str());
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 2);
        const int proxy = lua.gettop(L);
        lua.pushvalue(L, real);
        lua.setfield(L, proxy, "__index");
        lua.pushvalue(L, proxy);  // registry[proxy] = name
        lua.pushstring(L, type->name.c_str());
        lua.rawset(L, LUA_REGISTRYINDEX);
        lua.getfield(L, LUA_REGISTRYINDEX, "tolua_super");  // tolua_super[proxy] = tolua_super[real]
        if (lua.type(L, -1) == LUA_TTABLE) {
            lua.pushvalue(L, proxy);
            lua.pushvalue(L, real);
            lua.rawget(L, -3);
            lua.rawset(L, -3);
        }
        lua.settop(L, proxy);
        lua.pushvalue(L, proxy);
        lua.setfield(L, proxy - 1, type->name.c_str());
    }
    // stack: real, proxies, proxy
    auto* slot = static_cast<std::uintptr_t*>(lua.newuserdata(L, sizeof(std::uintptr_t)));
    *slot = address;
    lua.pushvalue(L, -2);
    lua.setmetatable(L, -2);
    lua.insert(L, real);
    lua.settop(L, real);
    return true;
}

// Calls the tolua function (upvalue 1) with every IEX object argument turned into a tolua userdata.
int ToluaBridge(lua_State* L)
{
    const int n = lua.gettop(L);
    lua.pushvalue(L, LuaUpvalueIndex(1));
    for (int i = 1; i <= n; ++i) {
        const Box* box = TryBox(L, i);
        if (!(box && box->type && PushToluaObject(L, box->address, box->type)))
            lua.pushvalue(L, i);
    }
    if (lua.pcallk(L, n, LUA_MULTRET, 0, 0, nullptr) != 0)
        lua.error(L);
    return lua.gettop(L) - n;
}

// Methods live in a global Lua table per engine class (CGameSprite, CGameArea...), so mods can add their own
// (`CGameSprite.getPortraitIndex = function(self) ... end`); lookup walks the base classes. Pushes the method
// and returns true when found. A C function of a tolua class table (the engine's own binding) is wrapped by
// ToluaBridge; IEX's native methods (CallNativeMethod closures) and Lua functions are used as they are.
bool PushMethod(lua_State* L, const TypeDesc* type, const char* key)
{
    // Native records first: they bind the full C++ signature, as EEex does; the engine's tolua functions of the
    // same name may take fewer arguments (CScreenWorld::TogglePauseGame).
    if (PushNativeMethod(L, type->name.c_str(), key))
        return true;
    lua.getglobal(L, type->name.c_str());
    if (lua.type(L, -1) == LUA_TTABLE) {
        lua.getfield(L, -1, key);
        if (lua.type(L, -1) != LUA_TNIL) {
            if (lua.iscfunction(L, -1) && lua.tocfunction(L, -1) != CallNativeMethod && IsToluaClass(L, -2))
                lua.pushcclosure(L, ToluaBridge, 1);
            lua.insert(L, -2);
            lua.settop(L, -2);
            return true;
        }
        lua.settop(L, -2);
    }
    lua.settop(L, -2);
    for (const auto& [base, baseOffset] : type->bases) {
        if (PushMethod(L, base, key))
            return true;
    }
    return false;
}

// Mods' own fields on engine objects: IEX_UDPeers[userdata] = { name = value }, a weak-keyed Lua table. As under
// EEex the fields belong to that userdata: another userdata of the same object (a second EEex_GameObject_Get)
// does not see them.
bool PushPeerField(lua_State* L, int ud, const char* key)
{
    lua.getglobal(L, "IEX_UDPeers");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        return false;
    }
    lua.pushvalue(L, ud);
    lua.rawget(L, -2);
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -3);
        return false;
    }
    lua.getfield(L, -1, key);
    if (lua.type(L, -1) == LUA_TNIL) {
        lua.settop(L, -4);
        return false;
    }
    lua.insert(L, -3);
    lua.settop(L, -3);
    return true;
}

void SetPeerField(lua_State* L, int ud, const char* key, int valueIndex)
{
    lua.getglobal(L, "IEX_UDPeers");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 0);
        lua.createtable(L, 0, 1);
        lua.pushstring(L, "k");
        lua.setfield(L, -2, "__mode");
        lua.setmetatable(L, -2);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_UDPeers");
    }
    lua.pushvalue(L, ud);
    lua.rawget(L, -2);
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, ud);
        lua.pushvalue(L, -2);
        lua.rawset(L, -4);
    }
    lua.pushvalue(L, valueIndex);
    lua.setfield(L, -2, key);
    lua.settop(L, -3);
}

int MetaIndex(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    const char* key = lua.tolstring(L, 2, nullptr);
    if (!key)
        LuaError(L, "IEX: field name must be a string");
    if (box->kind) {
        if (!std::strcmp(key, "get"))
            lua.pushcclosure(L, HandleGet, 0);
        else if (!std::strcmp(key, "set"))
            lua.pushcclosure(L, HandleSet, 0);
        else if (!std::strcmp(key, "getReference") && box->kind->kind == Kind::Array)
            lua.pushcclosure(L, HandleGetReference, 0);
        else if (box->kind->kind == Kind::Ptr && !std::strcmp(key, "reference"))
            PushValue(L, box->address, box->kind);  // pointer element reference: the object, nil if null
        else if (!std::strcmp(key, "value") && box->kind->kind != Kind::Array && box->kind->kind != Kind::List &&
                 box->kind->kind != Kind::Struct && box->kind->kind != Kind::Ptr)
            PushValue(L, box->address, box->kind);  // primitive element reference
        else if (box->kind->kind == Kind::Array && !std::strcmp(key, "size"))
            lua.pushinteger(L, static_cast<lua_Integer>(box->kind->count));  // EEex: array.size (element count)
        else if (box->kind->kind == Kind::CString && !std::strcmp(key, "m_pchData"))
            PushBox(L, box->address, nullptr, box->kind);  // EEex: cstring.m_pchData:get() reads the same text
        else if (box->kind->kind == Kind::List) {
            // An embedded list also reads as its CPtrList (m_nCount, m_pNodeHead.data...): node data comes back as
            // an object of the element type for typed lists (as EEex), else an integer (the value itself for id
            // lists).
            static const TypeDesc* ptrList = engineTypes.Get("CPtrList");
            std::uint32_t offset = 0;
            const FieldDesc* field = ptrList ? ptrList->Find(key, offset) : nullptr;
            const TypeDesc* node = box->kind->type ? engineTypes.TypedNode(box->kind->type) : nullptr;
            if (field && node && (!std::strcmp(key, "m_pNodeHead") || !std::strcmp(key, "m_pNodeTail")))
                PushObject(L, Read<std::uintptr_t>(box->address + offset), node);
            else if (field)
                PushValue(L, box->address + offset, field->kind);
            else
                lua.pushnil(L);
        } else
            lua.pushnil(L);
        return 1;
    }
    std::uint32_t offset = 0;
    const FieldDesc* field = box->type ? box->type->Find(key, offset) : nullptr;
    if (field && (!std::strcmp(key, "m_pNodeHead") || !std::strcmp(key, "m_pNodeTail"))) {
        // A list class object (CGameEffectList...): its nodes' data are objects of the element type (as EEex).
        const TypeDesc* element = nullptr;
        for (const TypeDesc* t = box->type; t && !element; t = t->bases.empty() ? nullptr : t->bases[0].first)
            element = t->element;
        if (const TypeDesc* node = engineTypes.TypedNode(element)) {
            PushObject(L, Read<std::uintptr_t>(box->address + offset), node);
            return 1;
        }
    }
    if (field) {
        PushValue(L, box->address + offset, field->kind);
        return 1;
    }
    if (box->type && PushMethod(L, box->type, key))
        return 1;
    if (box->type && PushPeerField(L, 1, key))
        return 1;
    // `array:getReference(i).reference` (pointer arrays) is a pointer element reference (HandleGetReference);
    // an object has no `.reference` (EEex: nil).
    lua.pushnil(L);
    return 1;
}

int MetaNewIndex(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    const char* key = lua.tolstring(L, 2, nullptr);
    if (box->kind && key && box->kind->kind != Kind::Array && box->kind->kind != Kind::List &&
        box->kind->kind != Kind::Struct &&
        (box->kind->kind == Kind::Ptr ? !std::strcmp(key, "reference") : !std::strcmp(key, "value"))) {
        WriteValue(L, box->address, box->kind, 3);
        return 0;
    }
    std::uint32_t offset = 0;
    const FieldDesc* field = (key && box->type) ? box->type->Find(key, offset) : nullptr;
    if (!field && key && box->type && !box->kind) {
        // EEex: a name the class does not have is the mod's own field, kept with the object (IUI++'s radar
        // stores sprite.portrait, sprite.displayed_name... on the sprites it lists and reads them back)
        SetPeerField(L, 1, key, 3);
        return 0;
    }
    if (!field)
        LuaError(L, "IEX: %s has no field '%s'", box->type ? box->type->name.c_str() : "handle", key ? key : "?");
    WriteValue(L, box->address + offset, field->kind, 3);
    return 0;
}

int MetaEq(lua_State* L)
{
    // EEex: an array and its first element (same address) are different values
    const Box* a = CheckBox(L, 1);
    const Box* b = CheckBox(L, 2);
    lua.pushboolean(L, a->address == b->address && (a->kind == nullptr) == (b->kind == nullptr) &&
                           (!a->kind || a->kind->kind == b->kind->kind));
    return 1;
}

// Readable name of a field handle's kind: Array<CPtrList<CCreatureFileMemorizedSpell>,9>, CResRef...
std::string KindName(const FieldKind* k)
{
    switch (k->kind) {
    case Kind::Array: return "Array<" + KindName(k->element) + "," + std::to_string(k->count) + ">";
    case Kind::List: return k->type ? "CPtrList<" + k->type->name + ">" : "CPtrList";
    case Kind::ResRef: return "CResRef";
    case Kind::CString: return "CString";
    case Kind::Chars: return "char[" + std::to_string(k->count) + "]";
    case Kind::Struct: return k->type ? k->type->name : "struct";
    case Kind::Ptr: return k->type ? k->type->name + "*" : "void*";
    default: return "primitive";
    }
}

int MetaToString(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    char text[128];
    std::string name = box->type ? box->type->name : "handle";
    if (box->kind)
        name = KindName(box->kind);
    std::snprintf(text, sizeof(text), "%s@0x%llx", name.c_str(), static_cast<unsigned long long>(box->address));
    lua.pushstring(L, text);
    return 1;
}

// IEX_ToObject(address, typeName) -> object or nil
int LuaToObject(lua_State* L)
{
    std::uintptr_t address = ToObjectAddress(L, 1);
    if (!address)
        address = static_cast<std::uintptr_t>(lua.tointegerx(L, 1, nullptr));
    const char* typeName = lua.tolstring(L, 2, nullptr);
    const TypeDesc* type = typeName ? engineTypes.Get(typeName) : nullptr;
    if (!type)
        LuaError(L, "IEX_ToObject: unknown type '%s'", typeName ? typeName : "?");
    PushObject(L, address, type);
    return 1;
}

// IEX_EngineGlobal(symbol, typeName) -> object pointed to by the engine global `symbol` (a pointer variable), or nil
int LuaEngineGlobal(lua_State* L)
{
    const char* symbol = lua.tolstring(L, 1, nullptr);
    const char* typeName = lua.tolstring(L, 2, nullptr);
    const std::uint32_t rva = symbol ? engineTypes.Symbol(symbol) : 0;
    const TypeDesc* type = typeName ? engineTypes.Get(typeName) : nullptr;
    if (!rva || !type)
        LuaError(L, "IEX_EngineGlobal: unknown symbol '%s' or type '%s'", symbol ? symbol : "?", typeName ? typeName : "?");
    PushObject(L, Read<std::uintptr_t>(EngineImageBase() + rva), type);
    return 1;
}

// IEX_IterateList(list, fn): walks an engine CPtrList from head to tail and calls fn(data) for each node;
// fn returning a truthy value stops the walk. `list` is a list field handle (typed: data is pushed as an
// object of the element type, an integer for id lists, or a raw address) or a CPtrList object (raw address).
int LuaIterateList(lua_State* L)
{
    const Box* box = CheckBox(L, 1);
    const TypeDesc* ptrList = engineTypes.Get("CPtrList");
    const TypeDesc* node = engineTypes.Get("CPtrList::CNode");
    std::uint32_t headOffset = 0, nextOffset = 0, dataOffset = 0;
    if (!ptrList || !node || !ptrList->Find("m_pNodeHead", headOffset) || !node->Find("pNext", nextOffset) ||
        !node->Find("data", dataOffset))
        LuaError(L, "IEX_IterateList: CPtrList layout missing from the engine description");

    const TypeDesc* elementType = nullptr;
    bool integers = false;
    if (box->kind) {
        if (box->kind->kind != Kind::List)
            LuaError(L, "IEX_IterateList: not a list");
        elementType = box->kind->type;
        integers = !elementType && box->kind->count == 1;
    } else {
        // A list class object (CGameEffectList...) knows its element type.
        for (const TypeDesc* t = box->type; t && !elementType; t = t->bases.empty() ? nullptr : t->bases[0].first)
            elementType = t->element;
    }
    const int fn = 2;
    for (std::uintptr_t n = Read<std::uintptr_t>(box->address + headOffset); n;
         n = Read<std::uintptr_t>(n + nextOffset)) {
        const auto data = Read<std::uintptr_t>(n + dataOffset);
        lua.pushvalue(L, fn);
        if (integers)
            lua.pushinteger(L, static_cast<std::int32_t>(data));
        else if (elementType)
            PushObject(L, data, elementType);
        else
            lua.pushinteger(L, static_cast<lua_Integer>(data));
        if (lua.pcallk(L, 1, 1, 0, 0, nullptr) != 0)
            lua.error(L);  // re-raise the listener's error with its original message
        const bool stop = lua.toboolean(L, -1) != 0;
        lua.settop(L, -2);
        if (stop)
            break;
    }
    return 0;
}

// IEX_Address(object) -> integer
int LuaAddress(lua_State* L)
{
    if (lua.type(L, 1) == LUA_TLIGHTUSERDATA) {  // a light userdata is its address
        lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<std::uintptr_t>(lua.touserdata(L, 1))));
        return 1;
    }
    lua.pushinteger(L, static_cast<lua_Integer>(ToObjectAddress(L, 1)));
    return 1;
}

// IEX_TypeName(object) -> string or nil
int LuaTypeName(lua_State* L)
{
    const Box* box = static_cast<const Box*>(lua.touserdata(L, 1));
    if (lua.type(L, 1) == LUA_TUSERDATA && box && box->type)
        lua.pushstring(L, box->type->name.c_str());
    else
        lua.pushnil(L);
    return 1;
}

} // namespace

void PushObject(lua_State* L, std::uintptr_t address, const TypeDesc* type)
{
    if (!address) {
        lua.pushnil(L);
        return;
    }
    PushBox(L, address, type, nullptr);
}

std::uintptr_t ToObjectAddress(lua_State* L, int index)
{
    // Only trust userdata that carries our metatable.
    const Box* box = TryBox(L, index);
    return box ? box->address : 0;
}

const TypeDesc* ToObjectType(lua_State* L, int index)
{
    const Box* box = TryBox(L, index);
    return box && !box->kind ? box->type : nullptr;
}

void OpenLuaObjects(lua_State* L)
{
    lua.L_newmetatable(L, kMeta);
    lua.pushcclosure(L, MetaIndex, 0);
    lua.setfield(L, -2, "__index");
    lua.pushcclosure(L, MetaNewIndex, 0);
    lua.setfield(L, -2, "__newindex");
    lua.pushcclosure(L, MetaEq, 0);
    lua.setfield(L, -2, "__eq");
    lua.pushcclosure(L, MetaToString, 0);
    lua.setfield(L, -2, "__tostring");
    lua.settop(L, -2);

    // One method table per engine class (kept if a mod already created it).
    engineTypes.ForEachType([L](const TypeDesc& type) {
        if (type.name.find(':') != std::string::npos)
            return;
        lua.getglobal(L, type.name.c_str());
        const bool exists = lua.type(L, -1) == LUA_TTABLE;
        lua.settop(L, -2);
        if (!exists) {
            lua.createtable(L, 0, 0);
            lua.setglobal(L, type.name.c_str());
        }
        // EEex exposes each class's byte size as Class.sizeof (mods step through arrays of records with it).
        if (type.size) {
            lua.getglobal(L, type.name.c_str());
            lua.pushinteger(L, static_cast<lua_Integer>(type.size));
            lua.setfield(L, -2, "sizeof");
            lua.settop(L, -2);
        }
    });

    lua.pushcclosure(L, LuaToObject, 0);
    lua.setglobal(L, "IEX_ToObject");
    lua.pushcclosure(L, LuaAddress, 0);
    lua.setglobal(L, "IEX_Address");
    lua.pushcclosure(L, LuaEngineGlobal, 0);
    lua.setglobal(L, "IEX_EngineGlobal");
    lua.pushcclosure(L, LuaIterateList, 0);
    lua.setglobal(L, "IEX_IterateList");
    lua.pushcclosure(L, LuaTypeName, 0);
    lua.setglobal(L, "IEX_TypeName");
}

} // namespace iex
