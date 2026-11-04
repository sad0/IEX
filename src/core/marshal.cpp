// See marshal.h. Format and placement observed by saving under EEex 1.3.1 (tools/difftest focus steps msave*,
// a save written under EEex); engine functions: IEX-data/engine/win/verified_marshal.json.
#include "marshal.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "event_hooks.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstdint>
#include <cstring>
#include <string>

namespace iex {

namespace {

using Word = std::uintptr_t;

constexpr const char* kSpriteMarshal = "_ZN11CGameSprite7MarshalEPPhPiPth";
constexpr const char* kSpriteCopy = "_ZN11CGameSprite4CopyEiiii";
constexpr const char* kListMarshal = "_ZN15CGameEffectList7MarshalEPPhhii";
constexpr const char* kListUnmarshal = "_ZN15CGameEffectList9UnmarshalEPhjP11CGameSpriteh";

constexpr std::size_t kRecord = 0x108;  // saved effect record (EFF V2 body)
constexpr char kMagic[8] = {'X', '-', 'B', 'I', 'V', '1', '.', '0'};

lua_State* g_L = nullptr;
Word g_spriteMarshal = 0, g_spriteCopy = 0, g_listMarshal = 0, g_listUnmarshal = 0;
// The creature whose CGameSprite::Marshal is running (its effect list is the next one marshalled), 0 otherwise.
Word g_marshalSprite = 0;
int g_copyDepth = 0;

template <typename T>
T Engine(const char* name)
{
    const std::uint32_t rva = engineTypes.Symbol(name);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

void PushSprite(lua_State* L, Word sprite) { PushObject(L, sprite, engineTypes.Get("CGameSprite")); }

// IEX_Marshal_Export(sprite) -> the handler stream (without the record header), or nil / "" for nothing.
bool Export(Word sprite, std::string& out)
{
    if (!g_L)
        return false;
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, "IEX_Marshal_Export");
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return false;
    }
    PushSprite(L, sprite);
    bool ok = false;
    if (lua.pcallk(L, 1, 1, 0, 0, nullptr) == 0) {
        if (lua.type(L, -1) == LUA_TSTRING) {
            std::size_t len = 0;
            const char* s = lua.tolstring(L, -1, &len);
            out.assign(s, len);
            ok = len > 0;
        }
    } else {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("IEX_Marshal_Export failed: %s", err ? err : "(unknown)");
    }
    lua.settop(L, top);
    return ok;
}

void Import(Word sprite, const std::uint8_t* data, std::size_t len)
{
    if (!g_L)
        return;
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, "IEX_Marshal_Import");
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return;
    }
    PushSprite(L, sprite);
    if (data)
        lua.pushlstring(L, reinterpret_cast<const char*>(data), len);
    else
        lua.pushnil(L);
    // Inside the creature's constructor: no name yet (EEex_Sprite_GetName gives "" there, as under EEex).
    const std::uintptr_t saved = g_spriteUnderConstruction;
    g_spriteUnderConstruction = sprite;
    const int status = lua.pcallk(L, 2, 0, 0, 0, nullptr);
    g_spriteUnderConstruction = saved;
    if (status != 0) {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("IEX_Marshal_Import failed: %s", err ? err : "(unknown)");
    }
    lua.settop(L, top);
}

// CGameSprite::Marshal(uchar** out, int* size, ushort* ..., uchar): remembers the creature for the effect list hook.
Word HookSpriteMarshal(Word sprite, Word out, Word size, Word a3, Word a4)
{
    const Word saved = g_marshalSprite;
    g_marshalSprite = sprite;
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(g_spriteMarshal)(sprite, out, size, a3, a4);
    g_marshalSprite = saved;
    return r;
}

// CGameSprite::Copy(int, int, int, int): the creature is marshalled and rebuilt as a clone.
Word HookSpriteCopy(Word sprite, Word a1, Word a2, Word a3, Word a4)
{
    ++g_copyDepth;
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(g_spriteCopy)(sprite, a1, a2, a3, a4);
    --g_copyDepth;
    return r;
}

