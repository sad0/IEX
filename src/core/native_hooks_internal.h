#pragma once

// Shared helpers of the native hook points (native_hooks.cpp, native_hooks_sado.cpp). Not a public API.
#include "engine_types.h"
#include "lua_api.h"

#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <string>

namespace iex::nh {

using Word = std::uintptr_t;

// Address of a symbol of the engine description in the running image (0 when the build lacks it).
Word Sym(const char* name);
// Field offset from the engine description (0 when missing).
std::uint32_t FieldOffset(const char* type, const char* field);
// The engine's Lua state (set by OpenLuaNativeHooks).
lua_State* State();


// Bytes of a small fixed thunk, assembled from literal instruction bytes and absolute addresses (no assembler:
// each behaviour writes its own few instructions).
struct Code {
    std::uint8_t b[160] = {};
    std::size_t n = 0;
    bool overflow = false;

    void Put(std::initializer_list<std::uint8_t> bytes);
    void PutBytes(const std::uint8_t* bytes, std::size_t count);
    void Put32(std::uint32_t v);
    void Put64(std::uint64_t v);
    void JmpAbs(Word target);   // jmp qword ptr [rip+0] ; target          (no register changed)
    void CallRax(Word target);  // mov rax, target ; call rax               (rax changed)
    std::size_t Jcc8(std::uint8_t opcode);  // short conditional jump, target set later by Land()
    void Land(std::size_t jccAt);           // makes the jump at jccAt land here
};

// True if the bytes at `at` are `bytes`.
bool BytesAre(Word at, const std::uint8_t* bytes, std::size_t count);

// Copies `code` to executable memory near `site` and writes `jmp thunk` over the first `overwrite` (>= 5) bytes
// at `site`, the rest filled with NOPs. The caller has checked the bytes at `site`.
bool JumpToThunk(Word site, std::size_t overwrite, const Code& code, std::string& why);

// Redirects the call at `site` to a fixed thunk built from `code` (entered by the call: the return address is on
// the stack). The call must currently reach `expectedTarget`.
bool CallToThunk(Word site, Word expectedTarget, const Code& code, std::string& why);

// Target of the E8 / E9 rel32 at `at` (0 when the opcode is neither).
Word RelTarget(Word at);

} // namespace iex::nh

namespace iex {

// Installers of the SadoEE hook points in native_hooks_sado.cpp (true = installed; `why` = reason otherwise).
// `a` / `b`: the integer arguments of IEX_NativeHook_Install(name, a, b).
bool InstallGroundContainer(std::string& why);
bool InstallSmallFootprint(std::string& why, nh::Word mode);
bool InstallContainerMarker(std::string& why, nh::Word colorAddress, nh::Word marker);
bool InstallLastingModes(std::string& why);
bool InstallFindTrapsButton(std::string& why);
bool InstallStealthReveals(std::string& why);
// Engine file / store functions for the Lua API (IEX_Eng_StoreAddItem...), registered by OpenLuaNativeHooks.
void OpenLuaSadoFunctions(lua_State* L);
// Availability of these hook points on this build (their sites are in the engine description).
bool SadoGroundContainerAvailable();
bool SadoSmallFootprintAvailable();
bool SadoContainerMarkerAvailable();
bool SadoLastingModesAvailable();
bool SadoFindTrapsButtonAvailable();
bool SadoStealthRevealsAvailable();

} // namespace iex
