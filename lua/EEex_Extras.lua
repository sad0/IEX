-- EEex public functions found missing by the EEex vs IEX differential test (docs/DIFFTEST_*.md) and used by mods
-- of the inventory (IEX-data/inventory/inventory.json). Behaviour from the public documentation and from what the
-- functions return when run under EEex.

-- --- Bits ---

-- OR of a list of flags: EEex_Flags({ 0x1, 0x8 }) == 0x9.
function EEex_Flags(flags)
	local value = 0
	for _, flag in ipairs(flags) do value = bit32.bor(value, flag) end
	return value
end

-- --- Per-object Lua data ---

-- The object's EEex_GetUDAux table if it has one, nil otherwise. Creatures always have one (EEex gives every
-- loaded sprite its table), so for them it is created when missing.
function EEex_TryGetUDAux(object)
	local aux = IEX_UDAux[IEX_Address(object)]
	if aux == nil and object and object.m_objectType == 0x31 then aux = EEex_GetUDAux(object) end
	return aux
end


-- --- Memory ---

-- Address held by a light userdata (EEex_UDToLightUD, UI tables).
function EEex_LightUDToPtr(lightUD)
	return IEX_Address(lightUD)
end

-- C strings that stay allocated for the whole session (addresses handed to engine code). WriteStringCache gives
-- the same address for the same text.
local stringCache = {}
function EEex_WriteStringAuto(text)
	text = tostring(text)
	local address = EEex_Malloc(#text + 1)
	EEex_WriteString(address, text)
	return address
end
function EEex_WriteStringCache(text)
	text = tostring(text)
	local address = stringCache[text]
	if not address then
		address = EEex_WriteStringAuto(text)
		stringCache[text] = address
	end
	return address
end

-- Lua registry slots (the references .menu items hold to their Lua functions).
function EEex_GetLuaRegistryIndex(index)
	return rawget(IEX_LuaRegistry(), index)
end
function EEex_SetLuaRegistryIndex(index, value)
	rawset(IEX_LuaRegistry(), index, value)
end

-- --- Menus ---

-- EEex_Menu_GetItemVariant: EEex_MenuUI.lua (numbers, strings, floats, Lua expressions).

-- --- Game state ---

-- Pauses / unpauses the game like the pause key (CScreenWorld::TogglePauseGame). Defaults as documented:
-- bLogPause true, bVisualPause true, bRequireHostUnpause false, nIdPlayerPause 0, bSendMessage true.
function EEex_GameState_TogglePause(bLogPause, bVisualPause, bRequireHostUnpause, nIdPlayerPause, bSendMessage)
	local world = EEex_EngineGlobal_CBaldurChitin.m_pEngineWorld
	if not world then return end
	local function flag(v, default) if v == nil then v = default end return v and 1 or 0 end
	world:TogglePauseGame(flag(bVisualPause, true), flag(bSendMessage, true), nIdPlayerPause or 0,
		flag(bLogPause, true), flag(bRequireHostUnpause, false))
end

-- --- Searches around a creature ---

-- func(object) for every object of the type in range (same search and defaults as EEex_Sprite_GetAllOfTypeInRange).
function EEex_Sprite_ForAllOfTypeInRange(sprite, aiObjectType, range, func, bCheckForLineOfSight, bCheckForNonSprites,
                                         terrainTable)
	for _, object in ipairs(EEex_Sprite_GetAllOfTypeInRange(sprite, aiObjectType, range, bCheckForLineOfSight,
			bCheckForNonSprites, terrainTable)) do
		func(object)
	end
end

function EEex_Sprite_ForAllOfTypeStringInRange(sprite, aiObjectTypeString, range, func, bCheckForLineOfSight,
                                               bCheckForNonSprites, terrainTable)
	for _, object in ipairs(EEex_Sprite_GetAllOfTypeStringInRange(sprite, aiObjectTypeString, range,
			bCheckForLineOfSight, bCheckForNonSprites, terrainTable)) do
		func(object)
	end
end

function EEex_Sprite_CountAllOfTypeInRange(sprite, aiObjectType, range, bCheckForLineOfSight, bCheckForNonSprites,
                                           terrainTable)
	return #EEex_Sprite_GetAllOfTypeInRange(sprite, aiObjectType, range, bCheckForLineOfSight, bCheckForNonSprites,
		terrainTable)
end

function EEex_Sprite_CountAllOfTypeStringInRange(sprite, aiObjectTypeString, range, bCheckForLineOfSight,
                                                 bCheckForNonSprites, terrainTable)
	return #EEex_Sprite_GetAllOfTypeStringInRange(sprite, aiObjectTypeString, range, bCheckForLineOfSight,
		bCheckForNonSprites, terrainTable)
end

CGameSprite.forAllOfTypeInRange = EEex_Sprite_ForAllOfTypeInRange
CGameSprite.forAllOfTypeStringInRange = EEex_Sprite_ForAllOfTypeStringInRange
CGameSprite.countAllOfTypeInRange = EEex_Sprite_CountAllOfTypeInRange
CGameSprite.countAllOfTypeStringInRange = EEex_Sprite_CountAllOfTypeStringInRange

-- --- Objects ---

-- Puts an object that is in no area into `area` at (x, y): the engine's AddToArea of the object's class (a creature
-- also joins the area's markers, search map...). z and listType default to the object's own values.
function EEex_Object_AddToArea(object, area, x, y, z, listType)
	object:virtual_AddToArea(area, { x = x, y = y }, z or object.m_posZ or 0, listType or object.m_listType or 0)
end

-- --- Arithmetic helpers ---

-- Bytes to add to `value` to reach the next multiple of `multiple` (0 when already aligned).
function EEex_DistanceToMultiple(value, multiple)
	return (multiple - value % multiple) % multiple
end

-- `value` rounded up to a multiple of `multiple`.
function EEex_RoundUp(value, multiple)
	return value + EEex_DistanceToMultiple(value, multiple)
end

-- --- Game state ---

-- True once the game state has been initialized this session (mods test it before registering late).
EEex_GameState_Private_AlreadyInitialized = EEex_GameState_Private_AlreadyInitialized or false
IEX_AddListener('GameStateInitialized', function() EEex_GameState_Private_AlreadyInitialized = true end)
