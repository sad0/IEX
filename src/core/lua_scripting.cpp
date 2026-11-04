// Script text parsed by the engine's own BCS compiler (CAIScriptFile), evaluated with the engine's condition and
// response code, and object searches through CGameArea::GetAllInRange. Engine evidence: verified_ta.json.
//
// One CAIScriptFile is built on first use (its constructor loads TRIGGER/ACTION/OBJECT.IDS) and reused. Parsing a
// conditional leaves a new CAICondition in the file (slot +0x18), a response a new CAIResponse (slot +0x20): IEX
// takes the object out of the slot, so it lives until Lua frees it, and the next parse starts from an empty slot.
#include "lua_scripting.h"

#include "callsite_hook.h"
#include "effects.h"
#include "engine_types.h"
#include "iex_core.h"
#include "log.h"
#include "lua_api.h"
#include "lua_objects.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <string>
#include <unordered_set>
#include <vector>

namespace iex {

namespace {

using Word = std::uintptr_t;

template <typename T>
T Engine(const char* mangled)
{
    const std::uint32_t rva = engineTypes.Symbol(mangled);
    return rva ? reinterpret_cast<T>(EngineImageBase() + rva) : nullptr;
}

template <typename T>
T Read(Word address)
{
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address), sizeof(T));
    return value;
}

constexpr const char* kScriptFileCtor = "_ZN13CAIScriptFileC1Ev";
constexpr const char* kParseConditional = "_ZN13CAIScriptFile22ParseConditionalStringE7CString";
constexpr const char* kParseResponse = "_ZN13CAIScriptFile19ParseResponseStringE7CString";
constexpr const char* kParseObject = "_ZN13CAIScriptFile15ParseObjectTypeER7CString";
constexpr const char* kHold = "_ZN12CAICondition4HoldER13CTypedPtrListI8CPtrListP10CAITriggerEP11CGameAIBase";
constexpr const char* kConditionDtor = "_ZN12CAIConditionD1Ev";
constexpr const char* kResponseDtor = "_ZN11CAIResponseD1Ev";
constexpr const char* kStringCtor = "_ZN7CStringC1EPKc";
constexpr const char* kStringDtor = "_ZN7CStringD1Ev";
constexpr const char* kDelete = "IEX_OperatorDelete";
constexpr const char* kListCtor = "_ZN8CPtrListC1Ei";
constexpr const char* kListRemoveAll = "_ZN8CPtrList9RemoveAllEv";
constexpr const char* kGetAllInRange =
    "_ZN9CGameArea13GetAllInRangeERK6CPointRK13CAIObjectTypesPKhR13CTypedPtrListI8CPtrListPiEii";
constexpr const char* kInsertResponse = "_ZN11CGameAIBase14InsertResponseER11CAIResponseii";
constexpr const char* kActionCopy = "_ZN9CAIActionC1ERKS_";
constexpr const char* kActionDecode = "_ZN9CAIAction6DecodeEP11CGameAIBase";
constexpr const char* kIdListFind = "_ZNK9CAIIdList4FindEi";
constexpr const char* kVtOffExecuteAction = "IEX_VtOff_ExecuteAction";
constexpr const char* kSpriteTerrain = "_ZN11CGameSprite22GetVisibleTerrainTableEv";
constexpr const char* kSpriteVisualRange = "_ZN11CGameSprite14GetVisualRangeEv";
constexpr const char* kBaseVisualRange = "_ZN11CGameAIBase14GetVisualRangeEv";

constexpr const char* kDecode = "_ZN13CAIObjectType6DecodeEP11CGameAIBase";
constexpr const char* kTypeGetShare = "_ZNK13CAIObjectType8GetShareEP11CGameAIBasei";
constexpr const char* kNoOne = "_ZN13CAIObjectType5NOONEE";
constexpr const char* kStringAssign = "_ZN7CStringaSEPKc";
constexpr const char* kObjectGetShare = "_ZN16CGameObjectArray8GetShareEiPP11CGameObjectb";
constexpr const char* kNearestOpenSquare = "_ZN13CSearchBitmap20GetNearestOpenSquareE6CPointPKhhs";

// CAIScriptFile slots (same on both builds), CAICondition / CAIResponse sizes (operator new in the parsers).
constexpr std::size_t kFileCondition = 0x18, kFileResponse = 0x20;
constexpr std::size_t kConditionSize = 0x38, kResponseSize = 0x40;
constexpr std::size_t kScriptFileAlloc = 0x400;  // Linux object is 0x1b0 (InitGame new); room for the MSVC layout
constexpr std::size_t kObjectTypeAlloc = 0x20;   // CAIObjectType is 0x18
constexpr std::size_t kListAlloc = 0x40;         // CPtrList is 0x38
// CPtrList / node layout (both builds): head +8; node next +0, data +0x10.
constexpr std::size_t kListHead = 0x8, kNodeData = 0x10;
constexpr std::uint8_t kObjectTypeSprite = 0x31;
// CAIResponse: action list (CPtrList of CAIAction*) at +8 on both builds, so its head is at +0x10.
constexpr std::size_t kResponseActions = 0x8;
// CAIAction (0x88, both builds): owned CStrings at +8/+0x20/+0x38 (CAIObjectType names), +0x60, +0x68, +0x80.
constexpr std::size_t kActionSize = 0x88;
constexpr std::size_t kActionStrings[] = {0x8, 0x20, 0x38, 0x60, 0x68, 0x80};
// CGameAIBase current-action state, written by CGameAIBase::SetCurrAction on both builds: +0x3e0 i32 / +0x3e4 i16
// (response ids, -1 for NO_ACTION), +0x3e8 i32 and +0x3ec i16 (zeroed: action step counters), m_curAction +0x3f8,
// +0x4ba i16 (set to -1; OnActionRemoval runs on the old action when it is not -1).
constexpr std::size_t kAIStateBegin = 0x3e0, kAIStateEnd = 0x3f0;
constexpr std::size_t kAIStepFlag = 0x3e8, kAIStepCount = 0x3ec, kAICurAction = 0x3f8, kAIActionState = 0x4ba;
// CInfGame id list of the actions SetCurrAction does not decode (object specifiers resolved later).
constexpr std::size_t kGameNoDecodeList = 0xa8;
// CGameAnimation inside the sprite: type object +0, override flags +8 (bit 2), override personal space +0x10.
constexpr std::size_t kAnimFlags = 0x8, kAnimPersonalSpace = 0x10;

