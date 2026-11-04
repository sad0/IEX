// See native_stick.h. Engine evidence (sites, registers, stack slots, both platforms):
// IEX-data/engine/win/verified_stick.json. Every hook is a call-site redirection (callsite_hook.h) or a
// register-context call-site hook (reg_hook.h); the engine's own call is always made.
//
// These are hook points of the registry (hook_points.h): installed at startup (the per-attack contexts chain onto
// the sprite hooks), active while a listener exists. Mods reach them through IEX_NativeHook_AddListener or, for
// EEex_Hook* requests (StickLuaFunctions), through the router (lua/IEX_HookRequests.lua).
#include "native_stick.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "hook_points.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"
#include "lua_sprite_hooks.h"
#include "platform_memory.h"
#include "reg_hook.h"

#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <string>

namespace iex {

namespace {

using Word = std::uintptr_t;

// Behaviours = hook points (hook_points.h).
using hp::Point;
constexpr Point kHide = hp::kHideInSight, kAttackIndex = hp::kAttackIndex, kAttackCancel = hp::kAttackCancel,
                kHitRoll = hp::kHitRoll, kHitMod = hp::kToHitTotal, kDamMod = hp::kDamageRoll,
                kCritMod = hp::kCritThreshold, kCritBlocked = hp::kCritBlocked, kCritMultiplier = hp::kCritMultiplier,
                kAttackResult = hp::kAttackResult, kButton = hp::kActionButtonL, kRButton = hp::kActionButtonR,
                kSaveDCSpell = hp::kCasterSchoolSpell, kSaveDCItem = hp::kCasterSchoolItem, kSaveMod = hp::kTargetSchool,
                kClassDone = hp::kClassDone, kProfMaxUI = hp::kProfMaxUI, kProfMax = hp::kProfMax;
constexpr Point kStickPoints[] = {kHide, kAttackIndex, kAttackCancel, kHitRoll, kHitMod, kDamMod, kCritMod,
                                  kCritBlocked, kCritMultiplier, kAttackResult, kButton, kRButton, kSaveDCSpell,
                                  kSaveDCItem, kSaveMod, kClassDone, kProfMaxUI, kProfMax};
std::uint32_t g_idOffset = 0x48;

template <typename T>
T Read(Word address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

template <typename T>
void Write(Word address, T value)
{
    std::memcpy(reinterpret_cast<void*>(address), &value, sizeof(T));
}

std::int64_t IdOf(Word object) { return object ? Read<std::int32_t>(object + g_idOffset) : -1; }

bool On(Point p) { return hp::Active(p); }

const TypeDesc* g_spriteType = nullptr;
const TypeDesc* g_effectType = nullptr;

void PushSprite(lua_State* L, Word sprite) { PushObject(L, sprite, g_spriteType); }

// Value point: (attacker, target, value) -> value. True when a listener gave a value (then in `v`).
bool FirePair(Point p, Word attacker, Word target, std::int64_t value, std::int64_t& v)
{
    return hp::FireValue(p, [&](lua_State* L) {
        PushSprite(L, attacker);
        PushSprite(L, target);
        lua.pushinteger(L, static_cast<lua_Integer>(value));
        return 3;
    }, v);
}

std::uint32_t Sym(const char* name) { return engineTypes.Symbol(name); }
Word Abs(std::uint32_t rva) { return rva ? EngineImageBase() + rva : 0; }

// --- Per-attack context (CGameSprite::Hit / CGameSprite::Damage call sites) ---

struct HitCtx {
    Word attacker, target;
    Word critRef;      // int& critical
    int roll = -1;     // d20 - 1 after the HitRoll callback
    bool mainPath = false;    // the normal to-hit path ran (GetCriticalValue reached)
    bool critBranch = false;  // the roll is a critical (before the helmet check)
};
thread_local HitCtx* g_hit = nullptr;

struct DamageCtx {
    Word attacker, target;
    int critical;
    bool multiplierSwapped = false;
    std::int16_t savedMultiplier = 0;
};
thread_local DamageCtx* g_damage = nullptr;

Word g_hitFn = 0, g_damageFn = 0, g_randFn = 0, g_critValueFn = 0, g_nearestFn = 0, g_lButtonFn = 0, g_rButtonFn = 0,
     g_classFn = 0;
Word g_critMultiplierGlobal = 0;
Word g_swingFn = 0, g_frameFn = 0;
std::int16_t g_attackNumOffset = 9;
std::int16_t g_attackDice = 20;
std::uint32_t g_locHitMod = 0, g_locDamMod = 0;
std::uint32_t g_locSaveSprite[3] = {}, g_locSaveEffect[3] = {};

// CGameSprite::Hit(this, target, item, ability, int& critical, left) -> hit (low byte).
Word HookHit(Word self, Word target, Word item, Word ability, Word critRef, Word left)
{
    HitCtx c{self, target, critRef};
    HitCtx* prev = g_hit;
    g_hit = &c;
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word, Word)>(g_hitFn)(self, target, item, ability,
                                                                                            critRef, left);
    g_hit = prev;
    if (On(kCritBlocked) && c.critBranch && critRef && Read<std::int32_t>(critRef) == 0)
        Write<std::int32_t>(critRef, 2);
    if (On(kAttackResult) && c.mainPath)
        hp::FireVoid(kAttackResult, [&](lua_State* L) {
            PushSprite(L, self);
            PushSprite(L, target);
            lua.pushinteger(L, static_cast<lua_Integer>(r & 0xFF));
            return 3;
        });
    return r;
}

// CGameSprite::Damage(this, weapon, launcher, ability, critical, targetType, s1, s2, target, left) -> effect.
Word HookDamage(Word self, Word weapon, Word launcher, Word ability, Word critical, Word type, Word s1, Word s2,
                Word target, Word left)
{
    DamageCtx c{self, target, static_cast<std::int32_t>(critical)};
    DamageCtx* prev = g_damage;
    g_damage = &c;
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word, Word, Word, Word, Word, Word)>(g_damageFn)(
        self, weapon, launcher, ability, critical, type, s1, s2, target, left);
    g_damage = prev;
    if (c.multiplierSwapped)
        platform::PatchCode(reinterpret_cast<void*>(g_critMultiplierGlobal), &c.savedMultiplier, 2);
    return r;
}

struct SwingCtx {
    Word attacker, target;
    bool armed = true;  // the swing's attack frame type is not read yet
};
thread_local SwingCtx* g_swing = nullptr;

// CGameSprite::Swing(this, target): one tick of a weapon attack.
Word HookSwing(Word self, Word target)
{
    SwingCtx c{self, target};
    SwingCtx* prev = g_swing;
    g_swing = &c;
    const Word r = reinterpret_cast<Word (*)(Word, Word)>(g_swingFn)(self, target);
    g_swing = prev;
    return r;
}

// CVidBitmap::GetPixelValue(x, y) of CGameAnimationType::GetAttackFrameType (win64: its tail jump; linux64: the
// copy Swing inlines, and the function's own tail jump): the attack frame type of the swing's current frame. The
// cancel callback can turn it into 6 (the engine's "no attack" frame); frames that lead to the attack-number code
// (all but 0, 6, 7, 8, 9, 15) report attack index = frame type - CGameSprite::ATTACK_NUM_OFFSET.
Word HookFrameType(Word bitmap, Word x, Word y)
{
    Word r = reinterpret_cast<Word (*)(Word, Word, Word)>(g_frameFn)(bitmap, x, y);
    SwingCtx* s = g_swing;
    if (!s || !s->armed)
        return r;
    s->armed = false;
    std::uint8_t ft = static_cast<std::uint8_t>(r);
    if (On(kAttackCancel)) {
        if (hp::FireBool(kAttackCancel, [&](lua_State* L) {
                PushSprite(L, s->attacker);
                PushSprite(L, s->target);
                return 2;
            }))
            ft = 6;
    }
    if (On(kAttackIndex) && ft != 0 && ft != 6 && ft != 7 && ft != 8 && ft != 9 && ft != 15)
        hp::FireVoid(kAttackIndex, [&](lua_State* L) {
            PushSprite(L, s->attacker);
            PushSprite(L, s->target);
            lua.pushinteger(L, static_cast<lua_Integer>(ft) - g_attackNumOffset);
            return 3;
        });
    return (r & ~static_cast<Word>(0xFF)) | ft;
}

// The d20 roll at the start of Hit: CUtil::UtilRandInt(20, 0).
Word HookHitRoll(Word range, Word bonus)
{
    Word r = reinterpret_cast<Word (*)(Word, Word)>(g_randFn)(range, bonus);
    if (HitCtx* h = g_hit) {
        if (On(kHitRoll)) {
            std::int64_t v = 0;
            if (FirePair(kHitRoll, h->attacker, h->target, static_cast<std::int16_t>(r), v)) {
                r = static_cast<Word>(v);
                NoteHitRoll(static_cast<int>(static_cast<std::int16_t>(r)) + 1);
            }
        }
        h->roll = static_cast<std::int16_t>(r);
    }
    return r;
}

// First CDerivedStats::GetCriticalValue(..., 0) of Hit: the critical-hit threshold.
Word HookCritValue(Word stats, Word left, Word itemType, Word abilityType, Word miss)
{
    Word v = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(g_critValueFn)(stats, left, itemType, abilityType,
                                                                                    miss);
    if (HitCtx* h = g_hit) {
        h->mainPath = true;
        if (On(kCritMod)) {
            std::int64_t r = 0;
            if (FirePair(kCritMod, h->attacker, h->target, static_cast<std::int32_t>(v), r))
                v = static_cast<Word>(r);
        }
        h->critBranch = h->roll >= 0 && h->roll + 1 >= g_attackDice - static_cast<std::int32_t>(v);
    }
    return v;
}

// Format(" +Right:%d ") in Hit: the to-hit total (right hand) is final up to there.
void RegHitMod(RegContext& ctx, const RegHookSite& site)
{
    ctx.rax = CallOriginal(ctx, site);
    HitCtx* h = g_hit;
    if (!h || !On(kHitMod))
        return;
    std::uint64_t* p = LocatePointer(ctx, g_locHitMod);
    if (!p)
        return;
    std::int64_t r = 0;
    if (FirePair(kHitMod, h->attacker, h->target, Read<std::int16_t>(reinterpret_cast<Word>(p)), r))
        Write<std::int16_t>(reinterpret_cast<Word>(p), static_cast<std::int16_t>(r));
}

// Format(" +DamageMod:%d ") in Damage: dice roll + damage bonus.
void RegDamMod(RegContext& ctx, const RegHookSite& site)
{
    ctx.rax = CallOriginal(ctx, site);
    DamageCtx* d = g_damage;
    if (!d || !On(kDamMod))
        return;
    std::uint64_t* p = LocatePointer(ctx, g_locDamMod);
    if (!p)
        return;
    std::int64_t r = 0;
    if (FirePair(kDamMod, d->attacker, d->target, Read<std::int16_t>(reinterpret_cast<Word>(p)), r))
        Write<std::int16_t>(reinterpret_cast<Word>(p), static_cast<std::int16_t>(r));
}

// The Format call right before Damage multiplies a critical hit by CGameSprite::CRITICAL_HIT_MULTIPLIER: the
// multiplier (minus 1 for a critical stopped by a helmet, flag 2) goes through the callback, and the engine reads
// the callback's value from the constant until Damage returns.
void RegCritMultiplier(RegContext& ctx, const RegHookSite& site)
{
    ctx.rax = CallOriginal(ctx, site);
    DamageCtx* d = g_damage;
    if (!d || d->critical == 0 || !On(kCritMultiplier) || !g_critMultiplierGlobal)
        return;
    const std::int16_t base = Read<std::int16_t>(g_critMultiplierGlobal);
    std::int64_t m = d->critical == 2 ? base - 1 : base;
    std::int64_t r = 0;
    if (!FirePair(kCritMultiplier, d->attacker, d->target, m, r))
        return;
    if (!d->multiplierSwapped) {
        d->savedMultiplier = base;
        d->multiplierSwapped = true;
    }
    const auto v = static_cast<std::int16_t>(r);
    platform::PatchCode(reinterpret_cast<void*>(g_critMultiplierGlobal), &v, 2);
}

// CGameArea::GetNearest(...) in CGameSprite::Hide: the nearest enemy that sees the hider (-1: none). Hiding in
// sight is allowed when the callback says so (the engine then takes its "nobody sees you" path); otherwise the
// engine's own rule applies (Shadowdancer kit only), which the callback also allows.
Word HookHideNearest(Word area, Word id, Word type, Word range, Word terrain, Word a5, Word a6, Word a7, Word a8,
                     Word a9)
{
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word, Word, Word, Word, Word, Word)>(g_nearestFn)(
        area, id, type, range, terrain, a5, a6, a7, a8, a9);
    if (static_cast<std::int32_t>(r) == -1 || !On(kHide))
        return r;
    if (hp::FireBool(kHide, [&](lua_State* L) {
            lua.pushinteger(L, static_cast<std::int32_t>(id));
            return 1;
        }))
        return static_cast<Word>(0xFFFFFFFFu);
    return r;
}

