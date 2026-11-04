// See native_hooks.h. Engine evidence (both builds, from the game binaries): IEX-data/engine/win/verified_native.json.
//
// keepAmmo: CGameSprite::Swing (L 0x44d800) uses up one charge of the ability it fires with
//     count = CItem::GetUsageCount(item, ability); CItem::SetUsageCount(item, ability, (u16)(count - 1))
// right after the hit roll, when the attacker's flag at +0x4b90 (W +0x4ba8) is set and the ability has charges
// (+0x22). That one call (IEX_Site_SwingSetUsageCount) is redirected; the attacker is in a callee-saved register
// there (L r14, W rbx), which a small thunk passes as an extra argument.
//
// groundMoveClick: CGameArea::OnActionButtonClickGround starts with a switch on CInfGame::m_nState (+0x4030):
// 0 = move the selection to the clicked point, 1 = other cursor states, anything else returns. Its callers are
// four direct calls and two tail jumps on each build; they are redirected to a function that reads the state
// first and calls the original afterwards.
#include "native_hooks.h"
#include "native_hooks_internal.h"

#include "callsite_hook.h"
#include "hook_points.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"
#include "platform_memory.h"

#include <climits>
#include <cstdint>
#include <cstring>
#include <string>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kSetUsageCount = "_ZN5CItem13SetUsageCountEit";
constexpr const char* kClickGround = "_ZN9CGameArea25OnActionButtonClickGroundERK6CPoint";
constexpr const char* kAmmoSite = "IEX_Site_SwingSetUsageCount";
constexpr const char* kClickGroundJmp[] = {"IEX_Site_ClickGroundJmp0", "IEX_Site_ClickGroundJmp1"};

#ifdef _WIN32
// lea ...; dec ax / mov edx, edi / movzx r8d, ax / mov rcx, r12 ; E8 SetUsageCount ; movzx eax, byte [rbx+0x4ba8]
constexpr std::uint8_t kAmmoBefore[] = {0x66, 0xFF, 0xC8, 0x8B, 0xD7, 0x44, 0x0F, 0xB7, 0xC0, 0x49, 0x8B, 0xCC};
constexpr std::uint8_t kAmmoAfter[] = {0x0F, 0xB6, 0x83, 0xA8, 0x4B, 0x00, 0x00};
// mov r9, rbx (attacker -> 4th argument)
constexpr std::uint8_t kSpriteToArg4[] = {0x49, 0x89, 0xD9};
#else
// lea edx, [rax-1] / mov esi, ebx / mov rdi, r13 / movzx edx, dx ; E8 SetUsageCount ; cmp byte [r14+0x4b90], 0
constexpr std::uint8_t kAmmoBefore[] = {0x8D, 0x50, 0xFF, 0x89, 0xDE, 0x4C, 0x89, 0xEF, 0x0F, 0xB7, 0xD2};
constexpr std::uint8_t kAmmoAfter[] = {0x41, 0x80, 0xBE, 0x90, 0x4B, 0x00, 0x00, 0x00};
// mov rcx, r14 (attacker -> 4th argument)
constexpr std::uint8_t kSpriteToArg4[] = {0x4C, 0x89, 0xF1};
#endif

lua_State* g_L = nullptr;
Word g_setUsageCount = 0, g_clickGround = 0;
int g_clickSites = 0;
std::uint32_t g_gameOffset = 0, g_stateOffset = 0;
Word g_chitin = 0;  // address of g_pBaldurChitin

Word Sym(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? EngineImageBase() + rva : 0;
}

std::uint32_t FieldOffset(const char* type, const char* field)
{
    const TypeDesc* t = engineTypes.Get(type);
    std::uint32_t offset = 0;
    return t && t->Find(field, offset) ? offset : 0;
}

// --- keepAmmo ---

