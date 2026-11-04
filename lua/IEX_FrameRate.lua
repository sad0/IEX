-- Render frame rate and game speed (docs/FRAMERATE.md).
--
-- EEex's 'Uncap FPS' settings (Baldur.lua [EEex], same keys, same defaults, same observable behaviour, measured
-- 2026-10-30 with tools/speedtest): the logic keeps "Maximum Frame Rate" (CChitin::TIMER_UPDATES_PER_SECOND,
-- EEex's "AI Speed") ticks per second, and frames are drawn at their own rate:
--   'Uncap FPS'                      1 (default): frames decoupled from ticks; 0: the engine's one frame per tick
--   'VSync Enabled'                  1 (default): frames at the monitor refresh rate; 0: as fast as possible
--   'Uncap FPS Limit Enabled' / 'Uncap FPS Limit'   0 / 144: cap on the frame rate
--   'Uncap FPS Busy Wait Threshold'  1: the last ms of a wait is spun (frame pacing precision)
--   'Uncap FPS Fullscreen VRR'       0: stored and shown; IEX does not change anything for it yet
-- IEX adds motion interpolation in the frames between ticks (creatures and projectiles glide instead of moving
-- 15 times a second) and its own override:
--   SetPrivateProfileString('IEX','Frame Rate','144')          (-1 = monitor rate; 0 = use the EEex settings)
--   SetPrivateProfileString('IEX','Frame Interpolation','0')   (default 1)
--   SetPrivateProfileString('IEX','Keep Game Speed','0')       (default 1, see lua/EEex_TA.lua EEex_CChitin)
--
--   IEX_SetFrameRate(n)   n frames per second; -1 = monitor refresh rate; 0 = one frame per tick
--   IEX_GetFrameRate()    -> requested rate, logic ticks/s, rate in use, mod floor, frames skipped, swap interval
--   IEX_GetRenderRate()   -> frames drawn and logic ticks run during the last second (engine counters)
--   IEX_SetFrameRateFloor(n), IEX_SetVSync(-1|0|1), IEX_SetBusyWait(ms)
--   IEX_SetFrameInterpolation(on), IEX_GetFrameInterpolation(), IEX_TraceFrameInterpolation(id, frames)
--   IEX_ApplyFrameSettings()   re-reads the Baldur.lua settings above (the options screen calls it)

local function setting(section, key, default)
	local ok, value = pcall(Infinity_GetINIValue, section, key, default)
	return ok and tonumber(value) or default
end

IEX_FrameSettings = IEX_FrameSettings or {}

function IEX_ApplyFrameSettings()
	if not IEX_SetFrameRate then return end
	local s = IEX_FrameSettings
	s.iexRate = setting('IEX', 'Frame Rate', 0)
	s.uncap = setting('EEex', 'Uncap FPS', 1) ~= 0
	s.vsync = setting('EEex', 'VSync Enabled', 1) ~= 0
	s.limitOn = setting('EEex', 'Uncap FPS Limit Enabled', 0) ~= 0
	s.limit = setting('EEex', 'Uncap FPS Limit', 144)
	s.busyWait = setting('EEex', 'Uncap FPS Busy Wait Threshold', 1)
	s.interpolation = setting('IEX', 'Frame Interpolation', 1) ~= 0
	s.keepSpeed = setting('IEX', 'Keep Game Speed', 1) ~= 0
	local rate, cap = 0, nil
	if s.iexRate ~= 0 then
		rate = s.iexRate
	elseif s.uncap then
		local limit = s.limitOn and s.limit > 0 and s.limit or nil
		if s.vsync then
			rate, cap = -1, limit  -- the window display's refresh rate (followed), at most the limit
		else
			rate = limit or 1000  -- no vsync, no limit: as fast as possible (capped at 1000)
		end
	end
	s.applied = IEX_SetFrameRate(rate, cap)
	if IEX_SetVSync then IEX_SetVSync(s.uncap and (s.vsync and 1 or 0) or -1) end
	if IEX_SetBusyWait then IEX_SetBusyWait(s.busyWait) end
	if IEX_SetFrameInterpolation then IEX_SetFrameInterpolation(s.interpolation) end
	if IEX_SetKeepGameSpeed then IEX_SetKeepGameSpeed(s.keepSpeed) end
	IEX_Log(string.format('Frame settings: uncap=%s vsync=%s limit=%s/%d busyWait=%s iexRate=%d -> %d fps, interpolation=%s, keep game speed=%s',
		tostring(s.uncap), tostring(s.vsync), tostring(s.limitOn), s.limit, tostring(s.busyWait), s.iexRate,
		s.applied, tostring(s.interpolation), tostring(s.keepSpeed)))
end

-- Infinity_GetINIValue does not exist yet when IEX_Main.lua runs: read the settings once the UI is up.
if Infinity_GetINIValue then
	IEX_ApplyFrameSettings()
else
	local pending = true
	EEex_Menu_AddMainFileLoadedListener(function()
		if not pending then return end
		pending = false
		IEX_ApplyFrameSettings()
	end)
end
