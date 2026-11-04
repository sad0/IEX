-- EEex-compatible UI menu objects: find a menu, read and change its items, swap the Lua functions stored in
-- menus, inject template instances into existing menus, item areas and cursor tests, per-item render listeners.
-- Engine side: lua_ui.cpp (findMenu, registry access, drawItem hook); layouts: uiMenu / uiItem in the engine
-- description. Item lists are singly linked (menu.items, item.next).

-- Item kinds stored in uiItem.type, one per .menu item keyword (set by the engine's .menu parser when it closes
-- an item; checked in game against every named item of the loaded UI). No keyword produces kind 8.
uiItemType = uiItemType or {
	ITEM_LABEL = 0, ITEM_TEXT = 1, ITEM_BUTTON = 2, ITEM_LIST = 3, ITEM_EDIT = 4, ITEM_MOVIE = 5,
	ITEM_SLIDER = 6, ITEM_HANDLE = 7, ITEM_SLOT = 9, ITEM_MAP = 10, ITEM_TEMPLATE = 11,
}

-- The engine menu (uiMenu object) named `name`, or nil. panel and state select among menus sharing a name.
function EEex_Menu_Find(name, panel, state)
	return IEX_MenuFind(name, panel or 0, state or 0)
end

-- The item named `name` (any loaded menu), or nil. Names are unique across menus (engine table nameToItem).
function EEex_Menu_GetItem(name)
	local p = type(nameToItem) == 'table' and nameToItem[name]
	if not p then return nil end
	return IEX_PointerToObject(p, 'uiItem')
end

-- Calls fn(item) for each item of `menu`; fn returning true stops the walk (and returns that item).
local function eachItem(menu, fn)
	local item = menu and menu.items
	while item do
		if fn(item) then return item end
		item = item.next
	end
end
IEX_MenuEachItem = eachItem

---------------------------------------------------------------------------------------------------
-- Lua functions of menus and items (onOpen, onClose, enabled...): the engine stores each compiled function in
-- the Lua registry and keeps its reference number in the menu/item (reference_* fields, IEX_LuaRef objects).
---------------------------------------------------------------------------------------------------

local function refNumber(r)
	if type(r) == 'number' then return r end
	if type(r) == 'userdata' then return r.ref end
	return nil
end

function EEex_Menu_GetItemFunction(r)
	local n = refNumber(r)
	if not n or n == 0 then return nil end
	return rawget(IEX_LuaRegistry(), n)
end

-- Replaces the function behind reference `r`. A field without a function yet (reference 0) gets a new registry
-- slot (after the last used one, like luaL_ref when its free list is empty).
function EEex_Menu_SetItemFunction(r, fn)
	local reg = IEX_LuaRegistry()
	local n = refNumber(r)
	if n and n ~= 0 then
		rawset(reg, n, fn)
		return
	end
	if type(r) ~= 'userdata' then error('EEex_Menu_SetItemFunction: menu reference expected', 2) end
	n = rawlen(reg) + 1
	rawset(reg, n, fn)
	r.ref = n
end

