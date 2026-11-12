-- Teleports with a stand-still warmup. Blocked while combat-tagged.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Combat = require(script.Parent.Combat)
local Messages = require(script.Parent.Messages)

local Teleport = {}

local pending: { [Player]: {} } = {}

local function combatMessage(player: Player): string
	return `You can't teleport while in combat! ({math.ceil(Combat.tagRemaining(player))}s left)`
end

-- `getTarget` runs after the warmup so destinations (e.g. /rtp) are picked at arrival time.
-- Returns false if the request was refused immediately.
function Teleport.request(player: Player, getTarget: () -> CFrame?, label: string, onArrive: (() -> ())?): boolean
	if Combat.isTagged(player) then
		Messages.send(player, combatMessage(player), "error")
		return false
	end
	local character, humanoid, root = Combat.aliveCharacter(player)
	if not character or not humanoid or not root then
		return false
	end

	local token = {}
	pending[player] = token
	local warmup = Config.TELEPORT_WARMUP
	if warmup > 0 then
		Messages.send(player, `Teleporting to {label} in {warmup} seconds. Don't move!`, "info")
	end

	task.spawn(function()
		local start = root.Position
		local began = os.clock()
		while os.clock() - began < warmup do
			task.wait(0.1)
			if pending[player] ~= token then
				return
			end
			if not root.Parent or humanoid.Health <= 0 then
				pending[player] = nil
				return
			end
			if Combat.isTagged(player) then
				pending[player] = nil
				Messages.send(player, "Teleport cancelled: you entered combat.", "error")
				return
			end
			if (root.Position - start).Magnitude > 1.5 then
				pending[player] = nil
				Messages.send(player, "Teleport cancelled because you moved.", "error")
				return
			end
		end
		if pending[player] ~= token then
			return
		end
		pending[player] = nil

		local target = getTarget()
		if not target then
			Messages.send(player, "Couldn't find a safe place to teleport to. Try again.", "error")
			return
		end
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
		if not character.Parent or humanoid.Health <= 0 or Combat.isTagged(player) then
			return
		end
		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
		Combat.resetFall(player)
		Messages.send(player, `Teleported to {label}.`, "success")
		if onArrive then
			onArrive()
		end
	end)
	return true
end

function Teleport.cancel(player: Player)
	pending[player] = nil
end

Players.PlayerRemoving:Connect(Teleport.cancel)

return Teleport
