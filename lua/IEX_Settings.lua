-- EEex's module switches (EEex_Modules) and the EEex.ini file mods write (src/core/settings.cpp reads it into
-- IEX_Settings.eeexIni, lowercase section / key names).
--
-- Under EEex 1.3.1, EEex_Modules lists its 8 modules with true / false (difftest 2026-10-29: all false in a game
-- whose EEex.ini says [Empty Container Module] Enable=1: EEex.ini is read by EEex's installer, the modules are
-- chosen at install). IEX reads EEex.ini at every start instead: a module IEX has is on when EEex.ini enables it.
-- A module IEX does not have is reported in IEX.log when EEex.ini enables it.

EEex_Modules = EEex_Modules or {}
local MODULES = {
	{ 'B3AttackInfo', 'attack info module' },
	{ 'B3EffMen', 'effect menu module' },
	{ 'B3EmptyContainer', 'empty container module' },
	{ 'B3Hotkey', 'hotkey module' },
	{ 'B3Invis', 'invisibility module' },
	{ 'B3Scale', 'scale module' },
	{ 'B3TimeStep', 'time step module' },
	{ 'B3Timer', 'timer module' },
}
-- Modules IEX implements (lua/IEX_Modules.lua): name -> true.
IEX_ModulesAvailableNames = { B3EmptyContainer = true, B3TimeStep = true, B3Timer = true, B3EffMen = true,
	B3AttackInfo = true }
IEX_ModulesAvailable = IEX_ModulesAvailable or {}

local function iniEnabled(section)
	local ini = IEX_Settings and IEX_Settings.eeexIni
	local s = type(ini) == 'table' and ini[section]
	return type(s) == 'table' and tonumber(s.enable) == 1
end

for _, m in ipairs(MODULES) do
	local name, section = m[1], m[2]
	if EEex_Modules[name] == nil then EEex_Modules[name] = false end
	-- the modules IEX has set their own entry when they start (IEX_Modules.lua)
	if iniEnabled(section) and not IEX_ModulesAvailableNames[name] and IEX_Log then
		IEX_Log('EEex.ini enables the ' .. section .. ' (' .. name .. '): not available in IEX, ignored')
	end
end
