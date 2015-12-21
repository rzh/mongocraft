
-- queue containing the updates that need to be applied to the minecraft world
UpdateQueue = nil
-- array of container objects
Containers = {}
-- 
SignsToUpdate = {}

-- as a lua array cannot contain nil values, we store references to this object
-- in the "Containers" array to indicate that there is no container at an index
EmptyContainerSpace = {}

-- Tick is triggered by cPluginManager.HOOK_TICK
function Tick(TimeDelta)
	UpdateQueue:update(MAX_BLOCK_UPDATE_PER_TICK)
end

-- Plugin initialization
function Initialize(Plugin)
	Plugin:SetName("MongoDB")
	Plugin:SetVersion(1)

	UpdateQueue = NewUpdateQueue()

	-- Hooks

	cPluginManager:AddHook(cPluginManager.HOOK_WORLD_STARTED, WorldStarted);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_JOINED, PlayerJoined);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_USING_BLOCK, PlayerUsingBlock);
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATING, OnChunkGenerating);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_FOOD_LEVEL_CHANGE, OnPlayerFoodLevelChange);
	cPluginManager:AddHook(cPluginManager.HOOK_TAKE_DAMAGE, OnTakeDamage);
	cPluginManager:AddHook(cPluginManager.HOOK_WEATHER_CHANGING, OnWeatherChanging);
	cPluginManager:AddHook(cPluginManager.HOOK_SERVER_PING, OnServerPing);
	cPluginManager:AddHook(cPluginManager.HOOK_TICK, Tick);

	-- Command Bindings

	cPluginManager.BindCommand("/mongo", "*", MongoCommand, " - mongo CLI commands")

	Plugin:AddWebTab("MongoDB",HandleRequest_MongoDB)

	-- make all players admin
	cRankManager:SetDefaultRank("Admin")

	setupPanel()

	
	LOG("Initialised " .. Plugin:GetName() .. " v." .. Plugin:GetVersion())

	return true
end

-- updateStats update CPU and memory usage displayed
-- on container sign (container identified by id)
function updateStats(id, mem, cpu)
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			Containers[i]:updateMemSign(mem)
			Containers[i]:updateCPUSign(cpu)
			break
		end
	end
end

-- getStartStopLeverContainer returns the container
-- id that corresponds to lever at x,y coordinates
function getStartStopLeverContainer(x, z)
    LOG("Lever address " .. x .. "   " .. z)
	for i=1, table.getn(Containers)
	do
	    LOG("Infor: check mongodb " .. i)
	    LOG("Container: " .. Containers[i].x .. "  " .. Containers[i].z)
		if Containers[i] ~= EmptyContainerSpace and x == Containers[i].x + 1 and z == Containers[i].z + 1
		then
			return Containers[i].id
		end
	end
	LOG("Warning: failed to find mongodb id for lever")
	return ""
end

-- getRemoveButtonContainer returns the container
-- id and state for the button at x,y coordinates
function getRemoveButtonContainer(x, z)
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and ( x == Containers[i].x + 2 or (x - 4) == Containers[i].x) and z == Containers[i].z + 3
		then
			return Containers[i].id, Containers[i].running
		end
	end
	return "", true
end

-- destroyContainer looks for the first container having the given id,
-- removes it from the Minecraft world and from the 'Containers' array
function destroyContainer(id)
	LOG("destroyContainer: " .. id)
	-- loop over the containers and remove the first having the given id
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			-- remove the container from the world
			Containers[i]:destroy()
			os.execute("/home/vagrant/gosrc/src/mongoproxy/mongoproxy \"killmongo?id=" .. id .. "\&rs=rs1\"")
			-- if the container being removed is the last element of the array
			-- we reduce the size of the "Container" array, but if it is not, 
			-- we store a reference to the "EmptyContainerSpace" object at the
			-- same index to indicate this is a free space now.
			-- We use a reference to this object because it is not possible to
			-- have 'nil' values in the middle of a lua array.
			if i == table.getn(Containers)
			then
				table.remove(Containers, i)
				-- we have removed the last element of the array. If the array
				-- has tailing empty container spaces, we remove them as well.
				while Containers[table.getn(Containers)] == EmptyContainerSpace
				do
					table.remove(Containers, table.getn(Containers))
				end
			else
				Containers[i] = EmptyContainerSpace
			end
			-- we removed the container, we can exit the loop
			break
		end
	end
