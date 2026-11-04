#pragma once

// Engine objects exposed to Lua as userdata, driven by the engine type registry:
//   sprite.m_id                       -> number
//   sprite.m_baseStats.m_level1       -> nested object, then number
//   sprite.m_scriptName:get()         -> string handle (resref / CString / char[N])
//   sprite.m_equipment.m_items:get(i) -> array handle, element i (0-based)
//   obj1 == obj2                      -> same address
#include <cstdint>

struct lua_State;

namespace iex {

struct TypeDesc;
struct FieldKind;

// Registers the metatable and the IEX_* object functions. Call once on the engine Lua state.
void OpenLuaObjects(lua_State* L);

// Pushes an object of `type` at `address` (nil if address is 0).
void PushObject(lua_State* L, std::uintptr_t address, const TypeDesc* type);

// Returns the address of the object/handle at `index`, or 0 if it isn't one.
std::uintptr_t ToObjectAddress(lua_State* L, int index);

// Returns the engine type of the object at `index` (nullptr for handles and non-objects).
const TypeDesc* ToObjectType(lua_State* L, int index);

} // namespace iex
