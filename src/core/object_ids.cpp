// Object ids that never run out (both builds, from the binaries; no EEex code).
//
// CGameObjectArray (statics): id = slot << 16 | key, entry = {i16 key, CGameObject*} per slot (m_pArray),
// m_maxArrayIndex = highest slot handed out, m_nextObjectId = next key and also the validity limit (GetShare accepts
// key < m_nextObjectId), m_deletedListHead = one slot Add takes before growing m_maxArrayIndex, m_nArray = 32767.
// CInfGame::DestroyGame starts both counters at 2000. Every Add takes a new key and, unless m_deletedListHead is set,
// a new slot: Delete only records a freed slot once the key passed 15000, and above 15000 Add recycles slots < 2000
// for two object types only. A long session (area loads, summons, spells) therefore grows both counters until
// m_maxArrayIndex reaches m_nArray: Add logs "Too many objects!" and gives the object id -1 (writing slot -1, before
// the table), or the i16 key wraps negative and GetShare rejects every object. The first new creature then enters
// its area with id -1: CGameArea::SortLists only skips stale ids (GetShare result 2), the -1 (result 3) gives a null
// object and an access violation at SortLists+0x24f (reading object + 0x48, m_lVertSort empty) or +0x26c (its
// vtable). Seen 2026-11-01 on the BOT's 10-member EET party at a world-map travel (LeaveAreaLUA -> LoadArea ->
// SortLists), after hours of play; one AR0500 load alone costs ~330 Adds.
//
// IEX (every Add already goes through the call-site hook of event_hooks.cpp): before Add, a free slot (entry key -1)
// below m_maxArrayIndex goes into m_deletedListHead and m_nextObjectId is set to IEX's key, which cycles 2000..14999;
// after Add, m_nextObjectId is pinned at 15000 (the validity limit, below the engine's "critical" paths). Slots and
// keys are reused, so the counters stay bounded; a stale id is still told apart unless its slot gets the very same key
// back (13000 Adds later). While Add runs, m_nextObjectId is the new key + 1: the rest of Add (single player) only
// copies AI types. Multiplayer sessions keep the engine's own ids.
#include "object_ids.h"

#include "engine_types.h"
#include "event_hooks.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr int kKeyFirst = 2000;   // DestroyGame's start value for both counters
constexpr int kKeyLimit = 15000;  // Add and Delete switch to their "critical" paths above it
constexpr int kSlotScan = 512;    // entries looked at per Add before the engine grows m_maxArrayIndex

struct ObjectIds {
    std::int16_t* nArray = nullptr;
    std::int16_t* maxIndex = nullptr;
    std::int16_t* nextId = nullptr;
    std::int16_t* deletedHead = nullptr;
    Word table = 0;          // m_pArray, 16-byte entries: i16 key (-1 = free), CGameObject*
    const Word* chitin = nullptr;
    Word mpFlag = 0;         // CChitin byte, 1 in a multiplayer session (tested by Add itself)
    bool active = false;
    bool driving = false;    // the running Add uses IEX's slot and key
    int depth = 0;
    int key = kKeyFirst;     // next key IEX hands out
    int cursor = kKeyFirst;  // slot scan position
    int slotGiven = -1;      // slot put into m_deletedListHead for the running Add
    std::uint64_t adds = 0, reused = 0, wraps = 0, full = 0;
};
ObjectIds g_ids;

Word Sym(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? EngineImageBase() + rva : 0;
}

std::int16_t EntryKey(int slot)
{
    std::int16_t v;
    std::memcpy(&v, reinterpret_cast<const void*>(g_ids.table + static_cast<Word>(slot) * 16), sizeof(v));
    return v;
}

int FindFreeSlot(int maxIndex, int limit)
{
    const int span = maxIndex - kKeyFirst + 1;
    if (span <= 0)
        return -1;
    if (g_ids.cursor < kKeyFirst || g_ids.cursor > maxIndex)
        g_ids.cursor = kKeyFirst;
    for (int i = 0; i < limit && i < span; ++i) {
        const int slot = g_ids.cursor;
        g_ids.cursor = slot >= maxIndex ? kKeyFirst : slot + 1;
        if (EntryKey(slot) == -1)
            return slot;
    }
    return -1;
}

bool Multiplayer()
{
    const Word chitin = g_ids.chitin ? *g_ids.chitin : 0;
    return chitin && *reinterpret_cast<const std::uint8_t*>(chitin + g_ids.mpFlag) == 1;
}

// IEX_ObjectIdInfo() -> table: active, adds (Adds IEX drove), reused (slots given back), wraps (key cycles),
// nextKey, maxIndex / nextObjectId / deletedHead (engine statics, 0 when not resolved).
int LuaObjectIdInfo(lua_State* L)
{
    const ObjectIds& d = g_ids;
    lua.createtable(L, 0, 8);
    lua.pushboolean(L, d.active);
    lua.setfield(L, -2, "active");
    const auto set = [L](const char* k, long long v) {
        lua.pushinteger(L, v);
        lua.setfield(L, -2, k);
    };
    set("adds", static_cast<long long>(d.adds));
    set("reused", static_cast<long long>(d.reused));
    set("wraps", static_cast<long long>(d.wraps));
    set("nextKey", d.key);
    set("maxIndex", d.maxIndex ? *d.maxIndex : 0);
    set("nextObjectId", d.nextId ? *d.nextId : 0);
    set("deletedHead", d.deletedHead ? *d.deletedHead : 0);
    return 1;
}

} // namespace