// CGameEffectList::Marshal(uchar** out, uchar, int, int) -> bytes in *out (operator new[], freed by the caller).
// For a creature's list the handler records are appended (same allocator family: the engine CRT malloc/free).
Word HookListMarshal(Word list, Word out, Word a2, Word a3, Word a4)
{
    const Word sprite = g_marshalSprite;
    g_marshalSprite = 0;  // only the creature's own list, once
    const std::int32_t size = static_cast<std::int32_t>(
        reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(g_listMarshal)(list, out, a2, a3, a4));
    g_marshalSprite = sprite;
    if (!sprite || !out || size < 0)
        return static_cast<std::uint32_t>(size);
    std::string stream;
    if (!Export(sprite, stream))
        return static_cast<std::uint32_t>(size);
    const std::size_t extra = (sizeof(kMagic) + stream.size() + kRecord - 1) / kRecord * kRecord;
    const auto alloc = Engine<void* (*)(std::size_t)>("SDL_malloc");
    const auto release = Engine<void (*)(void*)>("SDL_free");
    if (!alloc || !release || extra > 0x100000)
        return static_cast<std::uint32_t>(size);
    auto* buffer = static_cast<std::uint8_t*>(alloc(static_cast<std::size_t>(size) + extra));
    if (!buffer)
        return static_cast<std::uint32_t>(size);
    auto** slot = reinterpret_cast<std::uint8_t**>(out);
    if (size > 0 && *slot) {
        std::memcpy(buffer, *slot, static_cast<std::size_t>(size));
        release(*slot);
    }
    std::uint8_t* tail = buffer + size;
    std::memset(tail, 0, extra);
    std::memcpy(tail, kMagic, sizeof(kMagic));
    std::memcpy(tail + sizeof(kMagic), stream.data(), stream.size());
    *slot = buffer;
    return static_cast<std::uint32_t>(size + static_cast<std::int32_t>(extra));
}

// CGameEffectList::Unmarshal(uchar* data, uint size, CGameSprite* sprite, uchar v2Records).
void HookListUnmarshal(Word list, Word data, Word size, Word sprite, Word v2)
{
    const auto original = reinterpret_cast<void (*)(Word, Word, Word, Word, Word)>(g_listUnmarshal);
    const std::uint32_t bytes = static_cast<std::uint32_t>(size);
    if (!sprite || !(v2 & 0xff) || !data) {
        original(list, data, size, sprite, v2);
        return;
    }
    const auto* p = reinterpret_cast<const std::uint8_t*>(data);
    std::uint32_t at = 0;
    while (at + kRecord <= bytes && std::memcmp(p + at, kMagic, sizeof(kMagic)) != 0)
        at += kRecord;
    if (at + kRecord > bytes) {
        original(list, data, size, sprite, v2);
        Import(sprite, nullptr, 0);
        return;
    }
    original(list, data, at, sprite, v2);
    Import(sprite, p + at + sizeof(kMagic), bytes - at - sizeof(kMagic));
}

int HookAll(const char* target, Word& original, const void* replacement)
{
    const std::uint32_t rva = engineTypes.Symbol(target);
    if (!rva)
        return 0;
    original = EngineImageBase() + rva;
    int n = 0;
    for (std::uint32_t site : engineTypes.CallSitesOf(target))
        n += HookCallSite(EngineImageBase() + site, original, replacement) ? 1 : 0;
    return n;
}

int LuaIsMarshallingCopy(lua_State* L)
{
    lua.pushboolean(L, g_copyDepth > 0);
    return 1;
}

} // namespace

void OpenLuaMarshal(lua_State* L)
{
    g_L = L;
    lua.pushcclosure(L, LuaIsMarshallingCopy, 0);
    lua.setglobal(L, "IEX_IsMarshallingCopy");
}

void InstallMarshalHooks()
{
    // The effect list hooks only act inside the sprite hooks: without those they are not installed.
    const int sprite = HookAll(kSpriteMarshal, g_spriteMarshal, reinterpret_cast<const void*>(&HookSpriteMarshal));
    const int copy = HookAll(kSpriteCopy, g_spriteCopy, reinterpret_cast<const void*>(&HookSpriteCopy));
    int list = 0, unlist = 0;
    if (sprite > 0) {
        list = HookAll(kListMarshal, g_listMarshal, reinterpret_cast<const void*>(&HookListMarshal));
        unlist = HookAll(kListUnmarshal, g_listUnmarshal, reinterpret_cast<const void*>(&HookListUnmarshal));
    }
    Log("Marshal handlers: CGameSprite::Marshal %d, Copy %d, effect list Marshal %d / Unmarshal %d call sites", sprite,
        copy, list, unlist);
}

} // namespace iex
