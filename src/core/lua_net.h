#pragma once

struct lua_State;

namespace iex {

// Registers IEX_NetListen / IEX_NetPoll / IEX_NetSend: one loopback TCP bridge for an external client.
void OpenLuaNet(lua_State* L);

} // namespace iex
