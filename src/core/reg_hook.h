#pragma once

// Register-context call-site hooks: like HookCallSite (one `call rel32` of the engine redirected), but the C++
// handler sees the caller's registers at the moment of the call (callee-saved ones included: the values the
// calling engine function keeps there) and may change them before the call returns to the engine.
//
// A site's `call rel32` is redirected to a small per-site stub (mov r11, <site record>; jmp <common thunk>). The
// common thunk (src/platform/<platform>/reg_thunk_*) pushes every general-purpose register into a RegContext on
// the stack, calls the site's handler, pops them back (with the handler's changes) and returns to the engine.
// The original call is made by the handler (CallOriginal), so a handler can run code before and after it.
// Nothing is assembled at run time and no engine instruction is moved: only the call's rel32 changes.
#include <cstdint>

namespace iex {

struct RegContext {
    // Pushed by the thunk, lowest address first.
    std::uint64_t rax, rbx, rcx, rdx, rsi, rdi, rbp, r8, r9, r10, r11, r12, r13, r14, r15;
    std::uint64_t returnAddress;  // the engine instruction after the call
    // The caller's stack at the call (its rsp): stack arguments (win64: after the 32-byte home area) and locals.
    std::uint64_t callerStack[1];

    std::uint64_t& Reg(int index) { return (&rax)[index]; }
    std::uint64_t CallerRsp() const { return reinterpret_cast<std::uint64_t>(&callerStack[0]); }
};

// Register indexes of RegContext::Reg (the push order).
enum RegIndex : int { kRax, kRbx, kRcx, kRdx, kRsi, kRdi, kRbp, kR8, kR9, kR10, kR11, kR12, kR13, kR14, kR15 };

struct RegHookSite;
using RegHandler = void (*)(RegContext& ctx, const RegHookSite& site);

struct RegHookSite {
    std::uintptr_t original;  // what the call targeted before the hook (the engine function, or another IEX hook)
    RegHandler handler;
    std::uintptr_t site;      // address of the E8
    void* user;               // handler data
};

// Redirects the call at `site` (an E8) to `handler`. The call may target anything (`expectedTarget` = 0) or must
// target `expectedTarget`, either directly or through an IEX thunk already sitting there; the current target is
// kept as RegHookSite::original. Returns nullptr (and changes nothing) if the bytes are not a call.
const RegHookSite* HookCallSiteRegs(std::uintptr_t site, RegHandler handler, void* user = nullptr);

// Calls site.original with the integer arguments of the engine's call (win64: rcx, rdx, r8, r9, then the stack
// arguments; linux64: rdi, rsi, rdx, rcx, r8, r9, then the stack arguments; up to 6 stack arguments are passed)
// and returns rax. Arguments in the context can be changed before.
std::uint64_t CallOriginal(RegContext& ctx, const RegHookSite& site);

// Current target of the call at `site` (0 if it is not an E8).
std::uintptr_t CallTarget(std::uintptr_t site);

// Location of an engine value at a hooked call (engine description constant): kind << 16 | offset.
//   kind 1: register, offset = RegIndex.   kind 2: [rbp + (int16)offset].   kind 3: [caller rsp + offset].
std::uint64_t* LocatePointer(RegContext& ctx, std::uint32_t location);

} // namespace iex
