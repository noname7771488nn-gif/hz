-- Persists kit cooldowns and inventories in a DataStore.
-- If loading fails (outage, or Studio without API access) the session runs in memory and is never
-- saved, so a failed load can't overwrite real data.
local DataStoreService = game:GetService("DataStoreService")

local Data = {}

export type Profile = {
	loaded: boolean,
	kits: { [string]: number }, -- kit name -> unix time of last claim
	inventory: any,
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BlockCraft_PlayerData_v1")
	end)
	if ok then
		store = result
	else
		warn("[BlockCraft] DataStore unavailable, progress will not be saved:", result)
	end
end

Data.profiles = {} :: { [Player]: Profile }

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

function Data.load(player: Player): Profile
	local profile: Profile = { loaded = false, kits = {}, inventory = nil }
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if ok then
				profile.loaded = true
				if type(result) == "table" then
					if type(result.kits) == "table" then
						for name, time in result.kits do
							if type(name) == "string" and type(time) == "number" then
								profile.kits[name] = time
							end
						end
					end
					profile.inventory = result.inventory
				end
				break
			end
			warn(`[BlockCraft] Loading data for {player.Name} failed (attempt {attempt}):`, result)
			task.wait(attempt)
		end
	end
	Data.profiles[player] = profile
	return profile
end

function Data.save(player: Player, inventory: any)
	local profile = Data.profiles[player]
	if not store or not profile or not profile.loaded then
		return
	end
	local payload = { version = 1, kits = profile.kits, inventory = inventory }
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:SetAsync(keyFor(player), payload, { player.UserId })
		end)
		if ok then
			return
		end
		warn(`[BlockCraft] Saving data for {player.Name} failed (attempt {attempt}):`, err)
		task.wait(attempt)
	end
end

function Data.release(player: Player)
	Data.profiles[player] = nil
end

return Data
