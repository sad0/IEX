#include "spell_lists.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "hook_points.h"
#include "iex_core.h"
#include "lua_api.h"
#include "log.h"
#include "reg_hook.h"

#include <algorithm>
#include <cstdint>
#include <initializer_list>
#include <cstring>
#include <string>
#include <vector>

namespace iex {

namespace {

constexpr const char* kGetMageSpell = "_ZNK11CRuleTables12GetMageSpellEii";
constexpr const char* kGetPriestSpell = "_ZNK11CRuleTables14GetPriestSpellEii";
constexpr const char* kGetNumPriestSpells = "_ZNK11CRuleTables18GetNumPriestSpellsEi";

// List types, numbered as in spell.ids (type * 1000 + level * 100 + n).
constexpr int kPriest = 1;
constexpr int kWizard = 2;
constexpr int kMaxLevel[3] = {0, 7, 9};

// A resref as the engine stores it (CResRef: 8 upper-case chars, zero padded; all zero = empty).
using Res = std::uint64_t;

std::vector<Res> g_lists[3][10];  // [type][level]

std::vector<Res>* List(int type, int level)
{
    if (type != kPriest && type != kWizard)
        return nullptr;
    if (level < 1 || level > kMaxLevel[type])
        return nullptr;
    return &g_lists[type][level];
}

// Resref text -> Res. False for an empty, too long or badly formed name.
bool ToRes(const char* text, Res& out)
{
    if (!text)
        return false;
    const std::size_t n = std::strlen(text);
    if (n == 0 || n > 8)
        return false;
    char b[8] = {};
    for (std::size_t i = 0; i < n; ++i) {
        char c = text[i];
        if (c >= 'a' && c <= 'z')
            c = static_cast<char>(c - 'a' + 'A');
        if (static_cast<unsigned char>(c) <= ' ' || c == '.' || c == '/' || c == '\\')
            return false;
        b[i] = c;
    }
    std::memcpy(&out, b, 8);
    return true;
}

std::string ResText(Res r)
{
    char b[9] = {};
    std::memcpy(b, &r, 8);
    return b;
}

// --- engine getters (originals) and their ABI ---
//   linux64: CResRef GetMageSpell(this, level, index), the 8-byte CResRef returned in rax
//   win64:   CResRef* GetMageSpell(this, CResRef* out, level, index), returned through the hidden pointer
//   both:    int GetNumPriestSpells(this, level)
#if defined(_WIN32)
using GetFn = void* (*)(const void* rules, void* out, int level, int index);
#else
using GetFn = Res (*)(const void* rules, int level, int index);
#endif
using NumFn = int (*)(const void* rules, int level);

GetFn g_get[3] = {};  // [type]
NumFn g_numPriest = nullptr;

// The engine's own answer. Index 99 and up are never asked: "SPWI<l>100" does not fit the getters' 8-byte buffer,
// whatever their bound is.
Res Original(int type, const void* rules, int level, int index)
{
    if (index < 0 || index > 98)
        return 0;
#if defined(_WIN32)
    Res r = 0;
    g_get[type](rules, &r, level, index);
    return r;
#else
    return g_get[type](rules, level, index);
#endif
}

// Number of slots the engine getter answers right now: 50 on vanilla, 99 with spellSlots99 (or any other bound a
// byte patch put there). The getter answers every index up to its bound and nothing past it, so the first empty
// answer is found by bisection (at most 7 calls).
int Base(int type, const void* rules, int level)
{
    if (Original(type, rules, level, 98) != 0)
        return 99;
    int lo = 0, hi = 98;  // answer in [lo, hi]: Original(hi) is empty
    while (lo < hi) {
        const int mid = (lo + hi) / 2;
        if (Original(type, rules, level, mid) != 0)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}

int g_logged[3][10] = {};  // base logged once per type and level (diagnostics)

Res Resolve(int type, const void* rules, int level, int index)
{
    const Res own = Original(type, rules, level, index);
    if (own != 0)
        return own;
    const std::vector<Res>* list = List(type, level);
    if (!list || list->empty() || index < 0)
        return own;
    const int base = Base(type, rules, level);
    if (!g_logged[type][level]) {
        g_logged[type][level] = 1;
        Log("Spell lists: %s level %d: engine slots 01-%02d, then %zu IEX entries", type == kWizard ? "wizard" : "priest",
            level, base, list->size());
    }
    const long long k = static_cast<long long>(index) - base;
    if (k < 0 || k >= static_cast<long long>(list->size()))
        return 0;
    return (*list)[static_cast<std::size_t>(k)];
}

// Priest loops bounded by GetNumPriestSpells (CGameSprite::AddNewSpellsPriest, both MakeDualClass): SPELLS.2DA
// keeps limiting the engine slots there, as without IEX: engine slots 0 .. min(2DA, base) - 1, then the IEX list.
// The chargen / level-up lists (read until the empty resref) keep using Resolve: the engine shows every slot up to
// its bound there, whatever SPELLS.2DA says.
int CountedBase(const void* rules, int level)
{
    const int n = g_numPriest(rules, level);
    const int b = Base(kPriest, rules, level);
    return n < 0 ? 0 : (n < b ? n : b);
}

Res ResolveCounted(const void* rules, int level, int index)
{
    const std::vector<Res>* list = List(kPriest, level);
    if (!list || list->empty() || index < 0)
        return Original(kPriest, rules, level, index);
    const int nb = CountedBase(rules, level);
    if (index < nb)
        return Original(kPriest, rules, level, index);
    const long long k = static_cast<long long>(index) - nb;
    return k < static_cast<long long>(list->size()) ? (*list)[static_cast<std::size_t>(k)] : 0;
}

#if defined(_WIN32)
void* HookMage(const void* rules, void* out, int level, int index)
{
    const Res r = Resolve(kWizard, rules, level, index);
    std::memcpy(out, &r, 8);
    return out;
}

void* HookPriest(const void* rules, void* out, int level, int index)
{
    const Res r = Resolve(kPriest, rules, level, index);
    std::memcpy(out, &r, 8);
    return out;
}

void* HookPriestCounted(const void* rules, void* out, int level, int index)
{
    const Res r = ResolveCounted(rules, level, index);
    std::memcpy(out, &r, 8);
    return out;
}
#else
Res HookMage(const void* rules, int level, int index)
{
    return Resolve(kWizard, rules, level, index);
}

Res HookPriest(const void* rules, int level, int index)
{
    return Resolve(kPriest, rules, level, index);
}

Res HookPriestCounted(const void* rules, int level, int index)
{
    return ResolveCounted(rules, level, index);
}
#endif

// Loop count of CGameSprite::AddNewSpellsPriest and of the dual-class priest spells (SPELLS.2DA PRIEST row):
// min(2DA, engine base) engine slots, then the IEX list (see ResolveCounted). Unchanged while the list is empty.
int HookNumPriest(const void* rules, int level)
{
    const std::vector<Res>* list = List(kPriest, level);
    if (!list || list->empty())
        return g_numPriest(rules, level);
    const long long want = static_cast<long long>(CountedBase(rules, level)) + static_cast<long long>(list->size());
    return static_cast<int>(want > 0x7fffffff ? 0x7fffffff : want);
}

// --- CScreenCreateChar::MageSchoolSpellsAvailable(level, sprite) ---
// "Has this level a spell of the specialist's school?" (bonus slot). Its loop is a fixed 0..49 around one
// GetMageSpell call, so it never saw slots 51-99 nor the IEX list. A register hook on that call keeps the engine's
// own per-spell test and drives the loop counter: the call gets the virtual index v (0, 1, 2...), and the counter
// register is set so that the engine's `counter + 1 == 50` exit happens right after the last slot / list entry.
//   win64:   counter dil (`movzx r9d, dil` before the call; `inc dil` +0x141, `cmp dil, 0x32; jb` +0x148)
//   linux64: counter ebx (`mov edx, ebx` before the call; `add ebx, 1; cmp ebx, 0x32` at -0x17 / -0x14 and at
//            +0xbf / +0xc7)
// With at most 50 entries nothing changes (the engine's own counter runs).
constexpr std::uint64_t kSchoolCounterContinue = 10;  // next counter seen: 11 (never 0 = loop start, never 50)
constexpr std::uint64_t kSchoolCounterLast = 0x31;    // + 1 = 0x32: the engine leaves the loop
long long g_schoolIndex = 0;

bool SchoolSiteShape(std::uintptr_t site)
{
    const auto* c = reinterpret_cast<const std::uint8_t*>(site);
    const auto at = [c](std::ptrdiff_t off, std::initializer_list<std::uint8_t> bytes) {
        std::ptrdiff_t i = 0;
        for (std::uint8_t b : bytes)
            if (c[off + i++] != b)
                return false;
        return true;
    };
#if defined(_WIN32)
    return at(-14, {0x44, 0x0F, 0xB6, 0xCF}) && at(0x141, {0x40, 0xFE, 0xC7}) &&
           at(0x148, {0x40, 0x80, 0xFF, 0x32, 0x0F, 0x82});
#else
    return at(-2, {0x89, 0xDA}) && at(-0x17, {0x83, 0xC3, 0x01}) && at(-0x14, {0x83, 0xFB, 0x32}) &&
           at(0xbf, {0x83, 0xC3, 0x01}) && at(0xc7, {0x83, 0xFB, 0x32});
#endif
}

void RegSchool(RegContext& ctx, const RegHookSite&)
{
#if defined(_WIN32)
    const void* rules = reinterpret_cast<const void*>(ctx.rcx);
    const int level = static_cast<int>(ctx.r8);
    std::uint64_t& counterReg = ctx.rdi;
    const std::uint64_t counter = counterReg & 0xFF;
#else
    const void* rules = reinterpret_cast<const void*>(ctx.rdi);
    const int level = static_cast<int>(ctx.rsi);
    std::uint64_t& counterReg = ctx.rbx;
    const std::uint64_t counter = counterReg & 0xFFFFFFFF;
#endif
    const std::vector<Res>* list = List(kWizard, level);
    const long long total =
        static_cast<long long>(Base(kWizard, rules, level)) + (list ? static_cast<long long>(list->size()) : 0);
    Res r;
    if (total <= 50) {
        r = Resolve(kWizard, rules, level, static_cast<int>(counter));  // the engine's own loop
    } else {
        g_schoolIndex = counter == 0 ? 0 : g_schoolIndex + 1;
        r = Resolve(kWizard, rules, level, static_cast<int>(g_schoolIndex));
        const std::uint64_t next = g_schoolIndex + 1 < total ? kSchoolCounterContinue : kSchoolCounterLast;
#if defined(_WIN32)
        counterReg = (counterReg & ~0xFFull) | next;
#else
        counterReg = next;
#endif
    }
#if defined(_WIN32)
    std::memcpy(reinterpret_cast<void*>(ctx.rdx), &r, 8);
    ctx.rax = ctx.rdx;
#else
    ctx.rax = r;
#endif
}

struct Target {
    const char* name;
    const void* replacement;
};

const Target kTargets[] = {
    {kGetMageSpell, reinterpret_cast<const void*>(&HookMage)},
    {kGetPriestSpell, reinterpret_cast<const void*>(&HookPriest)},
    {kGetNumPriestSpells, reinterpret_cast<const void*>(&HookNumPriest)},
};

bool Available()
{
    for (const Target& t : kTargets)
        if (!engineTypes.Symbol(t.name) || engineTypes.CallSitesOf(t.name).empty())
            return false;
    return true;
}

bool CallsTo(std::uintptr_t site, std::uintptr_t target)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    return code[0] == 0xE8 && site + 5 + rel == target;
}

// All call sites or none: a list read through IEX in chargen but not for the priests' automatic spells would only
// confuse.
bool Install(std::string& why, std::uintptr_t, std::uintptr_t)
{
    const std::uintptr_t base = EngineImageBase();
    for (const Target& t : kTargets) {
        const std::uintptr_t fn = base + engineTypes.Symbol(t.name);
        for (std::uint32_t s : engineTypes.CallSitesOf(t.name)) {
            if (!CallsTo(base + s, fn)) {
                why = std::string(t.name) + ": call site already patched or other build";
                Log("Spell lists: %s (0x%x)", why.c_str(), s);
                return false;
            }
        }
    }
    g_get[kWizard] = reinterpret_cast<GetFn>(base + engineTypes.Symbol(kGetMageSpell));
    g_get[kPriest] = reinterpret_cast<GetFn>(base + engineTypes.Symbol(kGetPriestSpell));
    g_numPriest = reinterpret_cast<NumFn>(base + engineTypes.Symbol(kGetNumPriestSpells));
    // Build constants: the GetMageSpell call of MageSchoolSpellsAvailable, the GetNumPriestSpells-bounded priest calls.
    std::uint64_t schoolSite = 0;
    engineTypes.Const("IEX.spellLists.schoolSite", schoolSite);
    std::vector<std::uint32_t> counted;
    for (int i = 0; i < 16; ++i) {
        std::uint64_t v = 0;
        if (!engineTypes.Const("IEX.spellLists.countedPriest." + std::to_string(i), v))
            break;
        counted.push_back(static_cast<std::uint32_t>(v));
    }
    const bool school = schoolSite && SchoolSiteShape(base + schoolSite);
    if (!school)
        Log("Spell lists: MageSchoolSpellsAvailable loop not found as expected, specialist check stays on slots 01-50");
    int sites = 0;
    for (const Target& t : kTargets) {
        const std::uintptr_t fn = base + engineTypes.Symbol(t.name);
        for (std::uint32_t s : engineTypes.CallSitesOf(t.name)) {
            const void* replacement = t.replacement;
            if (t.name == kGetMageSpell && school && s == schoolSite) {
                if (!HookCallSiteRegs(base + s, &RegSchool)) {
                    why = "code write failed";
                    Log("Spell lists: %s at 0x%x (%d sites already redirected)", why.c_str(), s, sites);
                    return false;
                }
                ++sites;
                continue;
            }
            if (t.name == kGetPriestSpell && std::find(counted.begin(), counted.end(), s) != counted.end())
                replacement = reinterpret_cast<const void*>(&HookPriestCounted);
            if (!HookCallSite(base + s, fn, replacement)) {
                why = "code write failed";
                Log("Spell lists: %s at 0x%x (%d sites already redirected)", why.c_str(), s, sites);
                return false;
            }
            ++sites;
        }
    }
    hp::SetSites(hp::kSpellLists, sites);
    Log("Spell lists: %d call sites redirected (class spell lists continue with the IEX lists; %zu SPELLS.2DA-bounded "
        "priest calls; specialist check %s)",
        sites, counted.size(), school ? "extended" : "slots 01-50");
    return true;
}

// --- Lua ---

int ArgInt(lua_State* L, int i)
{
    return lua.type(L, i) == LUA_TNUMBER ? static_cast<int>(lua.tointegerx(L, i, nullptr)) : 0;
}

std::vector<Res>* ArgList(lua_State* L, const char* fn)
{
    std::vector<Res>* list = List(ArgInt(L, 1), ArgInt(L, 2));
    if (!list)
        LuaError(L, "%s: type 1 (priest, levels 1-7) or 2 (wizard, levels 1-9) and a level expected", fn);
    return list;
}

Res ArgRes(lua_State* L, int i, const char* fn)
{
    Res r = 0;
    const char* text = lua.type(L, i) == LUA_TSTRING ? lua.tolstring(L, i, nullptr) : nullptr;
    if (!ToRes(text, r))
        LuaError(L, "%s: resref of 1-8 characters expected", fn);
    return r;
}

// IEX_SpellList_Add(type, level, resref) -> true, or false when the resref is already in that list.
int LuaAdd(lua_State* L)
{
    std::vector<Res>* list = ArgList(L, "IEX_SpellList_Add");
    const Res r = ArgRes(L, 3, "IEX_SpellList_Add");
    for (Res x : *list) {
        if (x == r) {
            lua.pushboolean(L, 0);
            return 1;
        }
    }
    list->push_back(r);
    lua.pushboolean(L, 1);
    return 1;
}

// IEX_SpellList_Remove(type, level, resref) -> true if it was in the list.
int LuaRemove(lua_State* L)
{
    std::vector<Res>* list = ArgList(L, "IEX_SpellList_Remove");
    const Res r = ArgRes(L, 3, "IEX_SpellList_Remove");
    for (std::size_t i = 0; i < list->size(); ++i) {
        if ((*list)[i] == r) {
            list->erase(list->begin() + static_cast<std::ptrdiff_t>(i));
            lua.pushboolean(L, 1);
            return 1;
        }
    }
    lua.pushboolean(L, 0);
    return 1;
}

// IEX_SpellList_Get(type, level) -> { resref, ... } in list order.
int LuaGet(lua_State* L)
{
    const std::vector<Res>* list = ArgList(L, "IEX_SpellList_Get");
    lua.createtable(L, static_cast<int>(list->size()), 0);
    int i = 0;
    for (Res r : *list) {
        lua.pushstring(L, ResText(r).c_str());
        lua.rawseti(L, -2, ++i);
    }
    return 1;
}

// IEX_SpellList_Count(type, level) -> number of IEX entries.
int LuaCount(lua_State* L)
{
    lua.pushinteger(L, static_cast<lua_Integer>(ArgList(L, "IEX_SpellList_Count")->size()));
    return 1;
}

// IEX_SpellList_Clear([type [, level]]): one list, every list of a type, or all.
int LuaClear(lua_State* L)
{
    const int type = ArgInt(L, 1), level = ArgInt(L, 2);
    for (int t = kPriest; t <= kWizard; ++t)
        for (int l = 1; l <= kMaxLevel[t]; ++l)
            if ((type == 0 || type == t) && (level == 0 || level == l))
                g_lists[t][l].clear();
    return 0;
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

void InstallSpellListHooks()
{
    hp::SetInstaller(hp::kSpellLists, &Install, &Available);
}

void OpenLuaSpellLists(lua_State* L)
{
    Register(L, "IEX_SpellList_Add", LuaAdd);
    Register(L, "IEX_SpellList_Remove", LuaRemove);
    Register(L, "IEX_SpellList_Get", LuaGet);
    Register(L, "IEX_SpellList_Count", LuaCount);
    Register(L, "IEX_SpellList_Clear", LuaClear);
}

} // namespace iex
