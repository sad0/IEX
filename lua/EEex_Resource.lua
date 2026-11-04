-- EEex-compatible resource API: typed file headers (ITM / SPL / EFF), item and spell abilities, 2DA tables and IDS
-- lists. Built on IEX_ResourceData / IEX_ResourceText (src/core/lua_resources.cpp); 2DA and IDS files are parsed
-- here from their text (IESDP formats), so their objects are plain Lua tables, not engine C2DArray / CAIIdList.

-- Resource type codes of the Infinity Engine resource manager, by file extension.
local resourceTypes = {
	BMP = 0x001, MVE = 0x002, WAV = 0x004, WFX = 0x005, PLT = 0x006, BAM = 0x3E8, WED = 0x3E9, CHU = 0x3EA,
	TIS = 0x3EB, MOS = 0x3EC, ITM = 0x3ED, SPL = 0x3EE, BCS = 0x3EF, IDS = 0x3F0, CRE = 0x3F1, ARE = 0x3F2,
	DLG = 0x3F3, ['2DA'] = 0x3F4, GAM = 0x3F5, STO = 0x3F6, WMP = 0x3F7, EFF = 0x3F8, BS = 0x3F9, CHR = 0x3FA,
	VVC = 0x3FB, VEF = 0x3FC, PRO = 0x3FD, BIO = 0x3FE, WBM = 0x3FF, FNT = 0x400, GUI = 0x402, SQL = 0x403,
	PVRZ = 0x404, GLSL = 0x405, TOT = 0x406, TOH = 0x407, MENU = 0x408, LUA = 0x409, TTF = 0x40A, PNG = 0x40B,
}

function EEex_Resource_ExtToType(ext)
	return ext and resourceTypes[string.upper(ext)] or nil
end

-- Engine type used for each typed header. EFF: the file is the EFF V2 record, laid out like the CGameEffect
-- fields from +0x8 on (+0x10 opcode, +0x30 resource...), so the data is read through the CGameEffect type.
local headerTypes = { ITM = 'Item_Header_st', SPL = 'Spell_Header_st', EFF = 'CGameEffect', STO = 'CStoreFileHeader' }

local demanded = {}

-- (resref, ext) -> typed header object (ITM, SPL, EFF; STO when the engine description has the type),
-- the data address for other types, nil when the resource does not exist.
-- Like EEex, a missing resource gives no value at all (select('#', ...) == 0).
function EEex_Resource_Demand(resref, ext)
	if type(resref) ~= 'string' or resref == '' or type(ext) ~= 'string' then return end
	local upperExt = string.upper(ext)
	local key = string.upper(resref) .. '.' .. upperExt
	local cached = demanded[key]
	if cached ~= nil then return cached end
	local resType = resourceTypes[upperExt]
	if not resType then return end
	local address = IEX_ResourceData(resref, resType)
	if not address then return end
	local result = address
	local typeName = headerTypes[upperExt]
	if typeName then
		local ok, object = pcall(IEX_ToObject, address, typeName)
		if ok then result = object end
	end
	demanded[key] = result
	return result
end

-- (resref, ext) -> the resource object: for ITM / SPL, as EEex, an object with pHeader (the typed header),
-- pAbilities (first Item_ability_st / Spell_ability_st) and pEffects (first Item_effect_st of the file); header
-- fields also read through it. Other types: same as Demand (IEX keeps every demanded resource loaded).
local fetched = {}
local resObjectTypes = { ITM = 'Item_ability_st', SPL = 'Spell_ability_st' }
function EEex_Resource_Fetch(resref, ext)
	local header = EEex_Resource_Demand(resref, ext)
	local abilityType = type(ext) == 'string' and resObjectTypes[string.upper(ext)]
	if header == nil or not abilityType or type(header) == 'number' then return header end
	local key = string.upper(resref) .. '.' .. string.upper(ext)
	local res = fetched[key]
	if res then return res end
	local base = IEX_Address(header)
	local function at(field, typeName)
		local ok, v = pcall(function() return IEX_ToObject(base + header[field], typeName) end)
		return ok and v or nil
	end
	res = setmetatable({
		pHeader = header,
		pAbilities = at('abilityOffset', abilityType),
		pEffects = at('effectsOffset', 'Item_effect_st'),
	}, { __index = function(_, k) return header[k] end })
	fetched[key] = res
	return res
