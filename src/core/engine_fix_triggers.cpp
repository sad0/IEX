#include "engine_fix_triggers.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <utility>
#include <vector>

// --- 13. Event triggers (AttackedBy, Heard, ...) with an object function (PartySlot1, NearestEnemyOf, ...) kept the
// creature it named the first time ---
//
// CAICondition::TriggerHolds (and its two copies inlined in CAICondition::Hold on Linux) decodes the script's own
// trigger object in place, then matches it against each pending trigger (CAITrigger::OfType). Decode replaces the
// object functions by the found creature's instance id, so the script keeps that creature for good. Each such Decode
// / OfType pair now decodes a temporary copy, so the object is resolved again on every evaluation, as status triggers
// and NextTriggerObject already do. Objects without object functions (names, IDS fields) keep the in-place decode.
// Current EEex keeps the engine bug (tools/trigtest); this one goes beyond EEex parity.

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kTriggerHolds =
    "_ZN12CAICondition12TriggerHoldsEP10CAITriggerR13CTypedPtrListI8CPtrListS1_EP11CGameAIBase";
constexpr const char* kConditionHold = "_ZN12CAICondition4HoldER13CTypedPtrListI8CPtrListP10CAITriggerEP11CGameAIBase";
constexpr const char* kTriggerOfType = "_ZN10CAITrigger6OfTypeERKS_";
constexpr const char* kObjectDecode = "_ZN13CAIObjectType6DecodeEP11CGameAIBase";
// CAITrigger (both builds): id +0 (i16), param1 +4, object +8 (CAIObjectType, 0x18), flags +0x20 (bit 0: negated).
// CAIObjectType: name CString +0, IDS fields +8..+0xf, instance +0xc, object functions +0x10..+0x14 (first =
// innermost, 0 = none), specific / gender / alignment +0x15..+0x17. OfType reads id, param1 and the object only.
constexpr std::size_t kTriggerObject = 0x8, kTriggerFlags = 0x20, kObjectFunctions = 0x10;

using StringCtor = void (*)(Word*, const char*);
using StringDtor = void (*)(Word*);
using StringAssign = Word (*)(Word*, const Word*);
StringCtor g_stringCtor = nullptr;
StringDtor g_stringDtor = nullptr;
StringAssign g_stringAssign = nullptr;
Word g_decode = 0;  // what the Decode sites called before: IEX's script-object decode or the engine's Decode
Word g_ofType = 0;
thread_local Word t_deferredObject = 0, t_deferredCaller = 0;

Word Sym(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? EngineImageBase() + rva : 0;
}

Word CallTarget(Word site)
{
    std::int32_t rel;
    std::memcpy(&rel, reinterpret_cast<const void*>(site + 1), 4);
    return site + 5 + static_cast<std::intptr_t>(rel);
}

void FixTriggerDecode(Word object, Word caller)
{
    t_deferredObject = 0;
    if (*reinterpret_cast<const std::uint8_t*>(object + kObjectFunctions) != 0) {
        t_deferredObject = object;  // decoded by the OfType call that follows, on a copy
        t_deferredCaller = caller;
        return;
    }
    reinterpret_cast<void (*)(Word, Word)>(g_decode)(object, caller);
}

bool FixTriggerOfType(Word pending, Word trigger)
{
    const auto ofType = reinterpret_cast<bool (*)(Word, Word)>(g_ofType);
    if (t_deferredObject != trigger + kTriggerObject)
        return ofType(pending, trigger);
    t_deferredObject = 0;
    if (*reinterpret_cast<const std::int16_t*>(pending) != *reinterpret_cast<const std::int16_t*>(trigger))
        return false;  // OfType's own first test, before any decoding
    alignas(16) std::uint8_t copy[0x28] = {};
    const Word temp = reinterpret_cast<Word>(copy);
    std::memcpy(copy, reinterpret_cast<const void*>(trigger), kTriggerObject);
    std::memcpy(copy + kTriggerFlags, reinterpret_cast<const void*>(trigger + kTriggerFlags), 4);
    auto* name = reinterpret_cast<Word*>(temp + kTriggerObject);
    g_stringCtor(name, "");
    g_stringAssign(name, reinterpret_cast<const Word*>(trigger + kTriggerObject));
    std::memcpy(copy + kTriggerObject + 8, reinterpret_cast<const void*>(trigger + kTriggerObject + 8), 0x10);
    reinterpret_cast<void (*)(Word, Word)>(g_decode)(temp + kTriggerObject, t_deferredCaller);
    const bool match = ofType(pending, temp);
    g_stringDtor(name);
    return match;
}

} // namespace

bool InstallEventTriggerObjects()
{
    g_ofType = Sym(kTriggerOfType);
    g_stringCtor = reinterpret_cast<StringCtor>(Sym("_ZN7CStringC1EPKc"));
    g_stringDtor = reinterpret_cast<StringDtor>(Sym("_ZN7CStringD1Ev"));
    g_stringAssign = reinterpret_cast<StringAssign>(Sym("_ZN7CStringaSERKS_"));
    if (!g_ofType || !g_stringCtor || !g_stringDtor || !g_stringAssign || !engineTypes.Symbol(kObjectDecode))
        return false;
    std::vector<Word> decodeSites;  // every engine call of Decode (IEX's script-object hook may have redirected them)
    for (std::uint32_t site : engineTypes.CallSitesOf(kObjectDecode))
        decodeSites.push_back(EngineImageBase() + site);
    // In each function: a Decode call whose next call (within 0x20 bytes) is CAITrigger::OfType. Hold's
    // NextTriggerObject decode (followed by GetShareType) is not one.
    const struct {
        const char* fn;
        std::size_t size;
    } ranges[] = {{kTriggerHolds, 0xc0}, {kConditionHold, 0x340}};
    std::vector<std::pair<Word, Word>> pairs;
    for (const auto& r : ranges) {
        const Word fn = Sym(r.fn);
        if (!fn)
            continue;
        const auto* code = reinterpret_cast<const std::uint8_t*>(fn);
        for (Word d : decodeSites) {
            if (d < fn || d >= fn + r.size)
                continue;
            for (std::size_t i = d - fn + 5; i + 5 <= r.size && i < d - fn + 0x20; ++i) {
                if (code[i] == 0xE8 && CallTarget(fn + i) == g_ofType) {
                    pairs.emplace_back(d, fn + i);
                    break;
                }
            }
        }
    }
    if (pairs.empty())
        return false;
    // The sites may already go to IEX's script-object decode, each through its own thunk when IEX is loaded far from
    // the engine (Linux): any of them reaches the same function.
    g_decode = CallTarget(pairs[0].first);
    int hooked = 0;
    for (const auto& p : pairs) {
        // OfType first: a pair whose Decode hook then fails still decodes in place (the engine's behaviour)
        if (!HookCallSite(p.second, g_ofType, reinterpret_cast<const void*>(&FixTriggerOfType)))
            continue;
        hooked += HookCallSite(p.first, CallTarget(p.first), reinterpret_cast<const void*>(&FixTriggerDecode)) ? 1 : 0;
    }
    if (std::getenv("IEX_FIX_DEBUG"))
        Log("event trigger fix: %d of %zu Decode / OfType pairs hooked", hooked, pairs.size());
    return hooked > 0;
}

} // namespace iex
