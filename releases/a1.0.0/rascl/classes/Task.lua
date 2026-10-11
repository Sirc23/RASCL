Task = {}
Task.__index = Task

taskStatuses = {
	building = {status = "Building plan", color = colors.black},
	waiting = {status = "Waiting", color = colors.black},
	crafting = {status = "Crafting", color = colors.black}
}

function Task:new(recipes, amount, parentTask)
	local r = setmetatable({}, self)
	asdf("Task made")
	r.recipes = recipes
	r.amount = amount
	r.parentTask = parentTask
	r.childTasks = {}
	
	r:setStatus("building")
	
	r.recipe, r.plan = r:assessTask()
	if r.recipe then
		asdf("Recipe found, adding to queue")
		basalt.schedule(function()
			r:enterQueue()
		end)
	else
		asdf("No recipes found")
	end
	
	return r
end

function Task:destroy()

end

function Task:assessTask()
	asdf("recipes: " .. tostring(#self.recipes))
	for _, recipeObj in ipairs(self.recipes) do
		local recipeData = recipeObj.recipeData
		local hasAllItems = true
		local finalPlan = {}
		--asdf("recipeData: " .. tostring(#recipeData))
		for _, thisData in pairs(recipeData) do
			asdf(tableToString(thisData))
			local uniqueKey = thisData.uniqueKey
			local batchSize = math.min(self.amount, recipeObj.maxBatching)
			local count = thisData.count * batchSize
			
			local item = master.storage[uniqueKey]
			if item then
				local thisPlan = item:buildCheckoutPlan(count)
				if thisPlan ~= nil then
					asdf("# ops = " .. tostring(#thisPlan))
					local stuffedPlan = {}
					stuffedPlan.plan = thisPlan
					stuffedPlan.slots = deepCopy(thisData.slots)
					table.insert(finalPlan, stuffedPlan)
				else
					asdf("Couldn't form a plan for " .. uniqueKey)
					hasAllItems = false
					break
				end
			else
				asdf("Item not in master.storage: " .. uniqueKey)
				hasAllItems = false
				break
			end
			
		end
		if hasAllItems then
			return recipeObj, finalPlan
		end
		asdf("...This recipe isn't it")
	end
	
	return nil
end

function Task:enterQueue()
	if self.recipe.recipeType == "crafting" then
		local maxQueue = 999
		local turtlePeripheral = nil
		
		for _, thisTurtleTask in pairs(master.turtleTask) do
			if thisTurtleTask.task == nil and #thisTurtleTask.queue == 0 then
				asdf("Crafter " .. thisTurtleTask.peripheralName .. " is idle")
				self.station = thisTurtleTask.peripheralName
				self:startCraft()
				return true
			else
				thisQueue = math.min(maxQueue, #thisTurtleTask.queue)
				if thisQueue < maxQueue then
					maxQueue = thisQueue
					turtlePeripheral = thisTurtleTask.peripheralName
				end
			end
		end
		if turtlePeripheral then
			self:setStatus("waiting")
			self.station = turtlePeripheral
			asdf("Adding task to queue: " .. self.station)
			table.insert(master.turtleTask[turtlePeripheral].queue, self)
			self:manageStation()
		else
			--TODO: No stations defined
		end
	else
	
	end
end

function Task:manageStation()
	if self.recipe.recipeType == "crafting" then
		basalt.schedule(function()
			local myQueue = master.turtleTask[self.station]
			while master.turtleTask[self.station].task ~= nil or myQueue[1] ~= self do
				os.sleep(0.5)
			end
			table.remove(master.turtleTask[self.station], 1)
			self:startCraft()
		end)
	else
	
	end
end

function Task:startCraft()
	asdf("Beginning craft")
	master.turtleTask[self.station].task = self
	self:setStatus("crafting")
	local batchSize = math.min(self.amount, self.recipe.maxBatching)
	--Load up items
	--Perform movement operations
	for _, thisPlan in pairs(self.plan) do
		local slots = thisPlan.slots
		local currentSlot = table.remove(slots)
		local batchLeft = batchSize
		for _, thisOperation in pairs(thisPlan.plan) do
			local thisContainer = thisOperation.container
			asdf("thisOp = " .. tableToString(thisOperation))
			while thisOperation.count > 0 do
				local thisTransfer = thisContainer:checkout(self.station, thisOperation.slot, math.min(thisOperation.count, batchLeft), currentSlot)
				thisOperation.count = thisOperation.count - thisTransfer
				batchLeft = batchLeft - thisTransfer
				if batchLeft == 0 then
					currentSlot = table.remove(slots)
					batchLeft = batchSize
				end
			end
			--thisOperation.count = thisTransfer
			--thisOperation.container = thisContainer.name
			--table.insert(transfers, thisOperation)
		end
	end
	
	basalt.schedule(function()
		--Tell turtle to craft and await all done signal
		local auxSlots = {}
		for _, thisAux in pairs(self.recipe.auxillaryOutputs) do
			for _, slot in pairs(thisAux.slots) do
				table.insert(auxSlots, slot)
			end
		end
		asdf("My station: " .. self.station)
		asdf("In turtles: " .. tostring(master.turtles[self.station].computerID))
		local result = myTalker:requestFrom(master.turtles[self.station].computerID, "turtleDoCraft", {
			amount = self.amount,
			auxillarySlots = auxSlots
		})
		if result.success then
			asdf("Craft was a success!")
			master.turtleTask[self.station].task = nil
			--Close out task
			self:destroy()
		else
			asdf("Craft failed for some reason")
			asdf(tableToString(result))
			master.turtleTask[self.station].task = nil
			if result then
				self:setStatus("custom", {
					status = result.status,
					isError = true
				})
			end
		end
	end)
end

function Task:startProcess()
	
end

function Task:setStatus(newStatus, data)
	self.status = newStatus
	if newStatus == "custom" then
		self.statusDisplay = data.status
		if data.isError then
			self.statusColor = colors.red
		else
			self.statusColor = colors.black
		end
	else
		self.statusDisplay = taskStatuses[newStatus].status
		self.statusColor = taskStatuses[newStatus].color
	end
	asdf("New status: " .. tostring(self.statusDisplay))
end

function Task:addChild(child)
	table.insert(self.childTasks, child)
end

function Task:removeChild(child)
	local removeIndex = nil
	for i, thisTask in pairs(self.childTasks) do
		if child == thisTask then
			removeIndex = i
			break
		end
	end
	if removeIndex then
		table.remove(self.childTasks, removeIndex)
		return true
	end
	return false
end