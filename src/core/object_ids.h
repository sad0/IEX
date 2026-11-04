#pragma once

// Object ids that never run out (docs/API_SPEC.md section 19): CGameObjectArray slots and keys are reused, so a
// long session no longer ends with "Too many objects!" and a crash in CGameArea::SortLists. On by default;
// IEX_OBJECT_IDS=0 leaves the engine's own ids.

struct lua_State;

namespace iex {

// Resolves the CGameObjectArray statics (after InstallEventHooks: needs its CGameObjectArray::Add hook).
void InstallObjectIds();

// Called around every CGameObjectArray::Add (event_hooks.cpp's call-site hook).
void ObjectIdsBeforeAdd();
void ObjectIdsAfterAdd();

// IEX_Features.objectIdRecycling, IEX_ObjectIdInfo().
void OpenLuaObjectIds(lua_State* L);

} // namespace iex
