-- HD area tiles (native switch "hdTiles", src/core/hd_tiles.cpp, docs/HD_TILES.md).
--
-- A PVRZ-based TIS whose header tile size (+0x14) is 128, 256 or 512 has 2x, 4x or 8x PVRZ pages (the public
-- InfinityEngine-Enhancer convention): each 64x64 world tile is drawn from 128/256/512 texels. ARE / WED stay 1x.
-- A TIS with 64 (every vanilla TIS) is drawn by the engine exactly as without IEX, so the switch is on by default.
--
--   Baldur.lua: SetPrivateProfileString('IEX','HD Area Tiles','0') turns it off (read at start).
--   IEX_HdTiles_Status    'off' / 'on' / reason the switch could not be installed
--   IEX_HdTiles_Stats()   -> HD tile draws, other tile draws (since start), tile sets seen

IEX_HdTiles_Status = 'off'

local function apply()
	local ok, value = pcall(Infinity_GetINIValue, 'IEX', 'HD Area Tiles', 1)
	if ok and tonumber(value) == 0 then
		IEX_HdTiles_Status = 'off (Baldur.lua)'
		IEX_Log('[hdTiles] off (Baldur.lua IEX / HD Area Tiles = 0)')
		return
	end
	if not IEX_NativeHook_Enable then
		IEX_HdTiles_Status = 'no native hook API'
		return
	end
	local on, why = IEX_NativeHook_Enable('hdTiles')
	IEX_HdTiles_Status = on and 'on' or tostring(why)
	IEX_Log('[hdTiles] ' .. (on and 'switch on' or ('not installed: ' .. tostring(why))))
end

-- Infinity_GetINIValue does not exist yet when IEX_Main.lua runs: read the setting once the UI is up.
if Infinity_GetINIValue then
	apply()
elseif EEex_Menu_AddMainFileLoadedListener then
	local pending = true
	EEex_Menu_AddMainFileLoadedListener(function()
		if not pending then return end
		pending = false
		apply()
	end)
end