// CAIObjectType (0x18, both builds): name CString +0, instance id +0xc, object-function bytes +0x10..+0x14 (first =
// innermost, 0 ends the list). OBJECT.IDS values: 1 Myself; 115 EEex_LuaObject, 117 EEex_Target, 118 EEex_LuaDecode
// (IEX.tp2).
constexpr std::size_t kTypeName = 0x0, kTypeFields = 0x8, kTypeFieldsSize = 0x10, kTypeSpecial = 0x10;
constexpr int kSpecialCount = 5;
constexpr std::uint8_t kSpecialMyself = 1, kSpecialLuaObject = 115, kSpecialTarget = 117, kSpecialLuaDecode = 118;
// CGameArea: search map (CSearchBitmap) at +0xa60 on both builds (CGameSprite::JumpToPoint); its squares are 16x12 px.
constexpr std::size_t kAreaSearchMap = 0xa60;
constexpr int kSquareWidth = 16, kSquareHeight = 12;
// Terrain cost table for a walking creature (16 search-map values, 0xff = blocked): the bytes of the game's
// CGameObject::DEFAULT_TERRAIN_TABLE (Linux symtab 0xac4bf0), which has no symbol on the Windows build.
constexpr std::uint8_t kDefaultTerrain[16] = {0xff, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
                                              0xff, 0x05, 0xff, 0x05, 0xff, 0xff, 0xff, 0x05};

Word g_scriptFile = 0;
Word g_decode = 0;
lua_State* g_L = nullptr;
std::unordered_set<Word> g_parsedObjectTypes;

std::uint32_t FieldOffset(const char* type, const char* field)
{
    const TypeDesc* t = engineTypes.Get(type);
    std::uint32_t offset = 0;
    return t && t->Find(field, offset) ? offset : 0;
}

bool IsSprite(Word object)
{
    static const std::uint32_t typeOffset = FieldOffset("CGameObject", "m_objectType");
    return object && Read<std::uint8_t>(object + typeOffset) == kObjectTypeSprite;
}

Word ScriptFile()
{
    if (g_scriptFile)
        return g_scriptFile;
    const auto ctor = Engine<void (*)(Word)>(kScriptFileCtor);
    if (!ctor)
        return 0;
    void* p = std::calloc(1, kScriptFileAlloc);
    ctor(reinterpret_cast<Word>(p));
    g_scriptFile = reinterpret_cast<Word>(p);
    return g_scriptFile;
}

void EngineDelete(Word p, std::size_t size)
{
    // Windows: sized delete (rcx, rdx = size); Linux: operator delete(void*) ignores the second register.
    Engine<void (*)(Word, std::size_t)>(kDelete)(p, size);
}

// Runs one of the CAIScriptFile string parsers and takes the object it left in `slot`.
Word ParseInto(const char* parser, const char* text, std::size_t slot)
{
    const Word file = ScriptFile();
    const auto parse = Engine<void (*)(Word, Word*)>(parser);
    const auto stringCtor = Engine<void (*)(Word*, const char*)>(kStringCtor);
    const auto stringDtor = Engine<void (*)(Word*)>(kStringDtor);
    if (!file || !parse || !stringCtor || !stringDtor)
        return 0;
    alignas(8) Word arg = 0;  // CString passed by value = pointer to the caller's copy on both ABIs
    stringCtor(&arg, text);
    parse(file, &arg);
#if !defined(_WIN32)
    stringDtor(&arg);  // Itanium: the caller destroys by-value arguments (MSVC: the callee did)
#endif
    Word* slotPtr = reinterpret_cast<Word*>(file + slot);
    const Word object = *slotPtr;
    *slotPtr = 0;
    return object;
}

bool Available(std::initializer_list<const char*> names)
{
    for (const char* n : names)
        if (!engineTypes.Symbol(n))
            return false;
    return true;
}

// IEX_ParseConditional(text) -> address of a CAICondition, or nil.
int LuaParseConditional(lua_State* L)
{
    const char* text = lua.tolstring(L, 1, nullptr);
    if (!text || !Available({kParseConditional}))
        LuaError(L, "IEX_ParseConditional: string expected / not available for this game build");
    const Word condition = ParseInto(kParseConditional, text, kFileCondition);
    if (condition)
        lua.pushinteger(L, static_cast<lua_Integer>(condition));
    else
        lua.pushnil(L);
    return 1;
}

// IEX_ConditionHolds(condition, object) -> bool: the triggers evaluated for the script object (status triggers
// through the object; event triggers against an empty pending list, so they are false).
int LuaConditionHolds(lua_State* L)
{
    const Word condition = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const Word object = ToObjectAddress(L, 2);
    const auto hold = Engine<int (*)(Word, Word, Word)>(kHold);
    if (!condition || !object || !hold)
        LuaError(L, "IEX_ConditionHolds: condition and object expected");
    alignas(8) std::uint8_t emptyList[kListAlloc] = {};
    lua.pushboolean(L, hold(condition, reinterpret_cast<Word>(emptyList), object) != 0);
    return 1;
}

int LuaFreeConditional(lua_State* L)
{
    const Word condition = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const auto dtor = Engine<void (*)(Word)>(kConditionDtor);
    if (condition && dtor && engineTypes.Symbol(kDelete)) {
        dtor(condition);
        EngineDelete(condition, kConditionSize);
    }
    return 0;
}

// IEX_ParseResponse(text) -> address of a CAIResponse, or nil.
int LuaParseResponse(lua_State* L)
{
    const char* text = lua.tolstring(L, 1, nullptr);
    if (!text || !Available({kParseResponse}))
        LuaError(L, "IEX_ParseResponse: string expected / not available for this game build");
    const Word response = ParseInto(kParseResponse, text, kFileResponse);
    if (response)
        lua.pushinteger(L, static_cast<lua_Integer>(response));
    else
        lua.pushnil(L);
    return 1;
}

