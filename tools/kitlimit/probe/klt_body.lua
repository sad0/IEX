--[[
Kit-limit probe (tools/kitlimit, docs/KIT_LIMIT.md). Our own code. The runner prepends KLT_MODE, KLT_KIT, KLT_CONTROL.

KLT_MODE 'new':    start screen -> New Game -> chargen driven through createCharScreen (human male fighter, kit
                   KLT_KIT, abilities maxed), game starts; then in the world: CLAB innates of Player1, level-up through
                   the character screen, AddKit to KLT_CONTROL and back, save (slot "KLTSAVE"), dual-class to mage.
KLT_MODE 'reload': loads "KLTSAVE", checks kit and innates, levels up again.
The CLAB of probe kit n grants innate K<nnn>L<ll> at level ll (tools/kitlimit/make_mod.py): the innates tell which
kit's CLAB the engine applied, for which levels. Output: IEX/kitlimit_out.txt, status IEX/kitlimit_status.txt.
The runner sends F11 (background key events) while the status asks for it; every F11 runs one driver step.
--]]

KLT = KLT or {}
local S = KLT
S.lines = S.lines or {}
S.state = S.state or 'boot'
S.ticks = 0

local function writeFile(name, text)
	if IEX_WriteFile then return IEX_WriteFile(name, text) end
	return false
end
function S.status(s)
	if IEX_Log then pcall(IEX_Log, '[KLT] ' .. tostring(s)) end
	pcall(writeFile, 'kitlimit_status.txt', tostring(s) .. '\n')
