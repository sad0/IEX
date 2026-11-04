// Fog of war with any number of viewers (docs/API_SPEC.md, "Fog of war: unlimited viewers").
//
// Engine model (both builds, from the binaries): CVisibilityMap (CGameArea + 0xbb0) holds a u16 per 32x32 tile
// at +0 (count at +8, width/height at +0xc/+0xe) and 15 viewer ids at +0x20. Bit 15 of a tile = explored, any of
// bits 0-14 (VISIBILITY_MASK 0x7fff) = visible now; every reader (creature/door/container/projectile renders,
// CheckLOS, spawning, tooltips, fog and minimap via GetSubTileCode) only tests `tile & 0x7fff`. The writers are
// AddCharacter / UpDate (-> PrivateAddCharacter: OR a u8 mask `1 << slot` along the line-of-sight tree) and
// RemoveCharacter / UpDate (clear that mask in a square box around the old position). The mask is a u8, so slots
// 8-14 clear nothing, and with all 15 slots taken a viewer gets mask 0 and no slot: no fog clearing, no
// IsCharacterIdOnMap (-> no "seen" checks in CheckIfVisible, and RemoveFromArea skips the area party count).
//
// IEX replaces AddCharacter, RemoveCharacter, UpDate and IsCharacterIdOnMap (jmp at the entry) with its own
// bookkeeping, per visibility map:
//  - viewers: any number of ids. The first 15 also sit in the engine's id table (same first-free-slot order as
//    the engine), so code that reads the table keeps working; the others are an IEX overflow list.
//  - stamps: what one Add/UpDate of a viewer revealed = the tile list the engine's own PrivateAddCharacter marks,
//    captured by running it on a scratch tile array (same LOS, walls and range code, explored bit set on the
//    real tiles exactly where the engine would set it).
//  - refs: per tile, the number of stamps that contain it. Visible bit 0 is set while refs > 0.
// RemoveCharacter / UpDate clear the viewer's stamps inside the engine's own box, so the result is the engine's
// behaviour for <= 15 viewers (minus the shared-bit losses), and the same for every viewer past them.
// CGameSprite::CheckIfVisible only walks the 15 table slots: its call sites are hooked to run it again with the
// overflow viewers swapped into the table, 15 at a time, until the creature is seen.
#include "vision.h"

#include "hook_points.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kAdd = "_ZN14CVisibilityMap12AddCharacterERK6CPointiPKhhPi";
constexpr const char* kRemove = "_ZN14CVisibilityMap15RemoveCharacterERK6CPointiPKhhPih";
constexpr const char* kUpDate = "_ZN14CVisibilityMap6UpDateERK6CPointS2_iPhhPih";
constexpr const char* kIsOnMap = "_ZN14CVisibilityMap18IsCharacterIdOnMapEi";
constexpr const char* kPrivateAdd = "_ZN14CVisibilityMap19PrivateAddCharacterERK6CPointhPKhhPi";
constexpr const char* kInit = "_ZN14CVisibilityMap4InitEP9CGameArea";
constexpr const char* kUninit = "_ZN14CVisibilityMap6UninitEv";
constexpr const char* kCheckIfVisible = "_ZN11CGameSprite14CheckIfVisibleEv";

constexpr int kSlots = 15;             // CVisibilityMap::MAXIMUM_CHARACTERS
constexpr int kMaxRange = 0x17;        // range clamp of every CVisibilityMap function
constexpr std::uint16_t kExplored = 0x8000;
constexpr std::uint16_t kVisibleMask = 0x7fff;
constexpr std::uint16_t kVisibleBit = 0x0001;

struct CPoint {
    std::int32_t x, y;
};

// CVisibilityMap layout (same on both builds).
std::uint16_t*& Tiles(Word map) { return *reinterpret_cast<std::uint16_t**>(map); }
int TileCount(Word map) { return *reinterpret_cast<const std::int32_t*>(map + 8); }
int Width(Word map) { return *reinterpret_cast<const std::int16_t*>(map + 0xc); }
int Height(Word map) { return *reinterpret_cast<const std::int16_t*>(map + 0xe); }
std::int32_t* Ids(Word map) { return reinterpret_cast<std::int32_t*>(map + 0x20); }

