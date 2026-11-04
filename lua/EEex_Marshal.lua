-- EEex_Sprite_AddMarshalHandlers: per-creature mod data saved with the game (BuffBot, chriz mods).
-- The C++ side (src/core/marshal.cpp) calls IEX_Marshal_Export(sprite) whenever the engine marshals a creature
-- (save, area store, character export, creature copy) and IEX_Marshal_Import(sprite, bytes) when it rebuilds one.
--
-- Byte format, as EEex 1.3.1 writes it (observed by saving under EEex), so a
-- save moves between EEex and IEX both ways. After the "X-BIV1.0" header of the first pseudo effect record:
--   stream  = { handler name (NUL-terminated) table-body }* 0x00
--   body    = { key value }* 0x00             key, value = type byte + payload (little endian)
--   types   0x01 table (a body follows), 0x02 string (NUL-terminated), 0x03 int8, 0x04 uint8, 0x05 int16,
--           0x06 uint16, 0x07 int32, 0x08 uint32, 0x09 int64, 0x0a uint64, 0x0b false, 0x0c true
-- Integers get the smallest type that holds them. (EEex picks int8 for -129..-256, int16 for -32769..-65536 and
-- int32 for -2^31-1..-2^32, which wraps those values; IEX writes them correctly, and both read them alike.)
-- Values EEex cannot store (fractions, functions, userdata, cycles...) are left out with a log line instead of
-- breaking the whole save. Data of handlers that are not registered (mod removed) is kept for the creature and
-- written back, so a save that passes through a game without the mod does not lose it.

IEX_MarshalHandlers = IEX_MarshalHandlers or {}
IEX_MarshalOrder = IEX_MarshalOrder or {}
EEex_Sprite_Private_MarshalHandlers = IEX_MarshalHandlers
-- address -> { {name, raw body bytes}... } of handlers no mod registered
IEX_MarshalUnknown = IEX_MarshalUnknown or {}