// CInfButtonArray::OnLButtonPressed(index) / OnRButtonPressed(index): the callback runs for a button index 0..12,
// before the engine's own checks (disabled button...).
Word HookLButton(Word self, Word index)
{
    if (static_cast<std::uint32_t>(index) <= 12 && On(kButton))
        hp::FireVoid(kButton, [&](lua_State* L) {
            lua.pushinteger(L, static_cast<std::int32_t>(index));
            return 1;
        });
    return reinterpret_cast<Word (*)(Word, Word)>(g_lButtonFn)(self, index);
}

Word HookRButton(Word self, Word index)
{
    if (static_cast<std::uint32_t>(index) <= 12 && On(kRButton))
        hp::FireVoid(kRButton, [&](lua_State* L) {
            lua.pushinteger(L, static_cast<std::int32_t>(index));
            return 1;
        });
    return reinterpret_cast<Word (*)(Word, Word)>(g_rButtonFn)(self, index);
}

// CRuleTables::MapCharacterSpecializationToSchool(spec) in CSpell / CItem::GetAbilityEffect (caster) and
// CGameEffect::CheckSave (target): the callback gives the school number instead (Stick: from all the sprite's kits).
void RegSchool(RegContext& ctx, const RegHookSite& site)
{
    ctx.rax = CallOriginal(ctx, site);
    const int which = static_cast<int>(reinterpret_cast<std::intptr_t>(site.user));
    const Point b = which == 0 ? kSaveDCSpell : which == 1 ? kSaveDCItem : kSaveMod;
    if (!On(b))
        return;
    std::uint64_t* sprite = LocatePointer(ctx, g_locSaveSprite[which]);
    std::uint64_t* effect = LocatePointer(ctx, g_locSaveEffect[which]);
    if (!sprite || !effect || !*sprite)
        return;
    std::int64_t r = 0;
    if (hp::FireValue(b, [&](lua_State* L) {
            PushSprite(L, static_cast<Word>(*sprite));
            PushObject(L, static_cast<Word>(*effect), g_effectType);
            lua.pushinteger(L, static_cast<lua_Integer>(static_cast<std::int64_t>(ctx.rax)));
            return 3;
        }, r))
        ctx.rax = static_cast<std::uint64_t>(r);
}

