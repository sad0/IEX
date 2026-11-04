-- EEex-compatible keybinds (public documentation of EEex_Keybinds_*): a keybind is a key sequence pressed in order
-- while modifier keys are held; its callback fires when the sequence is satisfied (fireType DOWN) or when a key is
-- released after that (fireType UP; another key press first cancels it). Built on the key pressed / released
-- listeners. Definitions are kept in EEex_Keybinds_Private_Definitions[id] (mods read and clear it).

EEex_Keybinds_FireType = EEex_Keybinds_FireType or { DOWN = false, UP = true }
EEex_Keybinds_Private_Definitions = EEex_Keybinds_Private_Definitions or {}

local held = {}
local state = {}  -- id -> { progress = n, satisfied = bool }

local function stateOf(id)
	local s = state[id]
	if not s then
		s = { progress = 0, satisfied = false }
		state[id] = s
	end
	return s
end

local function contains(list, key)
	for _, k in ipairs(list or {}) do if k == key then return true end end
	return false
end

local function modifiersHeld(def)
	for _, k in ipairs(def.modifierKeys or {}) do if not held[k] then return false end end
	return true
end

local function call(fn, id)
	if type(fn) ~= 'function' then return end
	local ok, err = pcall(fn, id)
	if not ok then IEX_Log('EEex_Keybinds: ' .. tostring(id) .. ': ' .. tostring(err)) end
end

local function unsatisfy(id, def, s)
	if s.satisfied then
		s.satisfied = false
		call(def.onUnsatisfied, id)
	end
end

local function onPressed(key)
	if held[key] then return end  -- key repeat
	held[key] = true
	for id, def in pairs(EEex_Keybinds_Private_Definitions) do
		local keys = def.keys
		if type(keys) == 'table' and #keys > 0 and not contains(def.modifierKeys, key) then
			local s = stateOf(id)
			if s.satisfied then
				-- a further key press cancels a satisfied keybind
				if not def.allowOtherKeys then
					unsatisfy(id, def, s)
					s.progress = 0
				end
			elseif keys[s.progress + 1] == key then
				s.progress = s.progress + 1
			elseif not def.allowOtherKeys then
				s.progress = keys[1] == key and 1 or 0
			end
			if not s.satisfied and s.progress == #keys and modifiersHeld(def) then
				s.satisfied = true
				call(def.onSatisfied, id)
				if def.fireType == EEex_Keybinds_FireType.DOWN then call(def.callback, id) end
			end
		end
	end
end

local function onReleased(key)
	held[key] = nil
	for id, def in pairs(EEex_Keybinds_Private_Definitions) do
		local s = state[id]
		if s and s.satisfied then
			if def.fireType ~= EEex_Keybinds_FireType.DOWN then call(def.callback, id) end
			unsatisfy(id, def, s)
			s.progress = 0
		elseif s and contains(def.keys, key) then
			s.progress = 0
		end
	end
end

local listening = false
local function listen()
	if listening then return end
	listening = true
	EEex_Key_AddPressedListener(onPressed)
	EEex_Key_AddReleasedListener(onReleased)
end

-- The keybind table of `id`, nil when there is none.
function EEex_Keybinds_Get(id)
	return EEex_Keybinds_Private_Definitions[id]
end

-- Creates or updates keybind `id` with the fields of `args` (keys, modifierKeys, fireType, callback,
-- allowOtherKeys, onSatisfied, onUnsatisfied).
function EEex_Keybinds_Update(id, args)
	local def = EEex_Keybinds_Private_Definitions[id]
	if not def then
		def = { keys = {}, modifierKeys = {}, fireType = EEex_Keybinds_FireType.UP, allowOtherKeys = false,
			onSatisfied = function() end, onUnsatisfied = function() end }
		EEex_Keybinds_Private_Definitions[id] = def
	end
	for k, v in pairs(args or {}) do def[k] = v end
	state[id] = nil
	listen()
end

-- Clears the progress of keybind `id` (it is no longer satisfied).
function EEex_Keybinds_Reset(id)
	local s, def = state[id], EEex_Keybinds_Private_Definitions[id]
	if s and def then unsatisfy(id, def, s) end
	state[id] = nil
end

-- True while keybind `id` is satisfied.
function EEex_Keybinds_IsSatisfied(id)
	local s = state[id]
	return s ~= nil and s.satisfied
end

IEX_AddListener('GameStateDestroyed', function() held = {} state = {} end)
