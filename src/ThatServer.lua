local That = require(game:GetService("ReplicatedStorage").That)

That:Configure({
	References = {
		Modules = game:GetService("ServerStorage").Modules,
		Shared = game:GetService("ReplicatedStorage").Shared
	},
	--HandleInvalidAction = function(player, id)
	--	--id 0 = failed handshake
	--	--id 1 = failed authentication check
	--	--id 2 = requested an invalid event id
	--	warn(("Player %s performed an invalid action! Id: %i"):format(player.Name, id))
	--end,
	--ClearDataAfter = 10,
	--MaxInitTimeout = 5,
	--DebugLog = true,
	--LogPrefix = "",
})

That:Require(game:GetService("ServerStorage").Services)

That:Start()