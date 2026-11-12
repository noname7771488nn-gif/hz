local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local Client = script.Parent
local Pixel = require(Client.Pixel)
local Ui = require(Client.Ui)
local Hud = require(Client.Hud)
local Chat = require(Client.Chat)
local InventoryUi = require(Client.InventoryUi)
local KitsUi = require(Client.KitsUi)
local Effects = require(Client.Effects)
local Interaction = require(Client.Interaction)
local Controls = require(Client.Controls)

Ui.init()
Pixel.init()
Hud.init()
Chat.init()
InventoryUi.init()
KitsUi.init()
Effects.init()
Controls.init()

Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string?)
	if kind == "actionbar" then
		Hud.actionBar(text)
	else
		Chat.system(text, kind)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	Hud.update(dt)
	KitsUi.update(dt)
end)

-- Last: waits for the world folders to replicate.
Interaction.init()
