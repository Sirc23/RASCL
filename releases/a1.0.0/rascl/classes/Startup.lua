Startup = {}
Startup.__index = Startup

function Startup:new()
	local r = setmetatable({}, self)
	
	r.storage = {}
	r.craftableItems = {}
	
	r.containers = {}
	
	r.filters = {}
	
	r.recipes = {}
	
	r.mods = {}
	r.mod_ids = {}
	
	r.peripherals = {}
	r.turtles = {}
	r.turtleTask = {}
	
	r.clipboard = ""
	--[[
	r.ui_mainMenu = nil
		r.ui_debug = nil
		r.ui_items = nil
		r.ui_crafting = nil
		r.ui_containers = nil
		r.ui_filters = nil
	--]]
	return r
end

function Startup:initializeUI()
	while not basalt.getMainFrame() do
		os.sleep()
	end
	self.ui_mainMenu = self:initMainMenu(basalt.getMainFrame())
		
		self.ui_items = self:initItems(basalt.getMainFrame())
		self.ui_crafting = self:initCrafting(basalt.getMainFrame())
		self:initContainers(basalt.getMainFrame())
		self:initFilters(basalt.getMainFrame())
		self:initConfigEditor(basalt.getMainFrame())
		self:initModEditor(basalt.getMainFrame())
		
		if debugMode then
			self.ui_debug = self:initDebug(basalt.getMainFrame())
		end
		
		for _, child in pairs(basalt.getMainFrame():getChild("currentTab").children) do
			child.visible = false
		end
		basalt.getMainFrame():getChild("currentTab/Items").visible = true
		
	parallel.waitForAll(function() self:defineMods() end)
	parallel.waitForAll(function() self:defineFilters() end)
	parallel.waitForAll(function() self:defineTurtles() end)
	parallel.waitForAll(function() self:defineRecipes() end)
	parallel.waitForAll(function() self:defineContainers(self.ui_mainMenu) end)
	
	
end