void HookSetUsageCount(Word item, Word ability, Word count, Word sprite)
{
    std::uint16_t newCount = static_cast<std::uint16_t>(count);
    if (item && sprite && hp::Active(hp::kKeepAmmo) && hp::FireBool(hp::kKeepAmmo, [&](lua_State* L) {
            PushObject(L, sprite, engineTypes.Get("CGameSprite"));
            PushObject(L, item, engineTypes.Get("CItem"));
            return 2;
        }))
        newCount = static_cast<std::uint16_t>(newCount + 1);  // the count Swing read: nothing used up
    reinterpret_cast<void (*)(Word, Word, Word)>(g_setUsageCount)(item, ability, newCount);
}

bool InstallKeepAmmo(std::string& why)
{
    const Word site = Sym(kAmmoSite);
    g_setUsageCount = Sym(kSetUsageCount);
    if (!site || !g_setUsageCount) {
        why = "site not in the engine description";
        return false;
    }
    const auto* code = reinterpret_cast<const std::uint8_t*>(site);
    if (std::memcmp(code - sizeof(kAmmoBefore), kAmmoBefore, sizeof(kAmmoBefore)) != 0 ||
        std::memcmp(code + 5, kAmmoAfter, sizeof(kAmmoAfter)) != 0) {
        why = "unexpected code around the call (patched by something else?)";
        return false;
    }
    // mov <4th argument>, <attacker register> ; jmp qword ptr [rip+0] ; <HookSetUsageCount>
    auto* thunk = static_cast<std::uint8_t*>(platform::AllocExecNear(site, 32));
    if (!thunk) {
        why = "no executable memory";
        return false;
    }
    std::memcpy(thunk, kSpriteToArg4, sizeof(kSpriteToArg4));
    const std::uint8_t jmpAbs[6] = {0xFF, 0x25, 0, 0, 0, 0};
    std::memcpy(thunk + sizeof(kSpriteToArg4), jmpAbs, sizeof(jmpAbs));
    const auto target = reinterpret_cast<std::uint64_t>(&HookSetUsageCount);
    std::memcpy(thunk + sizeof(kSpriteToArg4) + sizeof(jmpAbs), &target, 8);
    if (!HookCallSite(site, g_setUsageCount, thunk)) {
        why = "the call does not go to CItem::SetUsageCount (patched by something else?)";
        return false;
    }
    return true;
}

// --- groundMoveClick ---

int GameState()
{
    if (!g_chitin || !g_gameOffset || !g_stateOffset)
        return -1;
    const Word chitin = *reinterpret_cast<const Word*>(g_chitin);
    const Word game = chitin ? *reinterpret_cast<const Word*>(chitin + g_gameOffset) : 0;
    return game ? *reinterpret_cast<const std::int16_t*>(game + g_stateOffset) : -1;
}

void HookClickGround(Word area, Word point)
{
    if (area && point && hp::Active(hp::kGroundMoveClick) && GameState() == 0) {
        const auto* pt = reinterpret_cast<const std::int32_t*>(point);
        hp::FireVoid(hp::kGroundMoveClick, [&](lua_State* L) {
            PushObject(L, area, engineTypes.Get("CGameArea"));
            lua.pushinteger(L, pt[0]);
            lua.pushinteger(L, pt[1]);
            return 3;
        });
    }
    reinterpret_cast<void (*)(Word, Word)>(g_clickGround)(area, point);
}