// CScreenCreateChar::CompleteCharacterClass(sprite) after the class step of OnDoneButtonClick.
Word HookClassDone(Word self, Word sprite)
{
    const Word r = reinterpret_cast<Word (*)(Word, Word)>(g_classFn)(self, sprite);
    if (On(kClassDone) && sprite)
        hp::FireVoid(kClassDone, [&](lua_State* L) {
            PushSprite(L, sprite);
            return 1;
        });
    return r;
}

// Proficiency maximum (character creation / level-up). UpdateProficienciesPanel fills one Lua table per proficiency
// (id, name, desc, value, max, min); its lua_setfield(L, -2, "max") call is redirected: the number on the stack top
// (the maximum shown) goes through the listeners first, with the table's id.
Word g_setFieldFn = 0, g_classProfFn = 0;

void HookProfMaxField(Word state, Word index, Word key)
{
    auto* L = reinterpret_cast<lua_State*>(state);
    if (On(kProfMaxUI) && L && L == hp::State()) {
        const lua_Number max = lua.tonumberx(L, -1, nullptr);
        lua.getfield(L, -2, "id");
        const lua_Integer id = lua.tointegerx(L, -1, nullptr);
        lua.settop(L, -2);
        std::int64_t v = 0;
        if (hp::FireValue(kProfMaxUI, [&](lua_State* S) {
                lua.pushinteger(S, id);
                lua.pushinteger(S, static_cast<lua_Integer>(max));
                return 2;
            }, v)) {
            lua.settop(L, -2);
            lua.pushnumber(L, static_cast<lua_Number>(static_cast<std::int32_t>(v)));
        }
    }
    reinterpret_cast<void (*)(Word, Word, Word)>(g_setFieldFn)(state, index, key);
}

