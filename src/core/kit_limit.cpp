#include "kit_limit.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "hook_points.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>

// Sources: the 2.7.3 binaries only (Linux symbols, Windows matching; IEX-data/studies/KIT_LIMIT_STUDY.md and
// IEX-data/engine/win/verified_kitlimit.json). Verified on both builds, 2026-11-04:
//   GetClassAbilityTable  Lin 0x2a1aa0 / Win 0x23cc60: KITLIST = C2DArray at rules+0x2610 (columns +0x2640, rows
//                         +0x2642, cells +0x2630, default +0x2638), CLASS = column 7 (sscanf %d), then
//                         `mov rax, [rules + (row-1)*8 + 0x2648]` with no bound against 256.
//   CRuleTables ctor      Lin 0x2ae5dc / Win 0x238dba: rows 1..min(rows-1, 256), each a 0x38-byte C2DArray (+0 = 0,
//                         +8 CResRef, +0x10/+0x18/+0x20 = 0, +0x28 = the empty CString _afxPchNil, +0x30 = 0), then
//                         C2DArray::Load(ABILITIES = column 4).
//   call sites            AddClassAbilities Lin 0x49f7f5 / Win 0x347d7c, RemoveClassAbilities Lin 0x48db73 /
//                         Win 0x3691c4: the only direct calls; no jmp and no pointer to the function in data.

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kGetClassAbilityTable = "_ZNK11CRuleTables20GetClassAbilityTableEhj";
constexpr const char* kLoad = "_ZN8C2DArray4LoadERK7CResRef";
constexpr const char* kPchNil = "_afxPchNil";
constexpr const char* kGetProfileInt = "_Z22BGGetPrivateProfileIntPKcS0_i";

// CRuleTables layout (same on both builds, checked in the getter's bytes at install).
constexpr Word kKitList = 0x2610;     // C2DArray KITLIST
constexpr Word kClabArray = 0x2648;   // C2DArray* [256], KITLIST rows 1..256
constexpr unsigned kEngineSlots = 256;
constexpr unsigned kMaxRow = 0x3FFF;  // kit value = 0x4000 | row
constexpr int kColAbilities = 4;
constexpr int kColClass = 7;
constexpr std::size_t kC2DArraySize = 0x38;

// ABI: Linux (rdi, sil, edx) / Windows (rcx, dl, r8d), C2DArray* in rax: the same C++ signature on both.
using GetTableFn = const void* (*)(const void* rules, std::uint8_t cls, std::uint32_t kit);
using LoadFn = void (*)(void* table, const void* resref);

GetTableFn g_original = nullptr;
LoadFn g_load = nullptr;
Word g_pchNil = 0;  // address of the engine's empty CString data pointer
bool g_installed = false;
int g_sites = 0;
std::string g_why;

std::mutex g_mutex;
const void* g_rules = nullptr;                 // the CRuleTables the cache belongs to
std::unordered_map<unsigned, void*> g_tables;  // KITLIST row -> IEX-owned C2DArray (never freed, as the engine's)

template <typename T>
T Read(Word address)
{
    T v;
    std::memcpy(&v, reinterpret_cast<const void*>(address), sizeof(T));
    return v;
}

Word Sym(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? EngineImageBase() + rva : 0;
}

// C2DArray cell text (cells +0x20 row-major, default +0x28, columns +0x30 i16, rows +0x32 i16), or the default's.
const char* Cell(Word table, int column, int row)
{
    const std::int16_t columns = Read<std::int16_t>(table + 0x30);
    const std::int16_t rows = Read<std::int16_t>(table + 0x32);
    Word cell = table + 0x28;
    if (column >= 0 && column < columns && row >= 0 && row < rows)
        cell = Read<Word>(table + 0x20) + static_cast<Word>(columns * row + column) * sizeof(Word);
    const char* text = Read<const char*>(cell);
    return text ? text : "";
}

