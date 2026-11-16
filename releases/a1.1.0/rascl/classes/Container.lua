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
		r.inventory = tempTurtleInfo
	end
	return r
end

function Container:getPeripheral(renew)
	if self.peripheral == nil or renew then
		if isHost then
			self.peripheral = peripheral.wrap(self.name)
		else
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
			assumptions.isStorageType = (master.containerTypes[self.type].storageType)
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
	if model == nil then
		os.sleep(1)
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

--NEW. A transfer found this container to be different from what the model says: it came up short, or the wrong item came
--out. Read the container again and replace the model's picture of it. Reading yields, replacing does not, so no other job
--can ever see the container half updated. (Staging chests have no model, so there is nothing to correct.)
--@ marker Container:resync: the model was wrong, so read the container again
function Container:resync()
	if not isHost or not self.inventory or self:missing() then
		return
	end
	asdf("The model was wrong about " .. self.name .. ": reading it again")
	--Remember it: if items could not be stored because of what was found here, Recovery reads it again before every retry
	master.suspectContainers = master.suspectContainers or {}
	master.suspectContainers[self.name] = true
	local model = Scanner:new(tonumber(config.max_scan_threads), {{name = self.name}}, false)
	self:removeFromModel()
	self:addToModel(model)
	local newPacket = myTalker:makePacket("broadcast_containerModel", {
		containerName = self.name,
		model = model
	})
	myTalker:broadcastPacket(newPacket)
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

--@ marker exportItemToStorage: plan first, then execute
--`job` (optional) is the job whose reserved slots may be used. Returns how many items could NOT be stored (0 = all stored).
function Container:exportItemToStorage(uniqueKey, fromSlot, job)
	if not isHost and not isCrafter then return end
	asdf("Starting export")
	if not master.containerTypes[self.type].canExportToStorage or self:missing() or (self.allocation ~= "") then
		asdf("nuh uh")
		return
	end
	--This is an input container, which does not have a smart infrastructure of item info like storage containers do
	local gid
	if self.isTempTurtle then
		gid = self.inventory[fromSlot]
	else
		gid = peripheral.call(self.name, "getItemDetail", fromSlot)
		if not gid then
			return 0
		end
		--What is really in the slot decides what it is (a staging slot may hold something the caller did not expect)
		gid.nbt = gid.nbt or "0"
		gid.uniqueKey = gid.name .. "|" .. (gid.nbt or "0")
	end
	
	local item = master.storage[gid.uniqueKey]
	local quantity = gid.count
	
	if item then
		Container.pruneStaleSlots(item)
		gid = item.gid
	else
		--Item is brand new, make it
		gid.nbt = gid.nbt or "0"
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
	
	--Work out where everything will go. This only plans: nothing is moved yet.
	local plan = Container.planImport(item, quantity, StorageView.live(job), fromSlot)
	
	--Execute the plan, even if it's not finalized, as long as there is something valid to do
	local stored = 0
	local short = {}		--Containers that took less than planned: what the model says about them is wrong
	if #plan > 0 then
		for _, thisOperation in pairs(plan) do
			local planned = thisOperation.count
			local transferred = self:checkin(thisOperation.containerName, thisOperation.fromSlot, thisOperation.count, thisOperation.toSlot, gid)
			if transferred < planned then
				short[thisOperation.containerName] = true
			end
			thisOperation.count = transferred
			stored = stored + transferred
			if job then
				Planner.consumeReservation(job, gid.uniqueKey, thisOperation.containerName, thisOperation.toSlot, transferred)
			end
		end
		
		if isHost and not self.isTempTurtle then
			local newPacket = myTalker:makePacket("broadcast_updateInventory", {
				inputContainerName = self.name,
				plan = plan,
				gid = gid
			})
			myTalker:broadcastPacket(newPacket)
		elseif isHost and self.isTempTurtle then
			local newPacket = myTalker:makePacket("broadcast_updateInventoryTurtle", {
				peripheralName = self.name,
				inventory = self.inventory,
				plan = plan,
				gid = gid
			})
			myTalker:broadcastPacket(newPacket)
		end
	end
	
	--A container that took less than planned is not what the model thinks it is: read it again
	if isHost then
		for containerName in pairs(short) do
			master.containers[containerName]:resync()
		end
	end
	return quantity - stored
end

--NEW. Forget slots that the model still lists for an item but that no longer hold anything.
--(This used to happen in the middle of planning inside exportItemToStorage.)
function Container.pruneStaleSlots(item)
	for containerName, inSlots in pairs(item.gid.containers) do
		local container = master.containers[containerName]
		for i = #inSlots, 1, -1 do
			if not container.inventory[inSlots[i]] then
				table.remove(inSlots, i)
			end
		end
	end
end

