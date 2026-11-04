-- The player modules EEex.ini switches on ([X Module] Enable=1, read at start; the Modules tab of the options
-- screen writes them). Behaviour as EEex 1.3.1 shows it (difftest modules 2026-10-29, eeex-docs.readthedocs.io
-- "Components"); IEX's own code. Menus: IEXMOD.menu (override), same menu names as EEex.
--   Empty Container   gray highlight for empty containers (native hook: src/core/modules.cpp)
--   Time Step         a key (D) that advances a paused game by one tick; held half a second: time flows
--   Timer             bars left of the party portraits: modal action (red), contingency check (green),
--                     spell / item cooldown (cyan)
--   Effect Menu       a key (Left Shift) held over a creature lists the spells affecting it
--   Attack Info       to-hit chances of the selected party against the creature under an attack cursor
--                     (Left Alt: the creature against the party)

IEXModules = IEXModules or {}
local MOD = IEXModules
IEX_ModulesAvailable = IEX_ModulesAvailable or {}
IEXOpt = IEXOpt or {}
IEXOpt.strings = IEXOpt.strings or {}
local S = IEXOpt.strings

local function log(msg)
	if IEX_Log then pcall(IEX_Log, '[Modules] ' .. tostring(msg)) end
end

local function iniEnabled(section)
	local ini = IEX_Settings and IEX_Settings.eeexIni
	local s = type(ini) == 'table' and ini[section]
	return type(s) == 'table' and tonumber(s.enable) == 1
end

local function now() return Infinity_GetClockTicks() end
local function worldActive()
	local ok, r = pcall(function() return worldScreen ~= nil and e:GetActiveEngine() == worldScreen end)
	return ok and r
end
local function paused()
	local ok, r = pcall(function() return worldScreen:CheckIfPaused() end)
	return ok and r and true or false
end
local function togglePause() pcall(function() worldScreen:TogglePauseGame(true) end) end
local function gameTick()
	local ok, t = pcall(function() return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame.m_worldTime.m_gameTime end)
	return ok and t or 0
end
local function keyCode(name) return EEex_Key_GetFromName and EEex_Key_GetFromName(name) or nil end
-- A key binding option value { modifier..., key } matches when its last key is `key` and the others are held.
local function keysMatch(keys, key)
	if type(keys) ~= 'table' or #keys == 0 or keys[#keys] ~= key then return false end
	for i = 1, #keys - 1 do
		if not (EEex_Key_IsDown and EEex_Key_IsDown(keys[i])) then return false end
	end
	return true
end
local function keysHeld(keys)
	if type(keys) ~= 'table' or #keys == 0 then return false end
	for i = 1, #keys do
		if not (EEex_Key_IsDown and EEex_Key_IsDown(keys[i])) then return false end
	end
	return true
end

-- Option helpers (EEex_Options classes); values persist in Baldur.lua [EEex Modules].
local function keyOption(id, keyName, storageKey)
	EEex_Options_Register(id, EEex_Options_Option.new({
		['default'] = { keyCode(keyName) },
		['type'] = EEex_Options_KeybindType.new(),
		['accessor'] = EEex_Options_KeybindAccessor.new(),
		['storage'] = EEex_Options_KeybindLuaStorage.new({ ['section'] = 'EEex Modules', ['key'] = storageKey }),
	}))
	return EEex_Options_Get(id)