end

-- updateContainer accepts 3 different states: running, stopped, created
-- sometimes "start" events arrive before "create" ones
-- in this case, we just ignore the update
function updateContainer(id,name,imageRepo,imageTag,state)
	LOG("Update container with ID: " .. id .. " state: " .. state)

	-- first pass, to see if the container is
	-- already displayed (maybe with another state)
	for i=1, table.getn(Containers)
	do
		-- if container found with same ID, we update it
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			Containers[i]:setInfos(id,name,imageRepo,imageTag,state == CONTAINER_RUNNING)
			Containers[i]:display(state == CONTAINER_RUNNING)
			LOG("found. updated. now return")
			return
		end
	end

	-- if container isn't already displayed, we see if there's an empty space
	-- in the world to display the container
	x = CONTAINER_START_X
	index = -1

	for i=1, table.getn(Containers)
	do
		-- use first empty location
		if Containers[i] == EmptyContainerSpace
		then
			LOG("Found empty location: Containers[" .. tostring(i) .. "]")
			index = i
			break
		end
		x = x + CONTAINER_OFFSET_X			
	end

	container = NewContainer()
	container:init(x,CONTAINER_START_Z)
	container:setInfos(id,name,imageRepo,imageTag,state == CONTAINER_RUNNING)
	container:addGround()
	container:setRS(rs)
	container:display(state == CONTAINER_RUNNING)

	if index == -1
		then
			table.insert(Containers, container)
		else
			Containers[index] = container
	end
end

--
function WorldStarted(World)
	y = GROUND_LEVEL
	-- just enough to fit one container
	-- then it should be dynamic
	for x= GROUND_MIN_X, GROUND_MAX_X
	do
		for z=GROUND_MIN_Z,GROUND_MAX_Z
		do
			setBlock(UpdateQueue,x,y,z,E_BLOCK_WOOL,E_META_WOOL_WHITE)
		end
	end	
end

--
function PlayerJoined(Player)
	-- enable flying
	Player:SetCanFly(true)

	-- refresh containers
	LOG("player " .. Player .. " joined")
	-- r = os.execute("goproxy containers")
	-- LOG("executed: goproxy containers -> " .. tostring(r))
end

-- 
function PlayerUsingBlock(Player, BlockX, BlockY, BlockZ, BlockFace, CursorX, CursorY, CursorZ, BlockType, BlockMeta)
	LOG("Using block: " .. tostring(BlockX) .. "," .. tostring(BlockY) .. "," .. tostring(BlockZ) .. " - " .. tostring(BlockType) .. " - " .. tostring(BlockMeta))

	-- lever: 1->OFF 9->ON (in that orientation)
	-- lever
	if BlockType == 69
	then
		containerID = getStartStopLeverContainer(BlockX,BlockZ)
		LOG("Using lever associated with container ID: " .. containerID)

		if containerID ~= ""
		then
			-- stop
			if BlockMeta == 1
			then
				Player:SendMessage("stop mongod" .. string.sub(containerID,1,8))
			-- start
			else 
				Player:SendMessage("start mongod" .. string.sub(containerID,1,8))
			end
		else
			LOG("WARNING: no ID attached to this lever")
		end
	end

	-- stone buttoe
	if BlockType == 77
	then
	    -- if this is create instance button
	    LOG("Clicked button " .. BlockX .. " | " .. BlockZ)
	    if BlockX == 7 and BlockZ == 4 - 5
	    then
			os.execute("/home/vagrant/gosrc/src/mongoproxy/mongoproxy \"newmongo?id=" .. table.getn(Containers)+1 .. "\&rs=rs1\"")
			updateContainer(table.getn(Containers) + 1,"test","","",CONTAINER_CREATED)
        else
            containerID, running = getRemoveButtonContainer(BlockX,BlockZ)

                Player:SendMessage("destroy mongod instance " .. string.sub(containerID,1,8))
                destroyContainer(containerID)
        end
	end
