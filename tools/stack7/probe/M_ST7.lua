local src = [==========[
--[[
Stack7 feature probe (IEX compat, our own code). Exercises the features of the 7 EEex mods of the popular-mods scan
(Tweaks Anthology, BuffBot, Bubb's Spell Menu Extended, Infinity UI++, Tactics Remix, Artisan's Kitpack) through the
mods' own functions, on the same save, under EEex and under IEX, and records observable results as "key = value"
lines (compare.py compares them). Nondeterministic values (random rolls, combat) are recorded under keys starting
with "nd." and compared loosely.
Boot as the other probes: F11 (background key sent by the runner) opens the load screen, loads the save, then the
steps run on a world tick menu (ST7_TICK).
Output: st7_out.txt through io or IEX_WriteFile; else "ST7|" lines on print (EEex: InfinityLoader log).
--]]

ST7 = ST7 or {}
local S = ST7
S.SAVE = S.SAVE or 'IEXRT'
S.lines = S.lines or {}
S.state = S.state or 'boot'
S.errors = S.errors or 0
S.side = (IEX_Version or IEX_Features) and 'iex' or 'eeex'

local hasIO = io and io.open and true or false
local function writeFile(name, text)
	if hasIO then
		local f = io.open(name, 'w')
		if f then f:write(text) f:close() return true end
	end
	if IEX_WriteFile then return IEX_WriteFile(name, text) end
	return false
end
local printed = 0
function S.status(s)
	s = tostring(s)
	if not pcall(writeFile, 'st7_status.txt', s .. '\n') or (not hasIO and not IEX_WriteFile) then print('ST7|STATUS ' .. s) end
end
local function clean(v)
	v = tostring(v)
	v = v:gsub('[\r\n]', '\\n')
	return v
end
local function out(k, v)
	local l = k .. ' = ' .. clean(v)
	S.lines[#S.lines + 1] = l
	if not hasIO and not IEX_WriteFile then
		-- long lines are split: ST7| then ST7~| continuations
		local first = true
		while #l > 0 do
			print((first and 'ST7|' or 'ST7~|') .. l:sub(1, 900))
			l = l:sub(901)
			first = false
		end
	end
end
S.out = out
function S.flush() pcall(writeFile, 'st7_out.txt', table.concat(S.lines, '\n') .. '\n') end
local function try(f, ...) local ok, v = pcall(f, ...) if ok then return v end return 'ERR:' .. tostring(v) end
local function now() return Infinity_GetClockTicks() end
local function P(i) return EEex_Sprite_GetInPortrait(i) end
local function queue(s, sp) if sp then return pcall(EEex_Action_QueueResponseStringOnAIBase, s, sp) end end
local function rget(v) if type(v) == 'userdata' and v.get then return v:get() end return v end
local function errOut(k, e) S.errors = S.errors + 1 out(k .. '.error', e) end
local function sorted(t) table.sort(t) return t end

-- error messages: absolute file paths and line numbers of IEX vs EEex internals differ; keep the mod-side part
local function errText(e)
	e = tostring(e)
	return e
end

local function section(name, fn, ...)
	local ok, e = pcall(fn, ...)
	if not ok then errOut(name, errText(e)) end
	S.flush()
end

-- --- Generic sprite dump (deterministic parts) ------------------------------------------------------------

local LOCALS = { "gtAnimalLastStand","gtAnimalRunningWild","gtArcherKitBonus","gtDisplayStoneskinsLeft","gtMakeGreaseIgnitable",
	"gtMakeInfravisionUseful","gtMoreSensibleCowlies","gtNWNArmorVsDex","gtNWNArmoredCaster","gtNWNBaneOfEnemies",
	"gtNWNBlindFight","gtNWNCalledShot","gtNWNCircleKick","gtNWNCleave","gtNWNCounterSpell","gtNWNCounterSpellMode",
	"gtNWNCurCantripsPerDay","gtNWNDarkBlessing","gtNWNDefensiveRoll","gtNWNDirtyFighting","gtNWNDisarm",
	"gtNWNDivineGrace","gtNWNDualWieldLeft","gtNWNDualWieldRight","gtNWNEvasion","gtNWNFearless","gtNWNGoodAim",
	"gtNWNKnockdown","gtNWNManyshot","gtNWNMaxCantripsPerDay","gtNWNNatureSense","gtNWNOpportunist","gtNWNParry",
	"gtNWNParryMode","gtNWNPoisonSave","gtNWNSelfConcealment","gtNWNSmiteEvil","gtNWNSmiteGood",
	"gtNWNSneakAttBlackguard","gtNWNSpellPenetration","gtNWNTracklessStep","gtNWNUncannyDodge",
	"gtNWNWeaponFinesse","gtNWNWoodlandStride" }

local function effectList(sp, listName)
	local l = {}
	EEex_Utility_IterateCPtrList(sp[listName], function(e)
		l[#l + 1] = string.format('%d:%s:%s:%d:%d:%d', e.m_effectId, rget(e.m_res), rget(e.m_sourceRes),
			e.m_effectAmount, e.m_dWFlags, e.m_durationType)
	end)
	return sorted(l)
end

local function buttons(sp, kind)
	local l = {}
	local list = sp:GetQuickButtons(kind, 0)
	EEex_Utility_IterateCPtrList(list, function(b)
		l[#l + 1] = string.format('%s:%d:%d', b.m_abilityId.m_res:get(), b.m_count, b.m_bDisabled)
	end)
	EEex_Utility_FreeCPtrList(list)
	return sorted(l)
end

function S.dumpSprite(k, sp, full)
	out(k .. '.class', try(function() return sp.m_typeAI.m_Class .. '/' .. tostring(EEex_Sprite_GetStat(sp, 152)) .. '/' .. sp.m_typeAI.m_Race end))
	out(k .. '.name', try(function() return sp:getName() end))
	local st = {}
	for i = 0, 202 do st[#st + 1] = tostring(try(EEex_Sprite_GetStat, sp, i)) end
	out(k .. '.stats', table.concat(st, ','))
	if IEX_GetStat then
		out(k .. '.stat78src', 'derived=' .. tostring(try(IEX_GetStat, sp.m_derivedStats, 78)) .. ' temp=' .. tostring(try(IEX_GetStat, sp.m_tempStats, 78))
			.. ' useDerived=' .. tostring(try(function() return sp.m_useDerivedStats end)) .. ' attacks=' .. tostring(try(IEX_GetStat, sp.m_derivedStats, 8)))
	end
	local loc = {}
	for _, n in ipairs(LOCALS) do
		local v = try(function() return sp:getLocalInt(n) end)
		if v ~= 0 then loc[#loc + 1] = n .. '=' .. tostring(v) end
	end
	out(k .. '.locals', table.concat(loc, ' '))
	out(k .. '.innates', try(function() return table.concat(buttons(sp, 4), ' ') end))
	if full then
		out(k .. '.spells', try(function() return table.concat(buttons(sp, 2), ' ') end))
		out(k .. '.timed', try(function() return table.concat(effectList(sp, 'm_timedEffectList'), ' ') end))
		out(k .. '.equiped', try(function() return table.concat(effectList(sp, 'm_equipedEffectList'), ' ') end))
	else
		out(k .. '.ntimed', try(function() return #effectList(sp, 'm_timedEffectList') end))
	end
end

-- --- Infinity UI++ (raw memory reads at engine offsets) ----------------------------------------------------

local function iuiSprite(k, sp)
	-- the mod's own functions (my_CRE.lua): portraits, scripts, items, timed effects
	out(k .. '.portraits', try(function() return table.concat({ Sprite_Portraits(sp) }, ',') end))
	out(k .. '.scripts', try(function() return table.concat({ Sprite_Scripts(sp) }, ',') end))
	local items = Sprite_Items(sp)
	local il = {}
	for _, it in ipairs(items) do
		il[#il + 1] = string.format('%s/%s/q%s,%s,%s/%s/w%s/sel%s/%s/d%d/%s', it.resref, it.slot and it.slot.id or '?', tostring(it.qty),
			tostring(it.qty_2), tostring(it.qty_3), tostring(it.icon), tostring(it.weight), tostring(it.is_weapon_selected),
			tostring(it.descPicture), #(it.description or ''), tostring(it.item_name))
	end
	-- Sprite_Items walks SLOTS with pairs(): its order is the Lua hash order (LuaJIT vs Lua 5.2), sorted here
	table.sort(il)
	table.sort(items, function(a, b) return a.resref < b.resref end)
	out(k .. '.items', #il .. ' ' .. table.concat(il, ' '))
	if items[1] then
		out(k .. '.hasItem', try(function() return table.concat(Sprite_HasItem(sp, items[1].resref), ',') end))
		out(k .. '.hasItemInSlot', try(function() return tostring(Sprite_HasItem_InSlot(sp, items[1].resref:lower(), { items[1].slot.id })) end))
	end
	local te = Sprite_Timed_Effects(sp)
	local tl = {}
	for _, e in ipairs(te) do
		tl[#tl + 1] = string.format('%s/%s/%s/op%s/p%s,%s/%s/d%d', e.res, e.icon, e.spellName, tostring(e.opcode),
			tostring(e.p1), tostring(e.p2), tostring(e.secondary_type), #(e.description or ''))
	end
	table.sort(tl)
	out(k .. '.timedEffects', #tl .. ' ' .. table.concat(tl, ' '))
	-- the same engine data through field names: each raw offset must name the field the mod's comment says
	local base = EEex_UDToPtr(sp.m_baseStats)
	local checks = {
		{ 'portraitSmall', 0x2C, function() return sp.m_baseStats.m_portraitSmall:get() end },
		{ 'portraitLarge', 0x34, function() return sp.m_baseStats.m_portraitLarge:get() end },
		{ 'scriptOverride', 0x240, function() return sp.m_baseStats.m_scriptOverRide:get() end },
		{ 'scriptClass', 0x248, function() return sp.m_baseStats.m_scriptClass:get() end },
		{ 'scriptRace', 0x280, function() return sp.m_baseStats.m_scriptRace:get() end },
		{ 'scriptGeneral', 0x258, function() return sp.m_baseStats.m_scriptGeneral:get() end },
		{ 'scriptDefault', 0x260, function() return sp.m_baseStats.m_scriptDefault:get() end },
	}
	for _, c in ipairs(checks) do
		local raw = try(EEex_ReadLString, base + c[2], 8)
		out(k .. '.raw.' .. c[1], tostring(raw) .. ' field=' .. tostring(try(c[3])))
	end
	local rr = try(function() return EEex_ReadLString(EEex_UDToPtr(sp.m_resref), 8) end)
	out(k .. '.raw.resref', tostring(rr) .. ' field=' .. tostring(try(function() return sp.m_resref:get() end)))
	-- the equipment array: slot pointers, CItem resref at +0x10, flags at +0x24, charges at +0x1C
	local ib = EEex_UDToPtr(sp.m_equipment.m_items)
	local sl = {}
	for i = 0, 38 do
		local item = EEex_Read64(ib + i * 8)
		if item ~= 0 then
			local viaField = try(function() return sp.m_equipment.m_items:get(i).pRes.resref:get() end)
			sl[#sl + 1] = i .. ':' .. EEex_ReadLString(item + 0x10, 8) .. '/' .. tostring(viaField) .. '/f' .. EEex_Read32(item + 0x24)
				.. '/c' .. EEex_Read16(item + 0x1C) .. ',' .. EEex_Read16(item + 0x1E) .. ',' .. EEex_Read16(item + 0x20)
		end
	end
	out(k .. '.raw.slots', table.concat(sl, ' '))
	out(k .. '.raw.selectedWeapon', try(function() return sp.m_equipment.m_selectedWeapon end))
end

local function iuiResources()
	-- item and spell headers read raw (my__LIB.lua my_Show_Description, my_CRE.lua): name, category, icons, weight
	for _, r in ipairs({ 'SW1H01', 'POTN08', 'SCRL1B', 'AROW01', 'MISC07', 'PLAT01', 'RING02' }) do
		local res = EEex_Resource_Demand(r, 'itm')
		if res then
			local f = EEex_UDToPtr(res)
			out('iui.itm.' .. r, string.format('name=%s cat=%d icon=%s desc=%d unid=%d max=%d w=%d pic=%s', Infinity_FetchString(EEex_Read32(f + 0x0C)),
				EEex_Read16(f + 0x1C), EEex_ReadLString(f + 0x3A, 8), EEex_Read32(f + 0x54), EEex_Read32(f + 0x50),
				EEex_Read16(f + 0x38), EEex_Read16(f + 0x4C), EEex_ReadLString(f + 0x58, 8)))
		else
			out('iui.itm.' .. r, 'nil')
		end
	end
	for _, r in ipairs({ 'SPWI112', 'SPPR101', 'SPWI304', 'SPIN101' }) do
		local h = EEex_Resource_Demand(r, 'SPL')
		if h then
			local f = EEex_UDToPtr(h)
			out('iui.spl.' .. r, string.format('name=%s raw=%d desc=%d/%d gname=%s lvl=%s', Infinity_FetchString(h.genericName),
				EEex_Read32(f + 0x0C), EEex_Read32(f + 0x50), EEex_Read32(f + 0x54), tostring(h.genericName), tostring(h.spellLevel)))
		end
	end
	-- header methods (BuffBot, IUI timed effects, Spell Menu): getAbility / getAbilityForLevel
	for _, r in ipairs({ 'SPWI305', 'SPWI112', 'SPPR101', 'SPIN101' }) do
		local h = EEex_Resource_Demand(r, 'SPL')
		local l = {}
		for _, lv in ipairs({ 0, 1, 5, 10, 30 }) do
			l[#l + 1] = 'L' .. lv .. '=' .. tostring(try(function() local a = h:getAbilityForLevel(lv) return a and a.minCasterLevel or 'nil' end))
		end
		for _, i in ipairs({ 0, 1, 99, -1 }) do
			l[#l + 1] = 'A' .. i .. '=' .. tostring(try(function() local a = h:getAbility(i) return a and (a.minCasterLevel .. '/' .. a.quickSlotIcon:get()) or 'nil' end))
		end
		l[#l + 1] = 'fn=' .. tostring(try(function() local a = EEex_Resource_GetSpellAbilityForLevel(h, 0) return a and a.minCasterLevel or 'nil' end))
		out('hdr.spl.' .. r, table.concat(l, ' '))
	end
	for _, r in ipairs({ 'SW1H01', 'POTN08', 'WAND02' }) do
		local h = EEex_Resource_Demand(r, 'ITM')
		local l = {}
		for _, i in ipairs({ 0, 1, 99 }) do
			l[#l + 1] = 'A' .. i .. '=' .. tostring(try(function() local a = h:getAbility(i) return a and (a.type .. '/' .. a.quickSlotIcon:get()) or 'nil' end))
		end
		out('hdr.itm.' .. r, table.concat(l, ' '))
	end
	-- custom fields on engine objects (IUI's radar stores its own fields on the sprites it lists)
	pcall(function()
		local sp = P(0)
		local ok1, e1 = pcall(function() sp.st7Custom = 'x1' end)
		local again = EEex_Sprite_GetInPortrait(0)
		out('ud.custom', tostring(ok1) .. ' same=' .. tostring(try(function() return sp.st7Custom end)) .. ' other=' .. tostring(try(function() return again.st7Custom end))
			.. ' raw=' .. tostring(rawequal(sp, again)))
		pcall(function() sp.st7Custom = nil end)
	end)
	-- write / read round trip on a resource header field the mod rewrites nowhere: written back at once
	local res = EEex_Resource_Demand('MISC07', 'itm')
	if res then
		local f = EEex_UDToPtr(res)
		local w0 = EEex_Read16(f + 0x4C)
		EEex_Write16(f + 0x4C, 1234)
		local w1 = EEex_Read16(f + 0x4C)
		local viaField = try(function() return res.weight end)
		EEex_Write16(f + 0x4C, w0)
		out('iui.write16', w1 .. ' field=' .. tostring(viaField) .. ' restored=' .. EEex_Read16(f + 0x4C))
	end
	-- the other read / write flavours IUI's library lists (my__LIB.lua), on a buffer we own
	local ok, e = pcall(function()
		local p = EEex_Malloc and EEex_Malloc(64)
		if not p then out('iui.rw', 'no EEex_Malloc') return end
		EEex_Write8(p, 0xFE) EEex_Write16(p + 2, 0xFFFE) EEex_Write32(p + 4, -2) EEex_Write64(p + 8, 0x123456789)
		EEex_WriteLString(p + 16, 'ABCDEFGHIJ', 8)
		EEex_WriteString(p + 32, 'hello')
		EEex_WritePtr(p + 48, p)
		out('iui.rw', table.concat({ EEex_Read8(p), EEex_ReadU8(p), EEex_Read16(p + 2), EEex_ReadU16(p + 2), EEex_Read32(p + 4),
			EEex_ReadU32(p + 4), tostring(EEex_Read64(p + 8)), tostring(EEex_ReadU64 and EEex_ReadU64(p + 8)),
			EEex_ReadLString(p + 16, 8), EEex_ReadString(p + 32), tostring(EEex_ReadPtr(p + 48) == p),
			tostring(EEex_ReadPointer(p + 48) == p) }, ','))
		if EEex_Free then EEex_Free(p) end
	end)
	if not ok then errOut('iui.rw', e) end
end

local function iuiRadar()
	if not my_screen_radar_Search_sprites then out('iui.radar', 'absent') return end
	my_screen_radar_Search_sprites()
	local list = my_radar_sprites or {}
	local names = {}
	for i, sp in ipairs(list) do names[#names + 1] = tostring(sp.displayed_name) .. '|' .. tostring(sp.hp) .. '|' .. tostring(sp.portrait) .. '|' .. tostring(sp.image) end
	out('iui.radar.count', #list)
	out('iui.radar.list', table.concat(names, ' ; '))
	if #list > 0 then
		my_screen_radar_Inspect_sprite(1)
		local t = my_radar_sprite or {}
		out('iui.radar.inspect', tostring(t.main_text))
		out('iui.radar.inspect.portrait', tostring(t.portrait) .. ' items=' .. #(t.items or {}) .. ' effects=' .. #(t.timed_effects or {}))
	end
end

function S.iui()
	out('iui.active', tostring(EEex_Active) .. ' modules=' .. type(EEex_Modules))
	for i = 0, 5 do
		local sp = P(i)
		if sp then section('iui.p' .. i, iuiSprite, 'iui.p' .. i, sp) end
	end
	section('iui.res', iuiResources)
	section('iui.radar', iuiRadar)
	out('iui.numChars', try(EEex_Sprite_GetNumCharacters))
	out('iui.globalInt', try(EEex_GameState_GetGlobalInt, 'CHAPTER'))
end

-- --- Bubb's Spell Menu Extended ------------------------------------------------------------------------------

local function spellList()
	local l = {}
	for _, lvl in ipairs(B3Spell_SpellListInfo or {}) do
		local e = {}
		for _, sd in ipairs(lvl) do
			if sd.spellResref then
				e[#e + 1] = string.format('%s:%d:%s:%s:%s:%s', sd.spellResref, sd.spellCastableCount or -1, tostring(sd.spellIcon),
					tostring(sd.spellDisabled), tostring(sd.spellName), tostring(sd.spellType))
			else
				e[#e + 1] = tostring(sd.bam) .. '/' .. tostring(sd.frame) .. '/' .. tostring(sd.disableTint)
			end
		end
		l[#l + 1] = tostring(lvl.infoMode) .. '@' .. tostring(lvl.spellLevel) .. '[' .. table.concat(e, ' ') .. ']'
	end
	return table.concat(l, ' ')
end

function S.select(i)
	pcall(Infinity_OnPortraitLClick, i)
end

function S.spellMenuFill(i)
	local sp = P(i)
	if not sp then return end
	S.select(i)
	local sel = EEex_GameObject_GetSelected()
	out('spm.p' .. i .. '.selected', tostring(sel and sel.m_id == sp.m_id))
	for name, mode in pairs(B3Spell_Modes or {}) do
		if name ~= 'Opcode214' then
			local ok, e = pcall(function()
				B3Spell_Mode = mode
				B3Spell_FillFromMemorized()
			end)
			out('spm.p' .. i .. '.' .. name, ok and spellList() or ('ERR:' .. tostring(e)))
		end
	end
	B3Spell_Mode = B3Spell_Modes and B3Spell_Modes.Normal
end

function S.spellMenuOpen(i)
	-- the mod's own launch path: opens its menu for the selected character
	S.select(i)
	local ok, e = pcall(function() B3Spell_LaunchSpellMenu(B3Spell_Modes.Normal, P(i).m_id) end)
	out('spm.p' .. i .. '.launch', ok and 'ok' or ('ERR:' .. tostring(e)))
	out('spm.p' .. i .. '.open', tostring(Infinity_IsMenuOnStack('B3Spell_Menu')) .. ' open=' .. tostring(B3Spell_IsSpellMenuOpenForSprite and try(B3Spell_IsSpellMenuOpenForSprite, P(i))))
	out('spm.p' .. i .. '.menuList', spellList())
end

function S.spellMenuClose()
	pcall(function() if Infinity_IsMenuOnStack('B3Spell_Menu') then Infinity_PopMenu('B3Spell_Menu') end end)
	out('spm.closed', tostring(not Infinity_IsMenuOnStack('B3Spell_Menu')))
end

function S.spellMenuCast(i)
	-- casts the first memorized spell through the mod (ReadySpell on the button the mod finds): the cursor goes to
	-- the targeting state
	S.select(i)
	B3Spell_Mode = B3Spell_Modes.Normal
	B3Spell_FillFromMemorized()
	local first
	for _, lvl in ipairs(B3Spell_SpellListInfo or {}) do
		for _, sd in ipairs(lvl) do if sd.spellResref and (sd.spellCastableCount or 0) > 0 and not first then first = sd end end
	end
	if not first then out('spm.p' .. i .. '.cast', 'no spell') return end
	local game = EngineGlobals.g_pBaldurChitin.m_pObjectGame
	local before = game.m_nState
	B3Spell_CastResref(first.spellResref, 2)
	out('spm.p' .. i .. '.cast', first.spellResref .. ' state ' .. tostring(before) .. '->' .. tostring(game.m_nState)
		.. ' icon=' .. tostring(try(function() return game.m_iconIndex end)))
	pcall(function() game:SetState(0, false) end)
end

-- --- Artisan's Kitpack / Tactics Remix action bar listeners -------------------------------------------------

local function barButtons()
	local a = EEex_Actionbar_GetArray()
	local t = {}
	for b = 0, 11 do t[#t + 1] = tostring(try(function() return a.m_buttonTypes:get(b) end)) end
	return 'state ' .. tostring(EEex_Actionbar_GetState()) .. ' [' .. table.concat(t, ',') .. ']'
end
S.barButtons = barButtons

function S.actionbarSelect(i)
	S.select(i)
end
function S.actionbarRead(i, tag)
	out('bar.p' .. i .. (tag or ''), barButtons())
end

-- the listeners themselves, called as the engine would, for each state that has a class bar (1-18)
function S.actionbarListeners()
	local fns = {}
	for k, v in pairs(_G) do
		if type(v) == 'function' and type(k) == 'string' and (k:match('^C0.*ActionbarListener$') or k:match('^Mo.*ActionbarListener$')) then fns[#fns + 1] = k end
	end
	table.sort(fns)
	out('bar.listeners', table.concat(fns, ' '))
	local a = EEex_Actionbar_GetArray()
	local saved = {}
	for b = 0, 11 do saved[b] = a.m_buttonTypes:get(b) end
	S.select(0)
	for _, name in ipairs(fns) do
		local res = {}
		for state = 1, 18 do
			for b = 0, 11 do a.m_buttonTypes:set(b, 100) end
			local ok, e = pcall(_G[name], state - 1, state)
			local changed = {}
			for b = 0, 11 do local v = a.m_buttonTypes:get(b) if v ~= 100 then changed[#changed + 1] = b .. '=' .. v end end
			if not ok then changed[#changed + 1] = 'ERR:' .. tostring(e) end
			if #changed > 0 then res[#res + 1] = state .. '{' .. table.concat(changed, ',') .. '}' end
		end
		out('bar.fn.' .. name, table.concat(res, ' '))
	end
	for b = 0, 11 do a.m_buttonTypes:set(b, saved[b]) end
	S.select(0)
end

-- --- BuffBot ---------------------------------------------------------------------------------------------

function S.buffbotTests()
	if not (BfBot and BfBot.Test and BfBot.Test.RunAll) then out('bb.tests', 'absent') return end
	local captured = {}
	local origPrint = BfBot._Print
	BfBot._Print = function(msg) captured[#captured + 1] = tostring(msg) end
	local ok, res = pcall(BfBot.Test.RunAll)
	BfBot._Print = origPrint
	out('bb.runall', tostring(ok) .. ' ' .. tostring(res))
	local pass, fail, warn = 0, 0, 0
	local section = '?'
	local counts = {}
	for _, l in ipairs(captured) do
		local s = l:match('^%s*=== (.-) ===') or l:match('^%[BuffBot%] (.-)$') or l:match('^%s*%-%-%- (.-):')
		if l:match('^%s*%-%-%- ') then
			out('bb.sum.' .. (l:match('%-%-%- (.-):') or '?'), l:match(':%s*(.-)%s*%-%-%-$'))
		end
		local kind, msg = l:match('^%s*(PASS): (.*)$')
		if not kind then kind, msg = l:match('^%s*(FAIL): (.*)$') end
		if not kind then kind, msg = l:match('^%s*(WARN): (.*)$') end
		if kind then
			counts[kind] = (counts[kind] or 0) + 1
			-- numbers in messages (ids, counts) stay: both sides run the same party
			if kind ~= 'PASS' then out('bb.' .. kind .. '.' .. counts[kind], msg) end
		elseif l:match(': PASS$') or l:match(': FAIL$') then
			out('bb.phase.' .. l:gsub('^%s+', ''):gsub(':.*', ''), l:match('(%u+)$'))
		end
	end
	out('bb.counts', 'pass=' .. (counts.PASS or 0) .. ' fail=' .. (counts.FAIL or 0) .. ' warn=' .. (counts.WARN or 0))
	-- the whole PASS list: a test that passes on one side only
	local passes = {}
	for _, l in ipairs(captured) do local m = l:match('^%s*PASS: (.*)$') if m then passes[#passes + 1] = m end end
	out('bb.passes', table.concat(passes, ' | '))
end

function S.buffbotOptions()
	for _, id in ipairs({ 'BuffBot_DarkMode', 'BuffBot_Accent', 'BuffBot_TextSize', 'BuffBot_ItemUseMode', 'BuffBot_RefreshBelow' }) do
		local opt = EEex_Options_Get(id)
		if not opt then out('bb.opt.' .. id, 'nil') else
			local r = try(function() return opt:_read() end)
			out('bb.opt.' .. id, 'read=' .. tostring(r) .. ' get=' .. tostring(try(function() return opt:get() end)) .. ' default=' .. tostring(try(function() return opt:_getDefault() end)))
		end
	end
	-- a set through the option reaches BuffBot's own preference (bridge storage), then is set back
	local opt = EEex_Options_Get('BuffBot_DarkMode')
	if opt then
		local d0 = BfBot.Theme._IsDark()
		local ok, e = pcall(function() opt:set(d0 and 0 or 1) end)
		local d1 = BfBot.Theme._IsDark()
		pcall(function() opt:set(d0 and 1 or 0) end)
		out('bb.opt.setDark', tostring(ok) .. (ok and '' or (' ' .. tostring(e))) .. ' ' .. tostring(d0) .. '->' .. tostring(d1) .. '->' .. tostring(BfBot.Theme._IsDark()))
	end
	out('bb.opt.tab', tostring(BfBot.Theme and BfBot.Theme._registered))
end

function S.buffbotCastStart()
	if not (BfBot and BfBot.Test and BfBot.Test.BuildTestQueue) then out('bb.cast', 'absent') return end
	local origPrint = BfBot._Print
	local captured = {}
	BfBot._Print = function(msg) captured[#captured + 1] = tostring(msg) end
	local q = BfBot.Test.BuildTestQueue()
	BfBot._Print = origPrint
	local l = {}
	for _, e in ipairs(q or {}) do l[#l + 1] = tostring(e.caster or e.casterSlot) .. ':' .. tostring(e.spell or e.resref) .. '>' .. tostring(e.target) end
	out('bb.queue', #(q or {}) .. ' ' .. table.concat(l, ' '))
	if q and #q > 0 then
		local ok, e = pcall(BfBot.Exec.Start, q)
		out('bb.exec.start', tostring(ok) .. ' ' .. tostring(e))
	end
end

function S.buffbotCastEnd()
	out('bb.exec.state', try(function() return BfBot.Exec.GetState and BfBot.Exec.GetState() or BfBot.Exec._state end))
	for i = 0, 5 do
		local sp = P(i)
		if sp then
			local l = {}
			EEex_Utility_IterateCPtrList(sp.m_timedEffectList, function(e)
				local s = rget(e.m_sourceRes)
				if s:match('^SP') then l[#l + 1] = s end
			end)
			local seen, u = {}, {}
			for _, s in ipairs(l) do if not seen[s] then seen[s] = true u[#u + 1] = s end end
			out('bb.buffs.p' .. i, table.concat(sorted(u), ' '))
		end
	end
end

-- --- Tweaks Anthology: tableau of spawned creatures ----------------------------------------------------------

S.TABLEAU = { 'ALHEL', 'DEGARD', 'OHNREDW7', 'AMMAG01', 'OHNLANNE', 'AEEXTORT', 'OHRSGMA2', 'AMCAPT01', 'OHNVGC',
	'SARKIS02', 'ACOLYTE1', 'BHELM', 'OHDCRU01', 'KPCHAP01', 'AMSMUG01', 'GROMG09', 'GORDECK5', 'YOSHI10',
	'C6GOFUS', 'BHNALLA', 'MERONIA', 'HAER10', 'ALAR', 'CHALPC09', 'KELDOR10', 'OHDNEO02', 'AMARCH01', 'REPTHF1',
	'OHBPOL', 'ANOMEN10', 'CGUARD1', 'ARKANISG', 'C6YEAN', 'CHANG01', 'CLCOTI01', 'CECHAL02', 'CERND10', 'DERRICK',
	'VALYG11', 'AMCARRAS', 'JAN10', 'MAEVAR', 'CLTCUT01' }

function S.spawnTableau()
	local p0 = P(0)
	local x, y = p0.m_pos.x, p0.m_pos.y
	for n, r in ipairs(S.TABLEAU) do
		local cx = x - 300 + ((n - 1) % 8) * 70
		local cy = y + 250 + math.floor((n - 1) / 8) * 70
		queue('CreateCreature("' .. r .. '",[' .. cx .. '.' .. cy .. '],0)', p0)
	end
end

function S.tableau()
	local found = {}
	local list = EEex_Sprite_GetAllOfTypeStringInRange(P(0), '[ANYONE]', 2000, false) or {}
	for _, sp in ipairs(list) do
		local r = sp.m_resref:get():upper()
		for _, t in ipairs(S.TABLEAU) do if t == r and not found[r] then found[r] = sp end end
	end
	return found
end

function S.calmTableau()
	-- neutral, no AI script: the creatures stand still, so their effect lists only change through the mods' listeners
	for r, sp in pairs(S.tableau()) do
		pcall(EEex_GameObject_ApplyEffect, sp, { effectID = 72, effectAmount = 128, dwFlags = 0, durationType = 9,
			sourceID = sp.m_id, sourceTarget = sp.m_id })
		for _, sc in ipairs({ 'OVERRIDE', 'CLASS', 'RACE', 'GENERAL', 'DEFAULT', 'AREA', 'SPECIFICS' }) do
			queue('ChangeAIScript("",' .. sc .. ')', sp)
		end
		queue('SetDialog("")', sp)
		queue('ClearActions(Myself)', sp)
	end
end

function S.dumpTableau(tag, full)
	local t = S.tableau()
	local names = {}
	for r in pairs(t) do names[#names + 1] = r end
	table.sort(names)
	out('ta.' .. tag .. '.found', #names .. ' ' .. table.concat(names, ' '))
	for _, r in ipairs(names) do S.dumpSprite('ta.' .. tag .. '.' .. r, t[r], full) end
end

-- TA spells: stoneskin feedback, fireshield, blade barrier, cowled wizard, grease... applied with the engine's own
-- ApplySpellRES (no roll: party members and the tableau, deterministic effects)
S.TA_SPELLS = { 'SPWI408', 'SPWI403', 'SPPR603', 'SPWI101', 'SPWI217', 'SPWI418', 'SPPR305' }
function S.taSpells()
	local sp0 = P(0)
	for _, s in ipairs(S.TA_SPELLS) do queue('ApplySpellRES("' .. s .. '",Myself)', sp0) end
end

-- --- Concentration (TR #60 / TA #2690: CONCENTR.2DA CHECK_MODE EEex-LuaFunction=<fn>) ------------------------

S.conc = { calls = 0, args = {} }
function S.wrapConcentration()
	local tbl = (function()
		local r = {}
		for _, n in ipairs({ 'MoTest', 'gtAlterConcentrationCheck' }) do r[#r + 1] = n end
		return r
	end)()
	for _, n in ipairs(tbl) do
		local orig = _G[n]
		if type(orig) == 'function' and not S['conc_' .. n] then
			S['conc_' .. n] = true
			_G[n] = function(sprite, damageData, ...)
				S.conc.calls = S.conc.calls + 1
				local dt = (function() local ok, v = pcall(function() return damageData.damageTaken end) return ok and v or 'ERR' end)()
				local keys = {}
				pcall(function() for k in pairs(damageData) do keys[#keys + 1] = tostring(k) end end)
				table.sort(keys)
				S.conc.args[#S.conc.args + 1] = n .. '(' .. tostring(try(function() return sprite.m_resref:get() end)) .. ',dt=' .. tostring(dt)
					.. ',keys=' .. table.concat(keys, '/') .. ',type=' .. type(damageData) .. ')'
				local r = orig(sprite, damageData, ...)
				S.conc.args[#S.conc.args] = S.conc.args[#S.conc.args] .. '->' .. tostring(r)
				return r
			end
		end
	end
	out('conc.wrapped', table.concat(tbl, ','))
	-- MoTest reports each check with Infinity_DisplayString: counted too (works whether the extender calls the
	-- function by name at each check or kept the original)
	if not S.dsWrapped then
		S.dsWrapped = true
		local ds = Infinity_DisplayString
		Infinity_DisplayString = function(msg, ...)
			local m = tostring(msg)
			if m:find('spell disruption', 1, true) or m:find('103601', 1, true) then
				S.conc.shown = (S.conc.shown or 0) + 1
				S.conc.lastShown = m
			end
			return ds(msg, ...)
		end
	end
end

function S.concentrationCast()
	-- a tableau mage casts a long spell at itself, then takes damage while casting
	local t = S.tableau()
	S.concCasters = {}
	for _, r in ipairs({ 'AMMAG01', 'ARKANISG', 'MAEVAR', 'JAN10', 'AMCARRAS', 'OHRSGMA2' }) do
		local sp = t[r]
		if sp then
			S.concCasters[#S.concCasters + 1] = sp
			queue('ClearActions(Myself)', sp)
			queue(S.concAction or 'ForceSpellRES("SPWI911",Myself)', sp)
		end
	end
	out('conc.casters', #S.concCasters)
end
function S.concentrationHit()
	for _, sp in ipairs(S.concCasters or {}) do
		local act = try(function() return sp.m_curAction.m_actionID end)
		pcall(EEex_GameObject_ApplyEffect, sp, { effectID = 12, effectAmount = 3, dwFlags = 0, durationType = 1,
			sourceID = P(0).m_id, sourceTarget = sp.m_id })
		S.conc.hitActions = (S.conc.hitActions or '') .. tostring(act) .. ' '
	end
end
-- real combat: hostile gnolls hit the party while each member casts (SpellNoDecRES: interruptible, not memorized)
function S.concFightStart()
	S.conc.calls0 = S.conc.calls
	S.conc.shown0 = S.conc.shown or 0
	for i = 0, 1 do
		for n = 1, 3 do queue('CreateCreatureObjectOffset("GNOLL01",Myself,[' .. (20 * n) .. '.20])', P(i)) end
	end
end
function S.concFightCast()
	for i = 0, 5 do
		local sp = P(i)
		if sp then queue('ClearActions(Myself)', sp) queue('SpellNoDecRES("SPWI911",Myself)', sp) end
	end
	S.conc.partyActs = (S.conc.partyActs or '') .. tostring(try(function() return P(0).m_curAction.m_actionID end)) .. ' '
end
function S.concFightEnd()
	out('conc.fight.partyActs', S.conc.partyActs)
	out('nd.conc.fight.calls', (S.conc.calls - (S.conc.calls0 or 0)) .. ' shown=' .. ((S.conc.shown or 0) - (S.conc.shown0 or 0)))
	out('conc.fight.called', tostring((S.conc.calls - (S.conc.calls0 or 0)) > 0 or ((S.conc.shown or 0) - (S.conc.shown0 or 0)) > 0))
	out('nd.conc.fight.last', tostring(S.conc.lastShown) .. ' | ' .. tostring(S.conc.args[#S.conc.args]))
	local n = 0
	for _, e in ipairs(EEex_Sprite_GetAllOfTypeStringInRange(P(0), '[ENEMY]', 1500, false) or {}) do
		pcall(EEex_GameObject_ApplyEffect, e, { effectID = 13, effectAmount = 0, dwFlags = 4, durationType = 1, sourceID = P(0).m_id, sourceTarget = e.m_id })
		n = n + 1
	end
	out('nd.conc.fight.killed', n)
end

-- SPLPROT stat checks of Artisan's proficiency spells (op326 rows prof_gt_89..: stat 89+ > 0), applied again on
-- a mage (no proficiency) and on fighters, after their stats settled
function S.splprotApply()
	local t = S.tableau()
	-- C0PR#CL (class sets), C0PR#MB (class 10 / 13, then kit check row 379), C0PR#XX (the root the effect
	-- creature casts)
	local spells = { AMMAG01 = 'C0PR#CL', DEGARD = 'C0PR#MB', ALHEL = 'C0PR#XX' }
	for r, spl in pairs(spells) do
		if t[r] then
			-- the proficiency effects removed first (opcode 321 by resource), so only this spell's result shows
			for n = 89, 115 do pcall(EEex_GameObject_ApplyEffect, t[r], { effectID = 321, res = 'C0PR#' .. n, durationType = 1, sourceID = t[r].m_id, sourceTarget = t[r].m_id }) end
			queue('ApplySpellRES("' .. spl .. '",Myself)', t[r])
		end
	end
end
function S.splprotDump()
	local t = S.tableau()
	for _, r in ipairs({ 'AMMAG01', 'DEGARD', 'ALHEL' }) do
		local sp = t[r]
		if sp then
			local l = {}
			EEex_Utility_IterateCPtrList(sp.m_timedEffectList, function(e)
				local s = rget(e.m_sourceRes)
				if s:match('^C0PR') then l[#l + 1] = s .. ':' .. e.m_effectId .. ':' .. e.m_dWFlags .. ':' .. tostring(try(function() return e.m_special end)) end
			end)
			out('splprot.' .. r, table.concat(sorted(l), ' '))
			local pr = {}
			for st = 89, 115 do pr[#pr + 1] = tostring(try(EEex_Sprite_GetStat, sp, st)) end
			out('splprot.' .. r .. '.prof', table.concat(pr, ','))
			out('splprot.' .. r .. '.kit', tostring(try(EEex_Sprite_GetStat, sp, 152)) .. ' class=' .. tostring(try(function() return sp.m_typeAI.m_Class end)))
		end
	end
end

-- where BuffBot's m_nCopyParent lives (EEex: the field exists; written once, the changed bytes found, restored)
function S.copyParent()
	local sp = P(0)
	local ok, v = pcall(function() return sp.m_nCopyParent end)
	out('copyParent.read', tostring(ok) .. ' ' .. tostring(v))
	if not ok or type(v) ~= 'number' then return end
	local base = EEex_UDToPtr(sp)
	local before = {}
	for o = 0, 0x5400 - 1 do before[o] = EEex_ReadU8(base + o) end
	sp.m_nCopyParent = 0x5A5A5A
	local diff = {}
	for o = 0, 0x5400 - 1 do if EEex_ReadU8(base + o) ~= before[o] then diff[#diff + 1] = string.format('0x%x', o) end end
	sp.m_nCopyParent = v
	out('copyParent.offset', table.concat(diff, ','))
end

function S.concentrationReport()
	out('conc.hitActions', S.conc.hitActions)
	out('nd.conc.calls', S.conc.calls)
	out('conc.called', tostring(S.conc.calls > 0 or (S.conc.shown or 0) > 0))
	out('nd.conc.shown', tostring(S.conc.shown) .. ' ' .. tostring(S.conc.lastShown))
	out('nd.conc.args', table.concat(S.conc.args, ' '))
	local fn = (function()
		local ok, v = pcall(function()
			local d = EEex_Resource_Load2DA and EEex_Resource_Load2DA('CONCENTR')
			return d and d:getAtLabels('VALUE', 'CHECK_MODE')
		end)
		return ok and v or ('ERR ' .. tostring(v))
	end)()
	out('conc.2da', tostring(fn))
end

-- --- TA listeners counted: every listener kind TA registers fires under both ---------------------------------

S.count = S.count or {}
local function counter(name) return function() S.count[name] = (S.count[name] or 0) + 1 end end
function S.addCounters()
	pcall(EEex_Opcode_AddListsResolvedListener, counter('listsResolved'))
	pcall(EEex_Action_AddSpriteStartedActionListener, counter('startedAction'))
	pcall(EEex_Sprite_AddQuickListsCheckedListener, counter('quickListsChecked'))
	pcall(EEex_Actionbar_AddListener, counter('actionbar'))
end
function S.reportCounters()
	for _, k in ipairs({ 'listsResolved', 'startedAction', 'quickListsChecked', 'actionbar' }) do
		out('nd.count.' .. k, S.count[k] or 0)
		out('count.' .. k .. '.fired', tostring((S.count[k] or 0) > 0))
	end
end

-- --- Steps ---------------------------------------------------------------------------------------------------

local function unpause() pcall(function() if worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end) end
local function pause() pcall(function() if not worldScreen:CheckIfPaused() then worldScreen:TogglePauseGame(true) end end) end

local function protectParty()
	for i = 0, 5 do
		local sp = P(i)
		if sp then pcall(EEex_GameObject_ApplyEffect, sp, { effectID = 208, effectAmount = 1, durationType = 0, duration = 7200,
			sourceID = sp.m_id, sourceTarget = sp.m_id }) end
	end
end

S.STEPS = {
	{ 1, 'start', function() out('side', S.side) out('io', tostring(hasIO)) protectParty() S.addCounters() S.wrapConcentration() end },
	{ 2, 'party', function() for i = 0, 5 do if P(i) then S.dumpSprite('party.p' .. i, P(i), true) end end end },
	{ 3, 'iui', S.iui },
	{ 4, 'spm.fill', function() for i = 0, 5 do if P(i) then S.spellMenuFill(i) end end end },
	{ 5, 'spm.open', function() S.spellMenuOpen(0) end },
	{ 6, 'spm.close', S.spellMenuClose },
	{ 7, 'spm.cast', function() for i = 0, 5 do if P(i) then S.spellMenuCast(i) end end end },
	{ 8, 'bar.sel0', function() S.actionbarSelect(0) end },
	{ 9, 'bar.read0', function() S.actionbarRead(0) S.actionbarSelect(1) end },
	{ 10, 'bar.read1', function() S.actionbarRead(1) S.actionbarSelect(0) end },
	{ 11, 'bar.fns', S.actionbarListeners },
	{ 12, 'bb.options', S.buffbotOptions },
	{ 13, 'bb.tests', S.buffbotTests },
	{ 14, 'bb.cast', S.buffbotCastStart },
	{ 20, 'ta.spawn', function() unpause() S.spawnTableau() end },
	{ 23, 'ta.calm', S.calmTableau },
	{ 26, 'hold', function() S.holdStatus = 'hold t26' end },
	{ 30, 'ta.dump1', function() S.dumpTableau('t1', true) end },
	{ 31, 'ta.spells', S.taSpells },
	{ 38, 'bb.castEnd', S.buffbotCastEnd },
	{ 40, 'ta.dump2', function() S.dumpTableau('t2', false) S.dumpSprite('party.after.p0', P(0), true) end },
	{ 41, 'conc.cast', S.concentrationCast },
	{ 41.6, 'conc.hit1', S.concentrationHit },
	{ 42.4, 'conc.hit2', S.concentrationHit },
	{ 43.2, 'conc.hit3', S.concentrationHit },
	{ 47, 'conc.cast2', function() S.concAction = 'SpellNoDecRES("SPWI911",Myself)' S.concentrationCast() end },
	{ 47.6, 'conc.hit4', S.concentrationHit },
	{ 48.4, 'conc.hit5', S.concentrationHit },
	{ 52, 'conc.report', S.concentrationReport },
	{ 53, 'splprot.apply', S.splprotApply },
	{ 53.5, 'copyParent', S.copyParent },
	{ 54, 'conc.fight', S.concFightStart },
	{ 56, 'conc.fightCast56', S.concFightCast },
	{ 59, 'conc.fightCast59', S.concFightCast },
	{ 62, 'conc.fightCast62', S.concFightCast },
	{ 65, 'conc.fightCast65', S.concFightCast },
	{ 68, 'conc.fightCast68', S.concFightCast },
	{ 71, 'conc.fightCast71', S.concFightCast },
	{ 74, 'conc.fightCast74', S.concFightCast },
	{ 77, 'conc.fightCast77', S.concFightCast },
	{ 80, 'conc.fightCast80', S.concFightCast },
	{ 83, 'conc.fightCast83', S.concFightCast },
	{ 57, 'splprot.dump', S.splprotDump },
	{ 88, 'conc.fightEnd', S.concFightEnd },
	{ 91, 'end', function() S.reportCounters() out('errors', S.errors) end },
}

local function tickWorld()
	local t = now()
	S.t0 = S.t0 or t
	local el = (t - S.t0) / 1000
	S.done = S.done or {}
	for i, st in ipairs(S.STEPS) do
		if not S.done[i] and el >= st[1] then
			S.done[i] = true
			S.status('step ' .. st[2])
			local menus = {}
			for _, m in ipairs({ 'WORLD_DIALOG', 'WORLD_DIALOG_CONFIRM', 'B3Spell_Menu', 'BFBOT_MAIN', 'WORLD_MESSAGES', 'RG_RADAR', 'OPTIONS', 'WORLD_ACTIONBAR' }) do
				if Infinity_IsMenuOnStack(m) then menus[#menus + 1] = m end
			end
			out('nd.time.' .. st[2], string.format('%.1f s game=%s paused=%s world=%s menus=%s', el,
				tostring(try(function() return EngineGlobals.g_pBaldurChitin.m_pObjectGame.m_worldTime.m_gameTime end)),
				tostring(try(function() return worldScreen:CheckIfPaused() end)), tostring(try(function() return e:GetActiveEngine() == worldScreen end)),
				table.concat(menus, ',')))
			local ok, err = pcall(st[3])
			if not ok then errOut('step.' .. st[2], err) end
			S.flush()
			if i == #S.STEPS then S.status('DONE ' .. #S.lines) end
			if S.holdStatus then S.status(S.holdStatus) S.holdStatus = nil end
			break
		end
	end
	if not S.lastUnpause or t - S.lastUnpause > 2000 then
		S.lastUnpause = t
		unpause()
		-- a dialogue a spawned creature starts would stop the game: closed
		pcall(function()
			if Infinity_IsMenuOnStack('WORLD_DIALOG') or Infinity_IsMenuOnStack('WORLD_DIALOG_CONFIRM') then
				local choices = worldPlayerDialogChoices
				if choices and #choices > 0 and choices[1].marker then worldScreen:OnDialogReplyClick(choices[1].marker) else worldScreen:StepDialog() end
			end
		end)
	end
end

function ST7_Tick()
	if S.state == 'world' then
		local ok, err = pcall(tickWorld)
		if not ok then S.status('tick error ' .. tostring(err)) end
	end
	return false
end

-- --- Boot ----------------------------------------------------------------------------------------------------

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
	local late = S.mainAt and now() - S.mainAt > 5000
	if S.state ~= 'boot' or ((S.startFrames or 0) < 30 and not late) then return end
	S.state = 'loadscreen'
	S.loadAt = now()
	S.status('opening load screen')
	pcall(function() startEngine:OnLoadGameButtonClick() end)
end
local function keyLoad()
	local late = S.loadAt and now() - S.loadAt > 3000
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
	if not Infinity_IsMenuOnStack('ST7_TICK') then Infinity_PushMenu('ST7_TICK') end
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
	pcall(EEex_Menu_LoadFile, 'ST7')
	wrapGlobal('getTitle', tickStart)
	wrapGlobal('getLoadMenuTitle', tickLoad)
	S.mainAt = now()
	S.status('main file loaded')
end) end)
pcall(EEex_GameState_AddInitializedListener, function() pcall(enterWorld, 'initialized') end)
pcall(EEex_Sprite_AddLoadedListener, function() pcall(function()
	if S.state == 'world' and not Infinity_IsMenuOnStack('ST7_TICK') then Infinity_PushMenu('ST7_TICK') end
end) end)
S.status('probe loaded')
]==========]
local fn, err = (loadstring or load)(src, '=st7')
local ok = fn ~= nil
if fn then ok, err = pcall(fn) end
if not ok then print('ST7|STATUS probe load error ' .. tostring(err)) if IEX_Log then pcall(IEX_Log, '[ST7] load error ' .. tostring(err)) end end
