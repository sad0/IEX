-- IEX camera API (no EEex equivalent): view position and zoom of an area, and a per-frame render event.
--
--   IEX_Camera_AddRenderListener(fn)    fn(area) runs every frame just before `area` is drawn; a camera
--                                       moved there shows in the same frame.
--   IEX_Camera_GetView(area)            -> x, y, w, h: top-left world point and world size of the view
--   IEX_Camera_SetView(area, x, y)      moves the top-left corner (the engine clamps it to the area)
--   IEX_Camera_CenterOn(area, x, y)     centres the view on world point (x, y)
--   IEX_Camera_GetZoom(area)            -> zoom (1 = none, smaller = closer), enabled
--   IEX_Camera_SetZoom(area, zoom)      clamped to IEX_Camera_ZoomLimits(); keeps the view centre
--   IEX_Camera_ZoomLimits([closest, farthest]) -> closest, farthest (engine defaults 0.5, 1.4)

function IEX_Camera_AddRenderListener(fn) IEX_AddListener('AreaRender', fn) end

function IEX_Camera_GetView(area)
	local inf = area.m_cInfinity
	local r = inf.rViewPortZoomed
	return inf.nNewX, inf.nNewY, r.right - r.left, r.bottom - r.top
end

function IEX_Camera_SetView(area, x, y)
	IEX_CameraSetView(area.m_cInfinity, x, y)
end

function IEX_Camera_CenterOn(area, x, y)
	local _, _, w, h = IEX_Camera_GetView(area)
	IEX_CameraSetView(area.m_cInfinity, math.floor(x - w / 2), math.floor(y - h / 2))
end

function IEX_Camera_GetZoom(area)
	local inf = area.m_cInfinity
	return inf.m_fZoom, inf.m_bZoomEnabled ~= 0
end

function IEX_Camera_SetZoom(area, zoom)
	IEX_CameraSetZoom(area.m_cInfinity, zoom)
end

IEX_Camera_ZoomLimits = IEX_CameraZoomLimits
