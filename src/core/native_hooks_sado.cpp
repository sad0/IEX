// SadoEE engine behaviours as native hook points, Windows + Linux (docs/API_SPEC.md "Native hook points").
// Engine evidence (both builds, from the game binaries): IEX-data/engine/win/verified_sado2.json.
//
//   groundContainer  CGameSprite::UpdateVisibleGroundItems lists the objects in range whose container type is 4
//                    (pile). Its call of CInfGame::GetContainerType goes through a thunk passing the sprite and
//                    the object: a listener returning true makes any other container count as a pile there.
//   smallFootprint   every call of CSearchBitmap::AddObject / RemoveObject / SnapshotRemoveObject: for a bumpable
//                    creature (its last argument is not 0) the footprint size becomes 1 (mode 1) or nothing is
//                    stamped (mode 0). Add and remove see the same change, so no square stays blocked.
//   containerMarker  modules.cpp: the permanent outline of a container whose m_drawPoly holds a marker value is
//                    drawn in a color read from memory.
//   lastingModes     the modal state (bard song, stealth, turn undead, dance) is no longer cancelled by a new
//                    action, an action-bar click, a spell hotkey or picking up an item (their SetModalState(0)
//                    calls), by a failed stealth re-roll (that path ends at once: no message, the thief rolls
//                    again next round) or by moving while dancing (opcode 363); CheckModal's per-round song / turn
//                    undead feedback is not printed.
//   findTrapsButton  the Find Traps action-bar button asks the listeners first; true = handled (the button
//                    handler ends as after a mode change, selection back to 100).
//   stealthReveals   a reveal (opcode 136, CGameEffectForceVisible) of a sprite in stealth clears its
//                    "already hidden" flag, so hiding again is a real roll. Talking, opening a container and
//                    picking up an item no longer reveal; a hostile spell / item / forced spell reveals only when
//                    its target is not the caster nor an ally (both EA <= 30 or both >= 200), creatures only.
//
// Mid-function sites use small fixed thunks written here per behaviour, after checking the site's bytes.
#include "native_hooks_internal.h"

#include "callsite_hook.h"
#include "hook_points.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"
#include "modules.h"
#include "platform_memory.h"

#include <climits>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace iex {

namespace nh {

void Code::Put(std::initializer_list<std::uint8_t> bytes)
{
    for (std::uint8_t v : bytes) {
        if (n >= sizeof(b)) {
            overflow = true;
            return;
        }
        b[n++] = v;
    }
}

void Code::PutBytes(const std::uint8_t* bytes, std::size_t count)
{
    for (std::size_t i = 0; i < count; ++i)
        Put({bytes[i]});
}

void Code::Put32(std::uint32_t v)
{
    for (int i = 0; i < 4; ++i)
        Put({static_cast<std::uint8_t>(v >> (8 * i))});
}

void Code::Put64(std::uint64_t v)
{
    for (int i = 0; i < 8; ++i)
        Put({static_cast<std::uint8_t>(v >> (8 * i))});
}

void Code::JmpAbs(Word target)
{
    Put({0xFF, 0x25, 0, 0, 0, 0});
    Put64(target);
}

void Code::CallRax(Word target)
{
    Put({0x48, 0xB8});
    Put64(target);
    Put({0xFF, 0xD0});
}

std::size_t Code::Jcc8(std::uint8_t opcode)
{
    Put({opcode, 0});
    return n - 1;
}

void Code::Land(std::size_t jccAt)
{
    const std::size_t rel = n - (jccAt + 1);
    if (rel > 127)
        overflow = true;
    b[jccAt] = static_cast<std::uint8_t>(rel);
}

bool BytesAre(Word at, const std::uint8_t* bytes, std::size_t count)
{
    return at && std::memcmp(reinterpret_cast<const void*>(at), bytes, count) == 0;
}

Word RelTarget(Word at)
{
    const auto* code = reinterpret_cast<const std::uint8_t*>(at);
    if (code[0] != 0xE8 && code[0] != 0xE9)
        return 0;
    std::int32_t rel;
    std::memcpy(&rel, code + 1, 4);
    return at + 5 + rel;
}

namespace {

std::uint8_t* PlaceThunk(Word site, const Code& code, std::string& why)
{
    if (code.overflow) {
        why = "thunk too large";
        return nullptr;
    }
    auto* t = static_cast<std::uint8_t*>(platform::AllocExecNear(site, code.n));
    if (!t) {
        why = "no executable memory";
        return nullptr;
    }
    std::memcpy(t, code.b, code.n);
    return t;
}

bool Rel32To(Word from, const void* to, std::int32_t& rel)
{
    const std::int64_t r = reinterpret_cast<std::int64_t>(to) - static_cast<std::int64_t>(from);
    if (r < INT32_MIN || r > INT32_MAX)
        return false;
    rel = static_cast<std::int32_t>(r);
    return true;
}

} // namespace

bool JumpToThunk(Word site, std::size_t overwrite, const Code& code, std::string& why)
{
    std::uint8_t* t = PlaceThunk(site, code, why);
    if (!t)
        return false;
    std::uint8_t patch[32];
    if (overwrite < 5 || overwrite > sizeof(patch)) {
        why = "bad patch size";
        return false;
    }
    std::int32_t rel;
    if (!Rel32To(site + 5, t, rel)) {
        why = "thunk out of range";
        return false;
    }
    patch[0] = 0xE9;
    std::memcpy(patch + 1, &rel, 4);
    for (std::size_t i = 5; i < overwrite; ++i)
        patch[i] = 0x90;
    return platform::PatchCode(reinterpret_cast<void*>(site), patch, overwrite) || (why = "site not writable", false);
}

bool CallToThunk(Word site, Word expectedTarget, const Code& code, std::string& why)
{
    if (RelTarget(site) != expectedTarget || reinterpret_cast<const std::uint8_t*>(site)[0] != 0xE8) {
        why = "the call site holds other code (patched by something else?)";
        return false;
    }
    std::uint8_t* t = PlaceThunk(site, code, why);
    if (!t)
        return false;
    std::int32_t rel;
    if (!Rel32To(site + 5, t, rel)) {
        why = "thunk out of range";
        return false;
    }
    return platform::PatchCode(reinterpret_cast<void*>(site + 1), &rel, 4) || (why = "site not writable", false);
}

} // namespace nh