function Startup:initMainMenu(container)
	
	local r = container:addFrame({
		width = termX,
		height = 1,
		x = 1,
		y = 1,
		background = colors.red,
		foreground = colors.black,
		name = "banner"
	})
	
	
	local currentTabLabel = r:addLabel({
		height = 1,
		x = 4,
		y = 1,
		background = colors.yellow,
		foreground = colors.black,
		name = "currentTabLabel",
		text = "Items"
	})
	
	local currentTab = container:addFrame({
		width = termX,
		height = termY - 1,
		x = 1,
		y = 2,
		background = colors.lightGray,
		name = "currentTab"
	})
	
	local toggleMenu = r:addButton({
        width = 3,
        height = 1,
        x = 1,
        y = 1,
		backgroundEnabled = false,
		foreground = colors.black,
        text = "\16|",
		name = "toggleMenu"
    })
	toggleMenu:onClick(function(element)
		local navigationMenu = element.parent.parent:getChild("navigationMenu")
		navigationMenu.visible = not navigationMenu.visible
		local versionLabel = element.parent.parent:getChild("versionLabel")
		versionLabel.visible = not versionLabel.visible
		if navigationMenu.visible then
			--Simulate click so that onBlur works for navigationMenu
			basalt.schedule(function()
				os.queueEvent("mouse_click", 1, 1, termY)
			end)
			element.text = "\31|"
		else
			element.text = "\16|"
		end
	end)
	
	self.menuNodes = {
		{text = "Items", background = colors.red, foreground = colors.black},
		{text = "Crafting", background = colors.purple, foreground = colors.black},
		{text = "Containers", background = colors.green, foreground = colors.black},
		{text = "Filters", background = colors.blue, foreground = colors.black}, 
		{text = "Mods", background = colors.lightBlue, foreground = colors.black},
		{text = "Palettes", background = colors.orange, foreground = colors.black},
		{text = "Configs", background = colors.gray, foreground = colors.white}
	}
	if debugMode then table.insert(self.menuNodes, {text = "Debug", background = colors.yellow, foreground = colors.black}) end
	
	local versionLabel = container:addLabel({
		height = 1,
		x = math.floor((1 + #version) / 2) + 1,
		y = container.height,
		z = 2000,
		foreground = colors.black,
		text = "v" .. version,
		visible = false,
		name = "versionLabel"
	})
	
	local navigationMenu = container:addTree({
		width = 13,
		height = termY - 1,
		x = -1,
		y = 2,
		z = 1000,
		visible = false,
		background = colors.lightGray,
		foreground = colors.black,
		selectedBackgroundColor = colors.gray,
		--selectedForegroundColor = colors.black,
		showScrollBar = false,
		nodes = self.menuNodes,
		name = "navigationMenu"
	})
	navigationMenu:onSelect(function(element, node)
		local foundValue = nil
		for _, value in ipairs(self.menuNodes) do
			if node.text == value.text then
				foundValue = value
				break
			end
		end
		if foundValue ~= nil then
			element.selectedNode = nil
			
			element.parent:getChild("banner").background = foundValue.background
			element.parent:getChild("banner").foreground = foundValue.foreground
			
			element.parent:getChild("banner/toggleMenu").foreground = foundValue.foreground
			element.parent:getChild("banner/toggleMenu"):setForegroundState("clicked", foundValue.foreground)
			
			element.parent:getChild("banner/currentTabLabel").text = foundValue.text
			element.parent:getChild("banner/currentTabLabel").foreground = foundValue.foreground
			
			for _, child in pairs(element.parent:getChild("currentTab").children) do
				child.visible = false
				if child.name == foundValue.text then
					child.visible = true
				end
			end
			
			element.visible = false
			element.parent:getChild("versionLabel").visible = false
			element.parent:getChild("banner/toggleMenu").text = "\16|"
		end
	end)
	navigationMenu:onBlur(function(element)
		if navigationMenu.visible then
			toggleMenu:fireEvent("mouse_click")
		end
	end)
	
	local breakerLabel = r:addLabel({
		height = 1,
		x = termX - 4,
		y = 1,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = " ",
		name = "breakerLabel"
	})
	
	local switchItems = r:addButton({
		width = 1,
		height = 1,
		x = termX - 3,
		y = 1,
		background = self.menuNodes[1].background,
		foreground = self.menuNodes[1].foreground,
		text = "I",
		name = "switchItems"
	})
	switchItems:setBackgroundState("clicked", colors.gray)
	switchItems:onClick(function(element)
		element.parent.parent:getChild("navigationMenu"):fireEvent("node_select", self.menuNodes[1])
	end)
	
	local switchCrafting = r:addButton({
		width = 1,
		height = 1,
		x = termX - 2,
		y = 1,
		background = self.menuNodes[2].background,
		foreground = self.menuNodes[2].foreground,
		text = "C",
		name = "switchCrafting"
	})
	switchCrafting:setBackgroundState("clicked", colors.gray)
	switchCrafting:onClick(function(element)
		element.parent.parent:getChild("navigationMenu"):fireEvent("node_select", self.menuNodes[2])
	end)
	
	local switchContainers = r:addButton({
		width = 1,
		height = 1,
		x = termX - 1,
		y = 1,
		background = self.menuNodes[3].background,
		foreground = self.menuNodes[3].foreground,
		text = "c",
		name = "switchContainers"
	})
	switchContainers:setBackgroundState("clicked", colors.gray)
	switchContainers:onClick(function(element)
		element.parent.parent:getChild("navigationMenu"):fireEvent("node_select", self.menuNodes[3])
	end)
	
	local switchFilters = r:addButton({
		width = 1,
		height = 1,
		x = termX,
		y = 1,
		background = self.menuNodes[4].background,
		foreground = self.menuNodes[4].foreground,
		text = "F",
		name = "switchFilters"
	})
	switchFilters:setBackgroundState("clicked", colors.gray)
	switchFilters:onClick(function(element)
		element.parent.parent:getChild("navigationMenu"):fireEvent("node_select", self.menuNodes[4])
	end)
	
	container:onKey(function(element, key)
		if key == keys.leftShift then
			shiftDown = true
		elseif key == keys.leftCtrl then
			ctrlDown = true
		end
		if shiftDown then
			cartAmount = 64
		elseif ctrlDown then
			cartAmount = 16
		else
			cartAmount = 1
		end
	end)
	container:onKeyUp(function(element, key)
		if key == keys.leftShift then
			shiftDown = false
		elseif key == keys.leftCtrl then
			ctrlDown = false
		end
		if shiftDown then
			cartAmount = 64
		elseif ctrlDown then
			cartAmount = 16
		else
			cartAmount = 1
		end
	end)
	
	if not isHost then
		--Update the display every second to refresh any UI changes
		local f = function()
			while true do
				r:updateLayout()
				os.sleep(0.5)
			end
		end
		table.insert(parallelProcesses, f)
	end
	
	--Allows user to shift/ctrl click a stock item on the very first click
	--Without this, the UI does not recognize the shift/ctrl keys being pressed
	r:mouse_click(0, 1, 2)
	
	return r
end

function Startup:initDebug(container)
	
	local frame = container:getChild("currentTab"):addFrame({
		width = termX,
		height = termY - 1,
		x = 1,
		y = 1,
		background = colors.white,
		name = "Debug"
	})
	local r = frame
	
	local debugLog = frame:addTextBox({
		width = frame.width,
		height = frame.height,
		x = 1,
		y = 1,
		backround = colors.white,
		foreground = colors.black,
		editable = true,
		name = "debugLog"
	})
	debugLog.lines[1] = "Debug initialized"
end

function Startup:initItems(container)
    local ui = container:getChild("currentTab"):addFrame({
        width = container.width - 2,
        height = container.height - 1,
        x = 2,
        y = 1,
        background = colors.lightGray,
		name = "Items"
    })
	
    local r = ui
	
    local tabs = ui:addTabControl({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        headerBackground = colors.lightGray,
        activeTabBackground = colors.yellow,
        scrollableTab = true,
		name = "tabs"
    })
    
    local stockTab = tabs:newTab("Stock")
    ui_stock = stockTab:addScrollFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray 
    })
	
	ui_stockManager = UI_Stock:new(ui_stock)
	
    local cartTab = tabs:newTab("Cart")
    ui_cart = cartTab:addFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray
    })
	
    ui_cartManager = UI_Cart:new(ui_cart)
	
	return r
