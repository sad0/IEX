-- EEex-compatible game state, party and sprite functions.

local function game()
	return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
end

-- Game object by id (nil if the id is invalid or the object was deleted), typed to its real class.
function EEex_GameObject_Get(id)
	if not id or id == -1 then return nil end
	return EEex_GameObject_CastUserType(IEX_GetObject(id))
end

-- --- Party / portraits ---

-- Party size of the portrait bar (6 in vanilla).
IEX_PortraitCount = IEX_PortraitCount or 6

-- Id of the creature in portrait slot (0-based), -1 if the slot is empty.
function EEex_Sprite_GetInPortraitID(slot)
	local g = game()
	if not g or slot < 0 or slot >= IEX_PortraitCount then return -1 end
	return g.m_characterPortraits:get(slot)
end

function EEex_Sprite_GetInPortrait(slot)
	return EEex_GameObject_Get(EEex_Sprite_GetInPortraitID(slot))
end

-- Number of creatures in the party (0 when no game is loaded).
function EEex_Sprite_GetNumCharacters()
	local g = game()
	return g and g.m_nCharacters or 0
end

-- Portrait slot of a creature, -1 if it is not in the party.
function EEex_Sprite_GetPortraitIndex(sprite)
	local g = game()
	if not g or not sprite then return -1 end
	local id = sprite.m_id
	for slot = 0, IEX_PortraitCount - 1 do
		if g.m_characterPortraits:get(slot) == id then return slot end
	end
	return -1
end

-- Index of a creature in the fixed (join) order of the party, -1 if not in the party.
function EEex_Sprite_GetCharacterIndex(sprite)
	local g = game()
	if not g or not sprite then return -1 end
	local id = sprite.m_id
	for slot = 0, IEX_PortraitCount - 1 do
		if g.m_characters:get(slot) == id then return slot end
	end
	return -1
end

-- --- Selection (the engine keeps the selected ids sorted by portrait, so the first one is the leader) ---