using PrivateAddFn = void (*)(Word, const CPoint*, std::uint8_t, const std::uint8_t*, std::uint8_t, std::int32_t*);
using InitFn = void (*)(Word, Word);
using UninitFn = void (*)(Word);
using SpriteFn = void (*)(Word);

PrivateAddFn g_privateAdd = nullptr;
InitFn g_init = nullptr;
UninitFn g_uninit = nullptr;
SpriteFn g_checkIfVisible = nullptr;
bool g_active = false;

std::uint64_t g_areaMap = 0xbb0;      // CGameArea -> CVisibilityMap
std::uint64_t g_objectActive = 0x4c;  // CGameObject: i16 "seen" countdown, CheckIfVisible sets it to 8
std::uint64_t g_objectArea = 0x18;    // CGameObject::m_pArea

struct Stamp {
    std::int32_t x, y;               // tile of the viewer when it was made
    std::vector<std::int32_t> tiles;
};

struct Viewer {
    std::vector<Stamp> stamps;
    bool registered = false;  // IsCharacterIdOnMap; stamps of an unregistered viewer stay until a later Remove
};

struct MapState {
    int width = 0, height = 0, count = 0;
    std::vector<std::uint32_t> refs;
    std::unordered_map<std::int32_t, Viewer> viewers;
    std::int32_t native[kSlots];
    std::vector<std::int32_t> overflow;
    std::uint64_t captures = 0;
};

std::unordered_map<Word, std::unique_ptr<MapState>> g_maps;
std::vector<std::uint16_t> g_scratch;
Word g_swappedMap = 0;  // map whose id table holds a CheckIfVisible batch right now

void WriteTable(Word map, const MapState& st)
{
    if (g_swappedMap == map)
        return;
    std::memcpy(Ids(map), st.native, sizeof(st.native));
}

// State of a map; created on first use (adopting the ids already in the engine table).
MapState& State(Word map)
{
    auto& slot = g_maps[map];
    const int w = Width(map), h = Height(map), n = TileCount(map);
    if (slot && (slot->width != w || slot->height != h || slot->count != n))
        slot.reset();  // re-initialised behind our back: start over
    if (!slot) {
        slot = std::make_unique<MapState>();
        slot->width = w;
        slot->height = h;
        slot->count = n;
        slot->refs.assign(n > 0 ? static_cast<std::size_t>(n) : 0, 0);
        for (int k = 0; k < kSlots; ++k) {
            const std::int32_t id = Ids(map)[k];
            slot->native[k] = id;
            if (id != -1)
                slot->viewers[id].registered = true;
        }
    }
    return *slot;
}

MapState* Find(Word map)
{
    auto it = g_maps.find(map);
    return it == g_maps.end() ? nullptr : it->second.get();
}

int ClampRange(std::uint8_t range) { return range < kMaxRange ? range : kMaxRange; }

// Engine tile of a point: (v + 31 for negatives) >> 5, i.e. division truncated toward zero.
int TileOf(std::int32_t v) { return v / 32; }

void Register(Word map, MapState& st, std::int32_t id, Viewer& v)
{
    if (v.registered)
        return;
    v.registered = true;
    for (int k = 0; k < kSlots; ++k) {
        if (st.native[k] == -1) {
            st.native[k] = id;
            WriteTable(map, st);
            return;
        }
    }
    st.overflow.push_back(id);
}