bool InstallGroundMoveClick(std::string& why)
{
    g_clickGround = Sym(kClickGround);
    g_chitin = Sym("g_pBaldurChitin");
    g_gameOffset = FieldOffset("CBaldurChitin", "m_pObjectGame");
    g_stateOffset = FieldOffset("CInfGame", "m_nState");
    const auto calls = engineTypes.CallSitesOf(kClickGround);
    Word jumps[2] = {Sym(kClickGroundJmp[0]), Sym(kClickGroundJmp[1])};
    if (!g_clickGround || !g_chitin || !g_gameOffset || !g_stateOffset || calls.empty() || !jumps[0] || !jumps[1]) {
        why = "function, call sites or fields missing from the engine description";
        return false;
    }
    // All-or-nothing: every caller must still reach the function directly.
    const auto reaches = [](Word s, std::uint8_t op) {
        const auto* code = reinterpret_cast<const std::uint8_t*>(s);
        std::int32_t rel;
        std::memcpy(&rel, code + 1, 4);
        return code[0] == op && s + 5 + rel == g_clickGround;
    };
    for (std::uint32_t s : calls)
        if (!reaches(EngineImageBase() + s, 0xE8)) {
            why = "a call site is patched by something else";
            return false;
        }
    for (Word s : jumps)
        if (!reaches(s, 0xE9)) {
            why = "a tail jump is patched by something else";
            return false;
        }
    const auto* hook = reinterpret_cast<const void*>(&HookClickGround);
    for (std::uint32_t s : calls)
        g_clickSites += HookCallSite(EngineImageBase() + s, g_clickGround, hook) ? 1 : 0;
    for (Word s : jumps)
        g_clickSites += HookJumpSite(s, g_clickGround, hook) ? 1 : 0;
    if (g_clickSites != static_cast<int>(calls.size()) + 2)
        Log("Native hook groundMoveClick: only %d of %d sites hooked", g_clickSites, static_cast<int>(calls.size()) + 2);
    return g_clickSites > 0;
}

// --- deathDrop (SadoEE #13 keep gear) ---

Word g_dropInventory = 0;

void HookDeathDropInventory(Word sprite, Word a1, Word a2)
{
    if (sprite && hp::Active(hp::kDeathDrop) && hp::FireBool(hp::kDeathDrop, [&](lua_State* L) {
            PushObject(L, sprite, engineTypes.Get("CGameSprite"));
            return 1;
        }))
        return;  // a listener keeps the inventory on the corpse
    reinterpret_cast<void (*)(Word, Word, Word)>(g_dropInventory)(sprite, a1, a2);
}

bool InstallSimpleCall(const char* siteName, const char* targetName, Word& target, const void* hook, std::string& why)
{
    const Word site = Sym(siteName);
    target = Sym(targetName);
    if (!site || !target) {
        why = "site not in the engine description";
        return false;
    }
    if (!HookCallSite(site, target, hook)) {
        why = "the call site holds other code (patched by something else?)";
        return false;
    }
    return true;
}

bool InstallDeathDrop(std::string& why)
{
    return InstallSimpleCall("IEX_Site_DeathDropInventory", "_ZN11CGameSprite13DropInventoryEhi", g_dropInventory,
                             reinterpret_cast<const void*>(&HookDeathDropInventory), why);
}

// --- respecGear (SadoEE camp respec): CompleteCharacterSkills gives no starting gold / weapon while a flag is set ---

Word g_respecFlag = 0, g_startingGold = 0, g_startWeapon = 0;
constexpr std::uint32_t kGoldOffset = 0x574;  // CGameSprite gold (both builds: CompleteCharacterSkills stores there)

bool RespecActive()
{
    return g_respecFlag && *reinterpret_cast<const std::uint8_t*>(g_respecFlag) != 0;
}

Word HookStartingGold(Word rules, Word sprite)
{
    if (RespecActive() && sprite)  // the gold the character has stays
        return static_cast<Word>(static_cast<std::uint32_t>(*reinterpret_cast<const std::int32_t*>(sprite + kGoldOffset)));
    return reinterpret_cast<Word (*)(Word, Word)>(g_startingGold)(rules, sprite);
}

#ifdef _WIN32
// MSVC: the CResRef comes back through a hidden pointer (rdx), the class is in r8b.
Word HookStartWeapon(Word rules, Word out, Word cls)
{
    if (RespecActive() && out) {
        std::memset(reinterpret_cast<void*>(out), 0, 8);  // "": no starting weapon
        return out;
    }
    return reinterpret_cast<Word (*)(Word, Word, Word)>(g_startWeapon)(rules, out, cls);
}
#else
// GCC: the 8-byte CResRef comes back in rax.
Word HookStartWeapon(Word rules, Word cls)
{
    if (RespecActive())
        return 0;
    return reinterpret_cast<Word (*)(Word, Word)>(g_startWeapon)(rules, cls);
}
#endif

