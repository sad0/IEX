// Network bridge for external clients (e.g. a 3D renderer): one loopback TCP listener, one client at a time,
// newline-delimited text messages. Everything is non-blocking and driven from Lua (call IEX_NetPoll each frame).
#include "lua_net.h"

#include "log.h"
#include "lua_api.h"
#include "platform_net.h"

#include <string>

namespace iex {

namespace {

constexpr std::size_t kMaxOutgoing = 8 * 1024 * 1024;  // drop the client rather than grow without bound
constexpr std::size_t kMaxLine = 1024 * 1024;

std::intptr_t g_listener = -1;
std::intptr_t g_client = -1;
std::string g_in, g_out;

void Drop(const char* why)
{
    if (g_client != -1)
        Log("Net: client disconnected (%s)", why);
    platform::NetClose(g_client);
    g_client = -1;
    g_in.clear();
    g_out.clear();
}

void Flush()
{
    while (g_client != -1 && !g_out.empty()) {
        const int n = platform::NetSend(g_client, g_out.data(), g_out.size());
        if (n < 0)
            return Drop("send failed");
        if (n == 0)
            return;
        g_out.erase(0, static_cast<std::size_t>(n));
    }
}

// IEX_NetListen(port) -> bool: starts listening on 127.0.0.1:port (once; later calls return the first result).
int LuaNetListen(lua_State* L)
{
    if (g_listener == -1) {
        const int port = static_cast<int>(lua.tointegerx(L, 1, nullptr));
        g_listener = platform::NetListen(port);
        Log(g_listener != -1 ? "Net: listening on 127.0.0.1:%d" : "Net: cannot listen on 127.0.0.1:%d", port);
    }
    lua.pushboolean(L, g_listener != -1);
    return 1;
}

// IEX_NetPoll() -> connected, {lines}: accepts a waiting client, sends queued data, returns the complete
// lines received since the last call (without their newline).
int LuaNetPoll(lua_State* L)
{
    if (g_listener != -1 && g_client == -1) {
        g_client = platform::NetAccept(g_listener);
        if (g_client != -1)
            Log("Net: client connected");
    }
    Flush();
    char buffer[16384];
    while (g_client != -1) {
        const int n = platform::NetRecv(g_client, buffer, sizeof(buffer));
        if (n < 0) {
            Drop("closed");
            break;
        }
        if (n == 0)
            break;
        g_in.append(buffer, static_cast<std::size_t>(n));
        if (g_in.size() > kMaxLine && g_in.find('\n') == std::string::npos) {
            Drop("line too long");
            break;
        }
    }
    lua.pushboolean(L, g_client != -1);
    lua.createtable(L, 0, 0);
    int count = 0;
    std::size_t start = 0, end;
    while ((end = g_in.find('\n', start)) != std::string::npos) {
        std::size_t len = end - start;
        if (len && g_in[start + len - 1] == '\r')
            --len;
        lua.pushlstring(L, g_in.data() + start, len);
        lua.rawseti(L, -2, ++count);
        start = end + 1;
    }
    g_in.erase(0, start);
    return 2;
}

// IEX_NetSend(text) -> bool: queues text for the client (add the newline yourself). False when no client.
int LuaNetSend(lua_State* L)
{
    std::size_t len = 0;
    const char* text = lua.tolstring(L, 1, &len);
    if (g_client == -1 || !text) {
        lua.pushboolean(L, 0);
        return 1;
    }
    if (g_out.size() + len > kMaxOutgoing) {
        Drop("client too slow");
        lua.pushboolean(L, 0);
        return 1;
    }
    g_out.append(text, len);
    Flush();
    lua.pushboolean(L, g_client != -1);
    return 1;
}

} // namespace

void OpenLuaNet(lua_State* L)
{
    lua.pushcclosure(L, LuaNetListen, 0);
    lua.setglobal(L, "IEX_NetListen");
    lua.pushcclosure(L, LuaNetPoll, 0);
    lua.setglobal(L, "IEX_NetPoll");
    lua.pushcclosure(L, LuaNetSend, 0);
    lua.setglobal(L, "IEX_NetSend");
}

} // namespace iex
