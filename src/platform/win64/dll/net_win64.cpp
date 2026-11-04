// Loopback TCP for the IEX network bridge (Winsock).
#include "platform_net.h"

#include <winsock2.h>
#include <ws2tcpip.h>

namespace iex::platform {

namespace {

bool Startup()
{
    static const bool ok = [] {
        WSADATA data;
        return WSAStartup(MAKEWORD(2, 2), &data) == 0;
    }();
    return ok;
}

void NonBlocking(SOCKET s)
{
    u_long on = 1;
    ioctlsocket(s, FIONBIO, &on);
}

} // namespace

std::intptr_t NetListen(int port)
{
    if (!Startup())
        return -1;
    const SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET)
        return -1;
    BOOL exclusive = TRUE;
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(static_cast<u_short>(port));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0 || listen(s, 1) != 0) {
        closesocket(s);
        return -1;
    }
    NonBlocking(s);
    return static_cast<std::intptr_t>(s);
}

std::intptr_t NetAccept(std::intptr_t listener)
{
    const SOCKET c = accept(static_cast<SOCKET>(listener), nullptr, nullptr);
    if (c == INVALID_SOCKET)
        return -1;
    NonBlocking(c);
    BOOL noDelay = TRUE;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&noDelay), sizeof(noDelay));
    return static_cast<std::intptr_t>(c);
}

int NetRecv(std::intptr_t socket, char* buffer, std::size_t size)
{
    const int n = recv(static_cast<SOCKET>(socket), buffer, static_cast<int>(size), 0);
    if (n > 0)
        return n;
    if (n == 0)
        return -1;  // orderly shutdown
    return WSAGetLastError() == WSAEWOULDBLOCK ? 0 : -1;
}

int NetSend(std::intptr_t socket, const char* data, std::size_t size)
{
    const int n = send(static_cast<SOCKET>(socket), data, static_cast<int>(size), 0);
    if (n >= 0)
        return n;
    return WSAGetLastError() == WSAEWOULDBLOCK ? 0 : -1;
}

void NetClose(std::intptr_t socket)
{
    if (socket != -1)
        closesocket(static_cast<SOCKET>(socket));
}

} // namespace iex::platform