void DecodeObjectType(Word type, Word caller);

// --- EEex_LuaObject / EEex_Target in response strings: resolved when the actions are queued or run ---
//
// A parsed response keeps "EEex_LuaObject" / "EEex_Target(name)" as object functions; resolved lazily (at the
// action's own decode) they would all name whatever the Lua global / stored target holds when the action finally
// runs. So before the actions are copied into the queue (or run instantly), every object of every action that uses
// them is decoded now, for the object that gets the actions, into a concrete object: the target's own AI type with
// its instance id, no object functions left (or the NOONE fields when there is no target). The engine copies the
// actions, then the parsed response gets its original objects back, so a response kept by a mod (parse once, queue
// many times) is resolved again on its next use.

// CAIAction objects: actor +8, actee +0x20, actee2 +0x38.
constexpr std::size_t kActionObjects[] = {0x8, 0x20, 0x38};

struct SavedObjectType {
    Word type;
    std::uint8_t fields[kTypeFieldsSize];
    std::string name;
};

bool UsesScriptObject(Word type)
{
    const auto* special = reinterpret_cast<const std::uint8_t*>(type + kTypeSpecial);
    for (int i = 0; i < kSpecialCount && special[i]; ++i)
        if (special[i] == kSpecialLuaObject || special[i] == kSpecialTarget)
            return true;
    return false;
}

std::vector<SavedObjectType> ResolveResponseScriptObjects(Word response, Word caller)
{
    std::vector<SavedObjectType> saved;
    if (!g_decode || !caller)
        return saved;
    for (Word node = Read<Word>(response + kResponseActions + kListHead); node; node = Read<Word>(node)) {
        const Word action = Read<Word>(node + kNodeData);
        if (!action)
            continue;
        for (std::size_t offset : kActionObjects) {
            const Word type = action + offset;
            if (!UsesScriptObject(type))
                continue;
            SavedObjectType s;
            s.type = type;
            std::memcpy(s.fields, reinterpret_cast<const void*>(type + kTypeFields), kTypeFieldsSize);
            const char* text = Read<const char*>(type + kTypeName);
            s.name = text ? text : "";
            saved.push_back(s);
            DecodeObjectType(type, caller);
            // Fully resolved: nothing left for the action's own decode to redo.
            std::memset(reinterpret_cast<void*>(type + kTypeSpecial), 0, kSpecialCount);
        }
    }
    return saved;
}

void RestoreResponseScriptObjects(const std::vector<SavedObjectType>& saved)
{
    const auto assign = Engine<Word (*)(Word, const char*)>(kStringAssign);
    for (const SavedObjectType& s : saved) {
        std::memcpy(reinterpret_cast<void*>(s.type + kTypeFields), s.fields, kTypeFieldsSize);
        const char* text = Read<const char*>(s.type + kTypeName);
        if (assign && s.name != (text ? text : ""))
            assign(s.type + kTypeName, s.name.c_str());
    }
}

// IEX_InsertResponse(response, object): queues the response's actions on the object, before its other actions
// and without interrupting the current one (CGameAIBase::InsertResponse, no duplicate check, no interrupt).
int LuaInsertResponse(lua_State* L)
{
    const Word response = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const Word object = ToObjectAddress(L, 2);
    const auto insert = Engine<void (*)(Word, Word, Word, Word)>(kInsertResponse);
    if (!response || !object || !insert)
        LuaError(L, "IEX_InsertResponse: response and object expected");
    const std::vector<SavedObjectType> saved = ResolveResponseScriptObjects(response, object);
    insert(object, response, 0, 0);
    RestoreResponseScriptObjects(saved);
    return 0;
}

// Destroys a CAIAction in place (the engine destructor only releases its CStrings, same on both builds).
void DestroyAction(Word action)
{
    const auto stringDtor = Engine<void (*)(Word)>(kStringDtor);
    for (std::size_t offset : kActionStrings)
        stringDtor(action + offset);
}

Word Game()
{
    static const std::uint32_t gameOffset = FieldOffset("CBaldurChitin", "m_pObjectGame");
    const std::uint32_t chitinRva = engineTypes.Symbol("g_pBaldurChitin");
    const Word chitin = chitinRva ? Read<Word>(EngineImageBase() + chitinRva) : 0;
    return chitin && gameOffset ? Read<Word>(chitin + gameOffset) : 0;
}

