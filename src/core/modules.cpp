// See modules.h. Engine evidence: IEX-data/engine/win/verified_modules.json (CGameContainer::Render, its vtable
// slot, CInfinity::OutlinePoly).
#include "modules.h"

#include "callsite_hook.h"
#include "hook_points.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_memory.h"
#include "lua_objects.h"
#include "platform_memory.h"

#include <cstdint>
#include <cstring>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kContainerRender = "_ZN14CGameContainer6RenderEP9CGameAreaP8CVidMode";
constexpr const char* kContainerRenderSlot = "IEX_VtSlot_ContainerRender";
constexpr const char* kOutlinePoly = "_ZN9CInfinity11OutlinePolyEPK6CPointsRK5CRectj";
constexpr const char* kEmptyContainerLabel = "Hook-CGameContainer::Render()-B3EmptyContainer";
constexpr const char* kEmptyContainerHook = "B3EmptyContainer_Hook_OnBeforeContainerOutlineRender";
// Render's body is about 0x9f0 bytes (Windows) / 0xe70 (Linux): the call sites are looked for in that range.
constexpr std::size_t kRenderScan = 0x1000;
// The permanent outline (m_drawPoly > 0, Find Traps) is drawn with this hard-coded color; the highlight (hover,
// Tab key) with green / cyan. Only the highlight goes through the hook, as under EEex.
constexpr std::uint32_t kDrawPolyColor = 0xFF;

lua_State* g_L = nullptr;
Word g_render = 0;        // original CGameContainer::Render (from the vtable slot)
Word g_outlinePoly = 0;   // CInfinity::OutlinePoly
Word g_container = 0;     // container being drawn (set around Render)
bool g_hookEnabled = false;
// Marker color (SadoEE #21 valuable containers): a container whose m_drawPoly holds g_marker gets its permanent
// outline in the color stored at g_markerColor instead of the engine's red.
Word g_markerColor = 0;
int g_marker = 0;
std::uint32_t g_drawPolyOffset = 0;

void CallHook(Word container, std::uint32_t& color)
{
    lua_State* L = g_L;
    if (!L)
        return;
    const int top = lua.gettop(L);
    lua.getglobal(L, kEmptyContainerHook);
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return;
    }
    static const TypeDesc* containerType = engineTypes.Get("CGameContainer");
    static const TypeDesc* boxType = engineTypes.Get("IEX_UIntValue");
    std::uint32_t box = color;
    PushObject(L, container, containerType);
    PushObject(L, reinterpret_cast<Word>(&box), boxType);
    if (lua.pcallk(L, 2, 0, 0, 0, nullptr) == 0) {
        color = box;
    } else {
        static int errors = 0;
        const char* err = lua.tolstring(L, -1, nullptr);
        if (errors++ < 10)
            Log("Lua error in %s: %s", kEmptyContainerHook, err ? err : "(unknown)");
    }
    lua.settop(L, top);
}

Word HookContainerRender(Word container, Word area, Word vid)
{
    const Word previous = g_container;
    g_container = container;
    const Word result = reinterpret_cast<Word (*)(Word, Word, Word)>(g_render)(container, area, vid);
    g_container = previous;
    return result;
}

Word HookOutlinePoly(Word infinity, Word points, Word count, Word rect, Word color)
{
    std::uint32_t c = static_cast<std::uint32_t>(color);
    if (g_hookEnabled && g_container && c != kDrawPolyColor)
        CallHook(g_container, c);
    else if (g_markerColor && g_container && c == kDrawPolyColor &&
             *reinterpret_cast<const std::int16_t*>(g_container + g_drawPolyOffset) == g_marker)
        c = *reinterpret_cast<const std::uint32_t*>(g_markerColor);
    return reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(g_outlinePoly)(infinity, points, count, rect, c);
}

