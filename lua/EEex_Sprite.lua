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

-- LOCALS of a creature: 0 / "" when it has no local variable table yet.
local function locals(sprite)
	return sprite.m_pLocalVariables
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
