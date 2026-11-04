-- EEex-compatible listener registration (same function names as EEex, implemented on IEX events).

-- UI: the main menu file (UI.MENU) has been parsed at startup.
function EEex_Menu_AddMainFileLoadedListener(fn) IEX_AddListener('MenuMainFileLoaded', fn) end
EEex_Menu_AddAfterMainFileLoadedListener = EEex_Menu_AddMainFileLoadedListener

-- UI: the main menu file (UI.MENU) is about to be parsed (startup), or parsed again (UI reload).
function EEex_Menu_AddBeforeMainFileLoadedListener(fn) IEX_AddListener('MenuBeforeMainFileLoaded', fn) end
function EEex_Menu_AddBeforeMainFileReloadedListener(fn) IEX_AddListener('MenuBeforeMainFileReloaded', fn) end

-- UI: the main menu file has been parsed again (UI reload); menus loaded by mods must be loaded again.
function EEex_Menu_AddAfterMainFileReloadedListener(fn) IEX_AddListener('MenuMainFileReloaded', fn) end

-- UI: the engine (re)loaded its translation strings.
function EEex_Menu_AddTranslationLoadedListener(fn) IEX_AddListener('TranslationLoaded', fn) end

-- Game: the engine game state is ready (after the UI and every M_*.lua file have loaded).
function EEex_GameState_AddInitializedListener(fn) IEX_AddListener('GameStateInitialized', fn) end

-- Sprites: a creature object has been created and added to the game (area load, save load, summon).
-- The listener receives the CGameSprite object.
function EEex_Sprite_AddLoadedListener(fn) IEX_AddListener('SpriteLoaded', fn) end
EEex_Sprite_LoadedListeners = IEX_GetListeners('SpriteLoaded')
-- Right before the loaded listeners, as under EEex, the global EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled(sprite)
-- runs (the creature's effects are in place; mods chain this hook). IEX's version imports marshal handler data.
function EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled(sprite)
	if IEX_MarshalImport then IEX_MarshalImport(sprite) end
end
IEX_AddListener('SpriteLoaded', function(sprite)
	local hook = EEex_Sprite_LuaHook_OnAfterEffectListUnmarshalled
	if type(hook) == 'function' then hook(sprite) end
end)

-- Keyboard: a key went down (repeats excluded). The listener receives the SDL keycode; returning true
-- consumes the key, so the engine never sees it.
-- EEex passes a second argument, false (key repeats are not reported).
function EEex_Key_AddPressedListener(fn)
	if type(fn) ~= 'function' then error('EEex_Key_AddPressedListener: function expected', 2) end
	IEX_AddListener('KeyPressed', function(key) return fn(key, false) end)
end

-- Keyboard: a key went up. The listener receives the SDL keycode.
function EEex_Key_AddReleasedListener(fn) IEX_AddListener('KeyReleased', fn) end

-- Actions: a sprite started a new action (CGameSprite::SetCurrAction, after the engine copied it). The listener
-- receives (sprite, action): action is sprite.m_curAction, so editing it changes what the sprite does.
function EEex_Action_AddSpriteStartedActionListener(fn) IEX_AddListener('SpriteStartedAction', fn) end
EEex_Action_Private_SpriteStartedActionListeners = IEX_GetListeners('SpriteStartedAction')

-- Opcode 409 (Enable Action Listener): fn(sprite, action, op409Effect) runs when a sprite that has an opcode 409
-- effect whose resource is `name` starts an action (one call per such effect).
EEex_Action_Private_EnabledSpriteStartedActionListeners = EEex_Action_Private_EnabledSpriteStartedActionListeners or {}
function EEex_Action_AddEnabledSpriteStartedActionListener(name, fn)
	if type(fn) ~= 'function' then error('EEex_Action_AddEnabledSpriteStartedActionListener: function expected', 2) end
	EEex_Action_Private_EnabledSpriteStartedActionListeners[tostring(name):upper()] = fn
end
IEX_AddListener('SpriteStartedAction', function(sprite, action)
	local listeners = EEex_Action_Private_EnabledSpriteStartedActionListeners
	if next(listeners) == nil then return end
	local found
	for _, list in ipairs({ sprite.m_timedEffectList, sprite.m_equipedEffectList }) do
		IEX_IterateList(list, function(e)
			if e.m_effectId == 409 then
				local fn = listeners[e.m_res:get():upper()]
				if fn then
					found = found or {}
					found[#found + 1] = { fn, e }
				end
			end
		end)
	end
	for _, f in ipairs(found or {}) do
		local ok, err = pcall(f[1], sprite, action, f[2])
		if not ok then IEX_Log('Error in an enabled sprite started action listener: ' .. tostring(err)) end
	end
end)

-- Action bar: the buttons have been rebuilt. The list is exposed under its EEex name too.
EEex_Actionbar_Private_ButtonsUpdatedListeners = IEX_GetListeners('ActionbarButtonsUpdated')
function EEex_Actionbar_AddButtonsUpdatedListener(fn) IEX_AddListener('ActionbarButtonsUpdated', fn) end

-- Game: the game session was destroyed (back to the main menu, or before another save is loaded).
function EEex_GameState_AddDestroyedListener(fn) IEX_AddListener('GameStateDestroyed', fn) end

-- UI: the screen size changed. fn(screenW, screenH) gets the UI size (Infinity_GetScreenSize); listeners also run
-- once when the game state is initialized, with the size the game started with.
function EEex_Menu_AddWindowSizeChangedListener(fn) IEX_AddListener('WindowSizeChanged', fn) end
local function windowSizeChanged()
	local ok, w, h = pcall(Infinity_GetScreenSize)
	if ok and w then IEX_Dispatch('WindowSizeChanged', w, h) end
end
IEX_AddListener('WindowResized', windowSizeChanged)
IEX_AddListener('GameStateInitialized', windowSizeChanged)

-- Effects: deferred variant of the lists resolved listeners: fn(sprite) once per engine tick for each creature
-- whose effect lists were re-evaluated during that tick (EEex reports far fewer calls than the immediate one).
function EEex_Opcode_AddDeferredListsResolvedListener(fn) IEX_AddListener('OpcodeDeferredListsResolved', fn) end
EEex_Opcode_DeferredListsResolvedListeners = IEX_GetListeners('OpcodeDeferredListsResolved')
do
	local pending, order = {}, {}
	IEX_AddListener('OpcodeListsResolved', function(sprite)
		local list = IEX_Listeners.OpcodeDeferredListsResolved
		if not list or #list == 0 then return end
		local id = sprite.m_id
		if not pending[id] then pending[id] = true order[#order + 1] = id end
	end)
	IEX_AddListener('EngineTickDone', function()
		if #order == 0 then return end
		local ids = order
		pending, order = {}, {}
		for _, id in ipairs(ids) do
			local sprite = EEex_GameObject_Get(id)
			if sprite then IEX_Dispatch('OpcodeDeferredListsResolved', sprite) end
		end
	end)
end
