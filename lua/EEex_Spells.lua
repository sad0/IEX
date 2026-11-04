-- EEex-compatible spell list API: the quick button records of a creature (CButtonData lists), casting from them,
-- the quick slot being configured, the spell list listeners, the disabled buttons / spell types of the active stats.
-- Engine side: method records (engine/methods.txt: GetQuickButtons, GetInternalButtonList, ReadySpell,
-- ReadyOffInternalList, SetQuickSlot, CInfGame:SetState), call-site hooks in src/core/event_hooks.cpp
-- (RemoveSpellFromQuickList, SetAllSpellsMemorized), helpers in src/core/lua_scripting.cpp.

-- --- Records ---

-- Default values of a CButtonData as the engine builds an empty one (no icon, no name strref, no ability, the
-- count shown): used for scratch records (EEex_RunWithStackManager { struct = "CButtonData" }, EEex_NewUD).
IEX_DefaultInit = IEX_DefaultInit or {}
IEX_DefaultInit.CButtonData = function(data)
	data.m_name = -1
	data.m_launcherName = -1
	data.m_count = 0
	local id = data.m_abilityId
	id.m_itemType = -1
	id.m_itemNum = -1
	id.m_abilityNum = -1
	id.m_toolTip = -1
	data.m_bDisabled = 0
	data.m_bDisplayCount = 1
end

-- Frees a list the engine returned with new (GetQuickButtons / GetInternalButtonList): its records, then the list.
function EEex_Utility_FreeCPtrList(list)
	if not list then return end
	local size = 0
	local typeName = IEX_TypeName(list)
	if typeName == 'CGameButtonList' then size = CButtonData.sizeof end
	local class = typeName and rawget(_G, typeName)
	IEX_FreeCPtrList(list, size, type(class) == 'table' and rawget(class, 'sizeof') or 0)
end

-- Static functions of CInfButtonArray under their EEex table name.
EEex_CInfButtonArray = EEex_CInfButtonArray or {}
-- SetQuickSlot(buttonData, slot, kind): kind 1 = quick weapon, 2 = quick spell, 3 = quick item (engine numbering).
function EEex_CInfButtonArray.SetQuickSlot(data, slot, kind)
	return CInfButtonArray.SetQuickSlot(data, slot, kind)
end

-- Action bar button kinds under the engine class name (CButtonType.NONE...), same numbers as
-- EEex_Actionbar_ButtonType.
CButtonType = CButtonType or {}
for name, value in pairs(EEex_Actionbar_ButtonType or {}) do
	if CButtonType[name] == nil then CButtonType[name] = value end
end

-- --- Disabled buttons (opcode 144) and spell types (opcode 145) ---

-- Index into CDerivedStats.m_disabledButtons per action bar button (CInfButtonArray::CheckActivation mapping).
EEex_DerivedStats_DisabledButtonType = {
	BUTTON_STEALTH = 0,
	BUTTON_THIEVING = 1,
	BUTTON_CASTSPELL = 2,
	BUTTON_QUICKSPELL0 = 3,
	BUTTON_QUICKSPELL1 = 4,
	BUTTON_QUICKSPELL2 = 5,
	BUTTON_TURNUNDEAD = 6,
	BUTTON_DIALOG = 7,
	BUTTON_USEITEM = 8,
	BUTTON_QUICKITEM0 = 9,
	BUTTON_BATTLESONG = 10,
	BUTTON_QUICKITEM1 = 11,
	BUTTON_QUICKITEM2 = 12,
	BUTTON_INNATES = 13,
	BUTTON_FINDTRAPS = 14,
}

-- --- Game objects and creatures ---

if CGameObject then
	function CGameObject.isSprite(object, allowDead) return EEex_GameObject_IsSprite(object, allowDead) end
end
function CGameSprite.isSprite(sprite, allowDead) return EEex_GameObject_IsSprite(sprite, allowDead) end

