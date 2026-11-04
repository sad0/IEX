-- The options screen (what EEex calls "EEex Options"): the tabs mods register with EEex_Options_AddTab, each a set
-- of columns of display entries (label + widget). Opened from a button IEX adds to the game's Options menu (where
-- EEex 1.3.1 puts its own, 2026-10-30 observations: vanilla UI: ESC_MENU, above Return; Infinity UI++: the options
-- column RG_START_OPTIONS_BAR, under its last button, also shown in the start screen's options), from its key
-- binding (\ by default, "Open Options" in the Keybinds tab) or by EEex_Options_Open(). The screen opens over the
-- menu it was opened from (the ESC menu stays under it and is back when it closes). Layout as EEex 1.3.1 shows it (difftest 2026-10-29 screenshots): a dark panel in the middle
-- of the screen, title, tabs on the left sorted by name, the tab's options in the middle (switches are the game's
-- red diamonds), the description of the option clicked last on the right. Menu file: IEXOPT.menu (override).
-- Values apply at once (option:_set: live value, storage, onChange).

IEXOpt = IEXOpt or {}
local O = IEXOpt

-- IEX's own texts (English; the game's uiStrings table is replaced when a translation loads, so they are kept
-- here and looked up first).
O.strings = O.strings or {}
local S = O.strings
S.IEX_OPTIONS_TITLE = 'IEX Options'
S.IEX_OPTIONS_BUTTON = 'IEX Options'
S.IEX_OPTIONS_HINT = 'Click an option label to view its description.'
S.IEX_OPTIONS_RESTART = '(applies after a restart)'
S.IEX_OPTIONS_PRESSKEY = 'Press a key...'
local function setStrings() end

local function log(msg)
	if IEX_Log then pcall(IEX_Log, '[OptionsUI] ' .. tostring(msg)) end
end

-- A uiStrings key (or plain text) as shown.
local function tr(key)
	if type(key) ~= 'string' then return key ~= nil and tostring(key) or '' end
	local v = S[key]
	if v == nil and type(uiStrings) == 'table' then v = uiStrings[key] end
	if v == nil and t then
		local ok, s = pcall(t, key)
		if ok and type(s) == 'string' then v = s end
	end
	return v or key
end

