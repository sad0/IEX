// EEex-compatible effects and script extensions (behavior from the public EEex docs and from how mods call them).
//
// Hooks (addresses: docs and IEX-data/engine/win/verified_opc.json):
//   - every call of CGameSprite::ProcessEffectList (+ Linux tail jumps): after it returns, if the effect lists
//     were re-evaluated during the call, dispatch "OpcodeListsResolved" with the sprite;
//   - the CDerivedStats::operator= call inside ProcessEffectList that starts a re-evaluation: marks the sprite
//     and resets its extended stats to their defaults (opcode 401 effects then apply on top);
//   - inert effects' ApplyEffect slot: opcode 401 (extended stat), 402 (call the Lua global named by the resref);
//   - CGameSprite vtable AddEffect: opcode 403 screening (each 403 effect on the sprite gets
//     FN(op403, incoming, sprite); true blocks the incoming effect);
//   - EvaluateStatusTrigger vtable slots (sprite + other script objects): EEex_LuaTrigger, EEex_IsImmuneToOpcode;
//   - CGameAIBase::ExecuteAction (sprite default call + other objects' vtable slots): EEex_LuaAction.
#include "opcodes.h"

#include "callsite_hook.h"
#include "effects.h"
#include "engine_types.h"
#include "events.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"
#include "platform_memory.h"

#include <cctype>
#include <climits>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

lua_State* g_L = nullptr;

// Script ids (ACTION.IDS / TRIGGER.IDS numbers EEex-built mods compile with).
constexpr std::uint16_t kActionLuaAction = 472;
constexpr std::uint16_t kTriggerLuaTrigger = 0x410E;
constexpr std::uint16_t kTriggerIsImmuneToOpcode = 0x410F;
constexpr std::int16_t kActionDone = -1;

// CGameEffect fields: the saved effect record (EFF V2 layout, IESDP offsets) starts at +0 of the object on both
// builds, so these offsets are the EFF V2 file offsets.
constexpr std::size_t kEffTiming = 0x24, kEffDone = 0x114;  // m_done: past the record (both AddEffect copies)
constexpr std::size_t kEffOpcode = 0x10, kEffParam1 = 0x1c, kEffParam2 = 0x20, kEffRes = 0x30, kEffSave = 0x40,
                      kEffSpecial = 0x48, kEffSchool = 0x4c, kEffResist = 0x5c, kEffSourceType = 0x90,
                      kEffSourceRes = 0x94, kEffProjectile = 0xa0, kEffSecondary = 0xd0;
// CAITrigger (same on both builds, read from both EvaluateStatusTrigger copies): id +0, int1 +4, object +8,
// flags +0x20, string1 +0x30 (CString).
constexpr std::size_t kTrigInt1 = 0x4, kTrigObject = 0x8, kTrigString1 = 0x30;
// CAIAction: m_string1 +0x60 (types).
constexpr std::size_t kActString1 = 0x60;
constexpr std::uint8_t kObjectTypeSprite = 0x31;

