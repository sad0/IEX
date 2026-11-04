#pragma once

// Engine member functions as Lua methods of the engine class tables (CInfGame, CGameArea, CGameObject...), from
// the `method` records of the engine description: `object:Name(...)` calls the engine function with the object
// as `this`. Methods the engine itself binds through tolua (worldScreen:StepDialog()...) are reached from IEX
// objects by the tolua bridge of lua_objects.cpp.
struct lua_State;

namespace iex {

// Registers one C closure per `method` record in its class table. Call after OpenLuaObjects.
void OpenLuaMethods(lua_State* L);

// The C function behind every native method closure (lua_objects.cpp tells them from tolua functions).
int CallNativeMethod(lua_State* L);

// Pushes the native method `key` of class `className` and returns true, or pushes nothing and returns false.
// The closures are kept in registry["IEX.Methods"][className] as well as in the class tables: the engine's tolua
// registration (CLUAConsole::LuaInit, after IEX starts) replaces the global tables of its own classes (CInfGame).
bool PushNativeMethod(lua_State* L, const char* className, const char* key);

} // namespace iex