// IEX_ExecuteResponseInstantly(response, object) -> number of actions run. Runs the response's actions now, in order,
// as the object's current action, through the object's own ExecuteAction (the vtable slot, so the sprite override and
// IEX's EEex_LuaAction hook apply), then puts the object's current action and its state back. The action queue is
// not touched. Each action is set up like CGameAIBase::SetCurrAction does it (copy, step counters 0, state -1, object
// specifiers decoded relative to the object unless the action is in the game's no-decode list), without the
// OnActionRemoval of the interrupted action and without the sprite's modal-state reset. ExecuteAction runs once per
// action: an instant action completes, an action that needs several ticks (moves, attacks, spells) only does its
// first step and is then dropped.
int LuaExecuteResponseInstantly(lua_State* L)
{
    const Word response = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const Word object = ToObjectAddress(L, 2);
    const auto copy = Engine<Word (*)(Word, Word)>(kActionCopy);
    const auto decode = Engine<void (*)(Word, Word)>(kActionDecode);
    const auto find = Engine<Word (*)(Word, int)>(kIdListFind);
    const std::uint32_t slot = engineTypes.Symbol(kVtOffExecuteAction);
    const Word game = Game();
    if (!response || !object || !copy || !decode || !find || !slot || !engineTypes.Symbol(kStringDtor) || !game)
        LuaError(L, "IEX_ExecuteResponseInstantly: response and object expected / not available for this game build");
    const Word current = object + kAICurAction;
    // Move the current action out bitwise (it owns only heap CStrings), and keep the state fields around it.
    alignas(8) std::uint8_t saved[kActionSize];
    alignas(8) std::uint8_t savedState[kAIStateEnd - kAIStateBegin];
    std::memcpy(saved, reinterpret_cast<const void*>(current), kActionSize);
    std::memcpy(savedState, reinterpret_cast<const void*>(object + kAIStateBegin), sizeof(savedState));
    const std::int16_t savedActionState = Read<std::int16_t>(object + kAIActionState);
    const auto execute = reinterpret_cast<std::int16_t (*)(Word)>(Read<Word>(Read<Word>(object) + slot));
    const std::vector<SavedObjectType> resolved = ResolveResponseScriptObjects(response, object);
    int n = 0;
    for (Word node = Read<Word>(response + kResponseActions + kListHead); node; node = Read<Word>(node)) {
        const Word action = Read<Word>(node + kNodeData);
        if (!action)
            continue;
        copy(current, action);
        *reinterpret_cast<std::int32_t*>(object + kAIStepFlag) = 0;
        *reinterpret_cast<std::int16_t*>(object + kAIStepCount) = 0;
        *reinterpret_cast<std::int16_t*>(object + kAIActionState) = -1;
        const std::int16_t id = Read<std::int16_t>(current);
        if (id != 0 && !find(game + kGameNoDecodeList, id))
            decode(current, object);
        execute(object);
        DestroyAction(current);
        ++n;
    }
    RestoreResponseScriptObjects(resolved);
    std::memcpy(reinterpret_cast<void*>(current), saved, kActionSize);
    std::memcpy(reinterpret_cast<void*>(object + kAIStateBegin), savedState, sizeof(savedState));
    *reinterpret_cast<std::int16_t*>(object + kAIActionState) = savedActionState;
    lua.pushinteger(L, n);
    return 1;
}

int LuaFreeResponse(lua_State* L)
{
    const Word response = static_cast<Word>(lua.tointegerx(L, 1, nullptr));
    const auto dtor = Engine<void (*)(Word)>(kResponseDtor);
    if (response && dtor && engineTypes.Symbol(kDelete)) {
        dtor(response);
        EngineDelete(response, kResponseSize);
    }
    return 0;
}

// Compiles an object string ("[PC]", "Player1", "LastAttackerOf(Myself)"...) into a new CAIObjectType (calloc'd,
// freed by FreeParsedObjectType), or 0.
Word ParseObjectType(const char* text)
{
    const Word file = ScriptFile();
    const auto stringCtor = Engine<void (*)(Word*, const char*)>(kStringCtor);
    const auto stringDtor = Engine<void (*)(Word*)>(kStringDtor);
    if (!text || !file || !stringCtor || !stringDtor || !Available({kParseObject}))
        return 0;
    void* result = std::calloc(1, kObjectTypeAlloc);
    alignas(8) Word arg = 0;
    stringCtor(&arg, text);
#if defined(_WIN32)
    Engine<void (*)(Word, void*, Word*)>(kParseObject)(file, result, &arg);  // this, hidden result, CString&
#else
    Engine<void (*)(void*, Word, Word*)>(kParseObject)(result, file, &arg);  // hidden result, this, CString&
#endif
    stringDtor(&arg);
    return reinterpret_cast<Word>(result);
}

void FreeParsedObjectType(Word type)
{
    const auto stringDtor = Engine<void (*)(Word*)>(kStringDtor);
    if (stringDtor)
        stringDtor(reinterpret_cast<Word*>(type + kTypeName));
    std::free(reinterpret_cast<void*>(type));
}

// IEX_ParseObjectType(text) -> CAIObjectType object (owned by IEX until IEX_FreeObjectType), or nil.
int LuaParseObjectType(lua_State* L)
{
    const Word address = ParseObjectType(lua.tolstring(L, 1, nullptr));
    if (!address)
        LuaError(L, "IEX_ParseObjectType: string expected / not available for this game build");
    g_parsedObjectTypes.insert(address);
    PushObject(L, address, engineTypes.Get("CAIObjectType"));
    return 1;
}

// IEX_FreeObjectType(objectType): frees a CAIObjectType made by IEX_ParseObjectType (others are ignored).
int LuaFreeObjectType(lua_State* L)
{
    const Word address = ToObjectAddress(L, 1);
    if (g_parsedObjectTypes.erase(address))
        FreeParsedObjectType(address);
    return 0;
}

// --- Script objects: EEex_LuaObject / EEex_Target("name") ---

Word ObjectById(std::int32_t id)
{
    const auto getShare = Engine<std::uint8_t (*)(int, Word*, bool)>(kObjectGetShare);
    Word object = 0;
    if (id == -1 || !getShare || getShare(id, &object, false) != 0)
        return 0;
    return object;
}

// Lua IEX_ResolveScriptObject(kind, callerAddress, name) -> id of the object the object function stands for, or -1.
std::int32_t ResolveScriptObject(std::uint8_t kind, Word caller, const char* name)
{
    if (!g_L)
        return -1;
    lua_State* L = g_L;
    const int top = lua.gettop(L);
    lua.getglobal(L, "IEX_ResolveScriptObject");
    if (lua.type(L, -1) != LUA_TFUNCTION) {
        lua.settop(L, top);
        return -1;
    }
    lua.pushinteger(L, kind);
    lua.pushinteger(L, static_cast<lua_Integer>(caller));
    lua.pushstring(L, name);
    std::int32_t id = -1;
    if (lua.pcallk(L, 3, 1, 0, 0, nullptr) == 0) {
        if (lua.type(L, -1) == LUA_TNUMBER)
            id = static_cast<std::int32_t>(lua.tointegerx(L, -1, nullptr));
    } else {
        const char* err = lua.tolstring(L, -1, nullptr);
        Log("Lua error in IEX_ResolveScriptObject: %s", err ? err : "(unknown)");
    }
    lua.settop(L, top);
    return id;
}

