#pragma once

// Loopback TCP primitives each platform layer implements (Winsock on Windows, BSD sockets on Linux). All calls
// are non-blocking; handles are opaque integers, -1 = none.
#include <cstddef>
#include <cstdint>

namespace iex::platform {

// Listens on 127.0.0.1:port only. Returns a listener handle or -1.
std::intptr_t NetListen(int port);
// Accepts one pending connection, or returns -1 when none is waiting.
std::intptr_t NetAccept(std::intptr_t listener);
// Reads what is available into buffer. Returns the byte count, 0 if nothing is waiting, -1 if the peer is gone.
int NetRecv(std::intptr_t socket, char* buffer, std::size_t size);
// Sends as much as the socket takes now. Returns the byte count, or -1 if the peer is gone.
int NetSend(std::intptr_t socket, const char* data, std::size_t size);
void NetClose(std::intptr_t socket);

} // namespace iex::platform
