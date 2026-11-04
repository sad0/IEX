-- HD tiles test probe (private test copies only). Command channel: IEX/hd_cmd.lua is run about twice a second,
-- then emptied; HD_Out(...) appends to IEX/hd_out.txt. HD_State() = switch status + draw counters.
local outBuf = {}
function HD_Out(...)
	local t = {}
	for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
	outBuf[#outBuf + 1] = table.concat(t, '\t')
	if IEX_WriteFile then IEX_WriteFile('hd_out.txt', table.concat(outBuf, '\n') .. '\n') end
end

function HD_State()
	local hd, plain, sets = -1, -1, -1
	if IEX_HdTiles_Stats then hd, plain, sets = IEX_HdTiles_Stats() end
	local inst = IEX_NativeHook_Installed and IEX_NativeHook_Installed('hdTiles')
	return ('status=%s installed=%s hdDraws=%d plainDraws=%d sets=%d'):format(tostring(IEX_HdTiles_Status),
		tostring(inst), hd, plain, sets)
end

-- Load the save whose name contains `part` (start screen -> load screen -> game).
function HD_Load(part)
	HD_T = { start = Infinity_GetClockTicks and Infinity_GetClockTicks() }
	local ok, err = pcall(function() startEngine:OnLoadGameButtonClick() end)
	HD_Out('load screen', ok, err)
	HD_PendingLoad = part
end

local cmdTick = 0
if IEX_AddListener and IEX_RunFile and IEX_WriteFile then
	IEX_WriteFile('hd_cmd.lua', '')
	IEX_AddListener('EngineTickDone', function()
		cmdTick = cmdTick + 1
		if cmdTick % 15 ~= 0 then return end
		if HD_PendingLoad and type(gameSaves) == 'table' and gameSaves.files then
			for _, f in ipairs(gameSaves.files) do
				if tostring(f.fileName):find(HD_PendingLoad, 1, true) then
					HD_PendingLoad = nil
					local ok, err = pcall(function() loadScreen:LoadGame(f.fileName) end)
					HD_Out('loading', f.fileName, ok, err)
					break
				end
			end
		end
		IEX_RunFile('hd_cmd.lua')
		IEX_WriteFile('hd_cmd.lua', '')
	end)
end

-- Load timing: ms from HD_Load to the area being visible, and to its 60th drawn frame (pages are demanded while the
-- first frames are drawn). Scroll benchmark: HD_Scroll(ms, dx) moves the view dx world px per drawn frame and
-- reports the drawn frames per second.
local frames = 0
if IEX_AddListener then
	IEX_AddListener('AreaRender', function()
		frames = frames + 1
		local t = HD_T
		if t and t.start and Infinity_GetClockTicks then
			if not t.visible and EEex_Area_GetVisible and EEex_Area_GetVisible() then
				t.visible = Infinity_GetClockTicks(); t.f0 = frames
			elseif t.visible and not t.done and frames - t.f0 >= 60 then
				t.done = Infinity_GetClockTicks()
				HD_Out(('LOADTIME visible=%d ms, +60 frames=%d ms'):format(t.visible - t.start, t.done - t.start))
			end
		end
		local s = HD_ScrollState
		if s then
			local a = EEex_Area_GetVisible()
			local x, y = IEX_Camera_GetView(a)
			IEX_CameraSetView(a.m_cInfinity, x + s.dx, y)
			s.n = s.n + 1
			local now = Infinity_GetClockTicks()
			if s.last and now - s.last > s.worst then s.worst = now - s.last end
			s.last = now
			if Infinity_GetClockTicks() - s.t0 >= s.ms then
				local dt = Infinity_GetClockTicks() - s.t0
				HD_Out(('SCROLL %d frames in %d ms = %.1f fps, longest frame %d ms'):format(s.n, dt, s.n * 1000 / dt, s.worst))
				HD_ScrollState = nil
			end
		end
	end)
end
function HD_Scroll(ms, dx)
	HD_ScrollState = { ms = ms or 5000, dx = dx or 2, n = 0, worst = 0, t0 = Infinity_GetClockTicks() }
end
