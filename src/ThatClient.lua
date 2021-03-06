local That = require(game:GetService("ReplicatedStorage"):WaitForChild("That"))

That:Configure({
	References = {
		Modules = script.Parent:WaitForChild("Modules"),
		Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	},
	--MaxInitTimeout = 5,
	--DebugLog = true,
	--LogPrefix = "",
})

That:Require(script.Parent:WaitForChild("Controllers"))

That:Start()