// The CLAB resref of a KITLIST cell as a CResRef (8 upper-case chars, zero padded); false for none / "*".
bool ToResRef(const char* text, char out[8])
{
    std::memset(out, 0, 8);
    std::size_t n = 0;
    for (; text[n] && n < 8; ++n) {
        char c = text[n];
        if (static_cast<unsigned char>(c) <= ' ')
            break;
        out[n] = (c >= 'a' && c <= 'z') ? static_cast<char>(c - 'a' + 'A') : c;
    }
    return n > 0 && !(n == 1 && out[0] == '*');
}

// IEX's table for a row past the engine array: an empty C2DArray as the engine's constructor makes it, filled by
// the engine's C2DArray::Load. A missing CLAB (or "*") stays empty, as the engine's own slots do.
void* Table(const void* rules, unsigned row)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (rules != g_rules) {  // a new CRuleTables (not seen in practice): its rows may differ
        g_rules = rules;
        g_tables.clear();
    }
    auto it = g_tables.find(row);
    if (it != g_tables.end())
        return it->second;
    auto* table = static_cast<std::uint8_t*>(std::calloc(1, kC2DArraySize));
    if (!table)
        return nullptr;
    const Word nil = Read<Word>(g_pchNil);
    std::memcpy(table + 0x28, &nil, sizeof(nil));
    const char* text = Cell(reinterpret_cast<Word>(rules) + kKitList, kColAbilities, static_cast<int>(row));
    char res[8];
    const bool named = ToResRef(text, res);
    if (named)
        g_load(table, res);
    g_tables.emplace(row, table);
    char name[9] = {};
    std::memcpy(name, res, 8);
    Log("Kit limit: KITLIST row %u (kit 0x%04X): CLAB %s, %d rows (IEX table)", row, 0x4000u | row,
        named ? name : "none", static_cast<int>(Read<std::int16_t>(reinterpret_cast<Word>(table) + 0x32)));
    return table;
}

const void* HookGetClassAbilityTable(const void* rules, std::uint8_t cls, std::uint32_t kit)
{
    const std::uint32_t row = kit & ~0x4000u;
    if (!(kit & 0x4000u) || row <= kEngineSlots || !rules)
        return g_original(rules, cls, kit);
    const Word kitList = reinterpret_cast<Word>(rules) + kKitList;
    const std::int16_t columns = Read<std::int16_t>(kitList + 0x30);
    const std::int16_t rows = Read<std::int16_t>(kitList + 0x32);
    if (columns <= kColClass || rows <= 0 || row >= static_cast<std::uint32_t>(rows))
        return g_original(rules, cls, kit);
    const long kitClass = std::strtol(Cell(kitList, kColClass, static_cast<int>(row)), nullptr, 10);
    if (kitClass != static_cast<long>(cls))
        return g_original(rules, cls, kit);  // the engine falls back to the class's default table
    if (void* table = Table(rules, row))
        return table;
    return g_original(rules, cls, kit);
}

// The getter must still be the one described above: its CRuleTables offsets, in its first 0x500 bytes (Linux reads the array at +0x3e3).
bool GetterShape(Word fn)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(fn);
    const auto has = [code](std::uint32_t disp) {
        for (std::size_t i = 0; i + 4 <= 0x500; ++i)
            if (std::memcmp(code + i, &disp, 4) == 0)
                return true;
        return false;
    };
    return has(static_cast<std::uint32_t>(kClabArray)) && has(static_cast<std::uint32_t>(kKitList + 0x30)) &&
           has(static_cast<std::uint32_t>(kKitList + 0x32)) && has(static_cast<std::uint32_t>(kKitList + 0x20));
}

bool CallsTo(Word site, Word target)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    return code[0] == 0xE8 && site + 5 + rel == target;
}

bool Available()
{
    return engineTypes.Symbol(kGetClassAbilityTable) && engineTypes.Symbol(kLoad) && engineTypes.Symbol(kPchNil) &&
           !engineTypes.CallSitesOf(kGetClassAbilityTable).empty();
}