namespace {

using nh::Code;
using nh::Sym;
using nh::Word;

const TypeDesc* Type(const char* name)
{
    return engineTypes.Get(name);
}

int PushSprite(lua_State* L, const void* ctx)
{
    PushObject(L, *static_cast<const Word*>(ctx), Type("CGameSprite"));
    return 1;
}

// All direct calls of `fn` (engine description call sites) redirected to `hook`; all-or-nothing.
bool HookAllCalls(const char* fn, Word& target, const void* hook, std::string& why)
{
    target = Sym(fn);
    const auto calls = engineTypes.CallSitesOf(fn);
    if (!target || calls.empty()) {
        why = std::string("no call sites of ") + fn + " in the engine description";
        return false;
    }
    for (std::uint32_t s : calls)
        if (nh::RelTarget(EngineImageBase() + s) != target) {
            why = std::string("a call of ") + fn + " is patched by something else";
            return false;
        }
    int n = 0;
    for (std::uint32_t s : calls)
        n += HookCallSite(EngineImageBase() + s, target, hook) ? 1 : 0;
    if (n != static_cast<int>(calls.size()))
        Log("Native hooks: only %d of %d calls of %s hooked", n, static_cast<int>(calls.size()), fn);
    return n == static_cast<int>(calls.size());
}

// Symbols name0, name1... while they exist.
std::vector<Word> Numbered(const char* prefix, int max = 32)
{
    std::vector<Word> out;
    for (int i = 0; i < max; ++i) {
        const Word a = Sym((std::string(prefix) + std::to_string(i)).c_str());
        if (!a)
            break;
        out.push_back(a);
    }
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// groundContainer (SadoEE #31 chests in the ground bar)

constexpr std::uint16_t kContainerPile = 4;
Word g_getContainerType = 0;

struct ContainerAndSprite {
    Word container, sprite;
};

int PushContainerAndSprite(lua_State* L, const void* ctx)
{
    const auto* p = static_cast<const ContainerAndSprite*>(ctx);
    PushObject(L, p->container, Type("CGameContainer"));
    PushObject(L, p->sprite, Type("CGameSprite"));
    return 2;
}

// GetContainerType(game, id) as UpdateVisibleGroundItems sees it; the thunk adds the sprite and the object.
Word HookGroundContainerType(Word game, Word id, Word sprite, Word container)
{
    const Word type = reinterpret_cast<Word (*)(Word, Word)>(g_getContainerType)(game, id);
    const auto t = static_cast<std::uint16_t>(type);
    if (t != kContainerPile && t != 0xFFFF && sprite && container) {
        const ContainerAndSprite p{container, sprite};
        if (hp::Active(hp::kGroundContainer) &&
            hp::FireBool(hp::kGroundContainer, [&](lua_State* L) { return PushContainerAndSprite(L, &p); }))
            return kContainerPile;
    }
    return type;
}

} // namespace

bool InstallGroundContainer(std::string& why)
{
    const Word site = Sym("IEX_Site_GroundItemsContainerType");
    g_getContainerType = Sym("_ZN8CInfGame16GetContainerTypeEi");
    if (!site || !g_getContainerType) {
        why = "site not in the engine description";
        return false;
    }
    static const std::uint8_t kAfter[] = {0x66, 0x83, 0xF8, 0x04};  // cmp ax, 4
#ifdef _WIN32
    static const std::uint8_t kBefore[] = {0x8B, 0xD3, 0x48, 0x8B, 0xCF};  // mov edx, ebx ; mov rcx, rdi
#else
    static const std::uint8_t kBefore[] = {0x44, 0x89, 0xEE};  // mov esi, r13d
#endif
    if (!nh::BytesAre(site + 5, kAfter, sizeof(kAfter)) || !nh::BytesAre(site - sizeof(kBefore), kBefore, sizeof(kBefore))) {
        why = "unexpected code around the call (patched by something else?)";
        return false;
    }
    Code c;
#ifdef _WIN32
    c.Put({0x4D, 0x89, 0xF8});              // mov r8, r15             sprite (this)
    c.Put({0x4C, 0x8B, 0x4C, 0x24, 0x58});  // mov r9, [rsp+0x58]      object (caller's [rsp+0x50])
#else
    c.Put({0x48, 0x8B, 0x95, 0x60, 0xFF, 0xFF, 0xFF});  // mov rdx, [rbp-0xa0]   sprite (this)
    c.Put({0x48, 0x8B, 0x8D, 0x78, 0xFF, 0xFF, 0xFF});  // mov rcx, [rbp-0x88]   object
#endif
    c.JmpAbs(reinterpret_cast<Word>(&HookGroundContainerType));
    return nh::CallToThunk(site, g_getContainerType, c, why);
}

namespace {

// ---------------------------------------------------------------------------------------------------------------
// smallFootprint (SadoEE #25 / #26)

constexpr const char* kSearchAdd = "_ZN13CSearchBitmap9AddObjectERK6CPointhhi";
constexpr const char* kSearchRemove = "_ZN13CSearchBitmap12RemoveObjectERK6CPointhhi";
constexpr const char* kSearchSnap = "_ZN13CSearchBitmap20SnapshotRemoveObjectE6CPointhi";
Word g_searchAdd = 0, g_searchRemove = 0, g_searchSnap = 0;
int g_footMode = 1;
bool g_footActive = false;  // hooks installed (SearchFootprintSize)

// false: nothing is stamped
bool FootSize(Word& size, Word bumpable)
{
    if (static_cast<std::int32_t>(bumpable) == 0)
        return true;
    if (g_footMode == 0)
        return false;
    if ((size & 0xFF) > 1)
        size = 1;
    return true;
}

// (bitmap, CPoint const&, uchar, uchar size, int bumpable)
void HookSearchAdd(Word bm, Word pt, Word a, Word size, Word bump)
{
    if (FootSize(size, bump))
        reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(g_searchAdd)(bm, pt, a, size, bump);
}

void HookSearchRemove(Word bm, Word pt, Word a, Word size, Word bump)
{
    if (FootSize(size, bump))
        reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(g_searchRemove)(bm, pt, a, size, bump);
}

// (bitmap, CPoint by value, uchar size, int bumpable): the pathing thread's copy; no Lua here.
void HookSearchSnap(Word bm, Word pt, Word size, Word bump)
{
    if (FootSize(size, bump))
        reinterpret_cast<void (*)(Word, Word, Word, Word)>(g_searchSnap)(bm, pt, size, bump);
}

} // namespace

bool InstallSmallFootprint(std::string& why, nh::Word mode)
{
    if (mode != 0 && mode != 1) {
        why = "mode must be 0 or 1";
        return false;
    }
    g_footMode = static_cast<int>(mode);
    // all three or none (checked before anything is written)
    for (const char* fn : {kSearchAdd, kSearchRemove, kSearchSnap}) {
        const Word target = Sym(fn);
        const auto calls = engineTypes.CallSitesOf(fn);
        if (!target || calls.empty()) {
            why = std::string("no call sites of ") + fn;
            return false;
        }
        for (std::uint32_t s : calls)
            if (nh::RelTarget(EngineImageBase() + s) != target) {
                why = "a CSearchBitmap call is patched by something else";
                return false;
            }
    }
    g_footActive = HookAllCalls(kSearchAdd, g_searchAdd, reinterpret_cast<const void*>(&HookSearchAdd), why) &&
                   HookAllCalls(kSearchRemove, g_searchRemove, reinterpret_cast<const void*>(&HookSearchRemove), why) &&
                   HookAllCalls(kSearchSnap, g_searchSnap, reinterpret_cast<const void*>(&HookSearchSnap), why);
    return g_footActive;
}

int SearchFootprintSize(int size, bool bumpable)
{
    if (!g_footActive)
        return size;
    Word w = static_cast<Word>(size);
    return FootSize(w, bumpable ? 1 : 0) ? static_cast<int>(w & 0xFF) : 0;
}

bool InstallContainerMarker(std::string& why, nh::Word colorAddress, nh::Word marker)
{
    if (!colorAddress) {
        why = "no color address";
        return false;
    }
    if (!SetContainerMarkerColor(colorAddress, static_cast<int>(marker))) {
        why = "the container outline hook is not installed";
        return false;
    }
    return true;
}

namespace {

// ---------------------------------------------------------------------------------------------------------------
// lastingModes (SadoEE #27)

Word g_setModalState = 0, g_feedBack = 0;
bool g_modesOn = false;

void HookModalCancel(Word sprite, Word state, Word b)
{
    if (g_modesOn && (state & 0xFF) == 0)
        return;
    reinterpret_cast<void (*)(Word, Word, Word)>(g_setModalState)(sprite, state, b);
}

// CGameSprite::FeedBack(this, uint, int, int, int, uint, int, CString const&): 8 arguments on both ABIs.
void HookModalFeedback(Word a, Word b, Word c, Word d, Word e, Word f, Word g, Word h)
{
    if (g_modesOn)
        return;
    reinterpret_cast<void (*)(Word, Word, Word, Word, Word, Word, Word, Word)>(g_feedBack)(a, b, c, d, e, f, g, h);
}

#ifdef _WIN32
// mov dword ptr [rsi+0x4e50], r12d (the flag the failure path clears) right before the site
const std::uint8_t kStealthFailBefore[] = {0x44, 0x89, 0xA6, 0x50, 0x4E, 0x00, 0x00};
const std::uint8_t kStealthFailSite[] = {0x48, 0x8D, 0x4D, 0xC0, 0xE8};  // lea rcx, [rbp-0x40] ; call
#else
// mov dword ptr [r13+0x4e38], 0
const std::uint8_t kStealthFailBefore[] = {0x41, 0xC7, 0x85, 0x38, 0x4E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
const std::uint8_t kStealthFailSite[] = {0x48, 0x89, 0xC3, 0x48, 0x89, 0xC7};  // mov rbx, rax ; mov rdi, rax
#endif

} // namespace

bool InstallLastingModes(std::string& why)
{
    g_setModalState = Sym("_ZN11CGameSprite13SetModalStateEhi");
    g_feedBack = Sym("_ZN11CGameSprite8FeedBackEjiiijiRK7CString");
    const auto cancels = Numbered("IEX_Site_ModalCancel");
    const auto fails = Numbered("IEX_Site_StealthFailJmp");
    const Word end = Sym("IEX_Site_CheckModalEnd"), dance = Sym("IEX_Site_DanceMoveJe");
    if (!g_setModalState || !g_feedBack || cancels.empty() || fails.empty() || !end || !dance) {
        why = "sites not in the engine description";
        return false;
    }
    // check everything first
    for (Word s : cancels)
        if (nh::RelTarget(s) != g_setModalState) {
            why = "a SetModalState call is patched by something else";
            return false;
        }
    for (Word s : fails)
        if (!nh::BytesAre(s - sizeof(kStealthFailBefore), kStealthFailBefore, sizeof(kStealthFailBefore)) ||
            !nh::BytesAre(s, kStealthFailSite, sizeof(kStealthFailSite))) {
            why = "unexpected code in CheckModal's stealth failure path";
            return false;
        }
    const auto* d = reinterpret_cast<const std::uint8_t*>(dance);
#ifdef _WIN32
    const bool danceOk = d[0] == 0x0F && d[1] == 0x84;
#else
    const bool danceOk = d[0] == 0x74;
#endif
    if (!danceOk) {
        why = "unexpected code in the movement-rate modal effect";
        return false;
    }
    // 1. / 2. the SetModalState(0) calls of actions and buttons
    for (Word s : cancels)
        if (!HookCallSite(s, g_setModalState, reinterpret_cast<const void*>(&HookModalCancel))) {
            why = "a SetModalState call could not be hooked";
            return false;
        }
    g_modesOn = true;
    // 3. a failed stealth re-roll ends CheckModal at once (the flag is cleared just before, as the engine does)
    for (Word s : fails) {
        std::uint8_t jmp[5] = {0xE9};
        const std::int32_t rel = static_cast<std::int32_t>(static_cast<std::int64_t>(end) - static_cast<std::int64_t>(s + 5));
        std::memcpy(jmp + 1, &rel, 4);
        if (!platform::PatchCode(reinterpret_cast<void*>(s), jmp, sizeof(jmp)))
            Log("Native hook lastingModes: stealth failure site %p not writable", reinterpret_cast<void*>(s));
    }
    // 4. dancing (opcode 363) is not cancelled by moving: je -> jmp
#ifdef _WIN32
    const std::uint8_t danceJmp[2] = {0x90, 0xE9};
    platform::PatchCode(reinterpret_cast<void*>(dance), danceJmp, 2);
#else
    const std::uint8_t danceJmp = 0xEB;
    platform::PatchCode(reinterpret_cast<void*>(dance), &danceJmp, 1);
#endif
    // 5b. no per-round song / dance / turn undead feedback (checked on their own)
    for (const char* name : {"IEX_Site_ModalFeedbackSong", "IEX_Site_ModalFeedbackTurn"}) {
        const Word s = Sym(name);
        if (!s || !HookCallSite(s, g_feedBack, reinterpret_cast<const void*>(&HookModalFeedback)))
            Log("Native hook lastingModes: %s not hooked", name);
    }
    return true;
}

namespace {

// ---------------------------------------------------------------------------------------------------------------
// findTrapsButton (SadoEE #27 + #20: the Find Traps button toggles the passive trap detection)

bool HookFindTraps(Word sprite)
{
    return sprite && hp::Active(hp::kFindTrapsButton) &&
           hp::FireBool(hp::kFindTrapsButton, [&](lua_State* L) { return PushSprite(L, &sprite); });
}

} // namespace

bool InstallFindTrapsButton(std::string& why)
{
    const Word site = Sym("IEX_Site_FindTrapsButton"), exit = Sym("IEX_Site_FindTrapsButtonExit");
    if (!site || !exit) {
        why = "site not in the engine description";
        return false;
    }
#ifdef _WIN32
    static const std::uint8_t kSite[] = {0x48, 0x8B, 0x4C, 0x24, 0x48};  // mov rcx, [rsp+0x48]   (the sprite)
    static const std::uint8_t kExit[] = {0xBF, 0x64, 0x00, 0x00, 0x00};  // mov edi, 100
#else
    static const std::uint8_t kSite[] = {0x4C, 0x8B, 0xAD, 0x80, 0xFE, 0xFF, 0xFF};  // mov r13, [rbp-0x180]
    static const std::uint8_t kExit[] = {0x48, 0x8B, 0x05};                         // mov rax, [rip+...]
#endif
    if (!nh::BytesAre(site, kSite, sizeof(kSite)) || !nh::BytesAre(exit, kExit, sizeof(kExit))) {
        why = "unexpected code in the Find Traps button handler";
        return false;
    }
    Code c;
    c.PutBytes(kSite, sizeof(kSite));  // the instruction replaced
#ifdef _WIN32
    c.Put({0x48, 0x83, 0xEC, 0x20});  // sub rsp, 0x20      (shadow space; rsp is 16-aligned in the body)
    c.CallRax(reinterpret_cast<Word>(&HookFindTraps));
    c.Put({0x48, 0x83, 0xC4, 0x20});  // add rsp, 0x20
    c.Put({0x84, 0xC0});              // test al, al
    const std::size_t handled = c.Jcc8(0x75);
    c.PutBytes(kSite, sizeof(kSite));  // rcx again
    c.JmpAbs(site + sizeof(kSite));
    c.Land(handled);
    c.JmpAbs(exit);
#else
    c.Put({0x4C, 0x89, 0xEF});        // mov rdi, r13
    c.CallRax(reinterpret_cast<Word>(&HookFindTraps));
    c.Put({0x84, 0xC0});              // test al, al
    const std::size_t handled = c.Jcc8(0x75);
    c.JmpAbs(site + sizeof(kSite));
    c.Land(handled);
    c.Put({0x41, 0xBC, 0x64, 0x00, 0x00, 0x00});  // mov r12d, 100 (selected button, as the toggle-off path)
    c.JmpAbs(exit);
#endif
    return nh::JumpToThunk(site, sizeof(kSite), c, why);
}

namespace {

// ---------------------------------------------------------------------------------------------------------------
// stealthReveals (SadoEE #27, stealth part)

constexpr std::uint8_t kModalStealth = 3;
constexpr std::uint8_t kTypeSprite = 0x31;      // CGameObject::m_objectType of a CGameSprite
constexpr std::uint32_t kObjectTypeOffset = 0x8;  // m_objectType (both builds)
constexpr std::uint32_t kEnemyAllyOffset = 0x38;  // m_typeAI.m_EnemyAlly (both builds)

Word g_fvApply = 0, g_forceVisible = 0, g_removeSanctuary = 0;
Word g_spell = 0, g_useItem = 0, g_forceSpell = 0;
std::uint32_t g_modalOffset = 0;
std::uint64_t g_hiddenOffset = 0;

Word HookForceVisibleApply(Word effect, Word sprite)
{
    if (sprite && *reinterpret_cast<const std::uint8_t*>(sprite + g_modalOffset) == kModalStealth)
        *reinterpret_cast<std::int32_t*>(sprite + g_hiddenOffset) = 0;
    return reinterpret_cast<Word (*)(Word, Word)>(g_fvApply)(effect, sprite);
}

// The target of the spell / item / forced spell being executed (CGameSprite::Spell, UseItem, ForceSpell: one
// engine call each), innermost last.
struct Cast {
    Word caster, target;
};
Cast g_casts[8];
int g_castDepth = 0;

template <Word* Original>
Word HookCastEntry(Word caster, Word target)
{
    const bool kept = g_castDepth < 8;
    if (kept)
        g_casts[g_castDepth++] = {caster, target};
    const Word r = reinterpret_cast<Word (*)(Word, Word)>(*Original)(caster, target);
    if (kept)
        --g_castDepth;
    return r;
}

// A hostile spell / item reveals its caster unless the target is the caster or an ally (creatures only).
bool CastReveals(Word caster)
{
    Word target = 0;
    bool known = false;
    for (int i = g_castDepth - 1; i >= 0; --i)
        if (g_casts[i].caster == caster) {
            target = g_casts[i].target;
            known = true;
            break;
        }
    if (!known || !target)
        return true;
    if (target == caster)
        return false;
    const auto* t = reinterpret_cast<const std::uint8_t*>(target);
    if (t[kObjectTypeOffset] != kTypeSprite)
        return true;
    const unsigned ea = reinterpret_cast<const std::uint8_t*>(caster)[kEnemyAllyOffset], tea = t[kEnemyAllyOffset];
    if (ea <= 30)
        return tea > 30;
    if (ea >= 200)
        return tea < 200;
    return true;
}

void HookCastForceVisible(Word sprite)
{
    if (CastReveals(sprite))
        reinterpret_cast<void (*)(Word)>(g_forceVisible)(sprite);
}

void HookCastRemoveSanctuary(Word sprite)
{
    if (CastReveals(sprite))
        reinterpret_cast<void (*)(Word)>(g_removeSanctuary)(sprite);
}

void HookNoReveal(Word) {}

#ifndef _WIN32
// Linux inlines ForceVisible + RemoveSanctuary after the hostile test: the test's je (to the code after both) goes
// through a thunk asking CastReveals(caster = rbx).
struct CastTest {
    Word site, next, skip;
    std::size_t length;  // bytes of the test + je replaced
};

bool DecodeCastTest(Word site, CastTest& out)
{
    static const std::uint8_t kTestAh6[] = {0xF6, 0xC4, 0x06};                                    // test ah, 6
    static const std::uint8_t kTestAbility[] = {0x41, 0xF7, 0x47, 0x26, 0x00, 0x06, 0x00, 0x00};  // test [r15+0x26], 0x600
    const auto* c = reinterpret_cast<const std::uint8_t*>(site);
    std::size_t testLen = 0;
    if (nh::BytesAre(site, kTestAh6, sizeof(kTestAh6)))
        testLen = sizeof(kTestAh6);
    else if (nh::BytesAre(site, kTestAbility, sizeof(kTestAbility)))
        testLen = sizeof(kTestAbility);
    else
        return false;
    out.site = site;
    if (c[testLen] == 0x74) {  // je rel8
        out.length = testLen + 2;
        out.skip = site + out.length + static_cast<std::int8_t>(c[testLen + 1]);
    } else if (c[testLen] == 0x0F && c[testLen + 1] == 0x84) {  // je rel32
        std::int32_t rel;
        std::memcpy(&rel, c + testLen + 2, 4);
        out.length = testLen + 6;
        out.skip = site + out.length + rel;
    } else {
        return false;
    }
    out.next = site + out.length;
    return out.length >= 5;
}

bool InstallCastTest(const CastTest& t, std::string& why)
{
    const auto* c = reinterpret_cast<const std::uint8_t*>(t.site);
    const std::size_t testLen = c[0] == 0xF6 ? 3 : 8;
    Code k;
    k.PutBytes(c, testLen);  // the original test
    const std::size_t notHostile = k.Jcc8(0x74);
    k.Put({0x48, 0x89, 0xDF});  // mov rdi, rbx (the caster)
    k.CallRax(reinterpret_cast<Word>(&CastReveals));
    k.Put({0x84, 0xC0});  // test al, al
    const std::size_t quiet = k.Jcc8(0x74);
    k.JmpAbs(t.next);
    k.Land(notHostile);
    k.Land(quiet);
    k.JmpAbs(t.skip);
    return nh::JumpToThunk(t.site, t.length, k, why);
}
#endif

} // namespace

bool InstallStealthReveals(std::string& why)
{
    const Word slot = Sym("IEX_VtSlot_ForceVisibleApply");
    g_fvApply = Sym("_ZN23CGameEffectForceVisible11ApplyEffectEP11CGameSprite");
    g_forceVisible = Sym("_ZN11CGameSprite12ForceVisibleEv");
    g_removeSanctuary = Sym("_ZN11CGameSprite15RemoveSanctuaryEv");
    const Word core = Sym("IEX_Fn_ForceVisibleCore");  // Linux only
    g_modalOffset = nh::FieldOffset("CGameSprite", "m_nModalState");
    const auto quiet = Numbered("IEX_Site_QuietReveal");
    const auto castCalls = Numbered("IEX_Site_CastRevealCall");
    const auto quietJne = Numbered("IEX_Site_QuietRevealJne");  // Linux only
    if (!slot || !g_fvApply || !g_forceVisible || !g_removeSanctuary || !g_modalOffset || quiet.empty() ||
        castCalls.empty() || !engineTypes.Const("IEX.native.stealthHidden", g_hiddenOffset)) {
        why = "sites not in the engine description";
        return false;
    }
    Word current = 0;
    std::memcpy(&current, reinterpret_cast<const void*>(slot), sizeof(current));
    if (current != g_fvApply) {
        why = "the force-visible effect's vtable slot holds something else";
        return false;
    }
    for (Word s : quiet) {
        const Word t = nh::RelTarget(s);
        if (reinterpret_cast<const std::uint8_t*>(s)[0] != 0xE8 || (t != g_forceVisible && (!core || t != core))) {
            why = "a reveal call is patched by something else";
            return false;
        }
    }
    for (Word s : castCalls) {
        const Word t = nh::RelTarget(s);
        if (reinterpret_cast<const std::uint8_t*>(s)[0] != 0xE8 || (t != g_forceVisible && t != g_removeSanctuary)) {
            why = "a cast reveal call is patched by something else";
            return false;
        }
    }
    static const std::uint8_t kJneRel32 = 0x85;
    for (Word s : quietJne)
        if (reinterpret_cast<const std::uint8_t*>(s)[0] != 0x0F || reinterpret_cast<const std::uint8_t*>(s)[1] != kJneRel32) {
            why = "an inlined reveal test is patched by something else";
            return false;
        }
#ifndef _WIN32
    std::vector<CastTest> tests;
    for (Word s : Numbered("IEX_Site_CastRevealTest")) {
        CastTest t{};
        if (!DecodeCastTest(s, t)) {
            why = "an inlined hostile-cast test is patched by something else";
            return false;
        }
        tests.push_back(t);
    }
#endif
    // the casts' targets (one engine call each)
    if (!HookAllCalls("_ZN11CGameSprite5SpellEP11CGameAIBase", g_spell,
                      reinterpret_cast<const void*>(&HookCastEntry<&g_spell>), why) ||
        !HookAllCalls("_ZN11CGameSprite7UseItemEP11CGameAIBase", g_useItem,
                      reinterpret_cast<const void*>(&HookCastEntry<&g_useItem>), why) ||
        !HookAllCalls("_ZN11CGameAIBase10ForceSpellEP11CGameSprite", g_forceSpell,
                      reinterpret_cast<const void*>(&HookCastEntry<&g_forceSpell>), why))
        return false;
    // 6. a reveal of a sprite in stealth clears its "already hidden" flag
    const Word hook = reinterpret_cast<Word>(&HookForceVisibleApply);
    if (!platform::PatchCode(reinterpret_cast<void*>(slot), &hook, sizeof(hook))) {
        why = "vtable slot not writable";
        return false;
    }
    // 7. no reveal when talking, opening a container, picking up an item
    for (Word s : quiet)
        HookCallSite(s, nh::RelTarget(s), reinterpret_cast<const void*>(&HookNoReveal));
    static const std::uint8_t kNop6[] = {0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00};
    for (Word s : quietJne)
        platform::PatchCode(reinterpret_cast<void*>(s), kNop6, sizeof(kNop6));
    // 8. hostile spell / item / forced spell: no reveal on self or allies
    for (Word s : castCalls) {
        const bool fv = nh::RelTarget(s) == g_forceVisible;
        HookCallSite(s, fv ? g_forceVisible : g_removeSanctuary,
                     fv ? reinterpret_cast<const void*>(&HookCastForceVisible)
                        : reinterpret_cast<const void*>(&HookCastRemoveSanctuary));
    }
#ifndef _WIN32
    for (const CastTest& t : tests) {
        std::string w;
        if (!InstallCastTest(t, w))
            Log("Native hook stealthReveals: cast test %p not patched: %s", reinterpret_cast<void*>(t.site), w.c_str());
    }
#endif
    return true;
}

namespace {

// ---------------------------------------------------------------------------------------------------------------
// Engine store / file functions (SadoEE camp merchant M_PSXGM.lua on Linux: its Windows stubs call these)

Word ArgW(lua_State* L, int i)
{
    return static_cast<Word>(lua.tointegerx(L, i, nullptr));
}

Word FnOrError(lua_State* L, const char* name)
{
    const Word f = Sym(name);
    if (!f)
        LuaError(L, "engine function %s not in the engine description", name);
    return f;
}

// IEX_Eng_StoreAddItem(CStore*, CItem*) -> result of CStore::AddItem(CItem&)
int LuaStoreAddItem(lua_State* L)
{
    const Word f = FnOrError(L, "_ZN6CStore7AddItemER5CItem");
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word (*)(Word, Word)>(f)(ArgW(L, 1), ArgW(L, 2)) & 0xFFFFFFFF));
    return 1;
}

// IEX_Eng_StoreCompressItems(CStore*)
int LuaStoreCompress(lua_State* L)
{
    const Word f = FnOrError(L, "_ZN6CStore13CompressItemsEv");
    reinterpret_cast<void (*)(Word)>(f)(ArgW(L, 1));
    lua.pushinteger(L, 0);
    return 1;
}

// IEX_Eng_ConstructItem(CItem*, resref, useCount1, useCount2, useCount3, wear, flags): CItem::CItem(CResRef, ...) on
// the memory at CItem* (EEex's CItem:Construct_Overload_Manual)
int LuaConstructItem(lua_State* L)
{
    const Word f = FnOrError(L, "_ZN5CItemC1E7CResRefttttj");
    const Word item = ArgW(L, 1);
    std::size_t len = 0;
    const char* res = lua.tolstring(L, 2, &len);
    if (!item || !res)
        LuaError(L, "IEX_Eng_ConstructItem: item and resref expected");
    char rr[8] = {};
    for (std::size_t i = 0; i < len && i < 8; ++i)
        rr[i] = static_cast<char>(res[i] >= 'a' && res[i] <= 'z' ? res[i] - 32 : res[i]);
    std::uint64_t value = 0;
    std::memcpy(&value, rr, 8);
    reinterpret_cast<void (*)(Word, Word, Word, Word, Word, Word, Word)>(f)(
        item, static_cast<Word>(value), ArgW(L, 3) & 0xFFFF, ArgW(L, 4) & 0xFFFF, ArgW(L, 5) & 0xFFFF, ArgW(L, 6) & 0xFFFF,
        ArgW(L, 7) & 0xFFFFFFFF);
    lua.pushinteger(L, 0);
    return 1;
}

// IEX_Eng_ResolveFileName(char* alias) -> char* real path (the engine's static buffer)
int LuaResolveFileName(lua_State* L)
{
    const Word f = FnOrError(L, "_Z19dimmResolveFileNamePKc");
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word (*)(Word)>(f)(ArgW(L, 1))));
    return 1;
}