O.MENU = IEX_OptionsMenuName or 'EEex_Options'
O.loaded = O.loaded or false
O.currentTab = O.currentTab or 0
O.built = O.built or {}       -- tab label -> its built columns (the builder runs once, like EEex's layout)
O.cols = O.cols or { {}, {}, {} }
O.desc = nil
iexOptTabs = iexOptTabs or {}
iexOptTab = iexOptTab or 0
iexOptCol1, iexOptCol2, iexOptCol3 = iexOptCol1 or {}, iexOptCol2 or {}, iexOptCol3 or {}
iexOptRow1, iexOptRow2, iexOptRow3 = 0, 0, 0
iexOptEditText = iexOptEditText or ''

-----------------------------------------------------------------------
-- Rows
-----------------------------------------------------------------------

local function kindOf(widget)
	if type(widget) ~= 'table' then return 'heading' end
	local ok, k = pcall(function() return widget:_kind() end)
	return ok and k or 'heading'
end

-- The builder's result as columns: { {entry, ...}, ... }; a flat list of entries is one column.
local function asColumns(built)
	if type(built) ~= 'table' then return {} end
	local first = built[1]
	if type(first) == 'table' and getmetatable(first) ~= nil and first.optionID ~= nil or
		type(first) == 'table' and first.widget ~= nil then
		return { built }
	end
	return built
end

local function addRows(rows, entry, indent)
	if type(entry) ~= 'table' then return end
	rows[#rows + 1] = { entry = entry, indent = indent }
	if type(entry.subOptions) == 'table' then
		for _, sub in ipairs(entry.subOptions) do addRows(rows, sub, indent + 1) end
	end
end

local function eachEntry(fn)
	for c = 1, 3 do
		for _, row in ipairs(O.cols[c]) do pcall(fn, row.entry) end
	end
end

local function showTab(index)
	O.currentTab = index
	iexOptTab = index
	O.cols = { {}, {}, {} }
	O.desc = nil
	local tab = iexOptTabs[index]
	if tab then
		local cols = O.built[tab.label]
		if cols == nil then
			local ok, built = pcall(tab.builder)
			if not ok then log('tab ' .. tostring(tab.label) .. ': ' .. tostring(built)) end
			cols = asColumns(ok and built or nil)
			O.built[tab.label] = cols
		end
		for c, col in ipairs(cols) do
			if c > 3 then break end
			for _, entry in ipairs(type(col) == 'table' and col or {}) do addRows(O.cols[c], entry, 0) end
		end
	end
	iexOptCol1, iexOptCol2, iexOptCol3 = O.cols[1], O.cols[2], O.cols[3]
	eachEntry(function(e)
		if e.widget and e.widget._onShowBeforeLayout then e.widget:_onShowBeforeLayout() end
	end)
	pcall(IEXOpt_Layout)
	eachEntry(function(e)
		if e.widget and e.widget._onShowAfterLayout then e.widget:_onShowAfterLayout() end
	end)
end

local function row(c, r) return O.cols[c] and O.cols[c][r] end

-----------------------------------------------------------------------
-- Menu functions (IEXOPT.menu)
-----------------------------------------------------------------------

function IEXOpt_Title() return tr('IEX_OPTIONS_TITLE') end
function IEXOpt_TabText(r) local tab = iexOptTabs[r] return tab and tab.text or '' end
function IEXOpt_TabClick()
	if iexOptTabs[iexOptTab] then showTab(iexOptTab) end
end

function IEXOpt_RowText(c, r)
	local x = row(c, r)
	if not x then return '' end
	local e = x.entry
	local text = string.rep('    ', x.indent) .. tr(e.label)
	if kindOf(e.widget) == 'heading' then text = '^0xffd7c8a0' .. text .. '^-' end
	local o = e._getOption and e:_getOption()
	if o and o.requiresRestart then text = text .. ' *' end
	return text
end
function IEXOpt_RowKind(c, r)
	local x = row(c, r)
	return x and kindOf(x.entry.widget) or ''
end
-- ROUNDBUT frames, as the game's own option switches: 0 off, 2 on.
function IEXOpt_RowFrame(c, r)
	local x = row(c, r)
	local w = x and x.entry.widget
	return (type(w) == 'table' and w.toggleState) and 2 or 0
end
local function keyText(keys)
	if type(keys) ~= 'table' then keys = { keys } end
	local parts = {}
	for i, k in ipairs(keys) do
		local n = tonumber(k)
		local name = n and IEX_KeyName and IEX_KeyName(n) or ''
		if name ~= '' then parts[i] = name
		elseif n and n >= 32 and n < 127 then parts[i] = string.char(n)
		elseif n then parts[i] = '#' .. n
		else parts[i] = tostring(k) end
	end
	return table.concat(parts, ' + ')
end
function IEXOpt_RowHasValue(c, r)
	local k = IEXOpt_RowKind(c, r)
	return k == 'edit' or k == 'keybind' or k == 'multi'
end
function IEXOpt_RowValue(c, r)
	local x = row(c, r)
	if not x then return '' end
	local e = x.entry
	local k = kindOf(e.widget)
	if k == 'keybind' and O.capture == e then return tr('IEX_OPTIONS_PRESSKEY') end
	local v = e._getWorkingValue and e:_getWorkingValue()
	if k == 'keybind' then return '[ ' .. keyText(v) .. ' ]' end
	return '[ ' .. (v ~= nil and tostring(v) or '') .. ' ]'
end

function IEXOpt_Description()
	local e = O.desc
	if not e then return tr('IEX_OPTIONS_HINT') end
	local text = tr(e.description or e.label)
	local o = e._getOption and e:_getOption()
	if o and o.requiresRestart then text = text .. '\n\n' .. tr('IEX_OPTIONS_RESTART') end
	return text
end

local function apply(e, value)
	if value == nil then return end
	if e._setWorkingValue then e:_setWorkingValue(value, false) end
	if e._set then e:_set(value) end
end

local function clickToggle(e)
	local w = e.widget
	if type(w.toggleWarning) == 'function' then
		local ok, cancel = pcall(w.toggleWarning, w, e)
		if not ok then log('toggleWarning: ' .. tostring(cancel)) end
		if not ok or cancel then return end
	end
	local ok, value = pcall(w._clickValue, w)
	if ok then apply(e, value) end
end

local function clickMulti(e)
	local w = e.widget
	local values, i = {}, 0
	if type(w._getChildWidgetsItr) == 'function' then
		for child in w:_getChildWidgetsItr() do
			if type(child) == 'table' and child.toggleValue ~= nil then values[#values + 1] = child.toggleValue end
		end
	end
	if #values == 0 then return end
	local current = e:_getWorkingValue()
	for k, v in ipairs(values) do if v == current then i = k end end
	apply(e, values[i % #values + 1])
end

function IEXOpt_RowClick(c)
	local r = c == 1 and iexOptRow1 or c == 2 and iexOptRow2 or iexOptRow3
	local x = row(c, r)
	if not x then return end
	local e = x.entry
	O.desc = e
	local k = kindOf(e.widget)
	-- the label shows the description (as under EEex); the widget column acts
	if cellNumber ~= nil and cellNumber ~= 2 then return end
	if k == 'toggle' then clickToggle(e)
	elseif k == 'multi' then clickMulti(e)
	elseif k == 'edit' then
		O.editing = e
		local v = e:_getWorkingValue()
		iexOptEditText = v ~= nil and tostring(v) or ''
		Infinity_PushMenu('IEX_OPTEDIT')
		pcall(IEXOpt_EditLayout)
	elseif k == 'keybind' then
		O.capture = e
	end
end
-- Right click: back to the default value.
function IEXOpt_RowReset(c)
	local r = c == 1 and iexOptRow1 or c == 2 and iexOptRow2 or iexOptRow3
	local x = row(c, r)
	if not x then return end
	local e = x.entry
	O.desc = e
	local k = kindOf(e.widget)
	if k == 'heading' then return end
	apply(e, e:_getDefault())
end

function IEXOpt_EditTitle() return O.editing and tr(O.editing.label) or '' end
function IEXOpt_EditDone(accept)
	local e = O.editing
	O.editing = nil
	Infinity_PopMenu('IEX_OPTEDIT')
	if not (accept and e) then return end
	local old = e:_getWorkingValue()
	local value = iexOptEditText
	if type(old) == 'number' or type(e:_getDefault()) == 'number' then value = tonumber(value) end
	apply(e, value)
end

-- Areas: EEex's panel is 945 x 395 UI units in the middle of the screen.
local function setArea(name, x, y, w, h) pcall(Infinity_SetArea, name, math.floor(x), math.floor(y), math.floor(w), math.floor(h)) end
function IEXOpt_Layout()
	local sw, sh = 1024, 768
	pcall(function() sw, sh = Infinity_GetScreenSize() end)
	local W, H = 945, 395
	local x, y = (sw - W) / 2, (sh - H) / 2
	setArea('IEXOPT_DIM', 0, 0, sw, sh)
	setArea('IEXOPT_PANEL', x, y, W, H)
	setArea('IEXOPT_BT', x, y, W, 2)
	setArea('IEXOPT_BB', x, y + H - 2, W, 2)
	setArea('IEXOPT_BL', x, y, 2, H)
	setArea('IEXOPT_BR', x + W - 2, y, 2, H)
	setArea('IEXOPT_TITLE', x + 10, y + 14, W - 20, 24)
	setArea('IEXOPT_CLOSE', x + W - 34, y + 14, 24, 24)
	setArea('IEXOPT_HSEP', x + 10, y + 45, W - 20, 2)
	setArea('IEXOPT_VSEP1', x + 216, y + 47, 2, H - 57)
	setArea('IEXOPT_VSEP2', x + 669, y + 47, 2, H - 57)
	setArea('IEXOPT_TABS', x + 10, y + 52, 200, H - 62)
	local n = (#O.cols[3] > 0 and 3) or (#O.cols[2] > 0 and 2) or 1
	local cx, cw = x + 224, 440
	for c = 1, 3 do
		if c <= n then
			setArea('IEXOPT_COL' .. c, cx + (c - 1) * cw / n, y + 52, cw / n, H - 62)
		else
			setArea('IEXOPT_COL' .. c, 0, 0, 0, 0)
		end
	end
	setArea('IEXOPT_DESC', x + 680, y + 52, W - 690, H - 62)
end
function IEXOpt_EditLayout()
	local sw, sh = 1024, 768
	pcall(function() sw, sh = Infinity_GetScreenSize() end)
	local W, H = 420, 150
	local x, y = (sw - W) / 2, (sh - H) / 2
	setArea('IEXOPTE_PANEL', x, y, W, H)
	setArea('IEXOPTE_BOX', x, y, W, H)
	setArea('IEXOPTE_TITLE', x + 10, y + 10, W - 20, 26)
	setArea('IEXOPTE_FIELDBG', x + 20, y + 46, W - 40, 30)
	setArea('IEXOPTE_FIELD', x + 26, y + 48, W - 52, 26)
	setArea('IEXOPTE_OK', x + 20, y + 92, 180, 44)
	setArea('IEXOPTE_CANCEL', x + W - 200, y + 92, 180, 44)
end

-----------------------------------------------------------------------
-- Open / close
-----------------------------------------------------------------------

local function onWorld()
	local ok, r = pcall(function() return worldScreen ~= nil and e:GetActiveEngine() == worldScreen end)
	return ok and r
end

local function buildTabList()
	iexOptTabs = {}
	for _, tab in ipairs(IEX_OptionTabs or {}) do
		iexOptTabs[#iexOptTabs + 1] = { label = tab.label, builder = tab.builder, text = tr(tab.label) }
	end
	-- as EEex 1.3.1 lists them: its own general tabs first (Menu, Miscellaneous Keybinds, Modules), then the
	-- others by name ('Module: Attack Info'..., mods' tabs)
	local first = { IEX_OPTIONS_TAB_MENU = 1, IEX_OPTIONS_TAB_KEYS = 2, IEX_OPTIONS_TAB_MODULES = 3 }
	table.sort(iexOptTabs, function(a, b)
		local pa, pb = first[a.label] or 99, first[b.label] or 99
		if pa ~= pb then return pa < pb end
		return tostring(a.text):lower() < tostring(b.text):lower()
	end)
end

function IEXOpt_OnOpen()
	setStrings()
	buildTabList()
	local keep = O.currentTabLabel
	O.currentTab = 0
	for i, tab in ipairs(iexOptTabs) do if tab.label == keep then O.currentTab = i end end
	showTab(O.currentTab)
	-- the game pauses while the screen is up (and goes on when it closes, if it was running)
	O.unpause = false
	if onWorld() then
		local ok, paused = pcall(function() return worldScreen:CheckIfPaused() end)
		if ok and not paused then
			pcall(function() worldScreen:TogglePauseGame(true) end)
			O.unpause = true
		end
	end
end

function IEXOpt_OnClose()
	O.capture = nil
	local tab = iexOptTabs[O.currentTab]
	O.currentTabLabel = tab and tab.label
	if Infinity_IsMenuOnStack('IEX_OPTEDIT') then Infinity_PopMenu('IEX_OPTEDIT') end
	if O.unpause then
		O.unpause = false
		local ok, paused = pcall(function() return worldScreen:CheckIfPaused() end)
		if ok and paused then pcall(function() worldScreen:TogglePauseGame(true) end) end
	end
end

function EEex_Options_Open()
	if not O.loaded then log('EEex_Options_Open: menu file IEXOPT not loaded') return end
	if Infinity_IsMenuOnStack(O.MENU) then return end
	-- pushed over the current menus, as EEex does: popping the ESC menu first left Infinity UI++'s options
	-- background alone on the screen once the options closed (IEX 0.3.0)
	Infinity_PushMenu(O.MENU)
end
function EEex_Options_Close()
	if Infinity_IsMenuOnStack('IEX_OPTEDIT') then Infinity_PopMenu('IEX_OPTEDIT') end
	if Infinity_IsMenuOnStack(O.MENU) then Infinity_PopMenu(O.MENU) end
end

-----------------------------------------------------------------------
-- The game's Options menu (ESC_MENU): a button above Return
-----------------------------------------------------------------------

-- The button's text, with the color code its neighbour's text starts with (Infinity UI++ writes '^$' before its
-- button texts; EEex's button there shows it too).
function IEXOpt_EscText()
	local prefix = ''
	if O.escNeighbor then
		local ok, text = pcall(IEX_MenuVariantText, O.escNeighbor.text.text)
		prefix = ok and type(text) == 'string' and text:match('^%^.') or ''
	end
	return prefix .. tr('IEX_OPTIONS_BUTTON')
end
function IEXOpt_EscClick() EEex_Options_Open() end

local function placeEscButton()
	local b, ret = O.escButton, O.escRet
	if not b or not ret then return end
	local a, r = b.area, ret.area
	if O.escBelow then
		-- under the column's last button, one row step lower (the step between its last two buttons)
		a.x, a.y, a.w, a.h = r.x, r.y + (O.escStep or r.h), r.w, r.h
	else
		a.x, a.y, a.w, a.h = r.x, r.y - r.h - 5, r.w, r.h
	end
end

local function makeButton(menuName, ref)
	local b = EEex_Menu_InjectTemplateInstance(menuName, 'IEXOPT_TEMPLATE_EscButton', 0, 0, 0)
	if not b then return nil end
	pcall(function()
		b.bam.resref = ref.bam.resref
		b.bam.sequence = ref.bam.sequence
		b.pad.x, b.pad.y, b.pad.w, b.pad.h = ref.pad.x, ref.pad.y, ref.pad.w, ref.pad.h
	end)
	b.area.x, b.area.y, b.area.w, b.area.h = 0, 0, 0, 0  -- placed when the menu opens
	return b
end

local function hookOnOpen(menu)
	local prev = EEex_Menu_GetItemFunction(menu.reference_onOpen)
	EEex_Menu_SetItemFunction(menu.reference_onOpen, function(...)
		pcall(placeEscButton)
		if prev then return prev(...) end
	end)
end

-- Infinity UI++: its options column (Gameplay ... UI++ Settings), shown with the ESC menu and in the start
-- screen's options. The button goes under the column's lowest button, with that button's look.
local function injectIntoOptionsBar()
	local bar = EEex_Menu_Find('RG_START_OPTIONS_BAR')
	if not bar then return false end
	local buttons = {}
	local item = bar.items
	while item do
		local okB, isButton = pcall(function() return item.type == 2 end)
		local a = item.area
		if okB and isButton and a.w > 0 and a.h > 0 then buttons[#buttons + 1] = item end
		item = item.next
	end
	local last
	for _, it in ipairs(buttons) do if not last or it.area.y > last.area.y then last = it end end
	if not last then return false end
	local prev
	for _, it in ipairs(buttons) do
		if it ~= last and it.area.x == last.area.x and it.area.y < last.area.y and (not prev or it.area.y > prev.area.y) then
			prev = it
		end
	end
	local b = makeButton('RG_START_OPTIONS_BAR', last)
	if not b then return false end
	O.escButton, O.escRet, O.escNeighbor, O.escBelow = b, last, last, true
	O.escStep = prev and (last.area.y - prev.area.y) or last.area.h
	placeEscButton()
	hookOnOpen(bar)
	return true
end

local function injectEscButton()
	O.escButton, O.escRet, O.escNeighbor, O.escBelow, O.escStep = nil, nil, nil, nil, nil
	if injectIntoOptionsBar() then return end
	local esc = EEex_Menu_Find and EEex_Menu_Find('ESC_MENU')
	if not esc then return end
	local ret = EEex_Options_Private_FindItemByText(esc, getUiString and getUiString('RETURN_GAME_BUTTON') or 'RETURN_GAME_BUTTON')
	if not ret then log('ESC_MENU: no Return button, no options button') return end
	local b = makeButton('ESC_MENU', ret)
	if not b then return end
	O.escButton, O.escRet, O.escNeighbor = b, ret, ret
	hookOnOpen(esc)
end

-- EEex builds a menu per options tab (EEex_Options_Tab1, 2...) once the game state is initialized. The engine keeps
-- its menus in an array sorted by name, so these, named between EEex_Options and ESC_MENU, move ESC_MENU and the
-- menus after it: a menu object a mod took from EEex_Menu_Find while the main file loaded then reads the menu that
-- took its place. SadoEE's ESC button placement depends on it (its free-slot search on that object finds nothing
-- and puts the button right of Return; 2026-10-30 observations with Infinity UI++ and the vanilla UI). IEX adds the
-- same menus (empty: IEX's screen is one menu, IEXOPTT.menu) at the same time, so mods meet the same menus.
local function addTabMenus()
	local ok, found = pcall(EEex_Menu_Find, 'EEex_Options_Tab1')
	if ok and found then return end
	if IEX_MenuLoadFile and not IEX_MenuLoadFile('IEXOPTT') then log('IEXOPTT.MENU not found') end
end

local function onMenusLoaded()
	O.loaded = IEX_MenuLoadFile and IEX_MenuLoadFile('IEXOPT') or false
	if not O.loaded then log('IEXOPT.MENU not found: no options screen') return end
	local ok, err = pcall(injectEscButton)
	if not ok then log('ESC_MENU button: ' .. tostring(err)) end
end

if not O.listenersAdded then
	O.listenersAdded = true
	EEex_Menu_AddMainFileLoadedListener(onMenusLoaded)
	if EEex_Menu_AddAfterMainFileReloadedListener then
		EEex_Menu_AddAfterMainFileReloadedListener(onMenusLoaded)
		EEex_Menu_AddAfterMainFileReloadedListener(addTabMenus)
	end
	EEex_GameState_AddInitializedListener(addTabMenus)
	if EEex_Menu_AddTranslationLoadedListener then EEex_Menu_AddTranslationLoadedListener(setStrings) end
end

-----------------------------------------------------------------------
-- Keys: the options screen's key, a key binding being recorded, key codes shown on demand
-----------------------------------------------------------------------

local MODIFIERS = { 'Left Shift', 'Right Shift', 'Left Ctrl', 'Right Ctrl', 'Left Alt', 'Right Alt' }
local function isModifier(key)
	for _, name in ipairs(MODIFIERS) do
		if EEex_Key_GetFromName and key == EEex_Key_GetFromName(name) then return true end
	end
	return false
end
local function keysMatch(keys, key)
	if type(keys) ~= 'table' or #keys == 0 then return false end
	if keys[#keys] ~= key then return false end
	for i = 1, #keys - 1 do
		if not (EEex_Key_IsDown and EEex_Key_IsDown(keys[i])) then return false end
	end
	return true
end

local function onKey(key)
	if O.capture then
		local e = O.capture
		if EEex_Key_GetFromName and key == EEex_Key_GetFromName('Escape') then O.capture = nil return end
		if isModifier(key) then return end
		local keys = {}
		for _, name in ipairs(MODIFIERS) do
			local code = EEex_Key_GetFromName(name)
			if EEex_Key_IsDown and EEex_Key_IsDown(code) then keys[#keys + 1] = code end
		end
		keys[#keys + 1] = key
		O.capture = nil
		apply(e, keys)
		return
	end
	local openKey = EEex_Options_Get('IEX_Options_OpenKey')
	if openKey and O.loaded and keysMatch(openKey:get(), key) then
		-- not while a text field has the keyboard (the key types a character there)
		if Infinity_IsMenuOnStack('IEX_OPTEDIT') then return end
		if Infinity_IsMenuOnStack(O.MENU) then EEex_Options_Close() else EEex_Options_Open() end
		return
	end
	local echo = EEex_Options_Get('IEX_Options_KeycodeKey')
	if echo and keysMatch(echo:get(), key) then
		O.echoKeys = not O.echoKeys
		if Infinity_DisplayString then Infinity_DisplayString('Key codes: ' .. (O.echoKeys and 'on' or 'off')) end
		return
	end
	if O.echoKeys and Infinity_DisplayString then Infinity_DisplayString('Key code: ' .. tostring(key)) end
end
if not O.keyListener and EEex_Key_AddPressedListener then
	O.keyListener = true
	EEex_Key_AddPressedListener(function(key) local ok, err = pcall(onKey, key) if not ok then log(err) end end)
end

-----------------------------------------------------------------------
-- IEX's own tabs: key bindings, EEex.ini modules, frame rate
-----------------------------------------------------------------------

local function backslash() return EEex_Key_GetFromName and EEex_Key_GetFromName('\\') or 92 end
local function backquote() return EEex_Key_GetFromName and EEex_Key_GetFromName('`') or 96 end

local function registerOwn()
	S.IEX_OPTIONS_TAB_KEYS = 'Miscellaneous Keybinds'
	S.IEX_OPTIONS_OPENKEY = 'Open Options'
	S.IEX_OPTIONS_OPENKEY_DESC = 'Opens and closes this screen. Click the key field, then press the key (with Shift / Ctrl / Alt if wanted); right click: default (\\).'
	S.IEX_OPTIONS_ECHOKEY = 'Toggle Keycode Output'
	S.IEX_OPTIONS_ECHOKEY_DESC = 'Turns on / off the display of the code of every key pressed (to write key bindings by hand).'
	EEex_Options_Register('IEX_Options_OpenKey', EEex_Options_Option.new({
		['default'] = { backslash() },
		['type'] = EEex_Options_KeybindType.new(),
		['accessor'] = EEex_Options_KeybindAccessor.new(),
		['storage'] = EEex_Options_KeybindLuaStorage.new({ ['section'] = 'IEX', ['key'] = 'Options Key' }),
	}))
	EEex_Options_Register('IEX_Options_KeycodeKey', EEex_Options_Option.new({
		['default'] = { backquote() },
		['type'] = EEex_Options_KeybindType.new(),
		['accessor'] = EEex_Options_KeybindAccessor.new(),
		['storage'] = EEex_Options_KeybindLuaStorage.new({ ['section'] = 'IEX', ['key'] = 'Keycode Output Key' }),
	}))
	EEex_Options_AddTab('IEX_OPTIONS_TAB_KEYS', function() return { {
		EEex_Options_DisplayEntry.new({ ['optionID'] = 'IEX_Options_OpenKey', ['label'] = 'IEX_OPTIONS_OPENKEY',
			['description'] = 'IEX_OPTIONS_OPENKEY_DESC', ['widget'] = EEex_Options_KeybindWidget.new() }),
		EEex_Options_DisplayEntry.new({ ['optionID'] = 'IEX_Options_KeycodeKey', ['label'] = 'IEX_OPTIONS_ECHOKEY',
			['description'] = 'IEX_OPTIONS_ECHOKEY_DESC', ['widget'] = EEex_Options_KeybindWidget.new() }),
	} } end)

	-- EEex.ini module switches (read at the next start: requiresRestart). Modules IEX does not have are marked.
	S.IEX_OPTIONS_TAB_MODULES = 'Modules'
	local modules = {
		{ 'B3AttackInfo', 'Attack Info Module', 'Attack Info' },
		{ 'B3EffMen', 'Effect Menu Module', 'Effect Menu' },
		{ 'B3EmptyContainer', 'Empty Container Module', 'Empty Container' },
		{ 'B3Scale', 'Scale Module', 'Scale' },
		{ 'B3TimeStep', 'Time Step Module', 'Time Step' },
		{ 'B3Timer', 'Timer Module', 'Timer' },
	}
	local entries = {}
	for _, m in ipairs(modules) do
		local id = 'IEX_Options_Module_' .. m[1]
		local available = IEX_ModulesAvailable and IEX_ModulesAvailable[m[1]]
		S[id] = 'Enable ' .. m[3] .. ' Module'
		S[id .. '_DESC'] = 'EEex.ini [' .. m[2] .. '] Enable. Read when the game starts.' ..
			(available and '' or ' IEX does not have this module yet: the switch is kept for the mods that set it.')
		EEex_Options_Register(id, EEex_Options_Option.new({
			['default'] = 0,
			['type'] = EEex_Options_ToggleType.new(),
			['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 1 }),
			['storage'] = EEex_Options_NumberINIStorage.new({ ['path'] = 'EEex.ini', ['section'] = m[2], ['key'] = 'Enable' }),
			['requiresRestart'] = true,
		}))
		entries[#entries + 1] = EEex_Options_DisplayEntry.new({ ['optionID'] = id, ['label'] = id,
			['description'] = id .. '_DESC', ['widget'] = EEex_Options_ToggleWidget.new() })
	end
	EEex_Options_AddTab('IEX_OPTIONS_TAB_MODULES', function() return { entries } end)

	-- Frame rate and game speed: EEex's "Uncap FPS" tab (same Baldur.lua keys and labels) plus IEX's own settings
	-- (IEX_FrameRate.lua, docs/FRAMERATE.md).
	if IEX_SetFrameRate then
		S.IEX_OPTIONS_TAB_FPS = 'Uncap FPS'
		local function apply(o, old) if old ~= nil and IEX_ApplyFrameSettings then pcall(IEX_ApplyFrameSettings) end end
		local entries = {}
		local function add(id, label, desc, kind, default, section, key, min, max, onChange)
			S[id] = label
			S[id .. '_DESC'] = desc
			EEex_Options_Register(id, EEex_Options_Option.new({
				['default'] = default,
				['type'] = kind == 'toggle' and EEex_Options_ToggleType.new() or EEex_Options_EditType.new(),
				['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = min, ['max'] = max }),
				['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = section, ['key'] = key }),
				['onChange'] = onChange or apply,
			}))
			entries[#entries + 1] = EEex_Options_DisplayEntry.new({ ['optionID'] = id, ['label'] = id,
				['description'] = id .. '_DESC',
				['widget'] = kind == 'toggle' and EEex_Options_ToggleWidget.new() or EEex_Options_EditWidget.new() })
		end
		-- Stored in [IEX] 'AI Speed', not 'Program Options' 'Maximum Frame Rate': the engine saves the current tick
		-- rate there, mods' changes included (see IEX_PlayerGameSpeed in EEex_TA.lua).
		add('IEX_Options_AISpeed', 'AI Speed', 'Game logic updates per second (default 30). This is the game speed: 60 runs the whole game twice as fast.',
			'edit', 30, 'IEX', 'AI Speed', 1, 240,
			function(o, old) if old ~= nil and IEX_TicksPerSecond then pcall(IEX_TicksPerSecond, o:get()) end end)
		add('IEX_Options_Uncap', 'Enable FPS Uncap', 'Frames are drawn at their own rate (the monitor refresh rate, or the limit below) instead of one per AI update. The game speed does not change.',
			'toggle', 1, 'EEex', 'Uncap FPS', 0, 1)
		add('IEX_Options_LimitOn', 'Enable FPS Limit', 'Caps the frame rate at the FPS Limit below.',
			'toggle', 0, 'EEex', 'Uncap FPS Limit Enabled', 0, 1)
		add('IEX_Options_Limit', 'FPS Limit', 'Highest frame rate when the limit is enabled.',
			'edit', 144, 'EEex', 'Uncap FPS Limit', 1, 1000)
		add('IEX_Options_BusyWait', 'FPS Limit Busy Wait Threshold', 'Milliseconds at the end of each wait spent spinning instead of sleeping: more precise frame pacing for a little more CPU.',
			'edit', 1, 'EEex', 'Uncap FPS Busy Wait Threshold', 0, 10)
		add('IEX_Options_VRR', 'Fullscreen Variable Refresh Rate Hint', 'Saved for EEex compatibility. IEX does not use it yet.',
			'toggle', 0, 'EEex', 'Uncap FPS Fullscreen VRR', 0, 1)
		add('IEX_Options_VSync', 'VSync Enabled', 'Frames wait for the monitor refresh (no tearing). Off with no limit: as many frames as the PC can draw.',
			'toggle', 1, 'EEex', 'VSync Enabled', 0, 1)
		add('IEX_Options_KeepSpeed', 'Keep Game Speed (IEX)', 'Mods that change the AI speed to get more frames (Tweaks Anthology Dynamic FPS: 60 out of combat) get the frames, not a faster game. Off: their change speeds the game up, as under EEex. BuffBot\'s fast mode always speeds the game up.',
			'toggle', 1, 'IEX', 'Keep Game Speed', 0, 1)
		add('IEX_Options_FrameInterpolation', 'Frame Interpolation (IEX)', 'Moving creatures and projectiles are drawn between their positions in the frames between AI updates.',
			'toggle', 1, 'IEX', 'Frame Interpolation', 0, 1)
		add('IEX_Options_FrameRate', 'Frame Rate Override (IEX)', 'Frames per second, used instead of the settings above when not 0 (-1: the monitor refresh rate).',
			'edit', 0, 'IEX', 'Frame Rate', -1, 1000)
		EEex_Options_AddTab('IEX_OPTIONS_TAB_FPS', function() return { entries } end)
	end

	-- Pathfinding Redux, native (IEX_Pathfinding.lua): allies walk through one another.
	if IEX_PathfindingRedux and IEX_PathfindingRedux().installed then
		local state = IEX_PathfindingRedux()
		S.IEX_OPTIONS_TAB_PATH = 'Movement'
		S.IEX_OPTIONS_PATH = 'Allied Pass-Through'
		S.IEX_OPTIONS_PATH_DESC = 'Party members and other allies walk through one another (BG Pathfinding Redux, run by IEX). Walls, doors, neutrals and enemies still block. Default: on when the BG Pathfinding Redux mod is installed.'
		S.IEX_OPTIONS_PATH_COMBAT = 'Only Outside Combat'
		S.IEX_OPTIONS_PATH_COMBAT_DESC = 'Allies block one another again during combat (any loaded area with a battle or damage counter), and pass again 3 seconds of game time after it. Saved in bg-redux-movement.ini.'
		EEex_Options_Register('IEX_Options_PathfindingRedux', EEex_Options_Option.new({
			['default'] = state.modInstalled and 1 or 0,
			['type'] = EEex_Options_ToggleType.new(),
			['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 1 }),
			['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = 'IEX', ['key'] = 'Pathfinding Redux' }),
			['onChange'] = function(o, old) if old ~= nil then pcall(IEX_PathfindingRedux, { enabled = o:get() ~= 0 }) end end,
		}))
		EEex_Options_Register('IEX_Options_PathfindingCombat', EEex_Options_Option.new({
			['default'] = 0,
			['type'] = EEex_Options_ToggleType.new(),
			['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 1 }),
			['storage'] = EEex_Options_NumberINIStorage.new({ ['path'] = 'bg-redux-movement.ini', ['section'] = 'Movement', ['key'] = 'OutOfCombatOnly' }),
			['onChange'] = function(o, old) if old ~= nil then pcall(IEX_PathfindingRedux, { combatOnly = o:get() ~= 0 }) end end,
		}))
		EEex_Options_AddTab('IEX_OPTIONS_TAB_PATH', function() return { {
			EEex_Options_DisplayEntry.new({ ['optionID'] = 'IEX_Options_PathfindingRedux', ['label'] = 'IEX_OPTIONS_PATH',
				['description'] = 'IEX_OPTIONS_PATH_DESC', ['widget'] = EEex_Options_ToggleWidget.new() }),
			EEex_Options_DisplayEntry.new({ ['optionID'] = 'IEX_Options_PathfindingCombat', ['label'] = 'IEX_OPTIONS_PATH_COMBAT',
				['description'] = 'IEX_OPTIONS_PATH_COMBAT_DESC', ['widget'] = EEex_Options_ToggleWidget.new() }),
		} } end)
	end

	-- Engine fixes (src/core/engine_fixes.cpp, docs/ENGINE_FIXES.md): Baldur.lua [IEX] 'Engine Fixes' and
	-- 'Engine Fix <name>', read when the game starts. IEX_ENGINE_FIXES / IEX_ENGINE_FIXES_OFF take precedence.
	if IEX_EngineFixes then
		S.IEX_OPTIONS_TAB_FIXES = 'Engine Fixes'
		local fixes = {
			{ nil, 'Engine Fixes', 'All engine fixes. Off: the game runs with the engine\'s own bugs, as without IEX.' },
			{ 'op182EquippedItem', 'Equipped Item Effects (op182)', 'Apply EFF if item equipped only applies when the item is really equipped.' },
			{ 'weaponSpeed', 'Weapon Speed', 'WSPECIAL.2DA SPEED column applied (High / Grand Mastery speed bonus); ranged attacks use the launcher\'s speed, not the ammo\'s.' },
			{ 'splprotSigned', 'Signed SPLPROT Checks', 'SPLPROT.2DA stat comparisons are signed: negative values compare correctly.' },
			{ 'trapLimit', 'Trap Limit', 'TRAPLIMT.2DA cap respected exactly (no extra trap).' },
			{ 'op33SaveVsDeath', 'Save vs Death (op33)', 'op33 mode 3 changes Save vs Death, not Save vs Wands.' },
			{ 'immunityMessages', 'Immunity Messages (op206/232/256)', 'Spell immunity strings and "cannot cast multiple instances" messages show.' },
			{ 'hpTableModifier', 'HP Table Modifier', 'HP tables add their static modifier when a die roll is set.' },
			{ 'simulacrumLevelDrain', 'Simulacrum Level Drain', 'Simulacrum level drain uses the average level of dual- and multi-classes.' },
			{ 'negativeXPFeedback', 'Negative XP Message', 'AddXPObject with a negative value shows "The Party Has Lost Experience".' },
			{ 'xpFloor', 'XP Floor', 'XP never goes below 0 (no wrap to the maximum).' },
			{ 'eventTriggerObjects', 'Event Trigger Objects', 'Event triggers such as AttackedBy(PartySlot1,DEFAULT) follow whoever the object names now.' },
		}
		local entries = {}
		for i, f in ipairs(fixes) do
			local id = 'IEX_Options_Fix' .. i
			local key = f[1] and ('Engine Fix ' .. f[1]) or 'Engine Fixes'
			S[id] = f[2]
			S[id .. '_DESC'] = f[3] .. ' Baldur.lua [IEX] \'' .. key .. '\'. Default: on.'
			EEex_Options_Register(id, EEex_Options_Option.new({
				['default'] = 1,
				['type'] = EEex_Options_ToggleType.new(),
				['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 1 }),
				['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = 'IEX', ['key'] = key }),
				['requiresRestart'] = true,
			}))
			entries[#entries + 1] = EEex_Options_DisplayEntry.new({ ['optionID'] = id, ['label'] = id,
				['description'] = id .. '_DESC', ['widget'] = EEex_Options_ToggleWidget.new() })
		end
		EEex_Options_AddTab('IEX_OPTIONS_TAB_FIXES', function() return { entries } end)
	end
end
local ok, err = pcall(registerOwn)
if not ok then log('own tabs: ' .. tostring(err)) end
