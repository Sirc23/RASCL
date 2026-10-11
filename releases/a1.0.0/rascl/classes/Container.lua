Container = {}
Container.__index = Container

function Container:new(name, tempTurtleInfo)
	local r = setmetatable({}, self)
	r.isTempTurtle = (tempTurtleInfo ~= nil)
	if not r.isTempTurtle then
		local csv_query = csv.select(config.containers, function(row)
			return row["name"] == name
		end)
		if #csv_query == 0 then error(name .. " does not have a record in the CSV table") end
		if #csv_query > 1 then error(name .. " has duplicate records in the CSV table") end
		local result = csv_query[1]
		
		r.name = result.name --minecraft:chest_1
		r.mod = string.gsub(r.name, ":.*$", "") --minecraft
		r.container = string.gsub(string.gsub(r.name, "^" .. r.mod .. ":", ""), "_%d+$", "") --chest
		r.noMod = string.gsub(r.name, "^" .. r.mod .. ":", "") --chest_1
		r.displayName = capitalizeWords(string.gsub(r.noMod, "_", " ")) --Chest 1
		r.number = tonumber((string.gsub(r.displayName, "%D+", ""))) or 0 --1
		
		r.type = result.type --storage
		r.allocation = result.allocation --String, user defined storage group eg. Overflow
		if r.allocation == nil then r.allocation = "" end
		r.filter = findFilter(r.allocation)
		if r.filter then
			r.filter:addContainer(r.name)
		end
		
		r.peripheral = r:getPeripheral() --{size(), list(), ...}
		
		--r.inventory = master.model.inventory[self.name] 
		r.inventory = nil --{{name = "minecraft:oak_log", nbt = "0", count = 27, uniqueKey = "minecraft:oak_log|0"}, ...}
	else
		asdf("Temp turtle made")
		r.name = name
		r.type = "input"
		r.allocation = ""
		r.peripheral = r:getPeripheral()
		r.tempGid = tempTurtleInfo.gid
	end
	return r
end

function Container:getPeripheral(renew)
	if self.peripheral == nil or renew then
		if isHost then
			self.peripheral = peripheral.wrap(self.name)
		else
			--self.peripheral = RemotePeripheral:new(self.name)
			self.peripheral = true
		end
	end
	return self.peripheral
end

function Container:destroy()
	self:reconsider({isPhysicallyConnected = false})
	master.containers[self.name] = nil
end

function Container:reconsider(assumptions, skipUIUpdate)
	master.model.current[self.name] = false
	basalt.schedule(function()
		assumptions = assumptions or {}
		
		if assumptions.isPhysicallyConnected == nil then
			assumptions.isPhysicallyConnected = (self:missing() == false)
		end
		if assumptions.isInModel == nil then
			assumptions.isInModel = (master.model.inventory[self.name] ~= nil)
		end
		if assumptions.isStorageType == nil then
			assumptions.isStorageType = (self.type == "storage")
		end
		
		if assumptions.isPhysicallyConnected then
			master.model.missing[self.name] = false
			if not self.peripheral then
				self.peripheral = self:getPeripheral()
			end
			
			if assumptions.isInModel and assumptions.isStorageType then
				self.inventory = master.model.inventory[self.name]
				master.model.current[self.name] = true
				return false
			elseif assumptions.isInModel and not assumptions.isStorageType then
				self:removeFromModel()
				ui_containerManager:scheduleUpdate()
				master.model.current[self.name] = true
				return false
			elseif not assumptions.isInModel and assumptions.isStorageType then
				local model = self:addToModel()
				ui_containerManager:scheduleUpdate()
				master.model.current[self.name] = true
				return model
			else
				self.inventory = nil
				master.model.current[self.name] = true
				return false
			end
		else
			master.model.missing[self.name] = true
			self.peripheral = nil
			
			if assumptions.isInModel then
				self:removeFromModel()
				
				ui_containerManager:scheduleUpdate()
				master.model.current[self.name] = true
				return false
			else
				self.inventory = nil
				if self.type == "output" then
					ui_cartManager.ui_output.scheduleUpdate()
				end
				master.model.current[self.name] = true
				return false
			end
		end
	end)