void Unregister(Word map, MapState& st, std::int32_t id)
{
    auto it = st.viewers.find(id);
    if (it == st.viewers.end() || !it->second.registered)
        return;
    it->second.registered = false;
    bool native = false;
    for (int k = 0; k < kSlots; ++k) {
        if (st.native[k] == id) {
            native = true;
            st.native[k] = -1;
            if (!st.overflow.empty()) {  // keep the engine table full: oldest overflow viewer moves in
                st.native[k] = st.overflow.front();
                st.overflow.erase(st.overflow.begin());
            }
            break;
        }
    }
    if (native)
        WriteTable(map, st);
    else
        st.overflow.erase(std::remove(st.overflow.begin(), st.overflow.end(), id), st.overflow.end());
    if (it->second.stamps.empty())
        st.viewers.erase(it);
}

void AddRef(MapState& st, std::uint16_t* tiles, std::int32_t t)
{
    if (st.refs[t]++ == 0)
        tiles[t] = static_cast<std::uint16_t>(tiles[t] | kVisibleBit);
}

void DropRef(MapState& st, std::uint16_t* tiles, std::int32_t t)
{
    if (st.refs[t] && --st.refs[t] == 0)
        tiles[t] = static_cast<std::uint16_t>(tiles[t] & ~kVisibleBit);
}

// Tiles the engine's PrivateAddCharacter marks for a viewer at `pos`, run on a scratch array.
std::vector<std::int32_t> Capture(Word map, MapState& st, const CPoint* pos, const std::uint8_t* terrain,
                                  std::uint8_t range, std::int32_t* extra)
{
    std::vector<std::int32_t> out;
    std::uint16_t* real = Tiles(map);
    const int w = st.width, h = st.height, n = st.count;
    if (!real || w <= 0 || h <= 0 || n < w * h)
        return out;
    if (g_scratch.size() < static_cast<std::size_t>(n))
        g_scratch.assign(static_cast<std::size_t>(n), 0);
    // Box: the engine clears (range + 1) tiles around a viewer; 2 more for walls climbed above the ray end.
    const int r = ClampRange(range) + 3;
    const int cx = TileOf(pos->x), cy = TileOf(pos->y);
    const int x0 = std::max(0, cx - r), x1 = std::min(w, cx + r + 1);
    const int y0 = std::max(0, cy - r), y1 = std::min(h, cy + r + 1);
    for (int y = y0; y < y1; ++y)
        std::fill_n(g_scratch.begin() + y * w + x0, std::max(0, x1 - x0), std::uint16_t{0});
    Tiles(map) = g_scratch.data();
    g_privateAdd(map, pos, 1, terrain, range, extra);
    Tiles(map) = real;
    ++st.captures;
    for (int y = y0; y < y1; ++y) {
        for (int x = x0; x < x1; ++x) {
            const int t = y * w + x;
            if (g_scratch[t]) {
                g_scratch[t] = 0;
                out.push_back(t);
                real[t] = static_cast<std::uint16_t>(real[t] | kExplored);
            }
        }
    }
    return out;
}

void AddStamp(Word map, MapState& st, Viewer& v, const CPoint* pos, std::vector<std::int32_t> tiles)
{
    std::uint16_t* real = Tiles(map);
    const int x = TileOf(pos->x), y = TileOf(pos->y);
    for (auto it = v.stamps.begin(); it != v.stamps.end(); ++it) {
        if (it->x == x && it->y == y) {  // same spot again: the new capture replaces the old one
            for (std::int32_t t : it->tiles)
                DropRef(st, real, t);
            v.stamps.erase(it);
            break;
        }
    }
    for (std::int32_t t : tiles)
        AddRef(st, real, t);
    v.stamps.push_back(Stamp{x, y, std::move(tiles)});
}

