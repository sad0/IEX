// Loopback TCP for the IEX network bridge (BSD sockets).
#include "platform_net.h"

#include <cerrno>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

namespace iex::platform {

namespace {

void NonBlocking(int s)
{
    fcntl(s, F_SETFL, fcntl(s, F_GETFL, 0) | O_NONBLOCK);
}

} // namespace

std::intptr_t NetListen(int port)
{
    const int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0)
        return -1;
    int on = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(static_cast<uint16_t>(port));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0 || listen(s, 1) != 0) {
        close(s);
        return -1;
    }
    NonBlocking(s);
    return s;
}

std::intptr_t NetAccept(std::intptr_t listener)
{
    const int c = accept(static_cast<int>(listener), nullptr, nullptr);
    if (c < 0)
        return -1;
    NonBlocking(c);
    int on = 1;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
    return c;
}

int NetRecv(std::intptr_t socket, char* buffer, std::size_t size)
{
    const ssize_t n = recv(static_cast<int>(socket), buffer, size, 0);
    if (n > 0)
        return static_cast<int>(n);
    if (n == 0)
        return -1;
    return (errno == EAGAIN || errno == EWOULDBLOCK) ? 0 : -1;
}

int NetSend(std::intptr_t socket, const char* data, std::size_t size)
{
    const ssize_t n = send(static_cast<int>(socket), data, size, MSG_NOSIGNAL);
    if (n >= 0)
        return static_cast<int>(n);
    return (errno == EAGAIN || errno == EWOULDBLOCK) ? 0 : -1;
}

void NetClose(std::intptr_t socket)
{
    if (socket != -1)
        close(static_cast<int>(socket));
}

} // namespace iex::platform
