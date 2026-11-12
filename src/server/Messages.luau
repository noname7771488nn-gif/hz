local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Messages = {}

-- kind: "info" | "success" | "error" | "death" | "actionbar"
function Messages.send(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

function Messages.broadcast(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "info")
end

function Messages.actionBar(player: Player, text: string)
	Remotes.Notify:FireClient(player, text, "actionbar")
end

return Messages
