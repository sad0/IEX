-- SpellListTest probe: IEX/slt.txt is rewritten whenever one of these numbers changes (checked every ~1 s):
-- the spellLists / spellSlots99 switch states, the IEX list sizes, and the chargen tables mageSpells[1] /
-- priestSpells[1] (built by CScreenCreateChar::ResetSpellTables) with their ZW / ZP / SPWI160 entries.
local last, tick = nil, 0

local function count(t)
	local n, zw, zp, s60 = 0, 0, 0, false
	for k in pairs(t or {}) do
		n = n + 1
		local key = tostring(k):upper()
		if key:sub(1, 2) == 'ZW' then zw = zw + 1 end
		if key:sub(1, 2) == 'ZP' then zp = zp + 1 end
		if key == 'SPWI160' then s60 = true end
	end
	return n, zw, zp, s60
end

function SLT_Report()
	local inst = IEX_NativeHook_Installed or function() return false end
	local lines = {
		'spellLists installed=' .. tostring(inst('spellLists')) .. ' status=' .. tostring(IEX_SpellLists_Status),
		'spellSlots99 installed=' .. tostring(inst('spellSlots99')),
		'IEX list wizard 1 = ' .. tostring(IEX_SpellList_Count and IEX_SpellList_Count(2, 1)),
		'IEX list priest 1 = ' .. tostring(IEX_SpellList_Count and IEX_SpellList_Count(1, 1)),
	}
	if type(mageSpells) == 'table' then
		local n, zw, _, s60 = count(mageSpells[1])
		lines[#lines + 1] = ('mageSpells[1] = %d entries, ZW = %d, SPWI160 = %s'):format(n, zw, tostring(s60))
	end
	if type(priestSpells) == 'table' then
		local n, _, zp = count(priestSpells[1])
		lines[#lines + 1] = ('priestSpells[1] = %d entries, ZP = %d'):format(n, zp)
	end
	return table.concat(lines, '\n') .. '\n'
end

if IEX_AddListener then
	IEX_AddListener('EngineTickDone', function()
		tick = tick + 1
		if tick % 30 ~= 0 then return end
		local r = SLT_Report()
		if r ~= last then
			last = r
			if IEX_WriteFile then IEX_WriteFile('slt.txt', r) end
			IEX_Log('[SLT] ' .. r:gsub('\n', ' | '))
		end
	end)
end

-- Test command channel (private test copies only): IEX/slt_cmd.lua is run about once a second, then emptied.
-- Results of SLT_Out(...) go to IEX/slt_out.txt.
local outBuf = {}
function SLT_Out(...)
	local t = {}
	for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
	outBuf[#outBuf + 1] = table.concat(t, '\t')
	if IEX_WriteFile then IEX_WriteFile('slt_out.txt', table.concat(outBuf, '\n') .. '\n') end
end
local cmdTick = 0
if IEX_AddListener and IEX_RunFile and IEX_WriteFile then
	IEX_WriteFile('slt_cmd.lua', '')
	IEX_AddListener('EngineTickDone', function()
		cmdTick = cmdTick + 1
		if cmdTick % 30 ~= 0 then return end
		IEX_RunFile('slt_cmd.lua')
		IEX_WriteFile('slt_cmd.lua', '')
	end)
end
