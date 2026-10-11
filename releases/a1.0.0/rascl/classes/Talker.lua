Talker = {}
Talker.__index = Talker

function Talker:listenForMessages()
	while true do
		while myTalker.ready do
			local packet = myTalker:receivePacket()
			if packet then
				if not packet.responseID then
					--If the host already answered this request before, resend the cached reply instead of re-running the handler. This is what makes it safe for the remote to blindly resend a request after a reconnect without double-execution.
					local alreadyHandled = isHost and myTalker:replayIfDuplicate(packet)
					if not alreadyHandled then
						myTalker.instructions[packet.instruction](packet)
					end
				else
					table.insert(myTalker.messages, packet)
				end
			end
		end
		os.sleep()
	end
end

local function validate(thing, reason, number)
	number = number or 0
	if thing == nil then
		error("Error thrown while handling Talker instruction: " .. tostring(reason) .. " #" .. tostring(number))
	end
end

function Talker:new(host, hostname)
	local r = setmetatable({}, self)
	
	r.protocol = config.server_protocol
	
	r.isHost = host
	r.hostname = hostname
	r.modem = nil
	r.modemName = nil
	
	--Received messages sit in this table until dealt with
	r.messages = {}
	
	--Find modem and turn it on
	r.modemName, r.modem = findModem()
	
	r.instructions = {
send_isInitialized	= function(packet)
			local data = {initialized = initialized}
			local newPacket = myTalker:makePacket("rec_isInitialized", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_isInitialized		= function(packet)
			validate(packet.data.initialized, packet.instruction)
			return packet.data.initialized
		end,
send_model	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			
			local data = {model = master.model}
			local newPacket = myTalker:makePacket("rec_model", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_model	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.model, packet.instruction, 1)
			return packet.data.model
		end,
send_modCSV			= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local data = csv.select(config.mods, function(row) return true end)
			local newPacket = myTalker:makePacket("rec_modCSV", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_modCSV			= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data, packet.instruction, 1)
			return packet.data
		end,
send_recipeCSV			= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local data = csv.select(config.recipes, function(row) return true end)
			local newPacket = myTalker:makePacket("rec_recipeCSV", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_recipeCSV			= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data, packet.instruction, 1)
			return packet.data
		end,
send_filterCSV			= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local data = csv.select(config.filters, function(row) return true end)
			local newPacket = myTalker:makePacket("rec_filterCSV", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_filterCSV			= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data, packet.instruction, 1)
			return packet.data
		end,
send_containerCSV		= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local data = csv.select(config.containers, function(row) return true end)
			local newPacket = myTalker:makePacket("rec_containerCSV", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_containerCSV		= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data, packet.instruction, 1)
			return packet.data
		end,
broadcast_attachContainer	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.containerName, packet.instruction, 1)
			validate(packet.data.model, packet.instruction, 2)
			basalt.schedule(function()
				while not master.containers do
					os.sleep()
				end
				
				local container
				if not master.containers[packet.data.containerName] then
					local CSVContainer = csv.select(config.containers, function(row) return row["name"] == packet.data.containerName end)
					if #CSVContainer < 1 then
						csv.insert(config.containers, {
							name = packet.data.containerName,
							type = "ignore",
							allocation = ""
						})
					end
					master.containers[packet.data.containerName] = Container:new(packet.data.containerName)
					container = master.containers[packet.data.containerName]
					
				else
					container = master.containers[packet.data.containerName]
				end
				
				container:addToModel(packet.data.model)
				
				container:reconsider({isPhysicallyConnected = (master.model.missing[packet.data.containerName] == false)})
			end)
		end,
broadcast_detachContainer	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.containerName, packet.instruction, 1)
			basalt.schedule(function()
				while not master.containers do
					os.sleep()
				end
				
				local container = master.containers[packet.data.containerName]
				if container then
					container:reconsider({isPhysicallyConnected = false})
				end
				
			end)
		end,
send_containerGetGidSlot	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.slot, packet.instruction, 2)
			local data = {
				gid = container.inventory[packet.data.slot]
			}
			local newPacket = myTalker:makePacket("rec_containerGetGidSlot", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_containerGetGidSlot		= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.gid, packet.instruction, 1)
			return packet.data.gid
		end,
send_containerInitUpdate	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			ui_containerManager.ui_update:fireEvent("mouse_click")
		end,
