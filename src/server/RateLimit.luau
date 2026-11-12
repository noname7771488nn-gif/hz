-- Fixed one-second windows per player and remote; enough to stop remote spam.
local RateLimit = {}

local buckets: { [Player]: { [string]: { start: number, count: number } } } = {}

function RateLimit.allow(player: Player, key: string, perSecond: number): boolean
	local now = os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket or now - bucket.start >= 1 then
		playerBuckets[key] = { start = now, count = 1 }
		return true
	end
	bucket.count += 1
	return bucket.count <= perSecond
end

function RateLimit.clear(player: Player)
	buckets[player] = nil
end

return RateLimit
