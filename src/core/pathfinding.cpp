// Pathfinding Redux, native: see pathfinding.h for the engine model and the hooks.
//
// The movement policy (who passes through whom, which cells may be cleared, the out-of-combat-only mode) follows
// BG Pathfinding Redux 0.1.11 (https://github.com/zach-hopkins/bg-pathfinding-redux, MIT licence, (c) 2026 Zach
// Hopkins), read from its own Lua and documentation. The engine side (functions, fields, call sites) comes from
// IEX's own analysis of both game binaries.
#include "pathfinding.h"

#include "callsite_hook.h"
#include "hook_points.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kWalk = "_ZN11CGameSprite12AIUpdateWalkEv";
constexpr const char* kSetTarget = "_ZN11CGameSprite9SetTargetEP14CSearchRequestih";
constexpr const char* kFindPath = "_ZN11CPathSearch8FindPathEP8tagPOINTS1_siiP13CSearchBitmapPhiP5CRect";
constexpr const char* kGetShare = "_ZN16CGameObjectArray8GetShareEiPP11CGameObjectb";
constexpr const char* kGetProfileInt = "_Z22BGGetPrivateProfileIntPKcS0_i";
constexpr const char* kChitin = "g_pBaldurChitin";

constexpr std::uint8_t kSpriteType = 0x31;
constexpr int kCellW = 16, kCellH = 12;
constexpr int kMaxGrid = 320;           // AddObject ignores centres outside 0..319
constexpr int kCombatClearTicks = 45;   // 3 s of game time (15 ticks/s), as the mod
constexpr std::size_t kMaxActors = 1024;

using WalkFn = void (*)(Word);
using SetTargetFn = void (*)(Word, Word, Word, Word);
using FindPathFn = Word (*)(Word, Word, Word, Word, Word, Word, Word, Word, Word, Word);
using GetShareFn = std::uint8_t (*)(int, Word*, bool);
using GetIntFn = int (*)(const char*, const char*, int);
using PersonalSpaceFn = std::uint8_t (*)(Word);

WalkFn g_walk = nullptr;
SetTargetFn g_setTarget = nullptr;
FindPathFn g_findPath = nullptr;
GetShareFn g_getShare = nullptr;
GetIntFn g_getInt = nullptr;
Word* g_chitin = nullptr;

// Layout (engine description: types + `IEX.path.*` consts).
struct Layout {
    std::uint32_t objType = 0x8, pos = 0xc, area = 0x18, typeAI = 0x30, id = 0x48;
    std::uint32_t animation = 0, painted = 0, repaint = 0, category = 0;
    std::uint32_t vtPersonalSpace = 0;
    std::uint32_t areaSearch = 0xa60, cells = 0x120, snapshot = 0x128, grid = 0x138;
    std::uint32_t lists[4] = {};
    std::uint32_t battle = 0, damage = 0;
    std::uint32_t game = 0, gameAreas = 0, worldTime = 0;
} L_;

bool g_installed = false;
bool g_enabled = false;     // allied passage on (session switch, Ctrl+Shift+F1 in IEX_Pathfinding.lua)
bool g_combatOnly = false;  // bg-redux-movement.ini [Movement] OutOfCombatOnly
bool g_modFound = false;    // override/M_BGREDX.lua

// Statistics (IEX_PathfindingRedux()).
struct Stats {
    std::uint64_t scopes = 0, scopeCells = 0, dropped = 0;
    std::uint64_t searches = 0, snapshotSearches = 0, snapshotCells = 0;
    double searchMs = 0, maxSearchMs = 0, overheadMs = 0, maxOverheadMs = 0;
} g_stats;

template <typename T>
T Get(Word base, std::uint32_t off)
{
    T v;
    std::memcpy(&v, reinterpret_cast<const void*>(base + off), sizeof(T));
    return v;
}

double NowMs()
{
    using namespace std::chrono;
    return duration<double, std::milli>(steady_clock::now().time_since_epoch()).count();
}

