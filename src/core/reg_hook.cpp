#include "reg_hook.h"

#include "log.h"
#include "platform_memory.h"

#include <cstring>

// Common thunk, one per platform (src/platform/win64/dll/reg_thunk_win64.asm, src/platform/linux64/reg_thunk_linux64.S).
extern "C" void iex_reg_thunk();

extern "C" void iex_reg_dispatch(iex::RegContext* ctx, const iex::RegHookSite* site)
{
    site->handler(*ctx, *site);
}

namespace iex {

std::uintptr_t CallTarget(std::uintptr_t site)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    if (code[0] != 0xE8)
        return 0;
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    return site + 5 + rel;
}

const RegHookSite* HookCallSiteRegs(std::uintptr_t site, RegHandler handler, void* user)
{
    const std::uintptr_t target = CallTarget(site);
    if (!target) {
        Log("Register hook: 0x%llx is not a call, skipped", static_cast<unsigned long long>(site));
        return nullptr;
    }
    // Stub near the image: the site record (never freed), then
    //   49 BB <imm64>       mov r11, record
    //   FF 25 00 00 00 00   jmp qword ptr [rip+0]
    //   <imm64>             iex_reg_thunk
    auto* record = new RegHookSite{target, handler, site, user};
    auto* stub = static_cast<std::uint8_t*>(platform::AllocExecNear(site, 24));
    if (!stub)
        return nullptr;
    const auto rec = reinterpret_cast<std::uint64_t>(record);
    const auto thunk = reinterpret_cast<std::uint64_t>(&iex_reg_thunk);
    std::uint8_t code[24] = {0x49, 0xBB};
    std::memcpy(code + 2, &rec, 8);
    code[10] = 0xFF;
    code[11] = 0x25;
    std::memcpy(code + 16, &thunk, 8);
    std::memcpy(stub, code, sizeof(code));
    const std::int64_t rel = reinterpret_cast<std::int64_t>(stub) - static_cast<std::int64_t>(site + 5);
    if (rel < INT32_MIN || rel > INT32_MAX)
        return nullptr;
    const auto rel32 = static_cast<std::int32_t>(rel);
    if (!platform::PatchCode(reinterpret_cast<void*>(site + 1), &rel32, 4))
        return nullptr;
    return record;
}

std::uint64_t CallOriginal(RegContext& ctx, const RegHookSite& site)
{
    using U = std::uint64_t;
    using Fn = U (*)(U, U, U, U, U, U, U, U, U, U, U, U);
    const auto fn = reinterpret_cast<Fn>(site.original);
    const U* s = ctx.callerStack;
#if defined(_WIN32)
    // rcx, rdx, r8, r9; stack arguments follow the 32-byte home area.
    return fn(ctx.rcx, ctx.rdx, ctx.r8, ctx.r9, s[4], s[5], s[6], s[7], s[8], s[9], 0, 0);
#else
    return fn(ctx.rdi, ctx.rsi, ctx.rdx, ctx.rcx, ctx.r8, ctx.r9, s[0], s[1], s[2], s[3], s[4], s[5]);
#endif
}

std::uint64_t* LocatePointer(RegContext& ctx, std::uint32_t location)
{
    const std::uint32_t kind = location >> 16;
    const std::uint16_t offset = static_cast<std::uint16_t>(location & 0xFFFF);
    switch (kind) {
    case 1:
        return offset < 15 ? &ctx.Reg(offset) : nullptr;
    case 2:
        return reinterpret_cast<std::uint64_t*>(ctx.rbp + static_cast<std::int16_t>(offset));
    case 3:
        return reinterpret_cast<std::uint64_t*>(ctx.CallerRsp() + offset);
    default:
        return nullptr;
    }
}

} // namespace iex