// The engine's clear box of RemoveCharacter / UpDate, applied to this viewer's stamps only.
void BoxClear(Word map, MapState& st, Viewer& v, const CPoint* pos, std::uint8_t range)
{
    const int r = ClampRange(range);
    const int cx = TileOf(pos->x), cy = TileOf(pos->y);
    const int x0 = std::max(0, cx - r - 1), x1 = std::min(st.width, cx + r + 1);
    const int y0 = std::max(0, cy - r - 1), y1 = std::min(st.height, cy + r + 1);
    if (x0 >= x1 || y0 >= y1)
        return;
    std::uint16_t* real = Tiles(map);
    for (auto s = v.stamps.begin(); s != v.stamps.end();) {
        auto& tiles = s->tiles;
        auto keep = std::remove_if(tiles.begin(), tiles.end(), [&](std::int32_t t) {
            const int x = t % st.width, y = t / st.width;
            if (x < x0 || x >= x1 || y < y0 || y >= y1)
                return false;
            DropRef(st, real, t);
            return true;
        });
        tiles.erase(keep, tiles.end());
        s = tiles.empty() ? v.stamps.erase(s) : s + 1;
    }
}

// --- Replacements (same parameters as the engine functions, `this` first on both ABIs) ---

int HookAdd(Word map, const CPoint* pos, std::int32_t id, const std::uint8_t* terrain, std::uint8_t range,
            std::int32_t* extra)
{
    MapState& st = State(map);
    Viewer& v = st.viewers[id];
    Register(map, st, id, v);
    AddStamp(map, st, v, pos, Capture(map, st, pos, terrain, range, extra));
    return 1;
}

void HookRemove(Word map, const CPoint* pos, std::int32_t id, const std::uint8_t*, std::uint8_t range,
                std::int32_t*, std::uint8_t removeId)
{
    MapState& st = State(map);
    auto it = st.viewers.find(id);
    if (it == st.viewers.end() || !it->second.registered)
        return;  // engine: id not on the map, nothing happens
    BoxClear(map, st, it->second, pos, range);
    if (removeId)
        Unregister(map, st, id);
}

void HookUpDate(Word map, const CPoint* oldPos, const CPoint* newPos, std::int32_t id, std::uint8_t* terrain,
                std::uint8_t range, std::int32_t* extra, std::uint8_t force)
{
    if (oldPos->x == newPos->x && oldPos->y == newPos->y && !force)
        return;
    MapState& st = State(map);
    auto it = st.viewers.find(id);
    if (it == st.viewers.end() || !it->second.registered)
        return;
    BoxClear(map, st, it->second, oldPos, range);
    AddStamp(map, st, it->second, newPos, Capture(map, st, newPos, terrain, range, extra));
}

int HookIsOnMap(Word map, std::int32_t id)
{
    if (id == -1)
        return 0;
    MapState& st = State(map);
    auto it = st.viewers.find(id);
    return it != st.viewers.end() && it->second.registered ? 1 : 0;
}

// The IsCharacterIdOnMap call of CGameSprite::RemoveFromArea: when it says yes the engine lowers the area's u8
// party count (CGameArea + 0x201) for portrait members, and keeps the value when it would go below 0 or onto the
// 0xff sentinel (`count - 1 < 0xfe`). 0xff = "loaded, nobody counted yet": CGameArea::Unmarshal sets it (e.g. the
// master area loaded with a save made in one of its interiors) and the next AddToArea turns it into 1. Logged here
// so a count that would wrap is visible; the engine's own guard already stops it.
std::uint64_t g_areaCount = 0x201;
int g_countLogs = 0;

int HookRemoveFromAreaIsOnMap(Word map, std::int32_t id)
{
    const int on = HookIsOnMap(map, id);
    const std::uint8_t count = *reinterpret_cast<const std::uint8_t*>(map - g_areaMap + g_areaCount);
    if (on && (count == 0 || count == 0xff) && g_countLogs < 50) {
        ++g_countLogs;
        Log("RemoveFromArea: viewer %08x leaves an area whose party count is %u, the engine keeps it (no wrap)",
            static_cast<unsigned>(id), count);
    }
    return on;
}

void HookInit(Word map, Word area)
{
    g_maps.erase(map);
    g_init(map, area);
}

void HookUninit(Word map)
{
    g_maps.erase(map);
    g_uninit(map);
}

