-- EEex-compatible API used by Tweaks Anthology (m_gt*.lua) and similar mods: object / trigger / response strings
-- compiled by the engine, object searches, more sprite getters and the weapon-hit / quick-list listeners.
-- C++ side: src/core/lua_scripting.cpp (IEX_Parse*, IEX_GetAllOfTypeInRange...), src/core/lua_sprite_hooks.cpp
-- (IEX_TA_* callbacks below are called by the engine hooks).

-- Mods test this to know an engine extender is running.
EEex_Active = true

-- CGameObject.m_objectType values (CGameObject::TYPE_* constants of the game binary).
CGameObjectType = CGameObjectType or {}
for name, value in pairs({
	NONE = 0x00, AIBASE = 0x01, SOUND = 0x10, CONTAINER = 0x11, SPAWNING = 0x20, DOOR = 0x21, STATIC = 0x30,
	SPRITE = 0x31, OBJECT_MARKER = 0x40, TRIGGER = 0x41, TILED_OBJECT = 0x51, TEMPORAL = 0x60, AREA_AI = 0x61,
	FIREBALL = 0x70, GAME_AI = 0x71,
}) do
	if CGameObjectType[name] == nil then CGameObjectType[name] = value end
end

-- --- Item abilities ---

-- item:getAbility(index) -> Item_ability_st of the item's resource (nil when out of range).
-- EEex's binding of CItem::CItem(CResRef, useCount1, useCount2, useCount3, wear, flags) on an object made by
-- EEex_NewUD('CItem') (SadoEE camp merchant): resref = a CResRef from EEex_NewUD or a string.
function CItem.Construct_Overload_Manual(item, resref, u1, u2, u3, wear, flags)
	local res = resref
	if type(resref) ~= 'string' then res = resref:get() end
	IEX_Eng_ConstructItem(IEX_Address(item), res, u1 or 0, u2 or 0, u3 or 0, wear or 0, flags or 0)
end

function CItem.getAbility(item, index)
	local res = item.pRes
	return res and EEex_Resource_GetItemAbility(res.pHeader, index) or nil
end

-- --- Object types: "[PC]", "[EVILCUTOFF]", "[0.0.0.0.12]", "Myself"... compiled by the engine ---

function EEex_Object_ParseString(text)
	return IEX_ParseObjectType(text)
end

function CAIObjectType.free(objectType)
	IEX_FreeObjectType(objectType)
end

-- --- Conditionals: trigger lines ("See([PC])\n!Global(...)") compiled and evaluated by the engine ---

local Conditional = {}
Conditional.__index = Conditional

-- True when every trigger holds for the script object (OR() blocks as in BCS files). Status triggers only:
-- event triggers (HitBy, AttackedBy...) see no pending events, so they are false.
function Conditional:evalConditionalAsAIBase(object)
	if not self.address or not object then return false end
	return IEX_ConditionHolds(self.address, object)
end

function Conditional:free()
	if self.address then IEX_FreeConditional(self.address) end
	self.address = nil
end

function EEex_Trigger_ParseConditionalString(text)
	return setmetatable({ address = IEX_ParseConditional(text) }, Conditional)
end

function EEex_Trigger_EvalScriptFileConditionalAsAIBase(conditional, object)
	return conditional:evalConditionalAsAIBase(object)
end

function EEex_Trigger_EvalConditionalStringAsAIBase(text, object)
	local conditional = EEex_Trigger_ParseConditionalString(text)
	local result = conditional:evalConditionalAsAIBase(object)
	conditional:free()
	return result
end

-- --- Responses: action lines compiled by the engine ---

local Response = {}
Response.__index = Response

-- Runs the actions now, in order, as the object (its own action code), without touching its action queue; the
-- object then goes on with its current action. Instant actions complete; an action that needs several ticks
-- (move, attack, spell) only does its first step (src/core/lua_scripting.cpp, IEX_ExecuteResponseInstantly).
function Response:executeResponseAsAIBaseInstantly(object)
	if self.address and object then IEX_ExecuteResponseInstantly(self.address, object) end
end