bool InstallRespecGear(std::string& why)
{
    return InstallSimpleCall("IEX_Site_SkillsStartingGold", "_ZNK11CRuleTables15GetStartingGoldEP11CGameSprite",
                             g_startingGold, reinterpret_cast<const void*>(&HookStartingGold), why) &&
           InstallSimpleCall("IEX_Site_SkillsStartWeapon", "_ZNK11CRuleTables14GetStartWeaponEh", g_startWeapon,
                             reinterpret_cast<const void*>(&HookStartWeapon), why);
}

// --- campMarker / campSameArea (SadoEE #10 camp) ---

Word g_campFlag = 0, g_markerPosition = 0, g_stopWorldMap = 0;

void HookMarkerPosition(Word worldMap, Word point)
{
    reinterpret_cast<void (*)(Word, Word)>(g_markerPosition)(worldMap, point);
    if (point && g_campFlag && *reinterpret_cast<const std::uint8_t*>(g_campFlag) != 0) {
        auto* pt = reinterpret_cast<std::int32_t*>(point);
        pt[0] = pt[1] = -20000;  // off the map: the party marker is not drawn
    }
}

void SameAreaClicked()
{
    if (hp::Active(hp::kCampSameArea))
        hp::FireVoid(hp::kCampSameArea, [](lua_State*) { return 0; });
}

bool InstallCampMarker(std::string& why)
{
    return InstallSimpleCall("IEX_Site_WorldMapMarker", "_ZN15CScreenWorldMap17GetMarkerPositionER6CPoint",
                             g_markerPosition, reinterpret_cast<const void*>(&HookMarkerPosition), why);
}

#ifdef _WIN32
// The je to the same-area close block is retargeted to a fixed thunk: call SameAreaClicked, then the close block
// (only rsi = this is live there; rsp is 16-aligned in the function body).
bool InstallCampSameArea(std::string& why)
{
    const Word je = Sym("IEX_Site_WorldMapSameAreaJe"), close = Sym("IEX_Site_WorldMapSameAreaClose");
    if (!je || !close) {
        why = "site not in the engine description";
        return false;
    }
    const auto* code = reinterpret_cast<const std::uint8_t*>(je);
    std::int32_t rel;
    std::memcpy(&rel, code + 2, 4);
    if (code[0] != 0x0F || code[1] != 0x84 || je + 6 + rel != close || code[-3] != 0x45 || code[-2] != 0x3B ||
        code[-1] != 0xC4) {
        why = "unexpected code at the same-area test (patched by something else?)";
        return false;
    }
    auto* t = static_cast<std::uint8_t*>(platform::AllocExecNear(je, 48));
    if (!t) {
        why = "no executable memory";
        return false;
    }
    const std::uint8_t body[] = {
        0x48, 0x83, 0xEC, 0x20,              // sub rsp, 0x20
        0xFF, 0x15, 0x12, 0x00, 0x00, 0x00,  // call [rip+0x12] -> t+28
        0x48, 0x83, 0xC4, 0x20,              // add rsp, 0x20
        0xFF, 0x25, 0x00, 0x00, 0x00, 0x00,  // jmp [rip] -> t+20
    };
    std::memcpy(t, body, sizeof(body));
    const std::uint64_t closeAbs = close, fn = reinterpret_cast<std::uint64_t>(&SameAreaClicked);
    std::memcpy(t + 20, &closeAbs, 8);
    std::memcpy(t + 28, &fn, 8);
    const std::int64_t newRel = reinterpret_cast<std::int64_t>(t) - static_cast<std::int64_t>(je + 6);
    if (newRel < INT32_MIN || newRel > INT32_MAX) {
        why = "thunk out of range";
        return false;
    }
    const auto rel32 = static_cast<std::int32_t>(newRel);
    return platform::PatchCode(reinterpret_cast<void*>(je + 2), &rel32, 4);
}
#else
void HookStopWorldMapSameArea(Word worldMap, Word arg)
{
    SameAreaClicked();
    reinterpret_cast<void (*)(Word, Word)>(g_stopWorldMap)(worldMap, arg);
}

