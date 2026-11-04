#include "log.h"

#include <cstdarg>
#include <cstdio>
#include <ctime>
#include <mutex>
#include <string>
#include <unordered_map>

namespace iex {

namespace {

std::FILE* g_file = nullptr;
std::mutex g_mutex;
std::size_t g_written = 0;
std::unordered_map<std::string, std::uint64_t> g_repeats;

// Messages can repeat every frame (a broken mod listener): IEX.log must never fill the disk.
constexpr std::size_t kMaxLogBytes = 64u * 1024 * 1024;

bool PowerOfTen(std::uint64_t n)
{
    while (n >= 10 && n % 10 == 0)
        n /= 10;
    return n == 1;
}

void WriteLine(const char* text)
{
    std::time_t now = std::time(nullptr);
    char stamp[32];
    std::strftime(stamp, sizeof(stamp), "%H:%M:%S", std::localtime(&now));
    const int n = std::fprintf(g_file, "[%s] %s\n", stamp, text);
    std::fflush(g_file);
    g_written += n > 0 ? static_cast<std::size_t>(n) : 0;
}

} // namespace

void LogOpen(const char* path)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_file) {
        // Keep the previous run's log (lost otherwise when the game is restarted after a crash).
        const std::string prev = std::string(path) + ".prev";
        std::remove(prev.c_str());
        std::rename(path, prev.c_str());
        g_file = std::fopen(path, "w");
    }
}

// Each distinct message is written the first time, then only at its 10th, 100th, 1000th... occurrence;
// past kMaxLogBytes the log stops (one final line says so).
void Log(const char* fmt, ...)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_file || g_written >= kMaxLogBytes)
        return;
    char text[2048];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(text, sizeof(text), fmt, args);
    va_end(args);

    const std::uint64_t count = ++g_repeats[text];
    if (count == 1) {
        WriteLine(text);
    } else if (PowerOfTen(count)) {
        const std::string repeated = std::string("(repeated ") + std::to_string(count) + " times) " + text;
        WriteLine(repeated.c_str());
    }
    if (g_written >= kMaxLogBytes)
        WriteLine("IEX.log reached its size limit (64 MB): logging stops here");
}

} // namespace iex