struct Actor {
    Word ptr;
    int id;
    int ea;
    int cx, cy;      // search cell of m_pos
    int personal;
    bool high;       // category 0: high counter (bits 4-6)
    int paint;       // 1 painted, 0 not, -1 inconsistent flags
};

int PersonalSpace(Word sprite)
{
    const Word anim = sprite + L_.animation;  // CGameAnimation: CGameAnimationType* at +0
    if (Get<std::uint8_t>(anim, 8) & 4)
        return Get<std::uint8_t>(anim, 0x10);
    const Word type = Get<Word>(anim, 0);
    if (!type)
        return -1;
    const Word vt = Get<Word>(type, 0);
    return reinterpret_cast<PersonalSpaceFn>(Get<Word>(vt, L_.vtPersonalSpace))(type);
}

bool IsAlly(int ea)
{
    return ea >= 2 && ea <= 30;  // EA.IDS PC .. GOODCUTOFF; NEUTRAL (128) is not allied
}

bool ReadActor(Word sprite, Actor& a)
{
    if (!sprite || Get<std::uint8_t>(sprite, L_.objType) != kSpriteType)
        return false;
    a.ptr = sprite;
    a.id = Get<std::int32_t>(sprite, L_.id);
    a.ea = Get<std::uint8_t>(sprite, L_.typeAI + 8);
    const int x = Get<std::int32_t>(sprite, L_.pos), y = Get<std::int32_t>(sprite, L_.pos + 4);
    a.cx = x >= 0 ? x / kCellW : -1;
    a.cy = y >= 0 ? y / kCellH : -1;
    a.personal = PersonalSpace(sprite);
    a.high = Get<std::int32_t>(sprite, L_.category) == 0;
    const int p = Get<std::int32_t>(sprite, L_.painted), r = Get<std::int32_t>(sprite, L_.repaint);
    a.paint = p == 1 && r == 0 ? 1 : p == 0 ? 0 : -1;
    return true;
}

// Footprint of CSearchBitmap::AddObject: square of radius (space-1)/2, cells with |dx|+|dy| <= space/2+1,
// clipped to the grid; nothing for a centre outside 0..319.
// The size is the one the map really got (SearchFootprintSize: SadoEE's small footprint, bumpable = category != 0).
template <typename F>
void ForFootprint(const Actor& a, int width, int height, F&& fn)
{
    const int size = SearchFootprintSize(a.personal, !a.high);
    if (a.cx < 0 || a.cy < 0 || a.cx >= kMaxGrid || a.cy >= kMaxGrid || size < 1)
        return;
    const int r = (size - 1) / 2, lim = size / 2 + 1;
    for (int y = a.cy - r; y <= a.cy + r; ++y) {
        if (y < 0 || y >= height)
            continue;
        for (int x = a.cx - r; x <= a.cx + r; ++x) {
            if (x < 0 || x >= width)
                continue;
            if (std::abs(x - a.cx) + std::abs(y - a.cy) <= lim)
                fn(y * width + x);
        }
    }
}

// Every creature of an area (its four vertical-sort lists: CPtrList, head at +8, node next +0, data id +0x10).
void AreaActors(Word area, std::vector<Actor>& out)
{
    out.clear();
    for (std::uint32_t list : L_.lists) {
        for (Word node = Get<Word>(area + list, 8); node && out.size() < kMaxActors; node = Get<Word>(node, 0)) {
            const int id = Get<std::int32_t>(node, 0x10);
            Word obj = 0;
            if (g_getShare(id, &obj, false) != 0 || !obj || Get<Word>(obj, L_.area) != area)
                continue;
            Actor a;
            if (!ReadActor(obj, a))
                continue;
            bool dup = false;
            for (const Actor& b : out)
                dup = dup || b.ptr == a.ptr;
            if (!dup)
                out.push_back(a);
        }
    }
}

