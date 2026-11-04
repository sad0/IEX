-- EEex-compatible action bar API (CInfButtonArray of the game, see src/core/actionbar.cpp for the hooks).
--
-- The bar has a state (which set of 12 buttons it shows: a class bar, the spell list...) and 12 button kinds
-- (m_buttonTypes). Changing the state rebuilds the kinds; IEX then runs the EEex_Actionbar_AddListener
-- listeners (they may replace kinds with EEex_Actionbar_SetButton) before the engine builds the buttons,
-- then the EEex_Actionbar_AddButtonsUpdatedListener listeners (they may restyle the built buttons).

-- Button kinds, as the engine numbers them (CInfButtonArray::UpdateButtons switch; tooltips from ENGINEST.2DA).
EEex_Actionbar_ButtonType = {
	BARD_SONG = 2,
	CAST_SPELL = 3,
	FIND_TRAPS = 4,       -- also the shaman's dance slot
	TALK = 5,
	GUARD = 7,
	ATTACK = 8,
	SPECIAL_ABILITIES = 10,
	STEALTH = 11,
	THIEVING = 12,
	TURN_UNDEAD = 13,
	USE_ITEM = 14,
	STOP = 15,
	QUICK_ITEM_1 = 21,
	QUICK_ITEM_2 = 22,
	QUICK_ITEM_3 = 23,
	QUICK_SPELL_1 = 24,
	QUICK_SPELL_2 = 25,
	QUICK_SPELL_3 = 26,
	QUICK_WEAPON_1 = 27,
	QUICK_WEAPON_2 = 28,
	QUICK_WEAPON_3 = 29,
	QUICK_WEAPON_4 = 30,
	NONE = 100,
}

-- The game's button array (nil before a game exists).
function EEex_Actionbar_GetArray()
	local chitin = EEex_EngineGlobal_CBaldurChitin
	local game = chitin and chitin.m_pObjectGame
	return game and game.m_cButtonArray or nil
end

function EEex_Actionbar_GetState()
	local array = EEex_Actionbar_GetArray()
	return array and array.m_nState or 0
end

-- State shown before the current sub-state (spell list, item list...) was opened.
function EEex_Actionbar_GetLastState()
	local array = EEex_Actionbar_GetArray()
	return array and array.m_nLastState or 0
end

function EEex_Actionbar_SetState(state)
	local array = EEex_Actionbar_GetArray()
	if array then IEX_ActionbarSetState(array, state) end
end

function EEex_Actionbar_RestoreLastState()
	EEex_Actionbar_SetState(EEex_Actionbar_GetLastState())
end

-- Button configuration of a state: states sharing the same buttons share a config (documented EEex mapping).
local CONFIG_OF_STATE = { [20] = 18, [21] = 19, [101] = 20, [102] = 21, [103] = 21, [104] = 22, [105] = 22,
	[106] = 23, [107] = 24, [108] = 25, [109] = 26, [110] = 27, [111] = 28, [112] = 29, [113] = 30, [114] = 30 }
function IEX_ActionbarConfig(state)
	if state >= 1 and state <= 18 then return state - 1 end
	return CONFIG_OF_STATE[state] or -1
end

-- Replaces the kind of button `index` (0-11). Inside an action bar listener the engine builds the buttons
-- right after; elsewhere the bar is rebuilt at once.
local inStateListeners = false
function EEex_Actionbar_SetButton(index, buttonType)
	local array = EEex_Actionbar_GetArray()
	if not array then return end
	if type(index) ~= 'number' or index < 0 or index > 11 then
		error('EEex_Actionbar_SetButton: index 0-11 expected, got ' .. tostring(index), 2)
	end
	array.m_buttonTypes:set(index, buttonType)
	if not inStateListeners then IEX_ActionbarUpdate(array) end
end

-- --- Listeners ---

-- fn(config, state): the bar changed state (also when the same state is set again, e.g. another character).
function EEex_Actionbar_AddListener(fn) IEX_AddListener('ActionbarState', fn) end
EEex_Actionbar_Private_StateListeners = IEX_GetListeners('ActionbarState')

local suppressed = 0
function EEex_Actionbar_SuppressListeners() suppressed = suppressed + 1 end
function EEex_Actionbar_AllowListeners() if suppressed > 0 then suppressed = suppressed - 1 end end
function EEex_Actionbar_RunWithListenersSuppressed(fn, ...)
	suppressed = suppressed + 1
	local results = table.pack(pcall(fn, ...))
	suppressed = suppressed - 1
	if not results[1] then error(results[2], 0) end
	return table.unpack(results, 2, results.n)
end

-- True while the THIEVING hotkey opened the special abilities list (thief kind not on the main bar).
-- IEX does not track that hotkey yet: always nil (EEex's "not opening" value is nil, not false).
function EEex_Actionbar_IsThievingHotkeyOpeningSpecialAbilities()
	return nil
end

-- The engine also sets bar states while it starts up, before the UI and its globals (e, worldScreen) exist:
-- listeners run once the game state is initialized, like the UI code they call into.
local uiReady = false
IEX_AddListener('GameStateInitialized', function() uiReady = true end)

-- EEex also runs them while a save loads and nobody is selected yet (state 0, config -1): so does IEX (a listener
-- that needs the selected creature fails under pcall and only that listener is skipped, as under EEex).
IEX_AddListener('ActionbarStateChanged', function()
	if suppressed > 0 or not uiReady then return end
	local state = EEex_Actionbar_GetState()
	inStateListeners = true
	local ok, err = pcall(IEX_Dispatch, 'ActionbarState', IEX_ActionbarConfig(state), state)
	inStateListeners = false
	if not ok then IEX_Log('Action bar listeners failed: ' .. tostring(err)) end
end)

-- --- Opcode 214 (select spell) from Lua ---

-- Turns an iterator of (spellResRef, spellHeader, spellAbility) into an iterator of button data, one per
-- spell, for an opcode 214 "from Lua" list. Fields follow the engine's CButtonData names; the mod may
-- edit them (m_count, m_bDisplayCount, m_abilityId.m_itemType...) before the list is built.
function EEex_Actionbar_GetOp214ButtonDataItr(itr)
	return function()
		while true do
			local resref, header, ability = itr()
			if resref == nil then return nil end
			if type(resref) ~= 'string' and resref.get then resref = resref:get() end
			return {
				m_abilityId = { m_itemType = 1, m_res = resref, m_itemNum = -1, m_abilityNum = 0, m_targetType = ability and ability.actionType or 0 },
				m_icon = ability and ability.quickSlotIcon and ability.quickSlotIcon:get() or '',
				m_name = header and header.genericName or -1,
				m_count = 0,
				m_bDisplayCount = false,
				m_launcherIcon = '',
				m_spellResRef = resref, m_spellHeader = header, m_spellAbility = ability,
			}
		end
	end
end
EEex_Actionbar_GetOp214ButtonDataIterator = EEex_Actionbar_GetOp214ButtonDataItr

-- Selected (leader) game object; EEex has it under the GameObject prefix too.
if rawget(_G, 'EEex_GameObject_GetSelected') == nil then
	function EEex_GameObject_GetSelected() return EEex_Sprite_GetSelected() end
end
if rawget(_G, 'EEex_GameObject_GetSelectedID') == nil then
	function EEex_GameObject_GetSelectedID() return EEex_Sprite_GetSelectedID() end
end
