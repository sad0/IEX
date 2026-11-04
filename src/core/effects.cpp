// Effects with opcodes the engine does not know (EEex opcodes 400-409 used by mods, and the engine's own gaps).
//
// CGameEffect::DecodeEffect has no case for them and crashes (it writes to NULL+0x150), which makes saves from
// modded games unloadable. IEX decodes them as an "inert" base CGameEffect: it keeps every field, does nothing
// when applied, expires on its normal duration and is saved back unchanged. Mods read them by m_effectId.
#include "effects.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"

#include <cstring>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kDecodeEffect = "_ZN11CGameEffect12DecodeEffectEP14Item_effect_stRK6CPointiS4_i";
constexpr const char* kBaseCtor = "_ZN11CGameEffectC1EP14Item_effect_stRK6CPointiS2_ii";
constexpr const char* kGetItemEffect = "_ZN11CGameEffect13GetItemEffectEv";
constexpr const char* kCopyFromBase = "_ZN11CGameEffect12CopyFromBaseEP15CGameEffectBase";
constexpr const char* kBaseVtable = "_ZTV11CGameEffect";

// CGameEffect layout bits used here (identical on both builds, see docs/EFFECTS_DECODE.md).
constexpr std::size_t kEffectSize = 0x158;
constexpr std::size_t kItemDiceSize = 0x20;   // Item_effect_st: -1 is normalized to 0 by DecodeEffect
constexpr std::size_t kArg5 = 0x150;          // stored by DecodeEffect's common tail
constexpr std::size_t kGameTime = 0x6c;       // same
constexpr std::size_t kSourcePoint = 0x80;    // CPoint, used by Copy
constexpr std::size_t kTargetPoint = 0x88;
constexpr std::size_t kSourceId = 0x110;
constexpr std::size_t kBaseRecord = 0x8;      // CGameEffectBase (the saved 0x108-byte record)