// --- Out-of-combat-only mode: a positive battle-song or damage counter in any loaded area (as quicksave's combat
// check, CGameArea::CanSaveGame), then 3 s of game time without one. ---
std::uint32_t g_combatTime = 0xffffffff, g_lastCombat = 0;
bool g_combatSeen = false, g_combatBlocked = false;

bool CombatBlocked()
{
    if (!g_combatOnly || !g_chitin || !*g_chitin)
        return false;
    const Word game = Get<Word>(*g_chitin, L_.game);
    if (!game)
        return false;
    const std::uint32_t now = Get<std::uint32_t>(game, L_.worldTime);
    if (now == g_combatTime)
        return g_combatBlocked;
    g_combatTime = now;
    bool fight = false;
    for (int i = 0; i < 12 && !fight; ++i) {
        const Word area = Get<Word>(game, L_.gameAreas + 8 * i);
        fight = area && (Get<std::int32_t>(area, L_.battle) > 0 || Get<std::int32_t>(area, L_.damage) > 0);
    }
    if (fight || (g_combatSeen && now < g_lastCombat)) {  // fight, or game time went back (load): restart
        g_combatSeen = true;
        g_lastCombat = now;
    }
    g_combatBlocked = g_combatSeen && now - g_lastCombat < kCombatClearTicks;
    return g_combatBlocked;
}

// --- Cell analysis ---

struct Grid {
    Word bitmap = 0;
    std::uint8_t* cells = nullptr;
    int width = 0, height = 0;
};

bool ReadGrid(Word area, Grid& g)
{
    if (!area)
        return false;
    g.bitmap = area + L_.areaSearch;
    g.cells = reinterpret_cast<std::uint8_t*>(Get<Word>(g.bitmap, L_.cells));
    g.width = Get<std::int32_t>(g.bitmap, L_.grid);
    g.height = Get<std::int32_t>(g.bitmap, L_.grid + 4);
    return g.cells && g.width >= 1 && g.width <= kMaxGrid && g.height >= 1 && g.height <= kMaxGrid;
}

// A mover the policy applies to: an ally of normal size (personal space 3) in an area, outside a combat block.
bool EligibleMover(const Actor& m)
{
    return g_enabled && IsAlly(m.ea) && m.personal == 3 && !CombatBlocked();
}

struct Cell {
    int index;
    std::uint8_t expLow = 0, expHigh = 0;  // counts expected from the painted creatures covering it
    std::uint8_t subLow = 0, subHigh = 0;  // the other allies' share
    bool foreign = false;                  // a painted non-ally (or an inconsistent paint) covers it
};

std::vector<Actor> g_actors;
std::vector<Cell> g_cells;
std::unordered_map<int, std::size_t> g_cellIndex;

// The cells where the other allies' footprints account, with the mover's, for the whole live occupancy.
void FriendlyCells(const Actor& mover, const Grid& g)
{
    g_cells.clear();
    g_cellIndex.clear();
    const Word area = Get<Word>(mover.ptr, L_.area);
    AreaActors(area, g_actors);
    for (const Actor& a : g_actors) {
        if (a.ptr == mover.ptr || a.paint != 1 || !IsAlly(a.ea))
            continue;
        ForFootprint(a, g.width, g.height, [&](int idx) {
            if (g_cellIndex.emplace(idx, g_cells.size()).second)
                g_cells.push_back(Cell{idx});
        });
    }
    if (g_cells.empty())
        return;
    for (const Actor& a : g_actors) {
        const bool friendly = a.ptr == mover.ptr || IsAlly(a.ea);
        if (a.paint == 0)
            continue;
        ForFootprint(a, g.width, g.height, [&](int idx) {
            const auto it = g_cellIndex.find(idx);
            if (it == g_cellIndex.end())
                return;
            Cell& c = g_cells[it->second];
            if (a.paint < 0 || !friendly) {
                c.foreign = true;
                return;
            }
            (a.high ? c.expHigh : c.expLow) += 1;
            if (a.ptr != mover.ptr)
                (a.high ? c.subHigh : c.subLow) += 1;
        });
    }
}

