-- UUID probe extra steps (tools/uuidtest run.ps1 -Extra): GetFromUUID and LoadedWithUUIDCallback semantics.
UUIDT_CALLS = UUIDT_CALLS or {}
local function cbDesc(tag)
	return function(...)
		local S = UUIDT
		local parts = {}
		local n = select('#', ...)
		for i = 1, n do
			local v = select(i, ...)
			local d = S.desc(v)
			if type(v) == 'userdata' then d = d .. ' id=' .. tostring(S.idOf(v)) .. ' uuid=' .. tostring((S.uuidOf(v))) end
			parts[#parts + 1] = d
		end
		UUIDT_CALLS[#UUIDT_CALLS + 1] = tag .. ' called with ' .. n .. ' arg(s): ' .. table.concat(parts, ', ')
		return 'ret-' .. tag
	end
end
function UUIDT_CB(...) return cbDesc('global-UUIDT_CB')(...) end

local function calls(S, label)
	S.out('--- callback calls (' .. label .. '): ' .. #UUIDT_CALLS)
	for _, l in ipairs(UUIDT_CALLS) do S.out('  ' .. l) end
	UUIDT_CALLS = {}
end
local function tables(S)
	S.dumpTable('EEex_Sprite_Private_LoadedWithUUIDCallbacks', 1)
	S.dumpTable('EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource', 1)
end

function UUIDT_EXTRA_IMPL(S, step)
	local P = S.P
	local next0 = EEex_GameState_GetGlobalInt('EEEX_NEXTUUID')
	S.out('=== extra ' .. step .. ': global EEEX_NEXTUUID = ' .. S.desc(next0))
	if step == 'first3' then
		local u0, u1 = S.uuidOf(P(0)), S.uuidOf(P(1))
		S.try('GetUUID(nil)', EEex_Sprite_GetUUID, nil)
		S.try('GetUUID(P0) again', EEex_Sprite_GetUUID, P(0))
		local r = S.try('GetFromUUID(uuid P0)', EEex_Sprite_GetFromUUID, u0)
		if r[1] and r[2] then S.out('  same id as P0: ' .. tostring(S.idOf(r[2]) == S.idOf(P(0))) .. ', rawequal ' .. tostring(rawequal(r[2], P(0)))) end
		S.try('GetFromUUID(999999)', EEex_Sprite_GetFromUUID, 999999)
		S.try('GetFromUUID(0)', EEex_Sprite_GetFromUUID, 0)
		S.try('GetFromUUID(-1)', EEex_Sprite_GetFromUUID, -1)
		S.try('GetFromUUID(nil)', EEex_Sprite_GetFromUUID, nil)
		S.try('GetFromUUID(tostring uuid P0)', EEex_Sprite_GetFromUUID, tostring(u0))
		S.try('GetFromUUID(uuid P0 + 0.5)', EEex_Sprite_GetFromUUID, u0 + 0.5)
		-- uuid of a creature stored in another area (loaded at save load but not in this area): Tiber etc. are in
		-- the area; take the highest uuid seen at load among the listener calls that is not in the area list.
		S.try('GetFromUUID(1) (loaded at save load, other area?)', EEex_Sprite_GetFromUUID, 1)
		S.try('GetFromUUID(115)', EEex_Sprite_GetFromUUID, 115)
		-- callbacks
		S.try('LoadedWithUUIDCallback(P0, uuid P1 (loaded), fnA)', EEex_Sprite_LoadedWithUUIDCallback, P(0), u1, cbDesc('A'))
		calls(S, 'right after A')
		tables(S)
		S.try('LoadedWithUUIDCallback(P0, 999999 (unknown), fnB)', EEex_Sprite_LoadedWithUUIDCallback, P(0), 999999, cbDesc('B'))
		S.try('LoadedWithUUIDCallback(P0, 999999 (unknown), fnB2 same source+uuid)', EEex_Sprite_LoadedWithUUIDCallback, P(0), 999999, cbDesc('B2'))
		S.try('LoadedWithUUIDCallback(P1, 999999, fnC other source)', EEex_Sprite_LoadedWithUUIDCallback, P(1), 999999, cbDesc('C'))
		S.try('LoadedWithUUIDCallback(P0, next+1, fnD)', EEex_Sprite_LoadedWithUUIDCallback, P(0), next0 + 1, cbDesc('D'))
		S.try('LoadedWithUUIDCallback(P1, next+2, fnE)', EEex_Sprite_LoadedWithUUIDCallback, P(1), next0 + 2, cbDesc('E'))
		S.try('LoadedWithUUIDCallback(nil, next+3, fnF)', EEex_Sprite_LoadedWithUUIDCallback, nil, next0 + 3, cbDesc('F'))
		S.try('LoadedWithUUIDCallback(P2, 999998, "UUIDT_CB" string)', EEex_Sprite_LoadedWithUUIDCallback, P(2), 999998, 'UUIDT_CB')
		S.try('LoadedWithUUIDCallback(P2, 999997, nil func)', EEex_Sprite_LoadedWithUUIDCallback, P(2), 999997, nil)
		calls(S, 'after registering')
		tables(S)
	elseif step == 'first9' then
		calls(S, 'after spawn and clone')
		tables(S)
		local marsh = {}
		for k in pairs(EEex_Sprite_Private_MarshalHandlers or {}) do marsh[#marsh + 1] = tostring(k) end
		S.out('marshal handlers: ' .. table.concat(marsh, ', '))
		-- pending callback whose source is a party member, kept across the save for mode reload
		S.try('LoadedWithUUIDCallback(P0, 999990, "UUIDT_CB")', EEex_Sprite_LoadedWithUUIDCallback, P(0), 999990, 'UUIDT_CB')
		S.try('LoadedWithUUIDCallback(P0, 999991, fnG)', EEex_Sprite_LoadedWithUUIDCallback, P(0), 999991, cbDesc('G'))
		tables(S)
	elseif step == 'first12' then
		calls(S, 'before save')
	elseif step == 'first18' then
		calls(S, 'after save')
		tables(S)
	elseif step == 'reload2' then
		calls(S, 'at reload')
		tables(S)
		S.try('GetFromUUID(147 = clone)', EEex_Sprite_GetFromUUID, 147)
		S.try('GetFromUUID(144 = cat)', EEex_Sprite_GetFromUUID, 144)
		-- callback registered while a target loads later: spawn after registering
		S.try('LoadedWithUUIDCallback(P0, next+1, fnH)', EEex_Sprite_LoadedWithUUIDCallback, P(0), next0 + 1, cbDesc('H'))
		S.unpause()
		S.queue('CreateCreatureObject("CAT",Myself,0,0,0)', P(0))
	elseif step == 'reload6' then
		calls(S, 'end')
		tables(S)
		S.listUUIDs('end of reload')
	end
end
UUID_EXTRA = function(S, step)
	local ok, err = pcall(UUIDT_EXTRA_IMPL, S, step)
	if not ok then S.out('extra ' .. step .. ' error: ' .. tostring(err)) end
end