function EEex_Sprite_GetAllSelectedIDs()
	local ids = {}
	local g = game()
	if not g then return ids end
	IEX_IterateList(g.m_group.m_memberList, function(id) ids[#ids + 1] = id end)
	return ids
end

function EEex_Sprite_GetAllSelected()
	local out = {}
	for _, id in ipairs(EEex_Sprite_GetAllSelectedIDs()) do
		local sprite = EEex_GameObject_Get(id)
		if sprite then out[#out + 1] = sprite end
	end
	return out
end

function EEex_Sprite_GetSelectedID()
	return EEex_Sprite_GetAllSelectedIDs()[1] or -1
end

function EEex_Sprite_GetSelected()
	return EEex_GameObject_Get(EEex_Sprite_GetSelectedID())
end

-- --- Sprite data ---

-- Current value of a STATS.IDS stat (effects included).
function EEex_Sprite_GetStat(sprite, stat)
	return IEX_GetStat(sprite.m_derivedStats, stat)
end

function EEex_Sprite_GetName(sprite)
	local _ = sprite.m_id  -- nil: "attempt to index local 'sprite'", as under EEex
	return IEX_SpriteName(sprite)
end

-- STATE.IDS flags currently in effect.
function EEex_Sprite_GetState(sprite)
	return sprite.m_derivedStats.m_generalState
end

-- Known spells: iterator over (level, index, resref), like EEex: the level is 0-based (0 = spell level 1), the
-- index 1-based within the level. startLevel / endLevel are spell levels (1-based, whole book by default).
local function knownSpellsIterator(levels, count, startLevel, endLevel)
	local entries = {}
	for level = startLevel or 1, endLevel or count do
		local index = 0
		if level >= 1 and level <= count then
			IEX_IterateList(levels:getReference(level - 1), function(spell)
				index = index + 1
				entries[#entries + 1] = { level - 1, index, spell.m_knownSpellId:get() }
			end)
		end
	end
	local i = 0
	return function()
		i = i + 1
		local e = entries[i]
		if e then return e[1], e[2], e[3] end
	end
end

function EEex_Sprite_GetKnownMageSpellsIterator(sprite, startLevel, endLevel)
	return knownSpellsIterator(sprite.m_knownSpellsMage, 9, startLevel, endLevel)
end

function EEex_Sprite_GetKnownPriestSpellsIterator(sprite, startLevel, endLevel)
	return knownSpellsIterator(sprite.m_knownSpellsPriest, 7, startLevel, endLevel)
end

-- --- Script variables ---

local function getInt(hash, name)
	local value = IEX_VariableGet(hash, name)
	return value
end

local function getString(hash, name)
	local _, text = IEX_VariableGet(hash, name)
	return text
end

function EEex_GameState_GetGlobalInt(name) return getInt(game().m_variables, name) end
function EEex_GameState_SetGlobalInt(name, value) IEX_VariableSet(game().m_variables, name, value, nil) end
function EEex_GameState_GetGlobalString(name) return getString(game().m_variables, name) end
function EEex_GameState_SetGlobalString(name, value) IEX_VariableSet(game().m_variables, name, nil, value) end

function EEex_Area_GetVariableInt(area, name) return getInt(area.m_variables, name) end
function EEex_Area_SetVariableInt(area, name, value) IEX_VariableSet(area.m_variables, name, value, nil) end
function EEex_Area_GetVariableString(area, name) return getString(area.m_variables, name) end
function EEex_Area_SetVariableString(area, name, value) IEX_VariableSet(area.m_variables, name, nil, value) end

-- LOCALS of a creature: 0 / "" when it has no local variable table yet (early in its constructor the field holds
-- a non-pointer value).
local function locals(sprite)
	local hash = sprite.m_pLocalVariables
	local a = hash and IEX_Address(hash)
	if not a or a < 0x10000 or a >= 0x800000000000 then return nil end
	return hash
end

function EEex_Sprite_GetLocalInt(sprite, name)
	local hash = locals(sprite)
	return hash and getInt(hash, name) or 0
end

function EEex_Sprite_SetLocalInt(sprite, name, value)
	local hash = locals(sprite)
	if hash then IEX_VariableSet(hash, name, value, nil) end
end

function EEex_Sprite_GetLocalString(sprite, name)
	local hash = locals(sprite)
	return hash and getString(hash, name) or ''
end

function EEex_Sprite_SetLocalString(sprite, name, value)
	local hash = locals(sprite)
	if hash then IEX_VariableSet(hash, name, nil, value) end
end

-- --- Methods on engine objects (mods may replace or add their own) ---

function CGameSprite.getName(sprite) return IEX_SpriteName(sprite) end
-- Methods delegate to the global functions (never the reverse), so a mod wrapping both stays loop-free.
function CGameSprite.getState(sprite) return EEex_Sprite_GetState(sprite) end
function CGameSprite.getPortraitIndex(sprite) return EEex_Sprite_GetPortraitIndex(sprite) end
function CGameSprite.getCharacterIndex(sprite) return EEex_Sprite_GetCharacterIndex(sprite) end
function CGameSprite.getLocalInt(sprite, name) return EEex_Sprite_GetLocalInt(sprite, name) end
function CGameSprite.setLocalInt(sprite, name, value) return EEex_Sprite_SetLocalInt(sprite, name, value) end
function CGameSprite.getLocalString(sprite, name) return EEex_Sprite_GetLocalString(sprite, name) end
function CGameSprite.setLocalString(sprite, name, value) return EEex_Sprite_SetLocalString(sprite, name, value) end

-- Stats currently in effect (effects included): the engine reads m_derivedStats when m_useDerivedStats is set,
-- else m_tempStats (CInfButtonArray::CheckActivation, CGameSprite::GetQuickButtons).
function EEex_Sprite_GetActiveStats(sprite)
	local flag = sprite.m_useDerivedStats
	if flag == nil or flag ~= 0 then return sprite.m_derivedStats end
	return sprite.m_tempStats
end
function CGameSprite.getActiveStats(sprite) return EEex_Sprite_GetActiveStats(sprite) end
function CGameSprite.getStat(sprite, stat) return EEex_Sprite_GetStat(sprite, stat) end

-- EEex_Sprite_DisplayTextRef(sprite, strref [, options]): the string as a line of the sprite in the dialog / combat
-- log, without queuing an action (SadoEE lasting modes: a DisplayStringHead action would end the thief's stealth).
-- IEX shows it in the log only (options.overHead is not drawn over the head yet).
function EEex_Sprite_DisplayTextRef(sprite, strref, options)
	if not sprite or type(strref) ~= 'number' or strref < 0 then return end
	local text = Infinity_FetchString(strref)
	if not text or text == '' then return end
	IEX_DisplayText(EEex_Sprite_GetName(sprite), text, 0xBED7D7, 0xBED7D7, -1)
end

-- CONCENTR.2DA CHECK_MODE "EEex-LuaFunction=<name>" (Tactics Remix #60, Tweaks Anthology #2690): the Lua function
-- fn(sprite, damageData) -> true when the damage disrupts the spell being cast. The engine reads the line as mode 0
-- (every hit disrupts); IEX's ConcentrationFailed hook (src/core/lua_sprite_hooks.cpp) calls the function instead.
function IEX_ReadConcentrationCheck()
	if not IEX_SetConcentrationCheck then return end
	local name
	pcall(function()
		local t = EEex_Resource_Load2DA('CONCENTR')
		local y = t and t:findRowLabel('CHECK_MODE') or -1
		local v = y >= 0 and t:getAtPoint(0, y) or ''
		name = string.match(tostring(v), '^EEex%-LuaFunction=([%w_%.]+)')
	end)
	local hooked = IEX_SetConcentrationCheck(name)
	if name and IEX_Log then IEX_Log('Concentration check: Lua function ' .. name .. (hooked and '' or ' (engine hook NOT installed)')) end
end
pcall(IEX_ReadConcentrationCheck)
if EEex_GameState_AddInitializedListener then EEex_GameState_AddInitializedListener(function() pcall(IEX_ReadConcentrationCheck) end) end

-- --- Per-creature UUIDs (docs/UUID.md) ---
--
-- Every creature gets a number that stays the same for its whole life, across saves and area changes. As under
-- EEex (observed, not copied): the number lives in the creature's local variable EEEX_UUID (low 32 bits in
-- m_intValue, high 32 bits in m_dWValue), so the engine saves it with the creature like any LOCALS variable; the last
-- number handed out is the global EEEX_NEXTUUID (saved in the GAM). Numbers are given in sequence (last + 1) when a
-- creature without one is created (spawn, new area, old save), and a creature copy (CGameSprite::Copy: simulacrum,
-- project image...) always gets a new one. Saves move between EEex and IEX with their numbers.
-- IEX extra: a creature loaded with a number another live creature already has (an imported character, a broken
-- save) gets a new one, so the number stays unique.

local UUID_VAR, NEXT_VAR = 'EEEX_UUID', 'EEEX_NEXTUUID'
local TWO32 = 4294967296
IEX_UUID_Ids = {}         -- uuid -> object id of the live creature
IEX_UUID_MaxSeen = 0      -- highest number seen this session (guards against a stale EEEX_NEXTUUID)

local localsOf = locals

local function readVar(hash, name)
	local v = hash and IEX_VariableFind(hash, name)
	if not v then return nil end
	return v.m_intValue % TWO32 + v.m_dWValue * TWO32
end

local function writeVar(hash, name, value)
	local low, high = value % TWO32, math.floor(value / TWO32)
	IEX_VariableSet(hash, name, low >= 2147483648 and low - TWO32 or low, nil)
	local v = IEX_VariableFind(hash, name)
	if v then v.m_dWValue = high end
end

-- Hands out the next number and stores it as the creature's EEEX_UUID.
local function assignUUID(sprite, hash)
	local g = game()
	local last = math.max(g and readVar(g.m_variables, NEXT_VAR) or 0, IEX_UUID_MaxSeen)
	local uuid = last + 1
	if g then writeVar(g.m_variables, NEXT_VAR, uuid) end
	writeVar(hash, UUID_VAR, uuid)
	IEX_UUID_MaxSeen = uuid
	return uuid
end

local function liveSprite(uuid)
	local id = IEX_UUID_Ids[uuid]
	if not id then return nil end
	local sprite = EEex_GameObject_Get(id)
	if sprite and sprite.m_objectType == 0x31 and readVar(localsOf(sprite), UUID_VAR) == uuid then
		return sprite
	end
	IEX_UUID_Ids[uuid] = nil
	return nil
end

-- The number saved with a creature, from its EEEX_UUID op187 record (src/core/marshal.cpp takes the record out of the
-- effect list before the engine applies it), by creature address until IEX_UUID_OnLoaded.
IEX_UUID_Saved = {}
function IEX_UUID_FromEffects(sprite, low, high)
	IEX_UUID_Saved[IEX_Address(sprite)] = low % TWO32 + high * TWO32
end

-- Called for every creature once it is created (lua/EEex_Listeners.lua, SpriteLoaded), before
-- EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled and the loaded listeners.
function IEX_UUID_OnLoaded(sprite)
	local address = IEX_Address(sprite)
	local saved = IEX_UUID_Saved[address]
	IEX_UUID_Saved[address] = nil
	local hash = localsOf(sprite)
	if not hash then return end
	local uuid = readVar(hash, UUID_VAR) or saved
	local other = uuid and liveSprite(uuid)
	if not uuid or IEX_IsMarshallingCopy() or (other and other.m_id ~= sprite.m_id) then
		uuid = assignUUID(sprite, hash)
	else
		if readVar(hash, UUID_VAR) ~= uuid then writeVar(hash, UUID_VAR, uuid) end
		if uuid > IEX_UUID_MaxSeen then IEX_UUID_MaxSeen = uuid end
	end
	IEX_UUID_Ids[uuid] = sprite.m_id
end

-- EEex_Sprite_GetUUID(sprite) -> number (errors on nil, as under EEex)
function EEex_Sprite_GetUUID(sprite)
	local hash = localsOf(sprite)
	if not hash then return nil end
	local uuid = readVar(hash, UUID_VAR)
	if not uuid then
		-- asked before IEX_UUID_OnLoaded (a marshal importer) or for a creature IEX never saw: settle it now
		IEX_UUID_OnLoaded(sprite)
		uuid = readVar(hash, UUID_VAR)
	end
	return uuid
end

-- EEex_Sprite_GetFromUUID(uuid) -> the live creature with that number, or nil. The argument must be a number
-- (fractions are cut, as under EEex); any loaded creature is found, in the visible area or not.
function EEex_Sprite_GetFromUUID(uuid)
	if type(uuid) ~= 'number' and type(uuid) ~= 'boolean' then
		error("EEex_Sprite_GetFromUUID: number expected for argument #1 'uuid', got " .. type(uuid), 2)
	end
	if type(uuid) == 'boolean' then uuid = uuid and 1 or 0 end
	uuid = uuid >= 0 and math.floor(uuid) or math.ceil(uuid)
	return liveSprite(uuid)
end

-- EEex_Sprite_LoadedWithUUIDCallback(sourceSprite, uuid, func): func(sourceSprite, target) runs now if the creature
-- `uuid` is loaded, and again each time it is loaded later in this session (after its effects are in place, before
-- the loaded listeners). Registrations are not saved. They end when the source creature is destroyed (area unloaded,
-- DestroySelf, another save loaded). Registering the same function twice calls it twice.
--   EEex_Sprite_Private_LoadedWithUUIDCallbacks[targetUUID][sourceUUID] = { func... }
--   EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource[sourceUUID][<the [targetUUID] table>] = true
EEex_Sprite_Private_LoadedWithUUIDCallbacks = EEex_Sprite_Private_LoadedWithUUIDCallbacks or {}
EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource = EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource or {}

function EEex_Sprite_LoadedWithUUIDCallback(sourceSprite, uuid, func)
	local source = EEex_Sprite_GetUUID(sourceSprite)
	local callbacks = EEex_Sprite_Private_LoadedWithUUIDCallbacks
	local bySource = EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource
	local forTarget = callbacks[uuid]
	if not forTarget then forTarget = {} callbacks[uuid] = forTarget end
	local list = forTarget[source]
	if not list then list = {} forTarget[source] = list end
	list[#list + 1] = func
	local sourceSet = bySource[source]
	if not sourceSet then sourceSet = {} bySource[source] = sourceSet end
	sourceSet[forTarget] = true
	local target = EEex_Sprite_GetFromUUID(uuid)
	if target then func(sourceSprite, target) end
end

-- Target loaded: run its callbacks (errors are logged, the load goes on).
function IEX_UUID_RunCallbacks(sprite)
	local uuid = readVar(localsOf(sprite), UUID_VAR)
	local forTarget = uuid and EEex_Sprite_Private_LoadedWithUUIDCallbacks[uuid]
	if not forTarget then return end
	local calls = {}
	for source, list in pairs(forTarget) do
		for _, fn in ipairs(list) do calls[#calls + 1] = { source, fn } end
	end
	for _, c in ipairs(calls) do
		local sourceSprite = liveSprite(c[1])
		if sourceSprite then
			local ok, err = pcall(c[2], sourceSprite, sprite)
			if not ok then IEX_Log('EEex_Sprite_LoadedWithUUIDCallback callback error: ' .. tostring(err)) end
		end
	end
end

-- Source destroyed: its registrations go; a target left without any is removed.
IEX_AddListener('IEX_SpriteDestroyed', function(sprite)
	local uuid = readVar(localsOf(sprite), UUID_VAR)
	if not uuid then return end
	if IEX_UUID_Ids[uuid] == sprite.m_id then IEX_UUID_Ids[uuid] = nil end
	local bySource = EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource
	local sourceSet = bySource[uuid]
	if not sourceSet then return end
	bySource[uuid] = nil
	local callbacks = EEex_Sprite_Private_LoadedWithUUIDCallbacks
	for forTarget in pairs(sourceSet) do
		forTarget[uuid] = nil
		if next(forTarget) == nil then
			for target, t in pairs(callbacks) do
				if t == forTarget then callbacks[target] = nil break end
			end
		end
	end
end)

IEX_AddListener('GameStateDestroyed', function()
	IEX_UUID_Ids = {}
	IEX_UUID_Saved = {}
	IEX_UUID_MaxSeen = 0
end)

-- EEex's CVariableHash:find(name) -> CVariable or nil (mods read sprite.m_pLocalVariables:find("EEEX_UUID")).
if CVariableHash then
	CVariableHash.find = function(hash, name) return IEX_VariableFind(hash, name) end
end