end

function Container:addToModel(model)
	--Figure out what is in the container's inventory
	model = model or nil
	os.sleep(1)
	if model == nil then
		if isHost then
			model = Scanner:new(tonumber(config.max_scan_threads), {{name = self.name}}, false)
		else
			model = myTalker:request("scan", {
				threads = tonumber(config.max_scan_threads),
				tasks = {{name = self.name}},
				doInitStuff = false
			})
		end
	end
	
	--Add presence in model
	master.model.inventory[self.name] = model.inventory[self.name]
	self.inventory = master.model.inventory[self.name]
	
	master.model.missing[self.name] = model.missing[self.name]
	master.model.sizes[self.name] = model.sizes[self.name]
	
	for uniqueKey, gid in pairs(model.items) do
		if not master.storage[uniqueKey] then
			--Add new items to model
			--asdf("New item! " .. uniqueKey)
			master.storage[uniqueKey] = Item:new(gid)
		else
			--Add item count to model
			--asdf("+" .. tostring(gid.count) .. " -> " .. uniqueKey)
			master.storage[uniqueKey]:addStock(gid.count)
			
			for containerName, inSlots in pairs(gid.containers) do
				master.storage[uniqueKey]:addContainer(containerName, inSlots)
			end
		end
	end
	
	if self.type == "output" then
		ui_cartManager.ui_output.scheduleUpdate()
	end
	
	ui_containerManager:scheduleUpdate()
	ui_stockManager:refreshUI()
	return model
end

function Container:removeFromModel()
	--Remove all items in container from stock
	for slot, item in pairs(master.model.inventory[self.name] or {}) do
		master.storage[item.uniqueKey]:removeStock(item.count, false)
		master.storage[item.uniqueKey]:removeContainer(self.name)
	end
	--Remove presence in model
	master.model.inventory[self.name] = nil
	self.inventory = nil
	
	if self.type == "output" then
		ui_cartManager.ui_output.scheduleUpdate()
	end
	
	ui_containerManager:scheduleUpdate()
	ui_stockManager:refreshUI()
end

function Container:exportModel()
	local model = {
		inventory = {},
		sizes = {},
		items = {},
		missing = {}
	}
	model.inventory[self.name] = self.inventory
	model.sizes[self.name] = master.model.sizes[self.name]
	model.missing[self.name] = self:missing()
	
	for _, thisSlot in pairs(self.inventory or {}) do
		local item = master.storage[thisSlot.uniqueKey]
		if not model.items[thisSlot.uniqueKey] then
			model.items[thisSlot.uniqueKey] = deepCopy(item.gid)
			model.items[thisSlot.uniqueKey].count = thisSlot.count
		else
			model.items[thisSlot.uniqueKey].count = model.items[thisSlot.uniqueKey].count + thisSlot.count
		end
	end
	
	return model
end

