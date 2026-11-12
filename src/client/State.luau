-- Client copy of the local player's inventory (the server stays authoritative), plus which menu
-- is open.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)

local State = {
	slots = {} :: { [number]: Items.Stack },
	armor = {} :: { [string]: Items.Stack },
	selected = 1,
	received = false,
	menu = nil :: string?, -- "inventory" | "kits" | "chat" | nil
	dead = false,
	changed = Instance.new("BindableEvent"),
	selectionChanged = Instance.new("BindableEvent"),
}

local closers: { [string]: () -> () } = {}

function State.selectedStack(): Items.Stack?
	return State.slots[State.selected]
end

function State.get(ref: number | string): Items.Stack?
	if type(ref) == "number" then
		return State.slots[ref]
	end
	return State.armor[ref]
end

function State.select(index: number)
	index = ((index - 1) % 9) + 1
	if index == State.selected then
		return
	end
	State.selected = index
	Remotes.SelectSlot:FireServer(index)
	State.selectionChanged:Fire()
end

function State.armorPoints(): number
	local total = 0
	for _, stack in State.armor do
		local def = Items.get(stack.id)
		total += if def then def.armor or 0 else 0
	end
	return total
end

-- Menus are exclusive: opening one closes whichever was open.
function State.registerMenu(name: string, close: () -> ())
	closers[name] = close
end

function State.closeMenu()
	local name = State.menu
	if name then
		State.menu = nil
		closers[name]()
	end
end

function State.openMenu(name: string)
	if State.menu ~= name then
		State.closeMenu()
		State.menu = name
	end
end

Remotes.Inventory.OnClientEvent:Connect(function(payload)
	local slots = {}
	for key, stack in payload.slots or {} do
		local i = tonumber(key)
		if i then
			slots[i] = stack
		end
	end
	State.slots = slots
	State.armor = payload.armor or {}
	-- The server's selection only matters on first sync; afterwards the client leads so fast
	-- scrolling never snaps back.
	if not State.received and type(payload.selected) == "number" then
		State.selected = payload.selected
		State.received = true
	end
	State.changed:Fire()
end)

return State