void HookCheckIfVisible(Word sprite)
{
    const Word area = *reinterpret_cast<const Word*>(sprite + g_objectArea);
    MapState* st = area ? Find(area + g_areaMap) : nullptr;
    if (!st || st->overflow.empty() || g_swappedMap) {
        g_checkIfVisible(sprite);
        return;
    }
    const Word map = area + g_areaMap;
    auto& active = *reinterpret_cast<std::int16_t*>(sprite + g_objectActive);
    const std::int16_t before = active;
    if (before == 8)
        active = 7;  // so that "seen" (set to 8) can be told apart; 7 is never tested by CheckIfVisible
    g_checkIfVisible(sprite);
    if (active != 8) {
        const std::vector<std::int32_t> extra = st->overflow;
        g_swappedMap = map;
        for (std::size_t i = 0; i < extra.size() && active != 8; i += kSlots) {
            std::int32_t batch[kSlots];
            for (int k = 0; k < kSlots; ++k)
                batch[k] = i + k < extra.size() ? extra[i + k] : -1;
            std::memcpy(Ids(map), batch, sizeof(batch));
            g_checkIfVisible(sprite);
        }
        g_swappedMap = 0;
        if (MapState* now = Find(map))
            WriteTable(map, *now);
        if (active != 8)
            active = before;
    }
}

// --- Lua ---

void SetField(lua_State* L, const char* key, lua_Integer v)
{
    lua.pushinteger(L, v);
    lua.setfield(L, -2, key);
}

void PushMapInfo(lua_State* L, Word map, const MapState& st)
{
    int registered = 0, detached = 0, stamps = 0, visible = 0, slots = 0;
    for (const auto& [id, v] : st.viewers) {
        (v.registered ? registered : detached) += 1;
        stamps += static_cast<int>(v.stamps.size());
    }
    for (std::uint32_t r : st.refs)
        visible += r ? 1 : 0;
    for (std::int32_t id : st.native)
        slots += id != -1 ? 1 : 0;
    lua.createtable(L, 0, 10);
    SetField(L, "map", static_cast<lua_Integer>(map));
    SetField(L, "width", st.width);
    SetField(L, "height", st.height);
    SetField(L, "viewers", registered);
    SetField(L, "tableSlots", slots);
    SetField(L, "overflow", static_cast<lua_Integer>(st.overflow.size()));
    SetField(L, "detached", detached);
    SetField(L, "stamps", stamps);
    SetField(L, "visibleTiles", visible);
    SetField(L, "captures", static_cast<lua_Integer>(st.captures));
}

// IEX_VisionInfo([map]) -> table of one map's counters, or a list of all maps known to IEX. `map` = area + 0xbb0.
int LuaVisionInfo(lua_State* L)
{
    if (lua.type(L, 1) == LUA_TNUMBER) {
        const Word map = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
        const MapState* st = Find(map);
        if (!st) {
            lua.pushnil(L);
            return 1;
        }
        PushMapInfo(L, map, *st);
        return 1;
    }
    lua.createtable(L, static_cast<int>(g_maps.size()), 0);
    int i = 0;
    for (const auto& [map, st] : g_maps) {
        PushMapInfo(L, map, *st);
        lua.rawseti(L, -2, ++i);
    }
    return 1;
}

// IEX_VisionViewer(map, id) -> registered, table slot (0-14, -1 = IEX overflow, nil = not a viewer), stamps, tiles
int LuaVisionViewer(lua_State* L)
{
    const Word map = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const auto id = static_cast<std::int32_t>(lua.tointegerx(L, 2, nullptr));
    const MapState* st = Find(map);
    if (!st || st->viewers.find(id) == st->viewers.end()) {
        lua.pushboolean(L, 0);
        return 1;
    }
    const auto it = st->viewers.find(id);
    int slot = -1;
    for (int k = 0; k < kSlots; ++k)
        slot = st->native[k] == id ? k : slot;
    std::size_t tiles = 0;
    for (const auto& s : it->second.stamps)
        tiles += s.tiles.size();
    lua.pushboolean(L, it->second.registered);
    if (it->second.registered)
        lua.pushinteger(L, slot);
    else
        lua.pushnil(L);
    lua.pushinteger(L, static_cast<lua_Integer>(it->second.stamps.size()));
    lua.pushinteger(L, static_cast<lua_Integer>(tiles));
    return 4;
}