// CAIObjectType::Decode with IEX's object functions. When the type uses EEex_LuaObject, EEex_Target("name") or
// EEex_LuaDecode("chunk"), the object it names (Lua global EEex_LuaObject / the caller's stored scripting target / the
// object the chunk returns, run with EEex_LuaDecode_Object = the caller) replaces the object chain at that
// point: the engine then decodes Myself plus the outer functions relative to that object
// ("LastAttackerOf(EEex_LuaObject)"). No object -> Nobody. Other types go to the engine untouched.
void DecodeObjectType(Word type, Word caller)
{
    const auto decode = reinterpret_cast<void (*)(Word, Word)>(g_decode);
    auto* special = reinterpret_cast<std::uint8_t*>(type + kTypeSpecial);
    int at = -1;
    for (int i = 0; i < kSpecialCount && special[i]; ++i)
        if (special[i] == kSpecialLuaObject || special[i] == kSpecialTarget || special[i] == kSpecialLuaDecode)
            at = i;
    if (at < 0 || !caller) {
        decode(type, caller);
        return;
    }
    std::string name;
    if (special[at] == kSpecialTarget || special[at] == kSpecialLuaDecode) {
        const char* text = Read<const char*>(type + kTypeName);
        name = text ? text : "";
        const auto assign = Engine<Word (*)(Word, const char*)>(kStringAssign);
        if (assign)
            assign(type + kTypeName, "");  // the target key / Lua chunk, not a script name to look up
    }
    const Word object = ObjectById(ResolveScriptObject(special[at], caller, name.c_str()));
    if (!object) {
        const std::uint32_t noOne = engineTypes.Symbol(kNoOne);
        if (noOne)
            std::memcpy(reinterpret_cast<void*>(type + kTypeFields),
                        reinterpret_cast<const void*>(EngineImageBase() + noOne + kTypeFields), kTypeFieldsSize);
        return;
    }
    std::uint8_t chain[kSpecialCount] = {kSpecialMyself};
    for (int i = at + 1, j = 1; i < kSpecialCount; ++i, ++j)
        chain[j] = special[i];
    std::memcpy(special, chain, kSpecialCount);
    decode(type, object);
}

// IEX_EvalObjectString(text, caller) -> the object the object string matches for the caller (engine decode, then
// CAIObjectType::GetShare: the nearest match for type filters), or nil.
int LuaEvalObjectString(lua_State* L)
{
    const char* text = lua.tolstring(L, 1, nullptr);
    const Word caller = ToObjectAddress(L, 2);
    const auto getShare = Engine<Word (*)(Word, Word, Word)>(kTypeGetShare);
    if (!text || !caller || !g_decode || !getShare)
        LuaError(L, "IEX_EvalObjectString: object string and object expected / not available for this game build");
    const Word type = ParseObjectType(text);
    Word object = 0;
    if (type) {
        DecodeObjectType(type, caller);
        object = getShare(type, caller, 0);
        FreeParsedObjectType(type);
    }
    PushObject(L, object, engineTypes.Get("CGameObject"));
    return 1;
}

// IEX_NearestOpenPosition(area, x, y [, personalSpace [, terrainTable]]) -> x, y of the nearest walkable point of
// the area's search map (CSearchBitmap::GetNearestOpenSquare, the search the engine uses to place jumping and
// created creatures). The point itself when its square is open, else the centre of the open square found.
int LuaNearestOpenPosition(lua_State* L)
{
    const Word area = ToObjectAddress(L, 1);
    const auto x = static_cast<std::int32_t>(lua.tointegerx(L, 2, nullptr));
    const auto y = static_cast<std::int32_t>(lua.tointegerx(L, 3, nullptr));
    const lua_Integer space = lua.type(L, 4) == LUA_TNUMBER ? lua.tointegerx(L, 4, nullptr) : 3;
    const Word table = lua.type(L, 5) == LUA_TUSERDATA ? ToObjectAddress(L, 5) : 0;
    const Word terrain = table ? table : reinterpret_cast<Word>(kDefaultTerrain);
    const std::uint32_t rva = engineTypes.Symbol(kNearestOpenSquare);
    if (!area || !rva)
        LuaError(L, "IEX_NearestOpenPosition: area expected / not available for this game build");
    const Word fn = EngineImageBase() + rva;
    const std::int32_t square[2] = {x / kSquareWidth, y / kSquareHeight};
    Word point = 0;
    std::memcpy(&point, square, sizeof(square));
    const Word search = area + kAreaSearchMap;
    const Word spaceArg = static_cast<std::uint8_t>(space < 1 ? 1 : space > 255 ? 255 : space);
    const Word anyDirection = 0xffff;  // short -1: every direction
    std::int32_t found[2] = {};
#if defined(_WIN32)
    // this, hidden CPoint* result, CPoint by value, table, personal space, direction; returns the result pointer.
    reinterpret_cast<Word (*)(Word, std::int32_t*, Word, Word, Word, Word)>(fn)(search, found, point, terrain, spaceArg,
                                                                                anyDirection);
#else
    // this, CPoint in one register, table, personal space, direction; returns the CPoint in rax.
    const Word r = reinterpret_cast<Word (*)(Word, Word, Word, Word, Word)>(fn)(search, point, terrain, spaceArg,
                                                                                 anyDirection);
    std::memcpy(found, &r, sizeof(found));
#endif
    if (found[0] == square[0] && found[1] == square[1]) {
        lua.pushinteger(L, x);
        lua.pushinteger(L, y);
    } else {
        lua.pushinteger(L, found[0] * kSquareWidth + kSquareWidth / 2);
        lua.pushinteger(L, found[1] * kSquareHeight + kSquareHeight / 2);
    }
    return 2;
}

Word VisibleTerrainTable(Word object)
{
    if (IsSprite(object)) {
        const auto fn = Engine<Word (*)(Word)>(kSpriteTerrain);
        return fn ? fn(object) : 0;
    }
    return 0;
}

// IEX_VisualRange(object) -> visual range in pixels (CGameSprite / CGameAIBase::GetVisualRange).
int LuaVisualRange(lua_State* L)
{
    const Word object = ToObjectAddress(L, 1);
    const auto fn = Engine<std::uint16_t (*)(Word)>(IsSprite(object) ? kSpriteVisualRange : kBaseVisualRange);
    if (!object || !fn)
        LuaError(L, "IEX_VisualRange: object expected");
    lua.pushinteger(L, static_cast<std::int16_t>(fn(object)));
    return 1;
}

