// IEXLauncher: starts the game suspended, queues a LoadLibraryW(IEX.dll) APC on its main thread, resumes it.
// The thread runs queued APCs at the end of process initialization (after the static imports are loaded and
// before the game's entry point), so IEX is in place before any game code runs.
//
// Usage: IEXLauncher.exe [game exe name]   (default: the first of Baldur.exe / BaldurII.exe / SiegeOfDragonspear.exe found
//                                            next to the launcher)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <string>

namespace {

std::wstring DirOf(const std::wstring& path)
{
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

bool FileExists(const std::wstring& path)
{
    DWORD attr = GetFileAttributesW(path.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
}

int Fail(const wchar_t* what)
{
    wchar_t msg[512];
    swprintf_s(msg, L"%s (error %lu)", what, GetLastError());
    MessageBoxW(nullptr, msg, L"IEX Launcher", MB_ICONERROR);
    return 1;
}

} // namespace

int wmain(int argc, wchar_t** argv)
{
    wchar_t self[MAX_PATH];
    GetModuleFileNameW(nullptr, self, MAX_PATH);
    const std::wstring dir = DirOf(self);

    std::wstring exe;
    if (argc > 1) {
        exe = dir + L"\\" + argv[1];
    } else {
        for (const wchar_t* name : {L"Baldur.exe", L"BaldurII.exe", L"SiegeOfDragonspear.exe"}) {
            if (FileExists(dir + L"\\" + name)) {
                exe = dir + L"\\" + name;
                break;
            }
        }
    }
    if (exe.empty() || !FileExists(exe))
        return Fail(L"Game executable not found next to IEXLauncher.exe");

    const std::wstring dll = dir + L"\\IEX.dll";
    if (!FileExists(dll))
        return Fail(L"IEX.dll not found next to IEXLauncher.exe");

    STARTUPINFOW si = {sizeof(si)};
    PROCESS_INFORMATION pi = {};
    std::wstring cmd = L"\"" + exe + L"\"";
    if (!CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE, CREATE_SUSPENDED, nullptr, dir.c_str(), &si, &pi))
        return Fail(L"CreateProcess failed");

    // The DLL path must live in the game process for LoadLibraryW to read it.
    const SIZE_T pathBytes = (dll.size() + 1) * sizeof(wchar_t);
    void* remotePath = VirtualAllocEx(pi.hProcess, nullptr, pathBytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remotePath || !WriteProcessMemory(pi.hProcess, remotePath, dll.c_str(), pathBytes, nullptr)) {
        TerminateProcess(pi.hProcess, 1);
        return Fail(L"Writing the DLL path into the game failed");
    }

    // kernel32 is mapped at the same address in every process of a boot session.
    const auto loadLibraryW =
        reinterpret_cast<PAPCFUNC>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW"));
    if (!QueueUserAPC(loadLibraryW, pi.hThread, reinterpret_cast<ULONG_PTR>(remotePath))) {
        TerminateProcess(pi.hProcess, 1);
        return Fail(L"Queueing the IEX load failed");
    }

    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
