--[[
IEX differential test probe (tools/difftest). Our own code: it calls the EEex API surface with fixed arguments on
deterministic targets and writes one JSON line per case, so the same file run under real EEex and under IEX can be
diffed (tools/difftest/compare.py).

Flow (no input needed):
  M_ load: register listeners only (no engine UI call here: that crashed EEex before).
  Main file loaded: load DIFFT.menu, wrap two per-frame UI functions of the start / load screens.
  Start screen: open the load screen, then load the save whose name contains DiffT.SAVE.
  World (GameStateInitialized + area visible + a short delay): run the cases, then trigger events (select
  portraits, queue an action), record the listener calls, write everything, write DONE in the status file.
Output: <game dir>/difftest_out.txt (io library) and difftest_status.txt.
--]]

DiffT = DiffT or {}
local DT = DiffT
DT.SAVE = DT.SAVE or 'DIFFTEST'
DT.OUT = 'difftest_out.txt'
DT.STATUS = 'difftest_status.txt'
DT.lines = DT.lines or {}
DT.events = DT.events or {}
DT.eventCounts = DT.eventCounts or {}
DT.phase = 'mload'
DT.seq = 0

-----------------------------------------------------------------------
-- Canonical serialization (JSON)
-----------------------------------------------------------------------

local function scrub(s)
	s = tostring(s)
	s = s:gsub('0[xX]%x+', '<p>')
	s = s:gsub('%x%x%x%x%x%x%x%x+', '<p>')
	return s
end
DT.scrub = scrub

local function jstr(s)
	s = tostring(s)
	s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
	s = s:gsub('[%z\1-\31\127-\255]', function(c) return string.format('\\u%04x', c:byte()) end)
	return '"' .. s .. '"'
end

local function num(v)
	if v ~= v then return '"NaN"' end
	if v == math.huge then return '"inf"' end
	if v == -math.huge then return '"-inf"' end
	if v == math.floor(v) and math.abs(v) < 2^53 then return string.format('%.0f', v) end
	return string.format('%.6g', v)
end

local ser
local function udDesc(v)
	return '{"__ud":' .. jstr(scrub(v)) .. '}'
end

