-- The actor-ID API of early EEex versions (EEex_GetActor*(actorID), EEex_GetActorIDSelected...). Current mods
-- still emit it: Olvyn's ClassSpellTool (copied into Morpheus562's Kitpack, Skills and Abilities, Tactics Remix,
-- IE Skillz, SoD to BG2EE Item Upgrade...) writes EEex_GetActorClass / Kit / Alignment calls into UI.MENU when
-- EEex is installed, and B_Kits / Proficiencies use EEex_GetActorStat. Each function takes an object id and
-- returns the engine value, or a neutral value (0, '', -1) when the id is not a creature.

local function sprite(actorID)
	if type(actorID) ~= 'number' or actorID == -1 then return nil end
	local object = EEex_GameObject_Get(actorID)
	if object and EEex_GameObject_IsSprite(object, true) then return object end
	return nil
end

-- Engine strings (resref, chars:N fields) come as objects with :get().
local function text(value)
	if type(value) == 'userdata' or type(value) == 'table' then return value:get() end
	return value or ''
end

local function typeAI(actorID, field)
	local s = sprite(actorID)
	return s and s.m_typeAI[field] or 0
end

-- OBJECT.IDS fields of the creature (CLASS.IDS, RACE.IDS, ALIGNMEN.IDS... values).
function EEex_GetActorAllegiance(actorID) return typeAI(actorID, 'm_EnemyAlly') end
function EEex_GetActorGeneral(actorID) return typeAI(actorID, 'm_General') end
function EEex_GetActorRace(actorID) return typeAI(actorID, 'm_Race') end
function EEex_GetActorClass(actorID) return typeAI(actorID, 'm_Class') end
function EEex_GetActorSpecifics(actorID) return typeAI(actorID, 'm_Specifics') end
function EEex_GetActorGender(actorID) return typeAI(actorID, 'm_Gender') end
function EEex_GetActorAlignment(actorID) return typeAI(actorID, 'm_Alignment') end

-- KIT.IDS value of the creature's kit (0x4000 + n for added kits, 0x40.. for mage specialists, 0 none).
function EEex_GetActorKit(actorID)
	local s = sprite(actorID)
	return s and s:getActiveStats().m_nKit or 0
end

-- Any stat (STATS.IDS, extended stats included) of the creature's active stats.
function EEex_GetActorStat(actorID, stat)
	local s = sprite(actorID)
	return s and EEex_Sprite_GetStat(s, stat) or 0
end

function EEex_GetActorState(actorID)
	local s = sprite(actorID)
	return s and EEex_Sprite_GetState(s) or 0
end

function EEex_GetActorName(actorID)
	local s = sprite(actorID)
	return s and EEex_Sprite_GetName(s) or ''
end

function EEex_GetActorScriptName(actorID)
	local s = sprite(actorID)
	return s and text(s.m_scriptName) or ''
end

-- Position in the area (pixels).
function EEex_GetActorLocation(actorID)
	local s = sprite(actorID)
	if not s then return -1, -1 end
	return s.m_pos.x, s.m_pos.y
end

-- Resref of the area the creature is in.
function EEex_GetActorAreaRes(actorID)
	local s = sprite(actorID)
	local area = s and s.m_pArea
	return area and text(area.m_resref) or ''
end

function EEex_GetActorDirection(actorID)
	local s = sprite(actorID)
	return s and s.m_nDirection or -1
end

function EEex_GetActorModalState(actorID)
	local s = sprite(actorID)
	return s and s.m_nModalState or 0
end

-- ACTION.IDS number of the action the creature is running (0 = none).
function EEex_GetActorCurrentAction(actorID)
	local s = sprite(actorID)
	return s and s.m_curAction.m_actionID or 0
end

-- LOCALS variable of the creature.
function EEex_GetActorLocal(actorID, name)
	local s = sprite(actorID)
	return s and EEex_Sprite_GetLocalInt(s, name) or 0
end

function EEex_SetActorLocal(actorID, name, value)
	local s = sprite(actorID)
	if s then EEex_Sprite_SetLocalInt(s, name, value) end
end

function EEex_IsSprite(actorID, allowDead)
	return sprite(actorID) ~= nil and (allowDead or EEex_GameObject_IsSprite(EEex_GameObject_Get(actorID), false))
end

-- Ids of party members: portrait slot (0-5) and character slot.
function EEex_GetActorIDPortrait(slot) return EEex_Sprite_GetInPortraitID(slot) or -1 end
function EEex_GetActorIDCharacter(slot)
	local game = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
	local id = game and game.m_characters and game.m_characters:get(slot)
	return id or -1
end

-- Id of the selected (leader) creature, -1 when nothing is selected.
function EEex_GetActorIDSelected()
	local id = EEex_Sprite_GetSelectedID()
	return id or -1
end

function EEex_GetAllActorIDSelected() return EEex_Sprite_GetAllSelectedIDs() end

-- Game time in ticks (15 per second at normal speed).
function EEex_GetGameTick()
	local game = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
	return game and game.m_worldTime.m_gameTime or 0
end

-- "0x" .. uppercase hex digits of number, left-padded with zeros to minLength digits; no prefix when
-- suppressPrefix is true.
function EEex_ToHex(number, minLength, suppressPrefix)
	local digits = string.format('%X', math.floor(tonumber(number) or 0) % 0x100000000)
	if minLength and #digits < minLength then digits = string.rep('0', minLength - #digits) .. digits end
	return suppressPrefix and digits or ('0x' .. digits)
end

-- Names of the EEex modules enabled in EEex_Modules.lua (B3Scale, B3Hotkey...). IEX implements features
-- directly, not as EEex modules: none are listed, so mods take their no-module path.
EEex_Modules = EEex_Modules or {}

-- --- Early action bar API (B_Kits, Proficiencies) ---

EEex_ACTIONBAR_TYPE = EEex_ACTIONBAR_TYPE or EEex_Actionbar_ButtonType
function EEex_SetActionbarButton(index, buttonType) EEex_Actionbar_SetButton(index, buttonType) end
-- fn(config, state) on every action bar state change (early EEex passed only config).
function EEex_AddActionbarListener(fn) EEex_Actionbar_AddListener(fn) end

-- Early EEex rebuilt its Lua state on some UI resets and called these listeners so mods could load their files
-- again. IEX keeps one Lua state for the whole session (listeners and globals survive UI reloads), so there is
-- nothing to redo: the listeners are kept but never called.
IEX_ResetListeners = IEX_ResetListeners or {}
function EEex_AddResetListener(fn) IEX_ResetListeners[#IEX_ResetListeners + 1] = fn end
