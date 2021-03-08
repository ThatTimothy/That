# That Framework

<img align="right" src="https://github.com/ThatTimothy/That/raw/main/res/512rounded.png" width=256 style="margin-left: 25px">

A Roblox Game Framework which simplifies communication between aspects of the game and unifies the Server-Client communication boundaries.

Basic usage is as follows:
```lua
local That = require(game:GetService("ReplicatedStorage").That))

That:Configure(settings)

That:Require(servicesOrControllers)

That:Start()
```

[Read The Docs](https://github.com/ThatTimothy/That/wiki) for more information.