bool Verified(const Cell& c, std::uint8_t live)
{
    return !c.foreign && (live & 0x81) == 0 && c.expLow < 8 && c.expHigh < 8 &&
           ((live >> 1) & 7) == c.expLow && ((live >> 4) & 7) == c.expHigh;
}

std::uint8_t AddCounts(std::uint8_t b, int dLow, int dHigh)
{
    const int low = (((b >> 1) & 7) + dLow) & 7, high = (((b >> 4) & 7) + dHigh) & 7;
    return static_cast<std::uint8_t>((b & 0x81) | (low << 1) | (high << 4));
}

// --- Live scopes: allies subtracted from the live counts while one call of an eligible mover runs ---

struct Delta {
    int index;
    std::uint8_t low, high;
};

struct Scope {
    Word mover = 0;
    Word area = 0;
    std::uint8_t* cells = nullptr;
    std::vector<Delta> deltas;
    bool live = false;
};

Scope* g_scope = nullptr;  // innermost applied scope (main thread only)

// The area is still loaded (one of CInfGame's 12 area slots) and still owns the same count array.
bool AreaAlive(Word area, const std::uint8_t* cells)
{
    const Word game = g_chitin && *g_chitin ? Get<Word>(*g_chitin, L_.game) : 0;
    for (int i = 0; game && i < 12; ++i) {
        if (Get<Word>(game, L_.gameAreas + 8 * i) == area)
            return Get<Word>(area + L_.areaSearch, L_.cells) == reinterpret_cast<Word>(cells);
    }
    return false;
}

void Undo(Scope& s)
{
    if (!s.live)
        return;
    s.live = false;
    if (!AreaAlive(s.area, s.cells)) {
        Log("Pathfinding Redux: area %p unloaded during a movement call, its counts were not restored",
            reinterpret_cast<void*>(s.area));
        return;
    }
    for (const Delta& d : s.deltas)
        s.cells[d.index] = AddCounts(s.cells[d.index], d.low, d.high);
}

bool Apply(Scope& s, Word sprite)
{
    Actor m;
    if (!g_installed || !ReadActor(sprite, m) || !EligibleMover(m))
        return false;
    Grid g;
    if (!ReadGrid(Get<Word>(sprite, L_.area), g))
        return false;
    const double t0 = NowMs();
    FriendlyCells(m, g);
    s.mover = sprite;
    s.area = Get<Word>(sprite, L_.area);
    s.cells = g.cells;
    s.deltas.clear();
    for (const Cell& c : g_cells) {
        if ((c.subLow || c.subHigh) && Verified(c, g.cells[c.index])) {
            s.deltas.push_back({c.index, c.subLow, c.subHigh});
            g.cells[c.index] = AddCounts(g.cells[c.index], -c.subLow, -c.subHigh);
        }
    }
    s.live = true;
    const double dt = NowMs() - t0;
    g_stats.overheadMs += dt;
    if (dt > g_stats.maxOverheadMs)
        g_stats.maxOverheadMs = dt;
    ++g_stats.scopes;
    g_stats.scopeCells += s.deltas.size();
    return true;
}

// Runs `call` with the other allies lifted from the live counts for `sprite`. A nested call for the same mover
// keeps the outer scope; one for another creature ends the outer scope first (the engine view is restored).
template <typename F>
void WithScope(Word sprite, F&& call, bool apply = true)
{
    if (g_scope && g_scope->live && g_scope->mover == sprite) {
        call();
        return;
    }
    if (g_scope && g_scope->live) {
        Undo(*g_scope);
        ++g_stats.dropped;
    }
    Scope s;
    Scope* outer = g_scope;
    if (apply && Apply(s, sprite))
        g_scope = &s;
    call();
    Undo(s);
    g_scope = outer;
}