ser = function(v, depth, seen)
	depth = depth or 0
	local t = type(v)
	if t == 'nil' then return 'null'
	elseif t == 'boolean' then return v and 'true' or 'false'
	elseif t == 'number' then return num(v)
	elseif t == 'string' then return jstr(v)
	elseif t == 'function' then return '"<function>"'
	elseif t == 'thread' then return '"<thread>"'
	elseif t == 'userdata' then return udDesc(v)
	elseif t == 'table' then
		seen = seen or {}
		if seen[v] then return '"<cycle>"' end
		if depth >= 4 then return '"<table>"' end
		seen[v] = true
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			if ta == 'number' or ta == 'string' then return a < b end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for i, k in ipairs(keys) do
			if i > 200 then parts[#parts + 1] = '"...":' .. num(#keys) break end
			local ks = type(k) == 'string' and k or ('#' .. scrub(k))
			parts[#parts + 1] = jstr(ks) .. ':' .. ser(v[k], depth + 1, seen)
		end
		seen[v] = nil
		return '{' .. table.concat(parts, ',') .. '}'
	end
	return jstr('<' .. t .. '>')
end
DT.ser = ser

local function errText(e)
	local s = tostring(e)
	for _ = 1, 4 do s = s:gsub('^[^:\n]-:%d+: ', '') end
	s = scrub(s):gsub('%s+', ' ')
	return 'ERROR:' .. s:sub(1, 90)
end

-----------------------------------------------------------------------
-- Output
-----------------------------------------------------------------------

-- The output channel is not under test: io when the Lua has it, IEX_WriteFile (IEX/<name>) otherwise,
-- print (InfinityLoader's log file) as the last resort.
local function writeFile(name, text)
	if not (io and io.open) then
		if IEX_WriteFile then IEX_WriteFile(name, text) return true end
		return false
	end
	local f = io.open(name, 'w')
	if not f then return false end
	f:write(text)
	f:close()
	return true
end

function DT.status(s)
	DT.lastStatus = s
	if IEX_Log then pcall(IEX_Log, '[DIFFT] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, DT.STATUS, s .. '\n')
	if not (ok and wrote) then print('DIFFT|STATUS ' .. tostring(s)) end
end

function DT.flush()
	local ok, wrote = pcall(writeFile, DT.OUT, table.concat(DT.lines, '\n') .. '\n')
	if not (ok and wrote) then
		-- Fallback: the log (print) with a prefix the runner can grep.
		-- long lines go out in pieces (InfinityLoader's print crashed the engine on a very long line, 2026-10-29)
		for i = (DT.printed or 0) + 1, #DT.lines do
			local line = DT.lines[i]
			print('DIFFT|' .. line:sub(1, 1000))
			for p = 1001, #line, 1000 do print('DIFFT~|' .. line:sub(p, p + 999)) end
		end
		DT.printed = #DT.lines
	end
end

local function emit(name, body)
	DT.lines[#DT.lines + 1] = '{"case":' .. jstr(name) .. ',' .. body .. '}'
end

-- One case: name + function; all its results are recorded, or the error.
local unpackAll = unpack or table.unpack

-- Cases that pass bad arguments (out-of-range ids, missing resources, nil objects) can crash the engine
-- natively under EEex, which pcall cannot catch. They run last, one by one, with the output flushed and a
-- TRACE line printed before each, so a crash loses nothing but that case; run.ps1 then adds it to skip.txt.
DT.deferred = DT.deferred or {}
-- No file channel (print only, EEex): every case is traced, so a native crash names its case.
DT.traceAll = not (io and io.open) and not IEX_WriteFile
DT.skip = DiffT_Skip or {}
local RISKY = { 'bad', 'Bad', 'missing', 'Missing', '%.nil', 'Out', '99', 'NOPE', 'unknown', 'doesNotExist',
	'zero', 'InPortrait6', 'Nope', 'NoSuch' }
local function risky(name)
	for _, p in ipairs(RISKY) do if name:find(p) then return true end end
	return false
end

local function case(name, fn, ...)
	-- M_DIFFTA.lua (the skip list) loads after this file: look it up at call time
	if (DiffT_Skip or {})[name] then
		emit(name, '"skip":"crashes the engine under EEex (skip.txt)"')
		return
	end
	if not DT.inDeferred and risky(name) then
		local args = { n = select('#', ...), ... }
		DT.deferred[#DT.deferred + 1] = { name, fn, args }
		return
	end
	if DT.inDeferred or DT.traceAll then
		DT.flush()
		print('DIFFT|TRACE ' .. name)
	end
	local function pack(...) return select('#', ...), { ... } end
	local n, r = pack(pcall(fn, ...))
	if r[1] then
		local parts = {}
		for i = 2, n do parts[#parts + 1] = ser(r[i]) end
		emit(name, '"r":[' .. table.concat(parts, ',') .. ']')
	else
		emit(name, '"err":' .. jstr(errText(r[2])))
	end
end
DT.case = case

-----------------------------------------------------------------------
-- Helpers on game objects (all called inside a case's pcall)
-----------------------------------------------------------------------

-- Reads a dotted field path; CResRef / char arrays with :get() are read as strings.
local function field(o, path)
	local v = o
	for part in path:gmatch('[^%.]+') do
		if v == nil then return nil end
		v = v[part]
	end
	if type(v) == 'userdata' then
		local ok, s = pcall(function() return v:get() end)
		if ok then return s end
	end
	return v
end
DT.field = field

local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function spriteName(s)
	if s == nil then return nil end
	local ok, n = pcall(EEex_Sprite_GetName, s)
	if ok then return n end
	return scrub(s)
end
local function argSummary(a)
	local t = type(a)
	if t == 'userdata' then
		local ok, n = pcall(EEex_Sprite_GetName, a)
		if ok and type(n) == 'string' then return 'sprite:' .. n end
		local okA, id = pcall(function() return a.m_actionID end)
		if okA and id ~= nil then return 'action:' .. tostring(id) end
		local okE, op = pcall(function() return a.m_effectId end)
		if okE and op ~= nil then
			local okR, res = pcall(function() return a.m_res:get() end)
			return 'effect:' .. tostring(op) .. ':' .. tostring(okR and res or '?')
		end
		local okI, iname = pcall(function() return a.name:get() end)
		if okI and iname ~= nil then return 'item:' .. tostring(iname) end
		return 'ud:' .. scrub(a)
	elseif t == 'table' then
		return 'table'
	elseif t == 'function' then
		return 'function'
	end
	return a
end

-- Collects up to max tuples from a generic-for iterator.
local function collect(max, f, s, var)
	local out = {}
	if type(f) ~= 'function' then return { notIterator = type(f) } end
	for i = 1, max do
		local r = { f(s, var) }
		if r[1] == nil then break end
		var = r[1]
		for k, x in pairs(r) do if type(x) == 'userdata' then r[k] = scrub(x) end end
		out[#out + 1] = r
	end
	return out
end
DT.collect = collect

-----------------------------------------------------------------------
-- Listener recording
-----------------------------------------------------------------------

local function record(name, ...)
	local key = DT.phase .. '|' .. name
	local n = (DT.eventCounts[key] or 0) + 1
	DT.eventCounts[key] = n
	DT.seq = DT.seq + 1
	if n <= 6 then
		local args = {}
		for i = 1, select('#', ...) do args[i] = argSummary((select(i, ...))) end
		DT.events[#DT.events + 1] = { seq = DT.seq, phase = DT.phase, name = name, n = n, args = args }
	end
end
DT.record = record

DT.registered = DT.registered or {}
local function listen(regName, ...)
	local reg = _G[regName]
	if type(reg) ~= 'function' then
		DT.registered[regName] = 'missing'
		return
	end
	local extra = { ... }
	extra[#extra + 1] = function(...) record(regName, ...) end
	local ok, err = pcall(reg, unpackAll(extra))
	DT.registered[regName] = ok and 'ok' or errText(err)
end

-----------------------------------------------------------------------
-- Cases
-----------------------------------------------------------------------

DT.loadTime = DT.loadTime or {}

-- Things checked at M_ load time (before the UI): globals present, Lua environment.
local function loadTimeSnapshot()
	local s = DT.loadTime
	s.version = _VERSION
	s.io = type(io)
	s.ioOpen = type(io) == 'table' and type(io.open) or 'none'
	s.os = type(os)
	s.osTime = type(os) == 'table' and type(os.time) or 'none'
	s.package = type(package)
	s.require = type(require)
	s.debug = type(debug)
	s.jit = type(jit)
	s.utf8 = type(utf8)
	s.bit32 = type(bit32)
	s.mathType = type(math.type)
	s.unpack = type(unpack)
	s.tableUnpack = type(table.unpack)
	s.loadstring = type(loadstring)
	s.setfenv = type(setfenv)
	s.intDiv = pcall(load or loadstring, 'return 7 // 2') and 'parses' or 'no'
	s.floatStr = tostring(3 / 1)
	s.EEex_Active = tostring(EEex_Active)
	s.optionsGetSQFps = type(EEex_Options_Get) == 'function' and tostring(EEex_Options_Get('SQOPT_Fps')) or 'n/a'
	s.uiItemType = type(uiItemType)
	s.EngineGlobals = type(EngineGlobals)
	s.worldScreen = type(worldScreen)
	s.e = type(e)
end
pcall(loadTimeSnapshot)

-- Options registered at M_ load time (like SadoEE does): the probe compares what get() returns later.
local function newOption(default, section, key, min, max, onChange)
	return EEex_Options_Option.new({
		['default'] = default,
		['type'] = EEex_Options_ToggleType.new(),
		['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = min or 0, ['max'] = max or 1 }),
		['storage'] = EEex_Options_NumberLuaStorage.new({ ['section'] = section, ['key'] = key }),
		['onChange'] = onChange,
	})
end
DT.onChange = DT.onChange or {}
local function registerLoadTimeOptions()
	-- Pre0 / Pre1 / Pre7 / PreStr are seeded in Baldur.lua by run.ps1; Fresh* keys are absent.
	local defs = {
		{ 'DIFFT_Pre0', 1, 'DiffTest', 'Pre0' },
		{ 'DIFFT_Pre1', 0, 'DiffTest', 'Pre1' },
		{ 'DIFFT_Pre7', 1, 'DiffTest', 'Pre7', 0, 10 },
		{ 'DIFFT_Pre7Clamp', 0, 'DiffTest', 'Pre7' },
		{ 'DIFFT_PreStr', 1, 'DiffTest', 'PreStr' },
		{ 'DIFFT_Fresh1', 1, 'DiffTest', 'Fresh1' },
		{ 'DIFFT_Fresh0', 0, 'DiffTest', 'Fresh0' },
		{ 'DIFFT_Set', 1, 'DiffTest', 'SetMe' },
		{ 'DIFFT_SetNil', 1, 'DiffTest', 'SetNil' },
	}
	for _, d in ipairs(defs) do
		local id = d[1]
		EEex_Options_Register(id, newOption(d[2], d[3], d[4], d[5], d[6], function(...)
			local args = { ... }
			for i, a in ipairs(args) do args[i] = argSummary(a) end
			DT.onChange[#DT.onChange + 1] = { id = id, phase = DT.phase, args = args }
		end))
	end
end
DT.optLoad = pcall(registerLoadTimeOptions)

local function optGet(id)
	local o = EEex_Options_Get(id)
	if o == nil then return 'no option' end
	return o:get()
end

-- Options snapshot at a lifecycle point (load / main file / initialized / suite).
DT.optSnaps = DT.optSnaps or {}
local SQ_KEYS = { 'StashTints', 'StashPlus', 'StashDps', 'Traps', 'AutoDisarm', 'AutoOpen', 'Outline', 'Ammo',
	'Quiver', 'AttackMove', 'SongSpam', 'SortedLoot', 'ChestsBar', 'Waiting', 'Fps', 'OpenPage' }
local DT_KEYS = { 'Pre0', 'Pre1', 'Pre7', 'Pre7Clamp', 'PreStr', 'Fresh1', 'Fresh0', 'Set', 'SetNil' }
local function optSnapshot(point)
	local snap = {}
	if type(EEex_Options_Get) ~= 'function' then snap.missing = true return end
	for _, k in ipairs(SQ_KEYS) do
		local ok, v = pcall(optGet, 'SQOPT_' .. k)
		snap['SQOPT_' .. k] = ok and v or errText(v)
	end
	for _, k in ipairs(DT_KEYS) do
		local ok, v = pcall(optGet, 'DIFFT_' .. k)
		snap['DIFFT_' .. k] = ok and v or errText(v)
	end
	DT.optSnaps[point] = snap
end
pcall(optSnapshot, '1_mload')


-----------------------------------------------------------------------
-- Settings and options UI helpers (EEex.ini / InfinityLoader.ini effects, EEex options screen)
-----------------------------------------------------------------------

-- A menu item value: string / number as is, a function called (pcall), other values scrubbed.
local function itemVariant(v)
	if EEex_Menu_GetItemVariant then
		local ok, r = pcall(EEex_Menu_GetItemVariant, v)
		if ok then v = r end
	end
	if type(v) == 'function' then
		local ok, r = pcall(v)
		v = ok and r or 'ERROR'
	end
	if type(v) == 'userdata' then v = scrub(v) end
	return v
end
-- The visible layout of a menu: per item its type, area, text, BAM and sequence (no code, only what is drawn).
local function menuLayout(name, max)
	local m = EEex_Menu_Find(name)
	if not m then return 'no menu' end
	local out, it, n = {}, m.items, 0
	while it ~= nil and n < (max or 150) do
		n = n + 1
		local r = {}
		pcall(function() r.type = it.type end)
		pcall(function() local a = it.area r.area = { a.x, a.y, a.w, a.h } end)
		pcall(function() r.text = itemVariant(it.text.text) end)
		pcall(function() r.bam = itemVariant(it.bam.resref) end)
		pcall(function() r.seq = itemVariant(it.bam.sequence) end)
		pcall(function() r.enabled = itemVariant(it.enabled) end)
		out[n] = r
		it = it.next
	end
	return n, out
end
DT.menuLayout = menuLayout
-- Method / field names of a class table and of its metatable chain (the API shape, not code).
local function classKeys(c, depth)
	if type(c) ~= 'table' then return type(c) end
	local out, seen, level = {}, {}, 0
	while type(c) == 'table' and not seen[c] and level < (depth or 4) do
		seen[c] = true
		level = level + 1
		local keys = {}
		for k, v in pairs(c) do if type(k) == 'string' then keys[#keys + 1] = k .. ':' .. type(v) end end
		table.sort(keys)
		out[level] = keys
		local mt = getmetatable(c)
		local nxt = nil
		if type(mt) == 'table' then
			nxt = rawget(mt, '__index')
			if type(nxt) ~= 'table' then nxt = mt end
		end
		c = nxt
	end
	return out
end
DT.classKeys = classKeys
-- Menus pushed while fn runs (the options screen's own menu names).
local function recordPushes(fn)
	local push, pushed = Infinity_PushMenu, {}
	Infinity_PushMenu = function(name, ...)
		pushed[#pushed + 1] = tostring(name)
		return push(name, ...)
	end
	local ok, err = pcall(fn)
	Infinity_PushMenu = push
	if not ok then pushed[#pushed + 1] = errText(err) end
	return pushed
end
DT.recordPushes = recordPushes
DT.optMenus = DT.optMenus or {}

-- A storage of BuffBot's shape: inherits EEex_Options_Private_Storage, read(option) / write(option, value).
DT.storageCalls = DT.storageCalls or {}
local function makeProbeStorage()
	if not EEex_Options_Private_Storage then return nil end
	local storage = {}
	storage.__index = storage
	setmetatable(storage, EEex_Options_Private_Storage)
	function storage:read(option)
		DT.storageCalls[#DT.storageCalls + 1] = { 'read', DT.phase, type(option),
			type(option) == 'table' and type(option._getDefault) or 'nil' }
		if type(option) == 'table' and option._getDefault then return option:_getDefault() + 1 end
		return 2
	end
	function storage:write(option, value)
		DT.storageCalls[#DT.storageCalls + 1] = { 'write', DT.phase, type(option), value }
	end
	storage.new = function(o) return setmetatable(o or {}, storage) end
	return storage
end
pcall(function()
	DT.storageClass = makeProbeStorage()
	if DT.storageClass then
		EEex_Options_Register('DIFFT_Custom', EEex_Options_Option.new({
			['default'] = 1,
			['type'] = EEex_Options_ToggleType.new(),
			['accessor'] = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 5 }),
			['storage'] = DT.storageClass.new(),
		}))
	end
end)

-- Fixed-size engine arrays (EEex usertype arrays): shape (.size, get / getReference / set), element objects
-- (arrays of CPtrList: getReference(i) is the level's list, usable by EEex_Utility_IterateCPtrList), bounds.
local function arrayCases()
	local function pc(f, ...) local ok, v = pcall(f, ...) if ok then return v end return 'ERR' end
	local function shape(a)
		return { t = type(a), size = pc(function() return a.size end), get = type(pc(function() return a.get end)),
			getReference = type(pc(function() return a.getReference end)), set = type(pc(function() return a.set end)),
			len = pc(function() return #a end) }
	end
	local function elem(v)
		if type(v) ~= 'userdata' then return { t = type(v), v = v } end
		return { t = 'userdata', m_nCount = pc(function() return v.m_nCount end),
			size = pc(function() return v.size end), reference = type(pc(function() return v.reference end)) }
	end
	local function entryName(e)
		return pc(function() return e.m_spellId:get() end) ~= 'ERR' and pc(function() return e.m_spellId:get() end)
			or pc(function() return e.m_knownSpellId:get() end)
	end
	local sprite = P(0)
	local lists = { 'm_knownSpellsMage', 'm_knownSpellsPriest', 'm_memorizedSpellsMage', 'm_memorizedSpellsPriest',
		'm_memorizedSpellsInnate' }
	for _, f in ipairs(lists) do
		case('arr.' .. f .. '.shape', function() return shape(sprite[f]) end)
		case('arr.' .. f .. '.get0', function() return elem(sprite[f]:get(0)) end)
		case('arr.' .. f .. '.ref0', function() return elem(sprite[f]:getReference(0)) end)
		case('arr.' .. f .. '.ref0isArray', function() return sprite[f]:getReference(0) == sprite[f] end)
		case('arr.' .. f .. '.levels', function()
			local a, out = sprite[f], {}
			for lvl = 0, a.size - 1 do
				local names = {}
				EEex_Utility_IterateCPtrList(a:getReference(lvl), function(e) names[#names + 1] = entryName(e) end)
				out[#out + 1] = table.concat(names, ',')
			end
			return out
		end)
		case('arr.' .. f .. '.refPastEnd', function() return elem(sprite[f]:getReference(sprite[f].size)) end)
		case('arr.' .. f .. '.refNegative', function() return elem(sprite[f]:getReference(-1)) end)
	end
	-- BGBot's spell restore loop (M_BGBCMB.lua), read-only
	case('arr.bgbotLoop', function()
		local n = 0
		for _, f in ipairs({ 'm_memorizedSpellsMage', 'm_memorizedSpellsPriest' }) do
			local levels = sprite[f]
			for lvl = 0, levels.size - 1 do
				EEex_Utility_IterateCPtrList(levels:getReference(lvl), function(spell) if spell.m_flags ~= nil then n = n + 1 end end)
			end
		end
		return n
	end)
	for _, f in ipairs({ 'm_memorizedSpellsLevelMage', 'm_memorizedSpellsLevelPriest' }) do
		case('arr.' .. f .. '.shape', function() return shape(sprite[f]) end)
		case('arr.' .. f .. '.get0', function() return elem(sprite[f]:get(0)) end)
		case('arr.' .. f .. '.ref0', function() return elem(sprite[f]:getReference(0)) end)
	end
	local prims = {
		{ 'm_disabledButtons', function() return sprite end },
		{ 'm_spellStates', function() return sprite.m_derivedStats end },
		{ 'm_formations', function() return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame end },
		{ 'm_characters', function() return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame end },
		{ 'm_gameAreas', function() return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame end },
		{ 'm_items', function() return sprite.m_equipment end },
	}
	for _, pr in ipairs(prims) do
		local f, owner = pr[1], pr[2]
		case('arr.' .. f .. '.shape', function() return shape(owner()[f]) end)
		case('arr.' .. f .. '.get', function()
			local a, out = owner()[f], {}
			for i = 0, math.min(a.size, 16) - 1 do out[#out + 1] = elem(a:get(i)) end
			return out
		end)
		case('arr.' .. f .. '.ref0', function() return elem(owner()[f]:getReference(0)) end)
		case('arr.' .. f .. '.ref0access', function()
			local r = owner()[f]:getReference(0)
			return { value = type(pc(function() return r.value end)), get = type(pc(function() return r:get() end)),
				reference = type(pc(function() return r.reference end)) }
		end)
		case('arr.' .. f .. '.getPastEnd', function() return elem(owner()[f]:get(owner()[f].size)) end)
	end
	case('arr.m_formations.setRoundTrip', function()
		local a = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame.m_formations
		local v = a:get(0)
		a:set(0, v)
		return a:get(0) == v
	end)
end
DT.arrayCases = arrayCases

-- The suite: deterministic calls only (the save, the party, fixed resrefs / IDS strings).
local function runCases()
	local p0, p1 = P(0), P(1)
	local function gameState()
		local g = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
		local out = { rep = g.m_nReputation, time = g.m_worldTime.m_gameTime }
		for i = 0, 5 do
			local s = P(i)
			if s then out['P' .. i] = { s.m_curAction.m_actionID, s.m_equipment.m_selectedWeapon, s.m_baseStats.m_hitPoints } end
		end
		return out
	end
	case('state.start', gameState)
	arrayCases()

	-- Lua environment and load-time state
	for k, v in pairs(DT.loadTime) do case('env.' .. k, function() return v end) end
	case('env.registered', function() return DT.registered end)
	case('probe.worldVia', function() return DT.worldVia or 'initialized' end)

	-- API surface: every EEex_* global (one case each: missing on one side = missing API)
	local names = {}
	for k, v in pairs(_G) do
		if type(k) == 'string' and k:match('^EEex_') then names[#names + 1] = k end
	end
	table.sort(names)
	for _, k in ipairs(names) do
		local v = _G[k]
		local t = type(v)
		case('global.' .. k, function()
			if t == 'table' then
				local keys = {}
				for kk in pairs(v) do if type(kk) == 'string' then keys[#keys + 1] = kk end end
				table.sort(keys)
				if #keys > 60 then return 'table', #keys end
				return 'table', table.concat(keys, ',')
			elseif t == 'function' or t == 'userdata' then
				return t
			end
			return t, v
		end)
	end
	-- Names from the generated list (M_DIFFTA.lua): type only, so absent names show too
	for _, k in ipairs(DiffT_SurfaceNames or {}) do
		case('surface.' .. k, function() return type(_G[k]) end)
	end

	-- Bit operations
	case('bit.BAnd', function() return EEex_BAnd(0xF0, 0x3C) end)
	case('bit.BOr', function() return EEex_BOr(0xF0, 0x0F) end)
	case('bit.BXor', function() return EEex_BXor(0xFF, 0x0F) end)
	case('bit.BNot0', function() return EEex_BNot(0) end)
	case('bit.LShift', function() return EEex_LShift(1, 4) end)
	case('bit.RShift', function() return EEex_RShift(256, 4) end)
	case('bit.IsBitSet', function() return EEex_IsBitSet(5, 0), EEex_IsBitSet(5, 1), EEex_IsBitSet(5, 2) end)
	case('bit.IsBitUnset', function() return EEex_IsBitUnset(5, 1) end)
	case('bit.SetBit', function() return EEex_SetBit(0, 3) end)
	case('bit.UnsetBit', function() return EEex_UnsetBit(15, 0) end)
	case('bit.IsMaskSet', function() return EEex_IsMaskSet(7, 3), EEex_IsMaskSet(4, 3) end)
	case('bit.IsMaskUnset', function() return EEex_IsMaskUnset(4, 3) end)
	case('bit.SetMask', function() return EEex_SetMask(1, 6) end)
	case('bit.UnsetMask', function() return EEex_UnsetMask(7, 2) end)
	case('bit.BAndNeg', function() return EEex_BAnd(-1, 0xFF) end)

	-- Memory
	case('mem.roundtrip', function()
		local m = EEex_Malloc(64)
		local r = {}
		EEex_Write32(m, -2) r.r32 = EEex_Read32(m) r.ru32 = EEex_ReadU32(m)
		EEex_Write8(m, 200) r.r8 = EEex_Read8(m) r.ru8 = EEex_ReadU8(m)
		EEex_Write16(m, 0xFFFF) r.r16 = EEex_Read16(m) r.ru16 = EEex_ReadU16(m)
		EEex_WriteU32(m, 0xFFFFFFFF) r.ru32b = EEex_ReadU32(m) r.r32b = EEex_Read32(m)
		EEex_WriteString(m + 8, 'difftest') r.str = EEex_ReadString(m + 8)
		r.lstr = EEex_ReadLString(m + 8, 4)
		EEex_Write64(m + 32, 1234567) r.r64 = EEex_Read64(m + 32)
		r.mallocType = type(m)
		EEex_Free(m)
		return r
	end)
	case('mem.WriteU8neg', function()
		local m = EEex_Malloc(8)
		EEex_WriteU8(m, -1)
		local v = EEex_ReadU8(m)
		EEex_Free(m)
		return v
	end)

	-- Party
	case('party.NumCharacters', function() return EEex_Sprite_GetNumCharacters() end)
	for i = 0, 6 do
		case('party.InPortrait' .. i, function() local s = P(i) return s ~= nil, spriteName(s) end)
		case('party.InPortraitID' .. i .. '.isNumber', function()
			local id = EEex_Sprite_GetInPortraitID(i) return type(id), id == -1
		end)
	end
	local STATS = {}
	for s = 1, 110 do STATS[#STATS + 1] = s end
	for i = 0, 5 do
		local tag = 'P' .. i
		case(tag .. '.GetName', function() return EEex_Sprite_GetName(P(i)) end)
		case(tag .. '.PortraitIndex', function() return EEex_Sprite_GetPortraitIndex(P(i)) end)
		case(tag .. '.CharacterIndex', function() return EEex_Sprite_GetCharacterIndex(P(i)) end)
		case(tag .. '.GetState', function() return EEex_Sprite_GetState(P(i)) end)
		case(tag .. '.GetClass', function() return EEex_Sprite_GetClass(P(i)) end)
		case(tag .. '.ModalState', function() return EEex_Sprite_GetModalState(P(i)) end)
		case(tag .. '.PersonalSpace', function() return EEex_Sprite_GetPersonalSpace(P(i)) end)
		case(tag .. '.SpellState1', function() return EEex_Sprite_GetSpellState(P(i), 1) end)
		case(tag .. '.CasterLevel.SPWI112', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'SPWI112', false) end)
		case(tag .. '.CasterLevel.SPPR101', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'SPPR101', true) end)
		case(tag .. '.Stats', function()
			local s, out = P(i), {}
			for _, st in ipairs(STATS) do
				local ok, v = pcall(EEex_Sprite_GetStat, s, st)
				out[st] = ok and v or errText(v)
			end
			return out
		end)
		case(tag .. '.StatBad', function() return EEex_Sprite_GetStat(P(i), 9999) end)
		case(tag .. '.LocalInt.unset', function() return EEex_Sprite_GetLocalInt(P(i), 'DIFFT_L') end)
		case(tag .. '.LocalInt.set', function()
			EEex_Sprite_SetLocalInt(P(i), 'DIFFT_L', 40 + i) return EEex_Sprite_GetLocalInt(P(i), 'DIFFT_L')
		end)
		case(tag .. '.LocalString.unset', function() return EEex_Sprite_GetLocalString(P(i), 'DIFFT_S') end)
		case(tag .. '.LocalString.set', function()
			EEex_Sprite_SetLocalString(P(i), 'DIFFT_S', 'v' .. i) return EEex_Sprite_GetLocalString(P(i), 'DIFFT_S')
		end)
		case(tag .. '.MageSpells', function() return collect(60, EEex_Sprite_GetKnownMageSpellsIterator(P(i))) end)
		case(tag .. '.MageSpells.L1', function() return collect(30, EEex_Sprite_GetKnownMageSpellsIterator(P(i), 1, 1)) end)
		case(tag .. '.PriestSpells', function() return collect(60, EEex_Sprite_GetKnownPriestSpellsIterator(P(i))) end)
		case(tag .. '.ActiveStats.type', function() return scrub(EEex_Sprite_GetActiveStats(P(i))) end)
		-- typed fields mods read
		local FIELDS = { 'm_id', 'm_objectType', 'm_pos.x', 'm_pos.y', 'm_typeAI.m_EnemyAlly', 'm_typeAI.m_General',
			'm_typeAI.m_Race', 'm_typeAI.m_Class', 'm_typeAI.m_Specifics', 'm_typeAI.m_Gender', 'm_typeAI.m_Alignment',
			'm_scriptName', 'm_resref', 'm_dialog', 'm_baseStats.m_name', 'm_baseStats.m_apparentName',
			'm_baseStats.m_flags', 'm_baseStats.m_xpValue', 'm_baseStats.m_xp', 'm_baseStats.m_gold',
			'm_baseStats.m_generalState', 'm_baseStats.m_hitPoints', 'm_baseStats.m_maxHitPointsBase',
			'm_baseStats.m_portraitSmall', 'm_baseStats.m_portraitLarge', 'm_baseStats.m_armorClass',
			'm_baseStats.m_level1', 'm_baseStats.m_level2', 'm_baseStats.m_level3', 'm_baseStats.m_STRBase',
			'm_baseStats.m_STRExtraBase', 'm_baseStats.m_INTBase', 'm_baseStats.m_WISBase', 'm_baseStats.m_DEXBase',
			'm_baseStats.m_CONBase', 'm_baseStats.m_CHRBase', 'm_baseStats.m_mageSpecUpperWord',
			'm_derivedStats.m_generalState', 'm_derivedStats.m_nMaxHitPoints', 'm_derivedStats.m_nSTR',
			'm_derivedStats.m_nLevel1', 'm_startTypeAI.m_Class', 'm_liveTypeAI.m_Class',
			'm_animation.m_animationID', 'm_pArea.m_resref', 'm_equipment.m_selectedWeapon',
			'm_queuedActions.m_nCount', 'm_curAction.m_actionID', 'm_doesNotExist' }
		for _, f in ipairs(FIELDS) do
			case(tag .. '.field.' .. f, function() return field(P(i), f) end)
		end
	end
	case('P0.UDEqual.self', function() return EEex_UDEqual(p0, P(0)) end)
	case('P0.UDEqual.other', function() return EEex_UDEqual(p0, p1) end)
	case('P0.GameObject.Get', function()
		local o = EEex_GameObject_Get(p0.m_id) return EEex_UDEqual(o, p0), scrub(o)
	end)
	case('P0.GameObject.IsSprite', function() return EEex_GameObject_IsSprite(p0), EEex_GameObject_IsSprite(p0, true) end)
	case('P0.GameObject.CastUserType', function() return scrub(EEex_GameObject_CastUserType(EEex_GameObject_Get(p0.m_id))) end)
	case('GameObject.Get.bad', function() return EEex_GameObject_Get(-1) end)
	case('GameObject.Get.zero', function() return EEex_GameObject_Get(0) end)
	case('Sprite.GetInPortrait.bad', function() return EEex_Sprite_GetInPortrait(9) end)
	case('Sprite.GetName.nil', function() return EEex_Sprite_GetName(nil) end)

	-- Legacy actor API
	case('legacy.GetActorName', function() return EEex_GetActorName(p0.m_id) end)
	case('legacy.GetActorStat', function() return EEex_GetActorStat(p0.m_id, 1) end)
	case('legacy.GetActorClass', function() return EEex_GetActorClass(p0.m_id) end)
	case('legacy.GetActorIDPortrait', function() return EEex_GetActorIDPortrait(0) == p0.m_id end)
	case('legacy.ToHex', function() return EEex_ToHex(255), EEex_ToHex(255, 4), EEex_ToHex(255, 4, true) end)

	-- Globals / area variables
	case('global.GetGlobalInt.unset', function() return EEex_GameState_GetGlobalInt('DIFFT_G') end)
	case('global.SetGlobalInt', function()
		EEex_GameState_SetGlobalInt('DIFFT_G', 7) return EEex_GameState_GetGlobalInt('DIFFT_G')
	end)
	case('global.GetGlobalString.unset', function() return EEex_GameState_GetGlobalString('DIFFT_GS') end)
	case('global.SetGlobalString', function()
		EEex_GameState_SetGlobalString('DIFFT_GS', 'abc') return EEex_GameState_GetGlobalString('DIFFT_GS')
	end)
	case('global.Chapter', function() return EEex_GameState_GetGlobalInt('CHAPTER') end)
	local area = EEex_Area_GetVisible()
	case('area.Visible', function() return area ~= nil, field(area, 'm_resref') end)
	case('area.SameAsP0', function() return EEex_UDEqual(area, p0.m_pArea) end)
	case('area.VariableInt', function()
		local a = EEex_Area_GetVariableInt(area, 'DIFFT_A')
		EEex_Area_SetVariableInt(area, 'DIFFT_A', 5)
		return a, EEex_Area_GetVariableInt(area, 'DIFFT_A')
	end)
	case('area.VariableString', function()
		local a = EEex_Area_GetVariableString(area, 'DIFFT_AS')
		EEex_Area_SetVariableString(area, 'DIFFT_AS', 'xy')
		return a, EEex_Area_GetVariableString(area, 'DIFFT_AS')
	end)
	case('area.objects', function()
		local types, scripts = {}, {}
		for _, listName in ipairs({ 'm_lVertSort', 'm_lVertSortBack' }) do
			EEex_Utility_IterateCPtrList(area[listName], function(id)
				local o = EEex_GameObject_Get(id)
				if o then
					local t = tostring(o.m_objectType)
					types[t] = (types[t] or 0) + 1
					if o.m_objectType ~= 49 then
						local cast = EEex_GameObject_CastUserType(o)
						local ok, sn = pcall(field, cast, 'm_scriptName')
						if ok and sn then scripts[#scripts + 1] = sn end
					end
				end
			end)
		end
		table.sort(scripts)
		return types, scripts
	end)
	case('area.GetAllOfTypeStringInRange.PLAYER1', function()
		local all = EEex_Area_GetAllOfTypeStringInRange(p0.m_pArea, p0.m_pos.x, p0.m_pos.y, '[PC]', 32767, false)
		local names = {}
		for _, s in ipairs(all or {}) do names[#names + 1] = spriteName(s) end
		table.sort(names)
		return type(all), names
	end)
	case('area.GetAllOfTypeInRange', function()
		local all = EEex_Sprite_GetAllOfTypeInRange(p0, '[PC]', 32767)
		return type(all), all and #all
	end)
	case('area.NearestOpenPosition', function()
		return EEex_Area_GetNearestOpenPosition(area, p0.m_pos.x, p0.m_pos.y, EEex_Sprite_GetPersonalSpace(p0))
	end)

	-- Resources
	case('res.ExtToType', function()
		return EEex_Resource_ExtToType('SPL'), EEex_Resource_ExtToType('ITM'), EEex_Resource_ExtToType('2DA'),
			EEex_Resource_ExtToType('IDS'), EEex_Resource_ExtToType('BAM'), EEex_Resource_ExtToType('XYZ')
	end)
	local SPL_FIELDS = { 'genericName', 'identifiedName', 'itemType', 'spellLevel', 'school', 'secondaryType',
		'abilityCount', 'abilityOffset', 'effectsOffset', 'castingSound', 'itemFlags', 'notUsableBy' }
	local ITM_FIELDS = { 'genericName', 'identifiedName', 'itemType', 'baseValue', 'baseWeight', 'maxStackable',
		'abilityCount', 'abilityOffset', 'equipedStartingEffect', 'equipedEffectCount', 'itemFlags', 'notUsableBy',
		'minLevelRequired', 'minSTRRequired', 'itemIcon', 'loreValue', 'descriptionPicture', 'animationType' }
	local ABIL_FIELDS = { 'type', 'quickSlotType', 'range', 'launcherType', 'damageDiceCount', 'damageDice',
		'damageDiceBonus', 'damageType', 'effectCount', 'startingEffect', 'actionCount', 'attackProbability',
		'quickSlotIcon', 'targetType', 'speedFactor', 'thac0Bonus', 'projectileType', 'minCasterLevel', 'abilityFlags' }
	for _, res in ipairs({ { 'SPWI112', 'SPL' }, { 'SPPR101', 'SPL' }, { 'SPWI304', 'SPL' } }) do
		local tag = 'res.' .. res[1]
		case(tag .. '.Demand', function() local h = EEex_Resource_Demand(res[1], res[2]) return h ~= nil, scrub(h) end)
		for _, f in ipairs(SPL_FIELDS) do
			case(tag .. '.' .. f, function() return field(EEex_Resource_Demand(res[1], res[2]), f) end)
		end
		case(tag .. '.ability0', function()
			local a = EEex_Resource_GetSpellAbility(EEex_Resource_Demand(res[1], res[2]), 0)
			local out = {}
			for _, f in ipairs(ABIL_FIELDS) do local ok, v = pcall(field, a, f) out[f] = ok and v or errText(v) end
			return out
		end)
		case(tag .. '.abilityForLevel9', function()
			local a = EEex_Resource_GetSpellAbilityForLevel(EEex_Resource_Demand(res[1], res[2]), 9)
			return a ~= nil and field(a, 'minCasterLevel')
		end)
		case(tag .. '.ability99', function() return EEex_Resource_GetSpellAbility(EEex_Resource_Demand(res[1], res[2]), 99) end)
	end
	for _, res in ipairs({ 'SW1H01', 'BOW01', 'POTN08', 'RING06', 'AROW01' }) do
		local tag = 'res.' .. res
		case(tag .. '.Demand', function() local h = EEex_Resource_Demand(res, 'ITM') return h ~= nil, scrub(h) end)
		case(tag .. '.fields', function()
			local h, out = EEex_Resource_Demand(res, 'ITM'), {}
			for _, f in ipairs(ITM_FIELDS) do local ok, v = pcall(field, h, f) out[f] = ok and v or errText(v) end
			return out
		end)
		case(tag .. '.ability0', function()
			local a = EEex_Resource_GetItemAbility(EEex_Resource_Demand(res, 'ITM'), 0)
			local out = {}
			for _, f in ipairs(ABIL_FIELDS) do local ok, v = pcall(field, a, f) out[f] = ok and v or errText(v) end
			return out
		end)
	end
	case('res.Demand.missing', function() return EEex_Resource_Demand('DIFFTNO', 'ITM') end)
	case('res.Demand.lower', function() return EEex_Resource_Demand('sw1h01', 'itm') ~= nil end)
	case('res.Fetch.SW1H01', function() return EEex_Resource_Fetch('SW1H01', 'ITM') ~= nil end)
	case('res.Fetch.missing', function() return EEex_Resource_Fetch('DIFFTNO', 'STO') end)

	-- 2DA
	for _, t in ipairs({ 'KITLIST', 'STRMOD', 'HPCLASS', 'WSPECIAL', 'XPLEVEL' }) do
		local tag = '2da.' .. t
		case(tag .. '.Load', function() return scrub(EEex_Resource_Load2DA(t)) end)
		case(tag .. '.getDimensions', function() return EEex_Resource_Load2DA(t):getDimensions() end)
		case(tag .. '.getAtPoint00', function() return EEex_Resource_Load2DA(t):getAtPoint(0, 0) end)
		case(tag .. '.getAtPoint11', function() return EEex_Resource_Load2DA(t):getAtPoint(1, 1) end)
		case(tag .. '.getAtPointOut', function() return EEex_Resource_Load2DA(t):getAtPoint(999, 999) end)
		case(tag .. '.getColumnLabel0', function() return EEex_Resource_Load2DA(t):getColumnLabel(0) end)
		case(tag .. '.getRowLabel0', function() return EEex_Resource_Load2DA(t):getRowLabel(0) end)
		case(tag .. '.getDefault', function() return EEex_Resource_Load2DA(t):getDefault() end)
		case(tag .. '.findColumnIndex', function()
			local a = EEex_Resource_Load2DA(t) return a:findColumnIndex(a:getColumnLabel(1))
		end)
		case(tag .. '.findRowIndex', function()
			local a = EEex_Resource_Load2DA(t) return a:findRowIndex(a:getRowLabel(2))
		end)
		case(tag .. '.GetAt2DAPoint', function() return EEex_Resource_GetAt2DAPoint(EEex_Resource_Load2DA(t), 1, 1) end)
	end
	case('2da.GetAt2DALabels.STRMOD', function() return EEex_Resource_GetAt2DALabels(EEex_Resource_Load2DA('STRMOD'), 'WEIGHT_ALLOWANCE', '18') end)
	case('2da.GetAt2DALabels.KITLIST', function() return EEex_Resource_GetAt2DALabels(EEex_Resource_Load2DA('KITLIST'), 'ROWNAME', '1') end)
	case('2da.GetAt2DALabels.HPCLASS', function() return EEex_Resource_GetAt2DALabels(EEex_Resource_Load2DA('HPCLASS'), 'TABLE', 'FIGHTER') end)
	case('2da.GetAt2DALabels.missing', function() return EEex_Resource_GetAt2DALabels(EEex_Resource_Load2DA('STRMOD'), 'NOPE', 'NOPE') end)
	case('2da.Load.missing', function() return EEex_Resource_Load2DA('DIFFTNO') end)

	-- IDS
	for _, t in ipairs({ 'STATS', 'KIT', 'ITEMCAT', 'CLASS', 'SPELL' }) do
		local tag = 'ids.' .. t
		case(tag .. '.Load', function() return scrub(EEex_Resource_LoadIDS(t)) end)
		case(tag .. '.getCount', function() return EEex_Resource_LoadIDS(t):getCount() end)
		case(tag .. '.getStart', function() return EEex_Resource_LoadIDS(t):getStart() end)
		case(tag .. '.getLine1', function() return EEex_Resource_LoadIDS(t):getLine(1) end)
		case(tag .. '.hasID1', function() return EEex_Resource_LoadIDS(t):hasID(1), EEex_Resource_LoadIDS(t):hasID(987654) end)
		case(tag .. '.iterate', function()
			local out, n = {}, 0
			for a, b in EEex_Resource_LoadIDS(t):iterateEntries() do
				n = n + 1
				if n <= 12 then out[#out + 1] = { a, b } end
			end
			return n, out
		end)
	end
	case('ids.KitIDSToSymbol', function() return EEex_Resource_KitIDSToSymbol(0x4001), EEex_Resource_KitIDSToSymbol(0) end)
	case('ids.KitSymbolToIDS', function() return EEex_Resource_KitSymbolToIDS('BERSERKER'), EEex_Resource_KitSymbolToIDS('NOPE') end)
	case('ids.ItemCatIDSToSymbol', function() return EEex_Resource_ItemCategoryIDSToSymbol(20), EEex_Resource_ItemCategoryIDSToSymbol(9) end)
	case('ids.ItemCatSymbolToIDS', function() return EEex_Resource_ItemCategorySymbolToIDS('LONG_SWORD'), EEex_Resource_ItemCategorySymbolToIDS('POTION') end)
	case('ids.cacheAsArray', function() local a = EEex_Resource_LoadIDS('STATS', true) return type(a), scrub(a) end)

	-- Trigger / action / object strings
	case('ta.Eval.True', function() return EEex_Trigger_EvalConditionalStringAsAIBase('True()', p0) end)
	case('ta.Eval.False', function() return EEex_Trigger_EvalConditionalStringAsAIBase('False()', p0) end)
	case('ta.Eval.Global', function() return EEex_Trigger_EvalConditionalStringAsAIBase('Global("DIFFT_G","GLOBAL",7)', p0) end)
	case('ta.Eval.InParty', function() return EEex_Trigger_EvalConditionalStringAsAIBase('InParty(Myself)', p0) end)
	case('ta.Eval.Two', function() return EEex_Trigger_EvalConditionalStringAsAIBase('True() !False()', p0) end)
	case('ta.Eval.Bad', function() return EEex_Trigger_EvalConditionalStringAsAIBase('NotATrigger(', p0) end)
	case('ta.Parse.EvalFile', function()
		local c = EEex_Trigger_ParseConditionalString('InParty(Myself)')
		local r = EEex_Trigger_EvalScriptFileConditionalAsAIBase(c, p1)
		pcall(function() c:free() end)
		return r
	end)
	case('ta.Object.Player1', function() return spriteName(EEex_Object_EvalStringAsAIBase('Player1', p1)) end)
	case('ta.Object.Myself', function() return spriteName(EEex_Object_EvalStringAsAIBase('Myself', p1)) end)
	case('ta.Object.Player6', function() return spriteName(EEex_Object_EvalStringAsAIBase('Player6', p0)) end)
	case('ta.Object.Parse', function() return scrub(EEex_Object_ParseString('Player2')) end)
	case('ta.ExecInstantly', function()
		EEex_Action_ExecuteResponseStringOnAIBaseInstantly('SetGlobal("DIFFT_H","GLOBAL",3)', p0)
		return EEex_GameState_GetGlobalInt('DIFFT_H')
	end)
	case('ta.ExecInstantly.Two', function()
		EEex_Action_ExecuteResponseStringOnAIBaseInstantly('SetGlobal("DIFFT_H2","GLOBAL",1) IncrementGlobal("DIFFT_H2","GLOBAL",4)', p0)
		return EEex_GameState_GetGlobalInt('DIFFT_H2')
	end)
	case('ta.ParseResponse', function() return scrub(EEex_Action_ParseResponseString('NoAction()')) end)

	-- Key names
	for _, k in ipairs({ 'a', 'A', 'z', 'F12', 'F1', 'Escape', 'Space', 'Return', 'Left Shift', 'Left Ctrl', 'Tab', '1', 'Nope' }) do
		case('key.GetFromName.' .. k, function() return EEex_Key_GetFromName(k) end)
	end
	case('key.IsDown.a', function() return EEex_Key_IsDown(EEex_Key_GetFromName('a')) end)

	-- Menus
	for _, m in ipairs({ 'WORLD_ACTIONBAR', 'RIGHT_SIDEBAR', 'OPTIONS', 'ESC_MENU', 'DIFFT_TICK', 'NOPE_MENU', 'SQOPT_PAGE', 'PSTASH' }) do
		case('menu.Find.' .. m, function() local x = EEex_Menu_Find(m) return x ~= nil, scrub(x) end)
		case('menu.GetArea.' .. m, function() return EEex_Menu_GetArea(m) end)
	end
	case('menu.UIMenuArea.WORLD_ACTIONBAR', function() return EEex_Menu_GetUIMenuArea(EEex_Menu_Find('WORLD_ACTIONBAR')) end)
	case('menu.IsMenuOnStack', function()
		return Infinity_IsMenuOnStack('WORLD_ACTIONBAR'), Infinity_IsMenuOnStack('DIFFT_TICK'), Infinity_IsMenuOnStack('OPTIONS')
	end)
	case('menu.items.ESC_MENU', function()
		local m, n = EEex_Menu_Find('ESC_MENU'), 0
		local it = m and m.items
		while it ~= nil and n < 200 do n = n + 1 it = it.next end
		return n
	end)
	case('menu.FindItemByText', function()
		local r = EEex_Options_Private_FindItemByText(EEex_Menu_Find('ESC_MENU'), getUiString('RETURN_GAME_BUTTON'))
		return r ~= nil
	end)
	case('menu.CursorWithin', function() return type(EEex_Menu_IsCursorWithin('WORLD_ACTIONBAR', 'NOPE')) end)

	-- Actionbar
	case('actionbar.GetState', function() return EEex_Actionbar_GetState() end)
	case('actionbar.GetLastState', function() return EEex_Actionbar_GetLastState() end)
	case('actionbar.GetArray', function() return scrub(EEex_Actionbar_GetArray()) end)
	case('actionbar.ThievingHotkey', function() return EEex_Actionbar_IsThievingHotkeyOpeningSpecialAbilities() end)
	case('actionbar.ButtonType', function() return type(EEex_Actionbar_ButtonType) end)

	-- Selection
	case('sel.Selected', function() return spriteName(EEex_Sprite_GetSelected()) end)
	case('sel.SelectedID.isNumber', function() return type(EEex_Sprite_GetSelectedID()) end)
	case('sel.AllSelected', function()
		local out = {}
		for _, s in ipairs(EEex_Sprite_GetAllSelected() or {}) do out[#out + 1] = spriteName(s) end
		return out
	end)
	case('sel.AllSelectedIDs.count', function() local t = EEex_Sprite_GetAllSelectedIDs() return type(t), t and #t end)

	-- Options (the maintainer's priority): values seeded in Baldur.lua by run.ps1 and options registered at M_ load
	case('opt.registeredAtLoad', function() return DT.optLoad end)
	for point, snap in pairs(DT.optSnaps) do
		for k, v in pairs(snap) do case('opt.snap.' .. point .. '.' .. k, function() return v end) end
	end
	optSnapshot('4_suite')
	for k, v in pairs(DT.optSnaps['4_suite'] or {}) do case('opt.snap.4_suite.' .. k, function() return v end) end
	case('opt.ini.Pre0', function() return Infinity_GetINIValue('DiffTest', 'Pre0') end)
	case('opt.ini.PreStr', function() return Infinity_GetINIValue('DiffTest', 'PreStr') end)
	case('opt.ini.PreStr.strDefault', function() return Infinity_GetINIValue('DiffTest', 'PreStr', '') end)
	case('opt.ini.Pre7.strDefault', function() return Infinity_GetINIValue('DiffTest', 'Pre7', '') end)
	case('opt.ini.PreStr.numDefault', function() return Infinity_GetINIValue('DiffTest', 'PreStr', -5) end)
	case('opt.ini.GetINIString', function() return type(Infinity_GetINIString) end)
	case('opt.ini.GetINIString.values', function()
		return Infinity_GetINIString('DiffTest', 'Pre7', '#d'), Infinity_GetINIString('DiffTest', 'PreStr', '#d'),
			Infinity_GetINIString('DiffTest', 'Pre0', '#d'), Infinity_GetINIString('DiffTest', 'NoKey', '#d')
	end)
	case('opt.ini.Missing', function() return Infinity_GetINIValue('DiffTest', 'Missing') end)
	case('opt.ini.MissingDefault', function() return Infinity_GetINIValue('DiffTest', 'Missing', 5) end)
	case('opt.ini.MissingDefaultStr', function() return Infinity_GetINIValue('DiffTest', 'Missing', 'x') end)
	case('opt.ini.SadoQoL.StashTints', function() return Infinity_GetINIValue('SadoQoL', 'Stash Tints') end)
	case('opt.ini.SadoQoL.FPS', function() return Infinity_GetINIValue('SadoQoL', 'FPS') end)
	case('opt.ini.SadoQoL.Passive Traps', function() return Infinity_GetINIValue('SadoQoL', 'Passive Traps') end)
	case('opt.ini.SadoQoL.Auto Disarm', function() return Infinity_GetINIValue('SadoQoL', 'Auto Disarm') end)
	case('opt.SQOpt_On', function()
		if not SQOpt_On then return 'no SQOpt' end
		local out = {}
		for _, k in ipairs(SQ_KEYS) do out[k] = SQOpt_On(k) end
		return out
	end)
	case('opt.SQFps.on', function() return SQFps and SQFps.on end)
	case('opt.SQTrap.ENABLED', function() return SQTrap and SQTrap.ENABLED end)
	case('opt.set0', function()
		local o = EEex_Options_Get('DIFFT_Set')
		DT.phase = 'opt.set0'
		o:set(0)
		return o:get(), Infinity_GetINIValue('DiffTest', 'SetMe')
	end)
	case('opt.set5clamp', function()
		local o = EEex_Options_Get('DIFFT_Set')
		DT.phase = 'opt.set5'
		o:set(5)
		return o:get(), Infinity_GetINIValue('DiffTest', 'SetMe')
	end)
	case('opt.setSame', function()
		local o = EEex_Options_Get('DIFFT_Set')
		DT.phase = 'opt.setSame'
		o:set(o:get())
		return o:get()
	end)
	case('opt.Options_Set', function()
		DT.phase = 'opt.Options_Set'
		local r = EEex_Options_Set('DIFFT_SetNil', 0)
		return r, optGet('DIFFT_SetNil'), Infinity_GetINIValue('DiffTest', 'SetNil')
	end)
	case('opt.Options_Set.nil', function()
		DT.phase = 'opt.Options_Set.nil'
		local r = EEex_Options_Set('DIFFT_SetNil', nil)
		return r, optGet('DIFFT_SetNil')
	end)
	case('opt.Options_Set.unknown', function() return EEex_Options_Set('DIFFT_NoSuch', 1) end)
	case('opt.Get.unknown', function() return EEex_Options_Get('DIFFT_NoSuch') end)
	case('opt.onChange', function() return DT.onChange end)
	case('opt.lateRegister', function()
		Infinity_SetINIValue('DiffTest', 'Late', 0)
		EEex_Options_Register('DIFFT_Late', newOption(1, 'DiffTest', 'Late'))
		return optGet('DIFFT_Late')
	end)
	case('opt.registerTwice', function()
		local a = EEex_Options_Register('DIFFT_Twice', newOption(1, 'DiffTest', 'Twice'))
		local b = EEex_Options_Register('DIFFT_Twice', newOption(0, 'DiffTest', 'Twice'))
		return optGet('DIFFT_Twice'), a == b, type(a)
	end)
	case('opt.optionMethods', function()
		local o = EEex_Options_Get('DIFFT_Pre0')
		local out = {}
		for _, m in ipairs({ 'get', 'set', 'getDefault', 'read', 'write', 'clamp', 'getID', '_get', '_set' }) do
			local ok, t = pcall(function() return type(o[m]) end)
			out[m] = ok and t or 'error'
		end
		return out
	end)
	case('opt.getDefault', function() return EEex_Options_Get('DIFFT_Pre0'):getDefault() end)
	case('opt.accessor.clamp', function()
		local a = EEex_Options_ClampedAccessor.new({ ['min'] = 0, ['max'] = 3 })
		return a:clamp(-1), a:clamp(2), a:clamp(9)
	end)
	case('opt.storage.read', function()
		local s = EEex_Options_NumberLuaStorage.new({ ['section'] = 'DiffTest', ['key'] = 'Pre7' })
		return s:read()
	end)
	case('opt.storage.readMissing', function()
		local s = EEex_Options_NumberLuaStorage.new({ ['section'] = 'DiffTest', ['key'] = 'Missing2' })
		return s:read()
	end)
	case('opt.classes', function()
		local out = {}
		for _, c in ipairs({ 'EEex_Options_Option', 'EEex_Options_ToggleType', 'EEex_Options_ClampedAccessor',
			'EEex_Options_NumberLuaStorage', 'EEex_Options_DisplayEntry', 'EEex_Options_ToggleWidget',
			'EEex_Options_HorizontalMultiToggleWidget' }) do
			local v = _G[c]
			out[c] = type(v) == 'table' and type(v.new) or type(v)
		end
		return out
	end)

	-- INI values the base game uses
	case('ini.ActiveCampaign', function() return Infinity_GetINIValue('Program Options', 'Active Campaign') end)
	case('ini.MaxFrameRate', function() return Infinity_GetINIValue('Program Options', 'Maximum Frame Rate') end)

	-- Utility
	case('util.GetMicroseconds', function() return type(EEex_Utility_GetMicroseconds()) end)
	case('util.Once', function()
		local n = 0
		EEex_Once('DIFFT_once', function() n = n + 1 end)
		EEex_Once('DIFFT_once', function() n = n + 1 end)
		return n
	end)
	case('util.FlattenTable', function() return EEex_FlattenTable({ { 1, 2 }, { 3 } }) end)
	-- Values batch (2026-10-29): shapes the first run did not cover
	case('util.FlattenTable.nested', function()
		local r = EEex_FlattenTable({ { 1, { 2, 3 } }, 4, { { { 5 } } }, 'x' })
		local out = {}
		for i, v in ipairs(r) do out[i] = type(v) == 'table' and ('table#' .. #v) or v end
		return #r, out
	end)
	case('util.Flags', function() return EEex_Flags({ 0x1, 0x8, 0x8 }) end)
	case('util.TryGetUDAux', function()
		local before = EEex_TryGetUDAux(p1)
		EEex_GetUDAux(p1).DIFFT = 1
		return before == nil, EEex_TryGetUDAux(p1).DIFFT
	end)
	local function writeCase(name, fn, value)
		case('mem.' .. name, function()
			local m = EEex_Malloc(16)
			local ok, e = pcall(fn, m, value)
			local r = EEex_ReadU64(m)
			EEex_Free(m)
			if not ok then error(e, 0) end
			return r
		end)
	end
	writeCase('Write8.neg128', EEex_Write8, -128)
	writeCase('Write8.neg129', EEex_Write8, -129)
	writeCase('WriteU8.255', EEex_WriteU8, 255)
	writeCase('WriteU8.256', EEex_WriteU8, 256)
	writeCase('Write16.FFFF', EEex_Write16, 0xFFFF)
	writeCase('Write16.neg1', EEex_Write16, -1)
	writeCase('WriteU16.neg1', EEex_WriteU16, -1)
	writeCase('WriteU16.10000', EEex_WriteU16, 0x10000)
	writeCase('Write32.FFFFFFFF', EEex_Write32, 0xFFFFFFFF)
	writeCase('Write32.neg1', EEex_Write32, -1)
	writeCase('WriteU32.neg1', EEex_WriteU32, -1)
	writeCase('WriteU32.100000000', EEex_WriteU32, 0x100000000)
	writeCase('Write64.neg1', EEex_Write64, -1)
	writeCase('WriteU64.neg1', EEex_WriteU64, -1)
	case('mem.Memset', function()
		local m = EEex_Malloc(8)
		EEex_Memset(m, 0xAB, 3)
		local r = EEex_ReadU32(m)
		EEex_Free(m)
		return r
	end)
	case('mem.Memcpy', function()
		local a, b = EEex_Malloc(8), EEex_Malloc(8)
		EEex_Write32(a, 0x1234)
		EEex_Memcpy(b, a, 4)
		local r = EEex_ReadU32(b)
		EEex_Free(a) EEex_Free(b)
		return r
	end)
	case('mem.ReadPtr', function()
		local m = EEex_Malloc(8)
		EEex_WritePtr(m, 0x123456789)
		local r = EEex_ReadPtr(m)
		EEex_Free(m)
		return r
	end)
	case('mem.ImageBaseType', function() return type(EEex_GetImageBase()) end)
	for i = 0, 5 do
		case('P' .. i .. '.InnateSpells', function() return collect(40, EEex_Sprite_GetKnownInnateSpellsIterator(P(i))) end)
		case('P' .. i .. '.MageWithAbility', function()
			local out = {}
			for a, b, c, d, e in EEex_Sprite_GetKnownMageSpellsWithAbilityIterator(P(i), 1, 2) do
				out[#out + 1] = { a, b, c, d ~= nil, e ~= nil and field(e, 'minCasterLevel') }
				if #out >= 8 then break end
			end
			return out
		end)
		case('P' .. i .. '.CasterLevel.SPWI304.nil', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'SPWI304') end)
		case('P' .. i .. '.CasterLevel.SPPR304', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'SPPR304', false) end)
		case('P' .. i .. '.CasterLevel.missing', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'DIFFTNO', false) end)
		case('P' .. i .. '.CasterLevel.innate', function() return EEex_Sprite_GetCasterLevelForSpell(P(i), 'SPIN101', false) end)
		case('P' .. i .. '.field.m_mageSpecialization', function() return field(P(i), 'm_baseStats.m_mageSpecialization') end)
	end
	for _, t in ipairs({ 'KITLIST', 'HPCLASS', 'STRMOD' }) do
		local tag = '2da.' .. t
		case(tag .. '.getMaxIndices', function() return EEex_Resource_Load2DA(t):getMaxIndices() end)
		case(tag .. '.lastColumn', function()
			local a = EEex_Resource_Load2DA(t)
			local x = a:getDimensions()
			return a:getAtPoint(x - 1, 0), a:getAtPoint(x - 2, 0), a:getColumnLabel(x - 1), a:getColumnLabel(x)
		end)
		case(tag .. '.labelsOut', function()
			local a = EEex_Resource_Load2DA(t)
			return a:getColumnLabel(999), a:getColumnLabel(-1), a:getRowLabel(999), a:getRowLabel(-1)
		end)
		case(tag .. '.getAtLabels.empty', function() local a = EEex_Resource_Load2DA(t) return a:getAtLabels('', a:getRowLabel(0)) end)
		case(tag .. '.findColumnIndex.value', function() local a = EEex_Resource_Load2DA(t) return a:findColumnIndex(0, a:getAtPoint(0, 0)) end)
		case(tag .. '.findRowIndex.value', function() local a = EEex_Resource_Load2DA(t) return a:findRowIndex(0, a:getAtPoint(0, 2)) end)
		case(tag .. '.findRowIndex.lower', function() local a = EEex_Resource_Load2DA(t) return a:findRowIndex(0, string.lower(a:getAtPoint(0, 2))) end)
		case(tag .. '.findColumnLabel.lower', function() local a = EEex_Resource_Load2DA(t) return a:findColumnLabel(string.lower(a:getColumnLabel(0))) end)
		case(tag .. '.rowTable', function()
			local a = EEex_Resource_Load2DA(t)
			for row, label in a:getRowTableItr() do return row, label end
		end)
		case(tag .. '.rowColumns', function() return collect(3, EEex_Resource_Load2DA(t):getRowColumnsItr(nil, 0, 1)) end)
	end
	-- Whole tables the installed mods read (every point, labels and default), one case per row block
	for _, t in ipairs({ 'PDIALOG', 'REPUTATI', 'STRMODEX', 'WSPECIAL', 'KITLIST', 'RACETEXT', 'CLASTEXT', 'HPWAR',
			'STRMOD', 'HPCLASS' }) do
		case('2dadump.' .. t .. '.head', function()
			local a = EEex_Resource_Load2DA(t)
			local x, y = a:getDimensions()
			local labels = {}
			for i = 0, x - 1 do labels[#labels + 1] = a:getColumnLabel(i) end
			return x, y, a:getDefault(), labels
		end)
		local a0 = EEex_Resource_Load2DA(t)
		local _, rows = a0:getDimensions()
		for b = 0, math.min(rows - 1, 200), 20 do
			case('2dadump.' .. t .. '.rows' .. b, function()
				local a = EEex_Resource_Load2DA(t)
				local x, y = a:getDimensions()
				local out = {}
				for r = b, math.min(b + 19, y - 1) do
					local cells = { a:getRowLabel(r) }
					for c = 0, x - 1 do cells[#cells + 1] = a:getAtPoint(c, r) end
					out[#out + 1] = table.concat(cells, '|')
				end
				return out
			end)
		end
	end
	case('2da.KITLIST.rowLabelCase', function() return EEex_Resource_Load2DA('KITLIST'):getRowLabel(1) end)
	case('res.SPWI112.missileType', function()
		local a = EEex_Resource_GetSpellAbility(EEex_Resource_Demand('SPWI112', 'SPL'), 0)
		return field(a, 'missileType'), field(a, 'castingTime'), field(a, 'location')
	end)
	case('res.SW1H01.attackProbability.get0', function()
		local a = EEex_Resource_GetItemAbility(EEex_Resource_Demand('SW1H01', 'ITM'), 0)
		local p = a.attackProbability
		return p:get(0), p:get(1), p:get(2)
	end)
	case('res.SW1H01.attackProbability.getNone', function()
		local a = EEex_Resource_GetItemAbility(EEex_Resource_Demand('SW1H01', 'ITM'), 0)
		return a.attackProbability:get()
	end)
	case('res.SPWI112.headerMore', function()
		local h = EEex_Resource_Demand('SPWI112', 'SPL')
		return field(h, 'completionSound'), field(h, 'castingSound'), field(h, 'genericDescription'), field(h, 'spellIcon')
	end)
	case('global.notEEex.type', function() return type(EEex_DiffT_NotAName) end)
	for _, res in ipairs({ 'SW1H01', 'BOW01', 'RING06', 'PLAT01', 'STAF01' }) do
		case('res.' .. res .. '.requirements', function()
			local h = EEex_Resource_Demand(res, 'ITM')
			local out = {}
			for _, f in ipairs({ 'minSTRRequired', 'minSTRBonusRequired', 'minINTRequired', 'minDEXRequired',
					'minWISRequired', 'minCONRequired', 'minCHRRequired', 'notUsableBy2a', 'notUsableBy2b',
					'notUsableBy2c', 'notUsableBy2d', 'proficiencyType', 'weaponProficiency' }) do
				local ok, v = pcall(field, h, f)
				out[f] = ok and v or errText(v)
			end
			return out
		end)
	end
	for _, n in ipairs({ 'EEex_Keybinds_FireType', 'EEex_Projectile_Type', 'EEex_LuaCallReturnType',
			'EEex_HookIntegrityWatchdogRegister' }) do
		case('enum.' .. n, function()
			local t = rawget(_G, n)
			if type(t) ~= 'table' then return type(t) end
			local out = {}
			for k, v in pairs(t) do if type(v) ~= 'table' and type(v) ~= 'function' then out[tostring(k)] = v end end
			return out
		end)
	end
	case('keybinds.GetMissing', function() return EEex_Keybinds_Get('DIFFT_none') end)
	case('keybinds.Update', function()
		EEex_Keybinds_Update('DIFFT_kb', { keys = { 0x61 }, modifierKeys = {}, callback = function() end })
		local k = EEex_Keybinds_Get('DIFFT_kb')
		local fields = {}
		for name, v in pairs(k or {}) do fields[#fields + 1] = name .. ':' .. type(v) end
		table.sort(fields)
		local r = { fields, EEex_Keybinds_IsSatisfied('DIFFT_kb') }
		EEex_Keybinds_Reset('DIFFT_kb')
		EEex_Keybinds_Private_Definitions.DIFFT_kb = nil
		return r
	end)
	case('menu.GetItemVariant.ESC', function()
		local menu = EEex_Menu_Find('ESC_MENU')
		local item = menu and menu.items
		if not item then return 'no item' end
		return type(EEex_Menu_GetItemVariant(item.enabled))
	end)
	case('util.ChainItrs', function()
		local function itr(t) local i = 0 return function() i = i + 1 return t[i] end end
		return collect(10, EEex_Utility_ChainItrs(itr({ 1, 2 }), itr({ 3 })))
	end)

	-- (hooks pass) hook globals as EEex defines them before mods load; projectile enums; script levels
	case('hooks.types', function() return DT.hookTypes end)
	case('proj.Type', function() return EEex_Projectile_Type end)
	case('proj.DecodeSource', function() return EEex_Projectile_DecodeSource end)
	case('proj.AddEffectSource', function() return EEex_Projectile_AddEffectSource end)
	case('marshal.handlersTable', function()
		local t = EEex_Sprite_Private_MarshalHandlers
		local h = t and t.DIFFTM
		return type(t), h and type(h.exporter), h and type(h.importer)
	end)
	case('marshal.importsAtLoad', function() return DT.marshal.imports end)
	for lvl = 0, 7 do
		case('script.level' .. lvl, function() return EEex_AIBase_GetScriptLevelResRef(p1, lvl) end)
	end
	case('script.method', function() return p1:getScriptLevelResRef(0) end)
	case('field.effect.m_sourceTarget', function()
		local found
		EEex_Utility_IterateCPtrList(p0.m_timedEffectList, function(e) if found == nil then found = e.m_sourceTarget end end)
		return found
	end)
	case('field.gameOptions', function() return type(gameOptions) end)
	case('field.gameOptions.m_bConfirmDialog', function() return gameOptions.m_bConfirmDialog end)
	case('field.gameOptions.m_bRenderFrameTimes', function() return gameOptions.m_bRenderFrameTimes end)

	-- Settings: EEex.ini modules, loader Lua mode, options API shape (both sides; differences are findings)
	case('settings.EEex_Modules', function() return EEex_Modules end)
	case('settings.emptyContainerHook', function() return type(B3EmptyContainer_Hook_OnBeforeContainerOutlineRender) end)
	case('settings.luaLibs', function()
		return { io = type(io), os = type(os), package = type(package), jit = type(jit), bit = type(bit),
			sethook = type(debug) == 'table' and type(debug.sethook) or 'none',
			traceback = type(debug) == 'table' and type(debug.traceback) or 'none', version = _VERSION }
	end)
	for _, c in ipairs({ 'EEex_Options_Option', 'EEex_Options_Private_Storage', 'EEex_Options_Widget',
		'EEex_Options_ToggleWidget', 'EEex_Options_DisplayEntry', 'EEex_Options_NumberLuaStorage',
		'EEex_Options_ClampedAccessor', 'EEex_Options_ToggleType', 'EEex_Options_HorizontalMultiToggleWidget',
		'EEex_Options_Private_INIStorage', 'EEex_Options_Private_LuaStorage', 'EEex_Options_EditWidget',
		'EEex_Options_KeybindWidget', 'EEex_Options_EditType', 'EEex_Options_KeybindType',
		'EEex_Options_StringLuaStorage', 'EEex_Options_NumberINIStorage', 'EEex_Options_StringINIStorage',
		'EEex_Options_KeybindLuaStorage', 'EEex_Options_Accessor', 'EEex_Options_Type', 'EEex_Options_ParentWidget' }) do
		case('settings.classKeys.' .. c, function() return classKeys(_G[c]) end)
	end
	case('settings.optionInstanceKeys', function()
		local o = EEex_Options_Get('DIFFT_Pre0')
		local keys = {}
		for k, v in pairs(o) do if type(k) == 'string' then keys[#keys + 1] = k .. ':' .. type(v) end end
		table.sort(keys)
		return keys
	end)
	case('settings.customStorage.get', function()
		local o = EEex_Options_Get('DIFFT_Custom')
		if not o then return 'no option' end
		return o:get()
	end)
	case('settings.customStorage.set', function()
		local o = EEex_Options_Get('DIFFT_Custom')
		if not o then return 'no option' end
		o:set(4)
		return o:get()
	end)
	case('settings.customStorage.calls', function() return DT.storageCalls end)
	case('settings.canReadEarly', function()
		local s = EEex_Options_Private_Storage
		if type(s) ~= 'table' or type(s.canReadEarly) ~= 'function' then return type(s) end
		local n = EEex_Options_NumberLuaStorage.new({ ['section'] = 'DiffTest', ['key'] = 'Pre0' })
		return s.canReadEarly(s), type(n.canReadEarly) == 'function' and n:canReadEarly() or type(n.canReadEarly)
	end)
	case('settings.option._getDefault', function()
		local o = EEex_Options_Get('DIFFT_Pre0')
		return type(o._getDefault) == 'function' and o:_getDefault() or type(o._getDefault)
	end)
	case('settings.option._read', function()
		local o = EEex_Options_Get('DIFFT_Pre7')
		return type(o._read) == 'function' and o:_read() or type(o._read)
	end)
	case('settings.layout.ESC_MENU', function() return menuLayout('ESC_MENU') end)

	-- Generated cases (M_DIFFTA.lua, from the inventory): { name, function }
	for _, c in ipairs(DiffT_GeneratedCases or {}) do case('gen.' .. c[1], c[2]) end
	case('state.end', gameState)
end
DT.runCases = runCases

-----------------------------------------------------------------------
-- Listeners (registered at M_ load: no engine calls, only registrations)
-----------------------------------------------------------------------

listen('EEex_Menu_AddMainFileLoadedListener')
listen('EEex_Menu_AddAfterMainFileReloadedListener')
listen('EEex_Menu_AddAfterMainFileLoadedListener')
listen('EEex_Menu_AddTranslationLoadedListener')
listen('EEex_Menu_AddWindowSizeChangedListener')
listen('EEex_GameState_AddInitializedListener')
listen('EEex_GameState_AddDestroyedListener')
listen('EEex_Sprite_AddLoadedListener')
listen('EEex_Key_AddPressedListener')
listen('EEex_Key_AddReleasedListener')
listen('EEex_Actionbar_AddListener')
listen('EEex_Actionbar_AddButtonsUpdatedListener')
listen('EEex_Action_AddSpriteStartedActionListener')
listen('EEex_Opcode_AddListsResolvedListener')
listen('EEex_Sprite_AddQuickListCountsResetListener')
listen('EEex_Sprite_AddQuickListNotifyRemovedListener')
listen('EEex_Sprite_AddQuickListsCheckedListener')
listen('EEex_Sprite_AddSpellDisableStateChangedListener')
listen('EEex_Sprite_AddBlockWeaponHitListener')
listen('EEex_Sprite_AddAlterBaseWeaponDamageListener')
-- (2026-10-29 hooks pass) listeners IEX lacked, and ones that take a name first
listen('EEex_AIBase_AddScriptingObjectUpdatedListener')
listen('EEex_Opcode_AddDeferredListsResolvedListener')
listen('EEex_Menu_AddBeforeMainFileLoadedListener')
listen('EEex_Menu_AddBeforeMainFileReloadedListener')
listen('EEex_Action_AddSpriteStartedNextActionListener')
listen('EEex_Menu_AddBeforeListRendersItemListener', 'DIFFTLIST')
listen('EEex_Menu_AddBeforeUIItemRenderListener', 'DIFFTLABEL')
listen('EEex_Action_AddEnabledSpriteStartedActionListener', 'DIFFTEN')

-- Details of the loaded sprites (when exactly the listener runs: name / resref / area set yet?)
pcall(EEex_Sprite_AddLoadedListener, function(s)
	local function f(fn) local ok, v = pcall(fn) if ok then return v end return 'ERR' end
	record('LoadedDetail', f(function() return s.m_resref:get() end), f(function() return s.m_pArea ~= nil end),
		f(function() return s.m_id ~= -1 end), f(function() return EEex_Sprite_GetName(s) end))
end)

-- Started action: is `action` the sprite's current action already (listener after the engine's copy)?
pcall(EEex_Action_AddSpriteStartedActionListener, function(s, a)
	local function f(fn) local ok, v = pcall(fn) if ok then return v end return 'ERR' end
	record('StartedDetail', f(function() return a.m_actionID end), f(function() return s.m_curAction.m_actionID end),
		f(function() return EEex_UDEqual and EEex_UDEqual(a, s.m_curAction) end))
end)

-- Engine hooks EEex calls by global name (mods replace them): wrapped at M_ load, the original (if any) still runs.
DT.hookTypes = {}
DT.HOOKS = { 'EEex_Actionbar_Hook_HasFullThieving', 'EEex_Menu_Hook_OnBeforeUIItemRender',
	'EEex_Menu_LuaHook_BeforeListRenderingItem', 'EEex_Menu_Hook_BeforeListRenderingItem',
	'EEex_Opcode_Hook_OnAfterSwingCheckedOp248', 'EEex_Opcode_Hook_OnAfterSwingCheckedOp249',
	'EEex_OnDecodeProjectile', 'EEex_OnPostProjectileCreation', 'EEex_OnAddEffectToProjectile',
	'EEex_Sprite_Hook_OnDestruct', 'EEex_GameObject_Hook_OnDeleting', 'EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled',
	'EEex_AIBase_LuaHook_OnScriptingObjectUpdated' }
for _, name in ipairs(DT.HOOKS) do
	local orig = rawget(_G, name)
	DT.hookTypes[name] = type(orig)
	_G[name] = function(...)
		pcall(record, 'hook.' .. name, ...)
		if orig then return orig(...) end
	end
end

-- Marshal handlers (per-creature data in saves): exporter / importer calls are recorded.
DT.marshal = { exports = 0, imports = {} }
pcall(EEex_Sprite_AddMarshalHandlers, 'DIFFTM', function(sprite)
	DT.marshal.exports = DT.marshal.exports + 1
	pcall(record, 'marshal.export', sprite)
	local data = DT.marshalData and DT.marshalData[spriteName(sprite) or ''] or nil
	if DT.exportLog then
		local okC, copy = pcall(function() return EEex.IsMarshallingCopy() end)
		DT.exportLog[#DT.exportLog + 1] = tostring(spriteName(sprite)) .. ':' .. type(data) .. (okC and (':copy=' .. tostring(copy)) or '')
	end
	return data
end, function(sprite, data)
	pcall(record, 'marshal.import', sprite, type(data))
	DT.marshal.imports[#DT.marshal.imports + 1] = { spriteName(sprite), data }
end)

-- Projectile mutators (opcode 408 'DIFFTPM' and a global one): contexts recorded.
local function ctxSummary(c)
	local out = {}
	for k, v in pairs(c or {}) do out[k] = argSummary(v) end
	pcall(function() if c.projectile then out.type = EEex_Projectile_GetType(c.projectile) end end)
	pcall(function() if c.projectile then out.isCProjectile = EEex_Projectile_IsOfType(c.projectile, EEex_Projectile_Type.CProjectile) end end)
	return scrub(ser(out))
end
for _, gname in ipairs({ 'DIFFTPM', 'DIFFTGM' }) do
	_G[gname] = {
		typeMutator = function(c) pcall(record, 'mut.' .. gname .. '.type', ctxSummary(c)) end,
		projectileMutator = function(c) pcall(record, 'mut.' .. gname .. '.projectile', ctxSummary(c)) end,
		effectMutator = function(c) pcall(record, 'mut.' .. gname .. '.effect', ctxSummary(c)) end,
	}
end
pcall(EEex_Projectile_RegisterGlobalMutator, 'DIFFTGM')

-- Opcode 402 targets used by the opcode steps
function DIFFT402(effect, sprite) pcall(record, 'op402', sprite, effect) end

difftListRows = { 'a', 'b' }
function DiffT_ListText(row) return '' end

-----------------------------------------------------------------------
-- Driving: start screen -> load -> world -> cases -> events -> done
-----------------------------------------------------------------------

DT.frames = 0
DT.state = 'boot'

local function now() return Infinity_GetClockTicks() end

local function writeEvents()
	DT.lines[#DT.lines + 1] = nil
	for _, ev in ipairs(DT.events) do
		local name = 'event.' .. string.format('%03d', ev.seq) .. '.' .. ev.phase .. '.' .. ev.name .. '#' .. ev.n
		emit(name, '"r":[' .. ser(ev.args) .. ']')
	end
	-- Per phase counts (order independent)
	local keys = {}
	for k in pairs(DT.eventCounts) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do emit('eventcount.' .. k, '"r":[' .. num(DT.eventCounts[k]) .. ']') end
	-- Order of first calls: listener names in the order first seen
	local order, seen = {}, {}
	for _, ev in ipairs(DT.events) do
		local k = ev.phase .. ':' .. ev.name
		if not seen[k] then seen[k] = true order[#order + 1] = k end
	end
	emit('eventorder', '"r":[' .. ser(order) .. ']')
end

-- Event triggers after the cases: each step runs once, then waits some frames.
local STEPS = {
	{ 'select1', function() Infinity_OnPortraitLClick(1) end },
	{ 'select0', function() Infinity_OnPortraitLClick(0) end },
	{ 'actionbarState', function() EEex_Actionbar_SetState(EEex_Actionbar_GetState()) end },
	{ 'queueAction', function()
		EEex_Action_QueueResponseStringOnAIBase('SetGlobal("DIFFT_Q","GLOBAL",1)', P(0))
	end },
	{ 'escOpen', function() Infinity_PushMenu('ESC_MENU') end, hold = true,
		check = function() case('step.escOpen.layout', function() return menuLayout('ESC_MENU') end) end },
	{ 'escClose', function() Infinity_PopMenu('ESC_MENU') end },
	{ 'optionsOpen', function()
		DT.optMenus = recordPushes(function() EEex_Options_Open() end)
	end, hold = true, check = function()
		case('step.optionsOpen.pushed', function() return DT.optMenus end)
		case('step.optionsOpen.onStack', function() return DT.menuNamesOnStack() end)
		for _, name in ipairs(DT.optMenus) do
			case('step.optionsOpen.layout.' .. name, function() return menuLayout(name, 400) end)
		end
	end },
	{ 'optionsClose', function() EEex_Options_Close() end, check = function()
		case('step.optionsClose.onStack', function()
			local out = {}
			for _, name in ipairs(DT.optMenus) do out[name] = Infinity_IsMenuOnStack(name) and true or false end
			return out
		end)
	end },
	{ 'after', function() end },
	-- (hooks pass) EEex opcodes and the listeners / hooks they drive
	{ 'op409', function()
		local s = P(0)
		s:applyEffect({ effectID = 409, durationType = 0, duration = 60, effectAmount = 1, res = 'DIFFTEN',
			sourceID = s.m_id, sourceTarget = s.m_id })
	end },
	{ 'queueAction2', function()
		EEex_Action_QueueResponseStringOnAIBase('SetGlobal("DIFFT_Q2","GLOBAL",1)', P(0))
	end },
	-- (opcodes 404-407 are not applied: EEex 1.3.1 crashed natively in DecodeEffect on one of them, 2026-10-29)
	{ 'op408', function()
		local s = P(0)
		s:applyEffect({ effectID = 408, durationType = 0, duration = 60, res = 'DIFFTPM',
			sourceID = s.m_id, sourceTarget = s.m_id })
	end },
	{ 'cast', function()
		EEex_Action_QueueResponseStringOnAIBase('ReallyForceSpellRES("SPWI112",Player2)', P(0))
	end },
	{ 'castWait', function() end },
	{ 'castWait2', function() end },
	{ 'summon', function()
		EEex_Action_QueueResponseStringOnAIBase('CreateCreatureObject("DOGWAR",Myself,0,0,0)', P(0))
	end },
	{ 'unsummon', function()
		if DT.summoned then EEex_Action_QueueResponseStringOnAIBase('DestroySelf()', DT.summoned) end
	end },
	-- marshal handlers: per-creature data written into a save (the next run can load it, run.ps1 -SaveName)
	{ 'marshalSave', function()
		DT.marshalData = {}
		for i = 0, 1 do
			local n = spriteName(P(i))
			if n then DT.marshalData[n] = { num = 42 + i, str = 'DiffT ' .. n, list = { 1, 2, 3 }, nested = { a = 'x', b = 7 } } end
		end
		DT.status('savekey (quick save from the F11 key)')
	end, 3000 },
	{ 'marshalSaved', function() DT.status('saved?') end },
	{ 'marshalSaved2', function() end },
	{ 'keytest', function() DT.status('keytest (F10 down, repeat, up)') end },
	{ 'keytest2', function() end },
	{ 'keytest3', function() end },
	{ 'keytest4', function() end },
	-- last: EEex crashed the engine around the end of this 400 effect in the first runs
	{ 'op400', function()
		-- the listener records so far are written now, in case the engine dies in the 400 steps
		pcall(writeEvents)
		DT.eventsWritten = true
		DT.flush()
		local s = P(1)
		s:applyEffect({ effectID = 400, durationType = 0, duration = 2, dwFlags = 0, res = 'DPLAYER3',
			sourceID = s.m_id, sourceTarget = s.m_id })
	end },
	{ 'op400b', function() end },
	{ 'op400c', function() end },
	{ 'op400d', function() end },
	{ 'op400e', function() end },
	{ 'op400f', function() end },
	{ 'op400wait', function() end, 5000 },
	{ 'afterAll', function() DT.status('steps done') end },
}

-- Focus steps (run.ps1 -Focus a,b,c): only the named steps run, the cases are skipped. A step that needs an input
-- context sets DT.keyAction and a 'savekey ...' status: the runner then sends F11 and the key listener runs it once.
-- Saves from the save screen as its 'new save' button does; never called on another screen (the engine reads the
-- save screen's slot list: empty elsewhere, native crash).
function DT.saveNamed(name)
	if e:GetActiveEngine() ~= saveScreen then
		emit('focus.save.' .. name, '"err":"not on the save screen"')
		return
	end
	DT.exportLog = {}
	saveScreen:SaveGame(#gameSaves.files, name)
end
-- One probe save deleted per key press (the slot list is rebuilt after each delete). DIFFTEST (the loaded save)
-- is kept.
function DT.cleanStep()
	if e:GetActiveEngine() ~= saveScreen then
		emit('focus.clean.' .. DT.phase, '"err":"not on the save screen"')
		return
	end
	for _, f in ipairs(gameSaves and gameSaves.files or {}) do
		local n = tostring(f.slotName or '') .. '|' .. tostring(f.fileName or '')
		if n:find('DIFFT', 1, true) and not n:find('DIFFTEST', 1, true) then
			local slot = f.slotIndex
			DT.keyAction = function()
				saveScreen:DeleteGame(slot)
				emit('focus.clean.deleted', '"r":[' .. jstr(n) .. ']')
			end
			DT.flush()
			DT.status('savekey delete ' .. n)
			return
		end
	end
	emit('focus.clean.' .. DT.phase, '"r":["nothing left"]')
end
local function keyStep(label, fn)
	DT.flush()
	DT.keyAction = fn
	DT.status('savekey ' .. label)
end
-- Values EEex 1.3.1 round-trips (its signed writer picks a too-narrow width for -129..-256, -32769..-65536 and
-- -2^31-1..-2^32: one such value corrupted every creature's block in the save, 2026-10-29).
local MARSHAL_SAMPLE = {
	str = 'DiffT string', empty = '', yes = true, no = false,
	u8 = 200, u16 = 60000, u32 = 4000000000, u64 = 2 ^ 40, zero = 0, one = 1,
	s8 = -100, s16 = -300, s32 = -100000, s64 = -5000000000,
	list = { 10, 20, 30 }, nested = { a = 'x', b = { c = 7 } }, emptyt = {},
	[5] = 'five', [-3] = 'minus three', [1000] = 'k1000',
}
DT.MARSHAL_BY_NAME = { Imoen = { long = string.rep('abcdefghij', 40) }, Yoshimo = {} }
DT.FOCUS_STEPS = {
	-- marshal handlers: a save without handler data, then the same save with data (diffed by tools/difftest)
	{ 'msaveOpenA', function()
		DT.marshalData = nil
		keyStep('open save screen (no data)', function() optionsScreen:SaveGame(0) end)
	end, 8000 },
	{ 'msaveA', function()
		case('focus.msaveOpenA.popupStrref', function() return TEXT_popup_info, TEXT_popup_info and Infinity_FetchString(TEXT_popup_info) end)
		case('focus.msaveOpenA.dialogOpen', function() return Infinity_IsMenuOnStack('WORLD_DIALOG') end)
		case('focus.msaveOpenA.saveScreenActive', function() return e:GetActiveEngine() == saveScreen end)
		keyStep('save (no data)', function() DT.saveNamed('DIFFTNONE') end)
	end, 8000 },
	{ 'msaveOpenB', function()
		case('focus.msaveA.exports', function() return DT.exportLog end)
		DT.marshalData = {}
		local names = {}
		for i = 0, 3 do names[i] = spriteName(P(i)) end
		if names[0] then DT.marshalData[names[0]] = MARSHAL_SAMPLE end
		for n, v in pairs(DT.MARSHAL_BY_NAME) do DT.marshalData[n] = v end
		case('focus.msaveOpenB.names', function() return names end)
		keyStep('open save screen (data)', function() optionsScreen:SaveGame(0) end)
	end, 8000 },
	{ 'msaveB', function()
		case('focus.msaveOpenB.saveScreenActive', function() return e:GetActiveEngine() == saveScreen end)
		keyStep('save (data)', function() DT.saveNamed('DIFFTDATA') end)
	end, 8000 },
	{ 'msaveDone', function()
		case('focus.msaveB.exports', function() return DT.exportLog end)
		case('focus.msaveB.worldActive', function() return e:GetActiveEngine() == worldScreen end)
	end },
	-- removes the probe's own saves (DIFFTNONE / DIFFTDATA...) through the save screen, which also deletes their
	-- Steam Cloud copies (a copy connected to Steam uploads every save it writes)
	{ 'cleanOpen', function()
		keyStep('open save screen (clean)', function() optionsScreen:SaveGame(0) end)
	end, 8000 },
	{ 'clean1', function() DT.cleanStep() end, 6000 },
	{ 'clean2', function() DT.cleanStep() end, 6000 },
	{ 'clean3', function() DT.cleanStep() end, 6000 },
	{ 'clean4', function() DT.cleanStep() end, 6000 },
	{ 'clean5', function() DT.cleanStep() end, 6000 },
	{ 'clean6', function() DT.cleanStep() end, 6000 },
	{ 'clean7', function() DT.cleanStep() end, 6000 },
	{ 'clean8', function() DT.cleanStep() end, 6000 },
	{ 'cleanDone', function()
		case('focus.clean.left', function()
			local left = {}
			for _, f in ipairs(gameSaves and gameSaves.files or {}) do left[#left + 1] = tostring(f.slotName) end
			return left
		end)
	end },
	-- listener records so far (event.* / eventcount.* lines) and a few fields, for short focus runs
	{ 'fields', function()
		case('focus.effect.m_sourceTarget', function()
			local found
			EEex_Utility_IterateCPtrList(P(0).m_timedEffectList, function(e) if found == nil then found = e.m_sourceTarget end end)
			return found
		end)
	end },
	{ 'arrays', function() arrayCases() end },
	{ 'events', function() pcall(writeEvents) DT.eventsWritten = true end },
	-- after loading a save made with data (run.ps1 -SaveFrom <run output>): what the importer got
	{ 'mimports', function()
		case('focus.mimports', function() return DT.marshal.imports end)
		case('focus.mimportCount', function() return #DT.marshal.imports end)
	end },
}
for _, st in ipairs(DT.FOCUS_STEPS) do st.focusOnly = true; STEPS[#STEPS + 1] = st end
local function focused()
	if type(DiffT_Focus) ~= 'table' or #DiffT_Focus == 0 then return nil end
	local set = {}
	for _, n in ipairs(DiffT_Focus) do set[n] = true end
	return set
end
-- Step list for this run, filtered once the world is up (M_DIFFTA.lua with DiffT_Focus loads after this file).
local function filterSteps()
	local f = focused()
	local out = {}
	for _, st in ipairs(STEPS) do
		if (f and f[st[1]]) or (not f and not st.focusOnly) then out[#out + 1] = st end
	end
	for i = #STEPS, 1, -1 do STEPS[i] = nil end
	for i, st in ipairs(out) do STEPS[i] = st end
	return f ~= nil
end

-- Remembers the summoned dog (unsummon step).
pcall(EEex_Sprite_AddLoadedListener, function(s)
	pcall(function() if s.m_resref:get() == 'DOGWAR' then DT.summoned = s end end)
end)

local function tickWorld()
	if DT.state == 'msteps' then return DT.moduleTick() end
	if DT.state == 'world' then
		if EEex_Area_GetVisible() == nil then return end
		DT.worldFrames = (DT.worldFrames or 0) + 1
		if DT.worldFrames < 60 or now() - (DT.worldAt or now()) < 3000 then return end
		-- with run.ps1 -HoldMs: a first hold on the untouched world (the cases change the game, e.g. reputation)
		if not DT.worldHoldDone then
			local hold = tonumber(Infinity_GetINIValue('DiffTest', 'HoldMs', 0)) or 0
			if hold > 0 then
				if not DT.holdUntil then
					DT.holdUntil = now() + hold
					DT.status('hold world')
				end
				if now() < DT.holdUntil then return end
				DT.holdUntil = nil
			end
			DT.worldHoldDone = true
		end
		if tonumber(Infinity_GetINIValue('DiffTest', 'Modules', 0)) == 1 then
			DT.holdMs = tonumber(Infinity_GetINIValue('DiffTest', 'HoldMs', 0)) or 0
			DT.state = 'msteps'
			return
		end
		if filterSteps() then
			-- focus run: no cases, straight to the chosen steps
			DT.phase = 'cases_done'
			DT.step, DT.stepFrames = 0, 0
			DT.state = 'steps'
			case('focus.steps', function() local n = {} for i, s in ipairs(STEPS) do n[i] = s[1] end return n end)
			case('focus.dialog', function()
				local ch = {}
				for i, r in ipairs(worldPlayerDialogChoices or {}) do ch[i] = tostring(r.text):sub(1, 60) end
				return Infinity_IsMenuOnStack('WORLD_DIALOG'), tostring(worldNPCDialogText):sub(1, 200), ch
			end)
			case('focus.party', function()
				local n = 0
				for i = 0, 9 do if P(i) ~= nil then n = n + 1 end end
				return n
			end)
			return
		end
		DT.state = 'cases'
		DT.phase = 'cases'
		DT.status('running cases')
		local ok, err = pcall(runCases)
		if not ok then emit('probe.runCases', '"err":' .. jstr(errText(err))) end
		DT.flush()
		DT.inDeferred = true
		for _, d in ipairs(DT.deferred) do
			pcall(case, d[1], d[2], unpackAll(d[3], 1, d[3].n))
		end
		DT.inDeferred = false
		print('DIFFT|TRACE (deferred done)')
		DT.phase = 'cases_done'
		DT.flush()
		DT.step, DT.stepFrames = 0, 0
		DT.holdMs = tonumber(Infinity_GetINIValue('DiffTest', 'HoldMs', 0)) or 0
		DT.state = 'steps'
		return
	end
	if DT.state == 'steps' then
		DT.stepFrames = DT.stepFrames + 1
		local cur = STEPS[DT.step]
		if DT.step > 0 and cur and cur[3] then
			if now() - (DT.stepAt or 0) < cur[3] then return end  -- this step waits a time (ms), not 20 frames
		elseif DT.step > 0 and DT.stepFrames < 20 then return end
		-- a step with hold = true stays up HoldMs ([DiffTest] HoldMs in Baldur.lua, set by run.ps1 -HoldMs) so the
		-- runner can take a screenshot (status 'hold <step>')
		if cur and cur.hold and (DT.holdMs or 0) > 0 then
			if not DT.holdUntil then
				DT.holdUntil = now() + DT.holdMs
				DT.status('hold ' .. cur[1])
			end
			if now() < DT.holdUntil then return end
			DT.holdUntil = nil
			DT.status('steps')
		end
		if DT.step > 0 then
			-- what the step changed
			local name = STEPS[DT.step][1]
			if cur.check then pcall(cur.check) end
			case('step.' .. name .. '.selected', function() return spriteName(EEex_Sprite_GetSelected()) end)
			case('step.' .. name .. '.actionbarState', function() return EEex_Actionbar_GetState() end)
			case('step.' .. name .. '.DIFFT_Q', function() return EEex_GameState_GetGlobalInt('DIFFT_Q') end)
			-- frames per game tick differ between sides (frame rate): per-frame listener counts depend on it
			case('timing.step.' .. name .. '.msPer20Frames', function() return now() - (DT.stepAt or now()) end)
			if DT.step >= 6 then
				case('step.' .. name .. '.DIFFT_Q2', function() return EEex_GameState_GetGlobalInt('DIFFT_Q2') end)
				case('step.' .. name .. '.scriptL0', function() return EEex_AIBase_GetScriptLevelResRef(P(1), 0) end)
				case('step.' .. name .. '.marshalExports', function() return DT.marshal.exports end)
				case('step.' .. name .. '.opcounts', function()
					local out = {}
					for i = 0, 2 do
						EEex_Utility_IterateCPtrList(P(i).m_timedEffectList, function(e)
							local op = e.m_effectId
							if op >= 400 and op <= 409 then
								local k = 'p' .. i .. '.' .. op
								out[k] = (out[k] or 0) + 1
							end
						end)
					end
					return out
				end)
			end
		end
		DT.step = DT.step + 1
		DT.stepFrames = 0
		local st = STEPS[DT.step]
		if not st then
			DT.state = 'done'
			DT.phase = 'done'
			if not DT.eventsWritten then pcall(writeEvents) end
			case('probe.frames', function() return DT.frames > 0 end)
			DT.flush()
			DT.status('DONE ' .. #DT.lines)
			return
		end
		DT.phase = st[1]
		DT.stepAt = now()
		-- steps that crashed the engine natively are in skip.txt as 'step:<name>' (run.ps1 adds them from this TRACE)
		-- the 400 steps crashed EEex natively (8 popups 2026-10-29, in print during op400wait / afterAll): IEX only
		if (DiffT_Skip or {})['step:' .. st[1]] or (not IEX_Log and st[1]:find('^op400')) then
			emit('step.' .. st[1] .. '.trigger', '"skip":"crashes the engine under EEex (skip.txt)"')
			return
		end
		DT.flush()
		print('DIFFT|TRACE step:' .. st[1])
		local ok, err = pcall(st[2])
		if not ok then emit('step.' .. st[1] .. '.trigger', '"err":' .. jstr(errText(err))) end
	end
end

-- The start / load steps run from a key press (input context, like a button click), never from a render
-- callback: loading a save from inside a menu's render crashed the engine. The runner sends the key (F11)
-- in the background; the render wrappers only report that the screen is up.
local function tickStart()
	if DT.state ~= 'boot' then return end
	DT.startFrames = (DT.startFrames or 0) + 1
	if DT.startFrames == 30 then DT.status('start screen ready') end
end
local function keyStart()
	if DT.state ~= 'boot' or (DT.startFrames or 0) < 30 then return end
	DT.state = 'loadscreen'
	DT.phase = 'loadscreen'
	DT.status('opening load screen')
	local ok, err = pcall(function() startEngine:OnLoadGameButtonClick() end)
	if not ok then DT.status('load screen error ' .. tostring(err)) end
end

local function tickLoad()
	if DT.state ~= 'loadscreen' then return end
	DT.loadFrames = (DT.loadFrames or 0) + 1
	if DT.loadFrames == 10 then DT.status('load screen ready') end
end
local function keyLoad()
	if DT.state ~= 'loadscreen' or (DT.loadFrames or 0) < 10 then return end
	local files = gameSaves and gameSaves.files or {}
	local names = {}
	for _, f in ipairs(files) do
		local label = tostring(f.slotName or '') .. '|' .. tostring(f.fileName or '')
		names[#names + 1] = label
		if label:find(DT.SAVE, 1, true) then
			DT.state = 'loading'
			DT.phase = 'loading'
			DT.status('loading ' .. tostring(f.fileName))
			local ok, err = pcall(function() loadScreen:LoadGame(f.fileName) end)
			if not ok then DT.status('load error ' .. tostring(err)) end
			return
		end
	end
	DT.state = 'failed'
	DT.status('save not found: ' .. table.concat(names, ' ; '))
end

-- Keys during a hold (sent in the background by hand when observing, never by run.ps1): F7 shows the next tab of
-- the options screen, F8 records its tabs and options, F9 closes it, F10 records which known menus are on the stack, F11 opens the options screen from an input context.
local function menuNamesOnStack()
	local names, out = {}, {}
	for _, t in ipairs({ EEex_Menu_NativeMap, EEex_Options_Private_TemplateInstancesByName }) do
		if type(t) == 'table' then for k in pairs(t) do if type(k) == 'string' then names[k] = true end end end
	end
	for k in pairs(names) do
		local ok, on = pcall(Infinity_IsMenuOnStack, k)
		if ok and on then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end
DT.menuNamesOnStack = menuNamesOnStack
DT.keyCount = 0
local function holdKey(name)
	DT.keyCount = DT.keyCount + 1
	local tag = 'key' .. DT.keyCount .. '.' .. name
	if name == 'F11' then
		-- the ESC menu's options button: run its action as a click would (input context)
		local fields, action = {}, nil
		pcall(function()
			local m = EEex_Menu_Find('ESC_MENU')
			local it = m and m.items
			while it ~= nil do
				if itemVariant(it.text.text) == 'EEex Options' or itemVariant(it.text.text) == 'IEX Options' then break end
				it = it.next
			end
			if it == nil then fields.noButton = true return end
			for _, f in ipairs({ 'action', 'reference_action', 'actionAlt', 'actionDbl', 'actionEnter', 'actionExit',
				'actionDrag', 'actionUp', 'actionDown', 'reference_actionAlt' }) do
				local ok, v = pcall(function() return it.button[f] end)
				if ok and v ~= nil then fields['button.' .. f] = type(v) == 'userdata' and scrub(v) or v end
				ok, v = pcall(function() return it[f] end)
				if ok and v ~= nil then fields[f] = type(v) == 'userdata' and scrub(v) or v end
			end
			for _, f in ipairs({ 'reference_action', 'action' }) do
				local okR, ref = pcall(function() return it[f] end)
				if okR and ref ~= nil and EEex_Menu_GetItemFunction then
					local okF, fn = pcall(EEex_Menu_GetItemFunction, ref)
					fields['fn.' .. f] = okF and type(fn) or errText(fn)
					if okF and type(fn) == 'function' then action = fn fields.used = f break end
				end
			end
		end)
		local pushed = recordPushes(function() if action then action() else EEex_Options_Open() end end)
		DT.heldMenus = pushed
		case('hold.' .. tag .. '.buttonFields', function() return fields end)
		case('hold.' .. tag .. '.pushed', function() return pushed end)
	elseif name == 'F9' then
		pcall(EEex_Options_Close)
	elseif name == 'F7' then
		DT.tabShown = (DT.tabShown or 0) + 1
		local res = {}
		pcall(function()
			EEex_Options_Private_CurrentTab = DT.tabShown
			for _, mname in ipairs(DT.heldMenus or {}) do
				local m = EEex_Menu_Find(mname)
				local it = m and m.items
				while it ~= nil do
					if it.type == 3 then
						local okR, ref = pcall(function() return it.reference_action end)
						local okF, fn = pcall(EEex_Menu_GetItemFunction, ref)
						res.listAction = okF and type(fn) or 'none'
						if okF and type(fn) == 'function' then
							rowNumber = DT.tabShown
							local okC, err = pcall(fn)
							res.called = okC or errText(err)
						end
					end
					it = it.next
				end
			end
		end)
		-- IEX's screen: its tab list variable and action
		if IEXOpt_TabClick then
			iexOptTab = DT.tabShown
			res.iex = pcall(IEXOpt_TabClick)
		end
		res.tab = DT.tabShown
		case('hold.' .. tag .. '.showTab', function() return res end)
		for _, m in ipairs(DT.heldMenus or {}) do
			case('hold.' .. tag .. '.layout.' .. m, function() return menuLayout(m, 600) end)
		end
		DT.flush()
	elseif name == 'F6' then
		-- IEX's screen: a click on the widget of the first row of the first column
		if IEXOpt_RowClick then
			iexOptRow1, cellNumber = 1, 2
			local ok, err = pcall(IEXOpt_RowClick, 1)
			case('hold.' .. tag .. '.rowClick', function() return ok or errText(err), IEXOpt_RowValue(1, 1), IEXOpt_RowFrame(1, 1) end)
			cellNumber = nil
		end
	elseif name == 'F8' then
		-- the options screen's data: tabs (label, entries, widget kinds), options (default, storage, accessor), and
		-- the next tab shown by running the tab list's action with its selection variable set
		DT.tabIndex = (DT.tabIndex or 0) + 1
		local classes = {}
		for k, v in pairs(_G) do
			if type(k) == 'string' and k:find('^EEex_Options_') and type(v) == 'table' then classes[v] = k end
		end
		local function className(o)
			local mt = type(o) == 'table' and getmetatable(o)
			return mt and (classes[mt] or classes[rawget(mt, '__index') or false]) or type(o)
		end
		local function label(key)
			if type(key) ~= 'string' then return key end
			local ok, v = pcall(function() return t(key) end)
			return (ok and v ~= nil) and v or key
		end
		local function entry(e)
			if type(e) ~= 'table' then return className(e) end
			local w = e.widget
			local r = { id = e.optionID, label = label(e.label), class = className(e), widget = className(w) }
			if type(w) == 'table' then
				r.toggleValue = w.toggleValue
				r.disallowToggleOff = w.disallowToggleOff
				r.widgetKeys = {}
				for k, v in pairs(w) do if type(k) == 'string' then r.widgetKeys[#r.widgetKeys + 1] = k .. ':' .. type(v) end end
				table.sort(r.widgetKeys)
			end
			if type(e.subOptions) == 'table' then
				r.sub = {}
				for i, x in ipairs(e.subOptions) do r.sub[i] = entry(x) end
			end
			local o = e.optionID and EEex_Options_Get(e.optionID)
			if o then
				r.default = o.default
				r.type = className(o.type)
				r.accessor = className(o.accessor)
				if type(o.accessor) == 'table' then r.min, r.max = o.accessor.min, o.accessor.max end
				r.storage = className(o.storage)
				if type(o.storage) == 'table' then r.section, r.key, r.path = o.storage.section, o.storage.key, o.storage.path end
				r.requiresRestart = o.requiresRestart
				local okV, v = pcall(function() return o:get() end)
				r.value = okV and v or 'ERR'
			end
			return r
		end
		if DT.tabIndex == 1 then
			local tabs = EEex_Options_Private_Tabs
			case('hold.' .. tag .. '.tabsShape', function()
				local out = {}
				for k, v in pairs(type(tabs) == 'table' and tabs or {}) do
					local keys = {}
					if type(v) == 'table' then for kk, vv in pairs(v) do keys[#keys + 1] = tostring(kk) .. ':' .. type(vv) end end
					table.sort(keys)
					out[#out + 1] = { key = tostring(k), keys = keys }
				end
				return out
			end)
			for k, v in pairs(type(tabs) == 'table' and tabs or {}) do
				case('hold.' .. tag .. '.tab.' .. tostring(k), function()
					local r = {}
					if type(v) ~= 'table' then return type(v) end
					for kk, vv in pairs(v) do
						if type(vv) == 'function' or (kk == 'layout' and type(vv) == 'table') then
							local okB, cols = true, vv
							if type(vv) == 'function' then okB, cols = pcall(vv) end
							if okB and type(cols) == 'table' then
								r[tostring(kk)] = {}
								for ci, col in ipairs(cols) do
									local c = {}
									for ei, e in ipairs(type(col) == 'table' and col or {}) do c[ei] = entry(e) end
									r[tostring(kk)][ci] = c
								end
							end
						elseif type(vv) ~= 'table' then
							r[tostring(kk)] = type(vv) == 'string' and label(vv) or vv
						end
					end
					return r
				end)
			end
			case('hold.' .. tag .. '.optionGlobals', function()
				local out = {}
				for k, v in pairs(_G) do
					if type(k) == 'string' and k:find('^EEex_Options_') and type(v) ~= 'function' and type(v) ~= 'table' then
						out[k] = v
					end
				end
				return out
			end)
		end
		DT.flush()
	elseif name == 'F10' then
		for _, m in ipairs(DT.heldMenus or {}) do
			case('hold.' .. tag .. '.held.' .. m, function() return menuLayout(m, 600) end)
		end
		case('hold.' .. tag .. '.onStack', menuNamesOnStack)
		for _, m in ipairs(menuNamesOnStack()) do
			case('hold.' .. tag .. '.layout.' .. m, function() return menuLayout(m, 400) end)
		end
		DT.flush()
	end
	DT.status('hold ' .. tag)
end

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if DT.holdUntil then
			for _, k in ipairs({ 'F6', 'F7', 'F8', 'F9', 'F10', 'F11' }) do
				if key == EEex_Key_GetFromName(k) then holdKey(k) return end
			end
		end
		if key ~= EEex_Key_GetFromName('F11') then return end
		if DT.state == 'steps' and DT.keyAction then
			local fn = DT.keyAction
			DT.keyAction = nil
			local ok, err = pcall(fn)
			emit('step.' .. tostring(DT.phase) .. '.keyAction', ok and '"r":["ok"]' or ('"err":' .. jstr(errText(err))))
			DT.status('key action done: ' .. tostring(DT.phase))
			return
		end
		if DT.state == 'steps' and DT.phase == 'marshalSave' and not DT.saved then
			-- a UI action, run from a key press (input context) like the quick save button
			DT.saved = true
			local ok, err = pcall(function() worldScreen:OnQuickSaveButtonClick(false) end)
			emit('step.marshalSave.quickSave', ok and '"r":["ok"]' or ('"err":' .. jstr(errText(err))))
			return
		end
		if DT.state == 'boot' then keyStart() elseif DT.state == 'loadscreen' then keyLoad()
		elseif DT.state == 'loading' and EEex_Area_GetVisible() ~= nil then
			-- the save is up but GameStateInitialized did not move us on: go on from the key
			DT.state = 'world'
			DT.phase = 'world'
			DT.worldVia = 'key'
			DT.worldAt = now()
			DT.status('world (via key, no initialized event)')
			if not Infinity_IsMenuOnStack('DIFFT_TICK') then Infinity_PushMenu('DIFFT_TICK') end
		end
	end)
end)

-----------------------------------------------------------------------
-- Modules mode ([DiffTest] Modules=1, run.ps1 -Modules): no cases; observes the player modules (EEex.ini
-- [X Module] Enable) and the menu API. Steps can ask the runner for background input: status
-- 'input <n> <spec>' with spec 'kd <vk> <scan>' (key down), 'ku <vk> <scan>' (key up), 'mm <fx> <fy>' (mouse move
-- to a fraction of the client area). A step with hold = true is screenshotted (status 'hold m.<name>').
-----------------------------------------------------------------------

DT.mod = DT.mod or { calls = {} }
local M = DT.mod

local function gameTime()
	local ok, v = pcall(function() return EngineGlobals.g_pBaldurChitin.m_pObjectGame.m_worldTime.m_gameTime end)
	if ok and v then return v end
	ok, v = pcall(function() return EEex_GameState_GetGameTime() end)
	if ok then return v end
	return 'n/a'
end
local function paused()
	local ok, v = pcall(function() return worldScreen:CheckIfPaused() end)
	return ok and v
end
local function setPaused(want)
	if (paused() and true or false) ~= want then pcall(function() worldScreen:TogglePauseGame(true) end) end
end
local function act(s, target)
	pcall(EEex_Action_QueueResponseStringOnAIBase, s, target or P(0))
end
local function shallow(v)
	if type(v) ~= 'table' then
		if type(v) == 'number' or type(v) == 'string' or type(v) == 'boolean' then return v end
		return '<' .. type(v) .. '>'
	end
	local keys = {}
	for k, x in pairs(v) do
		local d = type(x)
		if d == 'number' or d == 'string' or d == 'boolean' then d = d .. '=' .. tostring(x) end
		keys[#keys + 1] = tostring(k) .. ':' .. d
		if #keys > 80 then break end
	end
	table.sort(keys)
	return keys
end
local function variantInfo(v)
	local r = {}
	pcall(function() r.luaType = type(v) end)
	pcall(function() r.rawType = v.type end)
	pcall(function() r.rawValue = v.value end)
	if EEex_Menu_GetItemVariant then
		local ok, g = pcall(EEex_Menu_GetItemVariant, v)
		r.gvType = ok and type(g) or errText(g)
		if ok and type(g) ~= 'function' and type(g) ~= 'userdata' then r.gv = g end
		if ok and type(g) == 'function' then local okC, c = pcall(g) r.gvCall = okC and tostring(c) or 'ERR' end
	end
	return r
end
local function containerList()
	local out = {}
	pcall(function()
		local area = EEex_Area_GetVisible()
		EEex_Utility_IterateCPtrList(area.m_lVertSortBack, function(id)
			local ob = EEex_GameObject_Get(id)
			if ob and ob.m_objectType == 17 then
				local c = EEex_GameObject_CastUserType(ob)
				out[#out + 1] = { id = id, items = c.m_lstItems.m_nCount, x = c.m_pos.x, y = c.m_pos.y }
			end
		end)
	end)
	return out
end

M.steps = {
	{ 'globals', function()
		case('m.EEex_Modules', function() return EEex_Modules end)
		case('m.globalsB3', function()
			local out = {}
			for k, v in pairs(_G) do
				if type(k) == 'string' and k:find('^B3') then out[k] = shallow(v) end
			end
			return out
		end)
		case('m.uiStrings', function()
			local out = {}
			for k, v in pairs(type(uiStrings) == 'table' and uiStrings or {}) do
				if type(k) == 'string' and (k:find('B3') or k:upper():find('EEEX')) then out[k] = v end
			end
			return out
		end)
		case('m.menus', function()
			local out = {}
			for k in pairs(type(EEex_Menu_NativeMap) == 'table' and EEex_Menu_NativeMap or {}) do
				if type(k) == 'string' and k:find('B3') then out[#out + 1] = k end
			end
			table.sort(out)
			return out
		end)
		for _, m in ipairs({ 'B3EffectMenu_Menu', 'B3AttackInfo_Menu', 'B3Timer_Menu', 'B3TimeStep_Menu' }) do
			case('m.layout.' .. m, function() return menuLayout(m, 60) end)
		end
		case('m.escVariants', function()
			local out, it, n = {}, EEex_Menu_Find('ESC_MENU').items, 0
			while it ~= nil and n < 20 do
				n = n + 1
				local r = {}
				pcall(function() r.text = variantInfo(it.text.text) end)
				pcall(function() r.bam = variantInfo(it.bam.resref) end)
				pcall(function() r.seq = variantInfo(it.bam.sequence) end)
				pcall(function() r.enabled = variantInfo(it.enabled) end)
				pcall(function() r.refEnabled = it.reference_enabled end)
				out[n] = r
				it = it.next
			end
			return out
		end)
		case('m.containers', containerList)
		case('m.gameTime', gameTime)
		case('m.containerLabel', function()
			local a = EEex_Label('Hook-CGameContainer::Render()-B3EmptyContainer')
			local b = {}
			for i = 0, 9 do b[#b + 1] = string.format('%02X', EEex_ReadU8(a + 5 + i) % 256) end
			return type(a), table.concat(b, ' ')
		end)
		case('m.variantFns', function()
			return type(EEex_Menu_GetItemVariant), type(EEex_Menu_AfterMainFileLoadedListeners),
				type(EEex_Menu_BeforeMainFileLoadedListeners), type(EEex and EEex.DeepCopy)
		end)
	end },
	-- the options key (US backslash key: VK_OEM_5, scan 0x2B) sent in the background: key codes received
	{ 'optKey', function()
		M.keys = {}
		if not M.keyListener then
			M.keyListener = true
			pcall(EEex_Key_AddPressedListener, function(k) if M.keys and #M.keys < 20 then M.keys[#M.keys + 1] = k end end)
		end
	end, input = { 'kd 0xdc 0x2b', 'ku 0xdc 0x2b' }, wait = 800, check = function()
		case('m.optKey', function()
			return M.keys, Infinity_IsMenuOnStack('EEex_Options') and true or false,
				EEex_Key_GetFromName(string.char(92)), EEex_Key_GetFromName('*')
		end)
		pcall(EEex_Options_Close)
		M.keys = nil
	end },
	{ 'escMenu', function() Infinity_PushMenu('ESC_MENU') end, wait = 800, hold = true, check = function()
		case('m.escMenu.layout', function() return menuLayout('ESC_MENU') end)
		case('m.escMenu.uiMenuArea', function() return EEex_Menu_GetUIMenuArea(EEex_Menu_Find('ESC_MENU')) end)
		case('m.escMenu.area', function() return EEex_Menu_GetArea('ESC_MENU') end)
		case('m.screenSize', function() return Infinity_GetScreenSize() end)
		case('m.escMenu.sqReplace', function()
			local before = SQOpt and SQOpt.escArea and { SQOpt.escArea.x, SQOpt.escArea.y }
			SQOpt.escPlaced = false
			SQOpt_EscText()
			return before, { SQOpt.escArea.x, SQOpt.escArea.y }, { SQOpt.escRet.x, SQOpt.escRet.y, SQOpt.escRet.w, SQOpt.escRet.h }
		end)
		case('m.escMenu.busy', function()
			local esc = EEex_Menu_Find('ESC_MENU')
			local _, _, menuW, menuH = EEex_Menu_GetUIMenuArea(esc)
			local out, item, n = {}, esc.items, 0
			while item ~= nil do
				n = n + 1
				local a = item.area
				local okS, vS = pcall(function() return EEex_Menu_GetItemVariant(item.enabled) end)
				local okT, t = pcall(function() return EEex_Menu_GetItemVariant(item.text.text) end)
				if okT and type(t) == 'function' then local o2, r = pcall(t) t = o2 and r or nil end
				local known, isButton = pcall(function() return item.type == assert(uiItemType.ITEM_BUTTON) end)
				local okB, bam = pcall(function() return EEex_Menu_GetItemVariant(item.bam.resref) end)
				out[n] = { a.x, a.y, a.w, a.h, okS and tostring(vS) or 'err', okT and tostring(t) or 'errT', known, isButton,
					okB and tostring(bam) or 'errB', menuW, menuH }
				item = item.next
			end
			return out
		end)
		case('m.escMenu.placeTrace', function()
			local O = SQOpt
			local area, ret, esc = O.escArea, O.escRet, O.escMenu
			local x, w, h, gap = ret.x, ret.w, ret.h, 5
			local _, _, menuW, menuH = EEex_Menu_GetUIMenuArea(esc)
			local busy, skipped = {}, {}
			local item = esc.items
			while item ~= nil do
				local a = item.area
				local okT, text = pcall(function() return EEex_Menu_GetItemVariant(item.text.text) end)
				if okT and type(text) == 'function' then local o2, r = pcall(text) text = o2 and r or nil end
				if not okT then text = nil end
				local known, isButton = pcall(function() return item.type == assert(uiItemType.ITEM_BUTTON) end)
				local okBam, bam = pcall(function() return EEex_Menu_GetItemVariant(item.bam.resref) end)
				local taken = not known or isButton or (type(text) == 'string' and text ~= '')
					or (okBam and type(bam) == 'string' and bam ~= '')
				local okS, v = pcall(function() return EEex_Menu_GetItemVariant(item.enabled) end)
				local shown = (not okS or v == nil) and true or (v ~= 0 and v ~= false)
				if a and taken and text ~= O.TXT.button and shown and a.w > 0 and a.h > 0
					and a.w * a.h < 0.25 * (menuW or 1024) * (menuH or 768) then
					busy[#busy + 1] = { a.x, a.y, a.w, a.h }
				else
					skipped[#skipped + 1] = tostring(text) .. '|' .. tostring(taken) .. '|' .. tostring(shown)
				end
				item = item.next
			end
			local frees = {}
			for k = 1, 3 do
				local y = ret.y - k * (h + gap)
				local hit = 'free'
				for _, r in ipairs(busy) do
					if x < r[1] + r[3] and r[1] < x + w and y < r[2] + r[4] and r[2] < y + h then hit = table.concat(r, ',') break end
				end
				frees[k] = y .. ':' .. hit
			end
			return busy, skipped, frees, tostring(O.TXT.button), type(x), type(ret)
		end)
		case('m.escMenu.stale', function()
			local a, b = SQOpt.escMenu, EEex_Menu_Find('ESC_MENU')
			local n1, n2 = 0, 0
			local i = a.items while i ~= nil and n1 < 50 do n1 = n1 + 1 i = i.next end
			i = b.items while i ~= nil and n2 < 50 do n2 = n2 + 1 i = i.next end
			return a == b, EEex_UDToPtr(a) == EEex_UDToPtr(b), n1, n2,
				EEex_UDToPtr(a.items) == EEex_UDToPtr(b.items), type(a), type(a.items)
		end)
		case('m.uiItemType', function() return type(uiItemType), uiItemType and uiItemType.ITEM_BUTTON end)
		Infinity_PopMenu('ESC_MENU')
	end },
	{ 'optionsOpen', function() DT.heldMenus = recordPushes(function() EEex_Options_Open() end) end, wait = 800,
		hold = true, check = function() holdKey('F8') end },
	{ 'optTab1', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optTab2', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optTab3', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optTab4', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optTab5', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optTab6', function() holdKey('F7') end, wait = 500, hold = true },
	{ 'optClose', function() pcall(EEex_Options_Close) end, wait = 500 },
	-- Empty Container: the hook calls while the highlight key (Tab) is held
	{ 'container', function()
		local hook = B3EmptyContainer_Hook_OnBeforeContainerOutlineRender
		M.hookType = type(hook)
		if type(hook) == 'function' and not M.wrapped then
			M.wrapped = true
			B3EmptyContainer_Hook_OnBeforeContainerOutlineRender = function(container, color, ...)
				local rec = { extra = select('#', ...) }
				pcall(function()
					rec.colorType = type(color)
					rec.before = color.value
					rec.items = container.m_lstItems.m_nCount
					rec.id = container.m_id
				end)
				local res = { pcall(hook, container, color, ...) }
				pcall(function() rec.after = color.value end)
				rec.ok = res[1]
				if #M.calls < 40 then M.calls[#M.calls + 1] = rec end
				if res[1] then return select(2, unpackAll(res)) end
			end
		end
		local list = containerList()
		local pick, px, py = nil, 0, 0
		pcall(function() px, py = P(0).m_pos.x, P(0).m_pos.y end)
		local function d(c) return (c.x - px) ^ 2 + (c.y - py) ^ 2 end
		for _, c in ipairs(list) do if c.items == 0 and (not pick or d(c) < d(pick)) then pick = c end end
		pick = pick or list[1]
		M.playerPos = { px, py }
		M.pick = pick
		-- actions only run while the game runs
		setPaused(false)
		if pick then act('MoveViewPoint([' .. pick.x .. '.' .. pick.y .. '],0)') end
	end, wait = 1500 },
	{ 'containerTab', function() setPaused(true) end, wait = 500, input = { 'kd 0x09 0x0f' }, hold = true, check = function()
		case('m.container.hookType', function() return M.hookType, M.pick, M.playerPos end)
		case('m.container.calls', function() return M.calls end)
	end },
	{ 'containerUp', function() end, input = { 'ku 0x09 0x0f' }, wait = 500 },
	-- Time Step: a short press of D while paused, then a long one
	{ 'timeStep', function()
		setPaused(true)
		M.t0 = gameTime()
	end, wait = 600, input = { 'kd 0x44 0x20', 'ku 0x44 0x20' }, check = function()
		case('m.timeStep.short', function() return M.t0, gameTime(), paused() end)
	end },
	{ 'timeStepLong', function() M.t1 = gameTime() end, input = { 'kd 0x44 0x20' }, wait = 2000, check = function()
		case('m.timeStep.longHeld', function() return M.t1, gameTime(), paused() end)
	end },
	{ 'timeStepLongUp', function() end, input = { 'ku 0x44 0x20' }, wait = 800, check = function()
		case('m.timeStep.longUp', function() return M.t1, gameTime(), paused() end)
	end },
	-- Timer: a modal action and a spell cast, unpaused, screenshots of the portraits
	{ 'timer', function()
		setPaused(false)
		act('FindTraps()', P(0))
		act('ReallyForceSpellRES("SPWI112",Player1)', P(1) or P(0))
	end, wait = 1500, hold = true },
	{ 'timer2', function() end, wait = 1500, hold = true },
	{ 'timer3', function() end, wait = 2500, hold = true },
	-- Effect Menu: Left Shift held with the mouse over Player1 (view centered on it)
	{ 'effectMenuView', function()
		setPaused(false)
		act('MoveViewObject(Player1,0)', P(0))
	end, wait = 1200 },
	{ 'effectMenu', function() setPaused(true) end, wait = 500, input = { 'mm 0.5 0.47', 'kd 0x10 0x2a' }, hold = true, check = function()
		case('m.effectMenu.onStack', function() return DT.menuNamesOnStack() end)
		case('m.effectMenu.key', function() return B3EffectMenu_Key end)
	end },
	{ 'effectMenuUp', function() end, input = { 'ku 0x10 0x2a' }, wait = 500 },
	-- Attack Info: a hostile creature next to Player1, the party selected, the mouse over it; then Left Alt
	{ 'attackInfo', function()
		M.created = nil
		setPaused(false)
		for _, r in ipairs({ 'GOBLIN01', 'GNOLL01', 'KOBOLD01', 'ORC01', 'XVART01', 'GIBBERL' }) do
			local ok, h = pcall(EEex_Resource_Demand, r, 'CRE')
			if ok and h then M.creRes = r break end
		end
		if M.creRes then act('CreateCreatureObjectOffset("' .. M.creRes .. '",Player1,[0.60])', P(0)) end
	end, wait = 1500 },
	{ 'attackInfoView', function()
		if M.created then act('MoveViewObject(Myself,0)', M.created) end
	end, wait = 1200 },
	{ 'attackInfo2', function()
		setPaused(true)
		pcall(function() Infinity_OnPortraitLClick(0) end)
	end, wait = 800, input = { 'mm 0.5 0.47', 'mm 0.5 0.46' }, hold = true, check = function()
		case('m.attackInfo.created', function() return M.creRes, M.created ~= nil end)
		case('m.attackInfo.onStack', function() return DT.menuNamesOnStack() end)
	end },
	{ 'attackInfoAlt', function() end, input = { 'kd 0x12 0x38' }, wait = 600, hold = true },
	{ 'attackInfoAltUp', function() end, input = { 'ku 0x12 0x38' }, wait = 500 },
	-- ESC menu and options screen: layout, open from the ESC menu's button, close paths (X, \ key, Esc), paused or not
	-- (run.ps1 -ModSteps ou...). Buttons are 'clicked' by running their action (DT.ouInvoke).
	{ 'ouWorld', function() setPaused(false) DT.ouPushLog() end, wait = 600, hold = true, check = function() DT.ouState('ouWorld') end },
	{ 'ouEsc', function() end, input = { 'kd 0x1b 0x01', 'ku 0x1b 0x01' }, wait = 1000, hold = true, check = function()
		DT.ouState('ouEsc')
		case('ou.ouEsc.layout', function() return DT.ouLayout('ESC_MENU') end)
		case('ou.ouEsc.optButtons', function() return DT.ouFindOptButtons() end)
		case('ou.ouEsc.refs', function() return DT.ouEscRefs() end)
		case('ou.ouEsc.sqMenu', function()
			local O = SQOpt
			if type(O) ~= 'table' or not O.escMenu then return 'no SQOpt' end
			local fresh = EEex_Menu_Find('ESC_MENU')
			return O.escMenu == fresh, { EEex_Menu_GetUIMenuArea(O.escMenu) }, { EEex_Menu_GetUIMenuArea(fresh) },
				DT.ouReloads or 0, DT.ouLoads or 0
		end)
		case('ou.ouEsc.layout.RG_START_OPTIONS_BAR', function() return DT.ouLayout('RG_START_OPTIONS_BAR') end)
		case('ou.ouEsc.sqPlace', function()
			local O = SQOpt
			if type(O) ~= 'table' or not O.escArea then return 'no SQOpt' end
			local before = { O.escArea.x, O.escArea.y, O.escArea.w, O.escArea.h }
			O.escPlaced = false
			pcall(SQOpt_EscText)
			return before, { O.escArea.x, O.escArea.y, O.escArea.w, O.escArea.h }, { O.escRet.x, O.escRet.y, O.escRet.w, O.escRet.h },
				type(uiItemType), { EEex_Menu_GetUIMenuArea(O.escMenu) }
		end)
	end },
	{ 'ouOpenBtn', function() end, input = function() DT.ouInvokeOpt() return {} end, wait = 1200,
		hold = true, check = function()
		DT.ouState('ouOpenBtn')
		for name in pairs(DT.ouPushed or {}) do
			case('ou.ouOpenBtn.layout.' .. name, function() return DT.ouLayout(name) end)
		end
	end },
	{ 'ouCloseX', function() end, input = function() DT.ouInvokeClose() return {} end, wait = 1200, hold = true,
		check = function() DT.ouState('ouCloseX') end },
	{ 'ouEscAfter', function() end, input = { 'kd 0x1b 0x01', 'ku 0x1b 0x01' }, wait = 1000, hold = true,
		check = function() DT.ouState('ouEscAfter') end },
	{ 'ouReset1', function() pcall(EEex_Options_Close) end, input = function() return DT.ouResetKeys() end, wait = 1000,
		check = function() setPaused(false) DT.ouState('ouReset1') end },
	{ 'ouKeyOpen', function() end, input = { 'kd 0xdc 0x2b', 'ku 0xdc 0x2b' }, wait = 1200, hold = true,
		check = function() DT.ouState('ouKeyOpen') end },
	{ 'ouKeyClose', function() end, input = { 'kd 0xdc 0x2b', 'ku 0xdc 0x2b' }, wait = 1200, hold = true,
		check = function() DT.ouState('ouKeyClose') end },
	{ 'ouReset2', function() pcall(EEex_Options_Close) end, input = function() return DT.ouResetKeys() end, wait = 1000,
		check = function() setPaused(true) DT.ouState('ouReset2') end },
	{ 'ouPausedOpen', function() pcall(EEex_Options_Open) end, wait = 1200, hold = true,
		check = function() DT.ouState('ouPausedOpen') end },
	{ 'ouPausedX', function() end, input = function() DT.ouInvokeClose() return {} end, wait = 1200, hold = true,
		check = function() DT.ouState('ouPausedX') end },
	{ 'ouReset3', function() pcall(EEex_Options_Close) end, input = function() return DT.ouResetKeys() end, wait = 1000,
		check = function() setPaused(false) DT.ouState('ouReset3') end },
	{ 'ouEsc2', function() end, input = { 'kd 0x1b 0x01', 'ku 0x1b 0x01' }, wait = 1000, check = function() DT.ouState('ouEsc2') end },
	{ 'ouOpenBtn2', function() end, input = function() DT.ouInvokeOpt() return {} end, wait = 1200,
		check = function() DT.ouState('ouOpenBtn2') end },
	{ 'ouKeyClose2', function() end, input = { 'kd 0xdc 0x2b', 'ku 0xdc 0x2b' }, wait = 1200, hold = true,
		check = function() DT.ouState('ouKeyClose2') end },
	{ 'ouReset4', function() pcall(EEex_Options_Close) end, input = function() return DT.ouResetKeys() end, wait = 1000,
		check = function() setPaused(false) DT.ouState('ouReset4') end },
	{ 'ouTabs', function() pcall(EEex_Options_Open) end, wait = 1200, hold = true, check = function()
		DT.ouState('ouTabs')
		case('ou.tabs', function()
			local out = {}
			for i, tb in ipairs(type(iexOptTabs) == 'table' and iexOptTabs or {}) do out[i] = { tb.label, tb.text } end
			return out, type(uiStrings) == 'table' and uiStrings.SQOPT_Tab or 'no uiStrings', DT.ouTr
		end)
		pcall(EEex_Options_Close)
	end },
	{ 'mdone', function() end },
}

pcall(EEex_Sprite_AddLoadedListener, function(s)
	pcall(function() if DT.mod.creRes and s.m_resref:get() == DT.mod.creRes then DT.mod.created = s end end)
end)

-- Options UI steps (ou*): helpers
-- translation listeners: how many calls, and whether SadoEE's tab label is in uiStrings each time
DT.ouTr = {}
pcall(EEex_Menu_AddTranslationLoadedListener, function()
	DT.ouTr[#DT.ouTr + 1] = tostring(DT.phase) .. ':' .. tostring(type(uiStrings) == 'table' and rawget(uiStrings, 'SQOPT_Tab'))
end)
local function ouPtr(m) local ok, v = pcall(EEex_UDToPtr, m) return ok and v or 'err' end
pcall(EEex_Menu_AddMainFileLoadedListener, function()
	DT.ouLoads = (DT.ouLoads or 0) + 1
	pcall(function()
		DT.ouEscRef0 = EEex_Menu_Find('ESC_MENU')
		DT.ouEsc0 = { ouPtr(DT.ouEscRef0), EEex_Menu_GetUIMenuArea(DT.ouEscRef0) }
	end)
end)
pcall(EEex_GameState_AddInitializedListener, function()
	pcall(function()
		DT.ouEscRef1 = EEex_Menu_Find('ESC_MENU')
		DT.ouEsc1 = { ouPtr(DT.ouEscRef1), EEex_Menu_GetUIMenuArea(DT.ouEscRef1),
			DT.ouEscRef0 and EEex_Menu_GetUIMenuArea(DT.ouEscRef0) }
	end)
end)
function DT.ouEscRefs()
	local fresh = EEex_Menu_Find('ESC_MENU')
	return DT.ouEsc0, DT.ouEsc1, { ouPtr(fresh), EEex_Menu_GetUIMenuArea(fresh) },
		DT.ouEscRef0 and { ouPtr(DT.ouEscRef0), EEex_Menu_GetUIMenuArea(DT.ouEscRef0) },
		DT.ouEscRef1 and { ouPtr(DT.ouEscRef1), EEex_Menu_GetUIMenuArea(DT.ouEscRef1) },
		SQOpt and SQOpt.escMenu and ouPtr(SQOpt.escMenu)
end
pcall(EEex_Menu_AddAfterMainFileReloadedListener, function() DT.ouReloads = (DT.ouReloads or 0) + 1 end)
local OU_MENUS = { 'ESC_MENU', 'EEex_Options', 'WORLD_ACTIONBAR', 'RIGHT_SIDEBAR', 'LEFT_SIDEBAR', 'OPTIONS', 'IEX_OPTEDIT',
	'SQOPT_PAGE', 'START', 'WORLD_MESSAGES', 'DIFFT_TICK', 'SQOPT_TICK' }
DT.ouLog = {}
function DT.ouPushLog()
	if DT.ouPushWrapped then return end
	DT.ouPushWrapped = true
	DT.ouPushed = {}
	local push, pop = Infinity_PushMenu, Infinity_PopMenu
	Infinity_PushMenu = function(name, ...)
		if type(name) == 'string' and name ~= 'DIFFT_TICK' then
			DT.ouPushed[name] = true
			DT.ouLog[#DT.ouLog + 1] = 'push ' .. name
		end
		return push(name, ...)
	end
	Infinity_PopMenu = function(name, ...)
		if name ~= 'DIFFT_TICK' then DT.ouLog[#DT.ouLog + 1] = 'pop ' .. tostring(name) end
		return pop(name, ...)
	end
end
function DT.ouState(tag)
	local names = {}
	for k in pairs(DT.ouPushed or {}) do names[k] = true end
	for _, k in ipairs(OU_MENUS) do names[k] = true end
	local on = {}
	for k in pairs(names) do
		local ok, v = pcall(Infinity_IsMenuOnStack, k)
		if ok and v then on[#on + 1] = k end
	end
	table.sort(on)
	local log = DT.ouLog
	DT.ouLog = {}
	case('ou.' .. tag .. '.state', function()
		local world = false
		pcall(function() world = e:GetActiveEngine() == worldScreen end)
		return on, paused() and true or false, world, log
	end)
end
function DT.ouLayout(name)
	local m = EEex_Menu_Find(name)
	if not m then return 'no menu' end
	local mx, my, mw, mh = EEex_Menu_GetUIMenuArea(m)
	local out, it, n = {}, m.items, 0
	while it ~= nil and n < 120 do
		n = n + 1
		local r = {}
		pcall(function() local a = it.area r[1] = table.concat({ a.x, a.y, a.w, a.h }, ',') end)
		pcall(function() r[2] = tostring(itemVariant(it.text.text)) end)
		pcall(function() r[3] = tostring(itemVariant(it.bam.resref)) end)
		pcall(function() r[4] = tostring(itemVariant(it.enabled)) end)
		pcall(function() r[5] = it.type end)
		out[n] = r
		it = it.next
	end
	return { mx, my, mw, mh }, { Infinity_GetScreenSize() }, out
end
-- every loaded menu with an options button (EEex's / IEX's), and that button's area and look
function DT.ouFindOptButtons()
	local out = {}
	-- (walking every menu of EEex_Menu_NativeMap crashed EEex: a fixed list of the menus that could hold it)
	local names = { 'ESC_MENU', 'RG_START_OPTIONS_BAR', 'START', 'START_OPTIONS', 'RG_OPTIONS_BAR' }
	local seen = {}
	for _, name in ipairs(names) do
		if not seen[name] then
			seen[name] = true
			local ok, m = pcall(EEex_Menu_Find, name)
			local it = ok and m and m.items
			local n = 0
			while it ~= nil and n < 300 do
				n = n + 1
				local okT, t = pcall(function() return itemVariant(it.text.text) end)
				if okT and type(t) == 'string' then t = t:gsub('%^.', '') end
				if okT and (t == 'EEex Options' or t == 'IEX Options' or t == 'SadoEE') then
					local r = { menu = name, text = t, index = n }
					pcall(function() local a = it.area r.area = table.concat({ a.x, a.y, a.w, a.h }, ',') end)
					pcall(function() r.bam = tostring(itemVariant(it.bam.resref)) end)
					pcall(function() r.seq = tostring(itemVariant(it.bam.sequence)) end)
					pcall(function() local p = it.pad r.pad = table.concat({ p.x, p.y, p.w, p.h }, ',') end)
					pcall(function() r.enabled = tostring(itemVariant(it.enabled)) end)
					out[#out + 1] = r
				end
				it = it.next
			end
		end
	end
	return out
end
-- runs the action of the first item of menu `name` that `match` accepts, as a click does (posted mouse clicks
-- do not reach the engine's buttons in a background window)
function DT.ouInvoke(name, match, tag)
	local res = { menu = name }
	local ok, err = pcall(function()
		local m = EEex_Menu_Find(name)
		local it = m and m.items
		while it ~= nil do
			local okM, hit = pcall(match, it)
			if okM and hit then
				local a = it.area
				res.area = table.concat({ a.x, a.y, a.w, a.h }, ',')
				local fn
				for _, f in ipairs({ 'reference_action', 'action' }) do
					local okR, ref = pcall(function() return it[f] end)
					if okR and ref ~= nil then
						local okF, g = pcall(EEex_Menu_GetItemFunction, ref)
						if okF and type(g) == 'function' then fn = g res.field = f break end
					end
				end
				-- IEX's items have no reference_action field: its own buttons' actions (IEXOPT.menu)
				if not fn and DT.ouIexAction then fn = DT.ouIexAction(it) res.field = 'iex' end
				if not fn then res.err = 'no action' return end
				local okC, e2 = pcall(fn)
				res.called = okC or errText(e2)
				return
			end
			it = it.next
		end
		res.err = 'no item'
	end)
	if not ok then res.err = errText(err) end
	case('ou.invoke.' .. (tag or name), function() return res end)
end
function DT.ouIexAction(it)
	local t = itemVariant(it.text.text)
	if type(t) == 'string' then t = t:gsub('%^.', '') end
	if t == 'IEX Options' and IEXOpt_EscClick then return IEXOpt_EscClick end
	if t == 'X' and IEXOpt_Title then return EEex_Options_Close end
end
function DT.ouInvokeOpt()
	for _, r in ipairs(DT.ouFindOptButtons()) do
		if r.text ~= 'SadoEE' and Infinity_IsMenuOnStack(r.menu) then return DT.ouInvoke(r.menu, DT.ouIsOptButton, 'opt') end
	end
	case('ou.invoke.opt', function() return 'no options button on the stack' end)
end
-- the options screen's close (X) button: IEX's IEXOPT_CLOSE, or the EEex screen's item whose text is 'X' / a
-- close action, in any menu on the stack named EEex_Options*
function DT.ouInvokeClose()
	local function isX(it)
		local t = itemVariant(it.text.text)
		if type(t) == 'string' then t = t:gsub('%^.', '') end
		local okB, bam = pcall(function() return itemVariant(it.bam.resref) end)
		return t == 'X' or t == 'x' or (okB and bam == 'X-X')
	end
	for _, n in ipairs({ 'EEex_Options', 'EEex_Options_Tab1', 'EEex_Options_Tab2', 'EEex_Options_Tab3', 'EEex_Options_Tab4', 'EEex_Options_Tab5' }) do
		if Infinity_IsMenuOnStack(n) then
			local m = EEex_Menu_Find(n)
			local it, found = m and m.items, false
			while it ~= nil do
				local okM, hit = pcall(isX, it)
				if okM and hit then found = true break end
				it = it.next
			end
			if found then return DT.ouInvoke(n, isX, 'close') end
		end
	end
	case('ou.invoke.close', function() return 'no X item' end)
end
function DT.ouIsOptButton(it)
	local t = itemVariant(it.text.text)
	if type(t) == 'string' then t = t:gsub('%^.', '') end
	return t == 'EEex Options' or t == 'IEX Options'
end
function DT.ouResetKeys()
	if Infinity_IsMenuOnStack('ESC_MENU') then return { 'kd 0x1b 0x01', 'ku 0x1b 0x01' } end
	return {}
end
function DT.ouReset()
	pcall(EEex_Options_Close)
	for _ = 1, 3 do
		for _, k in ipairs({ 'ESC_MENU', 'OPTIONS' }) do
			if Infinity_IsMenuOnStack(k) then pcall(Infinity_PopMenu, k) end
		end
	end
	setPaused(false)
end

function DT.moduleTick()
	if M.i == nil then
		M.i, M.phase = 1, 'start'
		-- [DiffTest] ModSteps: only these steps (comma list)
		local only = tostring(Infinity_GetINIString('DiffTest', 'ModSteps', '') or '')
		if only ~= '' and only ~= '0' then
			local set, out = {}, {}
			for n in only:gmatch('[^,%s]+') do set[n] = true end
			for _, st in ipairs(M.steps) do if set[st[1]] or st[1] == 'mdone' then out[#out + 1] = st end end
			M.steps = out
		end
	end
	local st = M.steps[M.i]
	if not st then
		DT.state = 'done'
		DT.flush()
		DT.status('DONE ' .. #DT.lines)
		return
	end
	local t = now()
	if M.phase == 'start' then
		DT.phase = 'm.' .. st[1]
		print('DIFFT|TRACE mstep:' .. st[1])
		local ok, err = pcall(st[2])
		if not ok then emit('m.' .. st[1] .. '.trigger', '"err":' .. jstr(errText(err))) end
		M.inputs = st.input
		if type(st.input) == 'function' then
			local okI, list = pcall(st.input)
			M.inputs = okI and list or {}
			if not okI then emit('m.' .. st[1] .. '.input', '"err":' .. jstr(errText(list))) end
		end
		DT.flush()
		M.phase, M.at, M.inputI = 'input', t, 0
		return
	end
	if M.phase == 'input' then
		if M.inputI > 0 and t - M.at < 900 then return end
		M.inputI = M.inputI + 1
		local spec = M.inputs and M.inputs[M.inputI]
		if spec then
			M.inputN = (M.inputN or 0) + 1
			DT.status('input ' .. M.inputN .. ' ' .. spec)
			M.at = t
			return
		end
		M.phase, M.at = 'wait', t
		DT.status('mstep ' .. st[1])
		return
	end
	if M.phase == 'wait' then
		if t - M.at < (st.wait or 300) then return end
		if st.hold and (DT.holdMs or 0) > 0 then
			M.phase, M.at = 'hold', t
			DT.holdUntil = t + DT.holdMs
			DT.status('hold m.' .. st[1])
			return
		end
		M.phase = 'check'
	end
	if M.phase == 'hold' then
		if t - M.at < DT.holdMs then return end
		DT.holdUntil = nil
		M.phase = 'check'
	end
	if M.phase == 'check' then
		if st.check then
			local ok, err = pcall(st.check)
			if not ok then emit('m.' .. st[1] .. '.check', '"err":' .. jstr(errText(err))) end
		end
		DT.flush()
		M.i, M.phase = M.i + 1, 'start'
	end
end

function DiffT_Tick()
	DT.frames = DT.frames + 1
	local ok, err = pcall(tickWorld)
	if not ok then DT.status('tick error ' .. tostring(err)) end
	return false
end

local function wrapGlobal(name, tick)
	local orig = _G[name]
	if type(orig) ~= 'function' or DT['wrapped_' .. name] then return type(orig) == 'function' end
	DT['wrapped_' .. name] = true
	_G[name] = function(...)
		pcall(tick)
		return orig(...)
	end
	return true
end

pcall(EEex_Menu_AddMainFileLoadedListener, function() pcall(function()
	DT.phase = 'mainfile'
	pcall(optSnapshot, '2_mainfile')
	pcall(EEex_Menu_LoadFile, 'DIFFT')
	DT.wrapStart = wrapGlobal('getTitle', tickStart)
	-- Infinity UI++: no getTitle, getLoadMenuTitle unused; its start and load menus both show rgGetTitleFrame()
	if not DT.wrapStart then
		DT.wrapStart = wrapGlobal('rgGetTitleFrame', function() tickStart() tickLoad() end)
	end
	DT.wrapLoad = wrapGlobal('getLoadMenuTitle', tickLoad)
	DT.status('main file loaded; wraps ' .. tostring(DT.wrapStart) .. ' ' .. tostring(DT.wrapLoad))
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(function()
	pcall(optSnapshot, '3_initialized')
	if DT.state == 'loading' then
		DT.state = 'world'
		DT.phase = 'world'
		DT.worldAt = now()
		DT.status('game initialized')
	end
	pcall(function()
		if DT.state == 'world' and not Infinity_IsMenuOnStack('DIFFT_TICK') then Infinity_PushMenu('DIFFT_TICK') end
	end)
end) end)
pcall(EEex_Sprite_AddLoadedListener, function()
	pcall(function()
		if DT.state == 'world' and not Infinity_IsMenuOnStack('DIFFT_TICK') then Infinity_PushMenu('DIFFT_TICK') end
	end)
end)

pcall(DT.status, 'probe loaded')
