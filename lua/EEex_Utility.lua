-- EEex-compatible utility functions: bits, errors, per-object Lua data, casts, scopes and iterator combinators.

-- --- Bits (bit numbers start at 0; masks are tested whole) ---

function EEex_IsBitSet(value, bit) return bit32.band(value, bit32.lshift(1, bit)) ~= 0 end
function EEex_IsBitUnset(value, bit) return bit32.band(value, bit32.lshift(1, bit)) == 0 end
function EEex_SetBit(value, bit) return bit32.bor(value, bit32.lshift(1, bit)) end
function EEex_UnsetBit(value, bit) return bit32.band(value, bit32.bnot(bit32.lshift(1, bit))) end
function EEex_IsMaskSet(value, mask) return bit32.band(value, mask) == mask end
function EEex_IsMaskUnset(value, mask) return bit32.band(value, mask) == 0 end
function EEex_SetMask(value, mask) return bit32.bor(value, mask) end
function EEex_UnsetMask(value, mask) return bit32.band(value, bit32.bnot(mask)) end

-- --- Errors ---

function EEex_Error(message)
	error(message, 2)
end

-- How a table-to-struct writer treats a missing key: raise an error, use the given default, or leave the field.
EEex_WriteFailType = EEex_WriteFailType or { ERROR = 0, DEFAULT = 1, NOTHING = 2 }

-- --- Game objects ---

local STATE_DEAD = 0x800

-- True for a creature object; dead creatures count only when allowDead is true.
function EEex_GameObject_IsSprite(object, allowDead)
	if not object or object.m_objectType ~= 0x31 then return false end
	if allowDead then return true end
	local sprite = EEex_GameObject_CastUserType(object)
	return bit32.band(sprite.m_derivedStats.m_generalState, STATE_DEAD) == 0
end

-- Per-object Lua table, kept for the object's address (mods store their own state there).
IEX_UDAux = IEX_UDAux or {}
function EEex_GetUDAux(object)
	local address = IEX_Address(object)
	local aux = IEX_UDAux[address]
	if not aux then
		aux = {}
		IEX_UDAux[address] = aux
	end
	return aux
end

function EEex_DeleteUDAux(object)
	IEX_UDAux[IEX_Address(object)] = nil
end

-- Views the memory of an object (or an address) as another engine type. Value types that have no struct of
-- their own (CResRef, CString, char[]) come back as field handles with :get() / :set().
local valueViews = { CResRef = 'IEX_ResRefView', CString = 'IEX_CStringView' }

function EEex_CastUD(object, typeName)
	local address = type(object) == 'number' and object or IEX_Address(object)
	local view = valueViews[typeName]
	if view then
		local holder = IEX_ToObject(address, view)
		return holder and holder.value
	end
	return IEX_ToObject(address, typeName)
end

-- Runs fn in its own scope (locals declared inside stay inside).
function EEex_Utility_NewScope(fn)
	return fn()
end

-- --- Iterator combinators (iterators are plain Lua iterator functions) ---

-- Keeps the values for which predicate(...) is true.
function EEex_Utility_FilterItr(itr, predicate)
	return function()
		while true do
			local values = table.pack(itr())
			if values[1] == nil then return nil end
			if predicate(table.unpack(values, 1, values.n)) then return table.unpack(values, 1, values.n) end
		end
	end
end

-- Replaces each set of values by fn(...).
function EEex_Utility_ApplyItr(itr, fn)
	return function()
		local values = table.pack(itr())
		if values[1] == nil then return nil end
		return fn(table.unpack(values, 1, values.n))
	end
end
EEex_Utility_MutateItr = EEex_Utility_ApplyItr

-- Keeps the values from position n on, like select(n, ...).
function EEex_Utility_SelectItr(n, itr)
	return function()
		local values = table.pack(itr())
		if values[1] == nil then return nil end
		return select(n, table.unpack(values, 1, values.n))
	end
end

-- Runs the iterators one after the other.
function EEex_Utility_ChainItrs(...)
	local itrs = { ... }
	local i = 1
	return function()
		while itrs[i] do
			local values = table.pack(itrs[i]())
			if values[1] ~= nil then return table.unpack(values, 1, values.n) end
			i = i + 1
		end
		return nil
	end
end

-- Iterates a Lua array.
function EEex_Utility_IterateArray(array)
	local i = 0
	return function()
		i = i + 1
		return array[i]
	end
end

-- --- Once per session ---

-- Runs fn() the first time `key` is seen during this game session; later calls with the same key (a UI reload
-- running the mod's file again) do nothing. Returns true when fn ran.
IEX_OnceKeys = IEX_OnceKeys or {}
function EEex_Once(key, fn)
	if IEX_OnceKeys[key] then return false end
	IEX_OnceKeys[key] = true
	fn()
	return true
end

-- Table keyed by the n-th value of every iteration (e.g. the resrefs of a known-spells iterator), each set to
-- true: a set to test membership in.
function EEex_Utility_MapItrValues(n, itr)
	local out = {}
	for v in EEex_Utility_SelectItr(n, itr) do
		if v ~= nil then out[v] = true end
	end
	return out
end

-- Runs fn(), then finally() whether fn raised an error or not; the error, if any, is raised again afterwards.
-- Returns what fn returned.
function EEex_Utility_TryFinally(fn, finally)
	local result = table.pack(pcall(fn))
	if finally then finally() end
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end

-- Debug print prefixed with the calling function's name (IEX.log).
function EEex_FunctionLog(message)
	local info = debug and debug.getinfo and debug.getinfo(2, 'n')
	IEX_Log('[' .. tostring(info and info.name or '?') .. '] ' .. tostring(message))
end

-- --- Tables ---

-- One level of flattening: the array items of every table element in order, other elements kept as they are
-- ({{1, 2}, {3}} -> {1, 2, 3}). Assembly builders pass it lists of code parts.
function EEex_FlattenTable(t)
	local out = {}
	for _, v in ipairs(t) do
		if type(v) == 'table' then
			for _, w in ipairs(v) do out[#out + 1] = w end
		else
			out[#out + 1] = v
		end
	end
	return out
end