// CRuleTables::GetClassProficiency(class, ..., flag, proficiency, kit) -> maximum, at its three calls in
// OnProficiencyPlusMinusButtonClick: the maximum a + click may reach goes through the listeners. (StickLuaFunctions'
// patch rewrites the final maximum once; the engine takes the larger of two of these results on one path, so a
// listener that never lowers a larger input gives the same limit.)
Word HookClassProficiency(Word rules, Word a, Word b, Word c, Word flag, Word prof, Word kit)
{
    Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word, Word, Word)>(g_classProfFn)(rules, a, b, c, flag,
                                                                                                prof, kit);
    if (On(kProfMax)) {
        std::int64_t v = 0;
        if (hp::FireValue(kProfMax, [&](lua_State* L) {
                lua.pushinteger(L, static_cast<std::int32_t>(prof));
                lua.pushinteger(L, static_cast<std::int16_t>(r));
                return 2;
            }, v))
            r = (r & ~static_cast<Word>(0xFFFF)) | static_cast<std::uint16_t>(v);
    }
    return r;
}

// --- Installation ---

// Hooks the call at `site` whatever it currently targets (the engine function or an earlier IEX hook, which then
// runs inside ours); `original` gets that target.
bool Chain(Word site, Word& original, const void* replacement)
{
    const Word target = CallTarget(site);
    if (!target)
        return false;
    original = target;
    return HookCallSite(site, target, replacement);
}