end
local function numOption(id, default, min, max, storageKey, onChange)
	EEex_Options_Register(id, EEex_Options_Option.new({
		['default'] = default,
		['type'] = EEex_Options_EditType.new(),
		['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = min, ['max'] = max }),
		['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = 'EEex Modules', ['key'] = storageKey }),
		['onChange'] = onChange,
	}))
	return EEex_Options_Get(id)
end
local function toggleOption(id, default, storageKey)
	EEex_Options_Register(id, EEex_Options_Option.new({
		['default'] = default,
		['type'] = EEex_Options_ToggleType.new(),
		['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 1 }),
		['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = 'EEex Modules', ['key'] = storageKey }),
	}))
	return EEex_Options_Get(id)
end
local function entry(id, label, desc, widget)
	S[id .. '_LABEL'] = label
	S[id .. '_DESC'] = desc
	return EEex_Options_DisplayEntry.new({ ['optionID'] = id, ['label'] = id .. '_LABEL',
		['description'] = id .. '_DESC', ['widget'] = widget })
end
local function optValue(o, default)
	if not o then return default end
	local ok, v = pcall(function() return o:get() end)
	if ok and v ~= nil then return v end
	return default
end

-- Menus of IEXMOD.menu, loaded once the game's UI is up.
MOD.menusLoaded = MOD.menusLoaded or false
local function loadMenus()
	MOD.menusLoaded = IEX_MenuLoadFile and IEX_MenuLoadFile('IEXMOD') or false
	if not MOD.menusLoaded then log('IEXMOD.MENU not found: the modules have no menus') end
end
local function push(menu)
	if MOD.menusLoaded and not Infinity_IsMenuOnStack(menu) then Infinity_PushMenu(menu) end
end
local function pop(menu)
	if MOD.menusLoaded and Infinity_IsMenuOnStack(menu) then Infinity_PopMenu(menu) end
end
local function setArea(name, x, y, w, h)
	pcall(Infinity_SetArea, name, math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5))
end

-- Per-frame work of the enabled modules (B3TimeStep_Menu's tick label, pushed on the world screen).
MOD.ticks = MOD.ticks or {}
function IEXModules_Tick()
	for _, fn in ipairs(MOD.ticks) do
		local ok, err = pcall(fn)
		if not ok then
			MOD.tickErrors = (MOD.tickErrors or 0) + 1
			if MOD.tickErrors <= 10 then log('tick: ' .. tostring(err)) end
		end
	end
	return false
end
local function keepTickMenu()
	if #MOD.ticks > 0 and worldActive() then push('B3TimeStep_Menu') end
end

-----------------------------------------------------------------------
-- Empty Container
-----------------------------------------------------------------------

local GRAY, CYAN = 0x808080, 0xFFFF00
local function setupEmptyContainer()
	-- a mod may replace the callback (SadoEE's valuable containers): it is looked up at every call
	if B3EmptyContainer_Hook_OnBeforeContainerOutlineRender == nil then
		function B3EmptyContainer_Hook_OnBeforeContainerOutlineRender(container, color)
			if color.value == CYAN and container.m_lstItems.m_nCount == 0 then color.value = GRAY end
		end
	end
	if not (IEX_SetEmptyContainerHook and IEX_SetEmptyContainerHook(true)) then
		log('Empty Container: the engine hook is not available')
	end
end

-----------------------------------------------------------------------
-- Time Step
-----------------------------------------------------------------------

local TS = { active = false }
MOD.timeStep = TS
local function setupTimeStep()
	TS.key = keyOption('B3TimeStep_Keybind', 'D', 'Time Step Keybind')
	EEex_Key_AddPressedListener(function(key)
		if not keysMatch(optValue(TS.key), key) then return end
		if TS.active or not worldActive() or not paused() then return end
		if Infinity_IsMenuOnStack('EEex_Options') then return end
		TS.active, TS.flowing, TS.start, TS.tick = true, false, now(), gameTick()
		togglePause()
	end)
	MOD.ticks[#MOD.ticks + 1] = function()
		if not TS.active then return end
		local held = keysHeld(optValue(TS.key))
		if not TS.flowing and held and now() - TS.start >= 500 then TS.flowing = true end
		if TS.flowing then
			if not held then
				TS.active = false
				if not paused() then togglePause() end
			end
		elseif gameTick() ~= TS.tick then
			TS.active = false
			if not paused() then togglePause() end
		end
	end
	EEex_Options_AddTab('EEex_Options_TRANSLATION_TimeStep_TabTitle', function() return { {
		entry('B3TimeStep_Keybind', 'Advance Time Keybind',
			'While the game is paused, this key lets time run for the shortest possible moment (one game tick), then pauses again.\n\nHeld for half a second, it lets time run until it is released.',
			EEex_Options_KeybindWidget.new()),
	} } end)
	S.EEex_Options_TRANSLATION_TimeStep_TabTitle = 'Module: Time Step'
end

-----------------------------------------------------------------------
-- Timer
-----------------------------------------------------------------------

local TM = { portraits = {}, at = 0 }
MOD.timer = TM
-- EEex 1.3.1 draws the bars about 15 UI pixels left of the portrait (difftest modules 2026-10-29 screenshots)
local BAR_W, BAR_GAP = 2, 12
-- The portrait buttons of the sidebars (button.portrait = party slot 0-5), as the screen shows them.
local function findPortraits()
	TM.portraits = {}
	for _, menuName in ipairs({ 'RIGHT_SIDEBAR', 'LEFT_SIDEBAR' }) do
		local menu = EEex_Menu_Find(menuName)
		local item = menu and menu.items
		while item ~= nil do
			local ok, slot = pcall(function()
				local v = item.button.portrait
				if v == nil then return nil end
				return EEex_Menu_GetItemVariant(v)
			end)
			if ok and type(slot) == 'number' and slot >= 0 and slot <= 5 and not TM.portraits[slot + 1] then
				TM.portraits[slot + 1] = item
			end
			item = item.next
		end
	end
end
local function hasContingency(sprite)
	local found = false
	pcall(function()
		EEex_Utility_IterateCPtrList(sprite.m_timedEffectList, function(effect)
			if effect.m_effectId == 232 then found = true return true end
		end)
	end)
	return found
end
-- Fraction (0-1) of the bar `kind` (1 modal, 2 contingency, 3 cast) for party slot `slot`, or nil.
local function barFraction(kind, sprite)
	if kind == 1 then
		if not TM.showModal or sprite.m_nModalState == 0 then return nil end
		return 1 - EEex_Sprite_GetModalTimer(sprite) / 100
	elseif kind == 2 then
		if not TM.showContingency then return nil end
		local id = sprite.m_id
		local now = gameTick()
		if TM.contAt ~= now then TM.contAt, TM.cont = now, {} end
		local has = TM.cont[id]
		if has == nil then has = hasContingency(sprite) TM.cont[id] = has end
		if not has then return nil end
		return 1 - math.max(0, math.min(100, sprite.m_contingencyCountdown)) / 100
	else
		if not TM.showCast then return nil end
		local c = sprite.m_castCounter
		if c < 0 then return nil end
		return 1 - math.min(c, 100) / 100
	end
end
function IEXTimer_Bar(kind, slot)
	local ok, shown = pcall(function()
		if Infinity_GetClockTicks() - TM.at > 1000 then TM.at = Infinity_GetClockTicks() findPortraits() end
		local item = TM.portraits[slot]
		local sprite = EEex_Sprite_GetInPortrait(slot - 1)
		if not item or not sprite then return false end
		local f = barFraction(kind, sprite)
		if not f or f <= 0 then return false end
		local x, y, w, h = EEex_Menu_GetUIItemArea(item)
		local gap = TM.hug and 0 or BAR_GAP
		local bx = x - gap - kind * (BAR_W + 1)
		local bh = h * math.min(f, 1)
		setArea('B3TIMER_' .. ({ 'M', 'C', 'S' })[kind] .. slot, bx, y + h - bh, BAR_W, bh)
		return true
	end)
	return ok and shown or false
end
local function setupTimer()
	local modal = toggleOption('B3Timer_ShowModalTimer', 1, 'Timer Show Modal')
	local cont = toggleOption('B3Timer_ShowContingencyTimer', 1, 'Timer Show Contingency')
	local cast = toggleOption('B3Timer_ShowCastTimer', 1, 'Timer Show Cast')
	local hug = toggleOption('B3Timer_HugPortraits', 0, 'Timer Hug Portraits')
	MOD.ticks[#MOD.ticks + 1] = function()
		TM.showModal = optValue(modal, 1) ~= 0
		TM.showContingency = optValue(cont, 1) ~= 0
		TM.showCast = optValue(cast, 1) ~= 0
		TM.hug = optValue(hug, 0) ~= 0
		push('B3Timer_Menu')
	end
	EEex_Options_AddTab('EEex_Options_TRANSLATION_Timer_TabTitle', function() return { {
		entry('B3Timer_HugPortraits', 'Hug Portraits', 'The bars touch their portrait (no gap).', EEex_Options_ToggleWidget.new()),
		entry('B3Timer_ShowCastTimer', 'Show Cast Timer',
			'A cyan bar beside the portrait: time left before the character can use a spell or an item again.',
			EEex_Options_ToggleWidget.new()),
		entry('B3Timer_ShowContingencyTimer', 'Show Contingency Timer',
			'A green bar beside the portrait of a character with a contingency: time until its conditions are checked again.\n\nSome mods use hidden contingencies: the bar can then show up on its own.',
			EEex_Options_ToggleWidget.new()),
		entry('B3Timer_ShowModalTimer', 'Show Modal Timer',
			'A red bar beside the portrait: time until the current modal action (find traps, turn undead, battle song...) applies again.',
			EEex_Options_ToggleWidget.new()),
	} } end)
	S.EEex_Options_TRANSLATION_Timer_TabTitle = 'Module: Timer'
end

-----------------------------------------------------------------------
-- Effect Menu
-----------------------------------------------------------------------

local EM = { open = false }
MOD.effectMenu = EM
iexEffMenuRows = iexEffMenuRows or {}
iexEffMenuRow = 0
function IEXEffMenu_Icon(r) local x = iexEffMenuRows[r] return x and x.icon or '' end
function IEXEffMenu_Name(r) local x = iexEffMenuRows[r] return x and x.name or '' end
function B3EffectMenu_IsOpen() return EM.open end

local function spellRows(sprite)
	local rows, seen = {}, {}
	pcall(function()
		EEex_Utility_IterateCPtrList(sprite.m_timedEffectList, function(effect)
			local res = effect.m_sourceRes:get()
			if res and res ~= '' and not seen[res:upper()] then
				seen[res:upper()] = true
				local name, icon = nil, ''
				local ok, header = pcall(EEex_Resource_Demand, res, 'SPL')
				if not ok or not header then ok, header = pcall(EEex_Resource_Demand, res, 'ITM') end
				if ok and header then
					pcall(function()
						local strref = header.genericName
						if strref and strref ~= -1 and strref ~= 0xFFFFFFFF then name = Infinity_FetchString(strref) end
					end)
					pcall(function() icon = header.spellbookIcon:get() end)
					if icon == '' then pcall(function() icon = header.itemIcon:get() end) end
				end
				if name == nil or name == '' then name = S.B3EffectMenu_TRANSLATION_No_Name end
				rows[#rows + 1] = { res = res, name = name, icon = icon or '' }
			end
		end)
	end)
	table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return rows
end
local function layoutEffectMenu(rowCount)
	local mx, my = 0, 0
	pcall(function() mx, my = Infinity_GetMousePosition() end)
	local sw, sh = 1024, 768
	pcall(function() sw, sh = Infinity_GetScreenSize() end)
	local w, rowH = 260, 44
	local h = rowCount * rowH + 12
	local x, y = mx + 16, my + 16
	if x + w > sw then x = mx - w - 16 end
	if y + h > sh then y = math.max(0, sh - h) end
	setArea('B3EffectMenu_Menu_Border', x - 2, y - 2, w + 4, h + 4)
	setArea('B3EffectMenu_Menu_Background', x, y, w, h)
	setArea('B3EffectMenu_Menu_List', x + 6, y + 6, w - 12, h - 12)
end
local function setupEffectMenu()
	S.B3EffectMenu_TRANSLATION_No_Name = '(No Name)'
	EM.key = keyOption('B3EffectMenu_LaunchKeybind', 'Left Shift', 'Effect Menu Launch Keybind')
	EM.rows = numOption('B3EffectMenu_RowCount', 4, 1, 20, 'Effect Menu Row Count')
	B3EffectMenu_Key = (optValue(EM.key) or {})[1]
	MOD.ticks[#MOD.ticks + 1] = function()
		local keys = optValue(EM.key)
		B3EffectMenu_Key = type(keys) == 'table' and keys[#keys] or B3EffectMenu_Key
		local held = keysHeld(keys)
		if EM.open then
			if held or EEex_Menu_IsCursorWithin('B3EffectMenu_Menu', 'B3EffectMenu_Menu_Background') then return end
			EM.open, EM.target = false, nil
			pop('B3EffectMenu_Menu')
			return
		end
		if not held then return end
		local target = EEex_GameObject_GetUnderCursor()
		if not (target and EEex_GameObject_IsSprite(target)) then return end
		iexEffMenuRows = spellRows(target)
		if #iexEffMenuRows == 0 then return end
		EM.open, EM.target = true, target.m_id
		local n = math.min(#iexEffMenuRows, optValue(EM.rows, 4))
		layoutEffectMenu(n)
		push('B3EffectMenu_Menu')
	end
	EEex_Options_AddTab('EEex_Options_TRANSLATION_EffectMenu_TabTitle', function() return { {
		entry('B3EffectMenu_LaunchKeybind', 'Launch Keybind',
			'Hold this key with the mouse over a creature to list the spells affecting it.', EEex_Options_KeybindWidget.new()),
		entry('B3EffectMenu_RowCount', 'Row Count', 'How many rows the list shows at once.', EEex_Options_EditWidget.new()),
	} } end)
	S.EEex_Options_TRANSLATION_EffectMenu_TabTitle = 'Module: Effect Menu'
end

-----------------------------------------------------------------------
-- Attack Info
-----------------------------------------------------------------------

local AI = { open = false }
MOD.attackInfo = AI
iexAtkRows = iexAtkRows or {}
iexAtkRow = 0
function IEXAtk_Title() return AI.title or '' end
function IEXAtk_Point() return optValue(AI.font, 11) end
function IEXAtk_Cell(r, c) local x = iexAtkRows[r] return x and x[c] or '' end

-- STATS.IDS: ARMORCLASS 2, ACCRUSHINGMOD 3, ACMISSILEMOD 4, ACPIERCINGMOD 5, ACSLASHINGMOD 6, THAC0 7.
local MELEE = { [16] = true, [17] = true, [19] = true, [20] = true, [21] = true, [22] = true, [23] = true,
	[25] = true, [26] = true, [28] = true, [29] = true, [30] = true, [44] = true, [57] = true, [69] = true }
local function weaponIn(sprite, slot)
	local ok, res = pcall(function()
		local item = sprite.m_equipment.m_items:get(slot)
		return item and item.pRes.resref:get()
	end)
	if not ok or not res or res == '' then return nil end
	local okH, header = pcall(EEex_Resource_Demand, res, 'ITM')
	return okH and header or nil
end
local function stat(sprite, id)
	local ok, v = pcall(EEex_Sprite_GetStat, sprite, id)
	return ok and tonumber(v) or 0
end
-- Chance (0-100) that `attacker` hits `target` with its main / offhand weapon: a d20 roll of at least
-- THAC0 - AC (the AC adjusted for the weapon's damage type); 1 always misses, 20 always hits.
local function hitChance(attacker, target, offhand)
	local thac0 = stat(attacker, 7)
	local ac = stat(target, 2)
	local mod = stat(target, 6)  -- slashing by default
	local slot = 9
	if not offhand then
		local ok, sel = pcall(function() return attacker.m_equipment.m_selectedWeapon end)
		slot = ok and tonumber(sel) or 10
	end
	local weapon = weaponIn(attacker, slot)
	if weapon then
		pcall(function()
			local ability = weapon:getAbility(0)
			if ability then
				thac0 = thac0 - (ability.toHitBonus or 0)
				local dt = ability.damageType
				if dt == 1 then mod = stat(target, 5) elseif dt == 2 then mod = stat(target, 3)
				elseif dt == 3 then mod = stat(target, 6) elseif dt == 4 then mod = stat(target, 4) end
			end
		end)
	end
	if offhand then thac0 = thac0 + 4 end  -- base offhand penalty (proficiency and style reduce it: not counted)
	local need = thac0 - (ac + mod)
	need = math.max(2, math.min(20, need))
	return (21 - need) * 5
end
local function isEnemy(sprite)
	local ok, ea = pcall(function() return sprite.m_typeAI.m_EnemyAlly end)
	return ok and ea and ea >= 200
end
local function setupAttackInfo()
	AI.font = numOption('B3AttackInfo_FontPoint', 11, 6, 40, 'Attack Info Font Point')
	AI.openKey = keyOption('B3AttackInfo_OpenKeybind', 'Left Ctrl', 'Attack Info Open Keybind')
	AI.reverseKey = keyOption('B3AttackInfo_ReverseKeybind', 'Left Alt', 'Attack Info Reverse Keybind')
	AI.withCursor = toggleOption('B3AttackInfo_OpenWithAttackCursor', 1, 'Attack Info Open With Attack Cursor')
	AI.headers = toggleOption('B3AttackInfo_ShowColumnHeaders', 1, 'Attack Info Show Column Headers')
	AI.enabled = toggleOption('B3AttackInfo_Enable', 1, 'Attack Info Enabled')
	function B3AttackInfo_SetEnabled(on) pcall(function() AI.enabled:set(on and 1 or 0) end) end
	MOD.ticks[#MOD.ticks + 1] = function()
		local target = optValue(AI.enabled, 1) ~= 0 and EEex_GameObject_GetUnderCursor() or nil
		if target and not EEex_GameObject_IsSprite(target) then target = nil end
		local party = {}
		if target then
			EEex_Sprite_IterateSelected(function(s) if s.m_id ~= target.m_id then party[#party + 1] = s end end)
		end
		local want = target and #party > 0 and (keysHeld(optValue(AI.openKey)) or keysHeld(optValue(AI.reverseKey))
			or (optValue(AI.withCursor, 1) ~= 0 and isEnemy(target)))
		if not want then
			if AI.open then AI.open = false pop('B3AttackInfo_Menu') end
			return
		end
		local reverse = keysHeld(optValue(AI.reverseKey))
		local rows, anyOff = {}, false
		for _, s in ipairs(party) do
			local main, off
			if reverse then
				main = hitChance(target, s, false)
			else
				main = hitChance(s, target, false)
				local o = weaponIn(s, 9)
				if o and MELEE[o.itemType] then off = hitChance(s, target, true) anyOff = true end
			end
			rows[#rows + 1] = { EEex_Sprite_GetName(s) or '?', main .. '%', off and (off .. '%') or '' }
		end
		if optValue(AI.headers, 1) ~= 0 then table.insert(rows, 1, { '', 'Main', anyOff and 'Offhand' or '' }) end
		iexAtkRows = rows
		AI.title = reverse and 'Target attacks party' or 'Party attacks target'
		local mx, my = 0, 0
		pcall(function() mx, my = Infinity_GetMousePosition() end)
		local w, h = 230, 26 + #rows * 18
		setArea('B3AttackInfo_Menu_Border', mx + 18, my + 18, w + 4, h + 4)
		setArea('B3AttackInfo_Menu_Background', mx + 20, my + 20, w, h)
		setArea('B3AttackInfo_Menu_Title', mx + 26, my + 22, w - 12, 20)
		setArea('B3AttackInfo_Menu_List', mx + 24, my + 44, w - 8, h - 26)
		AI.open = true
		push('B3AttackInfo_Menu')
	end
	EEex_Options_AddTab('EEex_Options_TRANSLATION_AttackInfo_TabTitle', function() return { {
		entry('B3AttackInfo_Enable', 'Enabled', 'Shows the attack information popup.', EEex_Options_ToggleWidget.new()),
		entry('B3AttackInfo_FontPoint', 'Font Point', 'Size of the popup text.', EEex_Options_EditWidget.new()),
		entry('B3AttackInfo_OpenKeybind', 'Open Keybind', 'Held over a creature, this key opens the popup.',
			EEex_Options_KeybindWidget.new()),
		entry('B3AttackInfo_OpenWithAttackCursor', 'Open With Attack Cursor',
			'The popup opens by itself over a hostile creature.', EEex_Options_ToggleWidget.new()),
		entry('B3AttackInfo_ReverseKeybind', 'Reverse Keybind',
			'Held, the popup shows the chances of the creature under the cursor against the selected party members.',
			EEex_Options_KeybindWidget.new()),
		entry('B3AttackInfo_ShowColumnHeaders', 'Show Column Headers', 'The first row names the columns.',
			EEex_Options_ToggleWidget.new()),
	} } end)
	S.EEex_Options_TRANSLATION_AttackInfo_TabTitle = 'Module: Attack Info'
end

-----------------------------------------------------------------------
-- Start
-----------------------------------------------------------------------

local SETUP = {
	{ 'B3EmptyContainer', 'empty container module', setupEmptyContainer },
	{ 'B3TimeStep', 'time step module', setupTimeStep },
	{ 'B3Timer', 'timer module', setupTimer },
	{ 'B3EffMen', 'effect menu module', setupEffectMenu },
	{ 'B3AttackInfo', 'attack info module', setupAttackInfo },
}
for _, m in ipairs(SETUP) do IEX_ModulesAvailable[m[1]] = true end

if not MOD.started then
	MOD.started = true
	for _, m in ipairs(SETUP) do
		if iniEnabled(m[2]) then
			local ok, err = pcall(m[3])
			if ok then
				EEex_Modules[m[1]] = true
				log(m[2] .. ' on')
			else
				log(m[2] .. ': ' .. tostring(err))
			end
		end
	end
	if #MOD.ticks > 0 then
		EEex_Menu_AddMainFileLoadedListener(loadMenus)
		if EEex_Menu_AddAfterMainFileReloadedListener then EEex_Menu_AddAfterMainFileReloadedListener(loadMenus) end
		IEX_AddListener('EngineTickDone', function() pcall(keepTickMenu) end)
	end
end
