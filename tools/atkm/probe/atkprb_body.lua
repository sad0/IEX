--[[
SadoEE attack-move probe (tools/atkm). Our own code. Loads a save, then for 2..6 party members and each of the five
formation slots: a plain move click (CGameArea::OnActionButtonClickGround, the engine's own group move), then
SadoEE's attack-move order (SQAttackMove_At) to another point. Records each member's destination (m_curAction /
queued MoveToPoint m_dest, relative to the clicked point), SadoEE's order (waypoints) and the final positions.
The same file runs under real EEex and under IEX.
Output: atkm_out.txt (io) or IEX/atkm_out.txt (IEX_WriteFile), else print lines 'ATKPRB|OUT '; status atkm_status.txt.
Boot as tools/stick: F11 (sent by the runner in the background) opens the load screen, then loads the save.
--]]

ATK = ATK or {}
local S = ATK
S.SAVE = S.SAVE or 'ATKMTEST'
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
	if IEX_Log then pcall(IEX_Log, '[ATKPRB] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, 'atkm_status.txt', tostring(s) .. '\n')
	if not (ok and wrote) then print('ATKPRB|STATUS ' .. tostring(s)) end
end

local function out(s) S.lines[#S.lines + 1] = s end
function S.flush()
	local ok, wrote = pcall(writeFile, 'atkm_out.txt', table.concat(S.lines, '\n') .. '\n')
	if not (ok and wrote) then
		for i = (S.printed or 0) + 1, #S.lines do print('ATKPRB|OUT ' .. S.lines[i]) end
		S.printed = #S.lines
	end
end

local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function game() return EEex_EngineGlobal_CBaldurChitin.m_pObjectGame end

local function party()
	local t = {}
	for i = 0, 5 do local s = P(i) if s then t[#t + 1] = s end end
	return t
end

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

-- CInfGame +0x798c current formation (i16), +0x798e the five formation buttons (raw: same reading on both sides)
local function gptr() return EEex_UDToPtr(game()) end
local function formations()
	local g = gptr()
	local vals = {}
	for i = 0, 4 do vals[#vals + 1] = tostring(EEex_Read16(g + 0x798e + 2 * i)) end
	return 'cur=' .. tostring(EEex_Read16(g + 0x798c)) .. ' slots=' .. table.concat(vals, ',')
end
local function setFormation(f) EEex_Write16(gptr() + 0x798c, f) end

local function select(n)
	local g = game()
	g:UnselectAll()
	for i = 1, n do
		local s = P(i - 1)
		if s then g:SelectCharacter(s.m_id, false) end
	end
end

-- destination of a member: its current MoveToPoint (23), else the first queued one
local function destOf(s)
	local a = s.m_curAction
	if a.m_actionID == 23 then return a.m_dest.x, a.m_dest.y, 'cur' end
	local dx, dy, where
	EEex_Utility_IterateCPtrList(s.m_queuedActions, function(q)
		if q.m_actionID == 23 then dx, dy, where = q.m_dest.x, q.m_dest.y, 'queued' return true end
	end)
	return dx, dy, where or ('none(cur ' .. tostring(a.m_actionID) .. ' q ' .. tostring(s.m_queuedActions.m_nCount) .. ')')
end

local function dests(tag, n, x, y)
	local parts = {}
	for i = 1, n do
		local s = P(i - 1)
		if s then
			local dx, dy, where = destOf(s)
			parts[#parts + 1] = (dx and string.format('%+d,%+d', dx - x, dy - y) or '-') .. '/' .. where
		end
	end
	out(tag .. ' dest rel ' .. table.concat(parts, ' '))
end

local function finals(tag, n, x, y)
	local parts = {}
	for i = 1, n do
		local s = P(i - 1)
		if s then parts[#parts + 1] = string.format('%+d,%+d', s.m_pos.x - x, s.m_pos.y - y) end
	end
	out(tag .. ' final rel ' .. table.concat(parts, ' '))
end

local function vanillaClick(x, y)
	local area = EEex_Area_GetVisible()
	EEex_RunWithStackManager(
		{ { name = 'pt', struct = 'CPoint', constructor = { variant = 'fromXY', args = { x, y } } } },
		function(m) area:OnActionButtonClickGround(m:getUD('pt')) end)
end

local function order(tag, n, x, y)
	local T = SQAtkM or {}
	local parts = {}
	if T.order then
		for i = 1, n do
			local s = P(i - 1)
			local o = s and T.order.members[s.m_id]
			if o then parts[#parts + 1] = string.format('%+d,%+d', o.wp[1][1] - x, o.wp[1][2] - y) else parts[#parts + 1] = '-' end
		end
	end
	out(tag .. ' order wp rel ' .. (T.order and table.concat(parts, ' ') or 'NO ORDER') .. ' | status ' .. tostring(T.status)
		.. ' lastError ' .. tostring(T.lastError))
	T.lastError = nil
end

-- cursor maths of SadoEE's cursorWorld, with its inputs
local function cursorInfo(tag)
	local ok, err = pcall(function()
		local g = game()
		local inf = g.m_gameAreas:get(g.m_visibleArea).m_cInfinity
		local vp = inf.rViewPort
		local sw, sh = Infinity_GetScreenSize()
		local mx, my = EEex_Menu_GetMousePos()
		local ix, iy = Infinity_GetMousePosition()
		local zr = ''
		pcall(function() local z = inf.rViewPortZoomed zr = string.format(' zoomed %d,%d,%d,%d', z.left, z.top, z.right, z.bottom) end)
		out(string.format('%s cursor: mouse %s,%s infmouse %s,%s screen %s,%s vp %d,%d,%d,%d%s new %d,%d -> world %d,%d',
			tag, tostring(mx), tostring(my), tostring(ix), tostring(iy), tostring(sw), tostring(sh), vp.left, vp.top, vp.right,
			vp.bottom, zr, inf.nNewX, inf.nNewY,
			math.floor(inf.nNewX + mx * vp.right / sw), math.floor(inf.nNewY + my * vp.bottom / sh)))
	end)
	if not ok then out(tag .. ' cursor error ' .. tostring(err)) end
	ok, err = pcall(function()
		local g = game()
		local area = g.m_gameAreas:get(g.m_visibleArea)
		local a = EEex_UDToPtr(area)
		local i = EEex_UDToPtr(area.m_cInfinity)
		local raw = {}
		for o = 0x60, 0x84, 4 do raw[#raw + 1] = string.format('%x=%d', o, EEex_Read32(i + o)) end
		out(string.format('%s raw CInfinity (area+0x%x): %s', tag, i - a, table.concat(raw, ' ')))
	end)
	if not ok then out(tag .. ' raw error ' .. tostring(err)) end
	-- where the mouse pairs live: CBaldurChitin (0x1918 bytes) and CInfGame (0x97f8), consecutive i32 x, y
	ok, err = pcall(function()
		local mx, my = EEex_Menu_GetMousePos()
		local ix, iy = Infinity_GetMousePosition()
		local function scan(name, base, size)
			local hm, hi = {}, {}
			for o = 0, size - 8, 4 do
				local x, y = EEex_Read32(base + o), EEex_Read32(base + o + 4)
				if x == mx and y == my then hm[#hm + 1] = string.format('%x', o) end
				if x == ix and y == iy then hi[#hi + 1] = string.format('%x', o) end
			end
			out(string.format('%s scan %s: menuMouse(%d,%d) at [%s] infMouse(%d,%d) at [%s]', tag, name, mx, my,
				table.concat(hm, ','), ix, iy, table.concat(hi, ',')))
		end
		scan('chitin', EEex_UDToPtr(EEex_EngineGlobal_CBaldurChitin), 0x1918)
		scan('game', EEex_UDToPtr(game()), 0x97f8)
	end)
	if not ok then out(tag .. ' scan error ' .. tostring(err)) end
end

-- Cases -------------------------------------------------------------------------------------------------------

S.home = nil
local function caseSteps(list, t0, n, slot, label)
	local A, B
	local function pts()
		local hx, hy = S.home[1], S.home[2]
		return hx + 160, hy + 80, hx, hy
	end
	local tag = string.format('%s n=%d formation=%d', label, n, slot)
	list[#list + 1] = { t0, function()
		unpause()
		local ax, ay = pts()
		A = { ax, ay }
		setFormation(slot)
		select(n)
		out(tag .. ' ' .. formations() .. ' selected ' .. #EEex_Sprite_GetAllSelected())
		finals(tag .. ' start', n, ax, ay)
		vanillaClick(ax, ay)
		dests(tag .. ' vanilla', n, ax, ay)
	end }
	list[#list + 1] = { t0 + 160, function() finals(tag .. ' vanilla', n, A[1], A[2]) end }
	list[#list + 1] = { t0 + 165, function()
		unpause()
		local _, _, bx, by = pts()
		B = { bx, by }
		select(n)
		SQAttackMove_At(bx, by, false)
		dests(tag .. ' atkm', n, bx, by)
		order(tag .. ' atkm', n, bx, by)
	end }
	list[#list + 1] = { t0 + 175, function() dests(tag .. ' atkm+10', n, B[1], B[2]) end }
	list[#list + 1] = { t0 + 320, function()
		finals(tag .. ' atkm', n, B[1], B[2])
		local T = SQAtkM or {}
		out(tag .. ' atkm order after: ' .. (T.order and 'running' or 'over') .. ' lastError ' .. tostring(T.lastError))
		T.order = nil
	end }
	return t0 + 330
end

local function buildSteps()
	local list = {}
	list[#list + 1] = { 30, function()
		local p = party()
		S.home = { p[1].m_pos.x, p[1].m_pos.y }
		local area = EEex_Area_GetVisible()
		out('party ' .. #p .. ' area ' .. tostring(area and area.m_resref:get()) .. ' home ' .. S.home[1] .. ',' .. S.home[2]
			.. ' ' .. formations() .. ' SQAtkM.status ' .. tostring(SQAtkM and SQAtkM.status)
			.. ' redux ' .. tostring(IEX_PathfindingRedux and IEX_PathfindingRedux().enabled))
		cursorInfo('t30')
		for _, s in ipairs(p) do out(string.format('  member %d pos %d,%d', s.m_id % 100000, s.m_pos.x, s.m_pos.y)) end
	end }
	for k = 1, 4 do list[#list + 1] = { 30 + 25 * k, function() cursorInfo('t' .. (30 + 25 * k)) end } end
	local t = 160
	local np = 6
	for _, n in ipairs({ 2, 3, 4, 6 }) do
		for _, f in ipairs({ 0, 1, 5, 6, 8 }) do t = caseSteps(list, t, n, f, 'redux-on') end
	end
	if IEX_PathfindingRedux then
		list[#list + 1] = { t, function() pcall(IEX_PathfindingRedux, { enabled = false })
			out('redux now ' .. tostring(IEX_PathfindingRedux().enabled)) end }
		t = t + 5
		for _, f in ipairs({ 1, 6, 8 }) do t = caseSteps(list, t, 6, f, 'redux-off') end
	end
	list[#list + 1] = { t + 10, function() S.flush() S.status('DONE ' .. #S.lines) end }
	return list
end

local function tickWorld()
	S.ticks = S.ticks + 1
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local elapsed = (t - S.t0) * 30 / 1000
	S.steps = S.steps or buildSteps()
	S.done = S.done or {}
	if S.ticks % 30 == 0 then dismissDialog() end
	for i, st in ipairs(S.steps) do
		if not S.done[i] and elapsed >= st[1] then
			S.done[i] = true
			local ok, err = pcall(st[2])
			if not ok then out('step ' .. st[1] .. ' error: ' .. tostring(err)) end
			if i % 10 == 0 then S.flush() end
		end
	end
end

function ATK_Tick()
	if S.state == 'world' then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- Boot ------------------------------------------------------------------------------------------------------

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
	if not Infinity_IsMenuOnStack('ATK_TICK') then Infinity_PushMenu('ATK_TICK') end
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
	pcall(EEex_Menu_LoadFile, 'ATKPRB')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded')
