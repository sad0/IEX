--[[
Per-creature UUID probe (tools/uuidtest, docs/UUID.md). Our own code; the same file runs under EEex and IEX and only
uses the public EEex Lua API, so UUID behaviour is observed as a black box.
Modes (UUID_MODE, set by the runner):
  first  : load UUID_SAVE, introspect the API, list every creature's UUID and EEEX_UUID local, spawn creatures,
           clone a party member (op236 simulacrum), test GetFromUUID and LoadedWithUUIDCallback, then SaveGame(slot).
  reload : load UUID_SAVE (normally the save written by "first"), list UUIDs again, callbacks across a load.
Output: uuid_out.txt (io) or IEX/uuid_out.txt (IEX_WriteFile), or stdout (InfinityLoader log); status in
uuid_status.txt. Boot as tools/trigtest: F11 (sent by the runner in the background) opens the load screen, then
loads the save.
--]]

-- UUID_CONFIG

UUIDT = UUIDT or {}
local S = UUIDT
S.MODE = UUID_MODE or 'first'
S.SAVE = UUID_SAVE or 'DIFFTEST'
S.SLOT = UUID_SLOT or 9
S.lines = S.lines or {}
S.state = S.state or 'boot'
S.ticks = 0

local function writeFile(name, text)
	if io and io.open then
		local f = io.open(name, 'w')
		if f then f:write(text) f:close() return true end
	end
	if IEX_WriteFile then return IEX_WriteFile(name, text) end
	return false
end