// IEX_GetAllOfTypeInRange(area, x, y, aiType, range, checkLOS, checkNonSprites, terrainTable|nil, losObject|nil)
//   -> { ids } of the objects matching aiType within range of (x, y) (CGameArea::GetAllInRange, the search of
//   NumCreature-like triggers). The LOS check uses terrainTable, else losObject's visible terrain table; without
//   either it is skipped.
int LuaGetAllOfTypeInRange(lua_State* L)
{
    const Word area = ToObjectAddress(L, 1);
    const std::int32_t point[2] = {static_cast<std::int32_t>(lua.tointegerx(L, 2, nullptr)),
                                   static_cast<std::int32_t>(lua.tointegerx(L, 3, nullptr))};
    const Word aiType = ToObjectAddress(L, 4);
    const auto range = static_cast<std::int16_t>(lua.tointegerx(L, 5, nullptr));
    const int checkLOS = lua.toboolean(L, 6);
    const int checkNonSprites = lua.toboolean(L, 7);
    Word terrain = lua.type(L, 8) == LUA_TNIL ? 0 : ToObjectAddress(L, 8);
    if (!terrain && lua.type(L, 9) != LUA_TNIL)
        terrain = VisibleTerrainTable(ToObjectAddress(L, 9));
    const auto getAll = Engine<void (*)(Word, const std::int32_t*, Word, Word, Word, Word, Word, Word)>(kGetAllInRange);
    const auto listCtor = Engine<void (*)(Word, int)>(kListCtor);
    const auto removeAll = Engine<void (*)(Word)>(kListRemoveAll);
    if (!area || !aiType || !getAll || !listCtor || !removeAll)
        LuaError(L, "IEX_GetAllOfTypeInRange: area and object type expected");
    alignas(8) std::uint8_t list[kListAlloc] = {};
    const Word listAddress = reinterpret_cast<Word>(list);
    listCtor(listAddress, 10);
    getAll(area, point, aiType, static_cast<Word>(static_cast<std::uint16_t>(range)), terrain, listAddress,
           static_cast<Word>(checkLOS && terrain ? 1 : 0), static_cast<Word>(checkNonSprites));
    lua.createtable(L, 0, 0);
    int n = 0;
    for (Word node = Read<Word>(listAddress + kListHead); node; node = Read<Word>(node)) {
        lua.pushinteger(L, static_cast<std::int32_t>(Read<std::int64_t>(node + kNodeData)));
        lua.rawseti(L, -2, ++n);
    }
    removeAll(listAddress);
    return 1;
}

// IEX_PersonalSpace(sprite) -> personal space of the creature's animation (search-map squares).
int LuaPersonalSpace(lua_State* L)
{
    const Word sprite = ToObjectAddress(L, 1);
    static const std::uint32_t animation = FieldOffset("CGameSprite", "m_animation");
    const std::uint32_t slot = engineTypes.Symbol("IEX_VtOff_AnimPersonalSpace");
    if (!sprite || !IsSprite(sprite) || !animation || !slot) {
        lua.pushinteger(L, 0);
        return 1;
    }
    const Word anim = sprite + animation;
    std::uint8_t value;
    if (Read<std::uint8_t>(anim + kAnimFlags) & 4) {
        value = Read<std::uint8_t>(anim + kAnimPersonalSpace);
    } else {
        const Word type = Read<Word>(anim);
        value = type ? reinterpret_cast<std::uint8_t (*)(Word)>(Read<Word>(Read<Word>(type) + slot))(type) : 0;
    }
    lua.pushinteger(L, value);
    return 1;
}

// IEX_TicksPerSecond([n]) -> logic updates per second (CChitin::TIMER_UPDATES_PER_SECOND, "Maximum Frame Rate");
// with n (1..240) sets it first.
int LuaTicksPerSecond(lua_State* L)
{
    auto* tps = Engine<std::uint32_t*>("_ZN7CChitin24TIMER_UPDATES_PER_SECONDE");
    if (!tps)
        LuaError(L, "IEX_TicksPerSecond: not available for this game build");
    if (lua.type(L, 1) == LUA_TNUMBER) {
        const lua_Integer n = lua.tointegerx(L, 1, nullptr);
        if (n >= 1 && n <= 240 && static_cast<std::uint32_t>(n) != *tps) {
            Log("Logic updates per second: %u -> %d", *tps, static_cast<int>(n));
            *tps = static_cast<std::uint32_t>(n);
        }
    }
    lua.pushinteger(L, *tps);
    return 1;
}

// --- Memory and small engine bindings for EEex-style Lua code (EEex_NewUD, EEex_RunWithStackManager...) ---

// IEX_Alloc(size) -> address of zeroed memory owned by Lua code (IEX_Free releases it).
int LuaAlloc(lua_State* L)
{
    const lua_Integer size = lua.tointegerx(L, 1, nullptr);
    if (size <= 0 || size > (1 << 20))
        LuaError(L, "IEX_Alloc: size 1..1048576 expected");
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word>(std::calloc(1, static_cast<std::size_t>(size)))));
    return 1;
}

int LuaFree(lua_State* L)
{
    std::free(reinterpret_cast<void*>(static_cast<Word>(lua.tointegerx(L, 1, nullptr))));
    return 0;
}

// IEX_DecodeEffect(itemEffect, sourcePoint, sourceId, targetPoint, sourceTarget) -> CGameEffect (engine decode,
// unknown opcodes as inert effects).
int LuaDecodeEffect(lua_State* L)
{
    const Word item = ToObjectAddress(L, 1);
    const Word source = ToObjectAddress(L, 2);
    const Word target = ToObjectAddress(L, 4);
    if (!item || !source || !target)
        LuaError(L, "IEX_DecodeEffect: Item_effect_st, CPoint, id, CPoint, id expected");
    const auto sourceId = static_cast<std::int32_t>(lua.tointegerx(L, 3, nullptr));
    const auto arg5 = static_cast<std::int32_t>(lua.tointegerx(L, 5, nullptr));
    const Word effect = DecodeEffectAny(item, source, static_cast<Word>(static_cast<std::uint32_t>(sourceId)), target,
                                        static_cast<Word>(static_cast<std::uint32_t>(arg5)));
    PushObject(L, effect, engineTypes.Get("CGameEffect"));
    return 1;
}

