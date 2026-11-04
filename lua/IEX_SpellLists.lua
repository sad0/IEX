-- Class spell lists past the SPWI/SPPR numbering (native switch "spellLists", src/core/spell_lists.cpp,
-- docs/SPELL_LIST_UNLIMITED.md).
--
-- The engine's wizard and priest class lists (chargen and level-up choices, sorcerer / bard picks, dual-class, the
-- priests' automatic spells) are SPWI<level>01.. and SPPR<level>01.., up to slot 50 (99 with spellSlots99). Each
-- list can continue with any resrefs, in this order:
--   IEXSPLST.2DA (mods APPEND rows; read when the game state is initialized):
--       2DA V1.0
--       *
--                TYPE    LEVEL
--       SPWI1AA  2       1          <- row name = spell resref; TYPE 2 / WIZARD / MAGE, 1 / PRIEST; LEVEL 1-9 / 1-7
--   IEX_SpellList_Add(type, level, resref) from a mod's M_*.lua (any time).
-- The first entry of a list turns the switch on. Spells keep the engine's own checks (file present, its level
-- matches the list's level, HIDESPL.2DA, class / kit / school / alignment flags), exactly like SPWI/SPPR slots.
--
--   IEX_SpellList_Add(type, level, resref) -> true (false: already in that list); switches the hook on
--   IEX_SpellList_Remove(type, level, resref) -> true if removed
--   IEX_SpellList_Get(type, level) -> { resref, ... }   IEX_SpellList_Count(type, level) -> n
--   IEX_SpellList_Clear([type [, level]])
--   IEX_SpellLists_Status   'off' / 'on' / reason the switch could not be installed

IEX_SpellLists_Status = 'off'

local rawAdd = IEX_SpellList_Add

local function switchOn()
	if IEX_SpellLists_Status == 'on' then return true end
	if not IEX_NativeHook_Enable then
		IEX_SpellLists_Status = 'no native hook API'
		return false
	end
	local ok, why = IEX_NativeHook_Enable('spellLists')
	IEX_SpellLists_Status = ok and 'on' or tostring(why)
	IEX_Log('[spellLists] ' .. (ok and 'switch on' or ('not installed: ' .. tostring(why))))
	return ok
end

if rawAdd then
	function IEX_SpellList_Add(type, level, resref)
		local added = rawAdd(type, level, resref)
		switchOn()
		return added
	end
end

local TYPES = { ['1'] = 1, PRIEST = 1, ['2'] = 2, WIZARD = 2, MAGE = 2 }

-- Rows of IEXSPLST.2DA in file order (a plain text read: row order is the list order). Returns the number added.
function IEX_SpellLists_Load2DA(resref)
	resref = resref or 'IEXSPLST'
	if not (IEX_ResourceText and rawAdd) then return 0 end
	local text = IEX_ResourceText(resref, 0x3F4)
	if not text then return 0 end
	local added, line = 0, 0
	for row in text:gmatch('[^\r\n]+') do
		line = line + 1
		-- line 1 signature, line 2 default value, line 3 column names
		if line > 3 then
			local res, t, lvl = row:match('^%s*(%S+)%s+(%S+)%s+(%S+)')
			local ty, lv = t and TYPES[t:upper()], tonumber(lvl)
			if res and ty and lv then
				local ok, r = pcall(rawAdd, ty, lv, res)
				if not ok then
					IEX_Log('[spellLists] ' .. resref .. '.2DA line ' .. line .. ': ' .. tostring(r))
				elseif r then
					added = added + 1
				end
			elseif row:match('%S') then
				IEX_Log('[spellLists] ' .. resref .. '.2DA line ' .. line .. ' skipped: ' .. row)
			end
		end
	end
	return added
end

IEX_AddListener('GameStateInitialized', function()
	if IEX_SpellLists_Loaded then return end
	IEX_SpellLists_Loaded = true
	local n = IEX_SpellLists_Load2DA()
	if n > 0 then
		IEX_Log('[spellLists] IEXSPLST.2DA: ' .. n .. ' entries')
		switchOn()
	end
end)
