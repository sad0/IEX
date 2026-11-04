--[[
StickLuaFunctions native-hook probe (tools/stick). Our own code. Loads a save, starts fights and records every call
of StickLuaFunctions' hook callbacks (ST_Hook_* globals): arguments and return value, per test phase. The same
file runs under real EEex (Stick's asm hooks) and under IEX (src/core/native_stick.cpp).

Phases (game time, by world ticks of the STK_TICK menu):
  observe : enemies spawned next to the party, everyone attacks; callbacks unchanged.
  forceHit: ST_Hook_HitRoll returns 19 (natural 20), ST_Hook_CriticalHitMultiplier returns 3.
  forceMiss: ST_Hook_HitRoll returns 0 (natural 1).
  spells  : the party's casters cast at the enemies (saving throw / school hooks).
Output: <game dir>/stick_out.txt (io) or IEX/stick_out.txt (IEX_WriteFile); status in stick_status.txt.
Boot as tools/difftest: F11 (sent by the runner in the background) opens the load screen, then loads the save.
--]]

STK = STK or {}
local S = STK
S.SAVE = S.SAVE or 'STICKTEST'
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
	if IEX_Log then pcall(IEX_Log, '[STKPRB] ' .. tostring(s)) end
	local ok, wrote = pcall(writeFile, 'stick_status.txt', tostring(s) .. '\n')
	if not (ok and wrote) then print('STKPRB|STATUS ' .. tostring(s)) end
end

-- io / IEX_WriteFile when present, else print (InfinityLoader's log file, LogFile= in InfinityLoader.ini).
local function out(s) S.lines[#S.lines + 1] = s end
function S.flush()
	local ok, wrote = pcall(writeFile, 'stick_out.txt', table.concat(S.lines, '\n') .. '\n')
	if not (ok and wrote) then
		for i = (S.printed or 0) + 1, #S.lines do print('STKPRB|OUT ' .. S.lines[i]) end
		S.printed = #S.lines
	end
end

local function P(i) return EEex_Sprite_GetInPortrait(i) end

-- Callback recording ----------------------------------------------------------------------------------------
-- Through StickLuaFunctions' own listener API (ST_Add*Listener): its ST_Hook_* functions call the listeners with
-- their arguments, under EEex (asm hooks) and under IEX (native hooks) alike. Listeners can also change the
-- values (reroll tokens, new to-hit / damage / multiplier), which is how the force phases steer the fights.

S.phase = 'boot'
S.counts = {}
S.samples = {}
S.force = {}

local function idOf(sprite)
	local ok, id = pcall(function() return sprite.m_id end)
	return ok and id or tostring(sprite)
end

local function describe(v)
	local t = type(v)
	if t == 'userdata' then
		local id = idOf(v)
		return type(id) == 'number' and ('spr' .. id % 100000) or 'ud'
	end
	if t == 'number' and v > 0xFFFFFFFF then return 'ptr' end
	return tostring(v)
end

local function record(name, ret, ...)
	local key = S.phase .. ' ' .. name
	S.counts[key] = (S.counts[key] or 0) + 1
	local list = S.samples[key] or {}
	S.samples[key] = list
	if #list < 5 then
		local parts = {}
		for i = 1, select('#', ...) do parts[#parts + 1] = describe((select(i, ...))) end
		list[#list + 1] = '(' .. table.concat(parts, ',') .. ')' .. (ret ~= nil and (' -> ' .. describe(ret)) or '')
	end
	if name == 'AttackResult' then
		local hk = S.phase .. ' hits'
		S.counts[hk] = (S.counts[hk] or 0) + ((select(3, ...)) and 1 or 0)
	end
end

local function listen(adder, name, ret)
	local add = _G[adder]
	if type(add) ~= 'function' then out('no ' .. adder) return end
	add(function(...)
		local r = ret and ret(...) or nil
		record(name, r, ...)
		return r
	end)
end

local function installListeners()
	listen('ST_AddHideInPlainSightListener', 'Hide')
	listen('ST_AddAttackIndexListener', 'AttackIndex')
	listen('ST_AddAttackCancelListener', 'AttackCancel', function() return S.force.cancel end)
	listen('ST_AddHitRollListener', 'HitRoll', function() return S.force.reroll end)
	listen('ST_AddHitModListener', 'HitMod', function(_, _, v) return S.force.hitMod and v + S.force.hitMod end)
	listen('ST_AddAttackDamModListener', 'DamMod', function(_, _, v) return S.force.damMod end)
	listen('ST_AddCriticalHitModListener', 'CritMod', function(_, _, v) return S.force.critMod end)
	listen('ST_AddCriticalHitMultiplierListener', 'CritMult', function() return S.force.critMult end)
	listen('ST_AddButtonPressedListener', 'Button')
	listen('ST_AddRButtonPressedListener', 'RButton')
	listen('ST_AddBackstabTargetImmuneListener', 'BackstabImmune')
	listen('ST_AddBackstabConditionListener', 'BackstabDecide', function() return S.force.backstab end)
	listen('ST_AddBackstabSuccessListener', 'BackstabSuccess')
	listen('ST_AddSaveDCModListener', 'SaveDC')
	listen('ST_AddSaveModListener', 'SaveMod')
	listen('ST_AddCharGenClassDoneListener', 'ClassDone')
	listen('ST_AddProficiencyMaxListener', 'ProfMax', function(_, _, v) return S.force.profMax and v + S.force.profMax end)
	listen('ST_AddAttackResultListener', 'AttackResult')
	listen('ST_AddMeleeAttackListener', 'MeleeOp248')
end

local function report()
	out('== listener calls per phase (first samples: arguments -> listener value)')
	local keys = {}
	for k in pairs(S.counts) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		out(k .. ': ' .. S.counts[k])
		for _, s in ipairs(S.samples[k] or {}) do out('    ' .. s) end
	end
	out('== IEX_Features.stickHooks = ' .. tostring(IEX_Features and IEX_Features.stickHooks))
end

-- World actions ---------------------------------------------------------------------------------------------

local ENEMIES = { 'GNOLL01', 'XVART01', 'ORC01', 'SKELWA', 'GNOLL', 'XVART' }

local function queue(s, sprite) if sprite then pcall(EEex_Action_QueueResponseStringOnAIBase, s, sprite) end end

local function spawn()
	for i = 0, 2 do
		for k, r in ipairs(ENEMIES) do
			if (k + i) % 3 == 0 then queue('CreateCreatureObject("' .. r .. '",Myself,0,0,0)', P(i)) end
		end
	end
end

-- NPC dialogs (party members leaving, banters) pause the game: answer with the first reply / step on.
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

local function unpause()
	pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end)
end

local function attackAll()
	unpause()
	for i = 0, 5 do queue('AttackReevaluate(NearestEnemyOf(Myself),30)', P(i)) end
	-- what the party is doing (action id of each member's current action)
	local acts = {}
	for i = 0, 5 do
		local sp = P(i)
		local ok, a = pcall(function() return sp.m_curAction.m_actionID end)
		acts[#acts + 1] = sp and (ok and tostring(a) or '?') or '-'
	end
	local ok, list = pcall(EEex_Sprite_GetAllOfTypeStringInRange, P(0), '[ENEMY]', 800)
	local ok2, area = pcall(function() return P(0).m_pArea.m_resref:get() end)
	local ok3, gt = pcall(function() return EngineGlobals.g_pBaldurChitin.m_pObjectGame.m_worldTime.m_gameTime end)
	out(S.phase .. ' t=' .. tostring(gt) .. ' actions ' .. table.concat(acts, ' ') .. ' | enemies ' .. (ok and type(list) == 'table' and #list or tostring(list))
		.. ' | area ' .. tostring(area))
end

local function castAll()
	unpause()
	for i = 0, 5 do
		-- instant spell applications from each member (caster = the member): Fireball / Color Spray (school, save)
		queue('ClearActions(Myself)', P(i))
		queue('ApplySpellRES("SPWI304",NearestEnemyOf(Myself))', P(i))
		queue('ApplySpellRES("SPWI116",NearestEnemyOf(Myself))', P(i))
	end
end

local function hideAll()
	for i = 0, 5 do queue('Hide()', P(i)) end
end

local function phase(name, force)
	S.phase = name
	S.force = force
	S.status(name)
end

-- The party must survive the whole test (a dead protagonist ends the game): opcode 208 (minimum HP 1) on each
-- member, for the length of the test.
local function protectParty()
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			pcall(EEex_GameObject_ApplyEffect, sp, { effectID = 208, effectAmount = 1, durationType = 0, duration = 600,
				sourceID = sp.m_id, sourceTarget = sp.m_id })
		end
	end
end

-- Proficiency maximum (level-up screen): Player1 gets XP, the character screen's level-up opens, then the
-- proficiency panel's table (chargen.proficiency: id, value, max) is read with the listener off, then with +2
-- (the panel's max field); + is clicked 3 times on the lowest proficiency with -3, then up to 8 times on the first
-- with +2 (the maximum a + may reach).
local function profRows(tag)
	local rows = {}
	for i, p in ipairs(chargen and chargen.proficiency or {}) do
		if i <= 6 then rows[#rows + 1] = tostring(p.id) .. ':' .. tostring(p.value) .. '/' .. tostring(p.max) end
	end
	out('profMax ' .. tag .. ' ' .. (#rows > 0 and table.concat(rows, ' ') or 'no chargen.proficiency'))
end

local function profOpen()
	unpause()
	queue('AddXPObject(Player1,4000000)', P(0))
end

local function profLevelUp()
	local ok, err = pcall(function()
		e:SelectEngine(characterScreen)
		characterScreen:OnLevelUpButtonClick()
	end)
	out('profMax levelUp ' .. (ok and 'ok' or tostring(err)))
end

local function profClick(plus, n, row)
	local p = chargen and chargen.proficiency and chargen.proficiency[row or 1]
	local id = p and p.id
	if not id then return end
	for _ = 1, n do pcall(function() createCharScreen:OnProficiencyPlusMinusButtonClick(id, plus) end) end
end

local function profMeasure()
	S.force = {}
	profClick(true, 1) profClick(false, 1)
	profRows('off')
	S.force = { profMax = 2 }
	profClick(true, 1) profClick(false, 1)
	profRows('+2')
	-- the row with the lowest value (most room under the -3 maximum)
	local low, lowValue = 2, math.huge
	for i, p in ipairs(chargen and chargen.proficiency or {}) do
		if i <= 6 and (tonumber(p.value) or 99) < lowValue then low, lowValue = i, tonumber(p.value) end
	end
	S.force = { profMax = -3 }
	profClick(true, 3, low)
	profRows('-3 after 3 plus on row ' .. low)
	S.force = { profMax = 2 }
	profClick(true, 8)
	profRows('+2 after 8 plus')
	S.force = {}
end
local STEPS = {
	{ 30, function() installListeners() protectParty() phase('observe', {}) spawn() attackAll() end },
	{ 150, attackAll }, { 250, hideAll }, { 330, attackAll }, { 450, function() spawn() attackAll() end },
	{ 600, attackAll },
	{ 750, function() phase('forceHit', { reroll = 30, hitMod = 100, critMult = 3 }) spawn() attackAll() end },
	{ 900, attackAll }, { 1050, attackAll },
	{ 1200, function() phase('forceMiss', { reroll = -30, hitMod = -100 }) spawn() attackAll() end },
	{ 1350, attackAll }, { 1500, attackAll },
	{ 1650, function() phase('cancel', { cancel = true }) spawn() attackAll() end },
	{ 1800, attackAll },
	{ 1950, function() phase('spells', {}) spawn() end },
	{ 2050, castAll }, { 2200, castAll },
	{ 2300, function() phase('profMax', {}) profOpen() end },
	{ 2360, profLevelUp }, { 2420, profMeasure },
	{ 2480, function() report() S.flush() S.status('DONE ' .. #S.lines) end },
}

-- Step times are in 1/30 s of real time since the world came up (the tick menu runs at the render rate, which
-- differs between runs).
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

function STK_Tick()
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
	if not Infinity_IsMenuOnStack('STK_TICK') then Infinity_PushMenu('STK_TICK') end
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
	pcall(EEex_Menu_LoadFile, 'STKPRB')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = Infinity_GetClockTicks()
	S.status('main file loaded')
end) end)

pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)

S.status('probe loaded; M_Stick ' .. tostring(st_GameVersion))