---------------------------------------------------------------------------------------------------
-- Areas. Item areas are relative to their menu; a menu is placed on the screen by its alignment (left/right/
-- center, top/bottom/center) and size, then moved by its offset (same rule as the engine's drawMenu).
---------------------------------------------------------------------------------------------------

local function idiv(a, b) return a >= 0 and math.floor(a / b) or -math.floor(-a / b) end  -- C integer division

local function menuOrigin(menu)
	local sw, sh = Infinity_GetScreenSize()
	local w, h = menu.width, menu.height
	local ah, av = menu.alignHorizontal, menu.alignVertical
	local x = ah == 2 and idiv(sw, 2) - idiv(w, 2) or ah == 1 and sw - w or 0
	local y = av == 2 and idiv(sh, 2) - idiv(h, 2) or av == 1 and sh - h or 0
	return x + menu.offset.x, y + menu.offset.y, w, h
end

-- x, y, w, h of a menu object on the screen.
function EEex_Menu_GetUIMenuArea(menu)
	return menuOrigin(menu)
end

-- x, y, w, h on the screen of the menu named `menuName`; nothing (no value, like EEex) when there is none.
function EEex_Menu_GetArea(menuName)
	local menu = EEex_Menu_Find(menuName)
	if not menu then return end
	return menuOrigin(menu)
end

-- x, y, w, h of an item object on the screen.
function EEex_Menu_GetUIItemArea(item)
	local menu = item.menu
	local mx, my = 0, 0
	if menu then mx, my = menuOrigin(menu) end
	local a = item.area
	return mx + a.x, my + a.y, a.w, a.h
end

-- x, y, w, h on the screen of the item named `itemName`, or nil.
function EEex_Menu_GetItemArea(itemName)
	local item = EEex_Menu_GetItem(itemName)
	if not item then return nil end
	return EEex_Menu_GetUIItemArea(item)
end

if uiItem then
	function uiItem.getArea(self) return EEex_Menu_GetUIItemArea(self) end
end

local function nameOf(item)
	local n = item.name
	return n and n:get() or nil
end

-- True when the cursor is over the item `itemName` of menu `menuName`.
function EEex_Menu_IsCursorWithin(menuName, itemName)
	local menu = EEex_Menu_Find(menuName)
	local item = menu and eachItem(menu, function(i) return nameOf(i) == itemName end)
	if not item then return false end
	local x, y, w, h = EEex_Menu_GetUIItemArea(item)
	return EEex_Menu_IsCursorWithinRect(x, y, w, h)
end

---------------------------------------------------------------------------------------------------
-- Templates. The engine creates template instances (Infinity_InstanceAnimation) in the template's own menu;
-- an injected instance is then moved to the end of the target menu's item list.
---------------------------------------------------------------------------------------------------

local function lastItem(menu)
	local last
	eachItem(menu, function(i) last = i end)
	return last
end

local function moveToMenu(item, from, to)
	local prev
	eachItem(from, function(i)
		if i.next == item then prev = i return true end
	end)
	if prev then prev.next = item.next elseif from.items == item then from.items = item.next end
	item.next = nil
	local last = lastItem(to)
	if last then last.next = item else to.items = item end
	item.menu = to
end

-- Creates instance `instanceId` of template item `templateName` inside menu `menuName`, at x, y (relative to the
-- menu), sized w, h (the template's size when both are 0 or nil). Returns the new item.
function EEex_Menu_InjectTemplateInstance(menuName, templateName, instanceId, x, y, w, h)
	local menu = EEex_Menu_Find(menuName)
	if not menu then error('EEex_Menu_InjectTemplateInstance: no menu ' .. tostring(menuName), 2) end
	local template = EEex_Menu_GetItem(templateName)
	if not template then error('EEex_Menu_InjectTemplateInstance: no template ' .. tostring(templateName), 2) end
	local from = template.menu
	local before = lastItem(from)
	local savedId = currentAnimationID
	currentAnimationID = instanceId or 0
	Infinity_InstanceAnimation(templateName, '', x or 0, y or 0, w or 0, h or 0, '', 0)
	currentAnimationID = savedId
	local item = lastItem(from)
	if not item or item == before then
		error('EEex_Menu_InjectTemplateInstance: the engine did not create ' .. tostring(templateName), 2)
	end
	if from ~= menu then moveToMenu(item, from, menu) end
	return item
end

-- Changes the area of instance `instanceId` of `templateName` in menu `menuName`; nil keeps a value.
function EEex_Menu_SetTemplateArea(menuName, templateName, instanceId, x, y, w, h)
	local menu = EEex_Menu_Find(menuName)
	if not menu then return end
	eachItem(menu, function(item)
		local t = item.templateName
		if t and item.instanceId == instanceId and t:get() == templateName then
			local a = item.area
			if x then a.x = x end
			if y then a.y = y end
			if w then a.w = w end
			if h then a.h = h end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Text of items, and the item render listeners.
---------------------------------------------------------------------------------------------------

-- The value of a .menu value object as text: strref, string or Lua expression.
function IEX_MenuVariantText(v)
	if not v then return nil end
	local kind = v.type
	if kind == 0 then return Infinity_FetchString(v.value) end
	if kind == 2 then return v.string:get() end
	local fn = rawget(IEX_LuaRegistry(), v.value)
	if type(fn) ~= 'function' then return nil end
	local ok, result = pcall(fn)
	if ok and result ~= nil then return tostring(result) end
	return nil
end

-- The first item of `menu` whose text (as shown, or its uiStrings key) is `text`.
function EEex_Options_Private_FindItemByText(menu, text)
	return eachItem(menu, function(item)
		local s = IEX_MenuVariantText(item.text.text)
		if s == nil then return false end
		if s == text then return true end
		local lookup = getUiString or t
		if lookup then
			local ok, translated = pcall(lookup, s)
			if ok and translated == text then return true end
		end
		return false
	end)
end

-- fn(item) runs right before each draw of the items named `itemName` (one listener per name; a new one replaces it).
-- As under EEex, the engine hook calls the global EEex_Menu_Hook_OnBeforeUIItemRender(item), which looks the item's
-- name up in EEex_Menu_BeforeUIItemRenderListeners: a mod may replace either (BG2 Narrator replaces the hook).
IEX_ItemRenderListeners = IEX_ItemRenderListeners or {}
EEex_Menu_BeforeUIItemRenderListeners = IEX_ItemRenderListeners
function EEex_Menu_AddBeforeUIItemRenderListener(itemName, fn)
	EEex_Menu_BeforeUIItemRenderListeners[itemName] = fn
	IEX_MenuWatchItemRender(itemName, true)
end

function EEex_Menu_Hook_OnBeforeUIItemRender(item)
	local fn = EEex_Menu_BeforeUIItemRenderListeners[nameOf(item)]
	if fn then fn(item) end
end

if not IEX_ItemRenderDispatchAdded then
	IEX_ItemRenderDispatchAdded = true
	IEX_AddListener('BeforeUIItemRender', function(item)
		local hook = EEex_Menu_Hook_OnBeforeUIItemRender
		if type(hook) == 'function' then hook(item) end
	end)
end

-- fn(list, item, window, clip, alpha, menu) runs before each row of the lists named `listName` is drawn (item: the
-- row's copy of its template item, so it can be edited for this row; window / clip: SDL_Rect pointers; menu: the
-- list's menu). Several listeners per name. The engine hook (src/core/lua_ui.cpp, the drawItem call of
-- RenderListCallback) calls the global EEex_Menu_LuaHook_BeforeListRenderingItem, which mods may replace.
EEex_Menu_BeforeListRendersItemListeners = EEex_Menu_BeforeListRendersItemListeners or {}
function EEex_Menu_AddBeforeListRendersItemListener(listName, fn)
	local list = EEex_Menu_BeforeListRendersItemListeners[listName]
	if not list then
		list = {}
		EEex_Menu_BeforeListRendersItemListeners[listName] = list
	end
	list[#list + 1] = fn
end

function EEex_Menu_LuaHook_BeforeListRenderingItem(list, item, window, clip, alpha, menu)
	local listeners = EEex_Menu_BeforeListRendersItemListeners[nameOf(list)]
	if not listeners then return end
	for _, fn in ipairs(listeners) do fn(list, item, window, clip, alpha, menu) end
end

function IEX_ListRenderingItem(list, item, window, clip, alpha, menu)
	local hook = EEex_Menu_LuaHook_BeforeListRenderingItem
	if type(hook) ~= 'function' then return end
	local ok, err = pcall(hook, list, item, window, clip, alpha, menu)
	if not ok then
		local msg = tostring(err)
		IEX_ListRenderErrors = IEX_ListRenderErrors or {}
		if not IEX_ListRenderErrors[msg] then
			IEX_ListRenderErrors[msg] = true
			IEX_Log('EEex_Menu_LuaHook_BeforeListRenderingItem: ' .. msg)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Template instances created by Lua: store one under a name, destroy them, make a template from any item.
-- A .menu template is an item of kind ITEM_TEMPLATE whose templateItem is the prototype the engine copies for each
-- instance (uiCreateFromTemplate); nameToItem maps its name to it (light userdata), and instances keep the
-- template's name in templateName.
---------------------------------------------------------------------------------------------------

local function findInstance(menu, templateName, instanceId)
	return eachItem(menu, function(item)
		local t = item.templateName
		local name = t and t:get()
		return item.type ~= uiItemType.ITEM_TEMPLATE and name == templateName and item.instanceId == instanceId
	end)
end

-- Makes nameToItem[storeName] the instance `instanceId` of `templateName` in `menuName`, so the Infinity_* item
-- functions (Infinity_GetArea / SetArea...) reach that instance by name. Returns the instance, or nil.
function EEex_Menu_StoreTemplateInstance(menuName, templateName, instanceId, storeName)
	local menu = EEex_Menu_Find(menuName)
	local item = menu and findInstance(menu, templateName, instanceId)
	if item and type(nameToItem) == 'table' then nameToItem[storeName] = EEex_UDToLightUD(item) end
	return item
end

-- Removed instances are freed one destroy call later, and never while the UI still holds them as the captured
-- item: the engine may touch the item it is handling (button release) after the Lua action that removed it.
local pendingFree = {}
local function capturedAddress()
	local capture = EngineGlobals.capture
	local item = capture and capture.item
	return item and IEX_Address(item) or 0
end
local function flushPending()
	local keep = {}
	local captured = capturedAddress()
	for _, address in ipairs(pendingFree) do
		if address == captured then keep[#keep + 1] = address else IEX_EngineFree(address) end
	end
	pendingFree = keep
end

local function destroyInstances(menu, predicate)
	flushPending()
	local prev, item = nil, menu.items
	local removed = 0
	while item do
		local nextItem = item.next
		local t = item.templateName
		local name = t and t:get()
		if item.type ~= uiItemType.ITEM_TEMPLATE and name and name ~= '' and predicate(item, name) then
			if prev then prev.next = nextItem else menu.items = nextItem end
			pendingFree[#pendingFree + 1] = IEX_Address(item)
			removed = removed + 1
		else
			prev = item
		end
		item = nextItem
	end
	return removed
end

-- Destroys every template instance of menu `menuName` (injected or created there). Returns how many.
function EEex_Menu_DestroyAllTemplates(menuName)
	local menu = EEex_Menu_Find(menuName)
	if not menu then return 0 end
	return destroyInstances(menu, function() return true end)
end

-- Destroys instance `instanceId` of `templateName` in menu `menuName`.
function EEex_Menu_DestroyInjectedTemplate(menuName, templateName, instanceId)
	local menu = EEex_Menu_Find(menuName)
	if not menu then return 0 end
	return destroyInstances(menu, function(item, name) return name == templateName and item.instanceId == instanceId end)
end

-- Copies `item` (any uiItem) as a new template `templateName` of menu `menuName`: instances of it can then be
-- created like those of a .menu template (EEex_Menu_InjectTemplateInstance / Infinity_InstanceAnimation).
-- Returns the template item.
local ITEM_SIZE = uiItem and uiItem.sizeof or 0x358
function EEex_Menu_CreateTemplateFromCopy(menuName, templateName, item)
	local menu = EEex_Menu_Find(menuName)
	if not menu then error('EEex_Menu_CreateTemplateFromCopy: no menu ' .. tostring(menuName), 2) end
	if not item then error('EEex_Menu_CreateTemplateFromCopy: item expected', 2) end
	local protoAddress = IEX_EngineAlloc(ITEM_SIZE)
	IEX_MemCopy(protoAddress, item, ITEM_SIZE)
	local proto = IEX_ToObject(protoAddress, 'uiItem')
	proto.next = nil
	proto.menu = menu
	local templateAddress = IEX_EngineAlloc(ITEM_SIZE)
	local template = IEX_ToObject(templateAddress, 'uiItem')
	template.type = uiItemType.ITEM_TEMPLATE
	EEex_WritePointer(templateAddress + IEX_FieldOffset('uiItem', 'name'), IEX_EngineStrdup(templateName))
	template.menu = menu
	template.templateItem = proto
	local last = lastItem(menu)
	if last then last.next = template else menu.items = template end
	if type(nameToItem) == 'table' then nameToItem[templateName] = EEex_UDToLightUD(template) end
	return template
end

---------------------------------------------------------------------------------------------------
-- Sliced rectangles (9-slice frames from a PVRZ). The engine draws its own fixed set (uiDrawSlicedRect); IEX
-- keeps the definitions mods register but does not draw them yet (gap: the frame is simply not shown).
---------------------------------------------------------------------------------------------------

EEex = EEex or {}
IEX_SlicedRects = IEX_SlicedRects or {}
function EEex.RegisterSlicedRect(name, definition)
	IEX_SlicedRects[name] = definition
end
local reportedSliced = {}
function EEex.DrawSlicedRect(name, area)
	if not reportedSliced[name] then
		reportedSliced[name] = true
		IEX_Log('EEex.DrawSlicedRect: drawing sliced rects is not supported by IEX yet (' .. tostring(name) .. ')')
	end
end

---------------------------------------------------------------------------------------------------
-- .menu values, listener lists, table copy
---------------------------------------------------------------------------------------------------

-- IEEE 754 single from its 32 bits (a float .menu value).
local function floatFromBits(u)
	local sign = u >= 0x80000000 and -1 or 1
	local exponent = math.floor(u / 0x800000) % 0x100
	local mantissa = u % 0x800000
	if exponent == 0 then return sign * mantissa * 2 ^ -149 end
	if exponent == 0xFF then return mantissa == 0 and sign * math.huge or 0 / 0 end
	return sign * (1 + mantissa / 0x800000) * 2 ^ (exponent - 127)
end

-- The Lua value of a .menu value object (item.text.text, item.bam.resref, item.bam.sequence...): number, string,
-- or the function compiled from a Lua expression. nil gives nil; anything else is indexed as a value object
-- (a number raises "attempt to index", as under EEex 1.3.1: difftest modules 2026-10-29).
function EEex_Menu_GetItemVariant(variant)
	if variant == nil then return nil end
	local kind = variant.type
	if kind == 0 then return variant.value end
	if kind == 2 then
		local s = variant.string
		if type(s) == 'userdata' then return s:get() end
		return s
	end
	if kind == 3 then
		return floatFromBits(EEex_ReadU32(EEex_UDToPtr(variant) + 8))
	end
	return rawget(IEX_LuaRegistry(), variant.value)
end

-- The listener lists (mods remove their own entries from them).
EEex_Menu_AfterMainFileLoadedListeners = IEX_GetListeners('MenuMainFileLoaded')
EEex_Menu_MainFileLoadedListeners = EEex_Menu_AfterMainFileLoadedListeners
EEex_Menu_BeforeMainFileLoadedListeners = IEX_GetListeners('MenuBeforeMainFileLoaded')

-- A deep copy of a table (nested tables copied, each once; metatables kept), e.g. a text style copied from the
-- game's `styles` table (BuffBot registers its styles this way).
EEex = EEex or {}
function EEex.DeepCopy(value, seen)
	if type(value) ~= 'table' then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do copy[EEex.DeepCopy(k, seen)] = EEex.DeepCopy(v, seen) end
	return setmetatable(copy, getmetatable(value))
end