// Final target of an IEX call-site thunk (jmp qword ptr [rip+0] ; imm64), else `target` itself.
Word Resolve(Word target)
{
    const auto* b = reinterpret_cast<const std::uint8_t*>(target);
    if (b[0] == 0xFF && b[1] == 0x25 && b[2] == 0 && b[3] == 0 && b[4] == 0 && b[5] == 0)
        return Read<Word>(target + 6);
    return target;
}

// All call sites of `fn` (engine description callsite records); they must all lead to the same function (each
// earlier IEX hook has a thunk per site, all jumping to one replacement).
int ChainAll(const char* fn, Word& original, const void* replacement)
{
    int n = 0;
    for (std::uint32_t s : engineTypes.CallSitesOf(fn)) {
        Word target = 0;
        if (Chain(EngineImageBase() + s, target, replacement)) {
            if (original && Resolve(original) != Resolve(target))
                Log("[stick] call sites of %s target different functions", fn);
            original = target;
            ++n;
        }
    }
    return n;
}

Word SiteOf(const char* name) { return Abs(Sym(name)); }

bool g_installed[hp::kCount] = {};

void Mark(Point b, bool ok)
{
    g_installed[b] = ok;
}

} // namespace

void OpenLuaStickHooks(lua_State* L)
{
    // IEX_Features.stickHooks = number of combat / UI points installed on this build.
    int n = 0;
    for (Point p : kStickPoints)
        n += g_installed[p] ? 1 : 0;
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushinteger(L, n);
    lua.setfield(L, -2, "stickHooks");
    lua.settop(L, -2);
}