function S.status(s)
	if IEX_Log then pcall(IEX_Log, '[UUIDT] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, 'uuid_status.txt', tostring(s) .. '\n')
	if not (ok and wrote) then print('UUIDT|STATUS ' .. tostring(s)) end
end

local function out(s) S.lines[#S.lines + 1] = tostring(s) end
S.out = out
function S.flush()
	local ok, wrote = pcall(writeFile, 'uuid_out.txt', table.concat(S.lines, '\n') .. '\n')
	if not (ok and wrote) then
		for i = (S.printed or 0) + 1, #S.lines do print('UUIDT|OUT ' .. S.lines[i]) end
		S.printed = #S.lines
	end
end

-- Value description: type and an exact rendering (numbers as %.17g and, if integral, hex).
local function desc(v)
	local t = type(v)
	if t == 'number' then
		local s = string.format('%.17g', v)
		if v == math.floor(v) and v >= 0 and v < 2^63 then
			local hi, lo = math.floor(v / 2^32), v % 2^32
			s = s .. string.format(' (0x%08X%08X)', hi, lo)
		end
		local mt = math.type and math.type(v)
		return 'number' .. (mt and ('/' .. mt) or '') .. ':' .. s
	elseif t == 'string' then
		return 'string:' .. string.format('%q', v)
	elseif t == 'userdata' then
		return 'userdata'
	elseif t == 'table' then
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		return 'table[' .. n .. ']'
	end
	return t .. ':' .. tostring(v)
end
S.desc = desc

local function pack(...) return { n = select('#', ...), ... } end
local function descAll(r)
	local parts = {}
	for i = 1, r.n do parts[#parts + 1] = desc(r[i]) end
	return r.n .. ' value(s): ' .. table.concat(parts, ', ')
end
local function try(label, fn, ...)
	local r = pack(pcall(fn, ...))
	if r[1] then
		local rest = { n = r.n - 1 }
		for i = 2, r.n do rest[i - 1] = r[i] end
		out(label .. ' -> ' .. descAll(rest))
	else
		out(label .. ' -> ERROR ' .. tostring(r[2]))
	end
	return r
end

S.try = try
S.pack = pack
local function P(i) return EEex_Sprite_GetInPortrait(i) end
S.P = P
local function queue(s, sprite) if sprite then pcall(EEex_Action_QueueResponseStringOnAIBase, s, sprite) end end
local function name(sp)
	if not sp then return 'none' end
	local ok, n = pcall(EEex_Sprite_GetName, sp)
	if ok and n and n ~= '' then return tostring(n) end
	local ok2, s = pcall(function() return sp.m_scriptName:get() end)
	return ok2 and ('script:' .. tostring(s)) or '?'
end
local function idOf(sp)
	local ok, id = pcall(function() return sp.m_id end)
	return ok and id or -1
end

local function localUUID(sp)
	local ok, a, b = pcall(function()
		local v = sp.m_pLocalVariables:find('EEEX_UUID')
		if not v then return nil end
		return v.m_intValue, v.m_dWValue
	end)
	if not ok then
		local ok2, v = pcall(EEex_Sprite_GetLocalInt, sp, 'EEEX_UUID')
		return 'find error ' .. tostring(a) .. ' | GetLocalInt ' .. tostring(v)
	end
	if a == nil then return 'no EEEX_UUID local' end
	return ('EEEX_UUID int=%s dw=%s'):format(tostring(a), tostring(b))
end
S.localUUID = localUUID

local function uuidOf(sp)
	local r = pack(pcall(EEex_Sprite_GetUUID, sp))
	if not r[1] then return nil, 'ERROR ' .. tostring(r[2]) end
	local parts = {}
	for i = 2, r.n do parts[#parts + 1] = desc(r[i]) end
	return r[2], table.concat(parts, ', ')
end
S.uuidOf = uuidOf

-- Every creature of the visible area (and the party).
local function sprites()
	local list, seen = {}, {}
	local function add(sp)
		if sp and not seen[idOf(sp)] then seen[idOf(sp)] = true list[#list + 1] = sp end
	end
	for i = 0, 5 do add(P(i)) end
	pcall(function()
		local area = EEex_Area_GetVisible()
		EEex_Utility_IterateCPtrList(area.m_lVertSort, function(id)
			local o = EEex_GameObject_Get(id)
			if o and o.m_objectType == 49 then add(EEex_GameObject_CastUserType(o)) end
		end)
	end)
	return list
end

local function listUUIDs(label)
	out('--- ' .. label)
	S.byId = S.byId or {}
	local count, uniq, dup = 0, {}, 0
	for _, sp in ipairs(sprites()) do
		local u, d = uuidOf(sp)
		count = count + 1
		local key = tostring(u)
		if u ~= nil then
			if uniq[key] then dup = dup + 1 end
			uniq[key] = true
		end
		local res = '?'
		pcall(function() res = sp.m_resref:get() end)
		out(('  id=%d %s [%s] uuid=%s | %s'):format(idOf(sp), name(sp), tostring(res), d, localUUID(sp)))
		S.byId[idOf(sp)] = u
	end
	out(('  %d creatures, %d duplicate uuid(s)'):format(count, dup))
end

local function introspect(n)
	local fn = _G[n]
	out(n .. ': ' .. type(fn))
	if type(fn) ~= 'function' or not debug or not debug.getinfo then return end
	local ok, info = pcall(debug.getinfo, fn, 'Su')
	if ok and info then
		local names = {}
		for i = 1, (info.nparams or 0) do
			local pn = debug.getlocal and debug.getlocal(fn, i)
			names[#names + 1] = tostring(pn)
		end
		out(('  what=%s nparams=%s vararg=%s params=(%s)'):format(tostring(info.what), tostring(info.nparams),
			tostring(info.isvararg), table.concat(names, ', ')))
	end
end

local function dumpTable(n, depth)
	local t = _G[n]
	out(n .. ': ' .. desc(t))
	if type(t) ~= 'table' then return end
	for k, v in pairs(t) do
		local line = '  [' .. desc(k) .. '] = ' .. desc(v)
		if type(v) == 'table' and (depth or 1) > 0 then
			local sub = {}
			for k2, v2 in pairs(v) do sub[#sub + 1] = desc(k2) .. '=' .. desc(v2) end
			line = line .. ' {' .. table.concat(sub, '; ') .. '}'
		end
		out(line)
	end
end
S.dumpTable = dumpTable

-- Loaded listener: UUID and local at load time (before / after OnAfterEffectListUnmarshalled).
S.loads = S.loads or {}
pcall(EEex_Sprite_AddLoadedListener, function(sp)
	if #S.loads >= 60 then return end
	local u, d = uuidOf(sp)
	S.loads[#S.loads + 1] = ('load id=%d uuid=%s | %s'):format(idOf(sp), tostring(d), localUUID(sp))
end)

local function unpause()
	pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end)
end
local function dismissDialog()
	pcall(function()
		local choices = worldPlayerDialogChoices
		if choices and #choices > 0 and choices[1].marker then
			worldScreen:OnDialogReplyClick(choices[1].marker)
		elseif Infinity_IsMenuOnStack('WORLD_DIALOG') or Infinity_IsMenuOnStack('WORLD_DIALOG_CONFIRM') then
			worldScreen:StepDialog()
		end
	end)
end

local function flushLoads(label)
	out('--- loaded listener calls (' .. label .. '): ' .. #S.loads)
	for _, l in ipairs(S.loads) do out('  ' .. l) end
	S.loads = {}
end

-- UUID_QUIT: after DONE, quit to the start screen (CInfGame::DestroyGame deletes every creature while Lua runs),
-- then shut the program down normally.
function S.quit()
	if not UUID_QUIT then return end
	S.quitting = true
	S.state = 'quit'
	S.status('DONE quit: to start screen')
	pcall(function() optionsScreen:QuitGame() end)
end

S.queue, S.listUUIDs, S.sprites, S.idOf, S.name, S.flushLoads, S.unpause = queue, listUUIDs, sprites, idOf, name, flushLoads, unpause

local FIRST = {
	{ 2, function()
		out('engine ' .. (IEX_Log and 'IEX' or 'EEex') .. ', mode ' .. S.MODE)
		for _, n in ipairs({ 'EEex_Sprite_GetUUID', 'EEex_Sprite_GetFromUUID', 'EEex_Sprite_LoadedWithUUIDCallback' }) do
			introspect(n)
		end
		dumpTable('EEex_Sprite_Private_LoadedWithUUIDCallbacks')
		dumpTable('EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource')
		flushLoads('save load')
		listUUIDs('after load')
	end },
	{ 3, function()
		if UUID_EXTRA then UUID_EXTRA(S, 'first3') end
		unpause()
		queue('CreateCreatureObject("CAT",Myself,0,0,0)', P(0))
		queue('CreateCreatureObject("CAT",Myself,0,0,0)', P(0))
		queue('CreateCreatureObject("RABBIT",Myself,0,0,0)', P(0))
	end },
	{ 6, function()
		flushLoads('spawn')
		listUUIDs('after spawn')
		-- op236 simulacrum of portrait 1 (CGameSprite::Copy)
		local sp = P(0)
		try('ApplyEffect op236 simulacrum', EEex_GameObject_ApplyEffect, sp, { effectID = 236, dwFlags = 2,
			durationType = 0, duration = 600, sourceID = idOf(sp), sourceTarget = idOf(sp) })
	end },
	{ 9, function()
		flushLoads('clone')
		listUUIDs('after clone')
		if UUID_EXTRA then UUID_EXTRA(S, 'first9') end
	end },
	{ 12, function()
		if UUID_EXTRA then UUID_EXTRA(S, 'first12') end
		listUUIDs('before save')
		queue('SaveGame(' .. S.SLOT .. ')', P(0))
		out('SaveGame(' .. S.SLOT .. ') queued')
	end },
	{ 18, function()
		if UUID_EXTRA then UUID_EXTRA(S, 'first18') end
		flushLoads('end')
		S.flush() S.status('DONE ' .. #S.lines)
		S.quit()
	end },
}

local RELOAD = {
	{ 2, function()
		out('engine ' .. (IEX_Log and 'IEX' or 'EEex') .. ', mode ' .. S.MODE)
		flushLoads('save load')
		listUUIDs('after reload')
		if UUID_EXTRA then UUID_EXTRA(S, 'reload2') end
	end },
	{ 12, function()
		if UUID_EXTRA then UUID_EXTRA(S, 'reload6') end
		flushLoads('end')
		S.flush() S.status('DONE ' .. #S.lines)
		S.quit()
	end },
}

local function tickWorld()
	S.ticks = S.ticks + 1
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local elapsed = (t - S.t0) / 1000
	S.done = S.done or {}
	if S.ticks % 30 == 0 then dismissDialog() end
	-- extra files may drive their own steps (UUID_TICK) and hold the last step back (UUID_HOLD() true)
	if UUID_TICK then
		local ok, err = pcall(UUID_TICK, S, elapsed)
		if not ok then out('UUID_TICK error: ' .. tostring(err)) S.flush() end
	end
	local steps = S.MODE == 'reload' and RELOAD or FIRST
	for i, st in ipairs(steps) do
		if i == #steps and UUID_HOLD and UUID_HOLD(elapsed) then break end
		if not S.done[i] and elapsed >= st[1] then
			S.done[i] = true
			local ok, err = pcall(st[2])
			if not ok then out('step ' .. st[1] .. ' error: ' .. tostring(err)) end
			S.flush()
		end
	end
end

function UUIDT_Tick()
	if S.state == 'world' then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- Boot (as tools/trigtest) ------------------------------------------------------------------------------------

local function tickStart()
	if S.quitting then
		-- back on the start screen after optionsScreen:QuitGame(): leave the program the normal way
		S.quitting = false
		S.status('DONE quit: shutting down (' .. S.destroyedSprites .. ' IEX sprite deletes so far)')
		pcall(Infinity_ShutdownGame)
		return
	end
	if S.state ~= 'boot' then return end
	S.startFrames = (S.startFrames or 0) + 1
	if S.startFrames == 30 then S.status('start screen ready') end
end
local function tickLoad()
	if S.state ~= 'loadscreen' then return end
	S.loadFrames = (S.loadFrames or 0) + 1
	if S.loadFrames == 10 then S.status('load screen ready') end
end
local function keyStart()
	local late = S.mainAt and Infinity_GetClockTicks() - S.mainAt > 5000
	if S.state ~= 'boot' or ((S.startFrames or 0) < 30 and not late) then return end
	S.state = 'loadscreen'
	S.loadAt = Infinity_GetClockTicks()
	S.status('opening load screen')
	pcall(function() startEngine:OnLoadGameButtonClick() end)
end
local function keyLoad()
	local late = S.loadAt and Infinity_GetClockTicks() - S.loadAt > 3000
	if S.state ~= 'loadscreen' or ((S.loadFrames or 0) < 10 and not late) then return end
	for _, f in ipairs(gameSaves and gameSaves.files or {}) do
		local label = tostring(f.slotName or '') .. '|' .. tostring(f.fileName or '')
		if label:find(S.SAVE, 1, true) then
			S.state = 'loading'
			S.status('loading ' .. tostring(f.fileName))
			local ok, err = pcall(function() loadScreen:LoadGame(f.fileName) end)
			if not ok then S.status('load error ' .. tostring(err)) end
			return
		end
	end
	S.state = 'failed'
	S.status('save not found')
end

local function enterWorld(via)
	if S.state ~= 'loading' then return end
	S.state = 'world'
	S.status('world (' .. via .. ')')
	if not Infinity_IsMenuOnStack('UUIDT_TICK') then Infinity_PushMenu('UUIDT_TICK') end
end

-- Quit (UUID_QUIT): every creature is deleted inside CInfGame::DestroyGame; the runner then sends F11 (or the start
-- screen shows) and the program shuts down normally.
S.destroyedSprites = 0
pcall(IEX_AddListener or function() end, 'IEX_SpriteDestroyed', function() S.destroyedSprites = S.destroyedSprites + 1 end)
pcall(EEex_GameState_AddDestroyedListener, function()
	if S.state == 'quit' then S.status('DONE quit: game destroyed (' .. S.destroyedSprites .. ' IEX sprite deletes)') end
end)

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
		if S.quitting then
			S.quitting = false
			S.status('DONE quit: shutting down (' .. S.destroyedSprites .. ' IEX sprite deletes so far)')
			pcall(Infinity_ShutdownGame)
			return
		end
		if S.state == 'boot' then keyStart()
		elseif S.state == 'loadscreen' then keyLoad()
		elseif S.state == 'loading' and EEex_Area_GetVisible() ~= nil then enterWorld('key') end
	end)
end)

local function wrapGlobal(n, tick)
	local orig = _G[n]
	if type(orig) ~= 'function' or S['g_' .. n] then return end
	S['g_' .. n] = true
	_G[n] = function(...) pcall(tick) return orig(...) end
end

pcall(EEex_Menu_AddMainFileLoadedListener, function() pcall(function()
	pcall(EEex_Menu_LoadFile, 'UUIDT')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded')
