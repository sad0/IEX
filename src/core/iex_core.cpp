#include "iex_core.h"
#include "actionbar.h"
#include "lua_ini.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "effects.h"
#include "event_hooks.h"
#include "framerate.h"
#include "hd_tiles.h"
#include "events.h"
#include "log.h"
#include "lua_api.h"
#include "lua_engine.h"
#include "lua_memory.h"
#include "lua_net.h"
#include "lua_objects.h"
#include "lua_methods.h"
#include "lua_resources.h"
#include "opcodes.h"
#include "settings.h"
#include "spell_lists.h"
#include "spell_slots.h"
#include "engine_fixes.h"
#include "startup_movies.h"
#include "lua_ui.h"
#include "lua_scripting.h"
#include "lua_sprite_hooks.h"
#include "modules.h"
#include "native_hooks.h"
#include "marshal.h"
#include "native_stick.h"
#include "object_ids.h"
#include "vision.h"
#include "pathfinding.h"

#include <cstdarg>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace iex {

LuaApi lua;

void LuaError(lua_State* L, const char* fmt, ...)
{
    char message[512];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(message, sizeof(message), fmt, args);
    va_end(args);
    lua.pushstring(L, message);
    lua.error(L);
    for (;;) {
    }  // lua_error does not return
}

namespace {

std::string g_gameDir;
std::uintptr_t g_base = 0;
lua_State* g_engineLua = nullptr;

constexpr const char* kNewState = "luaL_newstate";
constexpr const char* kLuaInit = "_ZN11CLUAConsole7LuaInitEv";  // CLUAConsole::LuaInit()
constexpr const char* kUiLoadFunctions = "_Z15uiLoadFunctionsv";  // uiLoadFunctions(): runs the UI Lua files

template <typename T>
T EngineFunction(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(g_base + rva) : nullptr;
}

// IEX_Log(message): writes a line to IEX.log.
int LuaLog(lua_State* L)
{
    const char* msg = lua.tolstring(L, 1, nullptr);
    Log("[Lua] %s", msg ? msg : "(nil)");
    return 0;
}

bool RunFile(lua_State* L, const std::string& path, const char* chunkName)
{
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        Log("Script not found: %s", path.c_str());
        return false;
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    const std::string code = buffer.str();

    const int top = lua.gettop(L);
    if (lua.L_loadbufferx(L, code.data(), code.size(), chunkName, "t") != 0 || lua.pcallk(L, 0, 0, 0, 0, nullptr) != 0) {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("Lua error in %s: %s", chunkName, err ? err : "(unknown)");
        lua.settop(L, top);
        return false;
    }
    lua.settop(L, top);
    return true;
}

// IEX_RunFile(name): runs IEX/<name> (a file shipped with IEX). Returns true on success; errors are logged.
int LuaRunFile(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    if (!name)
        LuaError(L, "IEX_RunFile: file name expected");
    const std::string chunk = std::string("@") + name;
    lua.pushboolean(L, RunFile(L, g_gameDir + "/IEX/" + name, chunk.c_str()));
    return 1;
}

// IEX_WriteFile(name, text): writes IEX/<name> (reports such as missing_api.txt). Names with path separators
// or ".." are refused.
int LuaWriteFile(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    std::size_t len = 0;
    const char* text = lua.tolstring(L, 2, &len);
    const std::string n = name ? name : "";
    if (n.empty() || n.find_first_of("/\\") != std::string::npos || n.find("..") != std::string::npos || !text)
        LuaError(L, "IEX_WriteFile: plain file name and text expected");
    std::ofstream out(g_gameDir + "/IEX/" + n, std::ios::binary | std::ios::trunc);
    out.write(text, static_cast<std::streamsize>(len));
    lua.pushboolean(L, out.good());
    return 1;
}

void OnEngineLuaReady(lua_State* L)
{
    Log("Engine Lua state ready (%p)", static_cast<void*>(L));
    lua.pushcclosure(L, LuaLog, 0);
    lua.setglobal(L, "IEX_Log");
    lua.pushcclosure(L, LuaRunFile, 0);
    lua.setglobal(L, "IEX_RunFile");
    lua.pushcclosure(L, LuaWriteFile, 0);
    lua.setglobal(L, "IEX_WriteFile");
    OpenLuaObjects(L);
    OpenLuaMethods(L);
    OpenLuaEngine(L);
    OpenLuaResources(L);
    OpenLuaNet(L);
    OpenLuaMemory(L);
    OpenLuaFrameRate(L);
    OpenLuaActionbar(L);
    OpenLuaOpcodes(L);
    OpenLuaUi(L);
    OpenLuaScripting(L);
    OpenLuaSpriteHooks(L);
    OpenLuaModules(L);
    OpenLuaStickHooks(L);
    OpenLuaVision(L);
    OpenLuaObjectIds(L);
    OpenLuaNativeHooks(L);
    OpenLuaPathfinding(L);
    OpenLuaEngineFixes(L);
    OpenLuaSettings(L);
    OpenLuaIni(L);
    OpenLuaMarshal(L);
    OpenLuaSpellLists(L);
    OpenLuaHdTiles(L);
    if (RunFile(L, g_gameDir + "/IEX/IEX_Main.lua", "@IEX_Main.lua"))
        Log("IEX_Main.lua done");
    SetEventLuaState(L);
}

// --- Engine hooks (portable: the first integer argument is `this` on both ABIs) ---

lua_State* HookNewState()
{
    lua_State* L = EngineFunction<lua_State* (*)()>(kNewState)();
    if (!g_engineLua)
        g_engineLua = L;
    return L;
}

// IEX starts right before the engine runs the UI Lua files (uiLoadFunctions loads the M_*.lua files of mods,
// which register their EEex listeners), and at the latest after CLUAConsole::LuaInit.
bool g_iexLuaStarted = false;

void StartIexLua(const char* when)
{
    if (g_iexLuaStarted)
        return;
    if (!g_engineLua) {
        Log("%s: no engine Lua state captured yet", when);
        return;
    }
    g_iexLuaStarted = true;
    OnEngineLuaReady(g_engineLua);
}

void HookUiLoadFunctions()
{
    StartIexLua("uiLoadFunctions");
    EngineFunction<void (*)()>(kUiLoadFunctions)();
}

void HookLuaInit(void* self)
{
    EngineFunction<void (*)(void*)>(kLuaInit)(self);
    StartIexLua("CLUAConsole::LuaInit");
}

bool HookAllCallsOf(const char* target, const void* replacement)
{
    const std::uint32_t targetRva = engineTypes.Symbol(target);
    const auto sites = engineTypes.CallSitesOf(target);
    if (!targetRva || sites.empty()) {
        Log("No call site known for %s", target);
        return false;
    }
    bool ok = true;
    for (std::uint32_t site : sites)
        ok = HookCallSite(g_base + site, g_base + targetRva, replacement) && ok;
    return ok;
}

// --- Startup ---

std::uint32_t Hex(const std::string& text)
{
    return text.empty() ? 0 : static_cast<std::uint32_t>(std::stoul(text, nullptr, 16));
}

bool MatchesHost(const std::unordered_map<std::string, std::string>& build, const HostInfo& host)
{
    const auto get = [&](const char* key) {
        auto it = build.find(key);
        return it == build.end() ? std::string() : it->second;
    };
    if (get("platform") != host.platform)
        return false;
    if (std::string(host.platform) == "win64")
        return Hex(get("timestamp")) == host.timestamp && Hex(get("imagesize")) == host.imageSize;
    return get("buildid") == host.buildId;
}

std::string FindDescription(const HostInfo& host)
{
    namespace fs = std::filesystem;
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(fs::u8path(g_gameDir + "/IEX/engine"), ec)) {
        if (entry.path().extension() != ".iexd")
            continue;
        const std::string path = entry.path().u8string();
        if (MatchesHost(ReadBuildRecord(path), host))
            return path;
    }
    return {};
}

