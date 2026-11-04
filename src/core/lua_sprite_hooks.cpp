// See lua_sprite_hooks.h. Engine evidence: IEX-data/engine/win/verified_ta.json (Damage, CheckQuickLists,
// IEX_Site_HitRoll). Hooks are call-site redirections: the original function is called through its address.
#include "lua_sprite_hooks.h"

#include "callsite_hook.h"
#include "effects.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstdint>
#include <cstring>
#include <string>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kCheckQuickLists = "_ZN11CGameSprite15CheckQuickListsER10CAbilityIdsii";
constexpr const char* kDamage = "_ZN11CGameSprite6DamageEP5CItemS1_iiRK13CAIObjectTypessPS_i";
constexpr const char* kRandInt = "_ZN5CUtil11UtilRandIntEll";
constexpr const char* kConcentrationFailed = "_ZN11CGameSprite19ConcentrationFailedEv";

// CAbilityId: resref at +6 (both builds).
constexpr std::size_t kAbilityRes = 0x6;
// Inert opcode for the stand-in damage effect of a blocked hit (decoded by effects.cpp as an effect that does
// nothing; instant, so it expires at once).
constexpr std::uint16_t kInertOpcode = 0xFFFF;

lua_State* g_L = nullptr;
Word g_checkQuickLists = 0, g_damage = 0, g_randInt = 0, g_concentrationFailed = 0;
// CONCENTR.2DA CHECK_MODE "EEex-LuaFunction=<name>": the Lua global that decides spell disruption (empty: engine).
std::string g_concentrationFunction;
int g_lastRoll = 0;

template <typename T>
T Read(Word address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

std::uint32_t FieldOffset(const char* type, const char* field)
{
    const TypeDesc* t = engineTypes.Get(type);
    std::uint32_t offset = 0;
    return t && t->Find(field, offset) ? offset : 0;
}

// Calls the Lua global `name` if it is a function; returns its first result's truth (errors are logged once
// per message by the Lua side, here only the call failure).
template <typename P>
bool CallLua(const char* name, P&& push)
{
    if (!g_L)
        return false;
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, name);
    if (lua.type(L, -1) != LUA_TFUNCTION) {
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

void PushSprite(lua_State* L, Word sprite) { PushObject(L, sprite, engineTypes.Get("CGameSprite")); }
void PushItem(lua_State* L, Word item) { PushObject(L, item, engineTypes.Get("CItem")); }

// --- Attack roll ---

Word HookHitRoll(Word range, Word bonus)
{
    const Word r = reinterpret_cast<Word (*)(Word, Word)>(g_randInt)(range, bonus);
    g_lastRoll = static_cast<std::int32_t>(r) + 1;
    return r;
}

// --- Concentration (CONCENTR.2DA CHECK_MODE EEex-LuaFunction=<name>: Tactics Remix, Tweaks Anthology) ---

// CGameSprite::ConcentrationFailed(): true when the damage the caster took since the last check disrupts its spell.
// With a Lua check, fn(sprite, damageData) decides: damageData = { damageTaken, targetSprite, sourceSprite,
// effect } as under EEex (sourceSprite and effect are nil here: IEX does not record which effect did the damage).
// A missing function or a Lua error leaves the engine's own check.
bool HookConcentrationFailed(Word sprite)
{
    const auto original = [&] { return reinterpret_cast<bool (*)(Word)>(g_concentrationFailed)(sprite); };
    if (g_concentrationFunction.empty() || !g_L || !sprite)
        return original();
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, g_concentrationFunction.c_str());
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return original();
    }
    static const std::uint32_t damageOffset = FieldOffset("CGameSprite", "m_nLastDamageTaken");
    PushSprite(L, sprite);
    lua.createtable(L, 0, 4);
    lua.pushinteger(L, damageOffset ? Read<std::int32_t>(sprite + damageOffset) : 0);
    lua.setfield(L, -2, "damageTaken");
    PushSprite(L, sprite);
    lua.setfield(L, -2, "targetSprite");
    if (lua.pcallk(L, 2, 1, 0, 0, nullptr) != 0) {
        const char* err = lua.tolstring(L, -1, nullptr);
        static int logged = 0;
        if (logged++ < 5)
            Log("Lua error in concentration check %s: %s", g_concentrationFunction.c_str(), err ? err : "(unknown)");
        lua.settop(L, top);
        return original();
    }
    const bool failed = lua.toboolean(L, -1) != 0;
    lua.settop(L, top);
    return failed;
}

// IEX_SetConcentrationCheck(name or nil): the Lua function CONCENTR.2DA names (read by EEex_Sprite.lua).
int LuaSetConcentrationCheck(lua_State* L)
{
    const char* name = lua.type(L, 1) == LUA_TSTRING ? lua.tolstring(L, 1, nullptr) : nullptr;
    g_concentrationFunction = name ? name : "";
    lua.pushboolean(L, g_concentrationFailed != 0);
    return 1;
}

// --- Quick lists ---

