#pragma once

// Engine events forwarded to Lua: the C++ hooks call these, which call IEX_Dispatch(event, ...) in Lua.
#include <cstdint>

struct lua_State;

namespace iex {

struct TypeDesc;

// Sets the engine Lua state used for dispatch (once the IEX Lua files are loaded).
void SetEventLuaState(lua_State* L);

// Dispatches an event without arguments. Returns true if a listener consumed it.
bool DispatchEvent(const char* event);
// Dispatches an event with one engine object argument (nil if address is 0).
bool DispatchObjectEvent(const char* event, std::uintptr_t address, const TypeDesc* type);
// Dispatches an event with two engine object arguments (each nil if its address is 0).
bool DispatchObjectsEvent(const char* event, std::uintptr_t a, const TypeDesc* typeA, std::uintptr_t b,
                          const TypeDesc* typeB);
// Dispatches an event with one integer argument.
bool DispatchIntegerEvent(const char* event, std::int64_t value);

// Calls the Lua global EEex_Key_Hook_AfterEventsPoll(event) with a read-only view of an SDL2 event
// ({type, key.repeat, key.keysym.sym/scancode, button.button, wheel.x/y}). Returns true if it asks to drop the event.
bool DispatchSdlEvent(const std::uint8_t* sdlEvent);

} // namespace iex
