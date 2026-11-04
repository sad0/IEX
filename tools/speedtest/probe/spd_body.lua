--[[
IEX game speed / frame rate test probe (tools/speedtest). Our own code; observable behaviour only (clocks, game
time, sprite positions, counters), so the same probe runs under EEex and under IEX.

Flow: start screen -> load screen -> load the save whose name contains SPD.SAVE (the runner presses F11 in the
background), then in the world, one phase per entry of [SpeedTest] 'Phases' (Baldur.lua, seeded by the runner):
  "<rate>[c]"  sets EEex_CChitin.TIMER_UPDATES_PER_SECOND = rate (what Tweaks Anthology's Dynamic FPS and
               BuffBot's fast mode write); 'c' = the area's battle-song counter is held above 0 (combat).
  "ta"         Tweaks Anthology's Dynamic FPS rule each frame (out of combat: 60, in combat / cutscene: 30),
  "tac"        same rule with the area in combat.
Per phase (after a 1.5 s settle): frames drawn per real second (this probe's menu runs once per drawn frame),
game time (CTimerWorld m_gameTime) per real second, the engine's tick rate where IEX reports it, and the leader's
walking speed (px per real second and per game tick, from its first step to 2.5 s later).
Output: <game dir>/speedtest_out.txt (io) or IEX/speedtest_out.txt (IEX_WriteFile); status in speedtest_status.txt.
--]]

SPD = SPD or {}
local P = SPD
P.SAVE = P.SAVE or 'SPEEDTEST'
P.OUT = 'speedtest_out.txt'
P.STATUS = 'speedtest_status.txt'
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
	if IEX_Log then pcall(IEX_Log, '[SPD] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, P.STATUS, s .. '\n')
	if not (ok and wrote) then print('SPD|STATUS ' .. tostring(s)) end
end

function P.emit(s)
	P.lines[#P.lines + 1] = s
	local ok, wrote = pcall(writeFile, P.OUT, table.concat(P.lines, '\n') .. '\n')
	if not (ok and wrote) then print('SPD|' .. s) end
end

local function now() return Infinity_GetClockTicks() end
local function chitin() return EngineGlobals and EngineGlobals.g_pBaldurChitin or EEex_EngineGlobal_CBaldurChitin end
local function gtime() return chitin().m_pObjectGame.m_worldTime.m_gameTime end
local function tps() return EEex_CChitin.TIMER_UPDATES_PER_SECOND end

local function iniStr(key, default)
	local ok, v = pcall(Infinity_GetINIString, 'SpeedTest', key, default)
	if ok and v and v ~= '' then return v end
	return default
end

local function iniNum(section, key, default)
	local ok, v = pcall(Infinity_GetINIValue, section, key, default)
	return ok and tonumber(v) or default
end

local function leader() return EEex_Sprite_GetInPortrait(0) end
local function area() local s = leader() return s and s.m_pArea end

local function setCombat(on)
	local a = area()
	if a then pcall(function() a.m_nBattleSongCounter = on and 100000 or 0 end) end
end

local function inCombat()
	local a = area()
	return a and a.m_nBattleSongCounter > 0
end

-- Tweaks Anthology "Dynamic FPS Change" rule (observable behaviour of its Lua action, run here every frame).
local function taRule()
	local want = inCombat() and 30 or 60
	if tps() ~= want then EEex_CChitin.TIMER_UPDATES_PER_SECOND = want end
end

local function engineRates()
	if IEX_GetRenderRate then
		local ok, f, t = pcall(IEX_GetRenderRate)
		if ok then return f, t end
	end
	return -1, -1
end

local SETTLE, MEASURE = 1500, 5000
local WALK = tonumber(iniStr('WalkMs', '2500')) or 2500

-----------------------------------------------------------------------
-- "atk" phase: SadoEE attack-move (M_SQATKM.lua) into enemies spawned next to the party. Counts, per member, the
-- Attack actions SadoEE queues (EEex_Action_QueueResponseStringOnAIBase wrapped) and the current action ids seen
-- each frame, so a re-issued Attack (one feedback line each) shows up as attackQueues >> 1.
-----------------------------------------------------------------------
local ATK_MS = tonumber(iniStr('AtkMs', '15000')) or 15000

local function atkStart(ph)
	local l = leader()
	local x, y = l.m_pos.x, l.m_pos.y
	ph.atk = { queues = {}, hist = {}, changes = {}, last = {}, started = {} }
	if not P.queueWrapped then
		P.queueWrapped = true
		local orig = EEex_Action_QueueResponseStringOnAIBase
		EEex_Action_QueueResponseStringOnAIBase = function(str, sprite, ...)
			local a = P.ph and P.ph.atk
			if a and type(str) == 'string' and str:find('^Attack%(') and sprite then
				a.queues[sprite.m_id] = (a.queues[sprite.m_id] or 0) + 1
				local r = { n = select("#", orig(str, sprite, ...)) } -- orig returns nothing
				if (a.queues[sprite.m_id] or 0) <= 2 then
					local ids = {}
					EEex_Utility_IterateCPtrList(sprite.m_queuedActions, function(q) ids[#ids + 1] = q.m_actionID .. '>' .. tostring(q.m_acteeID.m_Instance) end)
					P.emit(string.format('  atk queued id=%d str=%s cur=%d queue=%s lua=%s', sprite.m_id, str,
						sprite.m_curAction.m_actionID, table.concat(ids, ','), tostring(EEex_LuaObject and EEex_LuaObject.m_id)))
				end
				return
			end
			return orig(str, sprite, ...)
		end
		pcall(EEex_Action_AddSpriteStartedActionListener, function(sp, act)
			local a = P.ph and P.ph.atk
			if a and act.m_actionID == 3 then a.started[sp.m_id] = (a.started[sp.m_id] or 0) + 1 end
		end)
	end
	local cre = iniStr('AtkCre', 'OGRE01')
	local n = tonumber(iniStr('AtkCount', '3')) or 3
	if n > 0 then ph.atk.spawned = n end
	for i = 1, n do
		local ex, ey = x + 90 + 30 * i, y + 40 * (i - 2)
		pcall(EEex_Action_QueueResponseStringOnAIBase,
			string.format('CreateCreature("%s",[%d.%d],0)', cre, ex, ey), l)
	end
	ph.atk.tx, ph.atk.ty = x + 160, y
	local g = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
	pcall(function()
		g:UnselectAll()
		for slot = 0, 5 do local m = EEex_Sprite_GetInPortrait(slot) if m then g:SelectCharacter(m.m_id, false) end end
	end)
end

local function atkStep(ph, t)
	local a = ph.atk
	if not a.ordered and t >= 1500 then
		a.ordered = true
		a.foes = 0
		a.listAll = iniStr('AtkListAll', '0') == '1'
		pcall(function()
			EEex_Utility_IterateCPtrList(area().m_lVertSort, function(id)
				local o = EEex_GameObject_Get(id)
				if o and o.m_objectType == 49 then
					local sp = EEex_GameObject_CastUserType(o)
					if sp.m_typeAI.m_EnemyAlly >= 200 or a.listAll then
						if sp.m_typeAI.m_EnemyAlly >= 200 then a.foes = a.foes + 1 end
						if sp.m_typeAI.m_EnemyAlly >= 200 and EEex_BAnd(sp.m_baseStats.m_generalState, 0xFC0) == 0 then
							local l0 = leader()
							local d0 = (sp.m_pos.x - l0.m_pos.x) ^ 2 + (sp.m_pos.y - l0.m_pos.y) ^ 2
							if not a.nearest or d0 < a.nearest.d then a.nearest = { x = sp.m_pos.x, y = sp.m_pos.y, d = d0 } end
						end
						local l = leader()
						local d = math.floor(math.sqrt((sp.m_pos.x - l.m_pos.x) ^ 2 + (sp.m_pos.y - l.m_pos.y) ^ 2))
						a.seeScript = a.seeScript or EEex_Trigger_ParseConditionalString('See(EEex_LuaObject)')
						EEex_LuaObject = o
						local okSee, seen = pcall(EEex_Trigger_EvalScriptFileConditionalAsAIBase, a.seeScript, l)
						if d < 600 then
							P.emit(string.format('  atk foe id=%d ea=%d state=0x%x d=%d see=%s', id, sp.m_typeAI.m_EnemyAlly,
								sp.m_baseStats.m_generalState, d, tostring(okSee and seen or seen)))
						end
					end
				end
			end)
		end)
		-- AtkTarget=foe: the order goes to the nearest living hostile of the area (an existing fight)
		if iniStr('AtkTarget', '') == 'foe' and a.nearest then a.tx, a.ty = a.nearest.x, a.nearest.y end
		local ok, err = pcall(SQAttackMove_At, a.tx, a.ty, false)
		a.orderErr = not ok and tostring(err) or nil
	end
	for slot = 0, 5 do
		local m = EEex_Sprite_GetInPortrait(slot)
		if m then
			local id = m.m_id
			local cur = m.m_curAction.m_actionID
			a.hist[id] = a.hist[id] or {}
			a.hist[id][cur] = (a.hist[id][cur] or 0) + 1
			if a.last[id] ~= nil and a.last[id] ~= cur then a.changes[id] = (a.changes[id] or 0) + 1 end
			a.last[id] = cur
		end
	end
	if t < ATK_MS then return false end
	for slot = 0, 5 do
		local m = EEex_Sprite_GetInPortrait(slot)
		if m then
			local id = m.m_id
			local h = {}
			for k, v in pairs(a.hist[id] or {}) do h[#h + 1] = k .. ':' .. v end
			table.sort(h)
			P.emit(string.format('  atk slot=%d class=%d attackQueues=%d attackStarted=%d actionChanges=%d curActions=%s',
				slot, m.m_typeAI.m_Class, a.queues[id] or 0, a.started[id] or 0, a.changes[id] or 0, table.concat(h, ',')))
		end
	end
	P.emit('  atk foes=' .. tostring(a.foes) .. ' order=' .. tostring(a.ordered) .. ' err=' .. tostring(a.orderErr) .. ' sqErr=' .. tostring(SQAtkM and SQAtkM.lastError)
		.. ' orderLeft=' .. tostring(SQAtkM and SQAtkM.order ~= nil))
	pcall(function() SQAtkM.order = nil end)
	return true
end

local function startPhase(spec)
	local ph = { spec = spec, t0 = now() }
	ph.ta = spec:find('^ta') ~= nil
	ph.combat = spec:sub(-1) == 'c'
	if spec == 'clr' then
		-- ClearActions(Myself) run instantly (EEex_Action_ExecuteResponseStringOnAIBaseInstantly) on a walking leader
		local l = leader()
		ph.clr = { x = l.m_pos.x, y = l.m_pos.y }
		EEex_Action_QueueResponseStringOnAIBase(string.format('MoveToPoint([%d.%d])', P.homeX + 300, P.homeY + 120), l)
		EEex_Action_QueueResponseStringOnAIBase('SmallWait(5)', l)
		P.ph = ph
		P.status('phase clr')
		return
	end
	if spec == 'atk' then
		ph.combat = false
		atkStart(ph)
		P.ph = ph
		P.status('phase atk')
		return
	end
	ph.rate = tonumber(spec:match('^(%d+)'))
	setCombat(ph.combat)
	if ph.rate then EEex_CChitin.TIMER_UPDATES_PER_SECOND = ph.rate end
	-- "bb<rate>": the write comes from a chunk named like BuffBot's fast mode file (BfBotFst.lua)
	local bb = tonumber(spec:match('^bb(%d+)'))
	if bb then
		local f = (loadstring or load)('return function(v) EEex_CChitin.TIMER_UPDATES_PER_SECOND = v end', '@BfBotFst.lua')()
		f(bb)
		P.bbReset = f
	end
	if ph.ta then taRule() end
	-- walk: the leader goes back and forth between its place at load and the farthest member's place at load
	local s = leader()
	P.flip = not P.flip
	local gx, gy = P.homeX, P.homeY
	if P.flip then gx, gy = P.homeX + iniNum('SpeedTest', 'WalkDX', 350), P.homeY + iniNum('SpeedTest', 'WalkDY', 150) end
	ph.sx, ph.sy, ph.lx, ph.ly, ph.len = s.m_pos.x, s.m_pos.y, s.m_pos.x, s.m_pos.y, 0
	EEex_Action_QueueResponseStringOnAIBase(string.format('MoveToPoint([%d.%d])', gx, gy), s)
	ph.gx, ph.gy = gx, gy
	P.ph = ph
	P.status('phase ' .. spec)
end

local function stepPhase()
	local ph = P.ph
	local t = now() - ph.t0
	if ph.clr then
		local c, l = ph.clr, leader()
		local function state(tag)
			local ids = {}
			EEex_Utility_IterateCPtrList(l.m_queuedActions, function(q) ids[#ids + 1] = tostring(q.m_actionID) end)
			P.emit(string.format('  clr %s cur=%d queue=[%s] pos=%d,%d', tag, l.m_curAction.m_actionID, table.concat(ids, ','),
				l.m_pos.x, l.m_pos.y))
		end
		if not c.done and t >= 1200 then
			c.done = true
			state('before')
			EEex_Action_ExecuteResponseStringOnAIBaseInstantly('ClearActions(Myself)', l)
			state('after')
			c.after = now()
		end
		if c.after and not c.late and now() - c.after >= 600 then
			c.late = true
			state('600ms')
			P.emit('phase=clr')
			P.ph = nil
			return true
		end
		return false
	end
	if ph.atk then
		if atkStep(ph, t) then
			P.emit(string.format('phase=atk tps=%d game_ticks=%d', tps(), gtime()))
			P.ph = nil
			return true
		end
		return false
	end
	if ph.ta then taRule() end
	if ph.combat then setCombat(true) end
	local s = leader()
	local x, y = s.m_pos.x, s.m_pos.y
	-- walk measure: path length from the first step until WALK ms later or until it stops (400 ms still)
	if not ph.act and t >= 300 then
		ph.act = string.format('%s/dlg=%s/goal=%d,%d/pos=%d,%d', tostring(s.m_curAction.m_actionID),
			tostring(Infinity_IsMenuOnStack('WORLD_DIALOG')), ph.gx, ph.gy, x, y)
	end
	local d = math.sqrt((x - ph.lx) ^ 2 + (y - ph.ly) ^ 2)
	ph.lx, ph.ly = x, y
	if not ph.w0 and d > 0 then ph.w0, ph.wg0, ph.wlast, ph.wglast = now(), gtime(), now(), gtime() end
	if ph.w0 and not ph.wdone then
		if d > 0 then ph.len, ph.wlast, ph.wglast = ph.len + d, now(), gtime() end
		if now() - ph.w0 >= WALK or now() - ph.wlast >= 400 then
			ph.wdone = { d = ph.len, ms = math.max(1, ph.wlast - ph.w0), g = ph.wglast - ph.wg0 }
		end
	end
	if t >= SETTLE and not ph.m0 then
		ph.m0, ph.g0, ph.frames = now(), gtime(), 0
	end
	if ph.m0 then
		ph.frames = ph.frames + 1
		local f, k = engineRates()
		ph.ef, ph.ek = f, k
	end
	if ph.m0 and now() - ph.m0 >= MEASURE and (ph.wdone or now() - ph.t0 > 15000) then
		local ms = now() - ph.m0
		local w = ph.wdone or { d = 0, ms = 1, g = 0 }
		P.emit(string.format('phase=%s tps_now=%d combat=%s frames_per_s=%.1f game_ticks_per_s=%.2f engine_fps=%d engine_tps=%d walk_px=%.0f walk_ms=%d walk_px_per_s=%.1f walk_px_per_gametick=%.2f act=%s',
			ph.spec, tps(), tostring(inCombat()), ph.frames * 1000 / ms, (gtime() - ph.g0) * 1000 / ms, ph.ef, ph.ek,
			w.d, w.ms, w.d * 1000 / w.ms, w.g > 0 and w.d / w.g or 0, tostring(ph.act)))
		if IEX_GetFrameRate then
			P.emit('  iex_frame_rate=' .. table.concat({ tostring(select(1, IEX_GetFrameRate())), tostring(select(2, IEX_GetFrameRate())),
				tostring(select(3, IEX_GetFrameRate())), tostring(select(4, IEX_GetFrameRate())), tostring(select(5, IEX_GetFrameRate())),
				tostring(select(6, IEX_GetFrameRate())) }, ',') .. ' interp=' .. (IEX_GetFrameInterpolation and table.concat({ tostring(select(2, IEX_GetFrameInterpolation())),
				tostring(select(3, IEX_GetFrameInterpolation())), tostring(select(5, IEX_GetFrameInterpolation())),
				tostring(select(6, IEX_GetFrameInterpolation())) }, ',') or '-'))
		end
		if P.bbReset then P.bbReset(30) P.bbReset = nil end
		P.ph = nil
		return true
	end
	return false
end

local function tickWorld()
	if P.state ~= 'world' then return end
	P.frames = (P.frames or 0) + 1
	if not P.phases then
		if P.frames < 90 then return end
		P.phases = {}
		-- reference run with the engine's own pacing (one frame per tick, as without an extender): mods' frame rate
		-- requests (TA Dynamic FPS through Keep Game Speed) are ignored
		if iniNum('SpeedTest', 'NoFloor', 0) == 1 and IEX_SetFrameRateFloor then
			IEX_SetFrameRateFloor(0)
			IEX_SetFrameRateFloor = function() return 0 end
		end
		for p in iniStr('Phases', '30,60,30'):gmatch('[^,]+') do P.phases[#P.phases + 1] = p end
		P.idx = 0
		local l = leader()
		P.homeX, P.homeY, P.farX, P.farY = l.m_pos.x, l.m_pos.y, l.m_pos.x, l.m_pos.y
		local best = -1
		for slot = 1, 5 do
			local m = EEex_Sprite_GetInPortrait(slot)
			if m then
				local dd = (m.m_pos.x - l.m_pos.x) ^ 2 + (m.m_pos.y - l.m_pos.y) ^ 2
				if dd > best then best, P.farX, P.farY = dd, m.m_pos.x, m.m_pos.y end
			end
		end
		pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true, true, 0) end end)
		local info = {}
		for _, k in ipairs({ 'Uncap FPS', 'Uncap FPS Limit Enabled', 'Uncap FPS Limit', 'Uncap FPS Busy Wait Threshold', 'Uncap FPS Fullscreen VRR' }) do
			info[#info + 1] = k:gsub(' ', '_') .. '=' .. tostring(iniNum('EEex', k, 'nil'))
		end
		P.emit(string.format('setup engine=%s tps=%d max_frame_rate=%s iex_frame_rate=%s %s area=%s',
			IEX_Version and ('IEX ' .. tostring(IEX_Version)) or (EEex_Version and 'EEex' or 'EEex?'), tps(),
			tostring(iniNum('Program Options', 'Maximum Frame Rate', 'nil')), tostring(IEX_GetFrameRate and IEX_GetFrameRate() or '-'),
			table.concat(info, ' '), tostring(select(2, pcall(function() return area().m_resref:get() end)))))
		return
	end
	if P.ph then stepPhase() return end
	P.idx = P.idx + 1
	local spec = P.phases[P.idx]
	if spec then startPhase(spec) return end
	setCombat(false)
	EEex_CChitin.TIMER_UPDATES_PER_SECOND = iniNum('SpeedTest', 'EndRate', 30)
	P.state = 'done'
	if iniNum('SpeedTest', 'Shots', 0) == 1 then
		-- the runner clicks and screenshots the options screen, then closes the game
		pcall(EEex_Options_Open)
		-- IEX: show the frame rate tab directly (background clicks are not always taken)
		pcall(function()
			for i, tab in ipairs(iexOptTabs or {}) do
				if tab.text == 'Uncap FPS' then iexOptTab = i IEXOpt_TabClick() end
			end
		end)
		P.status('shots ' .. #P.lines)
		return
	end
	P.status('DONE ' .. #P.lines)
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
	pcall(function() if not Infinity_IsMenuOnStack('SPD_TICK') then Infinity_PushMenu('SPD_TICK') end end)
end

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
		if P.state == 'boot' and (P.startFrames or 0) >= 30 and P.books and not P.campaign then
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

function SPD_Tick()
	-- start / load screens whose menus do not call the wrapped title functions (BG2EE with Infinity UI++)
	if P.state == 'boot' and P.tickMenuEarly then pcall(tickStart) end
	if P.state == 'loadscreen' and P.tickMenuEarly then pcall(tickLoad) end
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
	pcall(EEex_Menu_LoadFile, 'SPD')
	wrapGlobal('getTitle', tickStart)
	if type(startThreeBookHighlight) == 'function' then P.books = true end
	wrapGlobal('startThreeBookHighlight', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	if not P.books and type(getTitle) ~= 'function' and IEX_AddListener and not P.earlyListener then
		-- IEX only: the tick menu is pushed from a later engine tick (pushing it here crashes the engine)
		P.earlyListener = true
		local ticks = 0
		IEX_AddListener('EngineTickDone', function()
			if P.state ~= 'boot' and P.state ~= 'loadscreen' then return end
			ticks = ticks + 1
			if ticks < 60 then return end
			P.tickMenuEarly = true
			-- pushed again when a screen change removed it
			pcall(function() if not Infinity_IsMenuOnStack('SPD_TICK') then Infinity_PushMenu('SPD_TICK') end end)
		end)
	end
	P.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(function()
	if P.state == 'loading' then enterWorld('initialized') end
end) end)

pcall(P.status, 'probe loaded')
