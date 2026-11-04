-- EEex-compatible effects and script extensions (C++ side: src/core/opcodes.cpp).

-- A sprite's effect lists have just been re-evaluated (stats rebuilt from its effects). fn(sprite).
function EEex_Opcode_AddListsResolvedListener(fn) IEX_AddListener('OpcodeListsResolved', fn) end

-- Builds an effect from the table's fields (effectID, effectAmount, dwFlags, res, durationType, duration,
-- sourceID, sourceTarget, m_sourceRes...) and adds it to the creature.
function EEex_GameObject_ApplyEffect(object, args) IEX_ApplyEffect(object, args) end
if CGameSprite then
	function CGameSprite.applyEffect(sprite, args) IEX_ApplyEffect(sprite, args) end
end

-- Extended stats (opcode 401, ids > 202 from X-STATS.2DA) through the usual stat getter.
do
	local getStat = EEex_Sprite_GetStat
	function EEex_Sprite_GetStat(sprite, stat)
		if stat and stat > 202 then
			local value = IEX_GetExtendedStat(sprite, stat)
			if value ~= nil then return value end
		end
		return getStat(sprite, stat)
	end
	if CGameSprite then
		function CGameSprite.getStat(sprite, stat) return EEex_Sprite_GetStat(sprite, stat) end
	end
end

-- First extended stat id: ids from here on are X-STATS.2DA stats (opcode 401), below are STATS.IDS ones.
EEex_Stats_FirstExtendedStatID = 203

-- Value of an extended stat (its X-STATS.2DA default when no effect sets it, 0 for an undefined id).
function EEex_Sprite_GetExtendedStat(sprite, stat)
	return IEX_GetExtendedStat(sprite, stat) or 0
end

-- Any stat id, normal or extended.
function EEex_Sprite_GetAnyStat(sprite, stat)
	if stat < EEex_Stats_FirstExtendedStatID then return EEex_Sprite_GetStat(sprite, stat) end
	return EEex_Sprite_GetExtendedStat(sprite, stat)
end
if CGameSprite then
	function CGameSprite.getExtendedStat(sprite, stat) return EEex_Sprite_GetExtendedStat(sprite, stat) end
	function CGameSprite.getAnyStat(sprite, stat) return EEex_Sprite_GetAnyStat(sprite, stat) end
end

-- Where a projectile / its effects came from (values passed to projectile mutators; numbers as under EEex 1.3.1).
EEex_Projectile_DecodeSource = {
	CBounceList_Add = 1, CGameAIBase_FireItem = 2, CGameAIBase_FireItemPoint = 3, CGameAIBase_FireSpell = 4,
	CGameAIBase_FireSpellPoint = 5, CGameAIBase_ForceSpell = 6, CGameAIBase_ForceSpellPoint = 7,
	CGameEffect_FireSpell = 8, CGameEffectCastingGlow_ApplyEffect = 9, CGameEffectChangeStatic_ApplyEffect = 10,
	CGameEffectSummon_ApplyVisualEffect = 11, CGameEffectVisualSpellHitIWD_ApplyEffect = 12, CGameSprite_Spell = 13,
	CGameSprite_SpellPoint = 14, CGameSprite_Swing = 15, CGameSprite_UpdateAOE = 16, CGameSprite_UseItem = 17,
	CGameSprite_UseItemPoint = 18, CMessageFireProjectile_Run = 19, CProjectile_DecodeProjectile_MultiMagicMissile = 20,
	CProjectile_DecodeProjectile_ChainCallLightning = 21, CProjectile_DecodeProjectile_MultiProjectile = 22,
	CProjectileArea_CreateSecondary = 23, CProjectileArea_Explode = 24, CProjectileChain_AIUpdate = 25,
	CProjectileChain_Fire = 26, CProjectileFall_AIUpdate = 27,
}
EEex_Projectile_AddEffectSource = {
	CBounceList_Add = 1, CGameAIBase_FireItem = 2, CGameAIBase_FireItemPoint = 3, CGameAIBase_FireSpell = 4,
	CGameAIBase_FireSpellPoint = 5, CGameAIBase_ForceSpell = 6, CGameAIBase_ForceSpellPoint = 7,
	CGameEffect_FireSpell = 8, CGameSprite_LoadProjectile = 9, CGameSprite_Spell = 10, CGameSprite_SpellPoint = 11,
	CGameSprite_Swing = 12, CGameSprite_UseItem = 13, CGameSprite_UseItemPoint = 14,
}
-- Projectile classes, one bit each (EEex_Projectile_IsOfType tests a class and its derived classes).
EEex_Projectile_Type = {
	Unknown = 0x1, CProjectile = 0x2, CProjectileAmbiant = 0x4, CProjectileArea = 0x8, CProjectileBAM = 0x10,
	CProjectileChain = 0x20, CProjectileColorSpray = 0x40, CProjectileConeOfCold = 0x80, CProjectileFall = 0x100,
	CProjectileFireHands = 0x200, CProjectileInstant = 0x400, CProjectileMulti = 0x800, CProjectileMushroom = 0x1000,
	CProjectileNewScorcher = 0x2000, CProjectileScorcher = 0x4000, CProjectileSegment = 0x8000,
	CProjectileSkyStrike = 0x10000, CProjectileSkyStrikeBAM = 0x20000, CProjectileSpellHit = 0x40000,
	CProjectileTravelDoor = 0x80000,
}