broadcast_containerInitUpdate	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			self.ready = false
			ui_containerManager.ui_update.runButton(ui_containerManager.ui_update)
			self.ready = true
		end,
send_containerInitCull	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			ui_containerManager.ui_cull:fireEvent("mouse_click")
		end,
broadcast_containerInitCull	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			ui_containerManager.ui_cull.runButton(ui_containerManager.ui_cull)
		end,
send_containerEditorSave	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.changes, packet.instruction, 2)
			container:saveChanges(packet.data.changes)
			local newPacket = myTalker:makePacket("broadcast_containerEditorSave", packet.data)
			myTalker:broadcastPacket(newPacket)
		end,
broadcast_containerEditorSave	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.changes, packet.instruction, 2)
			basalt.schedule(function()
				--Skip adding/removing item counts since the host already
				--Broadcast changes to item counts when it ran saveChanges
				container:saveChanges(packet.data.changes, true)
			end)
		end,
send_filterSwap	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			validate(packet.data.currentRow, packet.instruction, 1)
			validate(packet.data.direction, packet.instruction, 2)
			ui_filterManager:swapCurrentRow(packet.data.currentRow, packet.data.direction)
			local newPacket = myTalker:makePacket("broadcast_filterSwap", packet.data)
			myTalker:broadcastPacket(newPacket)
		end,
broadcast_filterSwap	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.currentRow, packet.instruction, 1)
			validate(packet.data.direction, packet.instruction, 2)
			
			ui_filterManager:swapCurrentRow(packet.data.currentRow, packet.data.direction)
		end,
send_filterUpdate	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			validate(packet.data.filterName, packet.instruction, 1)
			local theFilter
			--Check if filter exists
			for _, thisFilter in ipairs(master.filters) do
				if packet.data.filterName == thisFilter.name then
					theFilter = thisFilter
					break
				end
			end
			--Create if it does not exist
			if not theFilter then
				csv.insert(config.filters, {
					name = packet.data.filterName,
					any = "true",
					whitelist = "true",
					visible = "true",
					filterType = "item",
					items = textutils.serialiseJSON({})
				})
				theFilter = Filter:new(packet.data.filterName)
				table.insert(master.filters, theFilter)
			end
			--Change filter to specified options
			validate(packet.data.changedState, packet.instruction, 2)
			theFilter:saveChanges(packet.data.changedState)
			ui_containerManager:scheduleUpdate()
			ui_filterManager:rebuildTable()
			
			local newPacket = myTalker:makePacket("broadcast_filterUpdate", packet.data)
			myTalker:broadcastPacket(newPacket)
		end,
broadcast_filterUpdate	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.filterName, packet.instruction, 1)
			local theFilter
			--Check if filter exists
			for _, thisFilter in ipairs(master.filters) do
				if packet.data.filterName == thisFilter.name then
					theFilter = thisFilter
					break
				end
			end
			--Create if it does not exist
			if not theFilter then
				csv.insert(config.filters, {
					name = packet.data.filterName,
					any = "true",
					whitelist = "true",
					visible = "true",
					filterType = "item",
					items = textutils.serialiseJSON({})
				})
				theFilter = Filter:new(packet.data.filterName)
				table.insert(master.filters, theFilter)
			end
			--Change filter to specified options
			validate(packet.data.changedState, packet.instruction, 2)
			theFilter:saveChanges(packet.data.changedState)
			ui_containerManager:scheduleUpdate()
			ui_filterManager:rebuildTable()
		end,
send_filterDelete	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			validate(packet.data.filterName, packet.instruction, 1)
			--Check if filter exists
			for _, thisFilter in ipairs(master.filters) do
				if packet.data.filterName == thisFilter.name then
					thisFilter:destroy()
					break
				end
			end
			local newPacket = myTalker:makePacket("broadcast_filterDelete", packet.data)
			myTalker:broadcastPacket(newPacket)
		end,
broadcast_filterDelete	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.filterName, packet.instruction, 1)
			--Check if filter exists
			for _, thisFilter in ipairs(master.filters) do
				if packet.data.filterName == thisFilter.name then
					thisFilter:destroy()
					break
				end
			end
		end,