-- Appends the actions to the object's action queue, without interrupting its current action
-- (CGameAIBase::InsertResponse without the interrupt flag).
function Response:queueResponseOnAIBase(object)
	if self.address and object then IEX_InsertResponse(self.address, object) end
end

function Response:free()
	if self.address then IEX_FreeResponse(self.address) end
	self.address = nil
end

function EEex_Action_ParseResponseString(text)
	return setmetatable({ address = IEX_ParseResponse(text) }, Response)
end

function EEex_Action_ExecuteScriptFileResponseAsAIBaseInstantly(response, object)
	response:executeResponseAsAIBaseInstantly(object)
end

function EEex_Action_ExecuteResponseStringOnAIBaseInstantly(text, object)
	local response = EEex_Action_ParseResponseString(text)
	response:executeResponseAsAIBaseInstantly(object)
	response:free()
end

-- Queues the actions of a response string on the object, after its current ones.
function EEex_Action_QueueScriptFileResponseOnAIBase(response, object)
	response:queueResponseOnAIBase(object)
end

function EEex_Action_QueueResponseStringOnAIBase(text, object)
	local response = EEex_Action_ParseResponseString(text)
	response:queueResponseOnAIBase(object)
	response:free()
end

-- Named targets kept per script object: EEex_Target("name") in its script strings resolves to them.
function CGameAIBase.setStoredScriptingTarget(object, name, target)
	local aux = EEex_GetUDAux(object)
	aux.IEX_ScriptingTargets = aux.IEX_ScriptingTargets or {}
	aux.IEX_ScriptingTargets[name] = target and target.m_id or nil
end

function CGameAIBase.getStoredScriptingTarget(object, name)
	local targets = EEex_GetUDAux(object).IEX_ScriptingTargets
	return targets and EEex_GameObject_Get(targets[name]) or nil
end

-- Called by the engine's object decoding (src/core/lua_scripting.cpp) for the OBJECT.IDS functions IEX adds:
-- 115 EEex_LuaObject = the object in the Lua global EEex_LuaObject, 117 EEex_Target("name") = the target stored
-- under name on the script's caller. -> object id, or nil (the object string then matches nobody).
function IEX_ResolveScriptObject(kind, callerAddress, name)
	if kind == 115 then
		local object = rawget(_G, 'EEex_LuaObject')
		return type(object) == 'userdata' and object.m_id or nil
	elseif kind == 117 then
		local aux = IEX_UDAux[callerAddress]
		local targets = aux and aux.IEX_ScriptingTargets
		return targets and targets[name] or nil
	elseif kind == 118 then
		return IEX_LuaDecode(name, callerAddress)
	end
end

-- 118 EEex_LuaDecode("chunk"): the chunk runs with EEex_LuaDecode_Object set to the script's caller and returns
-- the object to use (game object, or its id); anything else matches nobody.
local decodeChunks = {}
function IEX_LuaDecode(chunk, callerAddress)
	local fn = decodeChunks[chunk]
	if fn == nil then
		local err
		fn, err = load(chunk, '=EEex_LuaDecode')
		if not fn then IEX_Log('EEex_LuaDecode chunk does not compile: ' .. tostring(err) .. ' in ' .. chunk) end
		fn = fn or false
		decodeChunks[chunk] = fn
	end
	if not fn then return nil end
	local caller = IEX_ToObject(callerAddress, 'CGameObject')
	caller = caller and EEex_GameObject_Get(caller.m_id)
	local previous = rawget(_G, 'EEex_LuaDecode_Object')
	EEex_LuaDecode_Object = caller
	local ok, result = pcall(fn)
	EEex_LuaDecode_Object = previous
	if not ok then
		IEX_Log('Error in EEex_LuaDecode: ' .. tostring(result))
		return nil
	end
	if type(result) == 'number' then return result end
	if type(result) == 'userdata' then return result.m_id end
	return nil
end

-- --- Object strings evaluated for a script object ---

-- The object objectString names from aiBase's point of view ("Player1", "LastAttackerOf(Myself)", "[ENEMY]" =
-- nearest match), as the engine's own scripts resolve it; nil when none.
function EEex_Object_EvalStringAsAIBase(objectString, aiBase)
	if not aiBase then return nil end
	return IEX_EvalObjectString(objectString, aiBase)
