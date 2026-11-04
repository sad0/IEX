-- Pathfinding Redux, native (src/core/pathfinding.cpp): allies walk through one another. Replaces the runtime of
-- the BG Pathfinding Redux mod (override/M_BGREDX.lua, which needs EEex's assembly API) with IEX's own hooks.
--
--   IEX_PathfindingRedux()                         -> state and statistics table
--   IEX_PathfindingRedux({enabled=b, combatOnly=b}) switches (session); returns the same table
--   IEX_Features.pathfindingRedux                   true while the native policy is on
--
-- Settings: Baldur.lua [IEX] 'Pathfinding Redux' (1 on, 0 off; default: on when the mod is installed), the mod's
-- own bg-redux-movement.ini [Movement] OutOfCombatOnly (allies pass only outside combat). The mod's keys:
-- Left Ctrl + Left Shift + F1 switches allied passage for the session, + F2 the out-of-combat-only mode (saved).

if not IEX_PathfindingRedux then return end

local function say(text)
	if Infinity_DisplayString then pcall(Infinity_DisplayString, '[Pathfinding Redux] ' .. text) end
end

local function inWorld()
	local ok, active = pcall(function() return e:GetActiveEngine() == worldScreen end)
	return ok and active and not (Infinity_TextEditHasFocus and Infinity_TextEditHasFocus() ~= 0)
end

local function writeIni(key, value)
	if EEex and EEex.SetINIString then pcall(EEex.SetINIString, '.\\bg-redux-movement.ini', 'Movement', key, value) end
end

if EEex_Key_AddPressedListener and EEex_Key_GetFromName and EEex_Key_IsDown then
	local f1, f2 = EEex_Key_GetFromName('F1'), EEex_Key_GetFromName('F2')
	local ctrl, shift = EEex_Key_GetFromName('Left Ctrl'), EEex_Key_GetFromName('Left Shift')
	EEex_Key_AddPressedListener(function(key)
		if (key ~= f1 and key ~= f2) or not EEex_Key_IsDown(ctrl) or not EEex_Key_IsDown(shift) or not inWorld() then
			return
		end
		local state = IEX_PathfindingRedux()
		if not state.installed then return end
		if key == f1 then
			state = IEX_PathfindingRedux({ enabled = not state.enabled })
			say('allied movement ' .. (state.enabled and 'ON' or 'OFF'))
		else
			state = IEX_PathfindingRedux({ combatOnly = not state.combatOnly })
			writeIni('OutOfCombatOnly', state.combatOnly and '1' or '0')
			say('outside-combat-only allied passage ' .. (state.combatOnly and 'ON' or 'OFF'))
		end
	end)
end