// Resolves every IEX_LUA_API entry: `name` -> lua_name, `L_name` -> luaL_name.
bool ResolveLuaApi()
{
    bool ok = true;
    const auto resolve = [&ok](const char* shortName, auto& slot) {
        const std::string s = shortName;
        const std::string full = s.rfind("L_", 0) == 0 ? "luaL_" + s.substr(2) : "lua_" + s;
        slot = EngineFunction<std::remove_reference_t<decltype(slot)>>(full.c_str());
        if (!slot) {
            Log("Lua API function missing from the engine description: %s", full.c_str());
            ok = false;
        }
    };
#define IEX_LUA_RESOLVE(name, ret, params) resolve(#name, lua.name);
    IEX_LUA_API(IEX_LUA_RESOLVE)
#undef IEX_LUA_RESOLVE
    return ok;
}

} // namespace

std::uintptr_t EngineImageBase()
{
    return g_base;
}

const std::string& GameDir()
{
    return g_gameDir;
}

void Startup(const HostInfo& host)
{
    g_gameDir = host.gameDir;
    g_base = host.imageBase;
    LogOpen((g_gameDir + "/IEX.log").c_str());
    Log("IEX %s starting (%s), image base 0x%llx", kVersion, host.platform,
        static_cast<unsigned long long>(host.imageBase));

    LoadSettings(g_gameDir);
    const std::string description = FindDescription(host);
    if (description.empty()) {
        Log("No engine description for this game build in IEX/engine, IEX stays inactive");
        return;
    }
    Log("Engine description: %s", description.c_str());
    if (!engineTypes.Load(description) || !ResolveLuaApi()) {
        Log("Engine description unusable, IEX stays inactive");
        return;
    }
    if (!HookAllCallsOf(kNewState, reinterpret_cast<const void*>(&HookNewState)) ||
        !HookAllCallsOf(kLuaInit, reinterpret_cast<const void*>(&HookLuaInit)) ||
        !HookAllCallsOf(kUiLoadFunctions, reinterpret_cast<const void*>(&HookUiLoadFunctions)))
        Log("Installing engine hooks failed, IEX may not start");
    InstallEventHooks();
    InstallObjectIds();  // after InstallEventHooks: drives its CGameObjectArray::Add hook
    InstallEffectHooks();
    InstallFrameRateHooks();
    InstallActionbarHooks();
    InstallOpcodeHooks();
    InstallUiHooks();
    InstallSpriteHooks();
    InstallModuleHooks();
    InstallStickHooks();  // after InstallSpriteHooks: chains its Damage / attack roll hooks
    InstallScriptingHooks();
    InstallVisionHooks();
    InstallPathfindingHooks();
    InstallStartupMovieHooks();
    InstallSpellSlotHooks();
    InstallSpellListHooks();
    InstallHdTileHooks();
    InstallEngineFixes();
    InstallMarshalHooks();
}

} // namespace iex