// UTF-16LE (NUL-terminated, at most `max` units) -> UTF-8
std::string Utf8FromUtf16(const std::uint16_t* w, std::size_t max)
{
    std::string out;
    for (std::size_t i = 0; i < max && w[i]; ++i) {
        std::uint32_t cp = w[i];
        if (cp >= 0xD800 && cp < 0xDC00 && i + 1 < max && w[i + 1] >= 0xDC00 && w[i + 1] < 0xE000)
            cp = 0x10000 + ((cp - 0xD800) << 10) + (w[++i] - 0xDC00);
        if (cp < 0x80) {
            out += static_cast<char>(cp);
        } else if (cp < 0x800) {
            out += static_cast<char>(0xC0 | (cp >> 6));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += static_cast<char>(0xE0 | (cp >> 12));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (cp >> 18));
            out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }
    return out;
}

// IEX_File_WOpen(wchar16* path, wchar16* mode) -> FILE* (0 on failure): _wfopen on Windows, fopen(UTF-8) on Linux
int LuaFileWOpen(lua_State* L)
{
    const auto* path = reinterpret_cast<const std::uint16_t*>(ArgW(L, 1));
    const auto* mode = reinterpret_cast<const std::uint16_t*>(ArgW(L, 2));
    if (!path || !mode)
        LuaError(L, "IEX_File_WOpen: path and mode expected");
#ifdef _WIN32
    FILE* f = _wfopen(reinterpret_cast<const wchar_t*>(path), reinterpret_cast<const wchar_t*>(mode));
#else
    FILE* f = std::fopen(Utf8FromUtf16(path, 4096).c_str(), Utf8FromUtf16(mode, 16).c_str());
#endif
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word>(f)));
    return 1;
}

