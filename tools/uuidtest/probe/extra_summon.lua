-- UUID probe extra steps, mode reload: a summon (op67 Summon creature CAT on portrait 1) and a second simulacrum.
function UUIDT_EXTRA_IMPL(S, step)
	local P = S.P
	S.out('=== extra ' .. step .. ': global EEEX_NEXTUUID = ' .. S.desc(EEex_GameState_GetGlobalInt('EEEX_NEXTUUID')))
	if step == 'reload2' then
		S.unpause()
		S.try('op67 summon CAT', EEex_GameObject_ApplyEffect, P(0), { effectID = 67, res = 'CAT', durationType = 0,
			duration = 600, sourceID = S.idOf(P(0)), sourceTarget = S.idOf(P(0)) })
		S.try('op236 simulacrum of portrait 2', EEex_GameObject_ApplyEffect, P(1), { effectID = 236, dwFlags = 2,
			durationType = 0, duration = 600, sourceID = S.idOf(P(1)), sourceTarget = S.idOf(P(1)) })
	elseif step == 'reload6' then
		S.flushLoads('summon + simulacrum')
		S.listUUIDs('after summon + simulacrum')
	end
end
UUID_EXTRA = function(S, step)
	local ok, err = pcall(UUIDT_EXTRA_IMPL, S, step)
	if not ok then S.out('extra ' .. step .. ' error: ' .. tostring(err)) end
end