end

-- --- Object searches (the engine's own search, as NumCreature() and friends) ---

local function objectsFromIds(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local object = EEex_GameObject_Get(id)
		if object then out[#out + 1] = object end
	end
	return out
end

-- Every object matching aiObjectType within range of (x, y) in the area. bCheckForLineOfSight needs a terrain
-- table (else the search runs without it); bCheckForNonSprites also searches non-creature objects.
function EEex_Area_GetAllOfTypeInRange(area, x, y, aiObjectType, range, bCheckForLineOfSight, bCheckForNonSprites,
                                       terrainTable)
	if not area or not aiObjectType then return {} end
	return objectsFromIds(IEX_GetAllOfTypeInRange(area, x, y, aiObjectType, range,
		bCheckForLineOfSight == true, bCheckForNonSprites == true, terrainTable, nil))
end

function EEex_Area_GetAllOfTypeStringInRange(area, x, y, objectString, range, bCheckForLineOfSight,
                                             bCheckForNonSprites, terrainTable)
	local aiObjectType = EEex_Object_ParseString(objectString)
	local result = EEex_Area_GetAllOfTypeInRange(area, x, y, aiObjectType, range, bCheckForLineOfSight,
		bCheckForNonSprites, terrainTable)
	aiObjectType:free()
	return result
end

-- Around a sprite: line of sight by default (with the sprite's visible terrain table).
function EEex_Sprite_GetAllOfTypeInRange(sprite, aiObjectType, range, bCheckForLineOfSight, bCheckForNonSprites,
                                         terrainTable)
	if not sprite or not sprite.m_pArea or not aiObjectType then return {} end
	return objectsFromIds(IEX_GetAllOfTypeInRange(sprite.m_pArea, sprite.m_pos.x, sprite.m_pos.y, aiObjectType,
		range, bCheckForLineOfSight ~= false, bCheckForNonSprites == true, terrainTable, sprite))
end

function EEex_Sprite_GetAllOfTypeStringInRange(sprite, objectString, range, bCheckForLineOfSight,
                                               bCheckForNonSprites, terrainTable)
	local aiObjectType = EEex_Object_ParseString(objectString)
	local result = EEex_Sprite_GetAllOfTypeInRange(sprite, aiObjectType, range, bCheckForLineOfSight,
		bCheckForNonSprites, terrainTable)
	aiObjectType:free()
	return result
end

CGameSprite.getAllOfTypeInRange = EEex_Sprite_GetAllOfTypeInRange
CGameSprite.getAllOfTypeStringInRange = EEex_Sprite_GetAllOfTypeStringInRange

function CGameAIBase.virtual_GetVisualRange(object) return IEX_VisualRange(object) end
function CGameSprite.virtual_GetVisualRange(sprite) return IEX_VisualRange(sprite) end

-- --- Areas ---

-- Nearest walkable point to (x, y) in the area -> x, y (the engine's search for an open search-map square, as used
-- to place jumping and summoned creatures). personalSpace: creature size in search squares (default 3, a human).
function EEex_Area_GetNearestOpenPosition(area, x, y, personalSpace)
	return IEX_NearestOpenPosition(area, math.floor(x), math.floor(y),
		type(personalSpace) == 'number' and personalSpace or nil)
end
if CGameArea then CGameArea.getNearestOpenPosition = EEex_Area_GetNearestOpenPosition end

-- The object under the mouse cursor in the visible area (creature, container, door, region... as the engine
-- picks it for the cursor and tooltips), or nil.
function EEex_GameObject_GetUnderCursor()
	local area = EEex_Area_GetVisible()
	local id = area and area.m_iPicked
	if not id or id == -1 then return nil end
	return EEex_GameObject_Get(id)
end

-- Id of the object under the cursor, -1 when none.
function EEex_GameObject_GetUnderCursorID()
	local area = EEex_Area_GetVisible()
	local id = area and area.m_iPicked
	return id or -1
end

function EEex_GameObject_IsSpriteID(id, allowDead)
	if type(id) ~= 'number' or id == -1 then return false end
	return EEex_GameObject_IsSprite(EEex_GameObject_Get(id), allowDead)
end

-- --- Sprite getters ---

-- Modal action: 0 none, 1 battle song, 2 detect traps, 3 stealth, 4 turn undead, 5 shaman dance.
function EEex_Sprite_GetModalState(sprite) return sprite.m_nModalState end
CGameSprite.getModalState = EEex_Sprite_GetModalState

-- AI updates until the modal action applies again (0 = it applies on this update; the engine applies it when
-- its update counter and the creature id agree modulo 100).
function EEex_Sprite_GetModalTimer(sprite)
	return (sprite.m_id % 100 - sprite.m_nAIUpdateCounter % 100) % 100
end
CGameSprite.getModalTimer = EEex_Sprite_GetModalTimer

-- Casting counter: -1 when not casting.
function EEex_Sprite_GetCastTimer(sprite) return sprite.m_castCounter end
CGameSprite.getCastTimer = EEex_Sprite_GetCastTimer

-- SPLSTATE.IDS state of the active stats.
function EEex_Sprite_GetSpellState(sprite, id)
	if type(id) ~= 'number' or id < 0 or id >= 256 then return false end
	local word = sprite:getActiveStats().m_spellStates:get(math.floor(id / 32))
	return bit32.band(word, bit32.lshift(1, id % 32)) ~= 0
end
CGameSprite.getSpellState = EEex_Sprite_GetSpellState

-- PERSONALSPACE of the creature's animation.
function EEex_Sprite_GetPersonalSpace(sprite) return IEX_PersonalSpace(sprite) end
CGameSprite.getPersonalSpace = EEex_Sprite_GetPersonalSpace

-- Launcher equipped for a ranged ability (launcherType 1 bow, 2 crossbow, 3 sling) -> item, slot (35..38),
-- or nil, 0. Same search as CGameSprite::GetLauncher (weapon slots, item category 15 / 27 / 18).
local launcherCategory = { [1] = 15, [2] = 27, [3] = 18 }
function EEex_Sprite_GetLauncher(sprite, ability)
	if not ability or ability.type ~= 2 then return nil, 0 end
	local category = launcherCategory[ability.launcherType]
	if not category then return nil, 0 end
	local items = sprite.m_equipment.m_items
	local slot = 0
	for i = 35, 38 do
		slot = i
		local item = items:get(i)
		local res = item and item.pRes
		local header = res and res.pHeader
		if header and header.itemType == category then return item, i end
	end
	return nil, slot
end
CGameSprite.getLauncher = EEex_Sprite_GetLauncher

-- Caster level used for a spell: the engine's own CGameSprite::GetCasterLevel (wizard / priest casting level of
-- the creature's class, average level for other spell types, at least 1; includeWildMage adds the wild mage
-- level roll). The engine takes a CSpell: a 16-byte {CRes*, CResRef} wrapper built here around the demanded file.
-- A missing spell file gives a wrapper without resource: the engine then uses the average level (as under EEex).
local spellWrapper
function EEex_Sprite_GetCasterLevelForSpell(sprite, resref, includeWildMage)
	resref = type(resref) == 'string' and resref or ''
	local res = 0
	if resref ~= '' then
		local address, _, r = IEX_ResourceData(resref, 0x3EE)
		if address and r then res = r end
	end
	spellWrapper = spellWrapper or EEex_Malloc(16)
	EEex_WritePointer(spellWrapper, res)
	EEex_WriteLString(spellWrapper + 8, string.upper(resref), 8)
	return sprite:IEX_GetCasterLevel(spellWrapper, includeWildMage and 1 or 0)
end

-- --- Engine timer: logic updates per second ("Maximum Frame Rate", game speed) ---

-- Under EEex a write changes the logic rate, so the whole game runs faster (measured 2026-10-30: 60 = 2x, 120 =
-- 4x, with or without 'Uncap FPS'). Mods mostly write it to get a smoother picture (Tweaks Anthology "Dynamic FPS
-- Change": 60 out of combat), and the game then runs at double speed. With 'Keep Game Speed' on (Baldur.lua
-- [IEX], default 1), IEX keeps the logic rate and takes the value as a render rate instead (drawn frames with
-- motion interpolation); the writer reads back what it wrote. Code from the files in IEX_GameSpeedWriters (time
-- acceleration on purpose: BuffBot's fast mode, BfBotFst.lua) still changes the logic rate, as under EEex.
-- 'Keep Game Speed' 0: every write changes the logic rate, exactly as EEex.
IEX_GameSpeedWriters = IEX_GameSpeedWriters or { 'BfBotFst' }

local keepSpeed = true
local requested = nil  -- rate the mods asked for while the game speed is kept

-- The player's game speed while 'Keep Game Speed' is on: Baldur.lua [IEX] 'AI Speed' (written by the AI Speed
-- option of the Uncap FPS tab), default 30. 'Program Options' 'Maximum Frame Rate' cannot be trusted for this:
-- the engine's CBaldurChitin::SaveOptions writes the CURRENT tick rate there, so a mod's write (Tweaks Anthology
-- Dynamic FPS: 60 out of combat, under EEex or with 'Keep Game Speed' 0) is saved and becomes the logic rate of
-- the next launch (CChitin::InitInstance reads it): a game twice as fast in and out of combat (2026-10-30).
function IEX_PlayerGameSpeed()
	local ok, v = pcall(Infinity_GetINIValue, 'IEX', 'AI Speed', 30)
	v = ok and tonumber(v) or 30
	if v < 1 or v > 240 then v = 30 end
	return math.floor(v)
end

-- Once the engine has read Baldur.lua (first logic tick, after CChitin::InitInstance): the logic runs at the
-- player's speed, whatever an earlier session saved in 'Maximum Frame Rate'.
local startChecked = false
local function checkStartSpeed()
	if startChecked then return end
	startChecked = true
	if not keepSpeed then return end
	local current, base = IEX_TicksPerSecond(), IEX_PlayerGameSpeed()
	if current ~= base then
		IEX_Log(string.format("Keep Game Speed: Baldur.lua 'Maximum Frame Rate' %d (the tick rate saved by the engine, "
			.. "e.g. after a mod's frame rate change) not used, game speed %d (Options > Uncap FPS > AI Speed)", current, base))
		IEX_TicksPerSecond(base)
	end
end
if IEX_AddListener then IEX_AddListener('EngineTickDone', checkStartSpeed) end

local function speedWriter()
	if not keepSpeed then return true end
	-- level 1 = this function, 2 = the metamethod, 3 = the code that read or wrote the field
	local info = debug and debug.getinfo and debug.getinfo(3, 'S')
	local src = info and tostring(info.source) or ''
	for _, name in ipairs(IEX_GameSpeedWriters) do
		if src:find(name, 1, true) then return true end
	end
	return false
end

local function setRequested(value)
	requested = value
	if IEX_SetFrameRateFloor then
		IEX_SetFrameRateFloor(value or 0)  -- only used while above the tick rate
	end
end

-- IEX_SetKeepGameSpeed(on) (IEX_FrameRate.lua, options screen). Off: the rate a mod asked for becomes the logic
-- rate. On: the logic goes back to the player's speed ([IEX] 'AI Speed') and the current rate becomes a render
-- request.
function IEX_SetKeepGameSpeed(on)
	on = on and true or false
	if on == keepSpeed then return keepSpeed end
	keepSpeed = on
	if on then
		local current, base = IEX_TicksPerSecond(), IEX_PlayerGameSpeed()
		if current ~= base then
			IEX_TicksPerSecond(base)
			setRequested(current)
		end
	else
		local r = requested
		setRequested(nil)
		if r then IEX_TicksPerSecond(r) end
	end
	IEX_Log('Keep Game Speed: ' .. tostring(on))
	return keepSpeed
end

function IEX_GetKeepGameSpeed() return keepSpeed, requested end

EEex_CChitin = EEex_CChitin or setmetatable({}, {
	__index = function(_, key)
		if key == 'TIMER_UPDATES_PER_SECOND' then
			if requested and not speedWriter() then return requested end
			return IEX_TicksPerSecond()
		end
	end,
	__newindex = function(t, key, value)
		if key ~= 'TIMER_UPDATES_PER_SECOND' then rawset(t, key, value) return end
		if speedWriter() then
			IEX_TicksPerSecond(value)
		elseif tonumber(value) ~= requested then
			setRequested(tonumber(value))
		end
	end,
})

-- --- 2DA ---

function EEex_Resource_GetAt2DAPoint(array, x, y)
	return array:getAtPoint(x, y)
end

-- --- Sprite listeners (called by src/core/lua_sprite_hooks.cpp) ---

-- A spell / item ability use changed the creature's remaining uses: fn(sprite, resref, changeAmount).
function EEex_Sprite_AddQuickListsCheckedListener(fn) IEX_AddListener('QuickListsChecked', fn) end

-- A weapon attack hit; returning true from fn(args) cancels its base damage and on-hit effects.
-- args: attackingSprite, targetSprite, weapon, weaponAbility, launcher, launcherAbility.
function EEex_Sprite_AddBlockWeaponHitListener(fn) IEX_AddListener('BlockWeaponHit', fn) end

-- The base weapon damage effect of a hit was built (before it is applied): fn(context) may edit context.effect.
-- context: attacker, target, effect, weapon, ability, launcher, isCritical, isLeftHand, attackRoll.
function EEex_Sprite_AddAlterBaseWeaponDamageListener(fn) IEX_AddListener('AlterBaseWeaponDamage', fn) end

local function listeners(event)
	local list = IEX_Listeners[event]
	return list and #list > 0
end

function IEX_TA_QuickListsChecked(sprite, resref, changeAmount)
	if listeners('QuickListsChecked') then IEX_Dispatch('QuickListsChecked', sprite, resref, changeAmount) end
end

local function abilityOf(item, index)
	return item and item:getAbility(index) or nil
end

function IEX_TA_BlockWeaponHit(attacker, target, weapon, launcher, abilityIndex)
	if not listeners('BlockWeaponHit') then return false end
	local args = {
		attackingSprite = attacker, targetSprite = target, weapon = weapon,
		weaponAbility = abilityOf(weapon, abilityIndex), launcher = launcher,
		launcherAbility = abilityOf(launcher, 0),
	}
	return IEX_Dispatch('BlockWeaponHit', args)
end

function IEX_TA_AlterBaseWeaponDamage(attacker, target, effect, weapon, launcher, abilityIndex, isCritical,
                                      isLeftHand, attackRoll)
	if not listeners('AlterBaseWeaponDamage') then return end
	IEX_Dispatch('AlterBaseWeaponDamage', {
		attacker = attacker, target = target, effect = effect, weapon = weapon,
		ability = abilityOf(weapon, abilityIndex), launcher = launcher, isCritical = isCritical,
		isLeftHand = isLeftHand, attackRoll = attackRoll,
	})
end

-- --- Scratch engine objects (EEex_NewUD, EEex_RunWithStackManager, EEex_WriteUDArgs) ---

-- Engine messages built by Lua code are kept as Lua tables: :Construct(...) stores the arguments, and
-- CMessageHandler:AddMessage(message) performs them right away (IEX supports CMessageDisplayText).
local MessageProxy = {}
MessageProxy.__index = MessageProxy
function MessageProxy:Construct(...) self.args = { ... } end

-- A CResRef (the engine description has no such type: resrefs are fields there): :set(s) / :get() keep the
-- 8-character name, upper case, as EEex's CResRef userdata does.
local ResRefProxy = {}
ResRefProxy.__index = ResRefProxy
function ResRefProxy:set(s) self.value = string.upper(tostring(s or '')):sub(1, 8) end
function ResRefProxy:get() return self.value or '' end
IEX_ResRefProxy = ResRefProxy

-- typeName with a known size -> zeroed object of that type (never freed, like an engine allocation the mod
-- hands over to the engine); other names -> message proxy.
function EEex_NewUD(typeName)
	local class = rawget(_G, typeName)
	local size = type(class) == 'table' and rawget(class, 'sizeof')
	if typeName == 'CResRef' and not size then return setmetatable({ value = '' }, ResRefProxy) end
	if size and size > 0 then
		local object = IEX_ToObject(IEX_Alloc(size), typeName)
		local init = IEX_DefaultInit and IEX_DefaultInit[typeName]
		if init then init(object) end
		return object
	end
	return setmetatable({ iexType = typeName }, MessageProxy)
end

-- Releases an object made by EEex_NewUD (a message proxy needs nothing).
function EEex_FreeUD(object)
	if type(object) == 'userdata' then
		local address = IEX_Address(object)
		if address and address ~= 0 then IEX_Free(address) end
	end
end

-- Runs fn(manager) with scratch objects described by defs ({ name, struct, constructor = { args } }):
-- manager:getUD(name) returns each. CString values are the Lua string of their constructor; other structs are
-- zeroed memory of their size set to the engine's defaults when IEX_DefaultInit knows the type (CButtonData), and
-- CPoint-like `fromXY` constructors set x, y; freed when fn returns. Returns what fn returns, as EEex does
-- (SadoEE's passive traps read area:CheckLOS through it: a nil result read as "in sight", walls ignored).
local function packResults(...) return select('#', ...), { ... } end
function EEex_RunWithStackManager(defs, fn)
	local values, allocations = {}, {}
	for _, def in ipairs(defs) do
		if def.struct == 'CString' then
			local args = def.constructor and def.constructor.args
			values[def.name] = args and args[1] or ''
		else
			local class = rawget(_G, def.struct)
			local size = type(class) == 'table' and rawget(class, 'sizeof') or 0
			local address = IEX_Alloc(math.max(size, 8))
			allocations[#allocations + 1] = address
			values[def.name] = IEX_ToObject(address, def.struct)
			local init = IEX_DefaultInit and IEX_DefaultInit[def.struct]
			if init and values[def.name] then init(values[def.name]) end
			local ctor = def.constructor
			if ctor and ctor.variant == 'fromXY' and ctor.args then
				values[def.name].x, values[def.name].y = ctor.args[1], ctor.args[2]
			end
		end
	end
	local manager = { getUD = function(_, name) return values[name] end }
	local n, results = packResults(pcall(fn, manager))
	for _, address in ipairs(allocations) do IEX_Free(address) end
	if not results[1] then error(results[2], 0) end
	return (table.unpack or unpack)(results, 2, n)
end

-- Copies args[field] into object fields by a spec list { field, EEex_WriteFailType, default }.
function EEex_WriteUDArgs(object, args, spec)
	for _, entry in ipairs(spec) do
		local field, fail, default = entry[1], entry[2], entry[3]
		local value = args[field]
		if value == nil then
			if fail == EEex_WriteFailType.ERROR then
				error('EEex_WriteUDArgs: missing field ' .. tostring(field), 2)
			elseif fail == EEex_WriteFailType.DEFAULT then
				value = default
			end
		end
		if value ~= nil then
			local current = object[field]
			if type(current) == 'userdata' and type(value) == 'string' then current:set(value) else object[field] = value end
		end
	end
end

function CGameEffect.DecodeEffect(itemEffect, source, sourceId, target, sourceTarget)
	return IEX_DecodeEffect(itemEffect, source, sourceId or -1, target, sourceTarget or -1)
end

function CProjectile.AddEffect(projectile, effect) IEX_ProjectileAddEffect(projectile, effect) end

-- Name as EEex returns it for messages (a string here).
function CGameSprite.GetName(sprite) return IEX_SpriteName(sprite) end

CVidPalette = CVidPalette or {}
CVidPalette.RANGE_COLORS = CVidPalette.RANGE_COLORS or { get = function(_, index) return IEX_RangeColor(index) end }

local reportedMessages = {}
function CMessageHandler.AddMessage(handler, message, flag)
	if getmetatable(message) == MessageProxy and message.iexType == 'CMessageDisplayText' and message.args then
		local a = message.args
		IEX_DisplayText(tostring(a[1] or ''), tostring(a[2] or ''), a[3] or 0xBED7D7, a[4] or 0xBED7D7, a[5] or -1)
	elseif not reportedMessages[tostring(message and message.iexType)] then
		reportedMessages[tostring(message and message.iexType)] = true
		IEX_Log('CMessageHandler:AddMessage: message type not supported by IEX: ' .. tostring(message and message.iexType))
	end
end