end

-- --- Abilities ---

local function headerAbility(header, index, size, typeName)
	if not header or type(index) ~= 'number' or index < 0 or index >= header.abilityCount then return end
	return IEX_ToObject(IEX_Address(header) + header.abilityOffset + index * size, typeName)
end

-- (itemHeader, index) -> Item_ability_st, nil when out of range.
function EEex_Resource_GetItemAbility(header, index)
	return headerAbility(header, index, 0x38, 'Item_ability_st')
end
EEex_Resource_GetCItemAbility = EEex_Resource_GetItemAbility

-- (spellHeader, index) -> Spell_ability_st, nil when out of range.
function EEex_Resource_GetSpellAbility(header, index)
	return headerAbility(header, index, 0x28, 'Spell_ability_st')
end

-- (spellHeader, casterLevel) -> the ability with the highest minimum level not above casterLevel; nil when the
-- level is below all of them (as EEex: IUI++ and BuffBot then fall back to ability 0 themselves).
function EEex_Resource_GetSpellAbilityForLevel(header, casterLevel)
	if not header or header.abilityCount == 0 then return nil end
	local best = nil
	for i = 0, header.abilityCount - 1 do
		local ability = EEex_Resource_GetSpellAbility(header, i)
		if ability.minCasterLevel <= casterLevel then best = ability end
	end
	return best
end

-- Header methods mods call on what EEex_Resource_Demand returns (BuffBot's classifier and test suite, IUI++'s
-- timed effect list, Spell Menu Extended): header:getAbility(index), spellHeader:getAbilityForLevel(level).
Spell_Header_st = Spell_Header_st or {}
function Spell_Header_st.getAbility(header, index) return EEex_Resource_GetSpellAbility(header, index) end
function Spell_Header_st.getAbilityForLevel(header, casterLevel)
	return EEex_Resource_GetSpellAbilityForLevel(header, casterLevel)
end
Item_Header_st = Item_Header_st or {}
function Item_Header_st.getAbility(header, index) return EEex_Resource_GetItemAbility(header, index) end

-- --- 2DA tables ---

