#include "spell_slots.h"

#include "engine_types.h"
#include "hook_points.h"
#include "iex_core.h"
#include "log.h"
#include "platform_memory.h"

#include <cstdint>
#include <cstring>
#include <string>

namespace iex {

namespace {

constexpr const char* kGetMageSpell = "_ZNK11CRuleTables12GetMageSpellEii";
constexpr const char* kGetPriestSpell = "_ZNK11CRuleTables14GetPriestSpellEii";

// The bound test near the start of both functions, `index > 49 -> empty resref`:
//   Windows (index in r9d):  41 83 F9 31   cmp r9d, 0x31   77 xx  ja
//   Linux   (index in edx):  83 FA 31      cmp edx, 0x31   76 xx  jbe
// Returns the address of the 0x31 byte, or 0 when the function does not hold exactly one such test.
std::uintptr_t FindBound(std::uintptr_t fn)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(fn);
    std::uintptr_t found = 0;
    for (int i = 0; i + 4 < 0x40; ++i) {
        const bool win = code[i] == 0x41 && code[i + 1] == 0x83 && code[i + 2] == 0xF9 && code[i + 3] == 0x31 &&
                         code[i + 4] == 0x77;
        const bool lin = code[i] == 0x83 && code[i + 1] == 0xFA && code[i + 2] == 0x31 && code[i + 3] == 0x76;
        if (!win && !lin)
            continue;
        if (found)
            return 0;
        found = fn + i + (win ? 3 : 2);
    }
    return found;
}

std::uintptr_t g_sites[2] = {};

bool Available()
{
    return engineTypes.Symbol(kGetMageSpell) && engineTypes.Symbol(kGetPriestSpell);
}

// Both sites or none: the lists of one type at 99 and the other at 50 would only confuse.
bool Install(std::string& why, std::uintptr_t, std::uintptr_t)
{
    const char* names[2] = {kGetMageSpell, kGetPriestSpell};
    for (int i = 0; i < 2; ++i) {
        const std::uint32_t rva = engineTypes.Symbol(names[i]);
        g_sites[i] = rva ? FindBound(EngineImageBase() + rva) : 0;
        if (!g_sites[i]) {
            why = std::string(names[i]) + ": bound test not found (other build or already patched)";
            Log("Spell slots 51-99: %s", why.c_str());
            return false;
        }
    }
    const std::uint8_t bound = 0x62;  // index > 98 -> empty: slots 01-99
    for (std::uintptr_t site : g_sites) {
        if (!platform::PatchCode(reinterpret_cast<void*>(site), &bound, 1)) {
            why = "code write failed";
            Log("Spell slots 51-99: %s", why.c_str());
            return false;
        }
    }
    Log("Spell slots 51-99: class spell lists read SPWI/SPPR slots 01-99");
    return true;
}

} // namespace

void InstallSpellSlotHooks()
{
    hp::SetInstaller(hp::kSpellSlots99, &Install, &Available);
}

} // namespace iex
