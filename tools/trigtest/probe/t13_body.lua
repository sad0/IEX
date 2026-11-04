--[[
Event-trigger object probe (tools/trigtest, ENGINE_FIXES.md #13). Our own code; the same file runs under EEex and IEX
and only uses the public EEex Lua API, so the engine behaviour is observed as a black box.
The test creature IXT13D (script IXT13: Heard / AttackedBy with PartySlot1, then [ANYONE] as control) is spawned
next to the party. Party members shout / attack it one at a time, before and after portraits 1 and 2 are swapped.
Correct: the PartySlot1 counter follows whoever is in portrait 1. Bug ("locks on"): it keeps the first creature.
Output: stdout via print (InfinityLoader log) or IEX/trig_out.txt (IEX_WriteFile); status in trig_status.txt.
Boot as tools/stick: F11 (sent by the runner in the background) opens the load screen, then loads the save.
--]]

T13 = T13 or {}
local S = T13
S.SAVE = S.SAVE or 'TRIGTEST'
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
	if IEX_Log then pcall(IEX_Log, '[T13] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, 'trig_status.txt', tostring(s) .. '\n')
	if not (ok and wrote) then print('T13|STATUS ' .. tostring(s)) end
end

local function out(s) S.lines[#S.lines + 1] = s end
function S.flush()
	local ok, wrote = pcall(writeFile, 'trig_out.txt', table.concat(S.lines, '\n') .. '\n')
	if not (ok and wrote) then
		for i = (S.printed or 0) + 1, #S.lines do print('T13|OUT ' .. S.lines[i]) end
		S.printed = #S.lines
	end
end

local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function queue(s, sprite) if sprite then pcall(EEex_Action_QueueResponseStringOnAIBase, s, sprite) end end
local function name(sp)
	if not sp then return 'none' end
	local ok, n = pcall(EEex_Sprite_GetName, sp)
	if ok and n then return tostring(n) end
	local ok2, id = pcall(function() return sp.m_id end)
	return ok2 and ('id' .. tostring(id)) or '?'
end
local function g(n) local ok, v = pcall(EEex_GameState_GetGlobalInt, n) return ok and v or -1 end

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

-- The two creatures under test, fixed at the start: A = portrait 1, B = portrait 2.
local A, B
local function counters(label)
	out(('%-26s slot1=%s slot2=%s  Heard(PartySlot1)=%d Heard(other)=%d  AttackedBy(PartySlot1)=%d AttackedBy(other)=%d')
		:format(label, name(P(0)), name(P(1)), g('IXT13H'), g('IXT13X'), g('IXT13A'), g('IXT13Y')))
	S.flush()
end
local function shout(sp) unpause() queue('Shout(99)', sp) end
local function attack(sp) unpause() queue('Attack("IXT13D")', sp) end
local function stop()
	for i = 0, 5 do queue('ClearActions(Myself)', P(i)) end
end
local function swap()
	local ok, err = pcall(function() worldScreen:SwapPortraits(0, 1) end)
	if not ok then out('swap error ' .. tostring(err)) end
end

local STEPS = {
	-- saves with one member (Linux "Chapter 1 Start"): Jaheira joins, so portraits 1 and 2 are two creatures
	{ 10, function()
		unpause()
		if not P(1) then
			out('party has one member: Jaheira joins')
			queue('CreateCreatureObject("JAHEIRA",Myself,0,0,0)', P(0))
			queue('ActionOverride("Jaheira",JoinParty())', P(0))
		end
	end },
	{ 30, function() dismissDialog() end },
	{ 60, function()
		A, B = P(0), P(1)
		out('engine ' .. (IEX_Log and 'IEX' or 'EEex'))
		unpause()
		for _, n in ipairs({ 'IXT13H', 'IXT13X', 'IXT13A', 'IXT13Y' }) do pcall(EEex_GameState_SetGlobalInt, n, 0) end
		queue('CreateCreatureObject("IXT13D",Myself,0,0,0)', A)
	end },
	{ 120, function() counters('start') shout(A) end },
	{ 180, function() counters('A shouted (A slot1)') shout(B) end },
	{ 240, function() counters('B shouted (B slot2)') swap() end },
	{ 270, function() counters('portraits swapped') shout(B) end },
	{ 330, function() counters('B shouted (B slot1)') shout(A) end },
	{ 390, function() counters('A shouted (A slot2)') attack(B) end },
	{ 450, stop },
	{ 480, function() counters('B attacked (B slot1)') attack(A) end },
	{ 540, stop },
	{ 570, function() counters('A attacked (A slot2)') swap() end },
	{ 600, function() counters('portraits swapped back') shout(A) end },
	{ 660, function() counters('A shouted (A slot1)') shout(B) end },
	{ 720, function() counters('B shouted (B slot2)') S.flush() S.status('DONE ' .. #S.lines) end },
}

local function tickWorld()
	S.ticks = S.ticks + 1
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local elapsed = (t - S.t0) * 30 / 1000
	S.done = S.done or {}
	if S.ticks % 30 == 0 then dismissDialog() end
	for i, st in ipairs(STEPS) do
		if not S.done[i] and elapsed >= st[1] then
			S.done[i] = true
			local ok, err = pcall(st[2])
			if not ok then out('step ' .. st[1] .. ' error: ' .. tostring(err)) end
		end
	end
end

function T13_Tick()
	if S.state == 'world' then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- Boot (as tools/stick) ----------------------------------------------------------------------------------------

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
	if not Infinity_IsMenuOnStack('T13_TICK') then Infinity_PushMenu('T13_TICK') end
end

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
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
	pcall(EEex_Menu_LoadFile, 'T13')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded')