int g_parts = 7;  // IEX_PATH_PARTS (test bisection): 1 walk scope, 2 SetTarget scope, 4 snapshot

void HookWalk(Word sprite)
{
    WithScope(sprite, [&] { g_walk(sprite); }, (g_parts & 1) != 0);
}

bool g_debug = false;  // IEX_PATH_DEBUG=1: one log line per SetTarget / FindPath

void HookSetTarget(Word sprite, Word request, Word random, Word priority)
{
    WithScope(sprite, [&] {
        if (g_debug)
            Log("PathDbg SetTarget id=%d req=%p state=%d kind=%d scope=%d cells=%d", Get<std::int32_t>(sprite, L_.id),
                reinterpret_cast<void*>(request), request ? Get<std::uint8_t>(request, 0) : -1,
                request ? Get<std::int32_t>(request, 4) : -1, g_scope && g_scope->mover == sprite ? 1 : 0,
                g_scope && g_scope->mover == sprite ? static_cast<int>(g_scope->deltas.size()) : 0);
        g_setTarget(sprite, request, random, priority);
        if (g_debug)
            Log("PathDbg SetTarget done id=%d state=%d", Get<std::int32_t>(sprite, L_.id),
                request ? Get<std::uint8_t>(request, 0) : -1);
    }, (g_parts & 2) != 0);
}

// --- Background search: clear the fully-allied cells of the request's private snapshot ---

void PrepareSnapshot(Word bitmap, Word request)
{
    if (!g_installed || !request || !bitmap || Get<std::uint8_t>(request, 0) != 1 ||
        Get<std::int32_t>(request, 4) != 0 || Get<Word>(request, 0x18) != bitmap)
        return;
    Word sprite = 0;
    if (g_getShare(Get<std::int32_t>(request, 0x38), &sprite, false) != 0 || !sprite)
        return;
    Actor m;
    if (!ReadActor(sprite, m) || !EligibleMover(m))
        return;
    Grid g;
    const Word area = Get<Word>(sprite, L_.area);
    if (!ReadGrid(area, g) || g.bitmap != bitmap)
        return;
    auto* snap = reinterpret_cast<std::uint8_t*>(Get<Word>(bitmap, L_.snapshot));
    if (!snap || snap == g.cells)
        return;
    FriendlyCells(m, g);
    std::uint64_t cleared = 0;
    for (const Cell& c : g_cells) {
        const std::uint8_t live = g.cells[c.index], priv = snap[c.index];
        if (!Verified(c, live) || (priv & 0x81) != (live & 0x81) || ((priv >> 1) & 7) > ((live >> 1) & 7) ||
            ((priv >> 4) & 7) > ((live >> 4) & 7) || (priv & 0x7e) == 0)
            continue;
        snap[c.index] = priv & 0x81;
        ++cleared;
    }
    ++g_stats.snapshotSearches;
    g_stats.snapshotCells += cleared;
}

Word HookFindPath(Word self, Word start, Word goals, Word count, Word maxNodes, Word a6, Word bitmap, Word request,
                  Word a9, Word rect)
{
    const double t0 = NowMs();
    if (g_parts & 4)
        PrepareSnapshot(bitmap, request);
    const double t1 = NowMs();
    const Word r = g_findPath(self, start, goals, count, maxNodes, a6, bitmap, request, a9, rect);
    const double t2 = NowMs();
    if (g_debug)
        Log("PathDbg FindPath mover=%d result=%d snapshots=%llu ms=%.3f", request ? Get<std::int32_t>(request, 0x38) : -1,
            static_cast<int>(static_cast<std::int16_t>(r)), static_cast<unsigned long long>(g_stats.snapshotSearches),
            t2 - t1);
    ++g_stats.searches;
    g_stats.overheadMs += t1 - t0;
    if (t1 - t0 > g_stats.maxOverheadMs)
        g_stats.maxOverheadMs = t1 - t0;
    g_stats.searchMs += t2 - t1;
    if (t2 - t1 > g_stats.maxSearchMs)
        g_stats.maxSearchMs = t2 - t1;
    return r;
}