function Container:exportItemToStorage(uniqueKey, fromSlot)
	if not isHost and not isCrafter then return end
	asdf("Starting export")
	if self.type ~= "input" or self:missing() or (self.allocation ~= "") then
		asdf("nuh uh")
		return
	end
	--This is an input container, which does not have a smart infrastructure of item info like storage containers do
	local gid
	if self.isTempTurtle then
		gid = self.tempGid
	else
		gid = peripheral.call(self.name, "getItemDetail", fromSlot)
		if not gid then
			return
		end
		gid.uniqueKey = uniqueKey
	end
	
	local item = master.storage[gid.uniqueKey]
	
	local triedContainers = {}
	local plan = {}
	local quantity = gid.count
	
	--First try to insert into known containers that have the item
	if item then
		gid = item.gid
		--These containers are known to have the item
		for containerName, inSlots in pairs(gid.containers) do
			local container = master.containers[containerName]
			--Look at slots where the item already exists and try to add to that
			for _, slot in pairs(inSlots) do
				local gottenSlot = container.inventory[slot]
				local itemsInSlot = 0
				if gottenSlot then
					itemsInSlot = gottenSlot.count
				else
					table.remove(gid.containers[containerName], searchTable(gid.containers[containerName], slot))
				end
				--If there is room in this slot to add items, add it to the plan
				if itemsInSlot < gid.maxCount then
					table.insert(plan, {
						containerName = containerName,
						fromSlot = fromSlot,
						count = math.min(quantity, gid.maxCount - itemsInSlot),
						toSlot = slot
					})
					quantity = quantity - math.min(quantity, gid.maxCount - itemsInSlot)
					if quantity <= 0 then
						goto executePlan
					end
				end
			end
			
			--Next, look at free slots and place the item in those
			for slot = 1, master.model.sizes[container.name], 1 do
				local contents = container.inventory[slot]
				if contents == nil then
					table.insert(plan, {
						containerName = containerName,
						fromSlot = fromSlot,
						count = math.min(quantity, gid.maxCount),
						toSlot = slot
					})
					quantity = quantity - math.min(quantity, gid.maxCount)
					if quantity <= 0 then
						goto executePlan
					end
				end
			end
			table.insert(triedContainers, containerName)
		end
	else
		--Item is brand new, make it
		gid.count = 0
		gid.containers = {}
		
		local tags = {}
		for i,_ in pairs(gid.tags) do
			table.insert(tags, i)
		end
		gid.tags = tags
		
		gid.nameNoMod = string.sub(gid.name, string.find(gid.name, ":")+1, 999) --oak_log
		gid.modID = string.sub(gid.name, 0, string.find(gid.name, ":")-1) --minecraft
		gid.modName = master.mods[gid.modID] --Minecraft
		
		item = Item:new(gid)
		master.storage[gid.uniqueKey] = item
		ui_stockManager:refreshUI()
	end
	
	--If this fails, then iterate through filters to try and find a container that can accept the item
	for _, thisFilter in ipairs(master.filters) do
		--The filter accepts this item
		if thisFilter:containsItem(item) then
			--Search all containers that are assigned to this filter
			for _, containerName in pairs(thisFilter.containers) do
				local container = master.containers[containerName]
				--If we have searched it above, don't search again
				if searchTable(triedContainers, container.name) == -1 and not container:missing() then
					--At last, we can try to put the item in. We know it does not contain the item already, or else it would've been caught above.
					--Try to fill into empty spaces
					for slot = 1, master.model.sizes[container.name], 1 do
						local contents = container.inventory[slot]
						if contents == nil then
							table.insert(plan, {
								containerName = container.name,
								fromSlot = fromSlot,
								count = math.min(quantity, item.gid.maxCount),
								toSlot = slot
							})
							quantity = quantity - math.min(quantity, item.gid.maxCount)
							if quantity <= 0 then
								goto executePlan
							end
						end
					end
					table.insert(triedContainers, container.name)
				end
			end
		end
	end
	
	--Execute the plan, even if it's not finalized, as long as there is something valid to do
	::executePlan::
	if #plan > 0 then
		for _, thisOperation in pairs(plan) do
			local transferred = self:checkin(thisOperation.containerName, thisOperation.fromSlot, thisOperation.count, thisOperation.toSlot, gid)
			thisOperation.count = transferred
		end
		
		if isHost and not self.isTempTurtle then
			local newPacket = myTalker:makePacket("broadcast_updateInventory", {
				inputContainerName = self.name,
				plan = plan,
				gid = gid
			})
			myTalker:broadcastPacket(newPacket)
		end
		--TODO: Make sure this works
	end
	
	
end

