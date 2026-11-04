#include "callsite_hook.h"

#include "log.h"
#include "platform_memory.h"

#include <cstring>

namespace iex {

bool HookCallSite(std::uintptr_t site, std::uintptr_t expectedTarget, const void* replacement)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    if (code[0] != 0xE8 || site + 5 + rel != expectedTarget) {
        Log("Call site 0x%llx does not call 0x%llx, hook skipped", static_cast<unsigned long long>(site),
            static_cast<unsigned long long>(expectedTarget));
        return false;
    }

    // Thunk near the image: jmp qword ptr [rip+0] ; <absolute address of replacement>
    auto* thunk = static_cast<std::uint8_t*>(platform::AllocExecNear(site, 14));
    if (!thunk)
        return false;
    const std::uint8_t jmpAbs[6] = {0xFF, 0x25, 0, 0, 0, 0};
    std::memcpy(thunk, jmpAbs, sizeof(jmpAbs));
    const auto target = reinterpret_cast<std::uint64_t>(replacement);
    std::memcpy(thunk + 6, &target, 8);

    const std::int64_t newRel = reinterpret_cast<std::int64_t>(thunk) - static_cast<std::int64_t>(site + 5);
    if (newRel < INT32_MIN || newRel > INT32_MAX)
        return false;
    const auto rel32 = static_cast<std::int32_t>(newRel);
    return platform::PatchCode(reinterpret_cast<void*>(site + 1), &rel32, 4);
}

namespace {

// Thunk near `site`: jmp qword ptr [rip+0] ; <absolute address of replacement>
std::uint8_t* MakeThunk(std::uintptr_t site, const void* replacement)
{
    auto* thunk = static_cast<std::uint8_t*>(platform::AllocExecNear(site, 14));
    if (!thunk)
        return nullptr;
    const std::uint8_t jmpAbs[6] = {0xFF, 0x25, 0, 0, 0, 0};
    std::memcpy(thunk, jmpAbs, sizeof(jmpAbs));
    const auto target = reinterpret_cast<std::uint64_t>(replacement);
    std::memcpy(thunk + 6, &target, 8);
    return thunk;
}

} // namespace

bool HookJumpSite(std::uintptr_t site, std::uintptr_t expectedTarget, const void* replacement)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    if (code[0] != 0xE9 || site + 5 + rel != expectedTarget) {
        Log("Jump site 0x%llx does not jump to 0x%llx, hook skipped", static_cast<unsigned long long>(site),
            static_cast<unsigned long long>(expectedTarget));
        return false;
    }
    std::uint8_t* thunk = MakeThunk(site, replacement);
    if (!thunk)
        return false;
    const std::int64_t newRel = reinterpret_cast<std::int64_t>(thunk) - static_cast<std::int64_t>(site + 5);
    if (newRel < INT32_MIN || newRel > INT32_MAX)
        return false;
    const auto rel32 = static_cast<std::int32_t>(newRel);
    return platform::PatchCode(reinterpret_cast<void*>(site + 1), &rel32, 4);
}

bool FunctionEntryIntact(std::uintptr_t fn, std::uint64_t expectedPrologue)
{
    std::uint64_t bytes;
    std::memcpy(&bytes, reinterpret_cast<const void*>(fn), 8);
    if (bytes == expectedPrologue)
        return true;
    Log("Function 0x%llx starts with %016llx, expected %016llx (patched by something else?)",
        static_cast<unsigned long long>(fn), static_cast<unsigned long long>(bytes),
        static_cast<unsigned long long>(expectedPrologue));
    return false;
}

bool HookFunctionEntry(std::uintptr_t fn, std::uint64_t expectedPrologue, const void* replacement)
{
    if (!FunctionEntryIntact(fn, expectedPrologue))
        return false;
    std::uint8_t* thunk = MakeThunk(fn, replacement);
    if (!thunk)
        return false;
    const std::int64_t rel = reinterpret_cast<std::int64_t>(thunk) - static_cast<std::int64_t>(fn + 5);
    if (rel < INT32_MIN || rel > INT32_MAX)
        return false;
    std::uint8_t jmp[5] = {0xE9, 0, 0, 0, 0};
    const auto rel32 = static_cast<std::int32_t>(rel);
    std::memcpy(jmp + 1, &rel32, 4);
    return platform::PatchCode(reinterpret_cast<void*>(fn), jmp, sizeof(jmp));
}

} // namespace iex
