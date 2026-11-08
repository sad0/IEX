--[[
Engine-fix probe 2 (tools/fixtest2), IEX 0.4.1 fixes. Our own code. Loads a save and runs the repro of each new engine
fix of docs/ENGINE_FIXES.md; the runner starts the game with the fixes off (IEX_ENGINE_FIXES=0) or on and compares.
FX2_MODE (M_FX2CFG.lua, written by make_res.py):
  main        op182 / op183 effect leak (the runner samples the process memory at 'mem <tag>'), AddExperienceParty(-1000)
              with 6 members, party level sum > 255 through AddXP2DA, a 2DA with an indented row and a line of spaces
              through TakeItemListParty
  op248       op248 with a missing EFF and parameter 2 bit 2 (the engine crashes at the next effect pass)
  startup2da  WSPECIAL.2DA (loaded at startup) with an indented row: rows the engine counted
  rest        6 members of level 43 (sum 258), a rest encounter set on the visible area (ORC01, at most 6, difficulty
              1): the rest button and the number of creatures the encounter spawned (engine: budget 258 & 255 = 2)
Output: IEX/fixtest2_out.txt, status in IEX/fixtest2_status.txt. Boot as tools/fixtest (F11 from the runner).
--]]

FX2 = FX2 or {}
local S = FX2
S.SAVE = S.SAVE or 'FIXTEST2'
S.lines = S.lines or {}
S.state = S.state or 'boot'
S.ticks = 0
local MODE = 'main'  -- FX2_MODE, read when the world starts (M_FX2CFG.lua may load after this file)

local function writeFile(name, text)
	if IEX_WriteFile then return IEX_WriteFile(name, text) end
	return false
end

function S.status(s)
	if IEX_Log then pcall(IEX_Log, '[FX2] ' .. tostring(s)) end
	pcall(writeFile, 'fixtest2_status.txt', tostring(s) .. '\n')
end

