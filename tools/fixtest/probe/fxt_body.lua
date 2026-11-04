--[[
Engine-fix probe (tools/fixtest). Our own code. Loads a save and runs the repro of each engine fix of
docs/ENGINE_FIXES.md; the runner starts the game twice, IEX_ENGINE_FIXES=0 (engine bugs) and default (fixes on), and
compares. Output: IEX/fixtest_out.txt (IEX_WriteFile), status in IEX/fixtest_status.txt.
Boot as tools/stick: F11 (sent by the runner in the background) opens the load screen, then loads the save.
--]]

FXT = FXT or {}
local S = FXT
S.SAVE = S.SAVE or 'FIXTEST'
S.lines = S.lines or {}
S.state = S.state or 'boot'
S.ticks = 0

local function writeFile(name, text)
	if IEX_WriteFile then return IEX_WriteFile(name, text) end
	return false
end

function S.status(s)
	if IEX_Log then pcall(IEX_Log, '[FXT] ' .. tostring(s)) end
	pcall(writeFile, 'fixtest_status.txt', tostring(s) .. '\n')
end

local function out(s) S.lines[#S.lines + 1] = s pcall(IEX_Log, '[FXT] ' .. s) end
function S.flush() pcall(writeFile, 'fixtest_out.txt', table.concat(S.lines, '\n') .. '\n') end

local function P(i) return EEex_Sprite_GetInPortrait(i) end
-- Party slot i, or the last member when the party is smaller (Linux saves).
local function R(i)
	for k = i, 0, -1 do if P(k) then return P(k) end end
end
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
local function class(sp) local ok, v = pcall(function() return sp.m_typeAI.m_Class end) return ok and v or nil end

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

-- Tests ----------------------------------------------------------------------------------------------------

local T = {}
S.T = T

local function info()
	local parts = {}
	if IEX_EngineFixes then
		for k, v in pairs(IEX_EngineFixes()) do parts[#parts + 1] = k .. '=' .. tostring(v) end
		table.sort(parts)
	end
	out('fixes ' .. table.concat(parts, ' '))
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			out(('party %d %s class=%s lv=%s/%s/%s xp=%s luck=%s hp=%s death=%s wands=%s fire=%s'):format(i, name(sp),
				tostring(class(sp)), tostring(stat(sp, 34)), tostring(stat(sp, 68)), tostring(stat(sp, 69)),
				tostring(baseXP(sp)), tostring(stat(sp, 32)), tostring(stat(sp, 1)), tostring(stat(sp, 9)),
				tostring(stat(sp, 10)), tostring(stat(sp, 14))))
		end
	end
end

-- Games whose save has fewer than 6 party members (BG2EE "Chapter 1 Start" on Linux): BG2 NPCs join (spawned next to
-- Player1, JoinParty through ActionOverride on their script names).
local JOINERS = { { 'JAHEIRA', 'Jaheira' }, { 'MINSC', 'Minsc' }, { 'YOSHIMO', 'Yoshimo' }, { 'JAN', 'Jan' },
	{ 'KORGAN', 'Korgan' }, { 'EDWIN', 'Edwin' } }
local function partyFill()
	local n = 0
	for i = 0, 5 do if P(i) then n = n + 1 end end
	if n >= 6 then return end
	out('party has ' .. n .. ' members: NPCs join')
	local have = {}
	for i = 0, 5 do if P(i) then have[name(P(i))] = true end end
	local k = 0
	for _, j in ipairs(JOINERS) do
		if n + k >= 6 then break end
		if not have[j[2]] then
			k = k + 1
			queue('CreateCreatureObject("' .. j[1] .. '",Myself,0,0,0)', P(0))
			queue('ActionOverride("' .. j[2] .. '",JoinParty())', P(0))
		end
	end
end

-- The party must survive (opcode 208, minimum HP 1).
local function protectParty()
	for i = 0, 5 do
		local sp = P(i)
		if sp then apply(sp, { effectID = 208, effectAmount = 1, durationType = 0, duration = 900 }) end
	end
end

-- 5. op33 param2 3: SAVEVSDEATH -3 in the current pass (bug: SAVEVSWANDS -3 instead).
local function testOp33()
	local sp = P(0)
	local d0, w0 = stat(sp, 9), stat(sp, 10)
	apply(sp, { effectID = 33, effectAmount = 3, dwFlags = 3, durationType = 0, duration = 300 })
	local d1, w1 = stat(sp, 9), stat(sp, 10)
	out(('op33 same pass: death %s -> %s, wands %s -> %s'):format(tostring(d0), tostring(d1), tostring(w0), tostring(w1)))
end
local function testOp33Later()
	local sp = P(0)
	out(('op33 next passes: death %s wands %s'):format(tostring(stat(sp, 9)), tostring(stat(sp, 10))))
end

-- 1. op182: EFF applied while the item is equipped. IXNOITEM (not owned): no effect; AMUL01 in the amulet slot: effect.
local function op182Prepare()
	queue('CreateItem("AMUL01",0,0,0)', P(1))
	queue('XEquipItem("AMUL01",Myself,SLOT_AMULET,EQUIP)', P(1))
end
local function op182Missing()
	T.str182 = stat(P(1), 32)
	apply(P(1), { effectID = 177, effectAmount = 0, dwFlags = 2, durationType = 1, res = 'IXFX182M' })
end
local function op182MissingRead()
	local s = stat(P(1), 32)
	out(('op182 item not owned (IXNOITEM): LUCK %s -> %s'):format(tostring(T.str182), tostring(s)))
	T.str182 = s
	apply(P(1), { effectID = 177, effectAmount = 0, dwFlags = 2, durationType = 1, res = 'IXFX182A' })
end
local function op182AmuletRead()
	out(('op182 item in the amulet slot (AMUL01): LUCK %s -> %s'):format(tostring(T.str182), tostring(stat(P(1), 32))))
end

-- 3. SPLPROT (test row IXFXT: STAT(LUCK) >= 5): a creature with LUCK 7 - 10 = -3 is not protected by op324.
local function splprotPrepare()
	local sp = R(3)
	apply(sp, { effectID = 22, effectAmount = -10, dwFlags = 0, durationType = 0, duration = 600 })
end
local function splprotImmunity()
	T.strSplprot = stat(R(3), 32)
	out(('splprot row %s, LUCK %s'):format(tostring(FXT_SPLPROT_ROW), tostring(T.strSplprot)))
	apply(R(3), { effectID = 324, effectAmount = 0, dwFlags = FXT_SPLPROT_ROW or 151, durationType = 0, duration = 600, res = 'IXSPLP' })
end
local function splprotCast()
	queue('ApplySpellRES("IXSPLP",Myself)', R(3))
end
local function splprotRead()
	out(('splprot spell IXSPLP (LUCK +1) under op324 STAT(LUCK)>=5: LUCK %s -> %s'):format(tostring(T.strSplprot), tostring(stat(R(3), 32))))
end

-- 6. op206 with its own string: the string shows when the spell is blocked (screenshot "messages206").
local function op206()
	local sp = R(4)
	local ref = 17575
	local ok, text = pcall(Infinity_FetchString, ref)
	out(('op206 param1 %d = "%s" (expect it in the message log)'):format(ref, ok and tostring(text) or '?'))
	T.str206 = stat(sp, 32)
	apply(sp, { effectID = 206, effectAmount = ref, durationType = 0, duration = 300, res = 'IXSPLP' })
	queue('ApplySpellRES("IXSPLP",Myself)', sp)
end
local function op206Read()
	out(('op206 blocked spell: LUCK %s -> %s'):format(tostring(T.str206), tostring(stat(R(4), 32))))
end

-- 10 + 11. AddXPObject with a loss larger than the XP: XP 0 (bug: wraps), message "lost experience".
local function xpLoss()
	T.xp = baseXP(R(4))
	T.xpSlot = 0
	for i = 0, 5 do if P(i) == R(4) then T.xpSlot = i end end
	queue('AddXPObject(Player' .. (T.xpSlot + 1) .. ',-2000000000)', P(0))
end
local function xpRead()
	out(('xp AddXPObject(Player%d,-2000000000): XP %s -> %s'):format(T.xpSlot + 1, tostring(T.xp), tostring(baseXP(R(4)))))
end

-- 9. op236 param2 3 (Simulacrum) on a dual-class: Player6 (a multi-class: Montaron, Jan) made a dual-class (the
--    second class active) with levels 2 / 12. The clone's level drain is 40% of the average level (7 -> 2),
--    not of the active class's level count (LEVEL 2 -> 0).
local BASE = 0x560  -- CGameSprite m_baseStats (both builds)
local MULTI = { [7] = 0x8, [8] = 0x8, [9] = 0x8, [13] = 0x10, [14] = 0x20, [15] = 0x20 }
local function simSubject()
	for i = 5, 1, -1 do
		local sp = P(i)
		if sp and MULTI[class(sp)] then return sp end
	end
end
local function simPrepare()
	local sp = simSubject()
	if not sp then out('simulacrum: no multi-class member') return end
	local a = EEex_UDToPtr(sp)
	pcall(function()
		-- dual-class flag that makes the second class active (CAIObjectType::GetActiveInactiveClasses)
		local bit = MULTI[class(sp)]
		local f = EEex_ReadU32(a + BASE + 0x8)
		if f % (bit * 2) < bit then EEex_WriteU32(a + BASE + 0x8, f + bit) end
		EEex_WriteU8(a + BASE + 0x22c, 2)
		EEex_WriteU8(a + BASE + 0x22d, 12)
	end)
end
local function simCast()
	local sp = simSubject()
	if not sp then return end
	out(('simulacrum source %s class=%s lv=%s/%s'):format(name(sp), tostring(class(sp)), tostring(stat(sp, 34)), tostring(stat(sp, 68))))
	apply(sp, { effectID = 236, effectAmount = 0, dwFlags = 3, durationType = 0, duration = 300 })
end
local function simRead()
	local src = simSubject()
	if not src then return end
	local ok, list = pcall(EEex_Sprite_GetAllOfTypeStringInRange, src, '[ANYONE]', 600)
	local found = false
	for _, sp in ipairs(ok and type(list) == 'table' and list or {}) do
		if sp.m_id ~= src.m_id and name(sp) == name(src) then
			found = true
			out(('simulacrum clone %s lv=%s/%s (source %s/%s)'):format(name(sp), tostring(stat(sp, 34)), tostring(stat(sp, 68)),
				tostring(stat(src, 34)), tostring(stat(src, 68))))
		end
	end
	if not found then out('simulacrum: no clone found (' .. tostring(ok and type(list) == 'table' and #list or list) .. ' near)') end
end

-- 4. TRAPLIMT: with the area's set-trap count at the thief's limit (TRAPLIMT THIEF 6), opcode 252 (Set Snare) is
--    refused ("too many traps", strref 72712); the bug let one more trap through (screenshot "messages").
local function trapLimit()
	local sp = P(1)
	local ok, err = pcall(function()
		local area = EEex_UDToPtr(sp.m_pArea)
		T.trapCounts = { EEex_ReadU32(area + 0x104c), EEex_ReadU32(area + 0x1050) }
		EEex_WriteU32(area + 0x104c, 6)
		EEex_WriteU32(area + 0x1050, 0)
		local ok2, text = pcall(Infinity_FetchString, 72712)
		out(('trap limit: area count %d+%d set to 6+0; op252 on %s ("%s" expected with the fix)'):format(T.trapCounts[1],
			T.trapCounts[2], name(sp), ok2 and tostring(text) or '?'))
		apply(sp, { effectID = 252, effectAmount = 0, durationType = 1, res = 'IXSPLP' })
		EEex_WriteU32(area + 0x104c, T.trapCounts[1])
		EEex_WriteU32(area + 0x1050, T.trapCounts[2])
	end)
	if not ok then out('trap limit error ' .. tostring(err)) end
end

-- 8. HP table modifier: HPWAR 1d1+5 per level. Player1 (a fighter) gets XP for one level and levels up through the
--    character screen (level-up panel, Done); the max HP gain is read after.
local function hpXP()
	T.hp0, T.lv0 = stat(P(0), 1), stat(P(0), 34)
	queue('AddXPObject(Player1,40000)', P(0))
end
local function hpLevelUp()
	local ok, err = pcall(function()
		e:SelectEngine(characterScreen)
		characterScreen:OnLevelUpButtonClick()
	end)
	out('hp levelUp ' .. (ok and 'ok' or tostring(err)) .. ' levelingUp=' .. tostring(chargen and chargen.levelingUp))
end
local function hpDone()
	for _ = 1, 4 do
		pcall(function()
			if e:GetActiveEngine() == createCharScreen and createCharScreen:IsDoneButtonClickable() then
				createCharScreen:OnDoneButtonClick()
			end
		end)
	end
	pcall(function() if e:GetActiveEngine() ~= worldScreen then e:SelectEngine(worldScreen) end end)
end
local function hpRead()
	out(('hp level-up of %s (HPWAR 1d1+5, CON bonus on top): level %s -> %s, max HP %s -> %s'):format(name(P(0)),
		tostring(T.lv0), tostring(stat(P(0), 34)), tostring(T.hp0), tostring(stat(P(0), 1))))
end

-- 2 + 12. Weapon speed: a fight makes everyone swing; with IEX_FIX_DEBUG=1 IEX.log shows each speed factor the fix
--    computes (launcher speed for ammo, WSPECIAL SPEED -10 for proficiency 1-5).
local ENEMIES = { 'GNOLL01', 'XVART01', 'ORC01' }
local function spawn()
	for i = 0, 2 do
		for k, r in ipairs(ENEMIES) do
			if (k + i) % 3 == 0 then queue('CreateCreatureObject("' .. r .. '",Myself,0,0,0)', P(i)) end
		end
	end
end
local function attackAll()
	unpause()
	for i = 0, 5 do queue('AttackReevaluate(NearestEnemyOf(Myself),30)', P(i)) end
end
local function shot(tag) S.status('shot ' .. tag) end
-- Last lines of the dialog / combat log (the UI's worldMessageBoxText), colour codes removed.
local function messages(n)
	local text = tostring(rawget(_G, 'worldMessageBoxText') or '')
	local lines = {}
	for line in text:gmatch('[^\n]+') do
		line = line:gsub('%^0x%x%x%x%x%x%x%x%x', ''):gsub('%^%-', '')
		lines[#lines + 1] = line
	end
	for i = math.max(1, #lines - n + 1), #lines do out('log: ' .. lines[i]) end
end
local function pause(on)
	pcall(function() if worldScreen:CheckIfPaused() ~= on then worldScreen:TogglePauseGame(true) end end)
end

local STEPS = {
	{ 1, partyFill },
	{ 30, function() info() protectParty() testOp33() op182Prepare() splprotPrepare() simPrepare() end },
	{ 45, testOp33Later },
	{ 60, function() op182Missing() splprotImmunity() simCast() end },
	{ 90, splprotCast },
	{ 120, function() op182MissingRead() splprotRead() simRead() end },
	{ 150, function() op182AmuletRead() op206() xpLoss() trapLimit() end },
	{ 200, function() op206Read() xpRead() pause(true) end },
	{ 215, function() shot('messages') messages(12) end },
	{ 330, function() pause(false) hpXP() end },
	{ 380, hpLevelUp }, { 400, hpDone }, { 420, hpRead },
	{ 430, function() spawn() attackAll() end },
	{ 550, attackAll }, { 700, attackAll },
	{ 850, function() info() S.flush() S.status('DONE ' .. #S.lines) end },
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

function FXT_Tick()
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
	-- start screen up: its title function ran 30 times, or (UIs without getTitle) 5 s after the main file loaded
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
	if not Infinity_IsMenuOnStack('FXT_TICK') then Infinity_PushMenu('FXT_TICK') end
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
	pcall(EEex_Menu_LoadFile, 'FXT')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded')
