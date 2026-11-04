-- EEex-compatible options API (data side): option objects with a default, an accessor (where the live value is
-- kept, with validation such as clamping), a storage (where it is saved) and a working value (what the options
-- screen edits), plus the tabs, display entries and widgets mods describe for the options screen.
-- Shapes follow what EEex 1.3.1 exposes at run time (tools/difftest, 2026-10-29: class method names, instance
-- fields, storage call shapes read(option) / write(option, value), canReadEarly()); the code is IEX's own.
-- The screen itself: EEex_OptionsUI.lua.

-- A class: `new(o)` makes an instance and runs `_init`; `parent` gives inheritance through __index.
local function class(parent)
	local c = {}
	c.__index = c
	if parent then setmetatable(c, parent) end
	c.new = function(o)
		o = setmetatable(o or {}, c)
		if o._init then o:_init() end
		return o
	end
	return c
end
IEX_OptionsClass = class

local function log(msg)
	if IEX_Log then pcall(IEX_Log, '[Options] ' .. tostring(msg)) end
end

-----------------------------------------------------------------------
-- Types (what the value is; the widget decides how it is shown)
-----------------------------------------------------------------------

EEex_Options_Type = class()
function EEex_Options_Type:_init() end
EEex_Options_ToggleType = class(EEex_Options_Type)
EEex_Options_EditType = class(EEex_Options_Type)
EEex_Options_KeybindType = class(EEex_Options_Type)
function EEex_Options_KeybindType:_init() end

-----------------------------------------------------------------------
-- Accessors: get(option) / set(option, value) the live value, validate(option, value) -> value
-----------------------------------------------------------------------

EEex_Options_Accessor = class()
function EEex_Options_Accessor:_init() end
function EEex_Options_Accessor:validate(option, value) return value end

