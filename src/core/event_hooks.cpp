// Engine hooks that turn engine activity into IEX events (see lua/EEex_Listeners.lua for the Lua side).
// Every hook is a call-site hook: the replacement calls the original function and dispatches (after it,
// unless noted).
// Replacements only take integer/pointer arguments, so the same code works with the MSVC x64 and SysV ABIs
// (`this` is simply the first argument).
#include "event_hooks.h"

#include "callsite_hook.h"
#include "engine_types.h"
#include "events.h"
#include "framerate.h"
#include "object_ids.h"
#include "iex_core.h"
#include "log.h"
#include "platform_memory.h"

#include <cstring>

namespace iex {

std::uintptr_t g_spriteUnderConstruction = 0;

namespace {

using Word = std::uintptr_t;

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

// --- UI: main menu file loaded / reloaded ---

constexpr const char* kUiLoadMenu = "_Z10uiLoadMenuP8CResText";  // uiLoadMenu(CResText*)
constexpr const char* kUiRefreshMenu = "_Z13uiRefreshMenuv";       // uiRefreshMenu(): re-parses UI.MENU
bool g_mainMenuLoaded = false;
bool g_inRefresh = false;

// The engine parses UI.MENU through uiLoadMenu at startup, and again on a UI reload, either through
// uiRefreshMenu (which may inline uiLoadMenu) or by calling uiLoadMenu directly (build dependent).
Word HookUiLoadMenu(Word resText)
{
    // TranslationLoaded: UI.MENU's first Lua block runs the language file again (Infinity_DoFile("L_" ..)),
    // which replaces uiStrings; the Lua side reports the event right after that file ran (as EEex: strings mods
    // add to uiStrings from the listener stay), or after the parse when the file did not run (IEX_Events.lua).
    if (!g_mainMenuLoaded && !g_inRefresh) {
        DispatchEvent("MenuBeforeMainFileLoaded");
    } else if (!g_inRefresh) {
        DispatchEvent("MenuBeforeMainFileReloaded");
    }
    if (!g_inRefresh)
        DispatchEvent("IEX_MainFileParseStart");
    const Word result = Engine<Word (*)(Word)>(kUiLoadMenu)(resText);
    if (!g_inRefresh)
        DispatchEvent("IEX_MainFileParseEnd");
    if (!g_inRefresh) {
        DispatchEvent(g_mainMenuLoaded ? "MenuMainFileReloaded" : "MenuMainFileLoaded");
        g_mainMenuLoaded = true;
    }
    return result;
}

Word HookUiRefreshMenu()
{
    DispatchEvent("MenuBeforeMainFileReloaded");
    DispatchEvent("IEX_MainFileParseStart");
    g_inRefresh = true;
    const Word result = Engine<Word (*)()>(kUiRefreshMenu)();
    g_inRefresh = false;
    DispatchEvent("IEX_MainFileParseEnd");
    DispatchEvent("MenuMainFileReloaded");
    return result;
}

// --- Game: first engine tick after the UI is up ---

constexpr const char* kChitinUpdate = "_ZN7CChitin6UpdateEv";  // CChitin::Update()
bool g_gameStateInitialized = false;

Word HookChitinUpdate(Word self)
{
    FrameRateOnLogicTick();
    const Word result = Engine<Word (*)(Word)>(kChitinUpdate)(self);
    DispatchEvent("EngineTickDone");
    if (!g_gameStateInitialized && g_mainMenuLoaded) {
        g_gameStateInitialized = true;
        DispatchEvent("GameStateInitialized");
    }
    return result;
}

// --- Sprites: creature added to the game object array ---

// CGameObjectArray::Add(int* outId, CGameObject* object, int timeout) is a member function: `this` (the game's
// object array, CInfGame + 0x64f8 on Linux) comes first, though Add itself only uses the array's statics. The
// CGameSprite constructor calls it once the creature is built from its CRE data (save load, area load, summon),
// before the creature has a name or an area.
constexpr const char* kObjectArrayAdd = "_ZN16CGameObjectArray3AddEPiP11CGameObjecti";
constexpr std::uint8_t kObjectTypeSprite = 0x31;
bool g_objectArrayAddHooked = false;

Word HookObjectArrayAdd(Word self, Word outId, Word object, Word timeout)
{
    ObjectIdsBeforeAdd();
    const Word result = Engine<Word (*)(Word, Word, Word, Word)>(kObjectArrayAdd)(self, outId, object, timeout);
    ObjectIdsAfterAdd();
    static const TypeDesc* gameObject = engineTypes.Get("CGameObject");
    static const TypeDesc* sprite = engineTypes.Get("CGameSprite");
    std::uint32_t offset = 0;
    const FieldDesc* typeField = gameObject ? gameObject->Find("m_objectType", offset) : nullptr;
    // Add returns 0 on success (the constructor deletes the object otherwise).
    if (object && !(result & 0xff) && typeField && sprite &&
        *reinterpret_cast<const std::uint8_t*>(object + offset) == kObjectTypeSprite)
    {
        // The constructor has not filled in the name strings yet: CGameSprite::GetName would read garbage.
        g_spriteUnderConstruction = object;
        DispatchObjectEvent("SpriteLoaded", object, sprite);
        g_spriteUnderConstruction = 0;
    }
    return result;
}

// --- Actions: a sprite starts an action ---

// CGameSprite::SetCurrAction(const CAIAction&) is virtual and only ever called through the vtable: the sprite
// vtable slot is replaced. After the engine copied the action into m_curAction, listeners get
// (sprite, sprite.m_curAction): editing that action changes what the sprite does next.
constexpr const char* kSpriteSetCurrActionSlot = "IEX_VtSlot_SpriteSetCurrAction";
Word g_spriteSetCurrAction = 0;

Word HookSpriteSetCurrAction(Word sprite, Word action)
{
    const Word result = reinterpret_cast<Word (*)(Word, Word)>(g_spriteSetCurrAction)(sprite, action);
    static const TypeDesc* spriteType = engineTypes.Get("CGameSprite");
    static const TypeDesc* actionType = engineTypes.Get("CAIAction");
    static std::uint32_t curAction = [] {
        const TypeDesc* base = engineTypes.Get("CGameAIBase");
        std::uint32_t o = 0;
        return base && base->Find("m_curAction", o) ? o : 0u;
    }();
    static std::uint32_t actionId = [] {
        const TypeDesc* t = engineTypes.Get("CAIAction");
        std::uint32_t o = 0;
        return t && t->Find("m_actionID", o) ? o : 0u;
    }();
    // NoAction (id 0: the engine clearing the current action) is not reported, as under EEex.
    if (sprite && spriteType && actionType && curAction &&
        *reinterpret_cast<const std::int16_t*>(sprite + curAction + actionId) != 0)
        DispatchObjectsEvent("SpriteStartedAction", sprite, spriteType, sprite + curAction, actionType);
    return result;
}

bool HookVtableSlot(const char* slotName, const void* replacement, Word& original)
{
    const std::uint32_t rva = engineTypes.Symbol(slotName);
    if (!rva)
        return false;
    const Word slot = EngineImageBase() + rva;
    Word current;
    std::memcpy(&current, reinterpret_cast<const void*>(slot), sizeof(current));
    if (!current)
        return false;
    const Word value = reinterpret_cast<Word>(replacement);
    if (!platform::PatchCode(reinterpret_cast<void*>(slot), &value, sizeof(value)))
        return false;
    original = current;
    return true;
}

// --- Areas: one frame of the visible area is about to be drawn ---

// CGameArea::RenderZoomed() draws the area for every screen that shows it (world, inventory, map...), once
// per frame. Listeners run first, so a camera moved there is drawn in the same frame. Then, in the frame rate
// mode, moving objects are drawn at their interpolated position (framerate.cpp), restored right after.
constexpr const char* kAreaRenderZoomed = "_ZN9CGameArea12RenderZoomedEv";

Word HookAreaRenderZoomed(Word area)
{
    static const TypeDesc* gameArea = engineTypes.Get("CGameArea");
    if (area && gameArea)
        DispatchObjectEvent("AreaRender", area, gameArea);
    const bool interpolated = FrameInterpolationBegin(area);
    const Word result = Engine<Word (*)(Word)>(kAreaRenderZoomed)(area);
    if (interpolated)
        FrameInterpolationEnd();
    return result;
}

// --- Keyboard: SDL events polled by the engine ---

constexpr const char* kPollEvent = "SDL_PollEvent";
constexpr std::uint32_t kSdlKeyDown = 0x300;
// SDL_KeyboardEvent (SDL2): type @0, timestamp @4, windowID @8, state @12, repeat @13, keysym.scancode @16,
// keysym.sym @20.
constexpr std::size_t kKeyRepeat = 13;
constexpr std::size_t kKeySym = 20;

// Returns true if IEX consumed the event: first EEex_Key_Hook_AfterEventsPoll (a global mods may chain),
// then the KeyPressed listeners for key-down events.
bool FilterEvent(const std::uint8_t* event)
{
    if (DispatchSdlEvent(event))
        return true;
    std::uint32_t type;
    std::memcpy(&type, event, 4);
    if (type != kSdlKeyDown || event[kKeyRepeat] != 0)
        return false;
    std::int32_t sym;
    std::memcpy(&sym, event + kKeySym, 4);
    return DispatchIntegerEvent("KeyPressed", sym);
}

Word HookPollEvent(Word event)
{
    const auto poll = Engine<int (*)(Word)>(kPollEvent);
    for (;;) {
        const int got = poll(event);
        // With a null event SDL only reports whether events are pending: nothing to filter.
        if (!got || !event || !FilterEvent(reinterpret_cast<const std::uint8_t*>(event)))
            return static_cast<Word>(got);
        // Consumed: fetch the next event instead, so the engine never sees this one.
    }
}

// --- Spell lists of a creature (Bubb's Spell Menu: EEex_Sprite_AddQuickListCountsResetListener) ---
// (Spells removed from the lists are reported by the CheckQuickLists hook of lua_sprite_hooks.cpp.)

// CGameSprite::SetAllSpellsMemorized(): every memorized spell becomes castable again (rest): the castable counts
// of the spell lists are reset. Listeners get (sprite).
constexpr const char* kSetAllSpellsMemorized = "_ZN11CGameSprite21SetAllSpellsMemorizedEv";

Word HookSetAllSpellsMemorized(Word sprite)
{
    const Word result = Engine<Word (*)(Word)>(kSetAllSpellsMemorized)(sprite);
    static const TypeDesc* spriteType = engineTypes.Get("CGameSprite");
    if (sprite && spriteType)
        DispatchObjectEvent("QuickListCountsReset", sprite, spriteType);
    return result;
}

// --- Game: the game session is destroyed (quit to the main menu, before a load, new game) ---

constexpr const char* kDestroyGame = "_ZN8CInfGame11DestroyGameEhh";  // CInfGame::DestroyGame(uchar, uchar)

Word HookDestroyGame(Word game, Word a, Word b)
{
    const Word result = Engine<Word (*)(Word, Word, Word)>(kDestroyGame)(game, a, b);
    DispatchEvent("GameStateDestroyed");
    return result;
}

// --- Window: the game window changed size (CChitin::OnResizeWindow recomputes the UI screen size) ---

constexpr const char* kOnResizeWindow = "_ZN7CChitin14OnResizeWindowEii";

Word HookOnResizeWindow(Word chitin, Word w, Word h)
{
    const Word result = Engine<Word (*)(Word, Word, Word)>(kOnResizeWindow)(chitin, w, h);
    DispatchEvent("WindowResized");
    return result;
}

bool HookAll(const char* target, const void* replacement)
{
    const std::uint32_t targetRva = engineTypes.Symbol(target);
    const auto sites = engineTypes.CallSitesOf(target);
    if (!targetRva || sites.empty()) {
        Log("Event hook skipped, no call site known for %s", target);
        return false;
    }
    int hooked = 0;
    for (std::uint32_t site : sites)
        hooked += HookCallSite(EngineImageBase() + site, EngineImageBase() + targetRva, replacement) ? 1 : 0;
    Log("Event hook %s: %d/%zu call sites", target, hooked, sites.size());
    return hooked > 0;
}

} // namespace

bool ObjectArrayAddHooked()
{
    return g_objectArrayAddHooked;
}

void InstallEventHooks()
{
    HookAll(kUiLoadMenu, reinterpret_cast<const void*>(&HookUiLoadMenu));
    HookAll(kUiRefreshMenu, reinterpret_cast<const void*>(&HookUiRefreshMenu));
    HookAll(kChitinUpdate, reinterpret_cast<const void*>(&HookChitinUpdate));
    g_objectArrayAddHooked = HookAll(kObjectArrayAdd, reinterpret_cast<const void*>(&HookObjectArrayAdd));
    Log("Event hook sprite SetCurrAction slot: %s",
        HookVtableSlot(kSpriteSetCurrActionSlot, reinterpret_cast<const void*>(&HookSpriteSetCurrAction),
                       g_spriteSetCurrAction) ? "on" : "off");
    HookAll(kPollEvent, reinterpret_cast<const void*>(&HookPollEvent));
    HookAll(kAreaRenderZoomed, reinterpret_cast<const void*>(&HookAreaRenderZoomed));
    HookAll(kSetAllSpellsMemorized, reinterpret_cast<const void*>(&HookSetAllSpellsMemorized));
    HookAll(kDestroyGame, reinterpret_cast<const void*>(&HookDestroyGame));
    HookAll(kOnResizeWindow, reinterpret_cast<const void*>(&HookOnResizeWindow));
}

} // namespace iex
