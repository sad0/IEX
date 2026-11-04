// See hook_points.h.
#include "hook_points.h"

#include "log.h"
#include "lua_api.h"

#include <cstring>
#include <string>

namespace iex::hp {

namespace {

const Info kPoints[kCount] = {
    {"hitRoll", "attack", Kind::Listener, Result::Value,
     "CGameSprite::Hit: d20 attack roll, 0..19 (attacker, target, roll) -> roll"},
    {"toHitTotal", "attack", Kind::Listener, Result::Value,
     "CGameSprite::Hit: right-hand to-hit total, final (attacker, target, total) -> total"},
    {"critThreshold", "attack", Kind::Listener, Result::Value,
     "CGameSprite::Hit: critical threshold, CDerivedStats::GetCriticalValue (attacker, target, value) -> value"},
    {"critBlocked", "attack", Kind::Switch, Result::None,
     "CGameSprite::Hit: a critical stopped by a helmet sets the critical flag to 2 instead of 0"},
    {"attackResult", "attack", Kind::Listener, Result::None, "CGameSprite::Hit: hit or miss (hit 0/1)"},
    {"damageRoll", "attack", Kind::Listener, Result::Value,
     "CGameSprite::Damage: weapon dice roll + damage bonus (attacker, target, damage) -> damage"},
    {"critMultiplier", "attack", Kind::Listener, Result::Value,
     "CGameSprite::Damage: critical multiplier, -1 for a helmet-stopped critical (attacker, target, m) -> m"},
    {"attackIndex", "swing", Kind::Listener, Result::None,
     "CGameSprite::Swing: attack frame reached (attacker, target, attack index)"},
    {"attackCancel", "swing", Kind::Listener, Result::AnyTrue,
     "CGameSprite::Swing: attack frame type read (attacker, target) -> true cancels the attack"},
    {"hideInSight", "stealth", Kind::Listener, Result::AnyTrue,
     "CGameSprite::Hide: an enemy sees the hider (sprite id) -> true allows hiding"},
    {"casterSchoolSpell", "save", Kind::Listener, Result::Value,
     "CSpell::GetAbilityEffect: caster school for the save penalty (caster, effect, school) -> school"},
    {"casterSchoolItem", "save", Kind::Listener, Result::Value,
     "CItem::GetAbilityEffect: caster school for the save penalty (caster, effect, school) -> school"},
    {"targetSchool", "save", Kind::Listener, Result::Value,
     "CGameEffect::CheckSave: target school for the save bonus (target, effect, school) -> school"},
    {"actionButtonL", "ui", Kind::Listener, Result::None,
     "CInfButtonArray::OnLButtonPressed: action bar button 0..12 pressed (index)"},
    {"actionButtonR", "ui", Kind::Listener, Result::None,
     "CInfButtonArray::OnRButtonPressed: action bar button 0..12 right-pressed (index)"},
    {"classDone", "chargen", Kind::Listener, Result::None,
     "CScreenCreateChar::OnDoneButtonClick: class step completed (sprite)"},
    {"profMaxUI", "chargen", Kind::Listener, Result::Value,
     "UpdateProficienciesPanel: maximum shown, its table's max field (proficiency, max) -> max"},
    {"profMax", "chargen", Kind::Listener, Result::Value,
     "OnProficiencyPlusMinusButtonClick: maximum a + may reach, GetClassProficiency (proficiency, max) -> max"},
    {"keepAmmo", "swing", Kind::Listener, Result::AnyTrue,
     "CGameSprite::Swing: one charge / piece of ammo used (sprite, item) -> true keeps the count"},
    {"groundMoveClick", "world", Kind::Listener, Result::None,
     "CGameArea::OnActionButtonClickGround in game state 0: move order (area, x, y)"},
    {"deathDrop", "world", Kind::Listener, Result::AnyTrue,
     "death effect: inventory dropped on the ground (sprite) -> true keeps it on the corpse"},
    {"respecGear", "chargen", Kind::Switch, Result::None,
     "CompleteCharacterSkills: no starting gold / weapon while the byte at a is not 0"},
    {"campMarker", "worldmap", Kind::Switch, Result::None, "world map: no party marker while the byte at a is not 0"},
    {"campSameArea", "worldmap", Kind::Listener, Result::None, "world map: the current area clicked ()"},
    {"groundContainer", "world", Kind::Listener, Result::AnyTrue,
     "UpdateVisibleGroundItems: a non-pile container in range (container, sprite) -> true lists it"},
    {"smallFootprint", "search", Kind::Switch, Result::None,
     "CSearchBitmap Add/RemoveObject: bumpable creatures take 1 square (a = 1) or none (a = 0)"},
    {"containerMarker", "world", Kind::Switch, Result::None,
     "CGameContainer::Render: permanent outline of m_drawPoly == b drawn in the color at a"},
    {"lastingModes", "modal", Kind::Switch, Result::None,
     "modal states not cancelled by actions, buttons, a failed stealth re-roll or moving; no per-round feedback"},
    {"findTrapsButton", "modal", Kind::Listener, Result::AnyTrue,
     "Find Traps button clicked (sprite) -> true = handled"},
    {"stealthReveals", "modal", Kind::Switch, Result::None,
     "stealth: reveals clear the hidden flag; talking / containers / items / friendly spells do not reveal"},
    {"spellSlots99", "chargen", Kind::Switch, Result::None,
     "CRuleTables::GetMageSpell / GetPriestSpell: class spell lists read slots 01-99 instead of 01-50"},
    {"spellLists", "chargen", Kind::Switch, Result::None,
     "CRuleTables::GetMageSpell / GetPriestSpell / GetNumPriestSpells calls: class spell lists continue past the "
     "SPWI/SPPR slots with the IEX lists (IEX_SpellList_*, IEXSPLST.2DA)"},
    {"hdTiles", "render", Kind::Switch, Result::None,
     "CVidTile::RenderTexture calls of CInfTileSet::Render: PVRZ area tiles of a TIS with tile size 128/256/512 "
     "draw 2x/4x/8x texels into the same 64x64 world tile (64 = engine as is)"},
    {"partyVision", "feature", Kind::Feature, Result::None, "fog of war: unlimited viewers (vision.cpp)"},
    {"alliedPassThrough", "feature", Kind::Feature, Result::None,
     "Pathfinding Redux policy: allies walk through one another (pathfinding.cpp)"},
    {"emptyContainerOutline", "feature", Kind::Feature, Result::None,
     "CGameContainer::Render highlight outline: B3EmptyContainer module hook (modules.cpp)"},
};

struct State_ {
    Installer install = nullptr;
    Available available = nullptr;
    bool installed = false;
    bool tried = false;
    int listening = 0;  // Lua listeners + enables
    int sites = 0;
    std::string why;
};
State_ g_state[kCount];
lua_State* g_L = nullptr;
constexpr const char* kDispatcher = "IEX_NativeHook_Fire";

void Refresh(Point p)
{
    g_active[p] = g_state[p].installed && g_state[p].listening > 0;
}

Point ArgPoint(lua_State* L, int i)
{
    const char* n = lua.type(L, i) == LUA_TSTRING ? lua.tolstring(L, i, nullptr) : nullptr;
    return n ? Find(n) : kCount;
}

std::uintptr_t ArgWord(lua_State* L, int i)
{
    return lua.type(L, i) == LUA_TNUMBER ? static_cast<std::uintptr_t>(lua.tointegerx(L, i, nullptr)) : 0;
}

// IEX_NativeHook_Install(point [, a, b]) -> true | false, reason. Installing twice is a no-op (true).
int LuaInstall(lua_State* L)
{
    const Point p = ArgPoint(L, 1);
    if (p == kCount) {
        lua.pushboolean(L, 0);
        lua.pushstring(L, "unknown native hook");
        return 2;
    }
    std::string why;
    const bool ok = Install(p, ArgWord(L, 2), ArgWord(L, 3), why);
    lua.pushboolean(L, ok ? 1 : 0);
    if (ok)
        return 1;
    lua.pushstring(L, why.c_str());
    return 2;
}

int LuaInstalled(lua_State* L)
{
    const Point p = ArgPoint(L, 1);
    lua.pushboolean(L, p != kCount && g_state[p].installed ? 1 : 0);
    return 1;
}

int LuaSites(lua_State* L)
{
    const Point p = ArgPoint(L, 1);
    lua.pushinteger(L, p != kCount && g_state[p].installed ? g_state[p].sites : 0);
    return 1;
}

// IEX_NativeHook_SetListening(point, count): the Lua side's number of listeners (+ enables) of the point.
int LuaSetListening(lua_State* L)
{
    const Point p = ArgPoint(L, 1);
    if (p != kCount) {
        g_state[p].listening = static_cast<int>(lua.tointegerx(L, 2, nullptr));
        Refresh(p);
    }
    lua.pushboolean(L, p != kCount && g_active[p] ? 1 : 0);
    return 1;
}

const char* KindName(Kind k)
{
    return k == Kind::Listener ? "listener" : k == Kind::Switch ? "switch" : "feature";
}

const char* ResultName(Result r)
{
    return r == Result::AnyTrue ? "anyTrue" : r == Result::Value ? "value" : "none";
}

bool IsAvailable(Point p)
{
    const State_& s = g_state[p];
    return s.installed || (s.available ? s.available() : s.install != nullptr);
}

// IEX_NativeHook_Points() -> { [name] = {category, kind, result, moment, available, installed, active, sites, why} }
int LuaPoints(lua_State* L)
{
    lua.createtable(L, 0, kCount);
    for (int i = 0; i < kCount; ++i) {
        const Point p = static_cast<Point>(i);
        const Info& in = kPoints[i];
        const State_& s = g_state[i];
        lua.createtable(L, 0, 9);
        lua.pushstring(L, in.category);
        lua.setfield(L, -2, "category");
        lua.pushstring(L, KindName(in.kind));
        lua.setfield(L, -2, "kind");
        lua.pushstring(L, ResultName(in.result));
        lua.setfield(L, -2, "result");
        lua.pushstring(L, in.moment);
        lua.setfield(L, -2, "moment");
        lua.pushboolean(L, IsAvailable(p) ? 1 : 0);
        lua.setfield(L, -2, "available");
        lua.pushboolean(L, s.installed ? 1 : 0);
        lua.setfield(L, -2, "installed");
        lua.pushboolean(L, g_active[i] ? 1 : 0);
        lua.setfield(L, -2, "active");
        lua.pushinteger(L, s.sites);
        lua.setfield(L, -2, "sites");
        if (!s.why.empty()) {
            lua.pushstring(L, s.why.c_str());
            lua.setfield(L, -2, "why");
        }
        lua.setfield(L, -2, in.name);
    }
    return 1;
}

void Register(lua_State* L, const char* name, lua_CFunction fn)
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

const Info& InfoOf(Point p)
{
    return kPoints[p];
}

Point Find(const char* name)
{
    for (int i = 0; i < kCount; ++i)
        if (std::strcmp(kPoints[i].name, name) == 0)
            return static_cast<Point>(i);
    return kCount;
}

void SetInstaller(Point p, Installer install, Available available)
{
    g_state[p].install = install;
    g_state[p].available = available;
}

void MarkInstalled(Point p, bool installed, int sites, const char* why)
{
    State_& s = g_state[p];
    s.installed = installed;
    s.tried = true;
    s.sites = installed ? sites : 0;
    s.why = why ? why : "";
    Refresh(p);
}

void SetSites(Point p, int sites)
{
    g_state[p].sites = sites;
}

bool Install(Point p, std::uintptr_t a, std::uintptr_t b, std::string& why)
{
    State_& s = g_state[p];
    if (s.installed)
        return true;
    if (!s.install) {
        why = s.tried && !s.why.empty() ? s.why : "not installable on demand on this build";
        return false;
    }
    s.tried = true;
    s.installed = s.install(why, a, b);
    if (s.installed) {
        if (s.sites == 0)
            s.sites = 1;
        s.why.clear();
        Log("Native hook %s installed", kPoints[p].name);
    } else {
        s.why = why;
        Log("Native hook %s NOT installed: %s", kPoints[p].name, why.c_str());
    }
    Refresh(p);
    return s.installed;
}

bool Installed(Point p)
{
    return g_state[p].installed;
}

lua_State* State()
{
    return g_L;
}

bool BeginFire(Point p, int& top)
{
    lua_State* L = g_L;
    if (!L)
        return false;
    top = lua.gettop(L);
    lua.getglobal(L, kDispatcher);
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return false;
    }
    lua.pushstring(L, kPoints[p].name);
    return true;
}

bool EndFire(Point p, int nargs, int top)
{
    lua_State* L = g_L;
    (void)top;
    if (lua.pcallk(L, nargs + 1, 1, 0, 0, nullptr) == 0)
        return true;
    const char* err = lua.tolstring(L, -1, nullptr);
    Log("[hooks] Lua error at native hook %s: %s", kPoints[p].name, err ? err : "(unknown)");
    return false;
}

void Finish(int top)
{
    lua.settop(g_L, top);
}

bool ResultBool()
{
    return lua.toboolean(g_L, -1) != 0;
}

bool ResultInteger(std::int64_t& value)
{
    lua_State* L = g_L;
    if (lua.type(L, -1) == LUA_TNIL)
        return false;
    int isNum = 0;
    const lua_Integer v = lua.tointegerx(L, -1, &isNum);
    value = isNum ? static_cast<std::int64_t>(v) : 0;
    return true;
}

void OpenLua(lua_State* L)
{
    g_L = L;
    Register(L, "IEX_NativeHook_Install", LuaInstall);
    Register(L, "IEX_NativeHook_Installed", LuaInstalled);
    Register(L, "IEX_NativeHook_Sites", LuaSites);
    Register(L, "IEX_NativeHook_SetListening", LuaSetListening);
    Register(L, "IEX_NativeHook_Points", LuaPoints);
    lua.getglobal(L, "IEX_Features");
    if (lua.type(L, -1) != LUA_TTABLE) {
        lua.settop(L, -2);
        lua.createtable(L, 0, 4);
        lua.pushvalue(L, -1);
        lua.setglobal(L, "IEX_Features");
    }
#ifdef _WIN32
    lua.pushstring(L, "win64");
#else
    lua.pushstring(L, "linux64");
#endif
    lua.setfield(L, -2, "platform");
    // IEX_Features.nativeHooks[point] = the point exists on this build (its sites are in the engine description).
    lua.createtable(L, 0, kCount);
    for (int i = 0; i < kCount; ++i) {
        lua.pushboolean(L, IsAvailable(static_cast<Point>(i)) ? 1 : 0);
        lua.setfield(L, -2, kPoints[i].name);
    }
    lua.setfield(L, -2, "nativeHooks");
    lua.settop(L, -2);
}

} // namespace iex::hp