function EEex_Sprite_AddMarshalHandlers(name, exporter, importer)
	if type(name) ~= 'string' or name == '' or name:find('\0', 1, true) then
		error('EEex_Sprite_AddMarshalHandlers: handler name must be a non-empty string', 2)
	end
	if not IEX_MarshalHandlers[name] then IEX_MarshalOrder[#IEX_MarshalOrder + 1] = name end
	IEX_MarshalHandlers[name] = { exporter = exporter, importer = importer }
end

-- (EEex's debug switch: true stops both writing and reading the data)
if rawget(_G, 'EEex_Debug_DisableExtraCreatureMarshalling') == nil then EEex_Debug_DisableExtraCreatureMarshalling = false end

EEex = EEex or {}
function EEex.IsMarshallingCopy() return IEX_IsMarshallingCopy() end

local char, byte, floor = string.char, string.byte, math.floor
local unpack = table.unpack or unpack
local warned = {}
local function warn(msg)
	if warned[msg] then return end
	warned[msg] = true
	IEX_Log('[marshal] ' .. msg)
end

-- --- Writer ---

local function le(v, n)  -- v: 0 <= v < 2^(8n), n <= 4
	local t = {}
	for i = 1, n do
		t[i] = v % 256
		v = floor(v / 256)
	end
	return char(unpack(t))
end

local function encodeInteger(v)
	if v >= 0 then
		if v <= 0xFF then return '\4' .. le(v, 1) end
		if v <= 0xFFFF then return '\6' .. le(v, 2) end
		if v <= 0xFFFFFFFF then return '\8' .. le(v, 4) end
		if v < 2 ^ 64 then
			local hi = floor(v / 2 ^ 32)
			return '\10' .. le(v - hi * 2 ^ 32, 4) .. le(hi, 4)
		end
	else
		if v >= -0x80 then return '\3' .. le(v + 0x100, 1) end
		if v >= -0x8000 then return '\5' .. le(v + 0x10000, 2) end
		if v >= -0x80000000 then return '\7' .. le(v + 0x100000000, 4) end
		if v >= -2 ^ 63 then
			local hi = floor(v / 2 ^ 32)  -- negative
			return '\9' .. le(v - hi * 2 ^ 32, 4) .. le(hi + 2 ^ 32, 4)
		end
	end
	return nil
end

local encodeTable

-- Encoded key or value, or nil (and a log line) when it cannot be stored.
local function encode(v, path, ancestors)
	local t = type(v)
	if t == 'string' then
		local nul = v:find('\0', 1, true)
		if nul then
			warn(path .. ': string cut at its NUL byte')
			v = v:sub(1, nul - 1)
		end
		return '\2' .. v .. '\0'
	elseif t == 'boolean' then
		return v and '\12' or '\11'
	elseif t == 'number' then
		if v ~= v or v == math.huge or v == -math.huge or v ~= floor(v) then
			warn(path .. ': ' .. tostring(v) .. ' is not an integer, left out')
			return nil
		end
		local s = encodeInteger(v)
		if not s then warn(path .. ': ' .. tostring(v) .. ' is out of the 64-bit range, left out') end
		return s
	elseif t == 'table' then
		if ancestors[v] then
			warn(path .. ': table contains itself, left out')
			return nil
		end
		return '\1' .. encodeTable(v, path, ancestors)
	end
	warn(path .. ': a ' .. t .. ' cannot be saved, left out')
	return nil
end

-- Body of a table, keys sorted (booleans, numbers, strings) so the bytes do not depend on traversal order.
local KEY_TYPES = { boolean = true, number = true, string = true }
local function keyLess(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta < tb end
	if ta == 'boolean' then return (not a) and b end
	return a < b
end

encodeTable = function(t, path, ancestors)
	ancestors[t] = true
	local keys = {}
	for k in pairs(t) do
		if KEY_TYPES[type(k)] then
			keys[#keys + 1] = k
		else
			warn(path .. ': a ' .. type(k) .. ' key cannot be saved, left out')
		end
	end
	table.sort(keys, keyLess)
	local parts = {}
	for _, k in ipairs(keys) do
		local kpath = path .. '.' .. tostring(k)
		local ek = encode(k, kpath, ancestors)
		local ev = ek and encode(t[k], kpath, ancestors)
		if ev then
			parts[#parts + 1] = ek
			parts[#parts + 1] = ev
		end
	end
	ancestors[t] = nil
	parts[#parts + 1] = '\0'
	return table.concat(parts)
end

-- --- Reader ---

local function readU(s, pos, n)
	local v = 0
	for i = n - 1, 0, -1 do v = v * 256 + byte(s, pos + i) end
	return v
end

local SIZES = { [3] = 1, [4] = 1, [5] = 2, [6] = 2, [7] = 4, [8] = 4, [9] = 8, [10] = 8 }

local decodeBody

-- Returns value, next position (errors on a truncated stream).
local function decode(s, pos)
	local tag = byte(s, pos)
	if not tag then error('truncated') end
	pos = pos + 1
	if tag == 1 then return decodeBody(s, pos) end
	if tag == 2 then
		local e = s:find('\0', pos, true)
		if not e then error('unterminated string') end
		return s:sub(pos, e - 1), e + 1
	end
	if tag == 11 then return false, pos end
	if tag == 12 then return true, pos end
	local n = SIZES[tag]
	if not n then error('unknown type ' .. tag) end
	if pos + n - 1 > #s then error('truncated') end
	local v
	if n == 8 then
		local lo, hi = readU(s, pos, 4), readU(s, pos + 4, 4)
		if tag == 9 and hi >= 2 ^ 31 then hi = hi - 2 ^ 32 end
		v = hi * 2 ^ 32 + lo
	else
		v = readU(s, pos, n)
		if tag % 2 == 1 and v >= 2 ^ (8 * n - 1) then v = v - 2 ^ (8 * n) end  -- 3, 5, 7: signed
	end
	return v, pos + n
end

decodeBody = function(s, pos)
	local t = {}
	while true do
		local tag = byte(s, pos)
		if not tag then error('truncated') end
		if tag == 0 then return t, pos + 1 end
		local k, v
		k, pos = decode(s, pos)
		v, pos = decode(s, pos)
		t[k] = v
	end
end

-- --- Engine side ---

function IEX_Marshal_Export(sprite)
	if EEex_Debug_DisableExtraCreatureMarshalling then return nil end
	local address = IEX_Address(sprite)
	local parts = {}
	for _, name in ipairs(IEX_MarshalOrder) do
		local h = IEX_MarshalHandlers[name]
		if h and type(h.exporter) == 'function' then
			local ok, data = pcall(h.exporter, sprite)
			if not ok then
				warn(name .. ' exporter failed: ' .. tostring(data))
			elseif type(data) == 'table' then
				local okE, body = pcall(encodeTable, data, name, {})
				if okE then
					parts[#parts + 1] = name .. '\0' .. body
				else
					warn(name .. ': ' .. tostring(body))
				end
			end
		end
	end
	for _, u in ipairs(IEX_MarshalUnknown[address] or {}) do
		if not IEX_MarshalHandlers[u[1]] then parts[#parts + 1] = u[1] .. '\0' .. u[2] end
	end
	if #parts == 0 then return nil end
	parts[#parts + 1] = '\0'
	return table.concat(parts)
end

-- bytes: the stream after the header, padding included (nil: the creature has no handler data).
function IEX_Marshal_Import(sprite, bytes)
	local address = IEX_Address(sprite)
	IEX_MarshalUnknown[address] = nil
	if not bytes or EEex_Debug_DisableExtraCreatureMarshalling then return end
	local pos, unknown = 1, nil
	while pos <= #bytes do
		local e = bytes:find('\0', pos, true)
		if not e or e == pos then break end  -- empty name: end of the stream
		local name = bytes:sub(pos, e - 1)
		local ok, body, nextPos = pcall(decodeBody, bytes, e + 1)
		if not ok then
			warn('unreadable data of handler ' .. name .. ': ' .. tostring(body))
			break
		end
		local h = IEX_MarshalHandlers[name]
		if h then
			if type(h.importer) == 'function' then
				local okI, err = pcall(h.importer, sprite, body)
				if not okI then warn(name .. ' importer failed: ' .. tostring(err)) end
			end
		else
			unknown = unknown or {}
			unknown[#unknown + 1] = { name, bytes:sub(e + 1, nextPos - 1) }
		end
		pos = nextPos
	end
	IEX_MarshalUnknown[address] = unknown
end
