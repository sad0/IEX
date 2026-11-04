#pragma once

#include <cstdint>
#include <string>

struct lua_State;

namespace iex {

constexpr const char* kVersion = "0.4.0";

// Platform layer description of the running game image.
struct HostInfo {
    const char* platform;   // "win64" or "linux64"
    std::uintptr_t imageBase;
    const char* gameDir;    // directory of the game executable, no trailing separator
    // Build identity, compared with the `build` record of each engine description.
    std::uint32_t timestamp = 0;  // win64: PE TimeDateStamp
    std::uint32_t imageSize = 0;  // win64: PE SizeOfImage
    const char* buildId = "";     // linux64: GNU build-id (hex)
};

// Called once by the platform layer as early as possible in the game process, before the engine runs:
// opens IEX.log, loads the engine description matching this build, resolves the Lua API and installs the hooks.
void Startup(const HostInfo& host);

// Load address of the game executable.
std::uintptr_t EngineImageBase();

// Directory of the game executable (no trailing separator).
const std::string& GameDir();

} // namespace iex
