#pragma once

namespace iex {

// Opens IEX.log next to the game executable (path given by the platform layer).
void LogOpen(const char* path);
void Log(const char* fmt, ...);

} // namespace iex
