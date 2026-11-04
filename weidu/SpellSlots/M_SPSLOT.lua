-- SpellSlots: the engine's class spell lists (chargen, level-up, dual-class, priests' automatic spells) read
-- SPWI/SPPR slots 01-99 instead of 01-50. Runs once at UI load.
--   IEX:  native hook point "spellSlots99" (Windows + Linux 2.7.3).
--   EEex: Windows byte patch of the bound test in CRuleTables::GetMageSpell / GetPriestSpell
--         (`cmp r9d, 0x31; ja` -> `cmp r9d, 0x62`), only when the game's bytes are found unchanged.
-- SpellSlots_Status tells what happened (shown in the log / Lua console).

SpellSlots_Status = 'not applied'

-- Address of the 0x31 byte per Windows build (BGEE, BG2EE, EET share the executable layout per version).
local SPSL_SITES = {
	{ build = '2.7.3', mage = 0x140241EDB, priest = 0x1402453DB },
	{ build = '2.6.6', mage = 0x140241C7B, priest = 0x14024517B },
}

local function spslLog(msg)
	SpellSlots_Status = msg
	if IEX_Log then IEX_Log('[SpellSlots] ' .. msg) else print('[SpellSlots] ' .. msg) end
end

-- 41 83 F9 <bound> 77: cmp r9d, <bound>; ja
local function spslBoundAt(byteAddr)
	local ok, b = pcall(function()
		if EEex_ReadU8(byteAddr - 3) ~= 0x41 or EEex_ReadU8(byteAddr - 2) ~= 0x83 or EEex_ReadU8(byteAddr - 1) ~= 0xF9
			or EEex_ReadU8(byteAddr + 1) ~= 0x77 then
			return nil
		end
		return EEex_ReadU8(byteAddr)
	end)
	return ok and b or nil
end

local function spslApplyEEex()
	if not (EEex_ReadU8 and EEex_WriteU8) then return false, 'no EEex memory API' end
	for _, s in ipairs(SPSL_SITES) do
		local m, p = spslBoundAt(s.mage), spslBoundAt(s.priest)
		if m == 0x62 and p == 0x62 then return true, 'already applied (' .. s.build .. ')' end
		if m == 0x31 and p == 0x31 then
			if EEex_DisableCodeProtection then EEex_DisableCodeProtection() end
			EEex_WriteU8(s.mage, 0x62)
			EEex_WriteU8(s.priest, 0x62)
			if EEex_EnableCodeProtection then EEex_EnableCodeProtection() end
			return true, 'applied through EEex (' .. s.build .. ')'
		end
	end
	return false, 'unknown game build: nothing changed'
end

local function spslApply()
	if IEX_NativeHook_Enable then
		local ok, why = IEX_NativeHook_Enable('spellSlots99')
		if ok then return true, 'applied through IEX' end
		return false, 'IEX: ' .. tostring(why)
	end
	return spslApplyEEex()
end

if not SpellSlots_Applied then
	local ok, msg = spslApply()
	SpellSlots_Applied = ok
	spslLog(msg)
end