send_cartCheckout	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			validate(packet.data.outputContainerName, packet.instruction, 1)
			validate(packet.data.cart, packet.instruction, 2)
			
			local didSendCart
			local transfers
			didSendCart, transfers = ui_cartManager:sendCart(packet.data.cart, packet.data.outputContainerName)
			
			local newPacket = myTalker:makePacket("rec_cartCheckout", {
				didSendCart = didSendCart
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
			
			newPacket = myTalker:makePacket("broadcast_cartCheckout", {
				transfers = transfers
			})
			myTalker:broadcastPacket(newPacket)
		end,
rec_cartCheckout	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.didSendCart
		end,
broadcast_cartCheckout	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			validate(packet.data.transfers, packet.instruction, 1)
			
			for _, thisOperation in pairs(packet.data.transfers) do
				local thisContainer = master.containers[thisOperation.container]
				thisContainer:checkout("", thisOperation.slot, thisOperation.count)
			end
		end,
broadcast_updateInventory	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.inputContainerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.plan, packet.instruction, 2)
			validate(packet.data.gid, packet.instruction, 3)
			
			local item = master.storage[packet.data.gid.uniqueKey]
			if not item then
				packet.data.gid.count = 0
				item = Item:new(packet.data.gid)
				master.storage[packet.data.gid.uniqueKey] = item
				ui_stockManager:refreshUI()
			end
			
			for _, thisOperation in pairs(packet.data.plan) do
				container:checkin(thisOperation.containerName, thisOperation.fromSlot, thisOperation.count, thisOperation.toSlot, item.gid)
			end
		end,
send_rpInit = function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		validate(packet.data.containerName, packet.instruction, 1)
		
		local newPacket = myTalker:makePacket("rec_rpInit", {
				containerName = packet.data.containerName,
				exists = peripheral.isPresent(packet.data.containerName)
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpInit	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.exists
		end,
send_rpSize	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			
			local newPacket = myTalker:makePacket("rec_rpSize", {
				containerName = packet.data.containerName,
				size = container.size
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpSize	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.size
		end,
send_rpList	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			local data = {
				containerName = packet.data.containerName,
				list = container.inventory
			}
			newPacket = myTalker:makePacket("rec_rpList", data)
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpList	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.list
		end,
send_rpGetItemDetail	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.slot, packet.instruction, 2)
			
			local newPacket = myTalker:makePacket("rec_rpGetItemDetail", {
				containerName = packet.data.containerName,
				getItemDetail = container.peripheral.getItemDetail(packet.data.slot)
			})
			newPacket.getItemDetail.uniqueKey = container.inventory[packet.data.slot].uniqueKey
			--TODO: Add the rest of the rich GID fields
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpGetItemDetail	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.getItemDetail
		end,
send_rpGetItemLimit	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			validate(packet.data.slot, packet.instruction, 2)
			
			local newPacket = myTalker:makePacket("rec_rpGetItemLimit", {
				containerName = packet.data.containerName,
				getItemLimit = master.model.items[container.inventory[packet.data.slot].uniqueKey].maxCount
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpGetItemLimit	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.getItemLimit
		end,
send_rpPushItems	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			if not peripheral.isPresent(packet.data.toName) then validate(nil, packet.instruction, 2) return end
			validate(packet.data.fromSlot, packet.instruction, 3)
			
			local newPacket = myTalker:makePacket("rec_rpPushItems", {
				containerName = packet.data.containerName,
				number = container.peripheral.pushItems(packet.data.toName, packet.data.fromSlot, packet.data.limit, packet.data.toSlot)
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpPushItems	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.number
		end,
send_rpPullItems	= function(packet)
			if not isHost then validate(nil, packet.instruction) return end
			local container = master.containers[packet.data.containerName]
			validate(container, packet.instruction, 1)
			if not peripheral.isPresent(packet.data.fromName) then validate(nil, packet.instruction, 2) return end
			validate(packet.data.fromSlot, packet.instruction, 3)
			
			local newPacket = myTalker:makePacket("rec_rpPushItems", {
				containerName = packet.data.containerName,
				number = container.peripheral.pullItems(packet.data.fromName, packet.data.fromSlot, packet.data.limit, packet.data.toSlot)
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end,
rec_rpPullItems	= function(packet)
			if isHost then validate(nil, packet.instruction) return end
			return packet.data.number
		end,
send_scan	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		--[[model = myTalker:request("scan", {
				threads = config.max_scan_threads,
				tasks = {{name = self.name}},
				doInitStuff = false
			})--]]
		validate(packet.data.threads, packet.instruction, 1)
		validate(packet.data.tasks, packet.instruction, 2)
		validate(packet.data.doInitStuff, packet.instruction, 3)
		basalt.schedule(function()
			local newPacket = myTalker:makePacket("rec_scan", {
				model = Scanner:new(packet.data.threads, packet.data.tasks, packet.data.doInitStuff)
			})
			myTalker:sendPacket(newPacket, packet.sender, packet.id)
		end)
	end,
rec_scan	= function(packet)
		if isHost then validate(nil, packet.instruction) return end
		return packet.data.model
	end,
send_serverConfigChange	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		validate(packet.data.key, packet.instruction, 1)
		validate(packet.data.value, packet.instruction, 2)
		
		config[tostring(packet.data.key)] = tostring(packet.data.value)
		csv.update(ui_serverConfigManager.sourceTable, function(row)
			return row["key"] == packet.data.key
		end,
		function(row)
			row["value"] = config[packet.data.key]
		end)
		ui_serverConfigManager:rebuildTable()
		
		local newPacket = myTalker:makePacket("broadcast_serverConfigChange", {
			key = packet.data.key,
			value = packet.data.value
		})
		myTalker:broadcastPacket(newPacket)
	end,
broadcast_serverConfigChange	= function(packet)
		if isHost then validate(nil, packet.instruction) return end
		
		validate(packet.data.key, packet.instruction, 1)
		validate(packet.data.value, packet.instruction, 2)
		
		config[tostring(packet.data.key)] = tostring(packet.data.value)
		csv.update(ui_serverConfigManager.sourceTable, function(row)
			return row["key"] == packet.data.key
		end,
		function(row)
			row["value"] = config[packet.data.key]
		end)
		ui_serverConfigManager:rebuildTable()
	end,
send_reboot	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		
		local newPacket = myTalker:makePacket("broadcast_reboot", {})
		myTalker:broadcastPacket(newPacket)
		os.reboot()
	end,
broadcast_reboot	= function(packet)
		if isHost then validate(nil, packet.instruction) return end
		local r = basalt.getMainFrame():addFrame({
			width = basalt.getMainFrame().width + 2,
			height = basalt.getMainFrame().height + 1,
			x = 1,
			y = 1,
			z = 9999,
			background = colors.black
		})
		
		local ui = r:addFrame({
			width = 18 + (termX % 2),
			height = 6,
			x = math.ceil((2 + termX - 18) / 2),
			y = 4,
			background = colors.lightGray
		})
		ui:addBorder({
			color = colors.yellow,
			top = true,
			left = true,
			right = true,
			bottom = true
		})
		local label1 = ui:addLabel({
			width = ui.width - 2,
			height = 1,
			x = 2,
			y = 2,
			foreground = colors.black,
			text = " Host rebooting."
		})
		local label2 = ui:addLabel({
			width = ui.width - 2,
			height = 1,
			x = 2,
			y = 3,
			foreground = colors.black,
			text = " Time to reboot."
		})
		local ok = ui:addButton({
			width = 4,
			height = 1,
			x = ui.width - 4,
			y = 5,
			background = colors.green,
			foreground = colors.black,
			text = "Darn"
		})
		ok:onClick(function(element2)
			os.reboot()
		end)
	end,
send_updateMod	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		
		validate(packet.data.modName, packet.instruction, 1)
		validate(packet.data.modID, packet.instruction, 2)
		validate(packet.data.newMod, packet.instruction, 3)
		
		local newPacket = myTalker:makePacket("broadcast_updateMod", {
			modName = packet.data.modName,
			modID = packet.data.modID,
			newMod = packet.data.newMod
		})
		myTalker:broadcastPacket(newPacket)
		
		master.mods[packet.data.modID] = packet.data.modName
		master.mod_ids[packet.data.modName] = packet.data.modID
		
		if newMod then
			csv.insert(config.mods, {
				name = packet.data.modName,
				mod = packet.data.modID
			})
		else
			csv.update(config.mods, function(row)
				return row["name"] == packet.data.modName
			end,
			function(row)
				row["name"] = packet.data.modName
				row["mod"] = packet.data.modID
			end)
		end
		
		ui_modManager:rebuildTable()
	end,
broadcast_updateMod	= function(packet)
		if isHost then validate(nil, packet.instruction) return end
		
		validate(packet.data.modName, packet.instruction, 1)
		validate(packet.data.modID, packet.instruction, 2)
		validate(packet.data.newMod, packet.instruction, 3)
		
		master.mods[packet.data.modID] = packet.data.modName
		master.mod_ids[packet.data.modName] = packet.data.modID
		
		if newMod then
			csv.insert(config.mods, {
				name = packet.data.modName,
				mod = packet.data.modID
			})
		else
			csv.update(config.mods, function(row)
				return row["name"] == packet.data.modName
			end,
			function(row)
				row["name"] = packet.data.modName
				row["mod"] = packet.data.modID
			end)
		end
		
		ui_modManager:rebuildTable()
	end,
send_crafterHandshake	= function(packet)
		if not isCrafter then return end
		validate(packet.data.peripheralName, packet.instruction, 1)
		
		local newPacket = myTalker:makePacket("rec_crafterHandshake", {
			peripheralName = packet.data.peripheralName,
			computerID = os.getComputerID(),
			computerLabel = os.getComputerLabel()
		})
		myTalker:sendPacket(newPacket, packet.sender, packet.id)
	end,
rec_crafterHandshake	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		
		validate(packet.data.peripheralName, packet.instruction, 1)
		validate(packet.data.computerID, packet.instruction, 2)
		
		master.turtles[packet.data.peripheralName] = {
			peripheralName = packet.data.peripheralName,
			computerID = packet.data.computerID,
			computerLabel = packet.data.computerLabel
		}
		master.turtleTask[packet.data.peripheralName] = {
			peripheralName = packet.data.peripheralName,
			task = nil,
			queue = {}
		}
		asdf("Handshake with turtle " .. packet.data.computerID .. " success")
	end,
send_getTurtles	= function(packet)
	if not isHost then validate(nil, packet.instruction) return end
		local newPacket = myTalker:makePacket("rec_getTurtles", {
			turtles = master.turtles
		})
		myTalker:sendPacket(newPacket, packet.sender, packet.id)
	end,
rec_getTurtles	= function(packet)
	if isHost then validate(nil, packet.instruction) return end
		validate(packet.data.turtles, packet.instruction, 1)
		return packet.data.turtles
	end,
send_getTurtleInventory	= function(packet)
		if not isCrafter then validate(nil, packet.instruction) return end
		local isValid = turtle.craft(0)
		local newPacket = myTalker:makePacket("rec_getTurtleInventory", {
			inventory = {},
			isValid = isValid
		})
		local slots = {1,2,3,5,6,7,9,10,11}
		for index, slot in ipairs(slots) do
			newPacket.data.inventory[index] = turtle.getItemDetail(slot, true)
			--this is slow
		end
		
		myTalker:sendPacket(newPacket, packet.sender, packet.id)
	end,
rec_getTurtleInventory	= function(packet)
		validate(packet.data.inventory, packet.instruction, 1)
		validate(packet.data.isValid, packet.instruction, 2)
		return {inventory = packet.data.inventory, isValid = packet.data.isValid}
	end,
send_importTurtleSlot	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		validate(packet.data.computerID, packet.instruction, 1)
		validate(packet.data.slot, packet.instruction, 2)
		validate(packet.data.gid, packet.instruction, 3)
		local requestingTurtle
		for _, thisTurtle in pairs(master.turtles) do
			if thisTurtle.computerID == packet.data.computerID then
				requestingTurtle = thisTurtle
				break
			end
		end
		local tempContainer = Container:new(requestingTurtle.peripheralName, {gid = packet.data.gid})
		asdf("tempContainer made")
		tempContainer:exportItemToStorage("", packet.data.slot)
		asdf("Item export complete")
	end,
broadcast_updateRecipe	= function(packet)
		validate(packet.data.recipe, packet.instruction, 1)
		if master.recipes[packet.data.recipe.uniqueID] then
			local thisRecipe = master.recipes[packet.data.recipe.uniqueID]
			thisRecipe:setFromCSV(packet.data.recipe)
			
			csv.update(config.recipes, function(row)
				return row["primary_output"] == packet.data.recipe.primary_output and row["priority"] == packet.data.recipe.priority
			end, function(row)
				for i,v in pairs(packet.data.recipe) do
					row[i] = v
				end
			end)
			ui_recipeManager:refreshUI()
			--Might be unnecessary
			return
		end
			
		
		local recipeObj = Recipe:new(packet.data.recipe)
		master.recipes[packet.data.recipe.uniqueID] = recipeObj
		
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
		csv.insert(config.recipes, packet.data.recipe)
		asdf("Adding recipe")
		ui_recipeManager:refreshUI()
		ui_craftManager:refreshUI()
	end,
send_deleteRecipe	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		validate(packet.data.uniqueID, packet.instruction, 1)
		
		local newPacket = myTalker:makePacket("broadcast_deleteRecipe", {
			uniqueID = packet.data.uniqueID
		})
		myTalker:broadcastPacket(newPacket)
		if master.recipes[packet.data.uniqueID] then
			master.recipes[packet.data.uniqueID]:destroy()
		end
	end,
broadcast_deleteRecipe	= function(packet)
		if isHost then validate(nil, packet.instruction) return end
		validate(packet.data.uniqueID, packet.instruction, 1)
		
		if master.recipes[packet.data.uniqueID] then
			master.recipes[packet.data.uniqueID]:destroy()
		end
	end,
send_turtleDoCraft	= function(packet)
		if not isCrafter then validate(nil, packet.instruction) return end
		validate(packet.data.amount, packet.instruction, 1)
		validate(packet.data.auxillarySlots, packet.instruction, 2)
		table.insert(packet.data.auxillarySlots, 4)
		local newPacket = myTalker:makePacket("rec_turtleDoCraft", {})
		
		local success, status = turtle.craft(packet.data.amount)
		local isError = nil
		
		if success then
			
			for _, slot in pairs(packet.data.auxillarySlots, packet.instruction, 2) do
				local gid = turtle.getItemDetail(slot, true)
				gid.uniqueKey = gid.name .. "|" .. (gid.nbt or "0")
				local newPacket2 = myTalker:makePacket("send_importTurtleSlot", {
					computerID = os.getComputerID(),
					slot = slot,
					gid = gid
				})
				myTalker:sendPacket(newPacket2, myTalker.host)
				os.sleep()
			end
		else
			isError = true
		end
		asdf("Sending status")
		local newPacket = myTalker:makePacket("rec_turtleDoCraft", {
			success = success,
			status = status
		})
		myTalker:sendPacket(newPacket, packet.sender, packet.id)
	end,
rec_turtleDoCraft	= function(packet)
		if not isHost then validate(nil, packet.instruction) return end
		
		return packet.data
	end,
	}
	
	r.host = os.getComputerID()
	r.ready = false
	r:connectToHost()
	
	return r
end

function Talker:destroy()
	if self.isHost then
		rednet.unhost(self.protocol)
	end
	if self.modem then
		rednet.close(self.modemName)
	end
end

function Talker:connectToHost(timeout)
	self.ready = false
	if not self.isHost then
		local hosts = {}
		hosts = {rednet.lookup(self.protocol, self.hostname, (timeout or 0.5))}
		local timeoutAgain = 2
		while not hosts or #hosts == 0 do
			splashScreen("No host found", "retry in " .. tostring(timeoutAgain))
			hosts = {rednet.lookup(self.protocol, self.hostname, timeoutAgain)}
			timeoutAgain = math.min(60, timeoutAgain + 4)
		end
		self.host = hosts[1]
		
		while not self.ready do
			local newPacket = self:makePacket("send_isInitialized", {})
			self:sendPacket(newPacket, self.host)
			local packet = self:receivePacket("rec_isInitialized")
			local heardBack = packet.data.initialized
			if not heardBack then
				splashScreen("   Host is   ", "initializing")
				os.sleep(1)
			else
				splashScreen("   Host is   ", "initialized")
				self.ready = true
			end
		end
	else
		rednet.host(self.protocol, self.hostname)
		self.ready = true
	end
	return hosts
end

function Talker:request(name, data, f, allowError)
	local packet = self:makePacket("send_" .. name, data)
	local timePassed = 0
	while timePassed < 5 do
		self:sendPacket(packet, self.host)
		local result, resolved = self:resolveMessage("rec_" .. name, f)
		if resolved then
			return result
		end
		timePassed = timePassed + 1
	end
	if allowError then
		asdf("Request took too long to return: " .. name)
	else
		error("Request took too long to return: " .. name)
	end
end

function Talker:requestFrom(who, instruction, data, f, allowError)
	local packet = self:makePacket("send_" .. instruction, data)
	local timePassed = 0
	while timePassed < 9 do
		self:sendPacket(packet, who)
		local result, resolved = self:resolveMessage("rec_" .. instruction, f)
		if resolved then
			return result
		end
		timePassed = timePassed + 3
	end
	if allowError then
		asdf("Request took too long to return: " .. instruction)
	else
		error("Request took too long to return: " .. instruction)
	end
end

function Talker:makePacket(instruction, data)
	local packet = {
		instruction = instruction,
		data = data,
		protocol = self.protocol,
		hostname = self.hostname,
		sender = os.getComputerID(),
		id = "s" .. getUniqueID(6) .. "m" .. getUniqueID(6) .. "\215"
	}
	
	return packet
end

function Talker:sendPacket(packet, recipient, responseID)
	packet.recipient = recipient
	packet.responseID = responseID
	if isHost and responseID then
		--Cache the reply, keyed by the request id
		self.recentResponses = self.recentResponses or {}
		self.recentResponseOrder = self.recentResponseOrder or {}
		self.recentResponses[responseID] = packet
		table.insert(self.recentResponseOrder, responseID)
		if #self.recentResponseOrder > 200 then
			local oldest = table.remove(self.recentResponseOrder, 1)
			self.recentResponses[oldest] = nil
		end
	end
	rednet.send(recipient, packet, self.protocol)
	asdf("Sn " .. packet.instruction)
end

--Host-only. If the request id was already handled, resend the cached reply instead of running the instruction handler again.
function Talker:replayIfDuplicate(packet)
	if not self.recentResponses then return false end
	local cached = self.recentResponses[packet.id]
	if cached then
		rednet.send(packet.sender, cached, self.protocol)
		return true
	end
	return false
end

function Talker:broadcastPacket(packet, responseID)
	--local newPacket = self:makePacket(instruction, packet.data)
	packet.recipient = "broadcast"
	packet.responseID = responseID
	rednet.broadcast(packet, self.protocol)
	asdf("Br " .. packet.instruction)
end

function Talker:receivePacket(filter, timeout)
	local validMessage = false
	local sender, packet, protocol
	repeat
		sender, packet, protocol = rednet.receive(self.protocol, timeout or 1)
		if self.protocol == protocol and --Protocol must match (should always be true)
			type(packet) == "table" and --Message is a table
			packet.instruction and type(packet.instruction) == "string" and --Message has an instruction
			packet.data and type(packet.data) == "table" and --Message has data
			packet.protocol and type(packet.protocol) == "string" and --Message has protocol
			packet.hostname and type(packet.hostname) == "string" and --Message has hostname
			packet.sender and type(packet.sender) == "number" and --Message has sender
			packet.recipient and (type(packet.recipient) == "number" or packet.recipient == "broadcast") and --Message has recipient
			self.instructions[packet.instruction] ~= nil and --Instruction is valid
			self.protocol == packet.protocol and --Protocol must match (again, lol)
			self.hostname == packet.hostname and --Hostname must match
			(os.getComputerID() == packet.recipient or packet.recipient == "broadcast") and --Recipient must match
			#packet.id == 15 and --id is exact length
			string.gsub(packet.id, "[0-9a-f]", "") == "sm" .. "\215" and --id follows format
			(not filter or (filter and packet.instruction == filter)) --If the packet needs to be filtered, check if it passes the filter
		then
			if self.ready or packet.instruction == "rec_isInitialized" then
				validMessage = true
				asdf("Rc " .. packet.instruction)
			end
		end
	until validMessage
	return packet
end

function Talker:resolveMessage(instruction, f)
	if not self.instructions[instruction] then error("Received invalid instruction " .. tostring(instruction)) end
	f = f or function(packet) return true end
	--local packet = nil
	local timeSpent = 0
	while true do
		timeSpent = timeSpent + 0.05
        for index, packet in pairs(self.messages) do
            if packet.instruction == instruction and f(packet) then
                table.remove(self.messages, index)
                return self.instructions[packet.instruction](packet), true
            end
        end
		--asdf("problem?")
		os.sleep()
		--asdf("nope")
		local timeoutLength = 3
		if instruction == "rec_containerSnapshot" then timeoutLength = 60 end
		if timeSpent > timeoutLength then
			--We were expecting a message to arrive, but it's been too long.
			--The connection to the host must be lost.
			asdf(instruction .. " took too long")
			if not isHost then
				self:connectToHost()
			end
			return nil, false
		end
    end
end