template <typename T>
T Engine(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

template <typename T>
T Read(Word address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

void Put32(Word address, std::uint32_t v) { std::memcpy(reinterpret_cast<void*>(address), &v, 4); }

std::uint32_t FieldOffset(const char* type, const char* field)
{
    const TypeDesc* t = engineTypes.Get(type);
    std::uint32_t offset = 0;
    return t && t->Find(field, offset) ? offset : 0;
}

struct Offsets {
    std::uint32_t objectType = 0, id = 0, curAction = 0, tempStats = 0, timedList = 0, equipedList = 0;
    std::uint32_t listHead = 0, nodeNext = 0, nodeData = 0;
    bool ok = false;
} g_off;

bool LoadOffsets()
{
    g_off.objectType = FieldOffset("CGameObject", "m_objectType");
    g_off.id = FieldOffset("CGameObject", "m_id");
    g_off.curAction = FieldOffset("CGameAIBase", "m_curAction");
    g_off.tempStats = FieldOffset("CGameSprite", "m_tempStats");
    g_off.timedList = FieldOffset("CGameSprite", "m_timedEffectList");
    g_off.equipedList = FieldOffset("CGameSprite", "m_equipedEffectList");
    g_off.listHead = FieldOffset("CPtrList", "m_pNodeHead");
    g_off.nodeNext = 0;
    g_off.nodeData = 0x10;
    const TypeDesc* node = engineTypes.Get("CPtrList::CNode");
    std::uint32_t o = 0;
    if (node && node->Find("data", o))
        g_off.nodeData = o;
    g_off.ok = g_off.id && g_off.curAction && g_off.tempStats && g_off.timedList && g_off.equipedList && g_off.listHead;
    return g_off.ok;
}

bool IsSprite(Word object)
{
    return object && Read<std::uint8_t>(object + g_off.objectType) == kObjectTypeSprite;
}

std::int32_t ObjectId(Word object) { return Read<std::int32_t>(object + g_off.id); }

template <typename F>
void ForEachEffect(Word sprite, F&& fn)
{
    for (std::uint32_t listOffset : {g_off.timedList, g_off.equipedList}) {
        for (Word node = Read<Word>(sprite + listOffset + g_off.listHead); node; node = Read<Word>(node + g_off.nodeNext)) {
            const Word effect = Read<Word>(node + g_off.nodeData);
            if (effect && !fn(effect))
                return;
        }
    }
}

std::string ResRef(Word address)
{
    char buf[9] = {};
    std::memcpy(buf, reinterpret_cast<const void*>(address), 8);
    std::string s(buf);
    for (char& c : s)
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

const char* CStringText(Word address)
{
    const char* p = Read<const char*>(address);
    return p ? p : "";
}

const TypeDesc* TypeOf(Word object)
{
    static const TypeDesc* sprite = engineTypes.Get("CGameSprite");
    static const TypeDesc* aiBase = engineTypes.Get("CGameAIBase");
    return IsSprite(object) ? sprite : aiBase;
}

// Calls the Lua global `name` with values pushed by `push` (returns the count); returns the first result's
// truth. Errors are logged.
template <typename P>
bool CallLua(const char* name, P&& push)
{
    if (!g_L)
        return false;
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, name);
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        static std::unordered_set<std::string> reported;
        if (reported.insert(name).second)
            Log("Opcode callback: Lua function %s not defined", name);
        lua.settop(L, top);
        return false;
    }
    const int nargs = push(L);
    bool result = false;
    if (lua.pcallk(L, nargs, 1, 0, 0, nullptr) == 0) {
        result = lua.toboolean(L, -1) != 0;
    } else {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("Lua error in %s: %s", name, err ? err : "(unknown)");
    }
    lua.settop(L, top);
    return result;
}

// --- Extended stats (opcode 401) ---

struct StatDef {
    std::int32_t min = INT_MIN, max = INT_MAX, def = 0;
};
constexpr int kFirstExtendedStat = 203;
std::vector<StatDef> g_statDefs;                                       // index: id - 203
std::unordered_map<std::int32_t, std::vector<std::int32_t>> g_stats;  // sprite id -> current values
std::unordered_map<std::int32_t, std::vector<std::int32_t>> g_base;   // sprite id -> permanent (timing 1) values

std::FILE* OpenOverride(const char* upper, const char* lower)
{
    for (const char* name : {upper, lower}) {
        const std::string path = std::string("override/") + name;
        if (std::FILE* f = std::fopen(path.c_str(), "rb"))
            return f;
    }
    return nullptr;
}

std::vector<std::vector<std::string>> ReadTokens(std::FILE* f)
{
    std::vector<std::vector<std::string>> lines;
    std::string text;
    char buf[4096];
    std::size_t n;
    while ((n = std::fread(buf, 1, sizeof(buf), f)) > 0)
        text.append(buf, n);
    std::fclose(f);
    std::vector<std::string> cur;
    std::string tok;
    for (char c : text + "\n") {
        if (c == '\n' || c == '\r') {
            if (!tok.empty())
                cur.push_back(tok), tok.clear();
            if (!cur.empty())
                lines.push_back(cur), cur.clear();
        } else if (c == ' ' || c == '\t') {
            if (!tok.empty())
                cur.push_back(tok), tok.clear();
        } else {
            tok += c;
        }
    }
    return lines;
}

std::string Upper(std::string s)
{
    for (char& c : s)
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

void LoadExtendedStats()
{
    g_statDefs.clear();
    std::FILE* ids = OpenOverride("STATS.IDS", "stats.ids");
    std::FILE* table = OpenOverride("X-STATS.2DA", "x-stats.2da");
    if (!ids || !table) {
        if (ids)
            std::fclose(ids);
        if (table)
            std::fclose(table);
        Log("Extended stats: no override STATS.IDS / X-STATS.2DA, none defined");
        return;
    }
    std::unordered_map<std::string, int> idOf;
    for (const auto& line : ReadTokens(ids)) {
        if (line.size() < 2)
            continue;
        char* end = nullptr;
        const long id = std::strtol(line[0].c_str(), &end, 0);
        if (end && *end == 0 && id >= kFirstExtendedStat && id < kFirstExtendedStat + 0x10000)
            idOf[Upper(line[1])] = static_cast<int>(id);
    }
    int defined = 0;
    const auto lines = ReadTokens(table);
    for (std::size_t i = 3; i < lines.size(); ++i) {  // 2DA V1.0 / default / column names
        const auto& row = lines[i];
        if (row.size() < 4)
            continue;
        auto it = idOf.find(Upper(row[0]));
        if (it == idOf.end())
            continue;
        const std::size_t index = static_cast<std::size_t>(it->second - kFirstExtendedStat);
        if (g_statDefs.size() <= index)
            g_statDefs.resize(index + 1);
        StatDef& d = g_statDefs[index];
        d.min = static_cast<std::int32_t>(std::strtol(row[1].c_str(), nullptr, 0));
        d.max = static_cast<std::int32_t>(std::strtol(row[2].c_str(), nullptr, 0));
        d.def = static_cast<std::int32_t>(std::strtol(row[3].c_str(), nullptr, 0));
        ++defined;
    }
    Log("Extended stats: %d defined (ids %d..%d)", defined, kFirstExtendedStat,
        kFirstExtendedStat + static_cast<int>(g_statDefs.size()) - 1);
}

void ResetExtendedStats(Word sprite)
{
    if (g_statDefs.empty())
        return;
    const std::int32_t id = ObjectId(sprite);
    auto& values = g_stats[id];
    values.resize(g_statDefs.size());
    auto it = g_base.find(id);
    for (std::size_t i = 0; i < g_statDefs.size(); ++i)
        values[i] = it != g_base.end() && i < it->second.size() ? it->second[i] : g_statDefs[i].def;
}

std::vector<std::int32_t>& Values(std::unordered_map<std::int32_t, std::vector<std::int32_t>>& table, std::int32_t id)
{
    auto& values = table[id];
    if (values.size() != g_statDefs.size()) {
        const std::size_t old = values.size();
        values.resize(g_statDefs.size());
        for (std::size_t i = old; i < values.size(); ++i)
            values[i] = g_statDefs[i].def;
    }
    return values;
}

bool ExtendedStat(std::int32_t spriteId, int stat, std::int32_t& value)
{
    if (stat < kFirstExtendedStat || static_cast<std::size_t>(stat - kFirstExtendedStat) >= g_statDefs.size())
        return false;
    const std::size_t index = static_cast<std::size_t>(stat - kFirstExtendedStat);
    auto it = g_stats.find(spriteId);
    value = it != g_stats.end() && index < it->second.size() ? it->second[index] : g_statDefs[index].def;
    return true;
}

void Modify(std::vector<std::int32_t>& values, std::size_t index, Word effect)
{
    const std::int64_t amount = Read<std::int32_t>(effect + kEffParam1);
    std::int64_t v = values[index];
    switch (Read<std::uint32_t>(effect + kEffParam2)) {
    case 0: v += amount; break;
    case 1: v = amount; break;
    case 2: v = v * amount / 100; break;
    default: return;
    }
    const StatDef& d = g_statDefs[index];
    if (v < d.min)
        v = d.min;
    if (v > d.max)
        v = d.max;
    values[index] = static_cast<std::int32_t>(v);
}

// Timing 1 (permanent) changes the creature's permanent value too (kept until the game is closed).
void ApplyExtendedStat(Word effect, Word sprite, bool permanent)
{
    const std::int32_t stat = Read<std::int32_t>(effect + kEffSpecial);
    if (stat < kFirstExtendedStat || static_cast<std::size_t>(stat - kFirstExtendedStat) >= g_statDefs.size())
        return;
    const std::size_t index = static_cast<std::size_t>(stat - kFirstExtendedStat);
    const std::int32_t id = ObjectId(sprite);
    if (permanent)
        Modify(Values(g_base, id), index, effect);
    Modify(Values(g_stats, id), index, effect);
}

// --- Inert effects' ApplyEffect (opcodes the engine does not know) ---

// --- Script levels (opcode 400, EEex_AIBase_SetScriptLevelResRef) ---

// CGameAIBase script slot of each SCRLEV.IDS level (CGameAIBase::SetScript switch: 0 override, 1 area, 2 specifics,
// 4 class, 5 race, 6 general, 7 default; 3 has no slot of its own here).
constexpr const char* kScriptFields[8] = {"m_overrideScript", "m_areaScript", "m_specificsScript", nullptr,
                                          "m_classScript", "m_raceScript", "m_generalScript", "m_defaultScript"};
constexpr const char* kScriptCtor = "_ZN9CAIScriptC1E7CResRefi";  // CAIScript(CResRef name, int playerScript)
constexpr std::size_t kScriptSize = 0x40;
std::uint64_t g_setScriptSlot = 0;  // CGameAIBase vtable: SetScript(short level, CAIScript*)

std::string ScriptLevelResRef(Word aiBase, int level)
{
    if (level < 0 || level > 7 || !kScriptFields[level])
        return std::string();
    const std::uint32_t offset = FieldOffset("CGameAIBase", kScriptFields[level]);
    const Word script = offset ? Read<Word>(aiBase + offset) : 0;
    return script ? ResRef(script) : std::string();
}

// Gives level `level` of the script object a new script `resref` (empty: an empty script, the slot runs nothing;
// the engine's SetScript needs a script object). The engine deletes the previous one.
bool SetScriptLevel(Word aiBase, int level, const std::string& resref, bool playerScript)
{
    const auto ctor = Engine<void (*)(Word, std::uint64_t, int)>(kScriptCtor);
    const auto alloc = Engine<void* (*)(std::size_t)>("SDL_malloc");
    if (!aiBase || !ctor || !alloc || !g_setScriptSlot || level < 0 || level > 7)
        return false;
    const Word script = reinterpret_cast<Word>(alloc(kScriptSize));
    if (!script)
        return false;
    std::uint64_t name = 0;  // CResRef: 8 chars, zero padded, passed by value in one register on both ABIs
    std::memcpy(&name, resref.data(), resref.size() < 8 ? resref.size() : 8);
    ctor(script, name, playerScript ? 1 : 0);
    const Word vtable = Read<Word>(aiBase);
    reinterpret_cast<void (*)(Word, Word, Word)>(Read<Word>(vtable + g_setScriptSlot))(
        aiBase, static_cast<Word>(static_cast<std::uint16_t>(level)), script);
    return true;
}

// Opcode 400 (Set Temporary AI Script): like opcode 82, but the script the level had is put back when the effect
// ends. The previous resref is kept in the effect itself (m_res3; m_effectAmount5 = kOp400Applied once applied), so
// it survives a save and reload.
constexpr std::size_t kEffAmount5 = 0x6c, kEffRes3 = 0x78;
constexpr std::uint32_t kOp400Applied = 0x49455834;  // 'IEX4'

void ApplyTemporaryScript(Word effect, Word sprite)
{
    if (Read<std::uint32_t>(effect + kEffAmount5) == kOp400Applied)
        return;
    const int level = static_cast<std::int16_t>(Read<std::uint32_t>(effect + kEffParam2));
    const std::string previous = ScriptLevelResRef(sprite, level);
    char saved[8] = {};
    std::memcpy(saved, previous.data(), previous.size() < 8 ? previous.size() : 8);
    std::memcpy(reinterpret_cast<void*>(effect + kEffRes3), saved, 8);
    Put32(effect + kEffAmount5, kOp400Applied);
    SetScriptLevel(sprite, level, ResRef(effect + kEffRes), false);
}

Word g_baseOnRemove = 0;
std::uint64_t g_onRemoveSlot = 0;

Word InertOnRemove(Word effect, Word sprite)
{
    if (effect && sprite && Read<std::uint32_t>(effect + kEffOpcode) == 400 &&
        Read<std::uint32_t>(effect + kEffAmount5) == kOp400Applied) {
        Put32(effect + kEffAmount5, 0);
        const int level = static_cast<std::int16_t>(Read<std::uint32_t>(effect + kEffParam2));
        SetScriptLevel(sprite, level, ResRef(effect + kEffRes3), false);
    }
    return g_baseOnRemove ? reinterpret_cast<Word (*)(Word, Word)>(g_baseOnRemove)(effect, sprite) : 0;
}

Word InertApplyEffect(Word effect, Word sprite)
{
    if (!effect || !sprite)
        return 1;
    // Timing 1 (permanent): applied once, then the engine drops the effect (m_done).
    const bool permanent = Read<std::uint32_t>(effect + kEffTiming) == 1;
    const std::uint32_t opcode = Read<std::uint32_t>(effect + kEffOpcode);
    if (permanent && (opcode == 401 || opcode == 402))
        Put32(effect + kEffDone, 1);
    switch (opcode) {
    case 400:
        if (IsSprite(sprite))
            ApplyTemporaryScript(effect, sprite);
        break;
    case 401:
        ApplyExtendedStat(effect, sprite, permanent);
        break;
    case 402: {
        const std::string fn = ResRef(effect + kEffRes);
        if (!fn.empty())
            CallLua(fn.c_str(), [&](lua_State* L) {
                PushObject(L, effect, engineTypes.Get("CGameEffect"));
                PushObject(L, sprite, engineTypes.Get("CGameSprite"));
                return 2;
            });
        break;
    }
    default:
        break;
    }
    return 1;
}

// --- Effect lists resolved ---

constexpr const char* kProcessEffectList = "_ZN11CGameSprite17ProcessEffectListEi";
constexpr const char* kStatsCopy = "_ZN13CDerivedStatsaSERKS_";
std::unordered_set<Word> g_reevaluated;  // sprites whose lists were re-evaluated in the current call
std::unordered_set<Word> g_dispatching;  // sprites whose listeners are running (no re-entry)

Word HookStatsCopy(Word dst, Word src)
{
    const Word result = Engine<Word (*)(Word, Word)>(kStatsCopy)(dst, src);
    const Word sprite = dst - g_off.tempStats;
    g_reevaluated.insert(sprite);
    ResetExtendedStats(sprite);
    return result;
}

Word HookProcessEffectList(Word sprite, Word arg)
{
    const Word result = Engine<Word (*)(Word, Word)>(kProcessEffectList)(sprite, arg);
    if (g_reevaluated.erase(sprite) && !g_dispatching.count(sprite)) {
        g_dispatching.insert(sprite);
        DispatchObjectEvent("OpcodeListsResolved", sprite, engineTypes.Get("CGameSprite"));
        g_dispatching.erase(sprite);
    }
    return result;
}

// Linux tail jumps (E9) to ProcessEffectList are hooked with HookJumpSite (callsite_hook.h).

// --- vtable slots ---

// Replaces the function pointer in the vtable slot named `slotName` (description symbol = slot address).
// Returns the previous pointer (0 if not done).
Word HookSlot(const char* slotName, const void* replacement)
{
    const std::uint32_t rva = engineTypes.Symbol(slotName);
    if (!rva)
        return 0;
    const Word slot = EngineImageBase() + rva;
    const Word original = Read<Word>(slot);
    if (!original)
        return 0;
    const Word value = reinterpret_cast<Word>(replacement);
    return platform::PatchCode(reinterpret_cast<void*>(slot), &value, sizeof(value)) ? original : 0;
}

// Hooks the numbered slots `prefix_0`.. that all hold the same function; returns it.
Word HookSlotFamily(const char* prefix, const void* replacement, int& count)
{
    Word original = 0;
    count = 0;
    for (int i = 0; i < 16; ++i) {
        const std::string name = std::string(prefix) + "_" + std::to_string(i);
        const std::uint32_t rva = engineTypes.Symbol(name);
        if (!rva)
            continue;
        const Word current = Read<Word>(EngineImageBase() + rva);
        if (original && current != original) {
            Log("%s holds 0x%llx, not the family's function, skipped", name.c_str(),
                static_cast<unsigned long long>(current - EngineImageBase()));
            continue;
        }
        const Word previous = HookSlot(name.c_str(), replacement);
        if (previous) {
            original = previous;
            ++count;
        }
    }
    return original;
}

// --- Opcode 403 (screen incoming effects) ---

Word g_spriteAddEffect = 0;
int g_deleteSlot = 0;  // byte offset of the deleting destructor in effect vtables

void DeleteEffect(Word effect)
{
    const Word vtable = Read<Word>(effect);
    reinterpret_cast<void (*)(Word, Word)>(Read<Word>(vtable + g_deleteSlot))(effect, 1);
}

void HookSpriteAddEffect(Word sprite, Word effect, Word list, Word noSave, Word immediate)
{
    if (effect && g_L) {
        std::vector<Word> screens;
        ForEachEffect(sprite, [&](Word e) {
            if (Read<std::uint32_t>(e + kEffOpcode) == 403)
                screens.push_back(e);
            return true;
        });
        for (Word screen : screens) {
            const std::string fn = ResRef(screen + kEffRes);
            if (fn.empty())
                continue;
            const bool block = CallLua(fn.c_str(), [&](lua_State* L) {
                PushObject(L, screen, engineTypes.Get("CGameEffect"));
                PushObject(L, effect, engineTypes.Get("CGameEffect"));
                PushObject(L, sprite, engineTypes.Get("CGameSprite"));
                return 3;
            });
            if (block) {
                DeleteEffect(effect);
                return;
            }
        }
    }
    reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(g_spriteAddEffect)(sprite, effect, list, noSave, immediate);
}

// --- Triggers ---

Word g_spriteEvalTrigger = 0;
Word g_baseEvalTrigger = 0;

bool IsMyself(Word objectType)
{
    // CAIObjectType: EA/General/Race/Class +8..+0xb, Instance +0xc, SpecialCase[5] +0x10, Specifics/Gender/Align
    // +0x15..+0x17. "Myself" = object function 1 alone.
    const auto* p = reinterpret_cast<const std::uint8_t*>(objectType);
    if (p[0x10] != 1 || p[0x11] || p[0x12] || p[0x13] || p[0x14])
        return false;
    for (int i = 0x8; i <= 0xb; ++i)
        if (p[i])
            return false;
    return p[0x15] == 0 && p[0x16] == 0 && p[0x17] == 0;
}

bool ImmuneToOpcode(Word sprite, std::uint32_t opcode)
{
    bool immune = false;
    ForEachEffect(sprite, [&](Word e) {
        if (Read<std::uint32_t>(e + kEffOpcode) == 101 && Read<std::uint32_t>(e + kEffParam2) == opcode)
            immune = true;
        return !immune;
    });
    return immune;
}

// Returns true and sets `result` when the trigger is one of ours.
bool EvaluateOurTrigger(Word self, Word trigger, Word& result)
{
    const auto id = Read<std::uint16_t>(trigger);
    if (id == kTriggerLuaTrigger) {
        const char* chunk = CStringText(trigger + kTrigString1);
        result = CallLua("IEX_Opcode_LuaTrigger", [&](lua_State* L) {
            lua.pushstring(L, chunk);
            PushObject(L, self, TypeOf(self));
            return 2;
        }) ? 1 : 0;
        return true;
    }
    if (id == kTriggerIsImmuneToOpcode) {
        const Word target = IsMyself(trigger + kTrigObject) ? self : 0;
        result = target && IsSprite(target) &&
                 ImmuneToOpcode(target, static_cast<std::uint32_t>(Read<std::int32_t>(trigger + kTrigInt1))) ? 1 : 0;
        return true;
    }
    return false;
}

Word HookSpriteEvalTrigger(Word self, Word trigger)
{
    Word result = 0;
    if (EvaluateOurTrigger(self, trigger, result))
        return result;
    return reinterpret_cast<Word (*)(Word, Word)>(g_spriteEvalTrigger)(self, trigger);
}

Word HookBaseEvalTrigger(Word self, Word trigger)
{
    Word result = 0;
    if (EvaluateOurTrigger(self, trigger, result))
        return result;
    return reinterpret_cast<Word (*)(Word, Word)>(g_baseEvalTrigger)(self, trigger);
}

// --- Actions ---

constexpr const char* kBaseExecuteAction = "_ZN11CGameAIBase13ExecuteActionEv";
Word g_baseExecuteAction = 0;

Word HookBaseExecuteAction(Word self)
{
    const Word action = self + g_off.curAction;
    if (Read<std::uint16_t>(action) == kActionLuaAction) {
        const char* chunk = CStringText(action + kActString1);
        CallLua("IEX_Opcode_LuaAction", [&](lua_State* L) {
            lua.pushstring(L, chunk);
            PushObject(L, self, TypeOf(self));
            return 2;
        });
        return static_cast<Word>(static_cast<std::uint16_t>(kActionDone));
    }
    return reinterpret_cast<Word (*)(Word)>(g_baseExecuteAction)(self);
}

// --- Lua functions ---

lua_Integer FieldInt(lua_State* L, int t, const char* key, lua_Integer def)
{
    lua.getfield(L, t, key);
    lua_Integer v = def;
    const int type = lua.type(L, -1);
    if (type == LUA_TNUMBER)
        v = lua.tointegerx(L, -1, nullptr);
    else if (type == LUA_TBOOLEAN)
        v = lua.toboolean(L, -1);
    lua.settop(L, -2);
    return v;
}

bool FieldResRef(lua_State* L, int t, const char* key, char out[8])
{
    lua.getfield(L, t, key);
    bool found = false;
    if (lua.type(L, -1) == LUA_TSTRING) {
        const char* s = lua.tolstring(L, -1, nullptr);
        std::memset(out, 0, 8);
        for (int i = 0; i < 8 && s && s[i]; ++i)
            out[i] = static_cast<char>(std::toupper(static_cast<unsigned char>(s[i])));
        found = true;
    }
    lua.settop(L, -2);
    return found;
}

bool FieldPresent(lua_State* L, int t, const char* key)
{
    lua.getfield(L, t, key);
    const bool present = lua.type(L, -1) != LUA_TNIL;
    lua.settop(L, -2);
    return present;
}

template <typename T>
void Put(std::uint8_t* base, std::size_t offset, lua_Integer v)
{
    const T x = static_cast<T>(v);
    std::memcpy(base + offset, &x, sizeof(T));
}

// IEX_ApplyEffect(object, table): EEex_GameObject_ApplyEffect. Builds an item effect from the table, decodes it
// like the engine and adds it to the creature (timed list, resolved now).
int LuaApplyEffect(lua_State* L)
{
    const Word object = ToObjectAddress(L, 1);
    if (!object || lua.type(L, 2) != LUA_TTABLE)
        LuaError(L, "EEex_GameObject_ApplyEffect: object and table expected");
    if (!IsSprite(object))
        return 0;  // only creatures hold effect lists

    std::uint8_t item[0x30] = {};
    Put<std::uint16_t>(item, 0x0, FieldInt(L, 2, "effectID", 0));
    Put<std::uint8_t>(item, 0x2, FieldInt(L, 2, "targetType", 1));
    Put<std::uint8_t>(item, 0x3, FieldInt(L, 2, "spellLevel", 0));
    Put<std::int32_t>(item, 0x4, FieldInt(L, 2, "effectAmount", 0));
    Put<std::uint32_t>(item, 0x8, FieldInt(L, 2, "dwFlags", 0));
    Put<std::uint16_t>(item, 0xc, FieldInt(L, 2, "durationType", 0));
    Put<std::uint32_t>(item, 0xe, FieldInt(L, 2, "duration", 0));
    Put<std::uint8_t>(item, 0x12, FieldInt(L, 2, "probabilityUpper", 100));
    Put<std::uint8_t>(item, 0x13, FieldInt(L, 2, "probabilityLower", 0));
    char res[8];
    if (FieldResRef(L, 2, "res", res))
        std::memcpy(item + 0x14, res, 8);
    Put<std::int32_t>(item, 0x1c, FieldInt(L, 2, "numDice", 0));
    Put<std::int32_t>(item, 0x20, FieldInt(L, 2, "diceSize", 0));
    Put<std::uint32_t>(item, 0x24, FieldInt(L, 2, "noSave", 0) ? 0 : FieldInt(L, 2, "savingThrow", 0));
    Put<std::int32_t>(item, 0x28, FieldInt(L, 2, "saveMod", 0));
    Put<std::int32_t>(item, 0x2c, FieldInt(L, 2, "special", 0));

    const std::int32_t source[2] = {static_cast<std::int32_t>(FieldInt(L, 2, "sourceX", -1)),
                                    static_cast<std::int32_t>(FieldInt(L, 2, "sourceY", -1))};
    const std::int32_t target[2] = {static_cast<std::int32_t>(FieldInt(L, 2, "targetX", -1)),
                                    static_cast<std::int32_t>(FieldInt(L, 2, "targetY", -1))};
    const auto sourceId = static_cast<std::int32_t>(FieldInt(L, 2, "sourceID", -1));
    const auto sourceTarget = static_cast<std::int32_t>(FieldInt(L, 2, "sourceTarget", -1));

    const Word effect = DecodeEffectAny(reinterpret_cast<Word>(item), reinterpret_cast<Word>(source),
                                        static_cast<Word>(static_cast<std::uint32_t>(sourceId)),
                                        reinterpret_cast<Word>(target),
                                        static_cast<Word>(static_cast<std::uint32_t>(sourceTarget)));
    if (!effect)
        return 0;
    auto* e = reinterpret_cast<std::uint8_t*>(effect);
    if (FieldResRef(L, 2, "m_sourceRes", res))
        std::memcpy(e + kEffSourceRes, res, 8);
    if (FieldPresent(L, 2, "m_sourceType"))
        Put<std::uint32_t>(e, kEffSourceType, FieldInt(L, 2, "m_sourceType", 0));
    if (FieldPresent(L, 2, "m_school"))
        Put<std::uint32_t>(e, kEffSchool, FieldInt(L, 2, "m_school", 0));
    if (FieldPresent(L, 2, "m_secondaryType"))
        Put<std::uint32_t>(e, kEffSecondary, FieldInt(L, 2, "m_secondaryType", 0));
    if (FieldPresent(L, 2, "m_projectileType"))
        Put<std::uint32_t>(e, kEffProjectile, FieldInt(L, 2, "m_projectileType", 0));
    if (FieldPresent(L, 2, "m_flags"))
        Put<std::uint32_t>(e, kEffResist, FieldInt(L, 2, "m_flags", 0));
    if (FieldInt(L, 2, "noSave", 0))
        Put<std::uint32_t>(e, kEffSave, 0);

    // Through the (hooked) vtable, so opcode 403 screens apply: AddEffect(effect, timed list, 0, resolve now).
    static std::uint64_t addEffectSlot = 0;
    if (!addEffectSlot)
        engineTypes.Const("IEX.vt.AddEffect", addEffectSlot);
    const Word vtable = Read<Word>(object);
    reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(Read<Word>(vtable + addEffectSlot))(object, effect, 1, 0, 1);
    return 0;
}

// IEX_GetExtendedStat(sprite, id) -> value or nil (id not an extended stat).
int LuaGetExtendedStat(lua_State* L)
{
    const Word sprite = ToObjectAddress(L, 1);
    const auto stat = static_cast<int>(lua.tointegerx(L, 2, nullptr));
    std::int32_t value = 0;
    if (!sprite || !ExtendedStat(ObjectId(sprite), stat, value)) {
        lua.pushnil(L);
        return 1;
    }
    lua.pushinteger(L, value);
    return 1;
}

// IEX_IsImmuneToOpcode(sprite, opcode) -> bool (opcode 101 effect on the creature).
int LuaIsImmuneToOpcode(lua_State* L)
{
    const Word sprite = ToObjectAddress(L, 1);
    lua.pushboolean(L, sprite && IsSprite(sprite) &&
                           ImmuneToOpcode(sprite, static_cast<std::uint32_t>(lua.tointegerx(L, 2, nullptr))));
    return 1;
}

} // namespace

// IEX_GetScriptLevelResRef(aiBase, level) -> resref ('' when the level is empty).
int LuaGetScriptLevelResRef(lua_State* L)
{
    const Word object = ToObjectAddress(L, 1);
    const std::string res = object ? ScriptLevelResRef(object, static_cast<int>(lua.tointegerx(L, 2, nullptr))) : "";
    lua.pushstring(L, res.c_str());
    return 1;
}

// IEX_SetScriptLevelResRef(aiBase, level, resref [, playerScript]).
int LuaSetScriptLevelResRef(lua_State* L)
{
    const Word object = ToObjectAddress(L, 1);
    const char* res = lua.tolstring(L, 3, nullptr);
    if (!object)
        LuaError(L, "IEX_SetScriptLevelResRef: CGameAIBase expected");
    if (!SetScriptLevel(object, static_cast<int>(lua.tointegerx(L, 2, nullptr)), res ? res : "",
                        lua.toboolean(L, 4) != 0))
        LuaError(L, "IEX_SetScriptLevelResRef: not available for this game build");
    return 0;
}

void OpenLuaOpcodes(lua_State* L)
{
    lua.pushcclosure(L, LuaGetScriptLevelResRef, 0);
    lua.setglobal(L, "IEX_GetScriptLevelResRef");
    lua.pushcclosure(L, LuaSetScriptLevelResRef, 0);
    lua.setglobal(L, "IEX_SetScriptLevelResRef");
    g_L = L;
    lua.pushcclosure(L, LuaApplyEffect, 0);
    lua.setglobal(L, "IEX_ApplyEffect");
    lua.pushcclosure(L, LuaGetExtendedStat, 0);
    lua.setglobal(L, "IEX_GetExtendedStat");
    lua.pushcclosure(L, LuaIsImmuneToOpcode, 0);
    lua.setglobal(L, "IEX_IsImmuneToOpcode");
    LoadExtendedStats();
}

void InstallOpcodeHooks()
{
    if (!LoadOffsets()) {
        Log("Opcodes: engine description lacks object/sprite/list fields, hooks skipped");
        return;
    }
    const Word base = EngineImageBase();
    std::uint64_t deleteSlot = 0;
    engineTypes.Const("IEX.vt.EffectDelete", deleteSlot);
    g_deleteSlot = static_cast<int>(deleteSlot);

    // Inert effects: 401 / 402.
    std::uint64_t applySlot = 0;
    const bool inert = engineTypes.Const("CGameEffect.vtable.apply", applySlot) &&
                       SetInertSlot(static_cast<std::size_t>(applySlot), reinterpret_cast<const void*>(&InertApplyEffect));
    Log("Opcodes 401/402: %s", inert ? "on" : "inert vtable unavailable");
    // 400: the inert effects' OnRemove puts the previous script back (other opcodes: the base OnRemove).
    engineTypes.Const("CGameAIBase.vtable.setScript", g_setScriptSlot);
    const bool remove = inert && engineTypes.Const("CGameEffect.vtable.onRemove", g_onRemoveSlot) &&
                        (g_baseOnRemove = GetInertSlot(static_cast<std::size_t>(g_onRemoveSlot))) != 0 &&
                        SetInertSlot(static_cast<std::size_t>(g_onRemoveSlot), reinterpret_cast<const void*>(&InertOnRemove));
    Log("Opcode 400: %s", remove && g_setScriptSlot && engineTypes.Symbol(kScriptCtor) ? "on" : "off");

    // Lists resolved + extended stat reset.
    int pel = 0, jumps = 0;
    const std::uint32_t pelRva = engineTypes.Symbol(kProcessEffectList);
    for (std::uint32_t site : engineTypes.CallSitesOf(kProcessEffectList))
        pel += HookCallSite(base + site, base + pelRva, reinterpret_cast<const void*>(&HookProcessEffectList)) ? 1 : 0;
    for (int i = 0; i < 16; ++i) {
        const std::uint32_t site = engineTypes.Symbol("IEX_JmpSite_PEL_" + std::to_string(i));
        if (site && pelRva)
            jumps += HookJumpSite(base + site, base + pelRva, reinterpret_cast<const void*>(&HookProcessEffectList)) ? 1 : 0;
    }
    const std::uint32_t resetSite = engineTypes.Symbol("IEX_Site_PEL_StatsReset");
    const std::uint32_t copyRva = engineTypes.Symbol(kStatsCopy);
    const bool reset = resetSite && copyRva &&
                       HookCallSite(base + resetSite, base + copyRva, reinterpret_cast<const void*>(&HookStatsCopy));
    Log("Opcode lists resolved: %d ProcessEffectList call sites + %d jumps, re-evaluation point %s", pel, jumps,
        reset ? "hooked" : "NOT hooked");

    // 403.
    g_spriteAddEffect = HookSlot("IEX_VtSlot_SpriteAddEffect", reinterpret_cast<const void*>(&HookSpriteAddEffect));
    Log("Opcode 403 (sprite AddEffect): %s", g_spriteAddEffect ? "on" : "off");

    // Triggers.
    int baseTriggers = 0;
    g_spriteEvalTrigger = HookSlot("IEX_VtSlot_SpriteEvalTrigger", reinterpret_cast<const void*>(&HookSpriteEvalTrigger));
    g_baseEvalTrigger = HookSlotFamily("IEX_VtSlot_BaseEvalTrigger", reinterpret_cast<const void*>(&HookBaseEvalTrigger),
                                       baseTriggers);
    Log("EEex triggers: sprite %s, %d other script objects", g_spriteEvalTrigger ? "on" : "off", baseTriggers);

    // Actions.
    g_baseExecuteAction = engineTypes.Symbol(kBaseExecuteAction) ? base + engineTypes.Symbol(kBaseExecuteAction) : 0;
    const std::uint32_t execSite = engineTypes.Symbol("IEX_Site_SpriteExecBase");
    const bool spriteAction = g_baseExecuteAction && execSite &&
                              HookCallSite(base + execSite, g_baseExecuteAction,
                                           reinterpret_cast<const void*>(&HookBaseExecuteAction));
    int baseActions = 0;
    const Word family = HookSlotFamily("IEX_VtSlot_BaseExecuteAction",
                                       reinterpret_cast<const void*>(&HookBaseExecuteAction), baseActions);
    if (family && family != g_baseExecuteAction)
        Log("ExecuteAction slots hold 0x%llx, expected CGameAIBase::ExecuteAction",
            static_cast<unsigned long long>(family - base));
    Log("EEex actions: sprite %s, %d other script objects", spriteAction ? "on" : "off", baseActions);
}

} // namespace iex