// IEX_ProjectileAddEffect(projectile, effect): the effect travels with the projectile (CProjectile::AddEffect).
int LuaProjectileAddEffect(lua_State* L)
{
    const Word projectile = ToObjectAddress(L, 1);
    const Word effect = ToObjectAddress(L, 2);
    const auto add = Engine<void (*)(Word, Word)>("_ZN11CProjectile9AddEffectEP11CGameEffect");
    if (!projectile || !effect || !add)
        LuaError(L, "IEX_ProjectileAddEffect: projectile and effect expected");
    add(projectile, effect);
    return 0;
}

// IEX_RangeColor(index) -> RGB of a palette range (CVidPalette::RANGE_COLORS, 256 entries).
int LuaRangeColor(lua_State* L)
{
    const lua_Integer i = lua.tointegerx(L, 1, nullptr);
    const auto* colors = Engine<const std::uint32_t*>("_ZN11CVidPalette12RANGE_COLORSE");
    lua.pushinteger(L, colors && i >= 0 && i < 256 ? colors[i] : 0xBED7D7);
    return 1;
}

// IEX_DisplayText(name, text, nameColor, textColor, marker): a line in the dialog / combat log, as
// CMessageDisplayText::Run shows it (CScreenWorld::DisplayText).
int LuaDisplayText(lua_State* L)
{
    const char* name = lua.tolstring(L, 1, nullptr);
    const char* text = lua.tolstring(L, 2, nullptr);
    const auto display = Engine<void (*)(Word, Word*, Word*, Word, Word, Word, Word, Word, Word)>(
        "_ZN12CScreenWorld11DisplayTextERK7CStringS2_jjiiji");
    const auto stringCtor = Engine<void (*)(Word*, const char*)>(kStringCtor);
    const auto stringDtor = Engine<void (*)(Word*)>(kStringDtor);
    const std::uint32_t chitinRva = engineTypes.Symbol("g_pBaldurChitin");
    static const std::uint32_t worldOffset = FieldOffset("CBaldurChitin", "m_pEngineWorld");
    if (!display || !stringCtor || !stringDtor || !chitinRva || !worldOffset)
        LuaError(L, "IEX_DisplayText: not available for this game build");
    const Word chitin = Read<Word>(EngineImageBase() + chitinRva);
    const Word world = chitin ? Read<Word>(chitin + worldOffset) : 0;
    if (!world)
        return 0;
    alignas(8) Word nameStr = 0, textStr = 0;
    stringCtor(&nameStr, name ? name : "");
    stringCtor(&textStr, text ? text : "");
    display(world, &nameStr, &textStr, static_cast<Word>(static_cast<std::uint32_t>(lua.tointegerx(L, 3, nullptr))),
            static_cast<Word>(static_cast<std::uint32_t>(lua.tointegerx(L, 4, nullptr))),
            static_cast<Word>(static_cast<std::uint32_t>(lua.type(L, 5) == LUA_TNUMBER ? lua.tointegerx(L, 5, nullptr) : -1)),
            0, 0, 1);
    stringDtor(&nameStr);
    stringDtor(&textStr);
    return 0;
}

// --- Engine heap and raw pointers (spell menu / template helpers) ---

Word CheckWord(lua_State* L, int index)
{
    if (lua.type(L, index) == LUA_TLIGHTUSERDATA)
        return reinterpret_cast<Word>(lua.touserdata(L, index));
    if (const Word p = ToObjectAddress(L, index))
        return p;
    return static_cast<Word>(lua.tointegerx(L, index, nullptr));
}

// IEX_EngineAlloc(size) -> address of zeroed bytes from the engine's C heap (SDL_malloc = the engine CRT malloc),
// for objects the engine itself frees with free() (UI items).
int LuaEngineAlloc(lua_State* L)
{
    const lua_Integer size = lua.tointegerx(L, 1, nullptr);
    const auto alloc = Engine<void* (*)(std::size_t)>("SDL_malloc");
    if (size <= 0 || size > (1 << 20) || !alloc)
        LuaError(L, "IEX_EngineAlloc: size 1..1048576 expected");
    void* p = alloc(static_cast<std::size_t>(size));
    if (p)
        std::memset(p, 0, static_cast<std::size_t>(size));
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word>(p)));
    return 1;
}

// IEX_EngineFree(address): free() of the engine heap (nil / 0 ignored).
int LuaEngineFree(lua_State* L)
{
    const Word p = CheckWord(L, 1);
    const auto release = Engine<void (*)(void*)>("SDL_free");
    if (p && release)
        release(reinterpret_cast<void*>(p));
    return 0;
}

// IEX_EngineStrdup(text) -> address of a NUL-terminated copy on the engine heap.
int LuaEngineStrdup(lua_State* L)
{
    std::size_t len = 0;
    const char* text = lua.tolstring(L, 1, &len);
    const auto alloc = Engine<void* (*)(std::size_t)>("SDL_malloc");
    if (!text || !alloc)
        LuaError(L, "IEX_EngineStrdup: string expected");
    auto* p = static_cast<char*>(alloc(len + 1));
    std::memcpy(p, text, len + 1);
    lua.pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<Word>(p)));
    return 1;
}

// IEX_MemCopy(dst, src, size): copies bytes between engine objects / addresses.
int LuaMemCopy(lua_State* L)
{
    const Word dst = CheckWord(L, 1), src = CheckWord(L, 2);
    const lua_Integer size = lua.tointegerx(L, 3, nullptr);
    if (!dst || !src || size < 0)
        LuaError(L, "IEX_MemCopy: dst, src, size expected");
    std::memmove(reinterpret_cast<void*>(dst), reinterpret_cast<const void*>(src), static_cast<std::size_t>(size));
    return 0;
}