-- The live value kept in the option itself.
EEex_Options_PrivateAccessor = class(EEex_Options_Accessor)
-- (kept in the accessor instance: an option's own fields stay the ones EEex has)
function EEex_Options_PrivateAccessor:get(option) return self._value end
function EEex_Options_PrivateAccessor:set(option, value) self._value = value end

-- The live value kept in a global variable (`name`).
EEex_Options_GlobalAccessor = class(EEex_Options_Accessor)
function EEex_Options_GlobalAccessor:get(option) return _G[self.name] end
function EEex_Options_GlobalAccessor:set(option, value) _G[self.name] = value end

-- A number kept between min and max (private value).
EEex_Options_ClampedAccessor = class(EEex_Options_Accessor)
function EEex_Options_ClampedAccessor:_init() end
function EEex_Options_ClampedAccessor:clamp(value)
	value = tonumber(value) or self.min or 0
	if self.min and value < self.min then value = self.min end
	if self.max and value > self.max then value = self.max end
	return value
end
function EEex_Options_ClampedAccessor:validate(option, value)
	-- validate(value) (one argument) is accepted too
	if value == nil and type(option) ~= 'table' then value = option end
	return self:clamp(value)
end
EEex_Options_ClampedAccessor.get = EEex_Options_PrivateAccessor.get
EEex_Options_ClampedAccessor.set = EEex_Options_PrivateAccessor.set

-- A key binding (list of keys) kept in the option.
EEex_Options_KeybindAccessor = class(EEex_Options_Accessor)
EEex_Options_KeybindAccessor.get = EEex_Options_PrivateAccessor.get
EEex_Options_KeybindAccessor.set = EEex_Options_PrivateAccessor.set

-----------------------------------------------------------------------
-- Storages: read(option) -> value or nil (nil: not saved yet, the default applies), write(option, value).
-- canReadEarly(): true when the value can be read before the game's own settings are loaded.
-----------------------------------------------------------------------

EEex_Options_Private_Storage = class()
function EEex_Options_Private_Storage:canReadEarly() return false end

-- Values saved in the game's INI (Baldur.lua, [section] key) through the engine.
EEex_Options_Private_LuaStorage = class(EEex_Options_Private_Storage)
function EEex_Options_Private_LuaStorage:_init() end
-- Text written into Baldur.lua (which the engine runs as Lua): quotes, backslashes and line breaks escaped.
function EEex_Options_Private_LuaStorage:_escape(s)
	return (tostring(s):gsub('[\\\'"\n\r]', { ['\\'] = '\\\\', ["'"] = "\\'", ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r' }))
end
-- The engine reads Baldur.lua back as Lua: the text comes back unescaped already.
function EEex_Options_Private_LuaStorage:_unescape(s) return s end

local ABSENT_A, ABSENT_B = -2147483647, -2147483646
local ABSENT_S = '\1IEX absent\1'
-- Raw text of [section] key, or nil when the key is absent. The engine gives 0 for an absent key read with a nil or
-- string default, so absence is told by reading with two different number defaults when the text API is missing.
local function readRaw(section, key)
	if Infinity_GetINIString then
		local okS, raw = pcall(Infinity_GetINIString, section, key, ABSENT_S)
		if okS and type(raw) == 'string' then
			if raw == ABSENT_S then return nil end
			return raw
		end
	end
	local ok, value = pcall(Infinity_GetINIValue, section, key, ABSENT_A)
	value = ok and tonumber(value) or nil
	if value == ABSENT_A then
		local ok2, other = pcall(Infinity_GetINIValue, section, key, ABSENT_B)
		if ok2 and tonumber(other) == ABSENT_B then return nil end
	end
	return value ~= nil and tostring(value) or nil
end
function EEex_Options_Private_LuaStorage:read(option)
	local raw = readRaw(self.section, self.key)
	return raw ~= nil and self:_unescape(raw) or nil
end
function EEex_Options_Private_LuaStorage:write(option, value)
	if value == nil and type(option) ~= 'table' then value = option end  -- write(value) accepted too
	pcall(Infinity_SetINIValue, self.section, self.key, type(value) == 'string' and self:_escape(value) or value)
end

-- A number in Baldur.lua. A stored value that is not a number reads as absent (the default applies, as under EEex).
EEex_Options_NumberLuaStorage = class(EEex_Options_Private_LuaStorage)
function EEex_Options_NumberLuaStorage:read(option)
	local raw = readRaw(self.section, self.key)
	return raw ~= nil and tonumber(raw) or nil
end

-- A string in Baldur.lua.
EEex_Options_StringLuaStorage = class(EEex_Options_Private_LuaStorage)
function EEex_Options_StringLuaStorage:read(option)
	local raw = readRaw(self.section, self.key)
	return raw ~= nil and self:_unescape(raw) or nil
end

-- A key binding in Baldur.lua, as text (EEex_Options_MarshalKeybind).
EEex_Options_KeybindLuaStorage = class(EEex_Options_Private_LuaStorage)
function EEex_Options_KeybindLuaStorage:read(option)
	local raw = readRaw(self.section, self.key)
	if raw == nil then return nil end
	return EEex_Options_UnmarshalKeybind(raw)
end
function EEex_Options_KeybindLuaStorage:write(option, value)
	if value == nil and type(option) ~= 'table' then value = option end
	pcall(Infinity_SetINIValue, self.section, self.key, self:_escape(EEex_Options_MarshalKeybind(value)))
end

-- Values in an INI file of the game folder (`path`, default EEex.ini: EEex keeps its module switches there),
-- readable before the game's own settings: canReadEarly() is true.
EEex_Options_Private_INIStorage = class(EEex_Options_Private_Storage)
function EEex_Options_Private_INIStorage:_init()
	self.path = self.path or self.file or 'EEex.ini'
end
function EEex_Options_Private_INIStorage:canReadEarly() return true end
local function iniRead(self)
	if not IEX_ReadINIFile then return nil end
	local ok, v = pcall(IEX_ReadINIFile, self.path or 'EEex.ini', self.section, self.key)
	return ok and v or nil
end
function EEex_Options_Private_INIStorage:write(option, value)
	if value == nil and type(option) ~= 'table' then value = option end
	if IEX_WriteINIFile then pcall(IEX_WriteINIFile, self.path or 'EEex.ini', self.section, self.key, tostring(value)) end
end
EEex_Options_NumberINIStorage = class(EEex_Options_Private_INIStorage)
function EEex_Options_NumberINIStorage:read(option) local v = iniRead(self) return v ~= nil and tonumber(v) or nil end
EEex_Options_StringINIStorage = class(EEex_Options_Private_INIStorage)
function EEex_Options_StringINIStorage:read(option) return iniRead(self) end

-- Key bindings as text: key codes joined by '+' (modifiers first, in the order pressed).
function EEex_Options_MarshalKeybind(keys)
	if type(keys) ~= 'table' then return tostring(keys or '') end
	local parts = {}
	for i, k in ipairs(keys) do parts[i] = tostring(k) end
	return table.concat(parts, '+')
end
function EEex_Options_UnmarshalKeybind(text)
	local keys = {}
	for part in tostring(text or ''):gmatch('[^+]+') do keys[#keys + 1] = tonumber(part) or part end
	return keys
end

-----------------------------------------------------------------------
-- Options
-----------------------------------------------------------------------

-- Per-option state IEX keeps outside the option (its fields stay EEex's): registration id, value read yet.
local optionIds = setmetatable({}, { __mode = 'k' })
local optionLoaded = setmetatable({}, { __mode = 'k' })
local function idOf(option) return tostring(optionIds[option]) end

-- Instance fields (EEex's): default, type, accessor, storage, onChange(option, oldValue), requiresRestart,
-- _workingValue (what the screen shows / edits), _displayEntries (the screen rows bound to it).
EEex_Options_Option = class()
function EEex_Options_Option:_init()
	if self.accessor == nil then self.accessor = EEex_Options_PrivateAccessor.new() end
	if self.requiresRestart == nil then self.requiresRestart = false end
	self._displayEntries = self._displayEntries or {}
end
function EEex_Options_Option:_getDefault() return self.default end
function EEex_Options_Option:getDefault() return self.default end
function EEex_Options_Option:_canReadEarly()
	return self.storage ~= nil and type(self.storage.canReadEarly) == 'function' and self.storage:canReadEarly() or false
end
local function validate(self, value)
	local a = self.accessor
	if a and a.validate then
		local ok, v = pcall(a.validate, a, self, value)
		if ok and v ~= nil then return v end
	end
	return value
end
-- The stored value (validated), or nil when nothing is saved.
function EEex_Options_Option:_read()
	if not self.storage or type(self.storage.read) ~= 'function' then return nil end
	local ok, v = pcall(self.storage.read, self.storage, self)
	if not ok then log('read ' .. idOf(self) .. ': ' .. tostring(v)) return nil end
	if v == nil then return nil end
	return validate(self, v)
end
function EEex_Options_Option:_write()
	if self.storage and type(self.storage.write) == 'function' then
		local ok, err = pcall(self.storage.write, self.storage, self, self:_get())
		if not ok then log('write ' .. idOf(self) .. ': ' .. tostring(err)) end
	end
end
-- The live value; read from storage the first time (the default when nothing is saved).
function EEex_Options_Option:_get()
	if not optionLoaded[self] then
		optionLoaded[self] = true
		local v = self:_read()
		if v == nil then v = validate(self, self.default) end
		self.accessor:set(self, v)
		self._workingValue = v
	end
	return self.accessor:get(self)
end
function EEex_Options_Option:get() return self:_get() end
-- Sets the live value. noWrite: do not save it (the value was just read from storage). onChange(option, old)
-- runs when the value changes.
function EEex_Options_Option:_set(value, noWrite)
	value = validate(self, value)
	local old = self:_get()
	self.accessor:set(self, value)
	self:_setWorkingValue(value, false)
	if not noWrite then self:_write() end
	if old ~= value and type(self.onChange) == 'function' then
		local ok, err = pcall(self.onChange, self, old)
		if not ok then log('onChange ' .. idOf(self) .. ': ' .. tostring(err)) end
	end
	return value
end
function EEex_Options_Option:set(value) return self:_set(value) end
function EEex_Options_Option:_getWorkingValue()
	if self._workingValue == nil then self._workingValue = self:_get() end
	return self._workingValue
end
-- The value the screen shows; display entries bound to this option are told (their widgets redraw).
function EEex_Options_Option:_setWorkingValue(value, needCopy)
	if needCopy and type(value) == 'table' then
		local copy = {}
		for k, v in pairs(value) do copy[k] = v end
		value = copy
	end
	self._workingValue = value
	for _, entry in ipairs(self._displayEntries or {}) do
		if entry._onWorkingValueChanged then pcall(entry._onWorkingValueChanged, entry, value) end
	end
	return value
end

IEX_Options = IEX_Options or {}
IEX_OptionTabs = IEX_OptionTabs or {}

-- Registering reads the stored value now and calls onChange(option, nil) once, as EEex does (SadoEE's switches
-- copy their value into the feature's field there). A second registration under the same id replaces the first
-- (as under EEex: difftest opt.registerTwice).
function EEex_Options_Register(id, option)
	IEX_Options[id] = option
	if type(option) == 'table' then
		optionIds[option] = id
		if type(option.get) == 'function' then pcall(option.get, option) end
		if type(option.onChange) == 'function' then
			local ok, err = pcall(option.onChange, option, nil)
			if not ok then log('EEex_Options_Register ' .. tostring(id) .. ' onChange: ' .. tostring(err)) end
		end
	end
	return option
end

function EEex_Options_Get(id)
	return IEX_Options[id]
end

-- Changes an option's value (nil = its default). Returns the new value, or nil when no option has that id.
function EEex_Options_Set(id, value)
	local option = IEX_Options[id]
	if not option then return nil end
	if value == nil then value = option.default end
	if type(option.set) == 'function' then option:set(value) else option.value = value end
	return type(option.get) == 'function' and option:get() or option.value
end

-- label: uiStrings key of the tab name; builder() returns the tab's columns (each a list of display entries)
-- when the screen opens.
function EEex_Options_AddTab(label, builder)
	for _, tab in ipairs(IEX_OptionTabs) do
		if tab.label == label then tab.builder = builder return end
	end
	IEX_OptionTabs[#IEX_OptionTabs + 1] = { label = label, builder = builder }
end

-----------------------------------------------------------------------
-- Display entries and widgets (one row of the options screen)
-----------------------------------------------------------------------

-- Fields: optionID, label / description (uiStrings keys), widget, subOptions (indented entries below it).
EEex_Options_DisplayEntry = class()
function EEex_Options_DisplayEntry:_init()
	if self.widget then
		pcall(function() self.widget._displayEntry = self end)
		if type(self.widget._init) == 'function' and not self.widget._initDone then
			self.widget._initDone = true
			pcall(self.widget._init, self.widget)
		end
	end
	local option = self.optionID and IEX_Options[self.optionID]
	if option then self:_bind(option) end
end
function EEex_Options_DisplayEntry:_bind(option)
	self._option = option
	option._displayEntries = option._displayEntries or {}
	for _, e in ipairs(option._displayEntries) do if e == self then return end end
	option._displayEntries[#option._displayEntries + 1] = self
end
function EEex_Options_DisplayEntry:_getOption()
	if not self._option and self.optionID and IEX_Options[self.optionID] then self:_bind(IEX_Options[self.optionID]) end
	return self._option
end
function EEex_Options_DisplayEntry:_getDefault()
	local o = self:_getOption()
	return o and o:_getDefault()
end
function EEex_Options_DisplayEntry:_getWorkingValue()
	local o = self:_getOption()
	return o and o:_getWorkingValue()
end
function EEex_Options_DisplayEntry:_setWorkingValue(value, needCopy)
	local o = self:_getOption()
	if not o then return value end
	return o:_setWorkingValue(value, needCopy)
end
-- Applies a value from the screen: the option's live value and storage.
function EEex_Options_DisplayEntry:_set(value)
	local o = self:_getOption()
	if not o then return value end
	return o:_set(value)
end
function EEex_Options_DisplayEntry:_onWorkingValueChanged(value)
	local w = self.widget
	if w and type(w._onWorkingValueChanged) == 'function' then pcall(w._onWorkingValueChanged, w, value) end
end

-- Widgets: _buildLayout (rows for the screen), _onShowBeforeLayout / _onShowAfterLayout (screen opening),
-- _onWorkingValueChanged(value), _onMap. The base widget draws nothing: its entry is a heading.
EEex_Options_Widget = class()
function EEex_Options_Widget:_init() end
function EEex_Options_Widget:_buildLayout() return nil end
function EEex_Options_Widget:_onMap() end
function EEex_Options_Widget:_onShowBeforeLayout() end
function EEex_Options_Widget:_onShowAfterLayout() end
function EEex_Options_Widget:_onWorkingValueChanged(value) end
function EEex_Options_Widget:_kind() return 'heading' end

-- A switch. toggleValue: the value this switch stands for (radio groups: several switches on one option, with
-- disallowToggleOff); toggleState: shown on/off; toggleWarning(): called on a click, returning true cancels it.
EEex_Options_ToggleWidget = class(EEex_Options_Widget)
function EEex_Options_ToggleWidget:_init()
	if self.toggleState == nil then self.toggleState = false end
end
function EEex_Options_ToggleWidget:_kind() return 'toggle' end
function EEex_Options_ToggleWidget:_buildLayout() return 'toggle' end
local function toggleOn(self, value)
	if self.toggleValue ~= nil then return value == self.toggleValue end
	return value ~= nil and value ~= 0 and value ~= false
end
function EEex_Options_ToggleWidget:_onShowBeforeLayout()
	local e = self._displayEntry
	if e then self.toggleState = toggleOn(self, e:_getWorkingValue()) end
end
function EEex_Options_ToggleWidget:_onWorkingValueChanged(value)
	self.toggleState = toggleOn(self, value)
end
-- A click: the new value of the option, or nil when nothing changes.
function EEex_Options_ToggleWidget:_clickValue()
	local e = self._displayEntry
	local current = e and e:_getWorkingValue()
	if self.toggleValue ~= nil then
		if current == self.toggleValue then
			if self.disallowToggleOff then return nil end
			local d = e and e:_getDefault()
			return (d ~= nil and d ~= self.toggleValue) and d or 0
		end
		return self.toggleValue
	end
	local on = toggleOn(self, current)
	if on and self.disallowToggleOff then return nil end
	return on and 0 or 1
end

-- A widget made of child widgets (iterated by _getChildWidgetsItr).
EEex_Options_ParentWidget = class(EEex_Options_Widget)
function EEex_Options_ParentWidget:_getChildWidgetsItr()
	local list, i = self.widgets or self.children or {}, 0
	return function() i = i + 1 return list[i] end
end
-- Several switches side by side on one option (each child a ToggleWidget with its toggleValue).
EEex_Options_HorizontalMultiToggleWidget = class(EEex_Options_ParentWidget)
function EEex_Options_HorizontalMultiToggleWidget:_init() end
function EEex_Options_HorizontalMultiToggleWidget:_kind() return 'multi' end
function EEex_Options_HorizontalMultiToggleWidget:_buildLayout() return 'multi' end

-- A text field (EditType options).
EEex_Options_EditWidget = class(EEex_Options_Widget)
function EEex_Options_EditWidget:_kind() return 'edit' end
function EEex_Options_EditWidget:_buildLayout() return 'edit' end
-- A key binding: click, then press the keys.
EEex_Options_KeybindWidget = class(EEex_Options_Widget)
function EEex_Options_KeybindWidget:_kind() return 'keybind' end
function EEex_Options_KeybindWidget:_buildLayout() return 'keybind' end

-- The options screen: EEex_OptionsUI.lua replaces these once its menu is loaded.
-- The menu has EEex's name (EEex_Options), so mods testing Infinity_IsMenuOnStack('EEex_Options') see it.
IEX_OptionsMenuName = IEX_OptionsMenuName or 'EEex_Options'
function EEex_Options_Open() end
function EEex_Options_Close()
	if Infinity_IsMenuOnStack and Infinity_IsMenuOnStack(IEX_OptionsMenuName) then
		Infinity_PopMenu(IEX_OptionsMenuName)
	end
end
