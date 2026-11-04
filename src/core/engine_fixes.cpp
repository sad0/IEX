#include "engine_fixes.h"
#include "engine_fix_triggers.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "platform_memory.h"
#include "reg_hook.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// Sources: the public bug descriptions of the EE Fixpack thread (docs/ENGINE_FIXES.md). Every site below was found
// in the 2.7.3 binaries (Linux symbols, Windows matching, IEX-data/engine/win/verified_fixes.json); no EEex code.

namespace iex {

namespace {

using Word = std::uintptr_t;

struct FixState {
    const char* name;
    bool installed = false;
};

std::vector<FixState> g_fixes;
bool g_debug = false;  // IEX_FIX_DEBUG=1: the speed and HP fixes log what they compute (tools/fixtest)

Word Sym(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? EngineImageBase() + rva : 0;
}

Word Const(const char* name)
{
    std::uint64_t v = 0;
    return engineTypes.Const(name, v) ? static_cast<Word>(v) : 0;
}

std::uint32_t FieldOffset(const char* type, const char* field)
{
    const TypeDesc* t = engineTypes.Get(type);
    std::uint32_t offset = 0;
    return t && t->Find(field, offset) ? offset : 0;
}

template <typename T>
T Read(Word address)
{
    T v;
    std::memcpy(&v, reinterpret_cast<const void*>(address), sizeof(T));
    return v;
}

bool Matches(Word address, const std::uint8_t* bytes, std::size_t size)
{
    return std::memcmp(reinterpret_cast<const void*>(address), bytes, size) == 0;
}

bool Patch(Word address, const void* bytes, std::size_t size)
{
    return platform::PatchCode(reinterpret_cast<void*>(address), bytes, size);
}

// The one `call rel32` to `target` in [fn, fn + size), or 0 when there is none or more than one.
Word FindCall(Word fn, std::size_t size, Word target)
{
    Word found = 0;
    const auto* code = reinterpret_cast<const std::uint8_t*>(fn);
    for (std::size_t i = 0; i + 5 <= size; ++i) {
        if (code[i] != 0xE8)
            continue;
        std::int32_t rel;
        std::memcpy(&rel, code + i + 1, 4);
        if (fn + i + 5 + static_cast<std::intptr_t>(rel) != target)
            continue;
        if (found)
            return 0;
        found = fn + i;
    }
    return found;
}

// Baldur.lua (loaded by the engine before its Lua state is ready): [IEX] 'Engine Fixes' 0 turns every fix off,
// [IEX] 'Engine Fix <name>' 0 one fix. The environment variables take precedence over both.
using GetIntFn = int (*)(const char*, const char*, int);
constexpr const char* kGetProfileInt = "_Z22BGGetPrivateProfileIntPKcS0_i";

int IniInt(const char* key, int fallback)
{
    static const GetIntFn getInt = reinterpret_cast<GetIntFn>(Sym(kGetProfileInt));
    return getInt ? getInt("IEX", key, fallback) : fallback;
}

bool OffByName(const char* name)
{
    if (const char* env = std::getenv("IEX_ENGINE_FIXES_OFF")) {
        const std::string list = std::string(",") + env + ",";
        return list.find(std::string(",") + name + ",") != std::string::npos;
    }
    return IniInt((std::string("Engine Fix ") + name).c_str(), 1) == 0;
}

// Game rules (CInfGame derives from CRuleTables): g_pBaldurChitin->m_pObjectGame.
Word Game()
{
    static const Word chitin = Sym("g_pBaldurChitin");
    static const std::uint32_t gameOffset = FieldOffset("CBaldurChitin", "m_pObjectGame");
    if (!chitin || !gameOffset)
        return 0;
    const Word object = Read<Word>(chitin);
    return object ? Read<Word>(object + gameOffset) : 0;
}

// C2DArray (same layout on both builds): cells +0x20 (CString per cell, row-major), default cell +0x28,
// columns +0x30 (i16), rows +0x32 (i16). The cell's text, or the default's.
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

// --- 1. op182: the found slot index was tested as a boolean (amulet slot 0 = "not equipped", -1 = "equipped") ---

constexpr const char* kEquipItemApply = "_ZN31CGameEffectApplyEffectEquipItem11ApplyEffectEP11CGameSprite";
constexpr const char* kFindItemPersonal = "_ZN11CGameSprite16FindItemPersonalERK7CStringiii";
Word g_findItemPersonal = 0;

// Returns 1 when the item is found (any slot, amulet included), 0 when not (-1).
Word FixFindItemPersonal(Word sprite, Word name, int count, int skipInventory, int selectedOnly)
{
    const auto r = static_cast<std::int16_t>(reinterpret_cast<Word (*)(Word, Word, int, int, int)>(g_findItemPersonal)(
        sprite, name, count, skipInventory, selectedOnly));
    return r != -1 ? 1 : 0;
}

bool InstallOp182()
{
    const Word fn = Sym(kEquipItemApply);
    g_findItemPersonal = Sym(kFindItemPersonal);
    const Word site = fn && g_findItemPersonal ? FindCall(fn, 0x200, g_findItemPersonal) : 0;
    return site && HookCallSite(site, g_findItemPersonal, reinterpret_cast<const void*>(&FixFindItemPersonal));
}

// --- 2 + 12. Swing speed factor: WSPECIAL SPEED column, launcher weapon speed instead of the ammo's ---

constexpr const char* kSwing = "_ZN11CGameSprite5SwingEPS_";
constexpr const char* kMax = "_Z3maxRKiS0_";
Word g_getLauncher = 0, g_demand = 0, g_getAbility = 0, g_proficiencies = 0;
int g_regSprite = 0, g_regItem = 0, g_regAbility = 0;
constexpr std::uint32_t kWeaponSpecialization = 0x1500;  // CRuleTables: the WSPECIAL C2DArray (both builds)

// At `max(&zero, &diff)` of CGameSprite::Swing, diff = ability speed (+0x12) - the sprite's speed bonus stat.
// The ammo's speed is replaced by its launcher's, and the WSPECIAL SPEED cell (column 2) of the weapon's
// proficiency level (the larger of weapon and launcher, as for the HIT / DAMAGE columns) is added: the vanilla
// table gives High Mastery -1 and Grand Mastery -3 (a lower speed factor attacks sooner).
void SwingSpeedHandler(RegContext& ctx, const RegHookSite& site)
{
#ifdef _WIN32
    auto* diff = reinterpret_cast<int*>(ctx.rdx);
#else
    auto* diff = reinterpret_cast<int*>(ctx.rsi);
#endif
    const Word sprite = ctx.Reg(g_regSprite);
    const Word item = ctx.Reg(g_regItem);
    const Word ability = ctx.Reg(g_regAbility);
    if (diff && sprite && ability) {
        const int abilitySpeed = Read<std::uint8_t>(ability + 0x12);
        const int bonus = abilitySpeed - *diff;
        int speed = abilitySpeed;
        Word launcher = 0;
        if (Read<std::uint8_t>(ability) == 2) {  // ranged: ammo fired from a launcher
            std::int16_t slot = 0;
            launcher = reinterpret_cast<Word (*)(Word, Word, std::int16_t*)>(g_getLauncher)(sprite, ability, &slot);
            if (launcher) {
                reinterpret_cast<void (*)(Word)>(g_demand)(launcher);
                const Word launcherAbility = reinterpret_cast<Word (*)(Word, int)>(g_getAbility)(launcher, 0);
                if (launcherAbility)
                    speed = Read<std::uint8_t>(launcherAbility + 0x12);
            }
        }
        int level = item ? static_cast<std::int16_t>(reinterpret_cast<Word (*)(Word, Word)>(g_proficiencies)(sprite, item)) : 0;
        if (launcher) {
            const int launcherLevel = static_cast<std::int16_t>(
                reinterpret_cast<Word (*)(Word, Word)>(g_proficiencies)(sprite, launcher));
            if (launcherLevel > level)
                level = launcherLevel;
        }
        int special = 0;
        const Word game = Game();
        if (level > 0 && game)
            special = std::atoi(Cell(game + kWeaponSpecialization, 2, level));
        static int logged = 0;
        if (g_debug && logged < 40) {
            ++logged;
            Log("swing fix: ability type %d speed %d, launcher %s speed %d, bonus %d, proficiency %d, WSPECIAL SPEED %d:"
                " %d -> %d", Read<std::uint8_t>(ability), abilitySpeed, launcher ? "yes" : "no", speed, bonus, level,
                special, *diff, speed - bonus + special);
        }
        *diff = speed - bonus + special;
    }
    ctx.rax = CallOriginal(ctx, site);
}

bool InstallSwingSpeed()
{
    const Word swing = Sym(kSwing);
    const Word max = Sym(kMax);
    const Word site = Const("IEX.fix.swingMaxSite") ? EngineImageBase() + Const("IEX.fix.swingMaxSite") : 0;
    const Word regs = Const("IEX.fix.swingRegs");
    g_getLauncher = Sym("_ZN11CGameSprite11GetLauncherEPK15Item_ability_stRs");
    g_demand = Sym("_ZN5CItem6DemandEv");
    g_getAbility = Sym("_ZNK5CItem10GetAbilityEi");
    g_proficiencies = Sym("_ZN11CGameSprite13ProficienciesEPK5CItem");
    if (!swing || !max || !site || !regs || !g_getLauncher || !g_demand || !g_getAbility || !g_proficiencies)
        return false;
    if (site < swing || site > swing + 0x1000 || CallTarget(site) != max)
        return false;
    g_regSprite = static_cast<int>(regs & 0xff);
    g_regItem = static_cast<int>((regs >> 8) & 0xff);
    g_regAbility = static_cast<int>((regs >> 16) & 0xff);
    return HookCallSiteRegs(site, &SwingSpeedHandler) != nullptr;
}

// --- 3. SPLPROT: CRuleTables::Compare compared stat values unsigned (negative resistances > 100) ---

constexpr const char* kCompare = "_ZNK11CRuleTables7CompareEjji";
constexpr std::uint64_t kComparePrologues[] = {
    0x0f0bf983fa1e0ff3ull,  // Linux: endbr64; cmp ecx, 0xb; ja
    0x63491c770bf98341ull,  // Windows: cmp r9d, 0xb; ja; movsxd
};

// Same relations as the engine (SPLPROT.2DA relation column), signed. `value` is the creature's, `ref` the table's.
Word FixCompare(Word, std::uint32_t value, std::uint32_t ref, int relation)
{
    const auto v = static_cast<std::int32_t>(value);
    const auto r = static_cast<std::int32_t>(ref);
    switch (relation) {
    case 0: return v <= r;
    case 1: return v == r;
    case 2: return v < r;
    case 3: return v > r;
    case 4: return v >= r;
    case 5: return v != r;
    case 6: return (value & ~ref) == 0;
    case 7: return (~value & ref) == 0;
    case 8: return (value & ref) != 0;
    case 9: return (value & ref) == 0;
    case 10: return (value & ~ref) != 0;
    case 11: return (~value & ref) != 0;
    default: return 0;
    }
}

bool InstallSplprot()
{
    const Word fn = Sym(kCompare);
    if (!fn)
        return false;
    for (std::uint64_t prologue : kComparePrologues)
        if (FunctionEntryIntact(fn, prologue))
            return HookFunctionEntry(fn, prologue, reinterpret_cast<const void*>(&FixCompare));
    return false;
}

// --- 4. TRAPLIMT: "limit < traps set" refused only past the limit, so one trap more than the cap could be set ---

constexpr const char* kSetSnareApply = "_ZN19CGameEffectSetSnare11ApplyEffectEP11CGameSprite";
constexpr const char* kSetSnareLimit = "_ZNK11CRuleTables16GetSetSnareLimitEP11CGameSprite";

bool InstallTrapLimit()
{
    const Word fn = Sym(kSetSnareApply);
    const Word limit = Sym(kSetSnareLimit);
    const Word site = fn && limit ? FindCall(fn, 0x200, limit) : 0;
    if (!site)
        return false;
    const Word after = site + 5;
    static const std::uint8_t lin[] = {0x41, 0x39, 0xC6, 0x0F, 0x8F};  // cmp r14d, eax; jg refuse
    static const std::uint8_t win[] = {0x3B, 0xD8, 0x7E};              // cmp ebx, eax; jle accept
    if (Matches(after, lin, sizeof(lin))) {
        const std::uint8_t jge = 0x8D;
        return Patch(after + 4, &jge, 1);
    }
    if (Matches(after, win, sizeof(win))) {
        const std::uint8_t jl = 0x7C;
        return Patch(after + 2, &jl, 1);
    }
    return false;
}

// --- 5. op33 param2 3: the current-pass write went to SAVEVSWANDS (+0x1136) instead of SAVEVSDEATH (+0x1134) ---

constexpr const char* kSaveVsDeathApply = "_ZN22CGameEffectSaveVsDeath11ApplyEffectEP11CGameSprite";

bool InstallSaveVsDeath()
{
    const Word fn = Sym(kSaveVsDeathApply);
    if (!fn)
        return false;
    // sub word ptr [reg + 0x1136], ax  (66 29 /0 with mod 10: 86 = rsi, 87 = rdi ...), exactly once
    const auto* code = reinterpret_cast<const std::uint8_t*>(fn);
    Word found = 0;
    for (int i = 0; i + 7 <= 0x200; ++i) {
        if (code[i] == 0x66 && code[i + 1] == 0x29 && (code[i + 2] & 0xF8) == 0x80 && code[i + 2] != 0x84 &&
            code[i + 3] == 0x36 && code[i + 4] == 0x11 && code[i + 5] == 0 && code[i + 6] == 0) {
            if (found)
                return false;
            found = fn + i + 3;
        }
    }
    const std::uint8_t death = 0x34;
    return found && Patch(found, &death, 1);
}

// --- 6. op206 / op232 / op256 messages: CGameEffect::CheckAdd replaced every immunity string but 0xF00074 / 0xF00080
//        by -1 before the feedback, so op206's own param1 and the "cannot cast multiple instances" strings never showed

bool InstallImmunityMessages()
{
    const Word site = Const("IEX.fix.checkAddSite") ? EngineImageBase() + Const("IEX.fix.checkAddSite") : 0;
    const Word fn = Sym("_ZN11CGameEffect8CheckAddEP11CGameSpriteRhS2_S2_S2_S2_S2_S2_");
    if (!site || !fn || site < fn || site > fn + 0x1400)
        return false;
    // Linux: mov dword ptr [rax + 8], -1  ->  7-byte nop (the entry keeps its string)
    static const std::uint8_t lin[] = {0xC7, 0x40, 0x08, 0xFF, 0xFF, 0xFF, 0xFF};
    static const std::uint8_t linFix[] = {0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00};
    // Windows: cmp [r12+8], 0xF00074; mov eax, 0xF00073; cmove ebx, eax; mov [r12+8], ebx   (ebx = -1)
    //      ->  cmp [r12+8], 0xF00074; jne +9; mov dword ptr [r12+8], 0xF00073; 2-byte nop
    static const std::uint8_t win[] = {0x41, 0x81, 0x7C, 0x24, 0x08, 0x74, 0x00, 0xF0, 0x00, 0xB8, 0x73,
                                       0x00, 0xF0, 0x00, 0x0F, 0x44, 0xD8, 0x41, 0x89, 0x5C, 0x24, 0x08};
    static const std::uint8_t winFix[] = {0x41, 0x81, 0x7C, 0x24, 0x08, 0x74, 0x00, 0xF0, 0x00, 0x75, 0x09,
                                          0x41, 0xC7, 0x44, 0x24, 0x08, 0x73, 0x00, 0xF0, 0x00, 0x66, 0x90};
    static_assert(sizeof(win) == sizeof(winFix), "same length");
    if (Matches(site, lin, sizeof(lin)))
        return Patch(site, linFix, sizeof(linFix));
    if (Matches(site, win, sizeof(win)))
        return Patch(site, winFix, sizeof(winFix));
    return false;
}

// --- 8. HP tables: the MODIFIER column was added only when ROLLS is 0 (1d6+2 rolled 1d6) ---

constexpr const char* kRollTable = "_ZNK11CRuleTables13RollHitPointsERK8C2DArrayhhiiiiii";
constexpr const char* kRollClass = "_ZNK11CRuleTables13RollHitPointsEhhR13CDerivedStatsS1_iii";
using RollTableFn = int (*)(Word, Word, std::uint8_t, std::uint8_t, int, int, int, int, int, int);
using StringCtor = void (*)(Word*, const char*);
using StringDtor = void (*)(Word*);
using GetAtFn = Word (*)(Word, const Word*, const Word*);
RollTableFn g_rollTable = nullptr;
StringCtor g_stringCtor = nullptr;
StringDtor g_stringDtor = nullptr;
GetAtFn g_getAt = nullptr;

int TableInt(Word table, const char* column, int row)
{
    char rowName[16];
    std::snprintf(rowName, sizeof(rowName), "%d", row);
    Word col = 0, rowString = 0;
    g_stringCtor(&col, column);
    g_stringCtor(&rowString, rowName);
    const Word cell = g_getAt(table, &col, &rowString);
    const char* text = cell ? Read<const char*>(cell) : nullptr;
    const int value = text ? std::atoi(text) : 0;
    g_stringDtor(&rowString);
    g_stringDtor(&col);
    return value;
}

// Levels from+1..to of the class HP table, one level at a time through the engine's own roll (dice, maximum-HP
// option, minimum roll). A level with dice gets its MODIFIER (or the caller's override) before the per-class divisor,
// as a level without dice already did.
int FixRollTable(Word rules, Word table, std::uint8_t from, std::uint8_t to, int minRoll, int divisor,
                 int sidesOverride, int sides, int modifierOverride, int modifier)
{
    int total = 0;
    for (int level = from + 1; level <= to; ++level) {
        const auto prev = static_cast<std::uint8_t>(level - 1), cur = static_cast<std::uint8_t>(level);
        if (TableInt(table, "ROLLS", level) == 0 || divisor == 0) {
            total += g_rollTable(rules, table, prev, cur, minRoll, divisor, sidesOverride, sides, modifierOverride, modifier);
            continue;
        }
        const int dice = g_rollTable(rules, table, prev, cur, minRoll, 1, sidesOverride, sides, modifierOverride, modifier);
        const int bonus = modifierOverride ? modifier : TableInt(table, "MODIFIER", level);
        const int hp = (dice + bonus) / divisor;
        total += hp > 1 ? hp : 1;
        if (g_debug)
            Log("hp fix: level %d dice %d bonus %d divisor %d -> %d", level, dice, bonus, divisor, hp);
    }
    if (g_debug)
        Log("hp fix: levels %d..%d min %d div %d sOvr %d sides %d mOvr %d mod %d -> %d", from, to, minRoll, divisor,
            sidesOverride, sides, modifierOverride, modifier, total);
    return total;
}

bool InstallHitPointTables()
{
    const Word roll = Sym(kRollTable);
    const Word caller = Sym(kRollClass);
    g_stringCtor = reinterpret_cast<StringCtor>(Sym("_ZN7CStringC1EPKc"));
    g_stringDtor = reinterpret_cast<StringDtor>(Sym("_ZN7CStringD1Ev"));
    g_getAt = reinterpret_cast<GetAtFn>(Sym("_ZNK8C2DArray5GetAtERK7CStringS2_"));
    const Word site = roll && caller ? FindCall(caller, 0x300, roll) : 0;
    if (!site || !g_stringCtor || !g_stringDtor || !g_getAt)
        return false;
    g_rollTable = reinterpret_cast<RollTableFn>(roll);
    return HookCallSite(site, roll, reinterpret_cast<const void*>(&FixRollTable));
}

// --- 9. op236 param2 3 (Simulacrum): level drain from the active class's level only (dual-class: one class) ---

constexpr const char* kCopySelfApply = "_ZN19CGameEffectCopySelf11ApplyEffectEP11CGameSprite";
constexpr const char* kActiveInactive = "_ZNK13CAIObjectType24GetActiveInactiveClassesERhS0_";
Word g_activeInactive = 0;

// The drain's GetAverageLevel gets the creature's own class (average of LEVEL / LEVEL2 / LEVEL3 for dual- and
// multi-classes) instead of the active class.
void FixActiveInactive(Word aiType, std::uint8_t* active, std::uint8_t* inactive)
{
    reinterpret_cast<void (*)(Word, std::uint8_t*, std::uint8_t*)>(g_activeInactive)(aiType, active, inactive);
    *active = Read<std::uint8_t>(aiType + 0xb);
}

bool InstallSimulacrum()
{
    const Word fn = Sym(kCopySelfApply);
    g_activeInactive = Sym(kActiveInactive);
    const Word site = fn && g_activeInactive ? FindCall(fn, 0x1400, g_activeInactive) : 0;
    return site && HookCallSite(site, g_activeInactive, reinterpret_cast<const void*>(&FixActiveInactive));
}

// --- 10. AddXPObject() with a negative value said "<name> gains -N experience" ---

constexpr const char* kExecuteAction = "_ZN11CGameAIBase13ExecuteActionEv";
constexpr const char* kSpriteFeedBack = "_ZN11CGameSprite8FeedBackEjiiijiRK7CString";
Word g_spriteFeedBack = 0, g_gameFeedBack = 0;

// Feedback 50 (personal XP) with a loss: the party feedback's "lost experience" message, as AddExperienceParty.
void FixXPFeedBack(Word sprite, std::uint32_t id, int value, int a, int b, std::uint32_t c, int d, Word text)
{
    const Word game = Game();
    if (id == 50 && value < 0 && game) {
        reinterpret_cast<void (*)(Word, std::uint16_t, int)>(g_gameFeedBack)(game, 2, value);
        return;
    }
    reinterpret_cast<void (*)(Word, std::uint32_t, int, int, int, std::uint32_t, int, Word)>(g_spriteFeedBack)(
        sprite, id, value, a, b, c, d, text);
}

bool InstallXPFeedBack()
{
    // The AddXPObject case of CGameAIBase::ExecuteAction: its one FeedBack call (description constant, checked).
    const Word fn = Sym(kExecuteAction);
    const Word rva = Const("IEX.fix.xpFeedbackSite");
    const Word site = rva ? EngineImageBase() + rva : 0;
    g_spriteFeedBack = Sym(kSpriteFeedBack);
    g_gameFeedBack = Sym("_ZN8CInfGame8FeedBackEti");
    if (!fn || !site || !g_spriteFeedBack || !g_gameFeedBack || site < fn || site > fn + 0x8000)
        return false;
    return HookCallSite(site, g_spriteFeedBack, reinterpret_cast<const void*>(&FixXPFeedBack));
}

// --- 11. op104 (AddXPObject, AddexperienceParty, ...) could take permanent XP below 0: it wrapped to ~4 billion ---

constexpr const char* kXPApply = "_ZN13CGameEffectXP11ApplyEffectEP11CGameSprite";
constexpr std::uint32_t kSpriteXP = 0x570;  // CGameSprite base stats XP (both builds)
Word g_xpApply = 0;

Word FixXPApply(Word effect, Word sprite)
{
    const int param1 = Read<std::int32_t>(effect + 0x1c);
    const int param2 = Read<std::int32_t>(effect + 0x20);
    const int timing = Read<std::int32_t>(effect + 0x24);
    const std::uint32_t xp = Read<std::uint32_t>(sprite + kSpriteXP);
    std::int64_t result = 0;
    bool clamp = false;
    if (timing == 1 && param1 < 0) {
        if (param2 == 0)
            result = static_cast<std::int64_t>(xp) + param1;
        clamp = param2 == 1 || param2 == 2 || result < 0;  // set / percentage with a negative value: 0
    }
    if (!clamp)
        return reinterpret_cast<Word (*)(Word, Word)>(g_xpApply)(effect, sprite);
    const std::int32_t safe = param2 == 0 ? -static_cast<std::int32_t>(xp) : 0;
    std::memcpy(reinterpret_cast<void*>(effect + 0x1c), &safe, 4);
    const Word r = reinterpret_cast<Word (*)(Word, Word)>(g_xpApply)(effect, sprite);
    std::memcpy(reinterpret_cast<void*>(effect + 0x1c), &param1, 4);
    return r;
}

bool InstallXPClamp()
{
    g_xpApply = Sym(kXPApply);
    const Word slot = Const("IEX.fix.slot.xpApply") ? EngineImageBase() + Const("IEX.fix.slot.xpApply") : 0;
    if (!g_xpApply || !slot || Read<Word>(slot) != g_xpApply)
        return false;
    const Word value = reinterpret_cast<Word>(&FixXPApply);
    return Patch(slot, &value, sizeof(value));
}

struct FixDesc {
    const char* name;
    bool (*install)();
};

const FixDesc kFixes[] = {
    {"op182EquippedItem", &InstallOp182},
    {"weaponSpeed", &InstallSwingSpeed},  // WSPECIAL SPEED column + launcher weapon speed
    {"splprotSigned", &InstallSplprot},
    {"trapLimit", &InstallTrapLimit},
    {"op33SaveVsDeath", &InstallSaveVsDeath},
    {"immunityMessages", &InstallImmunityMessages},
    {"hpTableModifier", &InstallHitPointTables},
    {"simulacrumLevelDrain", &InstallSimulacrum},
    {"negativeXPFeedback", &InstallXPFeedBack},
    {"xpFloor", &InstallXPClamp},
    {"eventTriggerObjects", &InstallEventTriggerObjects},  // beyond EEex: current EEex keeps the engine bug
};

} // namespace

void InstallEngineFixes()
{
    // Nothing to do at startup: Baldur.lua is not loaded yet. The fixes are installed by OpenLuaEngineFixes, when
    // the engine's Lua state is ready and before the engine runs any game code they change.
}

namespace {

void InstallFixesNow()
{
    const char* env = std::getenv("IEX_ENGINE_FIXES");
    const bool all = (env && *env) ? std::strcmp(env, "0") != 0 : IniInt("Engine Fixes", 1) != 0;
    g_debug = std::getenv("IEX_FIX_DEBUG") != nullptr;
    std::string on, off;
    for (const FixDesc& fix : kFixes) {
        FixState state{fix.name};
        const bool wanted = all && !OffByName(fix.name);
        state.installed = wanted && fix.install();
        g_fixes.push_back(state);
        std::string& list = state.installed ? on : off;
        list += (list.empty() ? "" : ", ") + std::string(fix.name) + (wanted || state.installed ? "" : " (off)");
    }
    Log("Engine fixes: on: %s; not installed: %s%s", on.empty() ? "none" : on.c_str(), off.empty() ? "none" : off.c_str(),
        all ? "" : (env && *env) ? " (IEX_ENGINE_FIXES=0)" : " (Baldur.lua IEX / Engine Fixes = 0)");
}

void PushFixes(lua_State* L)
{
    lua.createtable(L, 0, static_cast<int>(g_fixes.size()));
    for (const FixState& fix : g_fixes) {
        lua.pushboolean(L, fix.installed);
        lua.setfield(L, -2, fix.name);
    }
}

int LuaEngineFixes(lua_State* L)
{
    PushFixes(L);
    return 1;
}

} // namespace

void OpenLuaEngineFixes(lua_State* L)
{
    static bool installed = false;
    if (!installed) {
        installed = true;
        InstallFixesNow();
    }
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    PushFixes(L);
    lua.setfield(L, -2, "engineFixes");
    lua.settop(L, -2);
    lua.pushcclosure(L, LuaEngineFixes, 0);
    lua.setglobal(L, "IEX_EngineFixes");
}

} // namespace iex
