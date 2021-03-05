local That = require(game:GetService("ReplicatedStorage"):WaitForChild("That"))
local LocalPlayer = game:GetService("Players").LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

That:Start({
	Base = game:GetService("ReplicatedStorage"):WaitForChild("Base"),
	Required = PlayerScripts:WaitForChild("Controllers"),
	References = {
		Modules = PlayerScripts:WaitForChild("Modules"),
		Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared"),
	},
	--MaxInitTimeout = 5,
	--DebugLog = true,
	--LogPrefix = "",
})
