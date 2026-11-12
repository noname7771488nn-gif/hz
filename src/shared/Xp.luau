-- Experience points and levels, using Minecraft's curve.
local Xp = {}

-- Points needed to go from `level` to the next one.
local function toNext(level: number): number
	if level >= 31 then
		return 9 * level - 158
	elseif level >= 16 then
		return 5 * level - 38
	end
	return 2 * level + 7
end

-- Returns the level and the progress (0-1) toward the next one for a total number of points.
function Xp.level(total: number): (number, number)
	local level = 0
	local remaining = math.max(0, total)
	while level < 1000 and remaining >= toNext(level) do
		remaining -= toNext(level)
		level += 1
	end
	return level, remaining / toNext(level)
end

return Xp
