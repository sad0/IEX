-- EEex-compatible menu and keyboard functions.

-- Loads <name>.MENU and adds its menus to the UI. Call it from a MainFileLoaded / MainFileReloaded listener.
function EEex_Menu_LoadFile(name)
	if not IEX_MenuLoadFile(name) then
		IEX_Log('EEex_Menu_LoadFile: ' .. tostring(name) .. '.MENU not found')
	end
end

-- SDL keycode from an SDL key name ('F12', 'Left Alt', 'a').
EEex_Key_GetFromName = IEX_KeyFromName

-- True while the key (SDL keycode) is held down, nil otherwise (EEex gives nil, not false).
function EEex_Key_IsDown(key)
	return IEX_KeyIsDown(key) or nil
end

-- SDL2 event type numbers (SDL_events.h), for EEex_Key_Hook_AfterEventsPoll handlers.
SDL_EventType = SDL_EventType or {
	SDL_KEYDOWN = 0x300, SDL_KEYUP = 0x301, SDL_TEXTINPUT = 0x303,
	SDL_MOUSEMOTION = 0x400, SDL_MOUSEBUTTONDOWN = 0x401, SDL_MOUSEBUTTONUP = 0x402, SDL_MOUSEWHEEL = 0x403,
}

-- Called by IEX for every SDL event the engine polls; returning true drops the event. Mods chain it.
EEex_Key_Hook_AfterEventsPoll = EEex_Key_Hook_AfterEventsPoll or function(event) return false end
