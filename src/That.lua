--[[
	  _______ _           _      ______                                           _    
	 |__   __| |         | |    |  ____|                                         | |   
	    | |  | |__   __ _| |_   | |__ _ __ __ _ _ __ ___   _____      _____  _ __| | __
	    | |  | '_ \ / _` | __|  |  __| '__/ _` | '_ ` _ \ / _ \ \ /\ / / _ \| '__| |/ /
	    | |  | | | | (_| | |_   | |  | | | (_| | | | | | |  __/\ V  V / (_) | |  |   < 
	    |_|  |_| |_|\__,_|\__|  |_|  |_|  \__,_|_| |_| |_|\___| \_/\_/ \___/|_|  |_|\_\



	A Roblox Game Framework, made by ThatTimothy.
	
	DevFourm: <coming soon™>
	GitHub: https://github.com/ThatTimothy/That
	Docs: <coming soon™>
	Demo: <coming soon™>
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	Several Notes:
	
		When writing this, I wanted to make it all in one file so you could just drag and drop it anywhere.
	Therefore, some sections are really ugly because I have to check for server / client usage, and I don't 
	use separate files for OOP classes.	Metatables are ugly, but needed for certain functionality. 
	
	Feel free to make any suggestions, I'm open to them. However, I want to keep the current functionality.
]]

-- It's time to start That.
local That = {}

-- Roblox Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService") --Only use is for GenerateGUID, no requests are made (you can check)

-- Roblox Globals
local isClient = RunService:IsClient() --Client behavior must be different

-- Constants
local CONST_THAT_STORAGE_INDEX = "__THAT_UNIQUE_INDEX" --Unique key to distinguish services.
local CONST_THAT_HANDSHAKE_NAME = "__THAT_HANDSHAKE" --Unique name to distinguish handshake event.
local CONST_THAT_LOG_PREFIX = "" --Change this if you want a log prefix
local CONST_AUTH_KEY_RANGE = { Min = 0, Max = math.pow(2, 30) } --The range to use for Auth keys

local THAT_BASE_DIR
local THAT_REQUIRE_DIR

local THAT_METATABLE --Global metatable to inject whenever possible
local THAT_EVENT --An event class setup in Init, used as a proxy to real remote events
local THAT_OPTIONS --Copy of options set in init
local ROOT_DIR --Services on server, Controllers on client, setup in Init
local ROOT_NAME = "Service" --On the client, services are called controllers
local THAT_INITED = false --Whether or not That Framework has been initialized
local THAT_STARTED = false --Whether or not That Framework has started yet

-- Proxies
local serviceProxies = {}

-- Queues
local updateQueue = function() end --Don't do anything yet

local THAT_QUEUE = {
	ToInit = {},
	ToStart = {}
}

-- Store service data returned from client methods & auth keys to use for validation
local serviceData = {}

-- Errors message, but trace the error up to where it actually occured
local function ErrorUp(message, level)
	--[[
	
		 _   _       _   _          
		| \ | |     | | (_)         
		|  \| | ___ | |_ _  ___ ___ 
		| . ` |/ _ \| __| |/ __/ _ \
		| |\  | (_) | |_| | (_|  __/
		|_| \_|\___/ \__|_|\___\___|
		
		
	
		If after clicking on red text you end up here, go to where the red text says instead of here.
		For example, it will say: ServerStorage.Services.SampleService:19. You would go to line 19 of SampleService
		
		
		Topics relating to why this happens and isn't fixable: 
			https://devforum.roblox.com/t/t/49455
			https://devforum.roblox.com/t/t/1062197
	
	
	]]--
	error(message, level or 3) --2 == one level up, where ErrorUp was called, so do 3 as default
end

-- Use assert, but trace the error up to where it actually occured
local function AssertUp(condition, message, level)
	if not condition then
		ErrorUp(message, (level + 1) or (3 + 1))
	end
end

-- Formats seconds into ms
local function FormatTime(seconds)
	local ms = seconds * 1000
	local accuracy = 1000
	local flooredMs = math.floor(ms * accuracy) / accuracy
	return flooredMs .. "ms"
end

-- Returns item passed if passed object is a player
local function IsPlayer(item)
	if item and typeof(item) == "Instance" and item:IsA("Player") then
		return item
	end
end

-- Generates a auth key from the given generator
local function generateAuthKey(generator)
	return generator:NextInteger(CONST_AUTH_KEY_RANGE.Min, CONST_AUTH_KEY_RANGE.Max)
end

-- Spawns a thread using a BindableEvent. Slower than coroutines, but handles errors much better.
local function SpawnThread(func, ...)
	local bindable = Instance.new("BindableEvent")
	
	local args = table.pack(...)
	bindable.Event:Connect(function()
		func(table.unpack(args))
	end)

	bindable:Fire()
	bindable:Destroy()
end

-- Allows modules to be lazy loaded in dot fashion
local function LazyLoadModule(file)
	if file:IsA("ModuleScript") then
		return require(file)
	end
	
	return setmetatable({}, {
		__index = function(tab, index)
			local found = file:FindFirstChild(index)
			if found then
				local set = LazyLoadModule(found)
				rawset(tab, index, set)
				return set
			end
		end
	})
end

-- Updates the queue, set in :Init
local function updateQueue()
	--Start out doing nothing
end

-- Handles Client -> Server, and Client -> Server -> Client events
local function HandleServerEvent(requestingData, serviceName, eventName, player, authKey, ...)
	--Notes: requestingData, serviceName, eventName, and player will always be valid
	--This function will always be called in it's own thread, so yielding is not an issue
	local thisData = serviceData[player.UserId]["ServiceData"][serviceName][eventName]
	local eventData = thisData.EventData
	
	--Client -> Server, perform request and check auth key 1
	if not requestingData then
		--Do auth key validation check
		local shouldBeAuthKey = generateAuthKey(thisData.AuthKeyGen1)
		if authKey and authKey == shouldBeAuthKey then
			thisData.OnId += 1

			local service = That.Services[serviceName]
			local clientMethods = service.Client
			local method = clientMethods[eventName]
			
			--Mark the data as being processed
			local newData = {
				Processed = false
			}
			eventData[thisData.OnId] = newData
			
			--Mark the services client table so Ratelimit function can use traceback
			That.Services[serviceName].Client._RatelimitTracebackData = {
				Player = player,
				EventName = eventName
			}
			
			--Call method, passing self as the first argument, player as the second, and then passed arguments
			--Also, save the packed return value so we can send to the client later if they request it
			local packedReturnValue = table.pack(method(clientMethods, player, ...))

			--Store returned value in-case needed, also store time so we can clear old data not in-use, 
			--and mark as processed so our cleanup function can proccess it
			newData.Time = time()
			newData.Data = packedReturnValue
			newData.Processed = true
		else
			THAT_OPTIONS.HandleInvalidAction(player, 1)
		end
	else
		--Client is requesting data from previous item
		
		local shouldBeAuthKey = generateAuthKey(thisData.AuthKeyGen2)
		local id = ...
		--Validate auth key & requesting id
		if authKey and authKey == shouldBeAuthKey and id and typeof(id) == "number" then
			local existingData = eventData[id]
			if not existingData then
				--Only cases: (id that doesn't exist yet (:Get() is faster then original send) or (exploiting)
				--This should never be possible, BUT in-case it ever happens do to some weird stuff, allow 1s
				--If it takes more than 10 seconds, we know it's not latency and an invalid action
				local start = time()
				while not existingData and time() - start < 10 do
					RunService.Stepped:Wait()
					existingData = eventData[id]
				end
			end
			
			--Check for client being a dirty exploiter
			if not existingData then
				THAT_OPTIONS.HandleInvalidAction(player, 2)
			else
				--Wait for the data to be processed
				while not existingData.Processed do
					RunService.Stepped:Wait()
				end
				--Return the data
				return table.unpack(existingData.Data)
			end
			
		else
			THAT_OPTIONS.HandleInvalidAction(player, 1)
		end
	end

end

-- Create an empty table with That Framework injected
function That:CreateWrapper(parameter)
	if parameter then
		ErrorUp("That:CreateWrapper() does not take parameters")
	end

	return setmetatable({}, THAT_METATABLE)
end

-- Creates a fake proxy to a service if it doesn't exist yet. This allows you to define services before they exist.
local function GetService(selfOrName, name)
	--Support .GetService and :GetService
	if not name then
		name = selfOrName
	end

	--Check for name message setting
	if not name or not typeof(name) == "string" then
		--Format error message
		local message = string.format("Please provide a valid string name to That:Get%s(name)", ROOT_NAME)

		--Error message
		ErrorUp(message, 4)
	end
	
	--Check if service already exists
	local exists = rawget(ROOT_DIR, name)
	if exists then
		return exists
	end
	
	--If the framework has already created services, error
	if THAT_INITED then
		local message = 'The %s "%s" does not exist'
		ErrorUp(string.format(message, ROOT_NAME:lower(), name), 4)
	end
	
	--Check if service proxy already exists
	local proxy = serviceProxies[name]
	if not proxy then
		--Create a proxy
		
		--Create a helpful traceback to when the bad index first occured, if it ever does, as this can be confusing.
		local traceback = debug.traceback():gmatch("[^\r\n]+") --The value of debug.traceback can change at any time.
		--However, since this is already an error, some info is better than none (worst case scenario)
		local ourName = script:GetFullName()
		local splitTraceback = {}
		for i in traceback do
			if not string.find(i, ourName) then
				splitTraceback[#splitTraceback + 1] = i
			end
		end
		
		local message = 
			('The service "%s" does not exist. Check the original definition (:GetService("%s") or .Services.%s)' ..
			'\n%s    <------- Original Definition'):format(name, name, name, splitTraceback[#splitTraceback]) ..
			'\nClicking on this error will not go to the right place, read above.'
		
		message = message:gsub("service", ROOT_NAME:lower()):gsub("Service", ROOT_NAME)

		--Create a thread to check for existance after the max timeout, so you don't get silent errors
		SpawnThread(function(name, m)
			--Wait until framework started
			while not THAT_INITED do
				RunService.Stepped:Wait()
			end

			--Check for existance again
			if not rawget(ROOT_DIR, name) then
				ErrorUp(m, 0)
			end
		end, name, message)
		
		--Create a "proxy" to the actual service which will hopefully be defined
		proxy = setmetatable({}, {
			__index = function(fakeService, index)
				--Pass on indexing
				local realService = rawget(ROOT_DIR, name)
				if not realService then
					--Doesn't exist
					ErrorUp(message)
				else
					--Update metatable to link directly now
					setmetatable(proxy, {
						__index = realService,
						__newindex = realService,
					})
					
					--Return the correct value
					return realService[index]
				end
			end,

			__newindex = function(fakeService, index, newValue)
				--Pass on new indexes
				local realService = rawget(ROOT_DIR, name)
				if not realService then
					--Doesn't exist
					ErrorUp(message)
				else
					--Update metatable to link directly now
					setmetatable(proxy, {
						__index = realService,
						__newindex = realService,
					})
					
					--Set the correct value
					realService[index] = newValue
				end
			end,
		})
		
		--Save proxy to save memory
		serviceProxies[name] = proxy
	end
	
	--Return a "proxy" to the actual service which will hopefully be defined
	return proxy
end

-- Creates a service. On the client, controllers are just renamed services (they are the same thing essentially)
local function CreateService(serviceName)
	--Check for string name
	AssertUp(serviceName and typeof(serviceName) == 'string', 
		("Please provide name to That:CreateService(name)"):gsub("Service", ROOT_NAME))
	
	--Make sure it has a unique name
	if rawget(ROOT_DIR, serviceName) then
		local msg = "A %s with the name `%s` already exists, please use a different name."
		ErrorUp(string.format(msg, ROOT_NAME:lower(), serviceName))
	end

	--Create a wrapper to base the service on
	local NewService = That:CreateWrapper()

	--Setup remotes if on the server
	if not isClient then
		--Create remotes folder for service
		local folder = Instance.new("Folder")
		folder.Name = serviceName
		folder.Parent = THAT_BASE_DIR

		--Create client events folder for service
		local clientF = Instance.new("Folder")
		clientF.Name = "Client Events"
		clientF.Parent = folder

		--Create server events folder for service
		local serverF = Instance.new("Folder")
		serverF.Name = "Server Events"
		serverF.Parent = folder
		
		--Setup variable to distinguish service
		NewService[CONST_THAT_STORAGE_INDEX] = {
			Name = serviceName
		}
		
		--Handles when a new client event is referenced, like Service.ClientEvent
		local function handleClientEvent(tab, index)
			local Event = THAT_EVENT.new(clientF, index)
			
			rawset(tab, index, Event)
			
			return tab[index]
		end
		
		--Handles when a new server event method is set, like function Service:ClientEvent()
		local function handleNewServerEvent(tab, index, value)
			--Create a new remote event
			local remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = index
			
			--Create a remote function, used for getting return values from server events / methods
			local remoteFunction = Instance.new("RemoteFunction")
			remoteFunction.Name = "Get"
			remoteFunction.Parent = remoteEvent
			
			--Connect an event to handle client using methods
			remoteEvent.OnServerEvent:Connect(function(player, ...)
				HandleServerEvent(false, serviceName, index, player, ...)
			end)
			
			--Connect an event to hanlde client wanting the data back
			function remoteFunction.OnServerInvoke(player, ...)
				return HandleServerEvent(true, serviceName, index, player, ...)
			end
			
			--Allow client to access by parenting to server folder
			remoteEvent.Parent = serverF

			--__newindex overrides actually setting the value, but in this case we want it to be set.
			rawset(tab, index, value)
		end
		
		--Add client metatable which allows for creation of Client -> Server events by just adding them to .Client
		local clientMetatable = {
			__index = handleClientEvent,
			__newindex = handleNewServerEvent,
		}
		
		--Create a ratelimit function for this service
		local function Ratelimit(self, t)
			--Retrive traceback data
			local tracebackData = self._RatelimitTracebackData
			self._RatelimitTracebackData = nil
			
			--Get the ratelimit data from traceback data
			local eventData = serviceData[tracebackData.Player.UserId].ServiceData[serviceName][tracebackData.EventName]
			local data = eventData.Ratelimit
			
			--Calculate the time passed, and update for future
			local timePassed = time() - data.LastCall
			data.LastCall = time()
			
			--Update the bucket
			data.Bucket = math.max(0, data.Bucket + t - timePassed)
			
			--Return a truthy value if bucket is overflowing
			if data.Bucket > t then
				--Return calls for useful conditioning from result
				return data.Bucket / t
			end
			
			--No ratelimit
			return false
		end
		
		--Create client table
		local clientTable = setmetatable({
			Ratelimit = Ratelimit,
			Server = NewService --Allow for self.Server syntax whilst inside client handler method
		}, clientMetatable)
		
		NewService.Client = clientTable
	end
	
	
	--Save service to common location
	ROOT_DIR[serviceName] = NewService
	
	--Insert service into queue
	table.insert(THAT_QUEUE.ToInit, {
		Name = serviceName,
		Required = NewService,
		AddedAt = os.clock(),
	})
	
	--Trigger updating of queue
	updateQueue()
	
	--Return new service
	return NewService
end

--Initialize the framework
function That:Start(options)
	--Mark That as itself
	That[CONST_THAT_STORAGE_INDEX] = CONST_THAT_STORAGE_INDEX
	
	--Prevent additional calls of :Start
	That.Start = function()
		ErrorUp("That:Start(options) can only be called once!")
	end
	
	--Make sure options exists
	AssertUp(options and typeof(options) == "table", 
		"That:Start(options) failed, please provide a valid options table.")
	
	--Default timeout option
	if not options.MaxInitTimeout then
		options.MaxInitTimeout = 5
	else
		--Validate is number
		AssertUp(typeof(options.MaxInitTimeout) == "number",
			"That:Start(options) failed, options.MaxInitTimeout must be a number.")
	end
	
	--Default logging option
	if options.DebugLog == nil then
		options.DebugLog = true
	end
	
	--Default options if server
	if not isClient then
		--Default ClearDataAfter option
		if not options.ClearDataAfter then
			options.ClearDataAfter = 10
		else
			--Validate is number
			AssertUp(typeof(options.ClearDataAfter) == "number",
				"That:Start(options) failed, options.ClearDataAfter must be a number.")
		end
		
		--Default HandleInvalidAction callback (if server)
		if not options.HandleInvalidAction then
			options.HandleInvalidAction = function(player, id)
				--id 0 = failed handshake
				--id 1 = failed authentication check
				--id 2 = requested an invalid event id
				warn(("Player %s performed an invalid action! Id: %i"):format(player.Name, id))
			end
		else
			--Validate is method
			AssertUp(typeof(options.HandleInvalidAction) == "function",
				"That:Start(options) failed, options.HandleInvalidAction must be a function.")
		end
	end
	
	--Change logging prefix
	if options.LogPrefix then
		CONST_THAT_LOG_PREFIX = options.LogPrefix
	end
	
	--Check for valid base dir
	AssertUp(options.Base, 
		"That:Start(options) failed, please provide options.Base")
	AssertUp(typeof(options.Base) == "Instance", 
		"That:Start(options) failed, options.Base must be an instance")

	THAT_BASE_DIR = options.Base

	--Check for valid required dir (only client has controllers)
	AssertUp(options.Required, 
		"That:Start(options) failed, please provide options.Required")
	AssertUp(typeof(options.Required) == "Instance", 
		"That:Start(options) failed, options.Required must be an instance")

	THAT_REQUIRE_DIR = options.Required
	
	--Setup services table which supports :GetService
	That.Services = setmetatable({}, {
		__index = function(tab, index)
			--For new indexes, use the GetService proxy method
			return That:GetService(index)
		end,
	})
	
	if isClient then
		--Commence "That Handshake"
		local handshakeEvent = THAT_BASE_DIR:WaitForChild(CONST_THAT_HANDSHAKE_NAME, math.huge)
		local authKeys = handshakeEvent:InvokeServer()
		
		--Destroy handshake event LOCALLY to prevent confusion with later items
		handshakeEvent:Destroy()
		
		--Get generators setup
		local authKeyGenerators = {}
		for serviceName, methods in pairs(authKeys) do
			authKeyGenerators[serviceName] = {}
			for methodName, methodAuthKeys in pairs(methods) do
				--Make generators from each set of keys
				authKeyGenerators[serviceName][methodName] = {
					AuthKeyGen1 = Random.new(methodAuthKeys.AuthKey1),	
					AuthKeyGen2 = Random.new(methodAuthKeys.AuthKey2),
				}
			end
		end
		
		--Define client service creator
		local function createClientService(serviceName)
			--Support ClientService.Event:Connect()
			
			local ClientService = setmetatable({}, {
				__index = function(tab, eventName)
					--On a new index, create a new client event to handle stuff
					local ClientEvent = THAT_EVENT.new(serviceName, eventName)
					
					--Set it so we don't make duplicates
					rawset(tab, eventName, ClientEvent)
					
					--Return it
					return ClientEvent
				end,
			})
			
			That.Services[serviceName] = ClientService
		end
		
		--Define client variables
		
		--On the client, controllers are basically services
		That.Controllers = That.Services
		
		--For services on the client, error if one doesn't exist, and make our client services as needed
		That.Services = setmetatable({}, {
			__index = function(tab, serviceName)
				local service = THAT_BASE_DIR:FindFirstChild(serviceName)
				
				if not service then
					ErrorUp(string.format('Service "%s" does not exist!', serviceName))
				end
				
				--Create a client service
				createClientService(serviceName)
				
				--Return the proper client service
				return tab[serviceName]
			end,
		})
		
		--Define basic handler for use
		local Signal = {}
		Signal.__index = Signal
		
		--Creates a singal
		function Signal.new(handler, root)
			local newSignal = {
				_handler = handler,
				_root = root,
			}
			
			setmetatable(newSignal, Signal)
			
			return newSignal
		end
		
		--Spawns handler in a new thread with passed arguments
		function Signal:Fire(...)
			SpawnThread(self._handler, ...)
		end
		
		--Disconnects signal by removing itself from it's root
		function Signal:Disconnect()
			self._root:Disconnect(self)
		end

		--Add aliases
		Signal.Destroy = Signal.Disconnect
		
		--Make services on the client a custom class
		THAT_EVENT = {}
		THAT_EVENT.__index = THAT_EVENT
		
		--Constant metatable which errors not to index itself
		local DontIndexMe = {__index = function()
			ErrorUp("To get a value from a method, don't index directly! Use :Get first!")
		end}
		
		--Handle Service.THAT_EVENT(...) or Service:THAT_EVENT(...)
		THAT_EVENT.__call = function(calledOn, arg1, ...)
			--Define needed constants
			local serverEvents = calledOn._serverEvents
			local eventName = calledOn._eventName
			local serviceName = calledOn._serviceName
			local parentService = That.Services[serviceName]
			
			--Check for an actual remote event to use
			local RemoteEvent = serverEvents:FindFirstChild(eventName)
			if RemoteEvent then
				--Get the authorization keys
				local generators = authKeyGenerators[serviceName][eventName]
				local key1 = generateAuthKey(generators.AuthKeyGen1)
				local key2 = generateAuthKey(generators.AuthKeyGen2)
				--Event methods can be called in . or : syntax, support both
				
				--If arg1 is the service it was called on, don't pass it through the remote event (: syntax passes self)
				--Normally, without the client-server barrier, : syntax would work, so make it appear that way
				if arg1 == parentService then
					--Lose arg1
					RemoteEvent:FireServer(key1, ...)
				else
					--Pass arg1 on
					RemoteEvent:FireServer(key1, arg1, ...)
				end
				
				--Keep track of id
				calledOn._onId += 1
				local thisId = calledOn._onId
				
				local requestTime = time()
				
				--Return a proxy which will get the result if :Get() is called
				return setmetatable({
					Get = function()
						--Check for yield already
						if time() - requestTime > (0.25) then
							ErrorUp("You cannot yield before calling :Get()")
						else
							--Make request, using key2
							return RemoteEvent:WaitForChild("Get"):InvokeServer(key2, thisId)
						end
					end,
				}, DontIndexMe)
			else
				--That method doesn't exist, provide some helpful debug information
				local listOfAllMethods = "None"
				for _, event in ipairs(serverEvents:GetChildren()) do
					if listOfAllMethods == "None" then
						listOfAllMethods = event.Name
					else
						listOfAllMethods = listOfAllMethods .. ", " .. event.Name
					end
				end

				--Format the information
				local message = "Attempt to call %s.%s, which is not defined in %s.Client"..
					"\nDefined Methods: %s"
				ErrorUp(string.format(message, serviceName, eventName, serviceName, listOfAllMethods))
			end
		end
		
		--Handle creation of a new client event
		function THAT_EVENT.new(serviceName, eventName)
			local serverEvents = THAT_BASE_DIR[serviceName]["Server Events"]
			
			--Define private fields for use by this class
			local newEvent = {
				_serviceName = serviceName,
				_eventName = eventName,
				_serverEvents = serverEvents,
				_onId = 0,
				_signals = {}
			}
			
			return setmetatable(newEvent, THAT_EVENT)
		end
		
		--Connects a handler to a new singal and stores it in this event
		function THAT_EVENT:Connect(handler)
			local signal = Signal.new(handler, self)
			self._signals[signal] = true
			return signal
		end
		
		--Disconnects all the siginals
		function THAT_EVENT:DisconnectAll()
			self._signals = {}
		end
		
		--Disconnects a specific signal, or alias to DisconnectAll
		function THAT_EVENT:Disconnect(signal)
			if not signal then
				THAT_EVENT:DisconnectAll()
			else
				self._signals[signal] = nil
			end
		end
		
		--Fires all connections to this signal with the specified arguments
		function THAT_EVENT:Fire(...)
			local firedSomething = false
			for signal, _ in pairs(self._signals) do
				signal:Fire(...)
				firedSomething = true
			end
			
			--If we didn't fire anything, log debug information
			if not firedSomething then
				local eventPath = string.format("%s.%s", self._serviceName, self._eventName)
				if not THAT_STARTED then
					--Server is firing BEFORE client has initialized fully
					local message = "Server is firing event %s before the client has initialized -" ..
						" Consider having client notify server when ready."
					warn(CONST_THAT_LOG_PREFIX .. string.format(message, eventPath))
				else
					--Client just hasn't connected to event
					local message = "No client-side connections for %s, dropping events. (Use %s:Connect(handler))"
					warn(CONST_THAT_LOG_PREFIX .. string.format(message, eventPath, eventPath))
				end
			end
		end
		
		
		--Setup client values
		ROOT_DIR = That.Controllers
		ROOT_NAME = "Controller"
		
		--Setup client methods
		That.CreateController = CreateService --Controllers = Services on client
		That.GetController = GetService
		
		--Setup client event connection
		
		--Handles an event from serviceName.eventName
		local function handleEventFromService(serviceName, eventName, ...)
			--Find the service event for the item
			local serviceEvent = That.Services[serviceName][eventName]
			
			--Fire it
			serviceEvent:Fire(...)
		end
		
		--Handles a new client remote event that we can use
		local function handleNewClientEvent(newClientEvent)
			--Get constants that are needed
			local serviceName = newClientEvent.Parent.Parent.Name
			local name = newClientEvent.Name
			
			--Setup a connection to the new remote event
			newClientEvent.OnClientEvent:Connect(function(...)
				handleEventFromService(serviceName, name, ...)
			end)
		end
		
		--Handle new service folders that are added
		local function handleNewServiceFolder(serviceFolder)
			--Make sure it's a folder
			if not serviceFolder:IsA("Folder") then return end
			
			--Find client events folder
			local clientEventsFolder = serviceFolder:WaitForChild("Client Events")
			
			--Create events for the existing children
			for _, item in ipairs(clientEventsFolder:GetChildren()) do
				handleNewClientEvent(item)
			end
			
			--Create events for newer children
			clientEventsFolder.ChildAdded:Connect(handleNewClientEvent)
		end
		
		--Wait for services to load
		for serviceName, methods in pairs(authKeys) do
			THAT_BASE_DIR:WaitForChild(serviceName)
		end
		
		--Handle loaded services
		for _, serviceFolder in ipairs(THAT_BASE_DIR:GetChildren()) do
			handleNewServiceFolder(serviceFolder)
		end
	else
		--Setup root directory
		ROOT_DIR = That.Services
		
		--Setup server methods
		That.CreateService = CreateService
		That.GetService = GetService
		
		--Setup server event proxy
		THAT_EVENT = {}
		THAT_EVENT.__index = THAT_EVENT
		
		--Creates a new client event
		function THAT_EVENT.new(root, name)
			--Find a remote event,
			local remote = root:FindFirstChild(name)
			if not remote then
				--Or create a new one
				remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = root
			end
			
			--Create an event, with private field remoteEvent
			local newEvent = {
				_remoteEvent = remote,
			}
			
			setmetatable(newEvent, THAT_EVENT)
			
			--Return newly created event
			return newEvent
		end
		
		--Fires item if the condition function doesn't exist or returns true
		function THAT_EVENT:FireIf(item, conditionF, ...)
			--Check for item being a list of players
			if typeof(item) == "table" then
				--Check for non-player contents
				for _, obj in pairs(item) do
					if not IsPlayer(obj) then
						error("ClientEvent:Fire(players, ...) requires players to be a valid table of only players")
					end
				end
				
				--Only contains players
				for _, obj in pairs(item) do
					--Do check for each
					self:FireIf(obj, conditionF, ...)
				end
				
			else
				--Check for player
				assert(IsPlayer(item),
					"ClientEvent:Fire(player, ...) requires a valid player object.")

				--Check for no or valid condition function
				assert((not conditionF) or typeof(conditionF) == "function", 
					"The condition function passed must be a valid function")

				--Fire event if there is no condition function, OR condition function returns true
				if (not conditionF) or conditionF(item) then
					self._remoteEvent:FireClient(item, ...)
				end
			end
		end
		
		--Fires a player if the condition function passes, acts on every player
		function THAT_EVENT:FireAllIf(conditionF, ...)
			self:FireIf(Players:GetPlayers(), conditionF, ...)
		end
		
		--Fires a player, or players if item is a table of players
		function THAT_EVENT:Fire(item, ...)
			self:FireIf(item, nil, ...)
		end
		
		--Fires all players
		function THAT_EVENT:FireAll(...)
			self:Fire(Players:GetPlayers(), ...)
		end
		
		--Fires all players that aren't the passed player
		function THAT_EVENT:FireOthers(plr, ...)
			self:FireIf(Players:GetPlayers(), function(item)
				return item ~= plr
			end)
		end
		
		--Name aliases that are commonly used, feel free to add your own
		THAT_EVENT.FireClient = THAT_EVENT.Fire
		THAT_EVENT.FireClients = THAT_EVENT.Fire
		THAT_EVENT.FireAllClients = THAT_EVENT.FireAll
		THAT_EVENT.FireOtherClients = THAT_EVENT.FireOthers
	end
	
	--Setup metatable
	THAT_METATABLE = {
		__index = function(tab, index)
			if rawget(ROOT_DIR, index) then
				--Allow That.ServiceName instead of That.Services.ServiceName
				return ROOT_DIR[index]
			elseif That[index] and index ~= "Start" then
				--Normal indexing behavior, but don't foward Start method
				return That[index]
			end
		end
	}
	
	--Save settings for later use
	THAT_OPTIONS = options
	
	--Define start for debugging purposes
	local start = os.clock()
	
	--Set attributes on Base folder, if it's the server
	if not isClient then
		THAT_BASE_DIR:SetAttribute("THAT_LOADED", false)
		THAT_BASE_DIR:SetAttribute("THAT_INITED", false)
		THAT_BASE_DIR:SetAttribute("THAT_STARTED", false)
	end
	
	--Allow references to be LazyLoaded (meaning they are required only once requested to be used)
	if options.References then
		AssertUp(typeof(options.References) == "table", 
			"That:Start(options) failed, options.References must be a table of instance")
		for name, root in pairs(options.References) do
			AssertUp(typeof(name) == "string", 
				"That:Start(options) failed, options.References must be a table of instance")
			AssertUp(typeof(root) == "Instance", 
				"That:Start(options) failed, options.References must be a table of instance")
			
			--Check for valid naming (Can't use stuff that already exists)
			if not That[name] then
				--Lazy load module scripts
				That[name] = LazyLoadModule(root)
			else
				ErrorUp(string.format("Cannot use That.%s as a reference name, as it is already in use.", name))
			end
		end
	end
	
	--Make function for handling requires
	local function HandleRequire(req)
		--Handle non-ModuleScript contents
		if not req:IsA("ModuleScript") then return end
		
		--If framework already started, it's too late
		if THAT_STARTED then
			local message = "Required items cannot be added after framework start (%s)"
			error(string.format(message, req:GetFullName()))
		end
		
		--Spawn the requiring
		SpawnThread(require, req)
	end
	
	--Require items that exist
	for _, req in ipairs(THAT_REQUIRE_DIR:GetChildren()) do
		HandleRequire(req)
	end
	
	--Support late-loaded requires (just in case™) (also replication can be weird so)
	THAT_REQUIRE_DIR.ChildAdded:Connect(HandleRequire)
	
	--If on server, mark services as loaded
	if not isClient then
		THAT_BASE_DIR:SetAttribute("THAT_LOADED", true)
	end
	
	--Toggle allowing Init & Start methods to run
	local initsInLimbo = {} --Solely for debugging which required items fail. Limbo = :Init() called, but never finished
	local initsInLimboLength = 0 --Because we can't do # with string keys, and table.insert is more annoying
	
	--This function will update the queue by processing it's current contents
	local function newUpdateQueue(isFirstCall)
		--Run init for contents
		while #THAT_QUEUE.ToInit > 0 do
			local last = table.remove(THAT_QUEUE.ToInit, #THAT_QUEUE.ToInit)
			
			local req = last.Required
			
			--Make sure :Init() exists
			if req.Init and typeof(req.Init) == "function" then
				--Mark this required item as in limbo
				initsInLimbo[last.Name] = true
				initsInLimboLength += 1
				
				--Spawn a thread to handle errors if they occur
				SpawnThread(function()
					--Store invoke time for logging
					last.InvokedAt = os.clock()
					
					--Init
					req:Init()
					
					--Remove from limbo
					initsInLimbo[last.Name] = nil
					initsInLimboLength -= 1
					
					--Log the initialization
					local formattedTime = FormatTime(os.clock() - last.InvokedAt)
					if os.clock() - start >= options.MaxInitTimeout then
						--We took too long, warn the user
						local message = CONST_THAT_LOG_PREFIX .. 
							'"%s" took %s to :Init(), but has now successfully initialized. Do not yield in :Init() methods!'
						warn(CONST_THAT_LOG_PREFIX .. string.format(message, last.Name, formattedTime))
					elseif options.DebugLog then
						--Init was normal, only log if options.DebugLog
						local message = CONST_THAT_LOG_PREFIX .. 
							'"%s" initialized (%s).'
						print(message:format(last.Name, formattedTime))
					end
					
					--Add required item to the start queue
					table.insert(THAT_QUEUE.ToStart, last)
					
					--Update the queue
					updateQueue()
				end)
			end
		end
		
		local alreadyWarned = false
		
		--Wait for inits to finish, if it's the original startup
		while not THAT_STARTED and initsInLimboLength > 0 do
			RunService.Stepped:Wait()
			
			--Check for max timeout
			if os.clock() - start >= options.MaxInitTimeout then
				if not alreadyWarned then
					--Get the required items that failed for logging
					local reqsName = ""
					for name, bool in pairs(initsInLimbo) do
						reqsName = reqsName .. ', "' .. name .. '"'
					end
					
					reqsName = string.sub(reqsName, 3)
				
					--Warn that some reqs failed
					local message = CONST_THAT_LOG_PREFIX ..
						"Some required item(s) failed to :Init within the set max timeout" ..
						"\nRequired items that have not successfully initialized: " .. reqsName ..
						"\nThat Framework will continue to wait until all services initialize."
					
					warn(message)
					alreadyWarned = true
				end
			end
		end
		
		--Mark required item as initialized if not already
		if not THAT_INITED then
			THAT_INITED = true
			
			--If on server, mark services as inited
			if not isClient then
				THAT_BASE_DIR:SetAttribute("THAT_INITED", true)
			end

			--Log inited if logging enabled
			if THAT_OPTIONS.DebugLog then
				print(CONST_THAT_LOG_PREFIX .. "All required items initialized in " .. FormatTime(os.clock() - start) .. "!")
			end
		end
		
		--Run start for contents
		while #THAT_QUEUE.ToStart > 0 do
			local last = table.remove(THAT_QUEUE.ToStart, #THAT_QUEUE.ToStart)
			
			local req = last.Required
			
			--Make sure start function exists
			if req.Start and typeof(req.Start) == "function" then
				--If logging is enabled, log that this req was started
				if THAT_OPTIONS.DebugLog then
					local message = CONST_THAT_LOG_PREFIX .. '"%s" started.'
					print(message:format(last.Name))
				end
				
				--Start required item in a new thread
				SpawnThread(req.Start, req)
			end
			
			--If we are the server, and a Stop function exists, bind to close stop methods
			if not isClient and req.Stop and typeof(req.Stop) == "function" then
				game:BindToClose(req.Stop)
			end
		end
	end
	
	--Run update for required items that have already been loaded in
	newUpdateQueue()
	
	--Allow newer required items to update the queue aswell, now that we guarentee initial processing happened
	updateQueue = newUpdateQueue
	
	--Setup server only stuff
	if not isClient then
		--Setup a random number generator for generating keys
		local KeyGen = Random.new()
		
		--Setup player event data for listeners
		local function PlayerAdded(plr)
			
			--Initialiaze auth keys
			local keysToGive = {}
			local data = {}

			--Assign an auth key for every method of every service
			for serviceName, service in pairs(That.Services) do
				keysToGive[serviceName] = {}
				data[serviceName] = {}
				
				if service.Client and typeof(service.Client == "table") then
					--Assign an auth key for every valid method
					for methodName, method in pairs(service.Client) do
						if typeof(method) == "function" then
							--Assign auth keys
							local key1 = generateAuthKey(KeyGen)
							local key2 = generateAuthKey(KeyGen)
							keysToGive[serviceName][methodName] = {
								AuthKey1 = key1,
								AuthKey2 = key2,
							}

							--Setup the auth key generator for the server, and data holding place
							data[serviceName][methodName] = {
								OnId = 0,
								Ratelimit = {
									LastCall = 0,
									Bucket = 0,
								},
								EventData = {},
								AuthKeyGen1 = Random.new(key1),
								AuthKeyGen2 = Random.new(key2),
							}
						end
					end
				end
			end
			
			
			--Define new data
			local newData = {
				ServiceData = data,
				KeysToGive = keysToGive,
				DidHandshake = false,
			}
			
			--Set their data to new data
			serviceData[plr.UserId] = newData
		end

		local function PlayerRemoved(plr)
			serviceData[plr.UserId] = nil --Clear all data (garbage collection)
		end

		--Run for players that may already exist due to slow script speeds
		for _, plr in ipairs(Players:GetPlayers()) do
			PlayerAdded(plr)
		end

		--Run for new players, and players disconnecting
		Players.PlayerAdded:Connect(PlayerAdded)
		Players.PlayerRemoving:Connect(PlayerRemoved)
		
		--Setup handshake now that we are ready
		local handshake = Instance.new("RemoteFunction")
		handshake.Name = CONST_THAT_HANDSHAKE_NAME
		
		function handshake.OnServerInvoke(plr)
			--Check that they still exist
			local data = serviceData[plr.UserId]
			if data then
				--Make sure they haven't had a handshake yet
				if data.DidHandshake then
					--If they have, handle the invalid action
					THAT_OPTIONS.HandleInvalidAction(plr, 0)
					return false
				end
				
				--Mark handshake as done
				data.DidHandshake = true
				
				local keysToGive = data.KeysToGive --Get the keys they should have
				data.KeysToGive = nil --We no longer need to store this data
				
				--Give them the keys, as well as expiration time
				return keysToGive
			end
			return false
		end
		
		handshake.Parent = THAT_BASE_DIR
		
		--Don't check every frame, but check often enough that data is removed fast enough
		local interval = options.ClearDataAfter / 5 
		local lastCheck = time()
		local lastCheckFinished = true
		
		--Setup check to clear unused data after ClearDataAfter
		RunService.Stepped:Connect(function()
			--See if we should run check
			if time() - lastCheck < interval and lastCheckFinished then return end
			
			--Mark last check as now
			lastCheck = time()
			lastCheckFinished = false
			
			--Run check
			for _, user in pairs(serviceData) do
				for _, service in pairs(user.ServiceData) do	
					for _, event in pairs(service) do
						for id, item in pairs(event.EventData) do
							--Check if data has expired, if the data has been processed
							if item.Processed and time() - item.Time >= options.ClearDataAfter then
								--Clear data
								event.EventData[id] = nil
							end
						end
					end
				end
			end
			
			--Mark check as done
			lastCheckFinished = true
		end)
	end
	
	--Mark That Framework as started
	THAT_STARTED = true
	
	--Set attributes on Base folder
	if not isClient then
		THAT_BASE_DIR:SetAttribute("THAT_STARTED", true)
	end

	--Log started if logging enabled
	if THAT_OPTIONS.DebugLog then
		local message = "%sFramework fully started! Total time to start: %s"
		print(message:format(CONST_THAT_LOG_PREFIX, FormatTime(os.clock() - start)))
	end
end

--And that's a wrap!
return That