void HookCheckQuickLists(Word sprite, Word ability, Word change, Word a3, Word a4)
{
    reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(g_checkQuickLists)(sprite, ability, change, a3, a4);
    if (!sprite || !ability)
        return;
    char res[9] = {};
    std::memcpy(res, reinterpret_cast<const void*>(ability + kAbilityRes), 8);
    CallLua("IEX_TA_QuickListsChecked", [&](lua_State* L) {
        PushSprite(L, sprite);
        lua.pushstring(L, res);
        lua.pushinteger(L, static_cast<std::int16_t>(change));
        return 3;
    });
    // Third int argument non-zero: the ability is taken out of the quick slots whatever its count (the spell was
    // removed: forgotten, unlearned). CGameSprite::RemoveSpellFromQuickList has no caller in either build.
    if (static_cast<std::int32_t>(a3) != 0)
        CallLua("IEX_QuickListNotifyRemoved", [&](lua_State* L) {
            PushSprite(L, sprite);
            lua.pushstring(L, res);
            return 2;
        });
}

// --- Weapon hits ---

Word InertEffect(Word attacker, Word target)
{
    static const std::uint32_t pos = FieldOffset("CGameObject", "m_pos");
    static const std::uint32_t id = FieldOffset("CGameObject", "m_id");
    std::uint8_t item[0x30] = {};
    std::memcpy(item, &kInertOpcode, 2);
    item[2] = 2;  // target: preset
    const Word sourceId = static_cast<Word>(static_cast<std::uint32_t>(Read<std::int32_t>(attacker + id)));
    const Word targetId = static_cast<Word>(static_cast<std::uint32_t>(Read<std::int32_t>(target + id)));
    return DecodeEffectAny(reinterpret_cast<Word>(item), attacker + pos, sourceId, target + pos, targetId);
}

Word HookDamage(Word attacker, Word weapon, Word launcher, Word ability, Word critical, Word targetType, Word s1,
                Word s2, Word target, Word leftHand)
{
    const auto damage = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word, Word, Word, Word, Word, Word)>(g_damage);
    const auto abilityIndex = static_cast<std::int32_t>(ability);
    if (target && CallLua("IEX_TA_BlockWeaponHit", [&](lua_State* L) {
            PushSprite(L, attacker);
            PushSprite(L, target);
            PushItem(L, weapon);
            PushItem(L, launcher);
            lua.pushinteger(L, abilityIndex);
            return 5;
        })) {
        const Word inert = InertEffect(attacker, target);
        if (inert)
            return inert;
    }
    const Word effect = damage(attacker, weapon, launcher, ability, critical, targetType, s1, s2, target, leftHand);
    if (effect && target)
        CallLua("IEX_TA_AlterBaseWeaponDamage", [&](lua_State* L) {
            PushSprite(L, attacker);
            PushSprite(L, target);
            PushObject(L, effect, engineTypes.Get("CGameEffect"));
            PushItem(L, weapon);
            PushItem(L, launcher);
            lua.pushinteger(L, abilityIndex);
            lua.pushboolean(L, static_cast<std::int32_t>(critical) != 0);
            lua.pushboolean(L, static_cast<std::int32_t>(leftHand) != 0);
            lua.pushinteger(L, g_lastRoll);
            return 9;
        });
    return effect;
}

int HookAll(const char* target, Word& original, const void* replacement)
{
    const std::uint32_t rva = engineTypes.Symbol(target);
    if (!rva)
        return 0;
    original = EngineImageBase() + rva;
    int n = 0;
    for (std::uint32_t site : engineTypes.CallSitesOf(target))
        n += HookCallSite(EngineImageBase() + site, original, replacement) ? 1 : 0;
    return n;
}

} // namespace

void NoteHitRoll(int roll)
{
    g_lastRoll = roll;
}

void OpenLuaSpriteHooks(lua_State* L)
{
    g_L = L;
    lua.pushcclosure(L, LuaSetConcentrationCheck, 0);
    lua.setglobal(L, "IEX_SetConcentrationCheck");
}

void InstallSpriteHooks()
{
    const int quick = HookAll(kCheckQuickLists, g_checkQuickLists, reinterpret_cast<const void*>(&HookCheckQuickLists));
    const int damage = HookAll(kDamage, g_damage, reinterpret_cast<const void*>(&HookDamage));
    bool roll = false;
    const std::uint32_t rollSite = engineTypes.Symbol("IEX_Site_HitRoll");
    const std::uint32_t randRva = engineTypes.Symbol(kRandInt);
    if (rollSite && randRva) {
        g_randInt = EngineImageBase() + randRva;
        roll = HookCallSite(EngineImageBase() + rollSite, g_randInt, reinterpret_cast<const void*>(&HookHitRoll));
    }
    const int concentration =
        HookAll(kConcentrationFailed, g_concentrationFailed, reinterpret_cast<const void*>(&HookConcentrationFailed));
    if (!concentration)
        g_concentrationFailed = 0;
    Log("Sprite listeners: %d CheckQuickLists call sites, %d Damage call sites, attack roll %s, %d concentration "
        "check call sites", quick, damage, roll ? "hooked" : "NOT hooked", concentration);
}

} // namespace iex