function Container:checkout(destination, slot, amount, toSlot)
	local gid = self.inventory[slot]
	local uniqueKey = gid.uniqueKey
	local thisItem = master.storage[uniqueKey]
	
	local transferred = amount
	if isHost then
		transferred = self.peripheral.pushItems(destination, slot, amount, toSlot)
	end
	
	
	thisItem:removeStock(transferred)
	
	--If the checkout removed all items in that slot, remove association between the item and the slot
	if(transferred >= gid.count) then
		local index = searchTable(thisItem.gid.containers[self.name], slot)
		table.remove(thisItem.gid.containers[self.name], index)
		self.inventory[slot] = nil
		--If that was the last slot that contained the item, remove association between the item and the container
		if(#thisItem.gid.containers[self.name] == 0) then
			thisItem:removeContainer(self.name)
		end
	else
		gid.count = gid.count - transferred
	end
	
	return transferred
end

function Container:checkin(destination, fromSlot, count, toSlot, gid)
	local container = master.containers[destination]
	if not container then return 0 end
	if not container.inventory then return 0 end
	local item = master.storage[gid.uniqueKey]
	
	local transferred = count
	if isHost and not self.isTempTurtle then
		transferred = self.peripheral.pushItems(destination, fromSlot, count, toSlot)
	elseif isHost and self.isTempTurtle then
		transferred = peripheral.call(destination, "pullItems", self.name, fromSlot, count, toSlot)
	end
	
	if transferred > 0 then
		item:addContainer(destination, {toSlot})
		
		if container.inventory[toSlot] == nil then
		container.inventory[toSlot] = {
			name = gid.name,
			nbt = gid.nbt,
			count = transferred,
			uniqueKey = gid.uniqueKey
		}
		else
			container.inventory[toSlot].count = container.inventory[toSlot].count + transferred
		end
		if container.inventory[toSlot].count > gid.maxCount then
			asdf("Weird: maxCount exceeded")
		end
	end
	
	item:addStock(transferred)
	
	return transferred
end

function Container:exportToCSV()
	local r = {
		container_name = self.name,
		type = self.type or "storage",
		allocation = self.allocation or ""
	}
	return r
end

function Container:saveChanges(changes, skipStockUpdate)
	local oldType = self.type
	if not changes then return end
	if not changes.type then return end
	--if (not changes.filter or changes.filter == "") and changes.type == "storage" then return end
	
	self.type = changes.type
	if(changes.type ~= "storage") then
		self.allocation = ""
		if self.filter then
			self.filter:removeContainer(self)
		end
		self.filter = nil
	elseif(changes.filter and changes.filter ~= "") then
		if self.filter then
			--Remove the container from the list of containers that the filter is assigned to
			self.filter:removeContainer(self)
		end
		--Set the allocation to the chosen filter
		self.allocation = changes.filter
		--Add the container to the list of containers that the filter is assigned to
		for _, thisFilter in ipairs(master.filters) do
			if thisFilter.name == self.allocation then
				self.filter = thisFilter
				thisFilter:addContainer(self.name)
				break
			end
		end
	else
		self.allocation = ""
		if self.filter then
			self.filter:removeContainer(self.name)
		end
		self.filter = nil
	end
	if self.allocation == "" or self.allocation == "unassigned" then
		self.allocation = ""
		if self.filter then
			self.filter:removeContainer(self.name)
		end
		self.filter = nil
	end
	
	if self.type == "output" then
		ui_cartManager.ui_output.scheduleUpdate()
	end
	
	self:updateCSV()
	self:reconsider()
	ui_containerManager:scheduleUpdate()
	
	--ui_cartManager.ui_refresh:fireEvent("mouse_click")
end

function Container:updateCSV()
	local r = self:exportToCSV()
	csv.update(config.containers, function(row)
		return row["name"] == self.name
	end, function(row)
		for i,v in pairs(r) do
			row[i] = v
		end
	end)
end

function Container:missing()
	if self.isTempTurtle then return false end
	return master.model.missing[self.name]
end