-- CLASS.IDS value of the creature (its AI object type, what the engine's GetClass reads).
function EEex_Sprite_GetClass(sprite) return sprite.m_typeAI.m_Class end
function CGameSprite.getClass(sprite) return EEex_Sprite_GetClass(sprite) end

-- Cursor icon of the game (index into the cursor BAM, as the thieving button sets it): the engine does it inline.
local function setIconIndex(game, index)
	game.m_iconIndex = index
	game.m_iconResRef:set('')
	game.m_iconStrref = -1
end

-- The engine's tolua registration replaces the class tables of its own classes (CInfGame...) after IEX starts:
-- the Lua methods are added again once the game state is initialized.
local function addClassMethods()
	-- rawset: a tolua class table's own __newindex would recurse
	if type(CInfGame) == 'table' then rawset(CInfGame, 'SetIconIndex', setIconIndex) end
end
addClassMethods()
IEX_AddListener('GameStateInitialized', addClassMethods)

-- --- Casting ---

-- The selected creature readies `resref` from a scratch spell button (the cursor then picks the target).
-- IEX approximation: the spell goes through CGameSprite::ReadySpell like a spell list button with an unlimited
-- count; whether the engine removes a memorized copy is the engine's own rule for that button.
function EEex_PlayerCastResrefNoDec(resref)
	local sprite = EEex_GameObject_GetSelected()
	if not sprite or not EEex_GameObject_IsSprite(sprite) then return end
	local header = EEex_Resource_Demand(resref, 'SPL')
	if not header then return end
	EEex_RunWithStackManager({ { name = 'data', struct = 'CButtonData' } }, function(manager)
		local data = manager:getUD('data')
		local level = EEex_Sprite_GetCasterLevelForSpell and EEex_Sprite_GetCasterLevelForSpell(sprite, resref) or 1
		local ability = EEex_Resource_GetSpellAbilityForLevel(header, level) or EEex_Resource_GetSpellAbility(header, 0)
		local icon = ability and ability.quickSlotIcon
		if type(icon) == 'userdata' then icon = icon:get() end
		if icon then data.m_icon:set(icon) end
		data.m_name = header.genericName
		data.m_count = 1
		local id = data.m_abilityId
		id.m_itemType = 1
		id.m_res:set(resref)
		if ability then
			id.m_targetType = ability.actionType or 0
			id.m_targetCount = ability.actionCount or 0
		end
		id.m_toolTip = header.genericName
		sprite:ReadySpell(data, 0)
	end)
end

-- --- Listeners ---

-- fn(sprite): the castable counts of the creature's spells were reset (all memorized spells restored, e.g. rest).
function EEex_Sprite_AddQuickListCountsResetListener(fn) IEX_AddListener('QuickListCountsReset', fn) end

-- fn(sprite, resref): a spell was removed from the creature's spell / quick lists.
function EEex_Sprite_AddQuickListNotifyRemovedListener(fn) IEX_AddListener('QuickListNotifyRemoved', fn) end
function IEX_QuickListNotifyRemoved(sprite, resref)
	local list = IEX_Listeners.QuickListNotifyRemoved
	if list and #list > 0 then IEX_Dispatch('QuickListNotifyRemoved', sprite, resref) end
end

-- fn(sprite): the creature's disabled spell types (opcode 145) or disabled buttons (opcode 144) changed after its
-- effects were evaluated.
local disableState = {}
local function stateKey(stats)
	local parts = {}
	for i = 0, 3 do parts[#parts + 1] = stats.m_disabledSpellTypes:get(i) end
	for i = 0, 15 do parts[#parts + 1] = stats.m_disabledButtons:get(i) end
	return table.concat(parts, ',')
end
local watching = false
function EEex_Sprite_AddSpellDisableStateChangedListener(fn)
	IEX_AddListener('SpellDisableStateChanged', fn)
	if watching then return end
	watching = true
	IEX_AddListener('OpcodeListsResolved', function(sprite)
		if not sprite then return end
		local key = stateKey(EEex_Sprite_GetActiveStats(sprite))
		local id = sprite.m_id
		local old = disableState[id]
		disableState[id] = key
		if old and old ~= key then IEX_Dispatch('SpellDisableStateChanged', sprite) end
	end)
	IEX_AddListener('GameStateDestroyed', function() disableState = {} end)
end

-- --- Screen size (options menus scale their fonts with it) ---

-- UI screen size (CVidMode::SCREENWIDTH / SCREENHEIGHT, what Infinity_GetScreenSize returns). The window size
-- is EngineGlobals.g_pBaldurChitin.cVideo.pCurrentMode.nWidth / nHeight (engine fields): mods scale font points
-- by nHeight / SCREENHEIGHT, and a 0 point size crashes the engine's text measure, so it must be the real one.
CVidMode = CVidMode or {}
if getmetatable(CVidMode) == nil then
	setmetatable(CVidMode, { __index = function(_, key)
		if key == 'SCREENWIDTH' then return (Infinity_GetScreenSize()) end
		if key == 'SCREENHEIGHT' then return select(2, Infinity_GetScreenSize()) end
	end })
end

-- --- Known spells with their ability, innate abilities ---

-- Innate abilities known by the creature (one level, 0 like the first mage / priest level): iterator over
-- (0, index, resref).
function EEex_Sprite_GetKnownInnateSpellsIterator(sprite)
	local resrefs = {}
	IEX_IterateList(sprite.m_knownSpellsInnate, function(spell)
		resrefs[#resrefs + 1] = spell.m_knownSpellId:get()
	end)
	local i = 0
	return function()
		i = i + 1
		if resrefs[i] then return 0, i, resrefs[i] end
	end
end

-- Adds the spell header and the ability the creature casts it with (its caster level for that spell) to a
-- known-spells iterator: (level, index, resref, header, ability). Spells whose file is missing are skipped.
local function withAbility(sprite, itr)
	return function()
		while true do
			local level, index, resref = itr()
			if level == nil then return nil end
			local header = EEex_Resource_Demand(resref, 'SPL')
			if header then
				local casterLevel = EEex_Sprite_GetCasterLevelForSpell(sprite, resref, true)
				return level, index, resref, header, EEex_Resource_GetSpellAbilityForLevel(header, casterLevel)
			end
		end
	end
end

function EEex_Sprite_GetKnownMageSpellsWithAbilityIterator(sprite, startLevel, endLevel)
	return withAbility(sprite, EEex_Sprite_GetKnownMageSpellsIterator(sprite, startLevel, endLevel))
end
function EEex_Sprite_GetKnownPriestSpellsWithAbilityIterator(sprite, startLevel, endLevel)
	return withAbility(sprite, EEex_Sprite_GetKnownPriestSpellsIterator(sprite, startLevel, endLevel))
end
function EEex_Sprite_GetKnownInnateSpellsWithAbilityIterator(sprite)
	return withAbility(sprite, EEex_Sprite_GetKnownInnateSpellsIterator(sprite))
end

-- Resrefs (an iterator of strings) -> iterator of (resref, header, ability) for the ones that exist, the
-- ability chosen by the creature's caster level for the spell: the input of EEex_Actionbar_GetOp214ButtonDataItr.
function EEex_Sprite_GetValidSpellsWithAbilityIterator(sprite, resrefItr)
	return function()
		while true do
			local resref = resrefItr()
			if resref == nil then return nil end
			if type(resref) ~= 'string' and resref.get then resref = resref:get() end
			local header = EEex_Resource_Demand(resref, 'SPL')
			if header then
				local casterLevel = EEex_Sprite_GetCasterLevelForSpell(sprite, resref, true)
				local ability = EEex_Resource_GetSpellAbilityForLevel(header, casterLevel)
				if ability then return resref, header, ability end
			end
		end
	end
end

-- Calls fn(sprite) for every selected creature.
function EEex_Sprite_IterateSelected(fn)
	for _, sprite in ipairs(EEex_Sprite_GetAllSelected()) do fn(sprite) end
end

do
	local methods = {
		getKnownMageSpellsItr = EEex_Sprite_GetKnownMageSpellsIterator,
		getKnownPriestSpellsItr = EEex_Sprite_GetKnownPriestSpellsIterator,
		getKnownInnateSpellsItr = EEex_Sprite_GetKnownInnateSpellsIterator,
		getKnownMageSpellsWithAbilityItr = EEex_Sprite_GetKnownMageSpellsWithAbilityIterator,
		getKnownPriestSpellsWithAbilityItr = EEex_Sprite_GetKnownPriestSpellsWithAbilityIterator,
		getKnownInnateSpellsWithAbilityItr = EEex_Sprite_GetKnownInnateSpellsWithAbilityIterator,
		getValidSpellsWithAbilityItr = EEex_Sprite_GetValidSpellsWithAbilityIterator,
	}
	for name, fn in pairs(methods) do
		CGameSprite[name] = fn
		CGameSprite[name:gsub('Itr$', 'Iterator')] = fn
	end
end
-- EEex_Sprite_...Itr: short names of the iterator functions
for _, name in ipairs({ 'GetKnownMageSpells', 'GetKnownPriestSpells', 'GetKnownInnateSpells',
		'GetKnownMageSpellsWithAbility', 'GetKnownPriestSpellsWithAbility', 'GetKnownInnateSpellsWithAbility',
		'GetValidSpellsWithAbility' }) do
	_G['EEex_Sprite_' .. name .. 'Itr'] = _G['EEex_Sprite_' .. name .. 'Iterator']
end
