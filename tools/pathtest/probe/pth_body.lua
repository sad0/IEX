--[[
IEX pathfinding test probe (tools/pathtest). Our own code; observable behaviour only (sprite positions, clocks,
IEX's statistics when present), so the same probe runs under vanilla, EEex + BG Pathfinding Redux and IEX.

Flow: start screen -> load screen -> load the save whose name contains PTH.SAVE (the runner presses F11 in the
background), then in the world:
  each scenario jumps the party back to the positions recorded at load, orders moves (MoveToPoint), samples every
  mover's position each frame until all arrived or the scenario times out, and writes one line per mover:
  time to arrive (ms of game clock), walked length, frames without moving, final distance to the goal.
Scenarios: swap (members exchange places across the group), through (the leader walks to the farthest member's
place through the others, then back), long (all to a far point), stress (random moves around the leader for
PTH.STRESS_MS, crash / hang check).
Output: <game dir>/pathtest_out.txt (io) or IEX/pathtest_out.txt (IEX_WriteFile); status in pathtest_status.txt.
--]]

PTH = PTH or {}
local P = PTH
P.SAVE = P.SAVE or 'PATHTEST'
P.OUT = 'pathtest_out.txt'
P.STATUS = 'pathtest_status.txt'
P.lines = {}
P.state = 'boot'

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

function P.status(s)
	if IEX_Log then pcall(IEX_Log, '[PTH] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, P.STATUS, s .. '\n')
	if not (ok and wrote) then print('PTH|STATUS ' .. tostring(s)) end
end

function P.emit(s)
	P.lines[#P.lines + 1] = s
	local ok, wrote = pcall(writeFile, P.OUT, table.concat(P.lines, '\n') .. '\n')
	if not (ok and wrote) then print('PTH|' .. s) end
end

local function now() return Infinity_GetClockTicks() end

-- Settings from Baldur.lua [PathTest] (seeded by the runner).
local function iniNum(key, default)
	local ok, v = pcall(Infinity_GetINIValue, 'PathTest', key, default)
	return ok and tonumber(v) or default
end

local function party()
	local list = {}
	for slot = 0, 5 do
		local s = EEex_Sprite_GetInPortrait(slot)
		if s then list[#list + 1] = s end
	end
	return list
end

local function pos(s) return s.m_pos.x, s.m_pos.y end
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function act(s, text)
	EEex_Action_QueueResponseStringOnAIBase(text, s)
end

local function iexStats()
	if not IEX_PathfindingRedux then return '' end
	local check = ''
	if IEX_PathfindingCheck and P.home and P.home[1] then
		local ok, bad, used, first = pcall(IEX_PathfindingCheck, EEex_UDToPtr(P.home[1].s))
		check = string.format(' map_bad=%s map_used=%s map_first=%s', tostring(bad), tostring(used), tostring(first)):gsub(' ', ' ')
	end
	local ok, t = pcall(IEX_PathfindingRedux)
	if not ok or type(t) ~= 'table' then return ' iex=error' end
	return string.format(' iex_enabled=%s scopes=%d scope_cells=%d searches=%d snap_searches=%d snap_cells=%d search_ms=%.2f max_search_ms=%.3f overhead_ms=%.2f max_overhead_ms=%.3f dropped=%d',
		tostring(t.enabled), t.scopes, t.scopeCells, t.searches, t.snapshotSearches, t.snapshotCells,
		t.searchMs, t.maxSearchMs, t.overheadMs, t.maxOverheadMs, t.droppedScopes) .. check
end

-----------------------------------------------------------------------
-- Scenarios
-----------------------------------------------------------------------

local scen = {}  -- current scenario run

local function startRun(name, orders, timeoutMs)
	scen = { name = name, orders = orders, t0 = now(), timeout = timeoutMs, movers = {} }
	for _, o in ipairs(orders) do
		local x, y = pos(o.s)
		scen.movers[#scen.movers + 1] = { s = o.s, id = o.s.m_id, gx = o.x, gy = o.y, lx = x, ly = y, len = 0,
			still = 0, arrived = nil, sx = x, sy = y, path = { string.format('%d,%d', x, y) } }
		act(o.s, string.format('MoveToPoint([%d.%d])', o.x, o.y))
	end
	P.status('scenario ' .. name)
end

local ARRIVE = 24  -- px: within 1.5 search cells of the goal

local function stepRun()
	local t = now() - scen.t0
	local all = true
	for _, m in ipairs(scen.movers) do
		local x, y = pos(m.s)
		local d = dist(x, y, m.lx, m.ly)
		if d > 0 then m.len = m.len + d else if not m.arrived then m.still = m.still + 1 end end
		if d > 0 and #m.path < 400 and dist(x, y, m.px or m.sx, m.py or m.sy) >= 16 then
			m.path[#m.path + 1] = string.format('%d,%d', x, y)
			m.px, m.py = x, y
		end
		m.lx, m.ly = x, y
		local action = m.s.m_curAction.m_actionID
		if not m.arrived and dist(x, y, m.gx, m.gy) <= ARRIVE then m.arrived = t end
		-- done: arrived, or stopped (no action) somewhere else
		if not m.arrived and not (action == 0 and t > 1500) then all = false end
		m.lastAction = action
	end
	if all or t > scen.timeout then
		for _, m in ipairs(scen.movers) do
			local x, y = pos(m.s)
			P.emit(string.format('%s mover=%d start=%d,%d goal=%d,%d end=%d,%d arrived_ms=%s len=%d still_frames=%d goal_dist=%d timeout=%s path=%s',
				scen.name, m.id, m.sx, m.sy, m.gx, m.gy, x, y, tostring(m.arrived or -1), m.len, m.still,
				dist(x, y, m.gx, m.gy), tostring(not all), table.concat(m.path, ';')))
		end
		local off = 0
		for _, m in ipairs(scen.movers) do
			for _, h in ipairs(P.home) do if h.s == m.s then off = off + dist(m.sx, m.sy, h.x, h.y) end end
		end
		P.emit(string.format('%s start_offset=%d', scen.name, off))
		if scen.name == 'swap_combat' and P.combatArea then
			pcall(function() P.combatArea.m_nBattleSongCounter = 0 end)
			IEX_PathfindingRedux({ combatOnly = false })
		end
		P.emit(string.format('%s summary wall_ms=%d all_done=%s%s', scen.name, now() - scen.t0, tostring(all), iexStats()))
		scen = {}
		return true
	end
	return false
end

-- Puts every member back on its recorded start position (JumpToPoint), then waits a few frames.
local function resetParty()
	for _, h in ipairs(P.home) do
		pcall(EEex_Action_ExecuteResponseStringOnAIBaseInstantly, 'ClearActions(Myself)', h.s)
		local ok = pcall(EEex_Action_ExecuteResponseStringOnAIBaseInstantly, string.format('JumpToPoint([%d.%d])', h.x, h.y), h.s)
		if not ok then act(h.s, string.format('JumpToPoint([%d.%d])', h.x, h.y)) end
	end
end

local function buildPlan()
	local list = party()
	P.home = {}
	for _, s in ipairs(list) do
		local x, y = pos(s)
		P.home[#P.home + 1] = { s = s, x = x, y = y }
	end
	local n = #P.home
	local plan = {}
	-- swap: member i -> place of member (i + n/2)
	plan[#plan + 1] = function()
		local o = {}
		for i, h in ipairs(P.home) do
			local t = P.home[((i - 1 + math.floor(n / 2)) % n) + 1]
			o[#o + 1] = { s = h.s, x = t.x, y = t.y }
		end
		return 'swap', o, 30000
	end
	-- through: the leader to the farthest member's place, then back
	local far, fd = P.home[1], -1
	for _, h in ipairs(P.home) do
		local d = dist(h.x, h.y, P.home[1].x, P.home[1].y)
		if d > fd then far, fd = h, d end
	end
	plan[#plan + 1] = function() return 'through', { { s = P.home[1].s, x = far.x, y = far.y } }, 20000 end
	plan[#plan + 1] = function()
		local o = {}
		for _, h in ipairs(P.home) do
			if h ~= P.home[1] then o[#o + 1] = { s = h.s, x = P.home[1].x, y = P.home[1].y } end
		end
		return 'converge', o, 25000
	end
	-- swap_combat (IEX only): the same swap with the out-of-combat-only mode on and the area's battle-song counter
	-- set (the engine counts it down): allies must block one another again. Restored afterwards.
	if IEX_PathfindingRedux then
		plan[#plan + 1] = function()
			local area = P.home[1].s.m_pArea
			P.combatArea = area
			pcall(function() area.m_nBattleSongCounter = 100000 end)
			IEX_PathfindingRedux({ combatOnly = true })
			P.emit(string.format('swap_combat setup battle=%s blocked=%s', tostring(area.m_nBattleSongCounter),
				tostring(IEX_PathfindingRedux().combatBlocked)))
			local o = {}
			for i, h in ipairs(P.home) do
				local t = P.home[((i - 1 + math.floor(n / 2)) % n) + 1]
				o[#o + 1] = { s = h.s, x = t.x, y = t.y }
			end
			return 'swap_combat', o, 15000
		end
	end
	-- long: everybody to points far from the leader (several directions; unreachable ones end at once)
	for _, d in ipairs({ { 'long_e', 600, 0 }, { 'long_w', -600, 0 }, { 'long_s', 0, 500 }, { 'long_se', 450, 400 }, { 'long_sw', -450, 400 } }) do
		plan[#plan + 1] = function()
			local o = {}
			for _, h in ipairs(P.home) do o[#o + 1] = { s = h.s, x = P.home[1].x + d[2], y = P.home[1].y + d[3] } end
			return d[1], o, 45000
		end
	end
	return plan
end

local rng = 12345
local function rand(n)
	rng = (rng * 1103515245 + 12345) % 2147483648
	return rng % n
end

local function stressTick()
	local t = now()
	if t - P.stressLast >= 4000 then
		P.stressLast = t
		P.stressOrders = P.stressOrders + 1
		for _, h in ipairs(P.home) do
			local x = P.home[1].x + rand(500) - 250
			local y = P.home[1].y + rand(380) - 190
			act(h.s, string.format('MoveToPoint([%d.%d])', x, y))
		end
	end
	if t - P.stressReport >= 60000 then
		P.stressReport = t
		P.emit(string.format('stress minute=%d orders=%d%s', math.floor((t - P.stressT0) / 60000), P.stressOrders, iexStats()))
		P.status(string.format('stress %d s', math.floor((t - P.stressT0) / 1000)))
	end
	return t - P.stressT0 >= P.stressMs
end

local function tickWorld()
	if P.state ~= 'world' then return end
	P.frames = (P.frames or 0) + 1
	if not P.plan then
		if P.frames < 60 then return end
		P.plan = buildPlan()
		P.step = 0
		P.wait = 0
		local cs = MRIP_CompatibilityStatus
		P.emit(string.format('setup members=%d area=%s mod_status=%s mod_provider=%s mod_trace=%s iex_feature=%s%s',
			#P.home, tostring(select(2, pcall(function() return P.home[1].s.m_pArea.m_resref:get() end))),
			tostring(cs and cs.supported), tostring(cs and cs.provider), tostring(MRIP_TraceEnabled),
			tostring(IEX_Features and IEX_Features.pathfindingRedux), iexStats()))
		return
	end
	if P.wait > 0 then
		P.wait = P.wait - 1
		if P.wait == 25 then resetParty() end  -- second pass: places that were still taken on the first one
		return
	end
	if scen.name then
		if stepRun() then resetParty(); P.wait = 45 end
		return
	end
	P.step = P.step + 1
	local f = P.plan[P.step]
	if f then
		startRun(f())
		return
	end
	if not P.stressT0 then
		P.stressMs = iniNum('StressMs', 120000)
		P.stressT0, P.stressLast, P.stressReport, P.stressOrders = now(), 0, now(), 0
		P.status('stress start')
		return
	end
	if stressTick() then
		P.emit(string.format('stress done ms=%d orders=%d%s', now() - P.stressT0, P.stressOrders, iexStats()))
		P.state = 'done'
		P.status('DONE ' .. #P.lines)
	end
end

-----------------------------------------------------------------------
-- Boot: start screen, load screen, world (key presses from the runner)
-----------------------------------------------------------------------

local function tickStart()
	if P.state ~= 'boot' then return end
	P.startFrames = (P.startFrames or 0) + 1
	if P.startFrames == 30 then P.status('start screen ready') end
end
local function tickLoad()
	if P.state ~= 'loadscreen' then return end
	P.loadFrames = (P.loadFrames or 0) + 1
	if P.loadFrames == 10 then P.status('load screen ready') end
end
local function keyLoad()
	local files = gameSaves and gameSaves.files or {}
	local names = {}
	for _, f in ipairs(files) do
		local label = tostring(f.slotName or '') .. '|' .. tostring(f.fileName or '')
		names[#names + 1] = label
		if label:find(P.SAVE, 1, true) then
			P.state = 'loading'
			P.status('loading ' .. tostring(f.fileName))
			local ok, err = pcall(function() loadScreen:LoadGame(f.fileName) end)
			if not ok then P.status('load error ' .. tostring(err)) end
			return
		end
	end
	P.state = 'failed'
	P.status('save not found: ' .. table.concat(names, ' ; '))
end

local function enterWorld(via)
	P.state = 'world'
	P.status('world (' .. via .. ')')
	pcall(function() if not Infinity_IsMenuOnStack('PTH_TICK') then Infinity_PushMenu('PTH_TICK') end end)
end

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
		if P.state == 'boot' and (P.startFrames or 0) >= 30 and P.books and not P.campaign then
			-- BG2EE's three-book start screen: choose SoA first, then the load button (next key press)
			P.campaign = true
			P.startFrames = 0
			P.status('campaign SoA')
			pcall(function() startEngine:OnSoAButtonClick(true) end)
			pcall(function() Infinity_PushMenu('START_MAIN') end)
		elseif P.state == 'boot' and (P.startFrames or 0) >= 30 then
			P.state = 'loadscreen'
			P.status('opening load screen')
			local ok, err = pcall(function() startEngine:OnLoadGameButtonClick() end)
			if not ok then P.status('load screen error ' .. tostring(err)) end
		elseif P.state == 'loadscreen' and (P.loadFrames or 0) >= 10 then
			keyLoad()
		elseif P.state == 'loading' and EEex_Area_GetVisible() ~= nil then
			enterWorld('key')
		end
	end)
end)

function PTH_Tick()
	local ok, err = pcall(tickWorld)
	if not ok then P.status('tick error ' .. tostring(err)); P.state = 'done'; P.emit('error ' .. tostring(err)) end
	return false
end

local function wrapGlobal(name, tick)
	local orig = _G[name]
	if type(orig) ~= 'function' or P['wrapped_' .. name] then return end
	P['wrapped_' .. name] = true
	_G[name] = function(...)
		pcall(tick)
		return orig(...)
	end
end

pcall(EEex_Menu_AddMainFileLoadedListener, function() pcall(function()
	pcall(EEex_Menu_LoadFile, 'PTH')
	wrapGlobal('getTitle', tickStart)
	if type(startThreeBookHighlight) == 'function' then P.books = true end
	wrapGlobal('startThreeBookHighlight', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	P.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(function()
	if P.state == 'loading' then enterWorld('initialized') end
end) end)

pcall(P.status, 'probe loaded')