local function splitLines(text)
	local lines = {}
	for line in string.gmatch(text .. '\n', '([^\n]*)\n') do
		lines[#lines + 1] = string.gsub(line, '\r$', '')
	end
	return lines
end

local function tokens(line)
	local out = {}
	for token in string.gmatch(line, '%S+') do out[#out + 1] = token end
	return out
end

local Array2DA = {}
Array2DA.__index = Array2DA

-- 2DA text, read like the engine's C2DArray::Load: line 1 signature ("2DA V1.0"), line 2 the default value (the
-- whole trimmed line), line 3 the column labels, then one line per row (label, then values). Labels are stored
-- upper case. The table is (column labels + 1) cells wide: the extra column has an empty label, and every cell a
-- row does not fill is "" (not the default). Tabs count as spaces.
local function parse2DA(name, text)
	local array = setmetatable({ name = name, default = '', columns = {}, rows = {}, cells = {},
		columnIndex = {}, rowIndex = {}, sizeX = 1 }, Array2DA)
	if not text then return array end
	local lines = splitLines(string.gsub(text, '\t', ' '))
	array.default = string.match(lines[2] or '', '^%s*(.-)%s*$')
	local labels = tokens(lines[3] or '')
	for x, label in ipairs(labels) do
		local upper = string.upper(label)
		array.columns[x] = upper
		if array.columnIndex[upper] == nil then array.columnIndex[upper] = x - 1 end
	end
	array.sizeX = #labels + 1
	array.columns[array.sizeX] = ''
	if array.columnIndex[''] == nil then array.columnIndex[''] = array.sizeX - 1 end
	for j = 4, #lines do
		local line = lines[j]
		-- the engine counts the rows that start with a label (no leading space)
		if line ~= '' and not string.find(line, '^ ') then
			local t = tokens(line)
			if t[1] then
				local y = #array.rows + 1
				local upper = string.upper(t[1])
				array.rows[y] = upper
				if array.rowIndex[upper] == nil then array.rowIndex[upper] = y - 1 end
				local row = {}
				for x = 2, math.min(#t, array.sizeX + 1) do row[x - 1] = t[x] end
				array.cells[y] = row
			end
		end
	end
	return array
end

local loaded2DA = {}

-- (resref) -> 2DA object. A missing file gives an empty table (every lookup returns the default).
function EEex_Resource_Load2DA(resref)
	local key = string.upper(tostring(resref))
	local array = loaded2DA[key]
	if array then return array end
	local text = IEX_ResourceText(key, resourceTypes['2DA'])
	if not text then IEX_Log('EEex_Resource_Load2DA: ' .. key .. '.2DA not found') end
	array = parse2DA(key, text)
	loaded2DA[key] = array
	return array
end

-- Columns count the row-label column (x = data columns + 1); rows exclude the column-label line.
function Array2DA:getDimensions() return self.sizeX, #self.rows end
-- Highest data column index (the extra empty column is not counted) and highest row index, as EEex returns them.
function Array2DA:getMaxIndices() return self.sizeX - 2, #self.rows - 1 end
function Array2DA:getDefault() return self.default end
-- Out of range labels are "" (EEex), not the default value.
function Array2DA:getColumnLabel(x) return self.columns[(tonumber(x) or -1) + 1] or '' end
function Array2DA:getRowLabel(y) return self.rows[(tonumber(y) or -1) + 1] or '' end
function Array2DA:free() end

-- (columnIndex, rowIndex), 0-based over the data cells; out of range -> default, an unfilled cell -> "".
function Array2DA:getAtPoint(x, y)
	x, y = tonumber(x), tonumber(y)
	if not x or not y or x < 0 or y < 0 or x >= self.sizeX or y >= #self.rows then return self.default end
	return self.cells[y + 1][x + 1] or ''
end

function Array2DA:getAtLabels(columnLabel, rowLabel)
	local x = self.columnIndex[string.upper(tostring(columnLabel))]
	local y = self.rowIndex[string.upper(tostring(rowLabel))]
	if not x or not y then return self.default end
	return self:getAtPoint(x, y)
end

function Array2DA:findColumnLabel(label) return self.columnIndex[string.upper(tostring(label))] or -1 end
function Array2DA:findRowLabel(label) return self.rowIndex[string.upper(tostring(label))] or -1 end

-- (rowIndex, toSearchFor) -> first column of the row holding that value (case ignored), -1 if none. toSearchFor
-- must be a string (EEex indexes it: a nil value is an error).
function Array2DA:findColumnIndex(y, toSearchFor)
	local wanted = toSearchFor:upper()
	for x = 0, self.sizeX - 1 do
		if string.upper(self:getAtPoint(x, y)) == wanted then return x end
	end
	return -1
end

-- (columnIndex, toSearchFor) -> first row of the column holding that value (case ignored), -1 if none.
function Array2DA:findRowIndex(x, toSearchFor)
	local wanted = toSearchFor:upper()
	for y = 0, #self.rows - 1 do
		if string.upper(self:getAtPoint(x, y)) == wanted then return y end
	end
	return -1
end

-- fn(i, value) for each value of a column / row; fn returning true stops.
function Array2DA:iterateColumnIndex(x, fn)
	for y = 0, #self.rows - 1 do
		if fn(y, self:getAtPoint(x, y)) then return end
	end
end
function Array2DA:iterateColumnLabel(label, fn)
	local x = self.columnIndex[string.upper(tostring(label))]
	if x then self:iterateColumnIndex(x, fn) end
end
function Array2DA:iterateRowIndex(y, fn)
	for x = 0, self.sizeX - 1 do
		if fn(x, self:getAtPoint(x, y)) then return end
	end
end
function Array2DA:iterateRowLabel(label, fn)
	local y = self.rowIndex[string.upper(tostring(label))]
	if y then self:iterateRowIndex(y, fn) end
end

-- Iterator over the rows from startRow (nil = 0), returning the values of the given columns for each row.
function Array2DA:getRowColumnsItr(startRow, ...)
	local columns = { ... }
	local y = (tonumber(startRow) or 0) - 1
	return function()
		y = y + 1
		if y >= #self.rows then return nil end
		local values = {}
		for i, x in ipairs(columns) do values[i] = self:getAtPoint(x, y) end
		return table.unpack(values, 1, #columns)
	end
end

-- Same with column labels.
function Array2DA:getRowColumnsByLabelItr(startRow, ...)
	local columns = {}
	for i, label in ipairs({ ... }) do columns[i] = self:findColumnLabel(label) end
	return self:getRowColumnsItr(startRow, table.unpack(columns))
end

-- Iterator over the values of one row.
function Array2DA:getRowValuesItr(y)
	local x = -1
	return function()
		x = x + 1
		if x >= self.sizeX then return nil end
		return self:getAtPoint(x, y)
	end
end

-- Iterator over the rows from startRow (nil = 0), returning each row's values as an array (one per column label,
-- in column order), like EEex.
function Array2DA:getRowTableItr(startRow)
	local y = (tonumber(startRow) or 0) - 1
	return function()
		y = y + 1
		if y >= #self.rows then return nil end
		local row = {}
		for x = 1, self.sizeX - 1 do row[x] = self:getAtPoint(x - 1, y) end
		return row
	end
end

Array2DA.getRowColumnsIterator = Array2DA.getRowColumnsItr
Array2DA.getRowColumnsByLabelIterator = Array2DA.getRowColumnsByLabelItr
Array2DA.getRowValuesIterator = Array2DA.getRowValuesItr
Array2DA.getRowTableIterator = Array2DA.getRowTableItr

-- EEex_Resource_<Name>(array, ...) = array:<method>(...)
local arrayFunctions = {
	Free2DA = 'free', Get2DADimensions = 'getDimensions', GetMax2DAIndices = 'getMaxIndices',
	Get2DADefault = 'getDefault', Get2DAColumnLabel = 'getColumnLabel', Get2DARowLabel = 'getRowLabel',
	GetAt2DAPoint = 'getAtPoint', GetAt2DALabels = 'getAtLabels', Find2DAColumnLabel = 'findColumnLabel',
	Find2DARowLabel = 'findRowLabel', Find2DAColumnIndex = 'findColumnIndex', Find2DARowIndex = 'findRowIndex',
	Iterate2DAColumnIndex = 'iterateColumnIndex', Iterate2DAColumnLabel = 'iterateColumnLabel',
	Iterate2DARowIndex = 'iterateRowIndex', Iterate2DARowLabel = 'iterateRowLabel',
	Get2DARowColumnsIterator = 'getRowColumnsItr', Get2DARowColumnsByLabelIterator = 'getRowColumnsByLabelItr',
	Get2DARowValuesIterator = 'getRowValuesItr', Get2DARowTableIterator = 'getRowTableItr',
}
for name, method in pairs(arrayFunctions) do
	_G['EEex_Resource_' .. name] = function(array, ...)
		if not array then return nil end
		return Array2DA[method](array, ...)
	end
end

-- --- IDS lists ---

local IdList = {}
IdList.__index = IdList

-- IDS text: optional header lines ("IDS V1.0", an entry count), then "<value> <symbol>" lines; values are
-- decimal or 0x hex. The first entry of a value wins for lookups by value.
local function parseIDS(name, text)
	local list = setmetatable({ name = name, entries = {}, byId = {} }, IdList)
	if not text then return list end
	for _, line in ipairs(splitLines(text)) do
		local value, symbol = string.match(line, '^%s*(%S+)%s+(.-)%s*$')
		local id = value and tonumber(value)
		if id and symbol ~= '' then
			local entry = { id = id, line = symbol, start = string.match(symbol, '^([^(]*)') }
			list.entries[#list.entries + 1] = entry
			if list.byId[id] == nil then list.byId[id] = entry end
		end
	end
	return list
end

local loadedIDS = {}

-- (resref, cacheAsArray) -> IDS object. Lookups by value are always hashed here, so cacheAsArray only changes
-- getCount (max id + 1 instead of the entry count). A missing file gives an empty list.
function EEex_Resource_LoadIDS(resref, cacheAsArray)
	local key = string.upper(tostring(resref))
	local list = loadedIDS[key]
	if not list then
		local text = IEX_ResourceText(key, resourceTypes.IDS)
		if not text then IEX_Log('EEex_Resource_LoadIDS: ' .. key .. '.IDS not found') end
		list = parseIDS(key, text)
		loadedIDS[key] = list
	end
	if cacheAsArray then
		local view = setmetatable({ cacheAsArray = true }, { __index = list })
		return view
	end
	return list
end

local function entryObject(entry)
	if not entry then return nil end
	local line = { get = function() return entry.line end }
	local start = { get = function() return entry.start end }
	return { m_id = entry.id, m_line = line, m_start = start }
end

function IdList:getCount()
	if self.cacheAsArray then
		local max = -1
		for id in pairs(self.byId) do if id > max then max = id end end
		return max + 1
	end
	return #self.entries
end
function IdList:hasID(id) return self.byId[id] ~= nil end
function IdList:getEntry(id) return entryObject(self.byId[id]) end
function IdList:getLine(id) local e = self.byId[id] return e and e.line end
function IdList:getStart(id) local e = self.byId[id] return e and e.start end
function IdList:free() end

-- fn(entry) / fn(id, line, start) for each entry in file order; fn returning true stops.
function IdList:iterateEntries(func)
	for _, e in ipairs(self.entries) do
		if func(entryObject(e)) then return end
	end
end
function IdList:iterateUnpackedEntries(func)
	for _, e in ipairs(self.entries) do
		if func(e.id, e.line, e.start) then return end
	end
end

-- Symbol -> value (first entry with that symbol, without case).
function IdList:findSymbol(symbol)
	if not self.bySymbol then
		self.bySymbol = {}
		for _, e in ipairs(self.entries) do
			local upper = string.upper(e.line)
			if self.bySymbol[upper] == nil then self.bySymbol[upper] = e.id end
		end
	end
	return symbol and self.bySymbol[string.upper(symbol)]
end

local idsFunctions = {
	FreeIDS = 'free', GetIDSCount = 'getCount', GetIDSEntry = 'getEntry', GetIDSLine = 'getLine',
	GetIDSStart = 'getStart', IDSHasID = 'hasID', IterateIDSEntries = 'iterateEntries',
	IterateUnpackedIDSEntries = 'iterateUnpackedEntries',
}
for name, method in pairs(idsFunctions) do
	_G['EEex_Resource_' .. name] = function(list, ...)
		if not list then return nil end
		return IdList[method](list, ...)
	end
end

-- KIT.IDS lookups. A kit value with the kit in the high word (0x4001xxxx, as stored in CRE files) is also tried
-- with its words swapped.
function EEex_Resource_KitIDSToSymbol(kit)
	if type(kit) ~= 'number' then return nil end
	local list = EEex_Resource_LoadIDS('KIT')
	local symbol = list:getLine(kit)
	if not symbol and kit > 0xFFFF then
		symbol = list:getLine((kit % 0x10000) * 0x10000 + math.floor(kit / 0x10000) % 0x10000)
	end
	return symbol
end

function EEex_Resource_KitSymbolToIDS(symbol)
	return EEex_Resource_LoadIDS('KIT'):findSymbol(symbol)
end

-- ITEMCAT.IDS lookups (item type of an ITM header).
function EEex_Resource_ItemCategoryIDSToSymbol(category)
	return EEex_Resource_LoadIDS('ITEMCAT'):getLine(category)
end

function EEex_Resource_ItemCategorySymbolToIDS(symbol)
	return EEex_Resource_LoadIDS('ITEMCAT'):findSymbol(symbol)
end