end


function OnChunkGenerating(World, ChunkX, ChunkZ, ChunkDesc)
	-- override the built-in chunk generator
	-- to have it generate empty chunks only
	ChunkDesc:SetUseDefaultBiomes(false)
	ChunkDesc:SetUseDefaultComposition(false)
	ChunkDesc:SetUseDefaultFinish(false)
	ChunkDesc:SetUseDefaultHeight(false)
	return true
end


function HandleRequest_MongoDB(Request)
	
	content = "[mongoclient]"

	if Request.PostParams["action"] ~= nil then

		action = Request.PostParams["action"]

		-- receiving informations about one container
		
		if action == "containerInfos"
		then
			LOG("EVENT - containerInfos")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]
			running = Request.PostParams["running"]

			-- LOG("containerInfos running: " .. running)

			state = CONTAINER_STOPPED
			if running == "true" then
				state = CONTAINER_RUNNING
			end

			updateContainer(id,name,imageRepo,imageTag,state)
		end

		if action == "startContainer"
		then
			LOG("EVENT - startContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_RUNNING)
		end

		if action == "createContainer"
		then
			LOG("EVENT - createContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_CREATED)
		end

		if action == "updateMongoStatus"
		then
			-- LOG("EVENT - updateMongoStatus")

			name = Request.PostParams["name"]
			rs = Request.PostParams["rs"]
			id = Request.PostParams["id"]
			isPrimary = Request.PostParams["isPrimary"]
			connections = Request.PostParams["connection"]

			LOG("Connection: " .. connections)

            for i=1, table.getn(Containers)
            do
                -- if container found with same ID, we update it
                if Containers[i] ~= EmptyContainerSpace and ( Containers[i].id == id or Containers[i].id .. "" == id)
                then
                    Containers[i]:setInfos(id,name,imageRepo,imageTag,true)
                    Containers[i]:updateMongoState(isPrimary == "true" or isPrimary == true, connections)
                    Containers[i]:display(state == CONTAINER_RUNNING)

                    LOG("Update status for " .. id )
                    content = content .. "{action:\"" .. action .. "\"}"
                    content = content .. "[/mongoclient]"
                    return content
                end
            end
            content = content .. "{error:\"action requested\"}"
            content = content .. "[/mongoclient]"
            return content
		end

		if action == "stopContainer"
		then
			LOG("EVENT - stopContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_STOPPED)
		end

		if action == "destroyContainer"
		then
			LOG("EVENT - destroyContainer")
			id = Request.PostParams["id"]
			destroyContainer(id)
		end

		if action == "stats"
		then
			id = Request.PostParams["id"]
			cpu = Request.PostParams["cpu"]
			ram = Request.PostParams["ram"]

			updateStats(id,ram,cpu)
		end


		content = content .. "{action:\"" .. action .. "\"}"

	else
		content = content .. "{error:\"action requested\"}"

	end

	content = content .. "[/mongoclient]"

	return content
end

function OnPlayerFoodLevelChange(Player, NewFoodLevel)
	-- Don't allow the player to get hungry
	return true, Player, NewFoodLevel
end

function OnTakeDamage(Receiver, TDI)
	-- Don't allow the player to take falling or explosion damage
	if Receiver:GetClass() == 'cPlayer'
	then
		if TDI.DamageType == dtFall or TDI.DamageType == dtExplosion then
			return true, Receiver, TDI
		end
	end
	return false, Receiver, TDI
end

function OnServerPing(ClientHandle, ServerDescription, OnlinePlayers, MaxPlayers, Favicon)
	-- Change Server Description
	ServerDescription = "A MongoDB client for Minecraft"
	-- Change favicon
	if cFile:IsFile("/srv/logo.png") then
		local FaviconData = cFile:ReadWholeFile("/srv/logo.png")
		if (FaviconData ~= "") and (FaviconData ~= nil) then
			Favicon = Base64Encode(FaviconData)
		end
	end
	return false, ServerDescription, OnlinePlayers, MaxPlayers, Favicon
end				

-- Make it sunny all the time!
function OnWeatherChanging(World, Weather)
	return true, wSunny
end

-- this is the control panel for the world


