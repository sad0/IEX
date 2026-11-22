-- UUID probe extra steps, mode reload of the save written by mode first (cats 144 / 145 present):
-- callback order against loaded listeners, source destroyed, duplicate functions, errors, inner storage.
UUIDT_SEQ = UUIDT_SEQ or {}
local function seq(s) UUIDT_SEQ[#UUIDT_SEQ + 1] = s end
pcall(EEex_Sprite_AddLoadedListener, function(sp) seq('loadedListener id=' .. tostring(UUIDT.idOf(sp)) .. ' uuid=' .. tostring((UUIDT.uuidOf(sp)))) end)
local function cb(tag)
	return function(src, target, extra)
		seq(tag .. ' cb src=' .. tostring((UUIDT.uuidOf(src))) .. ' target=' .. tostring((UUIDT.uuidOf(target))) .. ' extra=' .. tostring(extra))
	end
end
local function flushSeq(S, label)
	S.out('--- sequence (' .. label .. '): ' .. #UUIDT_SEQ)
	for _, l in ipairs(UUIDT_SEQ) do S.out('  ' .. l) end
	UUIDT_SEQ = {}
end
local function deep(S)
	for _, n in ipairs({ 'EEex_Sprite_Private_LoadedWithUUIDCallbacks', 'EEex_Sprite_Private_LoadedWithUUIDCallbacksBySource' }) do
		local t = _G[n]
		S.out(n .. ':')
		for k, v in pairs(t or {}) do
			for k2, v2 in pairs(v) do
				local inner = {}
				if type(k2) == 'table' then
					for k3, v3 in pairs(k2) do inner[#inner + 1] = S.desc(k3) .. '=' .. S.desc(v3) end
					S.out(('  [%s][table{%s}] = %s'):format(S.desc(k), table.concat(inner, '; '), S.desc(v2)))
				else
					if type(v2) == 'table' then for k3, v3 in pairs(v2) do inner[#inner + 1] = S.desc(k3) .. '=' .. S.desc(v3) end end
					S.out(('  [%s][%s] = %s {%s}'):format(S.desc(k), S.desc(k2), S.desc(v2), table.concat(inner, '; ')))
				end
			end
		end
	end
end

local function find(S, uuid) return EEex_Sprite_GetFromUUID(uuid) end

function UUIDT_EXTRA_IMPL(S, step)
	local P = S.P
	if step == 'reload2' then
		flushSeq(S, 'save load (last 8 shown by order)')
		local cat144, cat145 = find(S, 144), find(S, 145)
		S.out('cat144 ' .. tostring(cat144 ~= nil) .. ' cat145 ' .. tostring(cat145 ~= nil))
		local same = cb('same')
		S.try('register (P0, 12, same) #1', EEex_Sprite_LoadedWithUUIDCallback, P(0), 12, same)
		S.try('register (P0, 12, same) #2', EEex_Sprite_LoadedWithUUIDCallback, P(0), 12, same)
		S.try('register (P0, 1 (other area), x)', EEex_Sprite_LoadedWithUUIDCallback, P(0), 1, cb('otherArea'))
		S.try('register (P0, 12, err) immediate error', EEex_Sprite_LoadedWithUUIDCallback, P(0), 12, function() error('boom') end)
		S.try('register (cat144, 999999, s144)', EEex_Sprite_LoadedWithUUIDCallback, cat144, 999999, cb('s144'))
		S.try('register (cat144, 145, s144b) immediate', EEex_Sprite_LoadedWithUUIDCallback, cat144, 145, cb('s144b'))
		S.try('register (P0, 144 (cat144 = target), t144)', EEex_Sprite_LoadedWithUUIDCallback, P(0), 144, cb('t144'))
		S.try('register (P1, 149 (next spawn), order)', EEex_Sprite_LoadedWithUUIDCallback, P(1), EEex_GameState_GetGlobalInt('EEEX_NEXTUUID') + 1, cb('order'))
		flushSeq(S, 'registration')
		deep(S)
		S.unpause()
		S.queue('ClearActions(Myself)', cat144)
		S.queue('DestroySelf()', cat144)
		S.try('cat144 queue DestroySelf via ActionOverride', function() S.queue('ActionOverride("' .. tostring(cat144.m_scriptName:get()) .. '",DestroySelf())', P(0)) end)
		S.queue('CreateCreatureObject("CAT",Myself,0,0,0)', P(0))
	elseif step == 'reload6' then
		flushSeq(S, 'cat144 destroyed, spawn')
		S.out('cat144 still found: ' .. tostring(find(S, 144) ~= nil))
		deep(S)
	end
end
UUID_EXTRA = function(S, step)
	local ok, err = pcall(UUIDT_EXTRA_IMPL, S, step)
	if not ok then S.out('extra ' .. step .. ' error: ' .. tostring(err)) end
end
