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
--   SetPrivateProfileString('IEX','Show FPS','1')              (default 0: frame counter at the top right of the
--                                                               world screen, menu IEX_FPS in ui/IEXOPT.menu)
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

-- 'Show FPS': frames drawn per second, counted by the menu IEX_FPS (its first label's enabled check runs once per
-- drawn frame, so the count is the frames the player sees, interpolated frames included). The text is rebuilt every
-- half second; the menu is on the stack only while the option is on.
IEX_ShowFps = IEX_ShowFps or { on = false, frames = 0, text = '' }
local FPS_WINDOW = 500  -- ms per refresh

local function fpsInWorld()
	return worldScreen ~= nil and e:GetActiveEngine() == worldScreen
end

local function fpsPlace()
	-- top right, left of the portrait column (also clear of SadoEE's top-center counter)
	local w = Infinity_GetScreenSize()
	Infinity_SetArea('IEX_FPS_TEXT', math.floor(w - 190), 4, 90, 22)
end

function IEX_ShowFpsTick()
	local F = IEX_ShowFps
	local now = Infinity_GetClockTicks()
	F.frames = F.frames + 1
	if not F.start or now < F.start then F.start, F.frames = now, 0 return false end
	local dt = now - F.start
	if dt >= FPS_WINDOW then
		F.fps = F.frames * 1000 / dt
		F.text = string.format('%d FPS', math.floor(F.fps + 0.5))
		F.start, F.frames = now, 0
		pcall(fpsPlace)
	end
	return false
end

function IEX_ShowFpsVisible()
	return IEX_ShowFps.on and IEX_ShowFps.text ~= '' and fpsInWorld()
end

-- Keeps IEX_FPS on the stack while the option is on and the world screen is up (the engine rebuilds the menu stack
-- on loads and screen changes), pops it when the option is turned off. The menu comes with IEXOPT.menu.
function IEX_ShowFpsUpdate()
	local F = IEX_ShowFps
	pcall(function()
		if not (Infinity_IsMenuOnStack and EEex_Menu_Find and EEex_Menu_Find('IEX_FPS')) then return end
		local onStack = Infinity_IsMenuOnStack('IEX_FPS')
		if F.on and not onStack and fpsInWorld() then
			F.start, F.frames, F.text = nil, 0, ''
			Infinity_PushMenu('IEX_FPS')
		elseif not F.on and onStack then
			Infinity_PopMenu('IEX_FPS')
		end
	end)
end

if not IEX_ShowFps.listenersAdded then
	IEX_ShowFps.listenersAdded = true
	IEX_AddListener('EngineTickDone', function() if IEX_ShowFps.on then IEX_ShowFpsUpdate() end end)
end

function IEX_ApplyFrameSettings()
	-- Mods with many effect list listeners allocate tens of MB of short-lived Lua data per second (Tweaks Anthology: 30 MB/s
	-- with 20 creatures). Collecting less often costs some memory and about 10% less time in those listeners (tools/speedtest bench).
	collectgarbage('setpause', math.max(100, setting('IEX', 'Lua GC Pause', 400)))
	IEX_ShowFps.on = setting('IEX', 'Show FPS', 0) ~= 0
	IEX_ShowFpsUpdate()
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
	IEX_Log(string.format('Frame settings: uncap=%s vsync=%s limit=%s/%d busyWait=%s iexRate=%d -> %d fps, interpolation=%s, keep game speed=%s, show fps=%s',
		tostring(s.uncap), tostring(s.vsync), tostring(s.limitOn), s.limit, tostring(s.busyWait), s.iexRate,
		s.applied, tostring(s.interpolation), tostring(s.keepSpeed), tostring(IEX_ShowFps.on)))
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