-- Script levels (SCRLEV.IDS: 0 OVERRIDE, 1 AREA, 2 SPECIFICS, 4 CLASS, 5 RACE, 6 GENERAL, 7 DEFAULT).
function EEex_AIBase_GetScriptLevelResRef(aiBase, level) return IEX_GetScriptLevelResRef(aiBase, level) end
function EEex_AIBase_SetScriptLevelResRef(aiBase, level, resref, bPlayerScript)
	IEX_SetScriptLevelResRef(aiBase, level, resref or '', bPlayerScript and true or false)
end
for _, class in ipairs({ CGameAIBase or false, CGameSprite or false }) do
	if class then
		class.getScriptLevelResRef = EEex_AIBase_GetScriptLevelResRef
		class.setScriptLevelResRef = EEex_AIBase_SetScriptLevelResRef
	end
end

-- Script trigger EEex_LuaTrigger("chunk") and action EEex_LuaAction("chunk"): the chunk runs with
-- EEex_LuaTrigger_Object / EEex_LuaAction_Object set to the script's object. Compiled chunks are cached.
local chunkCache = {}
local function compile(chunk)
	local fn = chunkCache[chunk]
	if fn == nil then
		local err
		fn, err = load(chunk, '=EEex_Lua')
		if not fn then
			IEX_Log('EEex Lua chunk does not compile: ' .. tostring(err) .. ' in ' .. chunk)
			fn = false
		end
		chunkCache[chunk] = fn
	end
	return fn
end

function IEX_Opcode_LuaTrigger(chunk, object)
	local fn = compile(chunk)
	if not fn then return false end
	local previous = rawget(_G, 'EEex_LuaTrigger_Object')
	EEex_LuaTrigger_Object = object
	local ok, result = pcall(fn)
	EEex_LuaTrigger_Object = previous
	if not ok then
		IEX_Log('Error in EEex_LuaTrigger: ' .. tostring(result))
		return false
	end
	return result and true or false
end

function IEX_Opcode_LuaAction(chunk, object)
	local fn = compile(chunk)
	if not fn then return end
	local previous = rawget(_G, 'EEex_LuaAction_Object')
	EEex_LuaAction_Object = object
	local ok, err = pcall(fn)
	EEex_LuaAction_Object = previous
	if not ok then IEX_Log('Error in EEex_LuaAction: ' .. tostring(err)) end
end
