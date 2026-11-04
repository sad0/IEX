-- Native hook points (src/core/hook_points.h, docs/NATIVE_HOOK_POINTS.md): engine moments that mods used to patch
-- in Windows machine code, implemented once in C++ on Windows and Linux, with one Lua side for every mod.
--
--   IEX_NativeHook_AddListener(point, fn)   adds a listener (installs the point first; false, reason if it can't)
--   IEX_NativeHook_RemoveListener(point, fn)
--   IEX_NativeHook_Enable(point [, a, b])    a switch point (no Lua per call): installs it and turns it on
--   IEX_NativeHook_Install(point [, a, b])   installs the engine side only; IEX_NativeHook_Installed(point)
--   IEX_NativeHook_Points()                  every point: category, kind, result, moment, available, installed...
--
-- Listener arguments and results per point (engine objects are userdata, numbers are integers):
--   value points: fn(..., value) -> new value (number) or nil to keep it; the next listener gets the new value.
--     hitRoll(attacker, target, roll 0..19)        toHitTotal(attacker, target, total)
--     critThreshold(attacker, target, value)        damageRoll(attacker, target, damage)
--     critMultiplier(attacker, target, multiplier)  casterSchoolSpell / casterSchoolItem(caster, effect, school)
--     targetSchool(target, effect, school)
--   anyTrue points: every listener runs; one true = yes.
--     attackCancel(attacker, target) -> cancel      hideInSight(spriteId) -> allow hiding while seen
--     keepAmmo(sprite, item) -> keep the count      deathDrop(sprite) -> keep the inventory on the corpse
--     groundContainer(container, sprite) -> list its items in the ground bar
--     findTrapsButton(sprite) -> handled (the engine's own handling is skipped)
--   plain listeners: attackResult(attacker, target, hit 0/1), attackIndex(attacker, target, index),
--     actionButtonL(index) / actionButtonR(index), classDone(sprite), groundMoveClick(area, x, y), campSameArea()
--   switches (IEX_NativeHook_Enable / Install): critBlocked, respecGear(flagAddress), campMarker(flagAddress),
--     smallFootprint(mode 0/1), containerMarker(colorAddress, marker), lastingModes, stealthReveals,
--     spellSlots99 (class spell lists read SPWI/SPPR slots 01-99; the SpellSlots mod enables it),
--     spellLists (class spell lists continue with the IEX lists; lua/IEX_SpellLists.lua enables it),
--     hdTiles (HD area tiles: TIS tile size 128/256/512; lua/IEX_HdTiles.lua enables it)
--   features (installed at startup, reported only): partyVision, alliedPassThrough, emptyContainerOutline
--
-- EEex_Hook* requests of mods written for EEex's asm API reach these points through lua/IEX_HookRequests.lua.
--
-- SadoEE bridge: IEX has no EEex asm / JIT API, so SadoEE's engine patches written in Windows x64 code do not
-- install (on Linux their byte checks fail first; on Windows the asm calls reach IEX's missing-API stand-ins).
-- Once every M_*.lua file has run (GameStateInitialized), IEX connects each installed component's Lua side to
-- these hook points and gives it the status / data its own Lua checks (SQRespec.status == 'patched', the flag
-- bytes, the SQRespec_Eng_* / PStash_Eng_* engine functions). IEX_Features.sado<Feature> = true per component.

IEX_NativeHooks = IEX_NativeHooks or { listeners = {}, enabled = {}, failed = {} }
local H = IEX_NativeHooks
H.listeners = H.listeners or {}
H.enabled = H.enabled or {}
H.failed = H.failed or {}

IEX_Features = IEX_Features or {}
for _, f in ipairs({ 'sadoAmmo', 'sadoAttackMove', 'sadoKeepGear', 'sadoRespec', 'sadoCamp', 'sadoStash',
		'sadoChests', 'sadoContainers', 'sadoFootprint', 'sadoModes', 'sadoCampMerchant' }) do
	if IEX_Features[f] == nil then IEX_Features[f] = false end
end

local points = IEX_NativeHook_Points and IEX_NativeHook_Points() or {}
H.points = points

local function sync(name)
	local n = #(H.listeners[name] or {}) + (H.enabled[name] and 1 or 0)
	if IEX_NativeHook_SetListening then IEX_NativeHook_SetListening(name, n) end
end

function IEX_NativeHook_AddListener(name, fn)
	if type(fn) ~= 'function' then error('IEX_NativeHook_AddListener: listener is not a function', 2) end
	local p = points[name]
	if not p or p.kind ~= 'listener' then return false, 'unknown native hook ' .. tostring(name) end
	local ok, why = IEX_NativeHook_Install(name)
	if not ok then return false, why end
	local list = H.listeners[name] or {}
	H.listeners[name] = list
	list[#list + 1] = fn
	sync(name)
	return true
end

function IEX_NativeHook_RemoveListener(name, fn)
	local list = H.listeners[name]
	if not list then return false end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) sync(name) return true end
	end
	return false
end

function IEX_NativeHook_Enable(name, a, b)
	local p = points[name]
	if not p or p.kind == 'feature' then return false, 'unknown native hook ' .. tostring(name) end
	local ok, why = IEX_NativeHook_Install(name, a, b)
	if not ok then return false, why end
	H.enabled[name] = true
	sync(name)
	return true
end

local function report(name, err)
	local msg = tostring(err)
	if H.failed[msg] then return end
	H.failed[msg] = true
	IEX_Log('[IEX] native hook ' .. name .. ' listener error: ' .. msg)
end

-- The engine side calls this while a point is active (hook_points.cpp: IEX_NativeHook_Fire(point, ...)).
local unpack = table.unpack or unpack
function IEX_NativeHook_Fire(name, ...)
	local list = H.listeners[name]
	if not list then return nil end
	local p = points[name]
	local result = p and p.result
	if result == 'value' then
		local n = select('#', ...)
		local args = { ... }
		local given = nil
		for i = 1, #list do
			local ok, r = pcall(list[i], unpack(args, 1, n))
			if not ok then
				report(name, r)
			elseif r ~= nil then
				given = r
				if type(r) == 'number' then args[n] = r end
			end
		end
		return given
	elseif result == 'anyTrue' then
		local yes = false
		for i = 1, #list do
			local ok, r = pcall(list[i], ...)
			if not ok then report(name, r) elseif r then yes = true end
		end
		return yes
	end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then report(name, err) end
	end
	return nil
end

-- ---- SadoEE bridge ----

-- True while no EEex-style asm API exists (the mods' own engine patches cannot have been installed): the names are
-- undefined or IEX's inert router stand-ins (lua/IEX_HookRequests.lua).
local function noAsmApi()
	local standIn = IEX_IsAsmStandIn or function(name) return rawget(_G, name) == nil end
	return standIn('EEex_JITNear') and standIn('EEex_HookBeforeCallWithLabels')
end

local function bridge(feature, label, ok, why)
	IEX_Features[feature] = ok and true or false
	IEX_Log('[IEX] SadoEE ' .. label .. ': ' .. (ok and 'native IEX hook' or ('not available, ' .. tostring(why))))
	return ok
end

local function linux()
	return IEX_Features.platform == 'linux64'
end

local function sadoBridges()
	if not noAsmApi() then return end
	-- #24 endless ammo (qol/M_SQAMMO.lua): its Swing hook asks SQAmmo_Hook_Keep(sprite, item)
	if not IEX_Features.sadoAmmo and type(SQAmmo) == 'table' and type(SQAmmo_Hook_Keep) == 'function' then
		-- (on Windows its EEex_HookBeforeCallWithLabels request already reached the router, which bound it)
		local ok, why = true, nil
		if not (IEX_HookRequests_IsBound and IEX_HookRequests_IsBound('keepAmmo', 'SQAmmo_Hook_Keep')) then
			ok, why = IEX_NativeHook_AddListener('keepAmmo', function(sprite, item)
				return SQAmmo_Hook_Keep(sprite, item) == true
			end)
		end
		if bridge('sadoAmmo', 'endless ammo', ok, why) then SQAmmo.status = 'hooked' end
	end
	-- #28 attack-move (qol/M_SQATKM.lua): a normal move click calls SQAttackMove_Cancel() first
	if not IEX_Features.sadoAttackMove and type(SQAtkM) == 'table' and type(SQAttackMove_Cancel) == 'function' then
		local ok, why = IEX_NativeHook_AddListener('groundMoveClick', function() SQAttackMove_Cancel() end)
		if bridge('sadoAttackMove', 'attack-move cancel', ok, why) then SQAtkM.status = 'patched' end
	end
	-- #30 keep gear (qol/M_SQKEEP.lua): the death effect drops nothing for EA 2 (PC)
	if not IEX_Features.sadoKeepGear and type(SQKeep) == 'table' then
		local ok, why = IEX_NativeHook_AddListener('deathDrop', function(sprite)
			return sprite.m_typeAI.m_EnemyAlly == 2
		end)
		if bridge('sadoKeepGear', 'keep gear on death', ok, why) then SQKeep.status = 'patched' end
	end
	-- #14 respec (camp/M_SQRESP.lua): SQRespec.flag (a byte the mod sets during a respec) stops the starting
	-- gold / weapon; SQRespec_Eng_RemoveAbilities / SQRespec_Eng_SwapItem are engine calls it makes
	if not IEX_Features.sadoRespec and type(SQRespec) == 'table' and type(SQRespec_Begin) == 'function' then
		SQRespec.flag = SQRespec.flag or EEex_Malloc(8)
		local ok, why = IEX_NativeHook_Install('respecGear', SQRespec.flag)
		if bridge('sadoRespec', 'respec', ok, why) then
			SQRespec.status = 'patched'
			if rawget(_G, 'SQRespec_Eng_RemoveAbilities') == nil then SQRespec_Eng_RemoveAbilities = IEX_Eng_RemoveAbilities end
			if rawget(_G, 'SQRespec_Eng_SwapItem') == nil then SQRespec_Eng_SwapItem = IEX_Eng_SwapItemPersonal end
		end
	end
	-- #10 camp (camp/M_SQCAMP.lua): SQCamp.flag hides the world map marker; clicking the current area calls
	-- SQCamp_SameAreaClicked()
	if not IEX_Features.sadoCamp and type(SQCamp) == 'table' and type(SQCamp_SameAreaClicked) == 'function' then
		SQCamp.flag = SQCamp.flag or EEex_Malloc(8)
		local ok, why = IEX_NativeHook_Install('campMarker', SQCamp.flag)
		if ok then
			ok, why = IEX_NativeHook_AddListener('campSameArea', function() SQCamp_SameAreaClicked() end)
		end
		if bridge('sadoCamp', 'camp world map', ok, why) then SQCamp.patchStatus = 'patched' end
	end
	-- #31 chests in the ground bar (qol/M_SQCHST.lua): a non-pile container in range asks SQChest_Allowed(c, sprite)
	if not IEX_Features.sadoChests and type(SQChest) == 'table' and type(SQChest_Allowed) == 'function' then
		local ok, why = IEX_NativeHook_AddListener('groundContainer', function(c, sp)
			return SQChest_Allowed(c, sp) == true
		end)
		if bridge('sadoChests', 'chests in the ground bar', ok, why) then SQChest.status = 'patched' end
	end
	-- #21 valuable containers (qol/M_SQCONT.lua): m_drawPoly 401 = gold outline, color at SQCont.colorPtr
	-- (SQCont_Tick keeps it equal to SQCont.COLOR); the hover outline goes through the Empty Container module
	if not IEX_Features.sadoContainers and type(SQCont) == 'table' and type(SQCont_Tick) == 'function' then
		if not SQCont.colorPtr then
			SQCont.colorPtr = EEex_Malloc(4)
			EEex_WriteU32(SQCont.colorPtr, SQCont.COLOR or 0x00D7FF)
			SQCont.colorWritten = SQCont.COLOR
		end
		local ok, why = IEX_NativeHook_Install('containerMarker', SQCont.colorPtr, 401)
		if bridge('sadoContainers', 'valuable containers outline', ok, why) then SQCont.polyHooked = true end
	end
	-- #25 / #26 small party footprint (qol/M_SQFOOT.lua): SQFoot.MODE 1 = one square, 0 = none
	if not IEX_Features.sadoFootprint and type(SQFoot) == 'table' and (SQFoot.MODE == 0 or SQFoot.MODE == 1) then
		local ok, why = IEX_NativeHook_Install('smallFootprint', SQFoot.MODE)
		if bridge('sadoFootprint', 'small party footprint', ok, why) then SQFoot.status = 'patched, mode ' .. SQFoot.MODE end
	end
	-- #27 lasting modes (qol/M_SQMODE.lua); the Find Traps button toggles #0's passive trap detection (SQTrap)
	if not IEX_Features.sadoModes and type(SQMode) == 'table' and type(SQMode_ToggleTraps) == 'function' then
		local ok, why = IEX_NativeHook_Install('lastingModes')
		if bridge('sadoModes', 'lasting modes', ok, why) then
			local traps = false
			if type(SQTrap) == 'table' then
				traps = IEX_NativeHook_AddListener('findTrapsButton', function(sp) SQMode_ToggleTraps(sp) return true end)
			end
			SQMode.status = traps and 'patched' or 'patched (no #0: Find Traps button unchanged)'
			local okS, whyS = IEX_NativeHook_Install('stealthReveals')
			SQMode.stealthStatus = okS and 'patched' or ('skipped: ' .. tostring(whyS))
			IEX_Log('[IEX] SadoEE lasting modes, stealth: ' .. SQMode.stealthStatus)
			-- its spam filter reads the modal state at the Windows offset (+0x3A29): read the field instead
			if linux() and type(SQMode_OnStartedAction) == 'function' then
				function SQMode_OnStartedAction(sp, a)
					if not SQMode.SPAM then return end
					local id = a.m_actionID
					if id ~= 296 and id ~= 33 then return end -- BattleSong(), Turn()
					local m = sp.m_nModalState
					if (id == 296 and (m == 1 or m == 5)) or (id == 33 and m == 4) then a.m_actionID = 0 end
				end
			end
		end
	end
end

IEX_AddListener('GameStateInitialized', sadoBridges)

-- Party Stash (M_PSTASH.lua) builds Windows x64 call stubs for 7 engine functions after probing Windows code
-- addresses; on Linux IEX gives it the same calls natively, before the stash first asks (PStash_Ready).
local PSTASH_ENG = {
	AddItemToStore = 'IEX_Eng_AddItemToStore', SwapItemPersonal = 'IEX_Eng_SwapItemPersonalInventory',
	AddDisposableItem = 'IEX_Eng_AddDisposableItem', DemandServerStore = 'IEX_Eng_DemandServerStore',
	GetServerStore = 'IEX_Eng_GetServerStore', ReleaseServerStore = 'IEX_Eng_ReleaseServerStore',
	TakeItemFromStore = 'IEX_Eng_TakeItemFromStore', ProcessEffectList = 'IEX_Eng_ProcessEffectList',
}
function IEX_NativeHooks_StashReady()
	if not linux() or type(PStash) ~= 'table' or type(PStash_Ready) ~= 'function' then return false end
	for name, fn in pairs(PSTASH_ENG) do
		if rawget(_G, 'PStash_Eng_' .. name) == nil then _G['PStash_Eng_' .. name] = _G[fn] end
	end
	PStash.build = PStash.build or '2.7.3.0'
	PStash.scratch = PStash.scratch or EEex_Malloc(64)
	PStash.ready = true
	IEX_Features.sadoStash = true
	IEX_NativeHooks_CampMerchantReady()
	return true
end

-- The camp merchant (M_PSXGM.lua) reads save files and fills its store through Windows stubs of the engine's C
-- runtime (_wfopen, fread, fseek, fclose), dimmResolveFileName and CStore::AddItem / CompressItems. On Linux IEX
-- gives it the same functions natively (PSXGM.fileReady = true skips its Windows byte checks).
local PSXGM_ENG = {
	ResolveFileName = 'IEX_Eng_ResolveFileName', wfopen = 'IEX_File_WOpen', fread = 'IEX_File_Read',
	fseek = 'IEX_File_Seek', fclose = 'IEX_File_Close', StoreAddItem = 'IEX_Eng_StoreAddItem',
	StoreCompress = 'IEX_Eng_StoreCompressItems',
}
function IEX_NativeHooks_CampMerchantReady()
	if not linux() or type(PSXGM) ~= 'table' or IEX_Features.sadoCampMerchant then return false end
	for name, fn in pairs(PSXGM_ENG) do
		if rawget(_G, 'PStash_Eng_GM_' .. name) == nil then _G['PStash_Eng_GM_' .. name] = _G[fn] end
	end
	PSXGM.fileReady = true
	IEX_Features.sadoCampMerchant = true
	IEX_Log('[IEX] SadoEE camp merchant: native file / store functions')
	return true
end
-- as soon as the stash file has run (its listeners fire after every M_*.lua), and again at game start
IEX_AddListener('MenuBeforeMainFileLoaded', function() if not IEX_Features.sadoStash then IEX_NativeHooks_StashReady() end end)
IEX_AddListener('GameStateInitialized', function() if not IEX_Features.sadoStash then IEX_NativeHooks_StashReady() end end)
IEX_AddListener('GameStateInitialized', function() IEX_NativeHooks_CampMerchantReady() end)
