--[[
Router: EEex_Hook* / EEex_JITAt requests of mods written for EEex's x64 asm API -> IEX native hook points.

IEX has no assembler / JIT. The EEex_Hook* functions here are inert stand-ins: nothing is assembled, written or
executed. A request names a patch address (the mod's EEex 2.7.3 Windows x64 address, used only as a key) and asm
text; the only thing read from the text is the Lua function its EEex_GenLuaCall names. The address is looked up
in IEX_AsmSites (lua/IEX_AsmSites.lua, generated from the corpus catalogue by tools/compat/asm_sites.py; see
docs/NATIVE_HOOK_POINTS.md): a site IEX implements activates its hook point (src/core/hook_points.h) and binds
the named callback as a listener, its arguments / result translated by the site's binding:
  args  'idN' object id of the point's argument N (-1 for nil), 'argN' argument N as is, 'ptrN' address of
        argument N, 'objN' argument N (engine object)
  ret   'number': a number replaces the engine value (a non-number counts 0, as EEex's GenLuaCall reads it);
        a Lua error or a missing function keeps the engine value
        'boolean': the callback's truth; 'none'
  switch: the request is a pure asm patch: the point is turned on (IEX_NativeHook_Enable)
  bridge: the point needs data the request does not carry (SadoEE bridge, lua/IEX_NativeHooks.lua, binds it)
Unknown sites, and known sites whose point IEX does not implement, are logged once ("not supported natively:
<mod> <address>") and recorded in IEX/missing_api.txt. EEex_JITNear / EEex_JITNearAsLuaFunction stay undefined
(the missing-API trap): their result is code a mod would jump to, and IEX has none to give.
--]]

IEX_HookRequests = IEX_HookRequests or { bound = {}, logged = {}, standIns = {} }
local R = IEX_HookRequests
R.bound = R.bound or {}
R.logged = R.logged or {}
R.standIns = R.standIns or {}

local CALL_MARK = '\0IEXLUACALL:'

-- EEex_GenLuaCall(name, options) -> asm text. Here: a text that only carries the function name.
function EEex_GenLuaCall(name, options)
	return { CALL_MARK .. tostring(name) }
end

-- EEex_FlattenTable comes from EEex_Utility.lua (EEex's one-level behaviour); findCall below walks any depth.

EEex_LuaCallReturnType = EEex_LuaCallReturnType or { Boolean = 1, Number = 2 }
EEex_HookIntegrityWatchdogRegister = EEex_HookIntegrityWatchdogRegister or {
	RAX = 'RAX', RBX = 'RBX', RCX = 'RCX', RDX = 'RDX', RSI = 'RSI', RDI = 'RDI', RBP = 'RBP', RSP = 'RSP',
	R8 = 'R8', R9 = 'R9', R10 = 'R10', R11 = 'R11', R12 = 'R12', R13 = 'R13', R14 = 'R14', R15 = 'R15',
}

local function findCall(v, depth)
	if depth > 8 then return nil end
	if type(v) == 'string' then
		if v:sub(1, #CALL_MARK) == CALL_MARK then return v:sub(#CALL_MARK + 1) end
	elseif type(v) == 'table' then
		for i = 1, #v do
			local n = findCall(v[i], depth + 1)
			if n then return n end
		end
	end
	return nil
end

-- The requesting mod: the Lua file that called the stand-in (called from the stand-in itself).
local function requester()
	local info = debug and debug.getinfo and debug.getinfo(3, 'S')
	if not info then return '?' end
	local src = tostring(info.short_src or info.source or '?'):gsub('^@', '')
	return src:match('([^/\\]+)$') or src
end

-- Windows: a mod may compute its address from the image base; the table keys use the default base 0x140000000.
local function key(address)
	local base = IEX_ImageBase
	if IEX_Platform == 'win64' and type(base) == 'number' and base ~= 0x140000000 and address >= base and
			address < base + 0x2000000 then
		return address - base + 0x140000000
	end
	return address
end

-- Hex text of an address (Lua 5.2's %X takes 32-bit values only).
local function hex(a)
	if a < 0 or a ~= math.floor(a) then return tostring(a) end
	local hi, lo = math.floor(a / 4294967296), a % 4294967296
	return hi > 0 and string.format('0x%X%08X', hi, lo) or string.format('0x%X', lo)
end

local labelSites
local function siteOf(address)
	local s = IEX_AsmSites and IEX_AsmSites[address]
	if s then return s end
	if not labelSites then
		labelSites = {}
		for _, l in ipairs(IEX_AsmLabelSites or {}) do
			local ok, a = pcall(function() return EEex_Label(l.label) end)
			if ok and type(a) == 'number' and a ~= 0 then labelSites[key(a + l.offset)] = l end
		end
	end
	return labelSites[address]
end

local function unsupported(kind, address, mod, fn, why)
	local k = (mod .. ' ' .. hex(address))
	if R.logged[k] then return end
	R.logged[k] = true
	IEX_Log(string.format('[hooks] not supported natively: %s %s (%s%s)%s', mod, hex(address), kind,
		fn and (', ' .. fn) or '', why and (': ' .. why) or ''))
	if IEX_RecordMissing then IEX_RecordMissing(kind .. '(' .. hex(address) .. ')', mod) end
end

-- Argument translation of a binding: a function (point args...) -> callback args.
local function idOf(v)
	if v == nil then return -1 end
	if type(v) == 'number' then return v end
	local ok, id = pcall(function() return v.m_id end)
	return ok and id or -1
end

local function ptrOf(v)
	if v == nil then return 0 end
	if type(v) == 'number' then return v end
	return (IEX_Address and IEX_Address(v)) or 0
end

local function translator(spec)
	local ops = {}
	for i, a in ipairs(spec or {}) do
		local what, n = a:match('^(%a+)(%d+)$')
		ops[i] = { what, tonumber(n) }
	end
	return function(...)
		local out = {}
		for i, op in ipairs(ops) do
			local v = (select(op[2], ...))
			if op[1] == 'id' then v = idOf(v) elseif op[1] == 'ptr' then v = ptrOf(v) end
			out[i] = v
		end
		return out, #ops
	end
end

local unpack = table.unpack or unpack

-- Listener calling the mod's global `fn` by name at each call (the mod may redefine it later, as with EEex).
local function adapter(point, fn, bind)
	local args = translator(bind.args)
	local ret = bind.ret
	local errors = 0
	return function(...)
		local f = _G[fn]
		if type(f) ~= 'function' then return nil end
		local a, n = args(...)
		local ok, r = pcall(f, unpack(a, 1, n))
		if not ok then
			errors = errors + 1
			if errors <= 20 then IEX_Log('[hooks] Lua error in ' .. fn .. ' (' .. point .. '): ' .. tostring(r)) end
			return nil
		end
		if ret == 'number' then
			if type(r) ~= 'number' then r = tonumber(r) or 0 end
			return r
		elseif ret == 'boolean' then
			return r and true or false
		end
		return nil
	end
end

-- True once the request (point, callback) is bound (a bridge then leaves it alone).
function IEX_HookRequests_IsBound(point, fn)
	return R.bound[point .. ':' .. tostring(fn)] == true
end

local function bind(kind, address, fn, site, mod)
	local b = site.bind
	if site.status ~= 'native' or not b then
		unsupported(kind, address, mod, fn, site.status == 'feature'
			and ('covered by the IEX feature ' .. site.point .. ', not per request')
			or ('point ' .. tostring(site.point) .. ' ' .. tostring(site.status)))
		return site.status == 'feature'
	end
	if b.bridge then
		IEX_Log(string.format('[hooks] %s %s (%s): point %s, bound by the %s bridge', mod, hex(address), kind, site.point,
			b.bridge))
		return true
	end
	if b.switch then
		local ok, why = IEX_NativeHook_Enable(site.point)
		IEX_Log(string.format('[hooks] %s %s -> %s (switch)%s', mod, hex(address), site.point,
			ok and '' or (', NOT AVAILABLE: ' .. tostring(why))))
		return ok
	end
	fn = fn or b.fn
	if not fn then
		unsupported(kind, address, mod, nil, 'no Lua callback named')
		return false
	end
	local k = site.point .. ':' .. fn
	if R.bound[k] then return true end
	local ok, why = IEX_NativeHook_AddListener(site.point, adapter(site.point, fn, b))
	if ok then R.bound[k] = true end
	IEX_Log(string.format('[hooks] %s %s -> %s (Lua %s)%s', mod, hex(address), site.point, fn,
		ok and '' or (', NOT AVAILABLE on this build: ' .. tostring(why))))
	return ok
end

local function request(kind, mod, address, ...)
	if type(address) ~= 'number' then return end
	local fn
	for i = 1, select('#', ...) do
		fn = fn or findCall(select(i, ...), 0)
	end
	local a = key(address)
	local site = siteOf(a)
	if not site then
		unsupported(kind, a, mod, fn, 'unknown site')
		return
	end
	bind(kind, a, fn, site, mod)
end

-- Every address-taking hook kind of EEex's x64 API (and the older names mods still call).
for _, name in ipairs({
	'HookAfterCall', 'HookAfterCallWithLabels', 'HookBeforeCall', 'HookBeforeCallWithLabels',
	'HookBeforeAndAfterCall', 'HookBeforeAndAfterCallWithLabels', 'HookRemoveCall', 'HookRemoveCallWithLabels',
	'HookBeforeRestore', 'HookBeforeRestoreWithLabels', 'HookAfterRestore', 'HookAfterRestoreWithLabels',
	'HookConditionalJump', 'HookConditionalJumpWithLabels', 'HookConditionalJumpOnSuccess',
	'HookConditionalJumpOnSuccessWithLabels', 'HookConditionalJumpOnFail', 'HookConditionalJumpOnFailWithLabels',
	'HookBeforeConditionalJump', 'HookBeforeConditionalJumpWithLabels',
	'HookReplaceFunctionMaintainOriginal', 'HookShimFunctionMaintainOriginal', 'JITAt',
}) do
	local kind = 'EEex_' .. name
	if rawget(_G, kind) == nil then
		local f = function(address, ...)
			local ok, err = pcall(request, kind, requester(), address, ...)
			if not ok then IEX_Log('[hooks] ' .. kind .. ' request failed: ' .. tostring(err)) end
		end
		_G[kind] = f
		R.standIns[f] = true
	end
end

-- True when the global `name` is undefined or one of these inert stand-ins (no real asm API: SadoEE bridge).
function IEX_IsAsmStandIn(name)
	local v = rawget(_G, name)
	return v == nil or R.standIns[v] == true
end

-- StickLuaFunctions tells 2.6 from 2.7 by EEex_Label('Hook-CAIGroup::IsPartyLeader()-Override') (0x14011AC1A on
-- 2.7) before its hook requests. win64: the engine place (CAIGroup::IsPartyLeader, rva 0x11ABD0: the call that
-- looks the leader id up in the party list), its bytes checked. linux64: no such Windows address; IEX gives the
-- value the mod expects for 2.7 (it is only compared, never read). EEex_Label reads both tables.
IEX_AsmEngineLabels = IEX_AsmEngineLabels or {}
IEX_AsmAbsoluteLabels = IEX_AsmAbsoluteLabels or {}
do
	local name = 'Hook-CAIGroup::IsPartyLeader()-Override'
	if IEX_Platform == 'win64' then
		local ok, good = pcall(function()
			local want = { 0xE8, 0xD1, 0xCA, 0x2E, 0x00 }
			for i, b in ipairs(want) do
				if EEex_ReadU8(IEX_ImageBase + 0x11AC1A + i - 1) % 256 ~= b then return false end
			end
			return true
		end)
		if ok and good then IEX_AsmEngineLabels[name] = 0x11AC1A end
	elseif IEX_Platform == 'linux64' then
		IEX_AsmAbsoluteLabels[name] = 0x14011AC1A
	end
end