template <typename T>
T Engine(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

std::vector<Word> g_inertVtable;  // header qwords + slots
Word g_inertVtablePoint = 0;      // address point stored in objects

void* EngineAlloc(std::size_t size) { return Engine<void* (*)(std::size_t)>("SDL_malloc")(size); }
void EngineFree(void* p) { Engine<void (*)(void*)>("SDL_free")(p); }

std::int32_t GameTime()
{
    static const TypeDesc* chitin = engineTypes.Get("CBaldurChitin");
    static const TypeDesc* game = engineTypes.Get("CInfGame");
    std::uint32_t gameOffset = 0, timeOffset = 0;
    const std::uint32_t chitinRva = engineTypes.Symbol("g_pBaldurChitin");
    if (!chitin || !game || !chitinRva || !chitin->Find("m_pObjectGame", gameOffset) || !game->Find("m_worldTime", timeOffset))
        return 0;
    const Word chitinPtr = *reinterpret_cast<const Word*>(EngineImageBase() + chitinRva);
    const Word gamePtr = chitinPtr ? *reinterpret_cast<const Word*>(chitinPtr + gameOffset) : 0;
    return gamePtr ? *reinterpret_cast<const std::int32_t*>(gamePtr + timeOffset) : 0;
}

bool KnownOpcode(std::uint16_t op)
{
    return op < 368 && !(op >= 347 && op <= 359) && op != 364;
}

// Base ctor: (this, Item_effect_st*, CPoint const* source, int sourceId, CPoint target by value, int flag, int arg6).
// The 8-byte CPoint by value travels in one integer slot on both ABIs.
Word Construct(Word item, Word source, Word sourceId, std::uint64_t target, Word flag)
{
    auto* p = static_cast<std::uint8_t*>(EngineAlloc(kEffectSize));
    std::memset(p, 0, kEffectSize);
    Engine<Word (*)(Word, Word, Word, Word, std::uint64_t, Word, Word)>(kBaseCtor)(
        reinterpret_cast<Word>(p), item, source, sourceId, target, flag, static_cast<Word>(-1));
    std::memcpy(p, &g_inertVtablePoint, sizeof(Word));
    return reinterpret_cast<Word>(p);
}

// Copy slot of the inert vtable (the base class returns NULL there, and CheckAdd does not expect that).
Word InertCopy(Word self)
{
    const Word item = Engine<Word (*)(Word)>(kGetItemEffect)(self);
    std::uint64_t target;
    std::memcpy(&target, reinterpret_cast<const void*>(self + kTargetPoint), 8);
    const Word copy = Construct(item, self + kSourcePoint, *reinterpret_cast<const std::int32_t*>(self + kSourceId),
                                target, 1);
    EngineFree(reinterpret_cast<void*>(item));
    Engine<void (*)(Word, Word)>(kCopyFromBase)(copy, self + kBaseRecord);
    return copy;
}

Word HookDecodeEffect(Word item, Word source, Word sourceId, Word target, Word arg5)
{
    const auto opcode = *reinterpret_cast<const std::uint16_t*>(item);
    if (KnownOpcode(opcode) || !g_inertVtablePoint)
        return Engine<Word (*)(Word, Word, Word, Word, Word)>(kDecodeEffect)(item, source, sourceId, target, arg5);

    auto* dice = reinterpret_cast<std::int32_t*>(item + kItemDiceSize);
    if (*dice == -1)
        *dice = 0;
    std::uint64_t targetPoint;
    std::memcpy(&targetPoint, reinterpret_cast<const void*>(target), 8);
    const Word effect = Construct(item, source, sourceId, targetPoint, 0);
    *reinterpret_cast<std::int32_t*>(effect + kArg5) = static_cast<std::int32_t>(arg5);
    *reinterpret_cast<std::int32_t*>(effect + kGameTime) = GameTime();
    return effect;
}

// Copies the base vtable (description: symbol _ZTV11CGameEffect = start of the vtable object, plus the
// number of header qwords before the address point, the slot count and the Copy slot offset).
bool BuildInertVtable()
{
    std::uint64_t header = 0, slots = 0, copySlot = 0;
    const std::uint32_t rva = engineTypes.Symbol(kBaseVtable);
    if (!rva || !engineTypes.Const("CGameEffect.vtable.header", header) ||
        !engineTypes.Const("CGameEffect.vtable.slots", slots) || !engineTypes.Const("CGameEffect.vtable.copy", copySlot))
        return false;
    const auto* source = reinterpret_cast<const Word*>(EngineImageBase() + rva);
    g_inertVtable.assign(source, source + header + slots);
    g_inertVtable[header + copySlot / sizeof(Word)] = reinterpret_cast<Word>(&InertCopy);
    g_inertVtablePoint = reinterpret_cast<Word>(g_inertVtable.data() + header);
    return true;
}

} // namespace

std::uintptr_t DecodeEffectAny(std::uintptr_t item, std::uintptr_t source, std::uintptr_t sourceId,
                               std::uintptr_t target, std::uintptr_t arg5)
{
    return HookDecodeEffect(item, source, sourceId, target, arg5);
}

bool SetInertSlot(std::size_t slotOffset, const void* fn)
{
    std::uint64_t header = 0;
    if (!g_inertVtablePoint || !engineTypes.Const("CGameEffect.vtable.header", header))
        return false;
    g_inertVtable[header + slotOffset / sizeof(Word)] = reinterpret_cast<Word>(fn);
    return true;
}

std::uintptr_t GetInertSlot(std::size_t slotOffset)
{
    std::uint64_t header = 0;
    if (!g_inertVtablePoint || !engineTypes.Const("CGameEffect.vtable.header", header))
        return 0;
    return g_inertVtable[header + slotOffset / sizeof(Word)];
}

void InstallEffectHooks()
{
    if (!Engine<void*>(kBaseCtor) || !Engine<void*>(kGetItemEffect) || !Engine<void*>(kCopyFromBase) ||
        !Engine<void*>("SDL_malloc") || !Engine<void*>("SDL_free") || !BuildInertVtable()) {
        Log("Unknown-opcode effects: description incomplete, hook skipped");
        return;
    }
    const std::uint32_t decode = engineTypes.Symbol(kDecodeEffect);
    int hooked = 0;
    const auto sites = engineTypes.CallSitesOf(kDecodeEffect);
    for (std::uint32_t site : sites)
        hooked += HookCallSite(EngineImageBase() + site, EngineImageBase() + decode,
                               reinterpret_cast<const void*>(&HookDecodeEffect)) ? 1 : 0;
    Log("Unknown-opcode effects: %d/%zu DecodeEffect call sites", hooked, sites.size());
}

} // namespace iex