end

function Startup:initCrafting(container)
	local ui = container:getChild("currentTab"):addFrame({
        width = container.width - 2,
        height = container.height - 1,
        x = 2,
        y = 1,
        background = colors.lightGray,
		name = "Crafting"
    })
	
    local r = ui
	
    local tabs = ui:addTabControl({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        headerBackground = colors.lightGray,
        activeTabBackground = colors.yellow,
        scrollableTab = true,
		name = "tabs"
    })
    
    local craftTab = tabs:newTab("Craft")
    ui_craft = craftTab:addScrollFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray 
    })
	
	ui_craftManager = UI_Craft:new(ui_craft)
	
    local tasksTab = tabs:newTab("Tasks")
    ui_tasks = tasksTab:addFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray
    })
	
    ui_tasksManager = UI_Tasks:new(ui_tasks)
	
	local recipesTab = tabs:newTab("Recipes")
    ui_recipes = recipesTab:addFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray
    })
	
    ui_recipeManager = UI_Recipes:new(ui_recipes)
	
	return r
end

function Startup:initContainers(container)
	
	ui_containerManager = UI_Container:new(container:getChild("currentTab"))
	
end

function Startup:initFilters(container)
	ui_filterManager = UI_Filter:new(container:getChild("currentTab"))
end

function Startup:initConfigEditor(container)
	local ui = container:getChild("currentTab"):addFrame({
        width = container.width - 2,
        height = container.height - 1,
        x = 2,
        y = 1,
        background = colors.lightGray,
		name = "Configs"
    })
	
    local r = ui
	
    local tabs = ui:addTabControl({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        headerBackground = colors.lightGray,
        activeTabBackground = colors.yellow,
        scrollableTab = true,
		name = "tabs"
    })
    
    local clientTab = tabs:newTab("Client")
    ui_client = clientTab:addScrollFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray 
    })
	
	ui_clientConfigManager = UI_ConfigEditor:new(ui_client)
	
    local serverTab = tabs:newTab("Server")
    ui_server = serverTab:addFrame({
        width = ui.width,
        height = ui.height,
        x = 1,
        y = 1,
        background = colors.lightGray
    })
	
	ui_serverConfigManager = UI_ConfigEditor:new(ui_server, true)
	
	return r
end

function Startup:initModEditor(container)	
	ui_modManager = UI_ModEditor:new(container:getChild("currentTab"))
end


function Startup:validateTables()
	if(not fs.exists(config.filters .. ".csv")) then
		csv.create_table(config.filters, {"name","any","whitelist","visible","filterType","items"})
	end

	if(not fs.exists(config.containers .. ".csv")) then
		csv.create_table(config.containers, {"name","type","allocation"})
	end

	if(not fs.exists(config.mods .. ".csv")) then
		csv.create_table(config.mods, {"name","mod"})
	end
end