--NEW. Decides where `quantity` of `item` would be stored, without moving anything.
--`view` is a StorageView, so the exact same logic serves a real import (StorageView.live) and the
--"would it all fit?" check before a craft starts (StorageView.scratch). Nothing is copied or searched:
--the slots the job reserved say where its items go first, the item's own gid.containers says where it
--already is, and the filters say where it may go.
--Returns plan, leftover. leftover > 0 means that much would not fit.
--@ marker Container.planImport: where would this item go?
function Container.planImport(item, quantity, view, fromSlot)
	local gid = item.gid
	local tried = {}	--Containers already looked at, as a set: a list had to be searched for every container, which gets slow with thousands of containers
	local planned = {}	--planned[containerName][slot] = true: slots this plan has already used
	local plan = {}
	
	--Put `count` items in a slot. Returns true when everything has been placed.
	local function place(containerName, slot, count)
		table.insert(plan, {
			containerName = containerName,
			fromSlot = fromSlot,
			count = count,
			toSlot = slot
		})
		planned[containerName] = planned[containerName] or {}
		planned[containerName][slot] = true
		quantity = quantity - count
		return quantity <= 0
	end
	local function isPlanned(containerName, slot)
		return planned[containerName] ~= nil and planned[containerName][slot] == true
	end
	
	for _, reservation in ipairs(view:reservedFor(item)) do
		if quantity > 0 and reservation.remaining > 0 and view:usable(reservation.containerName) then
			local here = view:realContents(reservation.containerName, reservation.slot)
			if here == nil or here.uniqueKey == gid.uniqueKey then
				local room = gid.maxCount - (here and here.count or 0)
				local count = math.min(quantity, reservation.remaining, room)
				if count > 0 and place(reservation.containerName, reservation.slot, count) then
					return plan, 0
				end
			end
		end
	end
	
	for containerName, inSlots in pairs(view:holders(item)) do
		if view:usable(containerName) then
			--Look at slots that really hold the item and try to add to that
			--(a stale entry in the Item's list, or a slot an earlier plan filled with something else, is ignored)
			for _, slot in pairs(inSlots) do
				local gottenSlot = view:contents(containerName, slot)
				if gottenSlot and gottenSlot.uniqueKey == gid.uniqueKey and gottenSlot.count < gid.maxCount and not isPlanned(containerName, slot) then
					--There is room in this slot to add items: add it to the plan
					if place(containerName, slot, math.min(quantity, gid.maxCount - gottenSlot.count)) then
						return plan, 0
					end
				end
			end
			
			--Next, look at free slots and place the item in those
			for slot = 1, view:sizeOf(containerName), 1 do
				if view:contents(containerName, slot) == nil and not isPlanned(containerName, slot) then
					if place(containerName, slot, math.min(quantity, gid.maxCount)) then
						return plan, 0
					end
				end
			end
		end
		tried[containerName] = true
	end
	
	--If this fails, then iterate through filters to try and find a container that can accept the item
	for _, thisFilter in ipairs(master.filters) do
		--The filter accepts this item
		if thisFilter:containsItem(item) then
			--Search all containers that are assigned to this filter
			for _, containerName in pairs(thisFilter.containers) do
				--If we have searched it above, don't search again
				if not tried[containerName] and view:usable(containerName) then
					--At last, we can try to put the item in. We know it does not contain the item already, or else it would've been caught above.
					--Try to fill into empty spaces
					for slot = 1, view:sizeOf(containerName), 1 do
						if view:contents(containerName, slot) == nil and not isPlanned(containerName, slot) then
							if place(containerName, slot, math.min(quantity, gid.maxCount)) then
								return plan, 0
							end
						end
					end
					tried[containerName] = true
				end
			end
		end
	end
	
	return plan, quantity
end

--`job` (optional) is the job the items were reserved for: what is taken out stops being "reserved" and simply leaves the stock.
function Container:checkout(destination, slot, amount, toSlot, job)
	if self.type == "staging" and isHost then
		--A staging chest is not part of the stock model: there is nothing to keep up to date, just move the items
		return self.peripheral.pushItems(destination, slot, amount, toSlot)
	end
	local gid = self.inventory[slot]
	if not gid then
		return 0		--The model has nothing in this slot (it was corrected a moment ago): nothing to take
	end
	local uniqueKey = gid.uniqueKey
	local thisItem = master.storage[uniqueKey]
	
	local transferred = amount
	if isHost then
		transferred = self.peripheral.pushItems(destination, slot, amount, toSlot)
	end
	
	
	thisItem:removeStock(transferred)
	if job then
		Planner.consumeStock(job, uniqueKey, self.name, slot, transferred)
	end
	
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
	
	
	--The slot held less than the model said (or something else): the model is wrong. Read the container again.
	if transferred < amount and isHost then
		self:resync()
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
	
	self.type = changes.type
	if(not master.containerTypes[changes.type].storageType) then
		self.allocation = ""
		if self.filter then
			self.filter:removeContainer(self.name)
		end
		self.filter = nil
	elseif(changes.filter and changes.filter ~= "") then
		if self.filter then
			--Remove the container from the list of containers that the filter is assigned to
			self.filter:removeContainer(self.name)
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