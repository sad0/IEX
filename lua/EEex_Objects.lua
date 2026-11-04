-- EEex-compatible object helpers built on IEX engine objects.

-- The CBaldurChitin singleton (engine root object), also reachable as EngineGlobals.g_pBaldurChitin.
EEex_EngineGlobal_CBaldurChitin = IEX_EngineGlobal('g_pBaldurChitin', 'CBaldurChitin')
EngineGlobals = EngineGlobals or {}
EngineGlobals.g_pBaldurChitin = EEex_EngineGlobal_CBaldurChitin
-- The UI mouse capture (capture.item = the item being pressed / dragged, nil when none).
EngineGlobals.capture = IEX_EngineGlobalAt('IEX_UiCapture', 'uiCapture')

-- Address <-> object.
EEex_PtrToUD = IEX_ToObject
EEex_UDToPtr = IEX_Address

-- Same engine object (address compare).
function EEex_UDEqual(a, b)
	return IEX_Address(a) == IEX_Address(b)
end

-- Bit operations (Lua 5.2 bit32 library, 32-bit results like the engine fields they are used on).
EEex_BAnd = bit32.band
EEex_BOr = bit32.bor
EEex_BXor = bit32.bxor
-- EEex_BNot gives a signed 32-bit result (EEex_BNot(0) == -1); the other operations return bit32's unsigned values.
function EEex_BNot(value)
	local r = bit32.bnot(value)
	if r >= 0x80000000 then r = r - 0x100000000 end
	return r
end
EEex_LShift = bit32.lshift
EEex_RShift = bit32.rshift

-- Walks an engine CPtrList; fn(data) returning true stops.
EEex_Utility_IterateCPtrList = IEX_IterateList

-- Object classes by CGameObject.m_objectType.
IEX_ObjectTypes = IEX_ObjectTypes or {
	[0x11] = 'CGameContainer',
	[0x21] = 'CGameDoor',
	[0x31] = 'CGameSprite',
	[0x41] = 'CGameTrigger',
}

-- Re-types a game object to its real class (CGameSprite for creatures...); unknown classes stay as they are.
function EEex_GameObject_CastUserType(object)
	if not object then return nil end
	local class = IEX_ObjectTypes[object.m_objectType]
	if not class or IEX_TypeName(object) == class then return object end
	return IEX_ToObject(IEX_Address(object), class)
end

-- The area currently shown on screen, or nil (no game loaded).
function EEex_Area_GetVisible()
	local game = EEex_EngineGlobal_CBaldurChitin.m_pObjectGame
	if not game then return nil end
	return game.m_gameAreas:get(game.m_visibleArea)
end

-- The mouse in screen coordinates (Infinity_GetScreenSize space), as EEex returns it: the engine's own pointer
-- (CChitin m_ptPointer, set from every mouse motion event). Infinity_GetMousePosition is another value (it differed
-- from EEex_Menu_GetMousePos under EEex, difftest 2026-10-29). Fallback when the field is unknown.
function EEex_Menu_GetMousePos()
	local ok, x, y = pcall(function()
		local p = EEex_EngineGlobal_CBaldurChitin.m_ptPointer
		return p.x, p.y
	end)
	if ok and type(x) == 'number' then return x, y end
	return Infinity_GetMousePosition()
end

-- Game-world point of the visible area -> UI coordinates (same space as EEex_Menu_GetMousePos), using the
-- camera's top-left world point and the world size of the view (zoom included). Nil without a visible area.
function EEex_Menu_TranslateXYFromGame(x, y)
	local area = EEex_Area_GetVisible()
	if not area then return nil end
	local inf = area.m_cInfinity
	local r = inf.rViewPortZoomed
	local w, h = r.right - r.left, r.bottom - r.top
	if w <= 0 or h <= 0 then return nil end
	local sw, sh = Infinity_GetScreenSize()
	return math.floor((x - inf.nNewX) * sw / w + 0.5), math.floor((y - inf.nNewY) * sh / h + 0.5)
end

function EEex_Menu_IsCursorWithinRect(x, y, w, h)
	local mx, my = Infinity_GetMousePosition()
	return mx >= x and mx < x + w and my >= y and my < y + h
end