// IEX_File_Read(buffer, size, count, FILE*) -> items read
int LuaFileRead(lua_State* L)
{
    auto* f = reinterpret_cast<FILE*>(ArgW(L, 4));
    if (!f)
        LuaError(L, "IEX_File_Read: no file");
    lua.pushinteger(L, static_cast<lua_Integer>(std::fread(reinterpret_cast<void*>(ArgW(L, 1)), ArgW(L, 2), ArgW(L, 3), f)));
    return 1;
}

// IEX_File_Seek(FILE*, offset, whence) -> 0 on success
int LuaFileSeek(lua_State* L)
{
    auto* f = reinterpret_cast<FILE*>(ArgW(L, 1));
    if (!f)
        LuaError(L, "IEX_File_Seek: no file");
    lua.pushinteger(L, std::fseek(f, static_cast<long>(lua.tointegerx(L, 2, nullptr)), static_cast<int>(lua.tointegerx(L, 3, nullptr))));
    return 1;
}

// IEX_File_Close(FILE*)
int LuaFileClose(lua_State* L)
{
    auto* f = reinterpret_cast<FILE*>(ArgW(L, 1));
    lua.pushinteger(L, f ? std::fclose(f) : -1);
    return 1;
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

void OpenLuaSadoFunctions(lua_State* L)
{
    Register(L, "IEX_Eng_StoreAddItem", LuaStoreAddItem);
    Register(L, "IEX_Eng_StoreCompressItems", LuaStoreCompress);
    Register(L, "IEX_Eng_ResolveFileName", LuaResolveFileName);
    Register(L, "IEX_Eng_ConstructItem", LuaConstructItem);
    Register(L, "IEX_File_WOpen", LuaFileWOpen);
    Register(L, "IEX_File_Read", LuaFileRead);
    Register(L, "IEX_File_Seek", LuaFileSeek);
    Register(L, "IEX_File_Close", LuaFileClose);
}

bool SadoGroundContainerAvailable()
{
    return Sym("IEX_Site_GroundItemsContainerType") && Sym("_ZN8CInfGame16GetContainerTypeEi");
}

bool SadoSmallFootprintAvailable()
{
    return !engineTypes.CallSitesOf(kSearchAdd).empty() && !engineTypes.CallSitesOf(kSearchRemove).empty() &&
           !engineTypes.CallSitesOf(kSearchSnap).empty();
}

bool SadoContainerMarkerAvailable() { return Sym("_ZN14CGameContainer6RenderEP9CGameAreaP8CVidMode") != 0; }

bool SadoLastingModesAvailable()
{
    return Sym("IEX_Site_ModalCancel0") && Sym("IEX_Site_StealthFailJmp0") && Sym("IEX_Site_DanceMoveJe");
}

bool SadoFindTrapsButtonAvailable() { return Sym("IEX_Site_FindTrapsButton") && Sym("IEX_Site_FindTrapsButtonExit"); }

bool SadoStealthRevealsAvailable() { return Sym("IEX_VtSlot_ForceVisibleApply") && Sym("IEX_Site_QuietReveal0"); }

} // namespace iex