// EEex_UDToLightUD(object) -> light userdata of the object's address (what the engine's UI tables hold).
int LuaToLightUD(lua_State* L)
{
    const Word p = CheckWord(L, 1);
    if (!p) {
        lua.pushnil(L);
        return 1;
    }
    lua.pushlightuserdata(L, reinterpret_cast<void*>(p));
    return 1;
}

// IEX_EngineGlobalAt(symbol, typeName) -> object stored AT the engine global `symbol` (a struct variable).
int LuaEngineGlobalAt(lua_State* L)
{
    const char* symbol = lua.tolstring(L, 1, nullptr);
    const char* typeName = lua.tolstring(L, 2, nullptr);
    const std::uint32_t rva = symbol ? engineTypes.Symbol(symbol) : 0;
    const TypeDesc* type = typeName ? engineTypes.Get(typeName) : nullptr;
    if (!rva || !type) {
        lua.pushnil(L);
        return 1;
    }
    PushObject(L, EngineImageBase() + rva, type);
    return 1;
}

// IEX_FieldOffset(typeName, field) -> byte offset of the field in the engine description, or nil.
int LuaFieldOffset(lua_State* L)
{
    const char* typeName = lua.tolstring(L, 1, nullptr);
    const char* field = lua.tolstring(L, 2, nullptr);
    const TypeDesc* type = typeName ? engineTypes.Get(typeName) : nullptr;
    std::uint32_t offset = 0;
    if (type && field && type->Find(field, offset))
        lua.pushinteger(L, offset);
    else
        lua.pushnil(L);
    return 1;
}

// IEX_FreeCPtrList(list, elementSize, listSize): deletes every element (engine operator delete, trivially destructible
// records such as CButtonData), empties the list and deletes the list object itself (a list the engine returned
// from new, e.g. CGameSprite::GetQuickButtons).
int LuaFreeCPtrList(lua_State* L)
{
    const Word list = CheckWord(L, 1);
    const auto elementSize = static_cast<std::size_t>(lua.tointegerx(L, 2, nullptr));
    auto listSize = static_cast<std::size_t>(lua.tointegerx(L, 3, nullptr));
    const auto removeAll = Engine<void (*)(Word)>(kListRemoveAll);
    static const std::uint32_t head = FieldOffset("CPtrList", "m_pNodeHead");
    static const std::uint32_t next = FieldOffset("CPtrList::CNode", "pNext");
    static const std::uint32_t data = FieldOffset("CPtrList::CNode", "data");
    static const TypeDesc* listType = engineTypes.Get("CPtrList");
    if (!list)
        return 0;
    if (!removeAll || !engineTypes.Symbol(kDelete) || !listType || !data)
        LuaError(L, "IEX_FreeCPtrList: not available for this game build");
    for (Word n = Read<Word>(list + head); n; n = Read<Word>(n + next)) {
        const Word element = Read<Word>(n + data);
        if (element && elementSize)
            EngineDelete(element, elementSize);
    }
    removeAll(list);
    EngineDelete(list, listSize ? listSize : listType->size);
    return 0;
}

void Register(lua_State* L, const char* name, int (*fn)(lua_State*))
{
    lua.pushcclosure(L, fn, 0);
    lua.setglobal(L, name);
}

} // namespace

void OpenLuaScripting(lua_State* L)
{
    g_L = L;
    Register(L, "IEX_ParseConditional", LuaParseConditional);
    Register(L, "IEX_ConditionHolds", LuaConditionHolds);
    Register(L, "IEX_FreeConditional", LuaFreeConditional);
    Register(L, "IEX_ParseResponse", LuaParseResponse);
    Register(L, "IEX_InsertResponse", LuaInsertResponse);
    Register(L, "IEX_ExecuteResponseInstantly", LuaExecuteResponseInstantly);
    Register(L, "IEX_FreeResponse", LuaFreeResponse);
    Register(L, "IEX_ParseObjectType", LuaParseObjectType);
    Register(L, "IEX_FreeObjectType", LuaFreeObjectType);
    Register(L, "IEX_VisualRange", LuaVisualRange);
    Register(L, "IEX_GetAllOfTypeInRange", LuaGetAllOfTypeInRange);
    Register(L, "IEX_PersonalSpace", LuaPersonalSpace);
    Register(L, "IEX_TicksPerSecond", LuaTicksPerSecond);
    Register(L, "IEX_Alloc", LuaAlloc);
    Register(L, "IEX_Free", LuaFree);
    Register(L, "IEX_DecodeEffect", LuaDecodeEffect);
    Register(L, "IEX_ProjectileAddEffect", LuaProjectileAddEffect);
    Register(L, "IEX_RangeColor", LuaRangeColor);
    Register(L, "IEX_DisplayText", LuaDisplayText);
    Register(L, "IEX_EvalObjectString", LuaEvalObjectString);
    Register(L, "IEX_NearestOpenPosition", LuaNearestOpenPosition);
    Register(L, "IEX_EngineAlloc", LuaEngineAlloc);
    Register(L, "IEX_EngineFree", LuaEngineFree);
    Register(L, "IEX_EngineStrdup", LuaEngineStrdup);
    Register(L, "IEX_MemCopy", LuaMemCopy);
    Register(L, "EEex_UDToLightUD", LuaToLightUD);
    Register(L, "IEX_EngineGlobalAt", LuaEngineGlobalAt);
    Register(L, "IEX_FreeCPtrList", LuaFreeCPtrList);
    Register(L, "IEX_FieldOffset", LuaFieldOffset);
}

void InstallScriptingHooks()
{
    const std::uint32_t rva = engineTypes.Symbol(kDecode);
    if (!rva) {
        Log("Script objects: CAIObjectType::Decode not available, EEex_LuaObject / EEex_Target not resolved");
        return;
    }
    g_decode = EngineImageBase() + rva;
    int n = 0;
    for (std::uint32_t site : engineTypes.CallSitesOf(kDecode))
        n += HookCallSite(EngineImageBase() + site, g_decode, reinterpret_cast<const void*>(&DecodeObjectType)) ? 1 : 0;
    Log("Script objects: %d CAIObjectType::Decode call sites hooked (EEex_LuaObject, EEex_Target)", n);
}

} // namespace iex
