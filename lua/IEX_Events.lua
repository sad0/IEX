-- IEX event dispatch. The C++ hooks call IEX_Dispatch(event, ...) when an engine event happens.
-- Each listener runs under pcall: an error is logged and never stops the next listener.

IEX_Listeners = IEX_Listeners or {}

-- Returns the listener list of `event`, creating it if needed.
function IEX_GetListeners(event)
	local list = IEX_Listeners[event]
	if not list then
		list = {}
		IEX_Listeners[event] = list
	end
	return list
end

function IEX_AddListener(event, fn)
	if type(fn) ~= 'function' then
		error('IEX_AddListener: listener for ' .. tostring(event) .. ' is not a function', 2)
	end
	local list = IEX_GetListeners(event)
	list[#list + 1] = fn
end

-- Listener errors can repeat every frame (hundreds of events per second): each distinct message is logged the
-- first time, then only at 10, 100, 1000... occurrences, so IEX.log cannot grow without bound.
IEX_ErrorCounts = IEX_ErrorCounts or {}
local function logListenerError(event, i, message)
	local key = event .. '#' .. i .. ': ' .. message
	local n = (IEX_ErrorCounts[key] or 0) + 1
	IEX_ErrorCounts[key] = n
	if n == 1 then
		IEX_Log('Error in ' .. event .. ' listener #' .. i .. ': ' .. message)
	elseif n >= 10 and tostring(n):match('^10*$') then  -- 10, 100, 1000... (Lua 5.2 has no math.log10)
		IEX_Log('Error repeated ' .. n .. ' times in ' .. event .. ' listener #' .. i .. ': ' .. message)
	end
end

-- Calls every listener of `event` with the extra arguments. Returns true if a listener returned a truthy
-- value (used to consume key events). Listeners added during dispatch run from the next event.
function IEX_Dispatch(event, ...)
	if IEX_EnsureMissingTrap then IEX_EnsureMissingTrap() end
	local list = IEX_Listeners[event]
	if not list then return false end
	local consumed = false
	local count = #list
	for i = 1, count do
		local ok, result = pcall(list[i], ...)
		if not ok then
			logListenerError(event, i, tostring(result))
		elseif result then
			consumed = true
		end
	end
	return consumed
end

-- TranslationLoaded, as EEex reports it: right after the language file (L_<lang>.lua) ran. The engine's UI.MENU
-- runs it again in its first Lua block (Infinity_DoFile("L_" .. uiTranslationFile)), which replaces the uiStrings
-- table: strings a mod added before that are gone, so the listeners (that add them again) run after it. Infinity_DoFile
-- is wrapped while UI.MENU is parsed (IEX_MainFileParseStart / End, event_hooks.cpp); when no language file ran
-- during the parse, the event comes at its end, before the MainFileLoaded listeners.
local translationRan = false
local function pack(...) return { n = select('#', ...), ... } end
local unpackAll = table.unpack or unpack
local function wrappedDoFile(doFile)
	return function(name, ...)
		local results = pack(doFile(name, ...))
		if type(name) == 'string' and name:match('^[Ll]_') then
			translationRan = true
			IEX_Dispatch('TranslationLoaded')
		end
		return unpackAll(results, 1, results.n)
	end
end
IEX_AddListener('IEX_MainFileParseStart', function()
	translationRan = false
	if type(Infinity_DoFile) == 'function' and not IEX_DoFileWrapped then
		IEX_DoFileOriginal = Infinity_DoFile
		IEX_DoFileWrapped = wrappedDoFile(Infinity_DoFile)
		Infinity_DoFile = IEX_DoFileWrapped
	end
end)
IEX_AddListener('IEX_MainFileParseEnd', function()
	if Infinity_DoFile == IEX_DoFileWrapped then Infinity_DoFile = IEX_DoFileOriginal end
	IEX_DoFileWrapped = nil
	if not translationRan then IEX_Dispatch('TranslationLoaded') end
end)