void InstallStickHooks()
{
    g_spriteType = engineTypes.Get("CGameSprite");
    g_effectType = engineTypes.Get("CGameEffect");
    if (const TypeDesc* t = engineTypes.Get("CGameObject")) {
        std::uint32_t off = 0;
        if (t->Find("m_id", off))
            g_idOffset = off;
    }
    const Word base = EngineImageBase();
    std::uint64_t c = 0;
    auto loc = [](const char* name) { return Sym(name); };

    // Per-attack contexts.
    const int hitSites = ChainAll("_ZN11CGameSprite3HitEPS_P5CItemiRii", g_hitFn, reinterpret_cast<const void*>(&HookHit));
    const int damageSites = ChainAll("_ZN11CGameSprite6DamageEP5CItemS1_iiRK13CAIObjectTypessPS_i", g_damageFn,
                                     reinterpret_cast<const void*>(&HookDamage));
    const bool hitCtx = hitSites > 0, damageCtx = damageSites > 0;
    Mark(kAttackResult, hitCtx);
    if (const Word dice = SiteOf("_ZN11CGameSprite11ATTACK_DICEE"))
        g_attackDice = Read<std::int16_t>(dice);

    // Swing ticks and their attack frame type.
    const int swingSites = ChainAll("_ZN11CGameSprite5SwingEPS_", g_swingFn, reinterpret_cast<const void*>(&HookSwing));
    if (const Word off = SiteOf("_ZN11CGameSprite17ATTACK_NUM_OFFSETE"))
        g_attackNumOffset = Read<std::int16_t>(off);
    int frameSites = 0;
    for (const char* name : {"IEX_Site_StickFrameType", "IEX_Site_StickFrameType2"}) {
        const Word s = SiteOf(name);
        if (!s)
            continue;
        const auto* b = reinterpret_cast<const std::uint8_t*>(s);
        Word target = 0;
        bool ok = false;
        if (b[0] == 0xE8) {
            ok = Chain(s, target, reinterpret_cast<const void*>(&HookFrameType));
        } else if (b[0] == 0xE9) {
            std::int32_t rel;
            std::memcpy(&rel, b + 1, 4);
            target = s + 5 + rel;
            ok = HookJumpSite(s, target, reinterpret_cast<const void*>(&HookFrameType));
        }
        if (ok) {
            g_frameFn = target;
            ++frameSites;
        }
    }
    Mark(kAttackCancel, swingSites > 0 && frameSites > 0);
    Mark(kAttackIndex, swingSites > 0 && frameSites > 0);

    if (const Word s = SiteOf("IEX_Site_HitRoll"))
        Mark(kHitRoll, hitCtx && Chain(s, g_randFn, reinterpret_cast<const void*>(&HookHitRoll)));
    if (const Word s = SiteOf("IEX_Site_StickCritValue")) {
        const bool ok = hitCtx && Chain(s, g_critValueFn, reinterpret_cast<const void*>(&HookCritValue));
        Mark(kCritMod, ok);
        Mark(kCritBlocked, ok && g_installed[kHitRoll]);
    }
    g_locHitMod = loc("IEX_StickLoc_HitMod");
    if (const Word s = SiteOf("IEX_Site_StickHitMod"))
        Mark(kHitMod, hitCtx && g_locHitMod && HookCallSiteRegs(s, &RegHitMod));
    g_locDamMod = loc("IEX_StickLoc_DamMod");
    if (const Word s = SiteOf("IEX_Site_StickDamMod"))
        Mark(kDamMod, damageCtx && g_locDamMod && HookCallSiteRegs(s, &RegDamMod));
    g_critMultiplierGlobal = SiteOf("_ZN11CGameSprite23CRITICAL_HIT_MULTIPLIERE");
    if (const Word s = SiteOf("IEX_Site_StickCritMultiplier"))
        Mark(kCritMultiplier, damageCtx && g_critMultiplierGlobal && HookCallSiteRegs(s, &RegCritMultiplier));
    if (const Word s = SiteOf("IEX_Site_StickHideNearest"))
        Mark(kHide, Chain(s, g_nearestFn, reinterpret_cast<const void*>(&HookHideNearest)));
    Mark(kButton, ChainAll("_ZN15CInfButtonArray16OnLButtonPressedEi", g_lButtonFn,
                           reinterpret_cast<const void*>(&HookLButton)) > 0);
    Mark(kRButton, ChainAll("_ZN15CInfButtonArray16OnRButtonPressedEi", g_rButtonFn,
                            reinterpret_cast<const void*>(&HookRButton)) > 0);
    const char* schoolSites[3] = {"IEX_Site_StickSchoolSpell", "IEX_Site_StickSchoolItem", "IEX_Site_StickSchoolSave"};
    const char* schoolSprite[3] = {"IEX_StickLoc_SchoolSpellSprite", "IEX_StickLoc_SchoolItemSprite",
                                   "IEX_StickLoc_SchoolSaveSprite"};
    const char* schoolEffect[3] = {"IEX_StickLoc_SchoolSpellEffect", "IEX_StickLoc_SchoolItemEffect",
                                   "IEX_StickLoc_SchoolSaveEffect"};
    const Point schoolB[3] = {kSaveDCSpell, kSaveDCItem, kSaveMod};
    for (int i = 0; i < 3; ++i) {
        g_locSaveSprite[i] = loc(schoolSprite[i]);
        g_locSaveEffect[i] = loc(schoolEffect[i]);
        const Word s = SiteOf(schoolSites[i]);
        Mark(schoolB[i], s && g_locSaveSprite[i] && g_locSaveEffect[i] &&
                             HookCallSiteRegs(s, &RegSchool, reinterpret_cast<void*>(static_cast<std::intptr_t>(i))));
    }
    if (const Word s = SiteOf("IEX_Site_StickClassDone"))
        Mark(kClassDone, Chain(s, g_classFn, reinterpret_cast<const void*>(&HookClassDone)));
    // Proficiency maximum: the setfield call must follow `mov edx|esi, -2` and reach lua_setfield.
    g_setFieldFn = SiteOf("lua_setfield");
    if (const Word s = SiteOf("IEX_Site_ProfMaxField"); s && g_setFieldFn) {
        const auto* p = reinterpret_cast<const std::uint8_t*>(s);
        const bool minus2 = (p[-5] == 0xBA || p[-5] == 0xBE) && Read<std::uint32_t>(s - 4) == 0xFFFFFFFEu;
        Mark(kProfMaxUI, minus2 && HookCallSite(s, g_setFieldFn, reinterpret_cast<const void*>(&HookProfMaxField)));
    }
    g_classProfFn = SiteOf("_ZNK11CRuleTables19GetClassProficiencyEhhhijj");
    if (g_classProfFn) {
        int sites = 0;
        for (const char* name : {"IEX_Site_ProfMaxGet0", "IEX_Site_ProfMaxGet1", "IEX_Site_ProfMaxGet2"})
            if (const Word s = SiteOf(name))
                sites += HookCallSite(s, g_classProfFn, reinterpret_cast<const void*>(&HookClassProficiency)) ? 1 : 0;
        Mark(kProfMax, sites == 3);
        if (sites != 0 && sites != 3)
            Log("[stick] proficiency maximum: only %d of 3 GetClassProficiency call sites hooked", sites);
    }
    (void)base;
    (void)c;

    int n = 0;
    std::string missing;
    for (Point p : kStickPoints) {
        hp::MarkInstalled(p, g_installed[p], 1, g_installed[p] ? nullptr : "site missing or patched by something else");
        if (g_installed[p])
            ++n;
        else
            missing += std::string(" ") + hp::InfoOf(p).name;
    }
    Log("[stick] native hooks: %d/%d points installed (Hit sites %d, Damage sites %d); not installed:%s", n,
        static_cast<int>(sizeof(kStickPoints) / sizeof(kStickPoints[0])), hitSites, damageSites, missing.c_str());
}

} // namespace iex