bool InstallCampSameArea(std::string& why)
{
    return InstallSimpleCall("IEX_Site_WorldMapSameAreaCall", "_ZN15CScreenWorldMap12StopWorldMapEh", g_stopWorldMap,
                             reinterpret_cast<const void*>(&HookStopWorldMapSameArea), why);
}
#endif

// --- Engine functions callable from Lua (integers in, one integer out: the shape of mods' own call stubs) ---

Word ArgW(lua_State* L, int i)
{
    return static_cast<Word>(lua.tointegerx(L, i, nullptr));
}

int ArgI(lua_State* L, int i)
{
    return static_cast<int>(lua.tointegerx(L, i, nullptr));
}

Word Fn(lua_State* L, const char* name)
{
    const Word f = Sym(name);
    if (!f)
        LuaError(L, "engine function %s not in the engine description", name);
    return f;
}

int PushResult(lua_State* L, lua_Integer value)
{
    lua.pushinteger(L, value);
    return 1;
}

// (screen, sprite, newClass, flag): CScreenCreateChar::RemoveAbilities
int LuaRemoveAbilities(lua_State* L)
{
    using F = void (*)(Word, Word, int, int);
    reinterpret_cast<F>(Fn(L, "_ZN17CScreenCreateChar15RemoveAbilitiesEP11CGameSpriteii"))(ArgW(L, 1), ArgW(L, 2),
                                                                                         ArgI(L, 3), ArgI(L, 4));
    return PushResult(L, 0);
}

// (game, portrait, slot, CItem** hand, uint* err, maxCount, uchar, sprite): CInfGame::SwapItemPersonal
int LuaSwapItemPersonal(lua_State* L)
{
    using F = unsigned (*)(Word, short, short, Word, Word, unsigned short, unsigned char, Word);
    const unsigned r = reinterpret_cast<F>(Fn(L, "_ZN8CInfGame16SwapItemPersonalEssRP5CItemRjthP11CGameSprite"))(
        ArgW(L, 1), static_cast<short>(ArgI(L, 2)), static_cast<short>(ArgI(L, 3)), ArgW(L, 4), ArgW(L, 5),
        static_cast<unsigned short>(ArgI(L, 6)), static_cast<unsigned char>(ArgI(L, 7)), ArgW(L, 8));
    return PushResult(L, r);
}

// Party Stash (M_PSTASH.lua PStash_Eng_*): the calls its Windows stubs make, same arguments.
int LuaAddItemToStore(lua_State* L)  // (game, CResRef*, CItem*, uint* err) -> bool
{
    using F = unsigned char (*)(Word, Word, Word, Word);
    return PushResult(L, reinterpret_cast<F>(Fn(L, "_ZN8CInfGame14AddItemToStoreERK7CResRefP5CItemRj"))(
                             ArgW(L, 1), ArgW(L, 2), ArgW(L, 3), ArgW(L, 4)));
}

int LuaSwapItemPersonalInventory(lua_State* L)  // (game, portrait, CItem**, slot, uint* err, max, uchar, int, int)
{
    using F = unsigned (*)(Word, short, Word, short, Word, unsigned short, unsigned char, int, int);
    return PushResult(L, reinterpret_cast<F>(Fn(L, "_ZN8CInfGame25SwapItemPersonalInventoryEsRP5CItemsRjthii"))(
                             ArgW(L, 1), static_cast<short>(ArgI(L, 2)), ArgW(L, 3), static_cast<short>(ArgI(L, 4)),
                             ArgW(L, 5), static_cast<unsigned short>(ArgI(L, 6)),
                             static_cast<unsigned char>(ArgI(L, 7)), ArgI(L, 8), ArgI(L, 9)));
}

