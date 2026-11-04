-- Missing EEex API trap: reading an EEex_* global that EEex defines (IEX_EEexNames, observed by the differential
-- test) but IEX does not provide yet returns a stand-in instead of nil. The stand-in can be called, indexed and
-- iterated (it does nothing and returns nil), so a mod keeps loading instead of stopping on an error popup.
-- Names EEex does not define either read as nil, as under EEex (`if EEex_Something then` tests agree).
-- Every missing name is recorded once in IEX.log and in IEX/missing_api.txt (name, first caller).

IEX_MissingApi = IEX_MissingApi or {}
IEX_MissingApiOrder = IEX_MissingApiOrder or {}

local function caller()
	local info = debug and debug.getinfo and debug.getinfo(4, 'Sl')
	return info and (tostring(info.short_src) .. ':' .. tostring(info.currentline)) or '?'
end

local function record(name)
	if IEX_MissingApi[name] then return end
	local where = caller()
	IEX_MissingApi[name] = where
	IEX_MissingApiOrder[#IEX_MissingApiOrder + 1] = name
	IEX_Log('Missing EEex API: ' .. name .. ' (first use ' .. where .. ')')
	if IEX_WriteFile then
		local lines = {}
		for _, n in ipairs(IEX_MissingApiOrder) do lines[#lines + 1] = n .. '\t' .. IEX_MissingApi[n] end
		IEX_WriteFile('missing_api.txt', table.concat(lines, '\n') .. '\n')
	end
end

-- Other unsupported requests (lua/IEX_HookRequests.lua: engine patch sites IEX has no native point for).
function IEX_RecordMissing(name, where)
	if IEX_MissingApi[name] then return end
	IEX_MissingApi[name] = where or '?'
	IEX_MissingApiOrder[#IEX_MissingApiOrder + 1] = name
	if IEX_WriteFile then
		local lines = {}
		for _, n in ipairs(IEX_MissingApiOrder) do lines[#lines + 1] = n .. '\t' .. IEX_MissingApi[n] end
		IEX_WriteFile('missing_api.txt', table.concat(lines, '\n') .. '\n')
	end
end

-- One stand-in per name: callable, indexable (sub-tables like EEex_Actionbar_ButtonType.X), iterable.
local standIns = {}
local function standIn(name)
	local s = standIns[name]
	if s then return s end
	s = setmetatable({}, {
		__call = function() return nil end,
		__index = function(_, key) record(name .. '.' .. tostring(key)) return nil end,
		__tostring = function() return 'IEX missing ' .. name end,
	})
	standIns[name] = s
	return s
end

-- Puts the trap in front of a metatable's __index (keeping whatever lookup it had).
local function addTrap(mt)
	local previousIndex = mt.__index
	mt.__index = function(t, key)
		if type(key) == 'string' and key:sub(1, 5) == 'EEex_' then
			record(key)
			if not IEX_EEexNames or IEX_EEexNames[key] then return standIn(key) end
			return nil
		end
		if type(previousIndex) == 'function' then return previousIndex(t, key) end
		if type(previousIndex) == 'table' then return previousIndex[key] end
		return nil
	end
	return mt
end

local rawSetmetatable = setmetatable
local function install()
	local mt = getmetatable(_G)
	if mt and mt.__iexTrap then return end
	mt = addTrap(mt or {})
	mt.__iexTrap = true
	rawSetmetatable(_G, mt)
end
install()

-- The engine can replace or drop _G's metatable outside Lua: IEX_Dispatch calls this before every event.
IEX_EnsureMissingTrap = install

-- Mods (and the UI) may install their own metatable on _G later: keep the trap in front of it.
setmetatable = function(t, mt)
	if t == _G and type(mt) == 'table' then addTrap(mt) mt.__iexTrap = true end
	return rawSetmetatable(t, mt)
end
