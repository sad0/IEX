// IEX.dll entry: loaded into the game process by IEXLauncher before the game's entry point runs.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "iex_core.h"
#include "log.h"

#include <cstdint>
#include <cstdio>
#include <string>

namespace {

std::string Utf8(const std::wstring& w)
{
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n - 1 : 0, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, s.data(), n, nullptr, nullptr);
    return s;
}

// Access violations are logged (game / IEX.dll offsets of the faulting instruction and of the return addresses
// found on the stack) before the engine's own handler shows its error box: a crash leaves a trace in IEX.log.
std::uintptr_t g_gameBase = 0, g_gameEnd = 0, g_dllBase = 0, g_dllEnd = 0;

void Describe(char* out, std::size_t size, std::uintptr_t a)
{
    if (a >= g_gameBase && a < g_gameEnd)
        snprintf(out, size, "game+0x%llx", static_cast<unsigned long long>(a - g_gameBase));
    else if (a >= g_dllBase && a < g_dllEnd)
        snprintf(out, size, "IEX+0x%llx", static_cast<unsigned long long>(a - g_dllBase));
    else
        snprintf(out, size, "0x%llx", static_cast<unsigned long long>(a));
}

LONG CALLBACK CrashLogger(EXCEPTION_POINTERS* info)
{
    static volatile LONG logged = 0;
    if (info->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || InterlockedIncrement(&logged) > 3)
        return EXCEPTION_CONTINUE_SEARCH;
    char where[64];
    Describe(where, sizeof(where), static_cast<std::uintptr_t>(info->ContextRecord->Rip));
    iex::Log("Access violation at %s (%s 0x%llx)", where,
             info->ExceptionRecord->ExceptionInformation[0] ? "writing" : "reading",
             static_cast<unsigned long long>(info->ExceptionRecord->ExceptionInformation[1]));
    const auto* stack = reinterpret_cast<const std::uintptr_t*>(info->ContextRecord->Rsp);
    std::string trace;
    for (int i = 0, found = 0; i < 512 && found < 16; ++i) {
        const std::uintptr_t v = stack[i];
        if ((v >= g_gameBase && v < g_gameEnd) || (v >= g_dllBase && v < g_dllEnd)) {
            Describe(where, sizeof(where), v);
            trace += ' ';
            trace += where;
            ++found;
        }
    }
    iex::Log("  stack code addresses:%s", trace.c_str());
    return EXCEPTION_CONTINUE_SEARCH;
}

} // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID)
{
    if (reason != DLL_PROCESS_ATTACH)
        return TRUE;
    DisableThreadLibraryCalls(instance);

    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe);
    dir.resize(dir.find_last_of(L"\\/"));
    static std::string gameDir = Utf8(dir);

    const auto base = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);

    iex::HostInfo host;
    host.platform = "win64";
    host.imageBase = base;
    host.gameDir = gameDir.c_str();
    host.timestamp = nt->FileHeader.TimeDateStamp;
    host.imageSize = nt->OptionalHeader.SizeOfImage;
    g_gameBase = base;
    g_gameEnd = base + nt->OptionalHeader.SizeOfImage;
    g_dllBase = reinterpret_cast<std::uintptr_t>(instance);
    const auto* dllNt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(
        g_dllBase + reinterpret_cast<const IMAGE_DOS_HEADER*>(g_dllBase)->e_lfanew);
    g_dllEnd = g_dllBase + dllNt->OptionalHeader.SizeOfImage;
    iex::Startup(host);
    AddVectoredExceptionHandler(0, CrashLogger);
    return TRUE;
}