void InstallObjectIds()
{
    if (const char* env = std::getenv("IEX_OBJECT_IDS"); env && std::strcmp(env, "0") == 0) {
        Log("Object ids: IEX_OBJECT_IDS=0, the engine's own ids are kept");
        return;
    }
    const auto s16 = [](const char* name) { return reinterpret_cast<std::int16_t*>(Sym(name)); };
    g_ids.nArray = s16("_ZN16CGameObjectArray8m_nArrayE");
    g_ids.maxIndex = s16("_ZN16CGameObjectArray15m_maxArrayIndexE");
    g_ids.nextId = s16("_ZN16CGameObjectArray14m_nextObjectIdE");
    g_ids.deletedHead = s16("_ZN16CGameObjectArray17m_deletedListHeadE");
    g_ids.table = Sym("_ZN16CGameObjectArray8m_pArrayE");
    g_ids.chitin = reinterpret_cast<const Word*>(Sym("g_pChitin"));
    std::uint64_t mp = 0;
    engineTypes.Const("IEX.objid.mpFlag", mp);
    g_ids.mpFlag = static_cast<Word>(mp);
    // The statics hold 0 before CInfGame is built, 32767 = m_nArray after.
    const bool ok = g_ids.nArray && g_ids.maxIndex && g_ids.nextId && g_ids.deletedHead && g_ids.table &&
                    g_ids.chitin && g_ids.mpFlag && ObjectArrayAddHooked() &&
                    (*g_ids.nArray == 0 || *g_ids.nArray == 32767);
    g_ids.active = ok;
    Log("Object ids (slots and keys reused, no 'Too many objects'): %s",
        ok ? "on" : "engine description incomplete or Add not hooked, engine ids kept");
}

void ObjectIdsBeforeAdd()
{
    ObjectIds& d = g_ids;
    if (!d.active || d.depth++ > 0)
        return;
    d.slotGiven = -1;
    d.driving = !Multiplayer();
    if (!d.driving)
        return;
    const int engineNext = *d.nextId;
    if (engineNext != kKeyLimit) {
        // The engine's own counter: a new session (DestroyGame reset it to 2000) or IEX's first Add.
        d.key = engineNext >= kKeyFirst && engineNext < kKeyLimit ? engineNext : kKeyFirst;
        d.cursor = kKeyFirst;
    }
    const int maxIndex = *d.maxIndex;
    if (*d.deletedHead == -1) {
        int slot = FindFreeSlot(maxIndex, kSlotScan);
        if (slot < 0 && maxIndex + 1 >= *d.nArray - 1)
            slot = FindFreeSlot(maxIndex, maxIndex);  // table about to overflow: look at every slot once
        if (slot >= 0) {
            *d.deletedHead = static_cast<std::int16_t>(slot);
            d.slotGiven = slot;
        } else if (maxIndex + 1 >= *d.nArray - 1 && d.full++ < 5) {
            Log("Object ids: the object table is full (highest slot %d, no free slot)", maxIndex);
        }
    }
    *d.nextId = static_cast<std::int16_t>(d.key);
}

void ObjectIdsAfterAdd()
{
    ObjectIds& d = g_ids;
    if (!d.active || --d.depth > 0 || !d.driving)
        return;
    d.driving = false;
    if (*d.nextId == d.key + 1) {  // Add took the key
        ++d.adds;
        if (d.slotGiven >= 0 && *d.deletedHead == -1)
            ++d.reused;
        if (++d.key >= kKeyLimit) {
            d.key = kKeyFirst;
            if (d.wraps++ < 5)
                Log("Object ids: key cycle %llu done (%llu Adds, %llu slots reused, highest slot %d)",
                    static_cast<unsigned long long>(d.wraps), static_cast<unsigned long long>(d.adds),
                    static_cast<unsigned long long>(d.reused), *d.maxIndex);
        }
    } else if (*d.nextId != d.key) {
        return;  // an engine path IEX does not drive changed the counter: leave it to the engine
    }
    if (d.slotGiven >= 0 && *d.deletedHead == d.slotGiven)
        *d.deletedHead = -1;  // not taken
    d.slotGiven = -1;
    *d.nextId = static_cast<std::int16_t>(kKeyLimit);
}

void OpenLuaObjectIds(lua_State* L)
{
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushboolean(L, g_ids.active);
    lua.setfield(L, -2, "objectIdRecycling");
    lua.settop(L, -2);
    lua.pushcclosure(L, LuaObjectIdInfo, 0);
    lua.setglobal(L, "IEX_ObjectIdInfo");
}

} // namespace iex