// IEX_VisionTile(map, x, y) -> tile value (u16), viewer count; x, y in area pixels.
int LuaVisionTile(lua_State* L)
{
    const Word map = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const int x = TileOf(static_cast<std::int32_t>(lua.tointegerx(L, 2, nullptr)));
    const int y = TileOf(static_cast<std::int32_t>(lua.tointegerx(L, 3, nullptr)));
    const MapState* st = Find(map);
    if (!map || !Tiles(map) || x < 0 || y < 0 || x >= Width(map) || y >= Height(map)) {
        lua.pushnil(L);
        return 1;
    }
    const int t = y * Width(map) + x;
    lua.pushinteger(L, Tiles(map)[t]);
    lua.pushinteger(L, st && t < static_cast<int>(st->refs.size()) ? st->refs[t] : 0);
    return 2;
}

// IEX_VisionCheck() -> number of tiles whose visible bits disagree with the viewer counts, maps checked.
int LuaVisionCheck(lua_State* L)
{
    lua_Integer bad = 0;
    for (const auto& [map, st] : g_maps) {
        const std::uint16_t* tiles = Tiles(map);
        if (!tiles)
            continue;
        for (int t = 0; t < st->count && t < static_cast<int>(st->refs.size()); ++t)
            bad += ((tiles[t] & kVisibleBit) != 0) != (st->refs[t] != 0) ? 1 : 0;
    }
    lua.pushinteger(L, bad);
    lua.pushinteger(L, static_cast<lua_Integer>(g_maps.size()));
    return 2;
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

bool VisionActive()
{
    return g_active;
}

void InstallVisionHooks()
{
    if (const char* off = std::getenv("IEX_NO_PARTY_VISION"); off && *off && *off != '0') {
        Log("Party vision: disabled by IEX_NO_PARTY_VISION");
        return;
    }
    const Word base = EngineImageBase();
    const auto sym = [base](const char* name) -> Word {
        const std::uint32_t rva = engineTypes.Symbol(name);
        return rva ? base + rva : 0;
    };
    const auto cst = [](const char* name) {
        std::uint64_t v = 0;
        return engineTypes.Const(name, v) ? v : 0;
    };
    engineTypes.Const("IEX.vis.areaMap", g_areaMap);
    engineTypes.Const("IEX.vis.objectActive", g_objectActive);
    std::uint32_t offset = 0;
    if (const TypeDesc* obj = engineTypes.Get("CGameObject")) {
        if (obj->Find("m_pArea", offset))
            g_objectArea = offset;
    }
    struct Entry {
        const char* name;
        const char* prologue;
        const void* replacement;
        Word fn = 0;
        std::uint64_t expect = 0;
    } entries[] = {
        {kAdd, "IEX.vis.prologue.AddCharacter", reinterpret_cast<const void*>(&HookAdd)},
        {kRemove, "IEX.vis.prologue.RemoveCharacter", reinterpret_cast<const void*>(&HookRemove)},
        {kUpDate, "IEX.vis.prologue.UpDate", reinterpret_cast<const void*>(&HookUpDate)},
        {kIsOnMap, "IEX.vis.prologue.IsCharacterIdOnMap", reinterpret_cast<const void*>(&HookIsOnMap)},
    };
    const Word privateAdd = sym(kPrivateAdd), init = sym(kInit), uninit = sym(kUninit), check = sym(kCheckIfVisible);
    const auto initSites = engineTypes.CallSitesOf(kInit), uninitSites = engineTypes.CallSitesOf(kUninit);
    bool ok = privateAdd && init && uninit && !initSites.empty() && !uninitSites.empty();
    for (Entry& e : entries) {
        e.fn = sym(e.name);
        e.expect = cst(e.prologue);
        ok = ok && e.fn && e.expect;
    }
    if (!ok) {
        Log("Party vision: engine description incomplete, unlimited viewers disabled");
        return;
    }
    // All-or-nothing: every site must still hold the game's own bytes (no other patch stacked on them).
    for (const Entry& e : entries)
        ok = FunctionEntryIntact(e.fn, e.expect) && ok;
    ok = FunctionEntryIntact(privateAdd, cst("IEX.vis.prologue.PrivateAddCharacter")) && ok;
    const auto callsTo = [base](std::uint32_t site, Word target) {
        const auto* code = reinterpret_cast<const std::uint8_t*>(base + site);
        std::int32_t rel;
        std::memcpy(&rel, code + 1, 4);
        return code[0] == 0xE8 && base + site + 5 + rel == target;
    };
    for (std::uint32_t s : initSites)
        ok = ok && callsTo(s, init);
    for (std::uint32_t s : uninitSites)
        ok = ok && callsTo(s, uninit);
    if (!ok) {
        Log("Party vision: a visibility map function or call site is already patched, hooks skipped "
            "(engine 15-viewer limit stays)");
        return;
    }
    g_privateAdd = reinterpret_cast<PrivateAddFn>(privateAdd);
    g_init = reinterpret_cast<InitFn>(init);
    g_uninit = reinterpret_cast<UninitFn>(uninit);
    for (std::uint32_t s : initSites)
        HookCallSite(base + s, init, reinterpret_cast<const void*>(&HookInit));
    for (std::uint32_t s : uninitSites)
        HookCallSite(base + s, uninit, reinterpret_cast<const void*>(&HookUninit));
    bool all = true;
    for (const Entry& e : entries)
        all = HookFunctionEntry(e.fn, e.expect, e.replacement) && all;
    g_active = all;
    if (const std::uint64_t site = cst("IEX.vis.removeFromAreaIsOnMapSite"))
        HookCallSite(base + site, sym(kIsOnMap), reinterpret_cast<const void*>(&HookRemoveFromAreaIsOnMap));
    int checkSites = 0, checkTotal = 0;
    if (check) {
        g_checkIfVisible = reinterpret_cast<SpriteFn>(check);
        for (std::uint32_t s : engineTypes.CallSitesOf(kCheckIfVisible)) {
            ++checkTotal;
            checkSites += HookCallSite(base + s, check, reinterpret_cast<const void*>(&HookCheckIfVisible)) ? 1 : 0;
        }
        // Tail jumps (Linux CGameSprite::AIUpdate ends with `jmp CheckIfVisible`).
        for (int i = 0; i < 8; ++i) {
            const std::uint64_t site = cst(("IEX.vis.checkIfVisibleJmp." + std::to_string(i)).c_str());
            if (!site)
                break;
            ++checkTotal;
            checkSites += HookJumpSite(base + site, check, reinterpret_cast<const void*>(&HookCheckIfVisible)) ? 1 : 0;
        }
    }
    Log("Party vision (unlimited fog-of-war viewers): %s; CheckIfVisible call sites %d/%d",
        all ? "installed" : "PARTLY FAILED", checkSites, checkTotal);
    hp::MarkInstalled(hp::kPartyVision, all, checkSites + 6, all ? nullptr : "a function entry hook failed");
}

void OpenLuaVision(lua_State* L)
{
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushboolean(L, g_active);
    lua.setfield(L, -2, "partyVision");
    lua.settop(L, -2);
    Register(L, "IEX_VisionInfo", LuaVisionInfo);
    Register(L, "IEX_VisionViewer", LuaVisionViewer);
    Register(L, "IEX_VisionTile", LuaVisionTile);
    Register(L, "IEX_VisionCheck", LuaVisionCheck);
}

} // namespace iex