// --- Settings ---

bool FileExists(const std::string& path)
{
    std::ifstream f(path, std::ios::binary);
    return f.good();
}

// bg-redux-movement.ini [Movement] key (the mod's own settings file), -1 if absent.
int ModIniValue(const char* key)
{
    std::ifstream f(GameDir() + "/bg-redux-movement.ini");
    std::string line;
    bool section = false;
    while (std::getline(f, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == ' '))
            line.pop_back();
        if (!line.empty() && line[0] == '[') {
            section = line == "[Movement]";
            continue;
        }
        const auto eq = line.find('=');
        if (section && eq != std::string::npos && line.compare(0, eq, key) == 0)
            return std::atoi(line.c_str() + eq + 1);
    }
    return -1;
}

void SetField(lua_State* L, const char* key, double v)
{
    lua.pushnumber(L, v);
    lua.setfield(L, -2, key);
}

void SetBool(lua_State* L, const char* key, bool v)
{
    lua.pushboolean(L, v);
    lua.setfield(L, -2, key);
}

void PublishFeature(lua_State* L)
{
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
    lua.pushboolean(L, g_installed && g_enabled);
    lua.setfield(L, -2, "pathfindingRedux");
    lua.settop(L, -2);
}

// IEX_PathfindingCheck(sprite pointer) -> cells whose creature counts differ from the painted footprints of the
// sprite's area, total cells with counts, first mismatch "x,y live=.. exp=low/high" (test tool).
int LuaPathCheck(lua_State* L)
{
    const Word sprite = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    Grid g;
    if (!sprite || !ReadGrid(Get<Word>(sprite, L_.area), g)) {
        lua.pushnil(L);
        return 1;
    }
    std::vector<Actor> actors;
    AreaActors(Get<Word>(sprite, L_.area), actors);
    std::vector<std::uint8_t> low(static_cast<std::size_t>(g.width) * g.height), high(low.size());
    for (const Actor& a : actors) {
        if (a.paint != 1)
            continue;
        ForFootprint(a, g.width, g.height, [&](int idx) { ((a.high ? high : low)[idx] += 1) &= 7; });
    }
    int bad = 0, used = 0;
    std::string first;
    for (int i = 0; i < g.width * g.height; ++i) {
        const int l = (g.cells[i] >> 1) & 7, h = (g.cells[i] >> 4) & 7;
        used += (l || h) ? 1 : 0;
        if (l != low[i] || h != high[i]) {
            if (!bad) {
                char buf[96];
                std::snprintf(buf, sizeof buf, "%d,%d live=%02x exp=%d/%d", i % g.width, i / g.width, g.cells[i], low[i], high[i]);
                first = buf;
            }
            ++bad;
        }
    }
    lua.pushinteger(L, bad);
    lua.pushinteger(L, used);
    lua.pushstring(L, first.c_str());
    return 3;
}