-- each line is written out at once: a run whose engine bug crashes the game keeps the lines before the crash
local function out(s) S.lines[#S.lines + 1] = s pcall(IEX_Log, '[FX2] ' .. s) S.flush() end
function S.flush() pcall(writeFile, 'fixtest2_out.txt', table.concat(S.lines, '\n') .. '\n') end

local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function stat(sp, id) local ok, v = pcall(EEex_Sprite_GetStat, sp, id) return ok and v or nil end
local function queue(s, sprite) if sprite then pcall(EEex_Action_QueueResponseStringOnAIBase, s, sprite) end end
local function apply(sp, t)
	t.sourceID = t.sourceID or sp.m_id
	t.sourceTarget = t.sourceTarget or sp.m_id
	local ok, err = pcall(EEex_GameObject_ApplyEffect, sp, t)
	if not ok then S.lines[#S.lines + 1] = 'apply error ' .. tostring(err) end
end
local function name(sp) local ok, n = pcall(IEX_SpriteName, sp) return ok and tostring(n) or '?' end
local function baseXP(sp) local ok, v = pcall(function() return sp.m_baseStats.m_xp end) return ok and v or nil end
local function members() local n = 0 for i = 0, 5 do if P(i) then n = n + 1 end end return n end

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

local function info()
	local parts = {}
	if IEX_EngineFixes then
		for k, v in pairs(IEX_EngineFixes()) do parts[#parts + 1] = k .. '=' .. tostring(v) end
		table.sort(parts)
	end
	out('mode ' .. MODE .. '; fixes ' .. table.concat(parts, ' '))
	local okC, camp = pcall(function()
		local t = IEX_ResourceText('CAMPAIGN', 0x3F4) or ''
		t = t:gsub('\r', '')
		local hdr = t:match('[^\n]*\n[^\n]*\n([^\n]*)') or ''
		local row = t:match('\n(SOA[^\n]*)') or t:match('\n(BG2[^\n]*)') or 'no SoA row'
		return 'header ' .. hdr:gsub('%s+', ' ') .. ' | ' .. row:gsub('%s+', ' ')
	end)
	out('CAMPAIGN.2DA XPLIST: ' .. tostring(okC and camp or '?'))
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			out(('party %d %s lv=%s/%s/%s xp=%s'):format(i, name(sp), tostring(stat(sp, 34)), tostring(stat(sp, 68)),
				tostring(stat(sp, 69)), tostring(baseXP(sp))))
		end
	end
end

-- The BG2EE "Chapter 1 Start" save has 2 members. The party is filled up to 6, never more (a vanilla game with 7+
-- members forces the "remove party member" screen): 6 - n plain ORC01 creatures are created next to Player1 (only
-- the member count matters here), then they are asked to JoinParty() one at a time, each request only when the
-- previous one has joined or 2 s have passed, and only while the party has fewer than 6 members.
local function partyFillers()
	local need = 6 - members()
	S.fillersMade = need
	for _ = 1, need do queue('CreateCreatureObject("ORC01",Myself,0,0,0)', P(0)) end
end
local function inParty(sp)
	for i = 0, 5 do if P(i) and P(i).m_id == sp.m_id then return true end end
	return false
end
local function partyJoinOne()
	if members() >= 6 then return end
	local now = Infinity_GetClockTicks()
	if S.pending and not inParty(S.pending) and now - S.pendingAt < 2000 then return end
	S.pending = nil
	S.asked = S.asked or {}
	local ok, list = pcall(EEex_Sprite_GetAllOfTypeStringInRange, P(0), '[ANYONE]', 800)
	for _, sp in ipairs(ok and type(list) == 'table' and list or {}) do
		if name(sp) == 'Orc' and not inParty(sp) and not S.asked[sp.m_id] then
			S.asked[sp.m_id] = true
			S.pending, S.pendingAt = sp, now
			queue('JoinParty()', sp)
			return
		end
	end
end

local function protectParty()
	for i = 0, 5 do
		local sp = P(i)
		if sp then apply(sp, { effectID = 208, effectAmount = 1, durationType = 0, duration = 900 }) end
	end
end

-- op182 / op183 leak: 400 op182 (item IXNOITEM, owned by nobody) and 400 op183 (item type 0x60, none) per member,
-- through op177 + EFF. Every effect pass evaluates each of them; the engine read its EFF first and leaked the effect
-- object when it skipped it. The runner samples the process memory at 'mem leak0' and 'mem leak1' (60 s later).
local LEAK_COUNT = 400
local function leakSetup()
	local n = 0
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			for _ = 1, LEAK_COUNT do
				apply(sp, { effectID = 177, effectAmount = 0, dwFlags = 2, durationType = 1, res = 'IX182N' })
				apply(sp, { effectID = 177, effectAmount = 0, dwFlags = 2, durationType = 1, res = 'IX183N' })
				n = n + 2
			end
		end
	end
	out(('leak: %d op177 -> op182 / op183 effects applied on %d members'):format(n, members()))
end
-- Between the two memory samples every member gets a short LUCK +0 effect once a second: each added effect makes
-- the engine run a full effect pass on that creature (so every op182 / op183 above is evaluated each time).
local function leakPulse()
	if not S.pulsing then return end
	local now = Infinity_GetClockTicks()
	if S.lastPulse and now - S.lastPulse < 1000 then return end
	S.lastPulse = now
	S.pulses = (S.pulses or 0) + 1
	for i = 0, 5 do
		if P(i) then apply(P(i), { effectID = 22, effectAmount = 0, durationType = 0, duration = 1 }) end
	end
end

-- AddExperienceParty(-1000) with 6 living members (engine: unsigned share, each member gains ~715 million).
local function xpParty()
	S.xp0 = {}
	for i = 0, 5 do S.xp0[i] = P(i) and baseXP(P(i)) end
	queue('AddExperienceParty(-1000)', P(0))
end
local function xpRead(tag)
	local parts = {}
	for i = 0, 5 do
		if P(i) then
			local a, b = S.xp0[i], baseXP(P(i))
			parts[#parts + 1] = ('%s %s -> %s (%s)'):format(name(P(i)), tostring(a), tostring(b),
				(a and b) and tostring(b - a) or '?')
		end
	end
	out(tag .. ': ' .. table.concat(parts, '; '))
end

-- Party level sum > 255: LEVEL / LEVEL2 / LEVEL3 = 90 (party of 3+: sum of averages 270+). AddXP2DA("IXQ1")
-- reads XPLIST row = GetAveragePartyLevel (engine: (sum & 255) / n; fixed: 90 -> P_54000).
local BASE = 0x560  -- CGameSprite m_baseStats (both builds); +0x22c..0x22e LEVEL, LEVEL2, LEVEL3
local function levelsUp()
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			local a = EEex_UDToPtr(sp)
			pcall(function()
				EEex_WriteU8(a + BASE + 0x22c, 90)
				EEex_WriteU8(a + BASE + 0x22d, 90)
				EEex_WriteU8(a + BASE + 0x22e, 90)
			end)
		end
	end
	-- a stat change makes the engine rebuild the derived stats (levels included) at once
	for i = 0, 5 do if P(i) then apply(P(i), { effectID = 22, effectAmount = 1, durationType = 0, duration = 60 }) end end
end
local function xp2da()
	local parts = {}
	for i = 0, 5 do if P(i) then parts[#parts + 1] = name(P(i)) .. ' ' .. tostring(stat(P(i), 34)) end end
	out('levels before AddXP2DA: ' .. table.concat(parts, ', '))
	S.xp0 = {}
	for i = 0, 5 do S.xp0[i] = P(i) and baseXP(P(i)) end
	queue('AddXP2DA("IXQ1")', P(0))
end

-- 2DA rows: TakeItemListParty("IXFX2DA"): rows A, B (indented, MISC01), C, spaces, D (AMUL01). The engine counted
-- 3 rows (A, C, D) but filled A, B, C at 0-2 and D at 4 (past the arrays): it takes MISC01 only, then frees a
-- corrupted table. Fixed: rows A, B, C, D; both items taken.
local function countItem(sp, res)
	local n = 0
	pcall(function()
		for slot = 0, 38 do
			local item = sp.m_equipment.m_items:get(slot)
			if item and item.pRes.resref:get():upper() == res then n = n + 1 end
		end
	end)
	return n
end
local function itemsLine(tag)
	out(('%s: %s MISC01 %d AMUL01 %d; %s MISC01 %d AMUL01 %d'):format(tag, name(P(1)), countItem(P(1), 'MISC01'),
		countItem(P(1), 'AMUL01'), name(P(0)), countItem(P(0), 'MISC01'), countItem(P(0), 'AMUL01')))
end
local function listGive()
	queue('CreateItem("MISC01",0,0,0)', P(1))
	queue('CreateItem("AMUL01",0,0,0)', P(1))
end
local function listTake()
	itemsLine('items before TakeItemListParty')
	queue('TakeItemListParty("IXFX2DA")', P(0))
end

-- op248 with a missing EFF and param2 bit 2.
local function op248()
	out('op248: missing EFF IXNOEFF, param2 4 on ' .. name(P(0)))
	apply(P(0), { effectID = 248, effectAmount = 0, dwFlags = 4, durationType = 0, duration = 120, res = 'IXNOEFF' })
end

-- WSPECIAL (CRuleTables +0x1500, a C2DArray: +0x18 row names, +0x30 columns, +0x32 rows), loaded at startup.
local function wspecial()
	local ok, err = pcall(function()
		local game = EEex_UDToPtr(EngineGlobals.g_pBaldurChitin.m_pObjectGame)
		local t = game + 0x1500
		local rows = EEex_ReadU16(t + 0x32)
		local names = {}
		local base = EEex_ReadPointer(t + 0x18)
		for r = 0, rows - 1 do names[#names + 1] = EEex_ReadString(EEex_ReadPointer(base + r * 8)) end
		out(('WSPECIAL (indented row 3): %d rows, columns %d, row names %s'):format(rows, EEex_ReadU16(t + 0x30),
			table.concat(names, ',')))
	end)
	if not ok then out('wspecial error ' .. tostring(err)) end
end

-- Rest encounter strength: CGameArea::CheckRestEncounter sums the party's average levels (byte in the engine) and
-- spawns rest creatures while their levels add up to at most difficulty * sum. The visible area's rest header
-- (CGameArea +0xe0, the ARE rest block) is set in memory: active, 100% day and night, one type ORC01, at most 6,
-- difficulty 1, flags 0x400 (no extra creature option); then the rest button. Engine: 6 * 43 = 258 wraps to 2
-- (1 or 2 orcs); fixed: 6.
local function setLevels(lv)
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			local a = EEex_UDToPtr(sp)
			pcall(function()
				EEex_WriteU8(a + BASE + 0x22c, lv)
				EEex_WriteU8(a + BASE + 0x22d, lv)
				EEex_WriteU8(a + BASE + 0x22e, lv)
			end)
		end
	end
	for i = 0, 5 do if P(i) then apply(P(i), { effectID = 22, effectAmount = 1, durationType = 0, duration = 60 }) end end
end
local function strangers()
	local n, lv = 0, {}
	local ok, list = pcall(EEex_Sprite_GetAllOfTypeStringInRange, P(0), '[ANYONE]', 3000)
	for _, sp in ipairs(ok and type(list) == 'table' and list or {}) do
		if not inParty(sp) and name(sp) == 'Orc' then
			n = n + 1
			lv[#lv + 1] = tostring(stat(sp, 34))
		end
	end
	return n, table.concat(lv, ',')
end
-- the visible area's rest header and the creatures around Player1 that are not in the party
local function restState(tag)
	local ok, t = pcall(function()
		local area = EEex_UDToPtr(EEex_Area_GetVisible())
		local others = {}
		local okL, list = pcall(EEex_Sprite_GetAllOfTypeStringInRange, P(0), '[ANYONE]', 3000)
		for _, sp in ipairs(okL and type(list) == 'table' and list or {}) do
			if not inParty(sp) then others[#others + 1] = name(sp) end
		end
		return ('rest %s: area flags 0x%x active %d day %d night %d; others (%d) %s'):format(tag,
			EEex_ReadU16(area + 0x18c), EEex_ReadU16(area + 0x186), EEex_ReadU16(area + 0x188),
			EEex_ReadU16(area + 0x18a), #others, table.concat(others, ','))
	end)
	out(ok and t or ('rest state error ' .. tostring(t)))
end
local function restSetup()
	local parts, sum = {}, 0
	for i = 0, 5 do
		if P(i) then
			local l = stat(P(i), 34) or 0
			sum = sum + l
			parts[#parts + 1] = name(P(i)) .. ' ' .. tostring(l)
		end
	end
	S.orcs0 = strangers()
	out(('rest: %d members, levels %s (sum %d, byte %d); orcs around before %d'):format(members(),
		table.concat(parts, ', '), sum, sum % 256, S.orcs0))
	local ok, err = pcall(function()
		local area = EEex_UDToPtr(EEex_Area_GetVisible())
		EEex_WriteU16(area + 0x178, 1)       -- creature types
		EEex_WriteU16(area + 0x17a, 1)       -- difficulty
		EEex_WriteU16(area + 0x184, 6)       -- maximum creatures
		EEex_WriteU16(area + 0x186, 1)       -- active
		EEex_WriteU16(area + 0x188, 100)     -- day probability
		EEex_WriteU16(area + 0x18a, 100)     -- night probability
		EEex_WriteU16(area + 0x18c, 0x400)   -- flags: no extra creature
		local r = 'ORC01'
		for k = 0, 7 do EEex_WriteU8(area + 0x128 + k, k < #r and r:byte(k + 1) or 0) end
	end)
	if not ok then out('rest setup error ' .. tostring(err)) end
	restState('before')
end
-- the world screen's rest button (the RestParty() action is a scripted rest: the engine skips rest encounters then)
-- Clicked again every 3 s until the encounter happened (area flag 0x4): the engine refuses to rest while a creature
-- it counts as a monster (the dungeon's wandering golem) is in sight.
local function restClick()
	local okF, flags = pcall(function() return EEex_ReadU16(EEex_UDToPtr(EEex_Area_GetVisible()) + 0x18c) end)
	if okF and flags % 8 >= 4 then return end
	S.restWatch = true
	S.restClicks = (S.restClicks or 0) + 1
	local ok, err = pcall(function() worldScreen:OnRestButtonClick() end)
	if not ok then out('rest: rest button error ' .. tostring(err)) end
end
local function restRead()
	if S.restRead then return end
	S.restRead = true
	restState('after ' .. tostring(S.restClicks) .. ' rest button clicks')
	local n, lv = strangers()
	out(('rest: encounter spawned %d creatures (ORC01 levels %s; expected engine 1-2, fixed 6)'):format(n - (S.orcs0 or 0), lv))
end

S.restRead_ = restRead  -- the world tick reads 1 s after the encounter (the spawned orcs fight the party)
local function finish() info() S.flush() S.status('DONE ' .. #S.lines) end
local function mem(tag) S.status('mem ' .. tag) end

local STEPS
local function makeSteps()
MODE = FX2_MODE or 'main'
if MODE == 'op248' then
	STEPS = {
		{ 90, function() info() unpause() op248() S.flush() end },
		{ 400, function() out('op248: still running 10 s later') finish() end },
	}
elseif MODE == 'startup2da' then
	STEPS = { { 60, function() wspecial() finish() end } }
elseif MODE == 'rest' then
	STEPS = {
		{ 1, partyFillers }, { 30, partyJoinOne }, { 50, partyJoinOne }, { 70, partyJoinOne }, { 90, partyJoinOne }, { 110, partyJoinOne }, { 130, partyJoinOne }, { 150, partyJoinOne }, { 170, partyJoinOne }, { 190, partyJoinOne }, { 210, partyJoinOne }, { 230, partyJoinOne },
		{ 260, function() info() protectParty() unpause() setLevels(43) end },
		{ 330, restSetup },
		{ 340, restClick }, { 430, restClick }, { 520, restClick }, { 610, restClick }, { 700, restClick }, { 790, restClick }, { 880, restClick }, { 970, restClick }, { 1060, restClick }, { 1150, restClick },
		{ 1300, restRead },
		{ 1320, finish },
	}
else
	STEPS = {
		{ 1, partyFillers }, { 30, partyJoinOne }, { 50, partyJoinOne }, { 70, partyJoinOne }, { 90, partyJoinOne }, { 110, partyJoinOne }, { 130, partyJoinOne }, { 150, partyJoinOne }, { 170, partyJoinOne }, { 190, partyJoinOne }, { 210, partyJoinOne }, { 230, partyJoinOne }, { 250, partyJoinOne }, { 270, partyJoinOne }, { 290, partyJoinOne }, { 310, partyJoinOne },
		{ 340, function() info() protectParty() unpause() leakSetup() end },
		{ 420, function() mem('leak0') S.pulsing = true end },
		{ 2220, function() S.pulsing = false mem('leak1') out('leak: ' .. tostring(S.pulses) .. ' forced effect passes per member') end },
		{ 2300, xpParty },
		{ 2420, function() xpRead('AddExperienceParty(-1000)') end },
		{ 2450, levelsUp },
		{ 2600, xp2da },
		{ 2720, function() xpRead('AddXP2DA("IXQ1")') end },
		{ 2750, listGive },
		{ 2850, listTake },
		{ 2970, function() itemsLine('items after TakeItemListParty') end },
		{ 3000, finish },
	}
end
end

local function tickWorld()
	S.ticks = S.ticks + 1
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local elapsed = (t - S.t0) * 30 / 1000
	S.done = S.done or {}
	if not STEPS then makeSteps() end
	if S.ticks % 30 == 0 then dismissDialog() unpause() end
	if S.ticks % 15 == 0 then pcall(leakPulse) end
	if S.restWatch and not S.restRead then
		local okF, flags = pcall(function() return EEex_ReadU16(EEex_UDToPtr(EEex_Area_GetVisible()) + 0x18c) end)
		if okF and flags % 8 >= 4 then
			S.restSeen = S.restSeen or S.ticks
			if S.ticks - S.restSeen >= 30 then pcall(S.restRead_) end
		end
	end
	for i, st in ipairs(STEPS) do
		if not S.done[i] and elapsed >= st[1] then
			S.done[i] = true
			local ok, err = pcall(st[2])
			if not ok then out('step ' .. st[1] .. ' error: ' .. tostring(err)) end
		end
	end
end

function FX2_Tick()
	if S.state == 'world' then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- Boot (as tools/fixtest) ----------------------------------------------------------------------------------

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
	if not Infinity_IsMenuOnStack('FX2_TICK') then Infinity_PushMenu('FX2_TICK') end
end

pcall(EEex_Key_AddPressedListener, function(key)
	pcall(function()
		if key ~= EEex_Key_GetFromName('F11') then return end
		if S.state == 'boot' then keyStart()
		elseif S.state == 'loadscreen' then keyLoad()
		elseif S.state == 'loading' and EEex_Area_GetVisible() ~= nil then enterWorld('key') end
	end)
end)

local function wrapGlobal(gname, tick)
	local orig = _G[gname]
	if type(orig) ~= 'function' or S['g_' .. gname] then return end
	S['g_' .. gname] = true
	_G[gname] = function(...) pcall(tick) return orig(...) end
end

pcall(EEex_Menu_AddMainFileLoadedListener, function() pcall(function()
	pcall(EEex_Menu_LoadFile, 'FX2')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded')