int LuaAddDisposableItem(lua_State* L)  // (game, CItem*)
{
    reinterpret_cast<void (*)(Word, Word)>(Fn(L, "_ZN8CInfGame17AddDisposableItemEP5CItem"))(ArgW(L, 1), ArgW(L, 2));
    return PushResult(L, 0);
}

int LuaDemandServerStore(lua_State* L)  // (game, CResRef*, int)
{
    using F = Word (*)(Word, Word, int);
    return PushResult(L, static_cast<lua_Integer>(reinterpret_cast<F>(
                             Fn(L, "_ZN8CInfGame17DemandServerStoreERK7CResRefi"))(ArgW(L, 1), ArgW(L, 2), ArgI(L, 3))));
}

int LuaGetServerStore(lua_State* L)  // (game, CResRef*) -> CStore*
{
    using F = Word (*)(Word, Word);
    return PushResult(L, static_cast<lua_Integer>(
                             reinterpret_cast<F>(Fn(L, "_ZN8CInfGame14GetServerStoreERK7CResRef"))(ArgW(L, 1), ArgW(L, 2))));
}

int LuaReleaseServerStore(lua_State* L)  // (game, CResRef*)
{
    reinterpret_cast<void (*)(Word, Word)>(Fn(L, "_ZN8CInfGame18ReleaseServerStoreERK7CResRef"))(ArgW(L, 1), ArgW(L, 2));
    return PushResult(L, 0);
}

int LuaTakeItemFromStore(lua_State* L)  // (game, CResRef* bag, CResRef* item, count) -> number taken
{
    using F = unsigned short (*)(Word, Word, Word, int);
    return PushResult(L, reinterpret_cast<F>(Fn(L, "_ZN8CInfGame17TakeItemFromStoreERK7CResRefS2_i"))(
                             ArgW(L, 1), ArgW(L, 2), ArgW(L, 3), ArgI(L, 4)));
}

// (sprite): what the engine does after an inventory change: set the re-evaluation flag, ProcessEffectList(1).
int LuaProcessEffectList(lua_State* L)
{
    const Word sprite = ArgW(L, 1);
    std::uint64_t flag = 0;
    if (!sprite || !engineTypes.Const("IEX.native.reprocessFlag", flag))
        LuaError(L, "IEX_Eng_ProcessEffectList: sprite or IEX.native.reprocessFlag missing");
    *reinterpret_cast<std::int32_t*>(sprite + flag) = 1;
    reinterpret_cast<void (*)(Word, int)>(Fn(L, "_ZN11CGameSprite17ProcessEffectListEi"))(sprite, 1);
    return PushResult(L, 0);
}

// --- Lua ---

// --- Hook-point registry (hook_points.h): installers and availability of the points above and of
// native_hooks_sado.cpp's ---

bool InstKeepAmmo(std::string& why, Word, Word) { return InstallKeepAmmo(why); }
bool InstGroundMoveClick(std::string& why, Word, Word)
{
    const bool ok = InstallGroundMoveClick(why);
    hp::SetSites(hp::kGroundMoveClick, g_clickSites);
    return ok;
}
bool InstDeathDrop(std::string& why, Word, Word) { return InstallDeathDrop(why); }
bool InstRespecGear(std::string& why, Word flag, Word)
{
    g_respecFlag = flag;
    return InstallRespecGear(why);
}
bool InstCampMarker(std::string& why, Word flag, Word)
{
    g_campFlag = flag;
    return InstallCampMarker(why);
}
bool InstCampSameArea(std::string& why, Word, Word) { return InstallCampSameArea(why); }
bool InstGroundContainer(std::string& why, Word, Word) { return InstallGroundContainer(why); }
bool InstSmallFootprint(std::string& why, Word mode, Word) { return InstallSmallFootprint(why, mode); }
bool InstContainerMarker(std::string& why, Word color, Word marker) { return InstallContainerMarker(why, color, marker); }
bool InstLastingModes(std::string& why, Word, Word) { return InstallLastingModes(why); }
bool InstFindTrapsButton(std::string& why, Word, Word) { return InstallFindTrapsButton(why); }
bool InstStealthReveals(std::string& why, Word, Word) { return InstallStealthReveals(why); }