// IEX_PathfindingRedux([{enabled=bool, combatOnly=bool, reset=bool}]) -> state and statistics table.
int LuaPathfinding(lua_State* L)
{
    if (lua.type(L, 1) == LUA_TTABLE) {
        lua.getfield(L, 1, "enabled");
        if (lua.type(L, -1) != LUA_TNIL)
            g_enabled = g_installed && lua.toboolean(L, -1) != 0;
        lua.settop(L, -2);
        lua.getfield(L, 1, "combatOnly");
        if (lua.type(L, -1) != LUA_TNIL) {
            g_combatOnly = lua.toboolean(L, -1) != 0;
            g_combatTime = 0xffffffff;
            g_combatSeen = false;
        }
        lua.settop(L, -2);
        lua.getfield(L, 1, "reset");
        if (lua.toboolean(L, -1))
            g_stats = Stats{};
        lua.settop(L, -2);
        PublishFeature(L);
    }
    lua.createtable(L, 0, 16);
    SetBool(L, "installed", g_installed);
    SetBool(L, "enabled", g_enabled);
    SetBool(L, "combatOnly", g_combatOnly);
    SetBool(L, "combatBlocked", g_combatOnly && CombatBlocked());
    SetBool(L, "modInstalled", g_modFound);
    SetField(L, "scopes", static_cast<double>(g_stats.scopes));
    SetField(L, "scopeCells", static_cast<double>(g_stats.scopeCells));
    SetField(L, "droppedScopes", static_cast<double>(g_stats.dropped));
    SetField(L, "searches", static_cast<double>(g_stats.searches));
    SetField(L, "snapshotSearches", static_cast<double>(g_stats.snapshotSearches));
    SetField(L, "snapshotCells", static_cast<double>(g_stats.snapshotCells));
    SetField(L, "searchMs", g_stats.searchMs);
    SetField(L, "maxSearchMs", g_stats.maxSearchMs);
    SetField(L, "overheadMs", g_stats.overheadMs);
    SetField(L, "maxOverheadMs", g_stats.maxOverheadMs);
    return 1;
}

bool LoadLayout()
{
    const TypeDesc* obj = engineTypes.Get("CGameObject");
    const TypeDesc* sprite = engineTypes.Get("CGameSprite");
    const TypeDesc* area = engineTypes.Get("CGameArea");
    const TypeDesc* bitmap = engineTypes.Get("CSearchBitmap");
    const TypeDesc* chitin = engineTypes.Get("CBaldurChitin");
    const TypeDesc* game = engineTypes.Get("CInfGame");
    if (!obj || !sprite || !area || !bitmap || !chitin || !game)
        return false;
    bool ok = obj->Find("m_objectType", L_.objType) && obj->Find("m_pos", L_.pos) && obj->Find("m_pArea", L_.area) &&
              obj->Find("m_typeAI", L_.typeAI) && obj->Find("m_id", L_.id) &&
              sprite->Find("m_animation", L_.animation) && area->Find("m_search", L_.areaSearch) &&
              bitmap->Find("m_pDynamicCost", L_.cells) && bitmap->Find("m_GridSquareDimensions", L_.grid) &&
              area->Find("m_nBattleSongCounter", L_.battle) && chitin->Find("m_pObjectGame", L_.game) &&
              game->Find("m_gameAreas", L_.gameAreas) && game->Find("m_worldTime", L_.worldTime);
    const char* lists[4] = {"m_lVertSort", "m_lVertSortBack", "m_lVertSortFlight", "m_lVertSortAdd"};
    for (int i = 0; ok && i < 4; ++i)
        ok = area->Find(lists[i], L_.lists[i]) != nullptr;
    const auto cst = [&ok](const char* name, std::uint32_t& out) {
        std::uint64_t v = 0;
        ok = ok && engineTypes.Const(name, v) && v;
        out = static_cast<std::uint32_t>(v);
    };
    cst("IEX.path.painted", L_.painted);
    cst("IEX.path.repaint", L_.repaint);
    cst("IEX.path.category", L_.category);
    cst("IEX.path.vtPersonalSpace", L_.vtPersonalSpace);
    cst("IEX.path.snapshot", L_.snapshot);
    cst("IEX.path.damageCounter", L_.damage);
    return ok;
}

int HookSites(const char* target, const void* replacement, int& total)
{
    const Word base = EngineImageBase();
    const std::uint32_t rva = engineTypes.Symbol(target);
    int n = 0;
    for (std::uint32_t site : engineTypes.CallSitesOf(target)) {
        ++total;
        n += HookCallSite(base + site, base + rva, replacement) ? 1 : 0;
    }
    return n;
}

} // namespace

