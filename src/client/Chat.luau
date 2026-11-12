-- Minecraft-style chat: translucent lines in the bottom-left that fade after ten seconds, opened
-- with T (or / for commands). Player messages go through Roblox's TextChatService, so they are
-- filtered and respect chat settings; commands go to the server's command handler.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Chat = {}

local player = Players.LocalPlayer

local MAX_LINES = 100
local SHOWN_CLOSED = 10
local SHOWN_OPEN = 20
local VISIBLE_SECONDS = 10
local FADE_SECONDS = 1
local MAX_LENGTH = 200

local COLORS = {
	info = "#FFFFFF",
	success = "#55FF55",
	error = "#FF5555",
	death = "#FFFFFF",
	join = "#FFFF55",
	streak = "#FFAA00",
}

local container: Frame
local input: TextBox
local lines: { { label: TextLabel, at: number } } = {}
local history: { string } = {}
local historyIndex = 0
local nextOrder = 0

local function addLine(richText: string)
	nextOrder += 1
	local label = Ui.label({
		LayoutOrder = nextOrder,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		RichText = true,
		Text = richText,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})
	Ui.create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = label })
	table.insert(lines, { label = label, at = os.clock() })
	if #lines > MAX_LINES then
		lines[1].label:Destroy()
		table.remove(lines, 1)
	end
end

-- Server and game messages. kind: "info" | "success" | "error" | "death" | "join" | "streak"
function Chat.system(text: string, kind: string?)
	addLine(Ui.colored(text, COLORS[kind or "info"] or COLORS.info))
end

local function general(): TextChannel?
	local channels = TextChatService:FindFirstChild("TextChannels")
	return channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
end

local function send(text: string)
	text = string.sub((text:gsub("^%s+", ""):gsub("%s+$", "")), 1, MAX_LENGTH)
	if text == "" then
		return
	end
	if history[#history] ~= text then
		table.insert(history, text)
	end
	if string.sub(text, 1, 1) == "/" then
		Remotes.Command:FireServer(text)
		return
	end
	local channel = general()
	if not channel then
		Chat.system("Chat is not available right now.", "error")
		return
	end
	task.spawn(function()
		local ok = pcall(channel.SendAsync, channel, text)
		if not ok then
			Chat.system("Your message could not be sent.", "error")
		end
	end)
end

function Chat.isOpen(): boolean
	return State.menu == "chat"
end

function Chat.open(prefill: string)
	State.openMenu("chat")
	historyIndex = #history + 1
	input.Visible = true
	input:CaptureFocus()
	-- The key that opened the chat would otherwise be typed into the box.
	task.defer(function()
		RunService.RenderStepped:Wait()
		if Chat.isOpen() then
			input.Text = prefill
			input.CursorPosition = #prefill + 1
		end
	end)
end

local function update()
	local open = Chat.isOpen()
	local now = os.clock()
	local shown = if open then SHOWN_OPEN else SHOWN_CLOSED
	for i, line in lines do
		local age = now - line.at
		local recent = i > #lines - shown
		local visible = recent and (open or age < VISIBLE_SECONDS)
		line.label.Visible = visible
		if visible then
			local fade = if open then 0 else math.clamp((age - (VISIBLE_SECONDS - FADE_SECONDS)) / FADE_SECONDS, 0, 1)
			line.label.TextTransparency = fade
			line.label.TextStrokeTransparency = 0.25 + 0.75 * fade
			line.label.BackgroundTransparency = 0.5 + 0.5 * fade
		end
	end
end

function Chat.init()
	-- Replace Roblox's chat window, input bar and speech bubbles with this one.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	task.spawn(function()
		local bubbles = TextChatService:WaitForChild("BubbleChatConfiguration", 10)
		if bubbles and bubbles:IsA("BubbleChatConfiguration") then
			bubbles.Enabled = false
		end
	end)

	container = Ui.create("Frame", {
		Name = "Chat",
		Size = UDim2.fromScale(0.4, 0.5),
		Position = UDim2.new(0, 6, 1, -150),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = Ui.hud,
	}, {
		Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }),
		Ui.create("UISizeConstraint", { MinSize = Vector2.new(360, 0), MaxSize = Vector2.new(760, math.huge) }),
	})

	input = Ui.create("TextBox", {
		Name = "ChatInput",
		Size = UDim2.new(1, -12, 0, 34),
		Position = UDim2.new(0, 6, 1, -6),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Ui.FONT,
		PlaceholderText = "",
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		ZIndex = 20,
		Parent = Ui.overlay,
	}, {
		Ui.create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})

	input.FocusLost:Connect(function(enterPressed)
		local text = input.Text
		input.Text = ""
		if Chat.isOpen() then
			State.closeMenu()
		end
		if enterPressed then
			send(text)
		end
	end)
	State.registerMenu("chat", function()
		input.Visible = false
		if input:IsFocused() then
			input:ReleaseFocus(false)
		end
	end)

	-- Up/Down recall earlier messages while typing.
	UserInputService.InputBegan:Connect(function(key)
		if not Chat.isOpen() or #history == 0 then
			return
		end
		if key.KeyCode == Enum.KeyCode.Up then
			historyIndex = math.max(1, historyIndex - 1)
		elseif key.KeyCode == Enum.KeyCode.Down then
			historyIndex = math.min(#history + 1, historyIndex + 1)
		else
			return
		end
		input.Text = history[historyIndex] or ""
		input.CursorPosition = #input.Text + 1
	end)

	TextChatService.MessageReceived:Connect(function(message: TextChatMessage)
		local source = message.TextSource
		if not source then
			return -- system messages are added directly by Chat.system
		end
		if message.Status == Enum.TextChatMessageStatus.Success then
			local sender = Players:GetPlayerByUserId(source.UserId)
			local name = if sender then sender.Name else source.Name
			-- message.Text is already filtered and has rich-text characters escaped.
			addLine(Ui.escape(`<{name}> `) .. message.Text)
		elseif source.UserId == player.UserId and message.Status ~= Enum.TextChatMessageStatus.Sending then
			Chat.system("Your message was not sent.", "error")
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return Chat