bool AvKeepAmmo() { return Sym(kAmmoSite) && Sym(kSetUsageCount); }
bool AvGroundMoveClick()
{
    return Sym(kClickGround) && Sym(kClickGroundJmp[0]) && Sym(kClickGroundJmp[1]) &&
           !engineTypes.CallSitesOf(kClickGround).empty();
}
bool AvDeathDrop() { return Sym("IEX_Site_DeathDropInventory") != 0; }
bool AvRespecGear() { return Sym("IEX_Site_SkillsStartWeapon") != 0; }
bool AvCampMarker() { return Sym("IEX_Site_WorldMapMarker") != 0; }
#ifdef _WIN32
bool AvCampSameArea() { return Sym("IEX_Site_WorldMapSameAreaJe") != 0; }
#else
bool AvCampSameArea() { return Sym("IEX_Site_WorldMapSameAreaCall") != 0; }
#endif

void RegisterPoints()
{
    hp::SetInstaller(hp::kKeepAmmo, &InstKeepAmmo, &AvKeepAmmo);
    hp::SetInstaller(hp::kGroundMoveClick, &InstGroundMoveClick, &AvGroundMoveClick);
    hp::SetInstaller(hp::kDeathDrop, &InstDeathDrop, &AvDeathDrop);
    hp::SetInstaller(hp::kRespecGear, &InstRespecGear, &AvRespecGear);
    hp::SetInstaller(hp::kCampMarker, &InstCampMarker, &AvCampMarker);
    hp::SetInstaller(hp::kCampSameArea, &InstCampSameArea, &AvCampSameArea);
    hp::SetInstaller(hp::kGroundContainer, &InstGroundContainer, &SadoGroundContainerAvailable);
    hp::SetInstaller(hp::kSmallFootprint, &InstSmallFootprint, &SadoSmallFootprintAvailable);
    hp::SetInstaller(hp::kContainerMarker, &InstContainerMarker, &SadoContainerMarkerAvailable);
    hp::SetInstaller(hp::kLastingModes, &InstLastingModes, &SadoLastingModesAvailable);
    hp::SetInstaller(hp::kFindTrapsButton, &InstFindTrapsButton, &SadoFindTrapsButtonAvailable);
    hp::SetInstaller(hp::kStealthReveals, &InstStealthReveals, &SadoStealthRevealsAvailable);
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

void OpenLuaNativeHooks(lua_State* L)
{
    g_L = L;
    RegisterPoints();
    hp::OpenLua(L);
    Register(L, "IEX_Eng_RemoveAbilities", LuaRemoveAbilities);
    Register(L, "IEX_Eng_SwapItemPersonal", LuaSwapItemPersonal);
    Register(L, "IEX_Eng_AddItemToStore", LuaAddItemToStore);
    Register(L, "IEX_Eng_SwapItemPersonalInventory", LuaSwapItemPersonalInventory);
    Register(L, "IEX_Eng_AddDisposableItem", LuaAddDisposableItem);
    Register(L, "IEX_Eng_DemandServerStore", LuaDemandServerStore);
    Register(L, "IEX_Eng_GetServerStore", LuaGetServerStore);
    Register(L, "IEX_Eng_ReleaseServerStore", LuaReleaseServerStore);
    Register(L, "IEX_Eng_TakeItemFromStore", LuaTakeItemFromStore);
    Register(L, "IEX_Eng_ProcessEffectList", LuaProcessEffectList);
    OpenLuaSadoFunctions(L);
}

namespace nh {

Word Sym(const char* name)
{
    return iex::Sym(name);
}

std::uint32_t FieldOffset(const char* type, const char* field)
{
    return iex::FieldOffset(type, field);
}

lua_State* State()
{
    return g_L;
}

} // namespace nh

} // namespace iex