// All call sites or none.
bool Install(std::string& why)
{
    if (!Available()) {
        why = "symbols or call sites missing in the engine description";
        return false;
    }
    const Word base = EngineImageBase();
    const Word fn = Sym(kGetClassAbilityTable);
    if (!GetterShape(fn)) {
        why = "GetClassAbilityTable does not read the expected CRuleTables offsets (other build?)";
        return false;
    }
    const auto sites = engineTypes.CallSitesOf(kGetClassAbilityTable);
    for (std::uint32_t s : sites) {
        if (!CallsTo(base + s, fn)) {
            why = "call site already patched or other build";
            Log("Kit limit: %s (0x%x)", why.c_str(), s);
            return false;
        }
    }
    g_original = reinterpret_cast<GetTableFn>(fn);
    g_load = reinterpret_cast<LoadFn>(Sym(kLoad));
    g_pchNil = Sym(kPchNil);
    for (std::uint32_t s : sites) {
        if (!HookCallSite(base + s, fn, reinterpret_cast<const void*>(&HookGetClassAbilityTable))) {
            why = "code write failed";
            Log("Kit limit: %s at 0x%x (%d sites already redirected)", why.c_str(), s, g_sites);
            return false;
        }
        ++g_sites;
    }
    return true;
}

bool Wanted(const char*& reason)
{
    if (const char* env = std::getenv("IEX_KIT_LIMIT"); env && *env) {
        reason = " (IEX_KIT_LIMIT)";
        return std::strcmp(env, "0") != 0;
    }
    reason = " (Baldur.lua IEX / Unlimited Kits = 0)";
    using GetIntFn = int (*)(const char*, const char*, int);
    const auto getInt = reinterpret_cast<GetIntFn>(Sym(kGetProfileInt));
    return getInt ? getInt("IEX", "Unlimited Kits", 1) != 0 : true;
}

void InstallNow()
{
    const char* reason = "";
    if (!Wanted(reason)) {
        g_why = std::string("off") + reason;
        Log("Kit limit: off%s: single-class kits past KITLIST row %u keep the engine's behaviour", reason, kEngineSlots);
        hp::MarkInstalled(hp::kKitLimit, false, 0, g_why.c_str());
        return;
    }
    std::string why;
    g_installed = Install(why);
    g_why = why;
    if (g_installed)
        Log("Kit limit: %d call sites redirected (single-class kits on KITLIST rows %u-%u get their CLAB from IEX)",
            g_sites, kEngineSlots + 1, kMaxRow);
    else
        Log("Kit limit: not installed: %s", why.c_str());
    hp::MarkInstalled(hp::kKitLimit, g_installed, g_sites, g_installed ? nullptr : g_why.c_str());
}

// IEX_KitLimit() -> {installed, sites, engineSlots, maxRow, tables, why}
int LuaKitLimit(lua_State* L)
{
    lua.createtable(L, 0, 6);
    lua.pushboolean(L, g_installed ? 1 : 0);
    lua.setfield(L, -2, "installed");
    lua.pushinteger(L, g_sites);
    lua.setfield(L, -2, "sites");
    lua.pushinteger(L, kEngineSlots);
    lua.setfield(L, -2, "engineSlots");
    lua.pushinteger(L, g_installed ? kMaxRow : kEngineSlots);
    lua.setfield(L, -2, "maxRow");
    std::size_t tables;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        tables = g_tables.size();
    }
    lua.pushinteger(L, static_cast<lua_Integer>(tables));
    lua.setfield(L, -2, "tables");
    if (!g_why.empty()) {
        lua.pushstring(L, g_why.c_str());
        lua.setfield(L, -2, "why");
    }
    return 1;
}

} // namespace

// Baldur.lua is read once the engine's Lua state is ready, before any character is created or levelled.
void OpenLuaKitLimit(lua_State* L)
{
    static bool done = false;
    if (!done) {
        done = true;
        InstallNow();
    }
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushinteger(L, g_installed ? g_sites : 0);
    lua.setfield(L, -2, "kitLimit");
    lua.settop(L, -2);
    lua.pushcclosure(L, LuaKitLimit, 0);
    lua.setglobal(L, "IEX_KitLimit");
}

} // namespace iex
