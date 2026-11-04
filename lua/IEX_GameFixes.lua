-- Engine-version differences that mods made for another game version trip over.

-- 2.7 renamed the UI text lookup t() to getUiString(): UI mods built on the 2.6 UI.MENU show empty labels on 2.7,
-- and 2.7-based ones break on 2.6. Alias whichever is missing (now, and again once the UI Lua is loaded).
local function aliasUiString()
	if t == nil and getUiString ~= nil then t = getUiString end
	if getUiString == nil and t ~= nil then getUiString = t end
end

aliasUiString()
IEX_AddListener('MenuMainFileLoaded', aliasUiString)
IEX_AddListener('MenuMainFileReloaded', aliasUiString)

-- Infinity_DisplayString before a game exists (no CInfGame: start-up, main menu) crashes the engine inside
-- CScreenWorld::DisplayText (2026-10-29: BuffBot / Remote Console start-up messages, access violation reading
-- game+0x7df0). The text then goes to IEX.log and print() instead; with a game it is shown as before.
local function gameExists()
	local ok, game = pcall(function()
		local chitin = EEex_EngineGlobal_CBaldurChitin
		if chitin == nil then return true end  -- no engine view: do not block anything
		return chitin.m_pObjectGame
	end)
	return not ok or game ~= nil
end
local function guardDisplayString()
	local orig = Infinity_DisplayString
	if type(orig) ~= 'function' or IEX_DisplayStringGuarded == orig then return end
	local guarded = function(text, ...)
		if gameExists() then return orig(text, ...) end
		local where = debug and debug.traceback and debug.traceback('', 2):gsub('\n%s*', ' | '):sub(1, 300) or ''
		IEX_Log('Infinity_DisplayString without a game (not shown): ' .. tostring(text) .. ' ' .. where)
		pcall(print, tostring(text))
	end
	Infinity_DisplayString = guarded
	IEX_DisplayStringGuarded = guarded
end
guardDisplayString()
IEX_AddListener('MenuMainFileLoaded', guardDisplayString)
