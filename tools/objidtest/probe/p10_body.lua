--[[
Object id / area transition probe (tools/objidtest, our own code). Loads save P10TEST, then repeats what the BOT did
before the 2026-11-01 crash: ClearActions(Myself) instantly on each party member, then LeaveAreaLUA(area,"",[x.y],10)
queued on each member 20 ms apart, AR1000 <-> AR0500, P10_ROUNDS times (default 6). Logs the CGameObjectArray
statics (Windows addresses; -1 elsewhere) and IEX_ObjectIdInfo() after each round.
Options (set by the runner's -Config): P10_POKE = n writes n into m_maxArrayIndex and m_nextObjectId (Windows):
the object table is then about to run out, as after hours of play; P10_POKEKEY = n writes m_nextObjectId only.
Status in IEX/p10_status.txt, lines in IEX/p10_out.txt.
--]]
P10 = P10 or {}
-- P10_CONFIG

local S = P10
S.SAVE = S.SAVE or 'P10TEST'
S.state = S.state or 'boot'
S.lines = S.lines or {}

local function writeFile(name, text) if IEX_WriteFile then return IEX_WriteFile(name, text) end end
function S.status(s)
	pcall(IEX_Log, '[P10] ' .. tostring(s))
	pcall(writeFile, 'p10_status.txt', tostring(s) .. '\n')
end
local function out(s) S.lines[#S.lines + 1] = s pcall(IEX_Log, '[P10] ' .. s) pcall(writeFile, 'p10_out.txt', table.concat(S.lines, '\n') .. '\n') end

local function members()
	local t = {}
	local n = EEex_Sprite_GetNumCharacters()
	for i = 0, math.max(n, 6) + 4 do
		local sp = EEex_Sprite_GetInPortrait(i)
		if sp then t[#t + 1] = sp end
	end
	return t
end
local function areaName(sp)
	local ok, r = pcall(function() return sp.m_pArea.m_resref:get() end)
	return ok and tostring(r) or '?'
end

local function info(tag)
	local ms = members()
	local parts = {}
	for i, sp in ipairs(ms) do parts[#parts + 1] = (i - 1) .. ':' .. string.format('%08x', sp.m_id) .. '@' .. areaName(sp) end
	local function w(a) local ok, v = pcall(EEex_ReadU16, 0x140000000 + a) return ok and v or -1 end
	out(('%s objarray cap=%d maxSlot=%d key=%d free=%d crit=%d'):format(tag, w(0x68f8f0), w(0x68f8f4), w(0x68f8f8), w(0x68f8fc), w(0x68f900)))
	if IEX_ObjectIdInfo then
		local d = IEX_ObjectIdInfo()
		out(('%s objids active=%s adds=%d reused=%d wraps=%d nextKey=%d'):format(tag, tostring(d.active), d.adds, d.reused, d.wraps, d.nextKey))
	end
	out(tag .. ' n=' .. EEex_Sprite_GetNumCharacters() .. ' found=' .. #ms .. ' ' .. table.concat(parts, ' '))
end

S.TARGET = S.TARGET or { 'AR0500', 3000, 2000 }
S.ROUND = 0

local function startTravel()
	local ms = members()
	S.ROUND = S.ROUND + 1
	local cur = areaName(ms[1])
	local dest = S.TARGET
	if cur == dest[1] then dest = S.BACK or { 'AR1000', 1000, 1000 } end
	S.dest = dest[1]
	out(('round %d: %s -> %s'):format(S.ROUND, cur, dest[1]))
	for _, sp in ipairs(ms) do
		pcall(EEex_Action_ExecuteResponseStringOnAIBaseInstantly, 'ClearActions(Myself)', sp)
	end
	S.pending = {}
	local t = Infinity_GetClockTicks()
	for i, sp in ipairs(ms) do
		S.pending[#S.pending + 1] = { at = t + (i - 1) * 20, id = sp.m_id,
			s = ('LeaveAreaLUA("%s","",[%d.%d],10)'):format(dest[1], dest[2], dest[3]) }
	end
end

local function runPending()
	if not S.pending then return end
	local t = Infinity_GetClockTicks()
	local rest = {}
	for _, p in ipairs(S.pending) do
		if t >= p.at then
			local sp = EEex_GameObject_Get(p.id)
			if sp then pcall(EEex_Action_QueueResponseStringOnAIBase, p.s, sp) end
		else
			rest[#rest + 1] = p
		end
	end
	S.pending = #rest > 0 and rest or nil
end

S.ROUNDS = P10_ROUNDS or S.ROUNDS or 6
local function tickWorld()
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local e = (t - S.t0) / 1000
	runPending()
	pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end)
	if not S.infoDone and e > 3 then
		S.infoDone = true
		info('start')
		if P10_POKEKEY then
			pcall(EEex_WriteU16, 0x140000000 + 0x68f8f8, P10_POKEKEY)
			info('pokedkey')
		end
		if P10_POKE then
			pcall(EEex_WriteU16, 0x140000000 + 0x68f8f4, P10_POKE)
			pcall(EEex_WriteU16, 0x140000000 + 0x68f8f8, P10_POKE)
			info('poked')
		end
	end
	S.nextRound = S.nextRound or 5
	if e >= S.nextRound and S.ROUND < S.ROUNDS then
		if S.ROUND > 0 then info('after round ' .. S.ROUND) end
		S.nextRound = e + 12
		startTravel()
	elseif S.ROUND >= S.ROUNDS and e >= S.nextRound and not S.finished then
		S.finished = true
		info('end')
		S.status('DONE')
		return
	end
	if math.floor(e) ~= S.lastSec then S.lastSec = math.floor(e) S.status(('alive %d round %d'):format(S.lastSec, S.ROUND)) end
end

function P10_Tick()
	if S.state == 'world' and not S.finished then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- Boot (same as tools/fixtest) ---------------------------------------------------------------------------------
local function tickStart()
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
	if not Infinity_IsMenuOnStack('P10_TICK') then Infinity_PushMenu('P10_TICK') end
end
pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
		if S.state == 'boot' then keyStart()
		elseif S.state == 'loadscreen' then keyLoad()
		elseif S.state == 'loading' and EEex_Area_GetVisible() ~= nil then enterWorld('key') end
	end)
end)
local function wrapGlobal(name, tick)
	local orig = _G[name]
	if type(orig) ~= 'function' or S['g_' .. name] then return end
	S['g_' .. name] = true
	_G[name] = function(...) pcall(tick) return orig(...) end
end
pcall(EEex_Menu_AddMainFileLoadedListener, function() pcall(function()
	pcall(EEex_Menu_LoadFile, 'P10')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)
pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)
S.status('probe loaded')