void InstallPathfindingHooks()
{
    g_modFound = FileExists(GameDir() + "/override/M_BGREDX.lua");
    if (const char* dbg = std::getenv("IEX_PATH_DEBUG"); dbg && *dbg && *dbg != '0')
        g_debug = true;
    if (const char* parts = std::getenv("IEX_PATH_PARTS"); parts && *parts)
        g_parts = std::atoi(parts);
    if (const char* off = std::getenv("IEX_NO_PATHFINDING"); off && *off && *off != '0') {
        Log("Pathfinding Redux: disabled by IEX_NO_PATHFINDING");
        return;
    }
    const Word base = EngineImageBase();
    const std::uint32_t walk = engineTypes.Symbol(kWalk), target = engineTypes.Symbol(kSetTarget),
                        find = engineTypes.Symbol(kFindPath), share = engineTypes.Symbol(kGetShare),
                        getInt = engineTypes.Symbol(kGetProfileInt), chitin = engineTypes.Symbol(kChitin);
    if (!walk || !target || !find || !share || !getInt || !chitin || !LoadLayout() ||
        engineTypes.CallSitesOf(kWalk).empty() || engineTypes.CallSitesOf(kSetTarget).empty() ||
        engineTypes.CallSitesOf(kFindPath).empty()) {
        Log("Pathfinding Redux: engine description incomplete, disabled");
        return;
    }
    g_walk = reinterpret_cast<WalkFn>(base + walk);
    g_setTarget = reinterpret_cast<SetTargetFn>(base + target);
    g_findPath = reinterpret_cast<FindPathFn>(base + find);
    g_getShare = reinterpret_cast<GetShareFn>(base + share);
    g_getInt = reinterpret_cast<GetIntFn>(base + getInt);
    g_chitin = reinterpret_cast<Word*>(base + chitin);
    int total = 0;
    const int n = HookSites(kWalk, reinterpret_cast<const void*>(&HookWalk), total) +
                  HookSites(kSetTarget, reinterpret_cast<const void*>(&HookSetTarget), total) +
                  HookSites(kFindPath, reinterpret_cast<const void*>(&HookFindPath), total);
    g_installed = n == total;
    hp::MarkInstalled(hp::kAlliedPassThrough, g_installed, n, g_installed ? nullptr : "some call sites not hooked");
    Log("Pathfinding Redux (native allied pass-through): %d/%d call sites hooked%s%s", n, total,
        g_installed ? "" : ", PARTLY FAILED: policy off", g_modFound ? ", mod installed" : "");
}

void OpenLuaPathfinding(lua_State* L)
{
    // On by default when the BG Pathfinding Redux mod is installed; Baldur.lua [IEX] 'Pathfinding Redux' 0 / 1
    // (IEX options) or IEX_PATHFINDING=0/1 override it.
    int option = g_getInt ? g_getInt("IEX", "Pathfinding Redux", -1) : -1;
    if (const char* env = std::getenv("IEX_PATHFINDING"); env && *env)
        option = std::atoi(env);
    g_enabled = g_installed && (option < 0 ? g_modFound : option != 0);
    g_combatOnly = ModIniValue("OutOfCombatOnly") == 1;
    PublishFeature(L);
    lua.pushcclosure(L, LuaPathfinding, 0);
    lua.setglobal(L, "IEX_PathfindingRedux");
    lua.pushcclosure(L, LuaPathCheck, 0);
    lua.setglobal(L, "IEX_PathfindingCheck");
    if (g_enabled) {
        // The mod's own loader (override/M_BGREDX.lua) returns at once when this global is set: its runtime would
        // need EEex's assembly API, IEX runs the policy natively instead.
        lua.pushboolean(L, 1);
        lua.setglobal(L, "MRIP_DispatchLoaded");
        lua.createtable(L, 0, 3);
        SetBool(L, "supported", true);
        lua.pushstring(L, "IEX native");
        lua.setfield(L, -2, "provider");
        lua.setglobal(L, "MRIP_CompatibilityStatus");
    }
    Log("Pathfinding Redux: %s, out-of-combat-only %s", g_enabled ? "on" : "off", g_combatOnly ? "on" : "off");
}

} // namespace iex