std::int32_t Rel32(Word at)
{
    std::int32_t v;
    std::memcpy(&v, reinterpret_cast<const void*>(at), sizeof(v));
    return v;
}

// IEX_SetEmptyContainerHook(on): the Empty Container module calls the Lua hook for highlighted containers.
int LuaSetHook(lua_State* L)
{
    g_hookEnabled = lua.toboolean(L, 1) != 0;
    lua.pushboolean(L, g_render != 0 && g_outlinePoly != 0);
    return 1;
}

} // namespace

bool SetContainerMarkerColor(std::uintptr_t colorAddress, int marker)
{
    const TypeDesc* t = engineTypes.Get("CGameContainer");
    std::uint32_t offset = 0;
    if (!g_render || !g_outlinePoly || !colorAddress || !t || !t->Find("m_drawPoly", offset))
        return false;
    g_drawPolyOffset = offset;
    g_marker = marker;
    g_markerColor = colorAddress;
    return true;
}

void OpenLuaModules(lua_State* L)
{
    g_L = L;
    lua.pushcclosure(L, LuaSetHook, 0);
    lua.setglobal(L, "IEX_SetEmptyContainerHook");
}

void InstallModuleHooks()
{
    const Word base = EngineImageBase();
    const std::uint32_t renderRva = engineTypes.Symbol(kContainerRender);
    const std::uint32_t slotRva = engineTypes.Symbol(kContainerRenderSlot);
    const std::uint32_t outlineRva = engineTypes.Symbol(kOutlinePoly);
    if (!renderRva || !slotRva || !outlineRva) {
        Log("Modules: container outline hook skipped (engine description lacks Render / its slot / OutlinePoly)");
        return;
    }
    const Word render = base + renderRva;
    const Word slot = base + slotRva;
    const Word outline = base + outlineRva;
    Word current = 0;
    std::memcpy(&current, reinterpret_cast<const void*>(slot), sizeof(current));
    if (current != render) {
        Log("Modules: CGameContainer::Render slot holds %p, expected %p: container outline hook skipped",
            reinterpret_cast<void*>(current), reinterpret_cast<void*>(render));
        return;
    }
    // Every `call OutlinePoly` in Render: the highlight calls (and the red permanent one, passed through).
    int sites = 0;
    Word label = 0;
    for (Word p = render; p + 5 < render + kRenderScan; ++p) {
        if (*reinterpret_cast<const std::uint8_t*>(p) != 0xE8)
            continue;
        if (p + 5 + static_cast<std::intptr_t>(Rel32(p + 1)) != outline)
            continue;
        if (!HookCallSite(p, outline, reinterpret_cast<const void*>(&HookOutlinePoly)))
            continue;
        ++sites;
        // EEex's label: the highlight call right before the m_drawPoly check (`cmp word [reg+0x9a0], 0` follows
        // within a few bytes). Mods (SadoEE) read the code after it.
        if (!label)
            for (Word q = p + 5; q < p + 5 + 24; ++q)
                if (std::memcmp(reinterpret_cast<const void*>(q), "\xA0\x09\x00\x00", 4) == 0) {
                    label = p;
                    break;
                }
    }
    if (!sites) {
        Log("Modules: no OutlinePoly call found in CGameContainer::Render: container outline hook skipped");
        return;
    }
    g_outlinePoly = outline;
    const Word replacement = reinterpret_cast<Word>(&HookContainerRender);
    if (!platform::PatchCode(reinterpret_cast<void*>(slot), &replacement, sizeof(replacement))) {
        Log("Modules: CGameContainer::Render slot not writable: container outline hook skipped");
        return;
    }
    g_render = render;
    if (label)
        RegisterRuntimeLabel(kEmptyContainerLabel, label);
    Log("Modules: container outline hook on (%d OutlinePoly call sites, label %s)", sites, label ? "set" : "not found");
    hp::MarkInstalled(hp::kEmptyContainerOutline, true, sites);
}

} // namespace iex
