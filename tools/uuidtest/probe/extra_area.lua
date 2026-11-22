-- UUID probe extra, mode reload: the party leaves the area (LeaveAreaLUA to UUID_AREA_B, default AR0700) and comes
-- back. Checks: the area's creatures keep their numbers when the area is rebuilt; a LoadedWithUUIDCallback registered
-- for one of them (source: portrait 1) runs again when it is loaded the second time in the session.
local A = {}
UUIDT_AREA_CALLS = {}

local function areaRes()
	local ok, r = pcall(function() return EEex_Area_GetVisible().m_resref:get() end)
	return ok and r or '?'
end

local function areaCreatures(S)
	local set, party = {}, {}
	for i = 0, 5 do local p = S.P(i) if p then party[S.idOf(p)] = true end end
	for _, sp in ipairs(S.sprites()) do
		if not party[S.idOf(sp)] then
			local res = '?'
			pcall(function() res = sp.m_resref:get() end)
			set[#set + 1] = { uuid = (S.uuidOf(sp)), id = S.idOf(sp), name = S.name(sp), res = res }
		end
	end
	table.sort(set, function(a, b) return a.uuid < b.uuid end)
	return set
end

local function leave(S, area, positions)
	S.unpause()
	for i = 0, 5 do
		local p = S.P(i)
		if p then
			local pos = positions and positions[i] or { x = 1800, y = 1200 }
			S.queue(('LeaveAreaLUA("%s","",[%d.%d],0)'):format(area, pos.x, pos.y), p)
		end
	end
end

local STEPS = {
	{ 3, function(S)
		A.area = areaRes()
		A.pos = {}
		for i = 0, 5 do
			local p = S.P(i)
			if p then A.pos[i] = { x = p.m_pos.x, y = p.m_pos.y } end
		end
		A.before = areaCreatures(S)
		S.out(('area %s, %d non-party creatures'):format(A.area, #A.before))
		for _, c in ipairs(A.before) do S.out(('  before uuid=%s %s [%s]'):format(tostring(c.uuid), c.name, c.res)) end
		A.target = A.before[1]
		if A.target then
			S.out('callback target uuid ' .. tostring(A.target.uuid) .. ' ' .. A.target.name)
			S.try('register (P0, target, cb)', EEex_Sprite_LoadedWithUUIDCallback, S.P(0), A.target.uuid, function(src, t)
				UUIDT_AREA_CALLS[#UUIDT_AREA_CALLS + 1] = ('cb src=%s target=%s area=%s'):format(tostring((S.uuidOf(src))),
					tostring((S.uuidOf(t))), areaRes())
			end)
		end
		leave(S, UUID_AREA_B or 'AR0700', nil)
	end },
	{ 14, function(S)
		S.out('away: visible area ' .. areaRes())
		if A.target then
			S.out('away: GetFromUUID(target) ' .. tostring(EEex_Sprite_GetFromUUID(A.target.uuid) ~= nil))
		end
		leave(S, A.area, A.pos)
	end },
	{ 26, function(S)
		S.out('back: visible area ' .. areaRes())
		local after = areaCreatures(S)
		local byUuid = {}
		for _, c in ipairs(after) do byUuid[tostring(c.uuid)] = c end
		local kept, lost, moved = 0, 0, 0
		for _, c in ipairs(A.before) do
			local n = byUuid[tostring(c.uuid)]
			if n and n.name == c.name and n.res == c.res then
				kept = kept + 1
				if n.id ~= c.id then moved = moved + 1 end
			else
				lost = lost + 1
				S.out(('  not found again: uuid=%s %s'):format(tostring(c.uuid), c.name))
			end
		end
		S.out(('back: %d of %d creatures with the same uuid / name / resref (%d rebuilt with a new object id), %d missing, %d now'):format(
			kept, #A.before, moved, lost, #after))
		S.out('callback calls: ' .. #UUIDT_AREA_CALLS)
		for _, l in ipairs(UUIDT_AREA_CALLS) do S.out('  ' .. l) end
		A.finished = true
	end },
}

UUID_TICK = function(S, elapsed)
	A.done = A.done or {}
	for i, st in ipairs(STEPS) do
		if not A.done[i] and elapsed >= st[1] then
			A.done[i] = true
			local ok, err = pcall(st[2], S)
			if not ok then S.out('area step ' .. st[1] .. ' error: ' .. tostring(err)) end
			S.flush()
		end
	end
end
UUID_HOLD = function() return not A.finished end