function Startup:defineMods()
	local temp_mods
	
	if not isHost then
		temp_mods = myTalker:request("modCSV", {})
		csv.delete(config.mods, function(row) return true end)
	else
		temp_mods = csv.select(config.mods)
	end
	
	for _, thisMod in pairs(temp_mods) do
		if not isHost then
			csv.insert(config.mods, thisMod)
		end
		self.mods[thisMod.mod] = thisMod.name
		self.mod_ids[thisMod.name] = thisMod.mod
	end
	ui_modManager:rebuildTable()
end

function Startup:defineRecipes()
	local temp_recipes
	
	if not isHost then
		temp_recipes = myTalker:request("recipeCSV", {})
		csv.delete(config.recipes, function(row) return true end)
	else
		temp_recipes = csv.select(config.recipes, function(row) return true end)
	end
	--asdf(#temp_recipes)
	for _, thisRecipe in pairs(temp_recipes) do
		if not isHost then
			csv.insert(config.recipes, thisRecipe)
		end
		
		local recipeObj = Recipe:new(thisRecipe)
		self.recipes[thisRecipe.uniqueID] = recipeObj
		if not master.craftableItems[recipeObj.primaryOutput.uniqueKey] then
			master.craftableItems[recipeObj.primaryOutput.uniqueKey] = {
				uniqueKey = recipeObj.primaryOutput.uniqueKey,
				name = recipeObj.primaryOutput.name,
				displayName = recipeObj.primaryOutput.displayName,
				mod = recipeObj.primaryOutput.mod,
				recipes = {recipeObj}
			}
		else
			table.insert(master.craftableItems[recipeObj.primaryOutput.uniqueKey].recipes, recipeObj)
			table.sort(master.craftableItems[recipeObj.primaryOutput.uniqueKey].recipes, function(a,b)
				return a.priority < b.priority
			end)
		end
	end
	ui_recipeManager:refreshUI()
	ui_craftManager:refreshUI()
end

function Startup:defineFilters()
	self.filters = {}
	local temp_filters
	if not isHost then
		temp_filters = myTalker:request("filterCSV", {})
		csv.delete(config.filters, function(row) return true end)
	else
		temp_filters = csv.select(config.filters, function(row) return true end)
	end
	for _, thisFilter in ipairs(temp_filters) do
		if not isHost then
			csv.insert(config.filters, thisFilter)
		end
		table.insert(self.filters, Filter:new(thisFilter["name"]))
	end
	
	ui_filterManager:rebuildTable()
end

function Startup:defineContainers(container)
	readyForInput = false
	
	for _, thisItem in pairs(self.storage) do
		thisItem:destroy()
	end
	local ui
	if debugMode then
		ui = self:initDefineContainersUI(container)
	else
		ui = self:initDefineContainersUI(basalt.getMainFrame())
	end
	
	for _, item in pairs(self.storage) do
		item:destroy()
	end
	for _, container in pairs(self.containers) do
		container:destroy()
	end
	self.storage = {}
	self.containers = {}
	
	if not isHost then
		local allContainers = myTalker:request("containerCSV", {})
		
		csv.delete(config.containers, function(row) return true end)
		for _, thisContainer in pairs(allContainers) do
			csv.insert(config.containers, thisContainer)
		end
	end
	
	--Get a list of all existing containers
	local CSVContainers = csv.select(config.containers, function(row) return true end)
	local containersInCSV = {}
	for _, CSVRecord in pairs(CSVContainers) do
		--If remote, *all* containers are included
		--If host, some containers may be newly attached and have not been registered yet
		self.containers[CSVRecord["name"]] = Container:new(CSVRecord["name"])
	end
	
	if isHost then
		--Get all containers hooked up to computer
		--Some containers might not be in self.containers yet
		for _, p in pairs(peripheral.getNames()) do
			local isAdjacent = (p == "left" or p == "right" or p == "top" or p == "bottom" or p == "front" or p == "back")
			if peripheral.hasType(p, "inventory") and not isAdjacent and not self.containers[p] then
				csv.insert(config.containers, {
					name = p,
					type = "ignore",
					allocation = ""
				})
				self.containers[p] = Container:new(p)
			end
		end
	end
	--By now, all containers should be initialized and the container CSV should be up-to-date
	if not self.model then
		self.model = {}
	end
	self.model.current = {}
	local model
	if isHost then
		model = Scanner:new(tonumber(config.max_scan_threads), {}, true)
	else
		model = myTalker:request("model", {})
	end
	
	for index, value in pairs(model) do
		self.model[index] = value
	end
	
	local totalContainers = #self.containers
	local completedContainers = 0
	
	for uniqueKey, gid in pairs(self.model.items) do
		self.storage[uniqueKey] = Item:new(gid)
		--asdf("Adding " .. uniqueKey)
	end
	for containerName, container in pairs(self.containers) do
		container:reconsider({isPhysicallyConnected = (self.model.missing[containerName] == false)})
		completedContainers = completedContainers + 1
		ui.update(completedContainers, totalContainers)
	end
	
	ui_containerManager:scheduleUpdate()
	ui_stockManager:refreshUI()
	ui_cartManager:refreshUI()
	
	ui_cartManager.ui_output.update()
	
	--Choose preferred output when initializing, if it exists
	local preferredContainer = master.containers[config.preferred_output]
	if preferredContainer and preferredContainer.type == "output" and not preferredContainer:missing() then
		ui_cartManager.ui_output.setSelected(preferredContainer.displayName)
	end
	
	ui:destroyAll()
	
	readyForInput = true
	
	if isHost then
		local newPacket = myTalker:makePacket("broadcast_containerInitUpdate", {})
		myTalker:broadcastPacket(newPacket)
	end
	
	initialized = true
	
end

function Startup:defineTurtles()
	self.turtles = {}
	if isHost then
		
		for _, thisName in pairs(peripheral.getNames()) do
			if startsWith(thisName, "turtle_") then
				
				if peripheral.call(thisName, "isOn") then
					peripheral.call(thisName, "reboot")
				else
					peripheral.call(thisName, "turnOn")
				end
				basalt.schedule(function()
					local turtleID = peripheral.call(thisName, "getID")
					if turtleID then
						myTalker:requestFrom(turtleID, "crafterHandshake", {
							peripheralName = thisName
						}, nil, true)
					end
				end)
			end
		end
	else
		self.turtles = myTalker:request("getTurtles", {})
	end
end

function Startup:initDefineContainersUI(container)
	local r = container:addScrollFrame({
		width = math.ceil(5 * termX / 6),
        height = 6,
        x = math.ceil(termX / 12),
        y = 2 + 6,
        z = 100,
        background = colors.gray,
		ignoreOffset = true,
		visible = false
    })
	r:addBorder({
		color = colors.yellow,
		top = true,
		left = true,
		right = true,
		bottom = true
	})
	
	local loadingBar = r:addProgressBar({
		width = r.width - 4,
		height = 2,
		x = 3,
		y = 3,
		background = colors.black,
		foreground = colors.white,
		progressColor = colors.orange,
		showPercentage = true,
		direction = "right",
		name = "loadingBar",
		visible = true
	})
	
	local ui_fraction = r:addLabel({
		x = 2,
		y = 5,
		foreground = colors.white,
		text = "",
		name = "fraction"
	})
	local wall = container:addFrame({
		width = termX,
		height = termY,
		x = 1,
		y = 1,
		z = 90,
		ignoreOffset = true,
		background = colors.black,
		visible = not debugMode
	})
	
	local addLabelText = "Scanning..."
	if not isHost then addLabelText = "Receiving data..." end
	r:addLabel({
		height = 1,
		x = math.ceil((r.width - #addLabelText) / 2) + 1,
		y = 2,
		foreground = colors.white,
		text = addLabelText
	})
	
	r.update = bindFunctionToInstance(r, function(element, numerator, denominator)
		local loader = element:getChild("loadingBar")
		local fraction = element:getChild("fraction")
		loader.progress = math.floor(numerator * 100 / denominator)
		fraction.text = tostring(numerator) .. "/" .. tostring(denominator)
	end)
	
	r.destroyAll = bindFunctionToInstance(r, function(element)
		wall:destroy()
		r:destroy()
	end)
	
	return r
end

function Startup:compressRecipe(data)
	local indices = {}
	local index = 1
	for i = 1, 16 do
		local thisSlot = data[i]
		if thisSlot then
			local foundIndex = false
			for j, thisIndex in pairs(indices) do
				if thisIndex.uniqueKey == thisSlot.uniqueKey then
					foundIndex = true
					indices[j].count = indices[j].count + 1
					table.insert(indices[j].slots, i)
					break
				end
			end
			if not foundIndex then
				indices[index] = data[i]
				indices[index].count = 1
				indices[index].slots = {i}
				index = index + 1
			end
		end
	end
	return indices
end

function Startup:decompressRecipe(data)
	local r = {}
	for _, thisIndex in pairs(data) do
		for _, i in pairs(thisIndex.slots) do
			r[i] = deepCopy(thisIndex)
			r[i].count = nil
			r[i].slots = nil
		end
	end
	return r
end

function Startup:handleInputChests()
	while isHost do
		if readyForInput then
			local lastChest = 0
			for _, container in pairs(self.containers) do
				if container.type == "input" and not container:missing() and peripheral.isPresent(container.name) then
					local list = peripheral.call(container.name, "list")
					if list then
						
						for slot, item in pairs(list) do
							if not item.nbt then item.nbt = "0" end
							local uniqueKey = item.name .. "|" .. item.nbt
							--asdf("Bringing in " .. container.name .. " @ " .. tostring(slot))
							basalt.schedule(function()
								container:exportItemToStorage(uniqueKey, slot)
								--Uncomment this if you want new items to auto-sort instead of appearing at the bottom of the list
								--ui_stockManager:refreshUI()
							end)
							os.sleep()
						end
						lastChest = 0
						os.sleep()
					end
				else
					lastChest = lastChest + 1
				end
				
				if lastChest >= tonumber(config.search_chests_per_tick) then
					lastChest = 0
					os.sleep()
				end
			end
		end
		os.sleep()
	end
end

function Startup:peripheralAttachLoop()
	local processed = {}
	while isHost do
		local event, name = os.pullEvent("peripheral")
		while (not master.containers) or (not master.model) do
			os.sleep()
		end
		
		asdf("ATTACH EVENT: " .. tostring(name))
		rednet.close(myTalker.modemName)
		myTalker.modemName, myTalker.modem = findModem()
		
		local isAdjacent = (name == "left" or name == "right" or name == "top" or name == "bottom" or name == "front" or name == "back")
		if isHost and peripheral.hasType(name, "inventory") and not isAdjacent then
			if master.containers[name] == nil then
				
				csv.insert(config.containers, {
					name = name,
					type = "ignore",
					allocation = ""
				})
				master.containers[name] = Container:new(name)
			end
			
			basalt.schedule(function()
				master.containers[name]:reconsider({isPhysicallyConnected = true})
				
				while master.model.current[name] == false do
					os.sleep()
				end
				
				ui_containerManager:scheduleUpdate()
				if master.containers[name].type == "output" then
					ui_cartManager.ui_output.scheduleUpdate()
				end
				
				local newPacket = myTalker:makePacket("broadcast_attachContainer", {
					containerName = name,
					model = master.containers[name]:exportModel()
				})
				myTalker:broadcastPacket(newPacket)
			end)
		end
	end
end

function Startup:peripheralDetachLoop()
	while isHost do
		local event, name = os.pullEvent("peripheral_detach")
		while (not master.containers) or (not master.model) do
			os.sleep()
		end
		asdf("DETACH EVENT: " .. name)
		rednet.close(myTalker.modemName)
		myTalker.modemName, myTalker.modem = findModem()
		
		local container = master.containers[name]
		
		if container and not peripheral.isPresent(name) then
			basalt.schedule(function()
				container:reconsider({isPhysicallyConnected = false})
				
				while master.model.current[name] == false do
					os.sleep()
				end
				
				ui_containerManager:scheduleUpdate()
				if master.containers[name].type == "output" then
					ui_cartManager.ui_output.scheduleUpdate()
				end
				
				local newPacket = myTalker:makePacket("broadcast_detachContainer", {
					containerName = name
				})
				myTalker:broadcastPacket(newPacket)
			end)
		end
	end
end

function Startup:copyToClipboard(data)
	self.clipboard = tostring(data)
	basalt.schedule(function()
		if basalt.getMainFrame():getChild("copyLine1") then
			basalt.getMainFrame():getChild("copyLine1"):destroy()
		end
		if basalt.getMainFrame():getChild("copyLine2") then
			basalt.getMainFrame():getChild("copyLine2"):destroy()
		end
		
		local line1 = basalt.getMainFrame():addLabel({
			width = math.max(7, #self.clipboard),
			height = 1,
			x = 1,
			y = termY - 1,
			z = 99999,
			autoSize = false,
			background = colors.black,
			foreground = colors.white,
			backgroundEnabled = true,
			text = "Copied:",
			name = "copyLine1"
		})
		local line2 = basalt.getMainFrame():addLabel({
			width = math.max(7, #self.clipboard),
			height = 1,
			x = 1,
			y = termY,
			z = 99999,
			autoSize = false,
			background = colors.black,
			foreground = colors.white,
			backgroundEnabled = true,
			text = self.clipboard,
			name = "copyLine2"
		})
		os.sleep(3.5)
		line1:destroy()
		line2:destroy()
	end)
end