end
local function out(s) S.lines[#S.lines + 1] = s pcall(IEX_Log, '[KLT] ' .. s) end
function S.flush() pcall(writeFile, 'kitlimit_out.txt', table.concat(S.lines, '\n') .. '\n') end

local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function stat(sp, id) local ok, v = pcall(EEex_Sprite_GetStat, sp, id) return ok and v or nil end
local function queue(s, sprite) if sprite then pcall(EEex_Action_QueueResponseStringOnAIBase, s, sprite) end end


-- The probe innates the sprite knows: { [kitIndex] = {levels...} } and a text summary.
local function probeInnates(sp)
	local by = {}
	local ok, err = pcall(function()
		for _, _, resref in EEex_Sprite_GetKnownInnateSpellsIterator(sp) do
			local k, l = tostring(resref):match('^K(%d%d%d)L(%d%d)$')
			if not k then
				by.other = by.other or {}
				by.other[#by.other + 1] = tostring(resref)
			end
			if k then
				k, l = tonumber(k), tonumber(l)
				by[k] = by[k] or {}
				by[k][#by[k] + 1] = l
			end
		end
	end)
	local parts = {}
	local keys = {}
	for k in pairs(by) do if k ~= 'other' then keys[#keys + 1] = k end end
	table.sort(keys)
	for _, k in ipairs(keys) do
		table.sort(by[k])
		local lv = by[k]
		local lo, hi = lv[1], lv[#lv]
		parts[#parts + 1] = ('K%03d: %d innates (levels %d-%d)'):format(k, #lv, lo, hi)
	end
	if by.other then parts[#parts + 1] = ('other innates: %s'):format(table.concat(by.other, ' ')) end
	if not ok then parts[#parts + 1] = 'error ' .. tostring(err) end
	return by, (#parts > 0 and table.concat(parts, ', ') or 'no probe innates')
end

local function describe(tag)
	local sp = P(0)
	if not sp then out(tag .. ': no Player1') return end
	local okKit, kit = pcall(function() return sp.m_baseStats.m_mageSpecUpperWord * 0x10000 + sp.m_baseStats.m_mageSpecialization end)
	if not okKit then kit = stat(sp, 152) end
	local _, text = probeInnates(sp)
	local lim = IEX_KitLimit and IEX_KitLimit() or {}
	out(('%s: kit=0x%X (row %d) class=%s level=%s xp=%s | %s | IEX tables=%s'):format(tag, kit or -1,
		kit and (kit % 0x4000) or -1, tostring(sp.m_typeAI.m_Class), tostring(stat(sp, 34)),
		tostring(sp.m_baseStats.m_xp), text, tostring(lim.tables)))
end

-- Chargen driver ---------------------------------------------------------------------------------------------

local function onStack(name) local ok, r = pcall(Infinity_IsMenuOnStack, name) return ok and r end
local function cc(method, ...) local f = createCharScreen[method] return f(createCharScreen, ...) end
local function doneClickable() local ok, r = pcall(cc, 'IsDoneButtonClickable') return ok and r end
local function popDone(what)
	if not doneClickable() then return what .. ': done not clickable' end
	Infinity_PopMenu()
	cc('OnDoneButtonClick')
	return what .. ': done'
end
local function pick(list, test)
	for i, e in ipairs(list or {}) do
		local okName, name = pcall(Infinity_FetchString, e.name)
		if test(e, okName and name or '') then return i, e end
	end
end

local CG = {
	{ 'CHARGEN_DIFFICULTY', function()
		Infinity_PopMenu()
		cc('AcceptCharacter', currentDifficulty or 3)
		return 'difficulty: accept'
	end },
	{ 'CHARGEN_NAME', function()
		charNameEdit = 'Kit Tester'
		return popDone('name')
	end },
	{ 'CHARGEN_HATEDRACE', function()
		local e = chargen.hatedRace and chargen.hatedRace[1]
		if e then cc('OnRacialEnemySelectButtonClick', e.id) end
		return popDone('hated race')
	end },
	{ 'CHARGEN_CUSTOMSOUNDS', function() return popDone('sounds') end },
	{ 'CHARACTER_COLOR', function()
		cc('OnDoneButtonClick')
		Infinity_PopMenu('CHARACTER_COLOR', 0, 0)
		return 'colors: done'
	end },
	{ 'CHARGEN_PORTRAIT', function() return popDone('portrait') end },
	{ 'CHARGEN_PROFICIENCIES', function()
		for _ = 1, 20 do
			if doneClickable() then break end
			for _, p in ipairs(chargen.proficiency or {}) do pcall(cc, 'OnProficiencyPlusMinusButtonClick', p.id, true) end
		end
		return popDone('proficiencies')
	end },
	{ 'CHARGEN_ABILITIES', function()
		pcall(cc, 'OnCheatyMcCheaterson')
		return popDone('abilities')
	end },
	{ 'CHARGEN_ALIGNMENT', function()
		local tried = {}
		for i, a in ipairs(chargen.alignment or {}) do
			currentChargenAlignment = i
			pcall(cc, 'OnAlignmentSelectButtonClick', a.id)
			tried[#tried + 1] = tostring(a.id)
			if doneClickable() then break end
		end
		return popDone('alignment (' .. table.concat(tried, ' ') .. ')')
	end },
	{ 'CHARGEN_KIT', function()
		local i, e = pick(chargen.kit, function(_, name) return name:lower() == KLT_KIT:lower() end)
		if not e then
			local names = {}
			for k, x in ipairs(chargen.kit or {}) do
				if k <= 3 or k > #chargen.kit - 3 then names[#names + 1] = tostring(x.id) .. '=' .. tostring(Infinity_FetchString(x.name)) end
			end
			out(('chargen kit list: %d kits, %s not found (%s)'):format(#(chargen.kit or {}), KLT_KIT, table.concat(names, ' ')))
			return 'kit: not found'
		end
		out(('chargen kit list: %d kits, %s is entry %d (id %s)'):format(#chargen.kit, KLT_KIT, i, tostring(e.id)))
		currentChargenKit = i
		cc('OnKitSelectButtonClick', e.id)
		return popDone('kit ' .. KLT_KIT)
	end },
	{ 'CHARGEN_CLASS', function()
		local _, e = pick(chargen.class, function(x) return x.id == 2 end)
		if e then cc('OnClassSelectButtonClick', e.id) end
		return popDone('class fighter')
	end },
	{ 'CHARGEN_RACE', function()
		local _, e = pick(chargen.races, function(x) return x.id == 1 end)
		if e then cc('OnRaceSelectButtonClick', e.id) end
		return popDone('race human')
	end },
	{ 'CHARGEN_GENDER', function()
		cc('OnGenderSelectButtonClick', 1)
		return popDone('gender')
	end },
}

local function chargenStep()
	for _, m in ipairs(CG) do
		if onStack(m[1]) then return m[2]() end
	end
	if onStack('CHARGEN') then
		if cc('IsChargenComplete') then
			cc('AcceptCharacter', -1)
			return 'accept'
		end
		cc('OnMenuButtonClick')
		return 'menu (step ' .. tostring(cc('GetCurrentStep')) .. ')'
	end
	return nil
end

-- World steps ------------------------------------------------------------------------------------------------

local function levelUp(tag)
	local ok, err = pcall(function()
		e:SelectEngine(characterScreen)
		characterScreen:OnLevelUpButtonClick()
	end)
	out(tag .. ' level-up opened: ' .. (ok and 'ok' or tostring(err)))
end
local function levelUpDone(tag)
	for _ = 1, 6 do
		pcall(function()
			if e:GetActiveEngine() == createCharScreen then
				for _, p in ipairs(chargen.proficiency or {}) do
					if doneClickable() then break end
					pcall(cc, 'OnProficiencyPlusMinusButtonClick', p.id, true)
				end
				if doneClickable() then cc('OnDoneButtonClick') end
			end
		end)
	end
	pcall(function() if e:GetActiveEngine() ~= worldScreen then e:SelectEngine(worldScreen) end end)
end

-- Script action SaveGame(slot): the engine's own save path, no save screen.
local function saveGame()
	queue('SaveGame(' .. (KLT_SAVESLOT or 9) .. ')', P(0))
	out('save: SaveGame(' .. (KLT_SAVESLOT or 9) .. ') queued')
end

local function dualStep()
	-- character screen -> Dual Class (CHARGEN_DUALCLASS): class mage, proficiencies, done
	if onStack('CHARGEN_CLASS') then
		local _, en = pick(chargen.class, function(x) return x.id == 1 end)
		if en then cc('OnClassSelectButtonClick', en.id) end
		return popDone('dual class mage')
	end
	if onStack('CHARGEN_PROFICIENCIES') then
		for _ = 1, 20 do
			if doneClickable() then break end
			for _, p in ipairs(chargen.proficiency or {}) do pcall(cc, 'OnProficiencyPlusMinusButtonClick', p.id, true) end
		end
		return popDone('dual proficiencies')
	end
	if onStack('CHARGEN_CHOOSE_SPELLS') then
		for i = 1, 6 do pcall(cc, 'OnLearnMageSpellButtonClick', i) end
		return popDone('dual spells')
	end
	if onStack('CHARGEN_MEMORIZE_MAGE') then return popDone('dual memorize') end
	if onStack('CHARGEN_DUALCLASS') then
		local step = cc('GetCurrentStep')
		if step == const.STEP_DUALCLASS_DONE then
			Infinity_PopMenu()
			cc('OnDoneButtonClick')
			return 'dual done'
		end
		cc('OnMenuButtonClick')
		return 'dual menu (step ' .. tostring(step) .. ')'
	end
	return nil
end

local W = {}
local NEW_STEPS = {
	{ 5, function() describe('after chargen') end },
	{ 6, function() queue('AddXPObject(Player1,1500000)', P(0)) end },
	{ 10, function() W.lv = stat(P(0), 34) levelUp('level-up 1') end },
	{ 14, function() levelUpDone('level-up 1') end },
	{ 18, function() describe('after level-up') end },
	{ 20, function() queue('AddKit(' .. KLT_CONTROL .. ')', P(0)) end },
	{ 26, function() describe('after AddKit(' .. KLT_CONTROL .. ')') end },
	{ 27, function() queue('AddKit(' .. KLT_KIT .. ')', P(0)) end },
	{ 33, function() describe('after AddKit(' .. KLT_KIT .. ')') end },
	{ 34, saveGame },
	{ 38, function() pcall(function() if e:GetActiveEngine() ~= worldScreen then e:SelectEngine(worldScreen) end end) end },
	{ 36, function()
		-- dual-class to mage needs STR 15 / INT 17: permanent op44 / op19 (set 18) on the base stats
		local sp = P(0)
		for _, op in ipairs({ 19, 44 }) do  -- INT, STR
			pcall(EEex_GameObject_ApplyEffect, sp, { effectID = op, effectAmount = 18, dwFlags = 1, durationType = 1,
				sourceID = sp.m_id, sourceTarget = sp.m_id })
		end
	end },
	{ 40, function() pcall(function() e:SelectEngine(characterScreen) end) end },
	{ 43, function()
		local sp = P(0)
		out(('dual-class: STR %s INT %s, clickable %s'):format(tostring(stat(sp, 36)), tostring(stat(sp, 38)),
			tostring(characterScreen:IsDualClassButtonClickable())))
		local ok, err = pcall(function() characterScreen:OnDualClassButtonClick() end)
		out('dual-class opened: ' .. (ok and 'ok' or tostring(err)))
		S.dual = true
	end },
	{ 70, function()
		S.dual = false
		pcall(function() if e:GetActiveEngine() ~= worldScreen then e:SelectEngine(worldScreen) end end)
	end },
	{ 74, function() describe('after dual-class') end },
	{ 76, function() S.flush() S.status('DONE ' .. #S.lines) end },
}
local RELOAD_STEPS = {
	{ 5, function() describe('after reload') end },
	{ 6, function() queue('AddXPObject(Player1,500000)', P(0)) end },
	{ 10, function() levelUp('level-up after reload') end },
	{ 14, function() levelUpDone('level-up after reload') end },
	{ 18, function() describe('after reload level-up') end },
	{ 20, function() S.flush() S.status('DONE ' .. #S.lines) end },
}

local function tickWorld()
	local t = Infinity_GetClockTicks()
	S.t0 = S.t0 or t
	local elapsed = (t - S.t0) / 1000
	S.done = S.done or {}
	if not S.dual and e:GetActiveEngine() == worldScreen then
		pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end)
	end
	if S.dual then
		local r = dualStep()
		if r then out('dual: ' .. r) end
	end
	pcall(function()
		local choices = worldPlayerDialogChoices
		if choices and #choices > 0 and choices[1].marker then worldScreen:OnDialogReplyClick(choices[1].marker)
		elseif Infinity_IsMenuOnStack('WORLD_DIALOG') then worldScreen:StepDialog() end
	end)
	for i, st in ipairs(KLT_MODE == 'reload' and RELOAD_STEPS or NEW_STEPS) do
		if not S.done[i] and elapsed >= st[1] then
			S.done[i] = true
			local ok, err = pcall(st[2])
			if not ok then out('step ' .. st[1] .. ' error: ' .. tostring(err)) end
			S.flush()
		end
	end
end

-- Boot: every F11 runs one step ------------------------------------------------------------------------------

local function enterWorld(via)
	if S.state == 'world' then return end
	S.state = 'world'
	S.status('world (' .. via .. ') - keys')
	local lim = IEX_KitLimit and IEX_KitLimit() or {}
	out(('IEX kitLimit: installed=%s sites=%s maxRow=%s why=%s; IEX_Features.kitLimit=%s'):format(tostring(lim.installed),
		tostring(lim.sites), tostring(lim.maxRow), tostring(lim.why), tostring(IEX_Features and IEX_Features.kitLimit)))
end

local function inWorld()
	local ok, r = pcall(function() return P(0) ~= nil and e:GetActiveEngine() == worldScreen end)
	return ok and r
end

local function onKey()
	if S.state == 'boot' then
		if KLT_MODE == 'reload' then
			S.state = 'loadscreen'
			S.status('opening load screen - keys')
			startEngine:OnLoadGameButtonClick()
		else
			S.state = 'chargen'
			pcall(function() startEngine:OnSoAButtonClick(true) end)
			startEngine:OnNewGameButtonClick()
			S.status('chargen - keys')
		end
	elseif S.state == 'loadscreen' then
		for _, f in ipairs(gameSaves and gameSaves.files or {}) do
			out('save found: ' .. tostring(f.slotName) .. ' | ' .. tostring(f.fileName))
			do
				S.state = 'loading'
				S.status('loading ' .. tostring(f.fileName) .. ' - keys')
				loadScreen:LoadGame(f.fileName)
				return
			end
		end
		S.status('save not found')
	elseif (S.state == 'chargen' or S.state == 'loading') and inWorld() then
		enterWorld(S.state)
	elseif S.state == 'chargen' then
		local r = chargenStep()
		S.cgSteps = (S.cgSteps or 0) + 1
		if r then out('chargen: ' .. r) end
		if S.cgSteps > 80 then S.flush() S.status('chargen stuck') end
	elseif S.state == 'world' then
		pcall(tickWorld)
	end
end

pcall(EEex_Key_AddPressedListener, function(key)
	if key ~= EEex_Key_GetFromName('F11') then return end
	local ok, err = pcall(onKey)
	if not ok then out('key step error: ' .. tostring(err)) S.flush() end
end)

pcall(EEex_Menu_AddMainFileLoadedListener, function() S.status('main file loaded - keys') end)
S.status('probe loaded')
