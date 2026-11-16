Task = {}
Task.__index = Task

taskStatuses = {
	building = {status = "Building plan", color = colors.black},
	waiting = {status = "Waiting", color = colors.black},
	crafting = {status = "Crafting", color = colors.black},
	done = {status = "Done", color = colors.black}
}

function Task:destroy()

end

--Turns a list of operations ({container, slot, count}) into the per-turtle-slot plan:
--finalPlan[turtleSlot] = list of {container, slot, count}. Consumes `ops`.
function Task.addToSlotPlan(finalPlan, ops, turtleSlots, count)
	local oldPlan = ops
	local thisPlanCount = count
	local currentOperation = table.remove(oldPlan, 1)
	
	local quotaPerSlot = count/#turtleSlots
	asdf("===")
	for _, thisSlot in pairs(turtleSlots) do
		local addToSlot = 0
		local thisPlan = {}
		
		while addToSlot < quotaPerSlot do
			local removeAmount = math.min(currentOperation.count, quotaPerSlot - addToSlot)
			table.insert(thisPlan, {container = currentOperation.container, slot = currentOperation.slot, count = removeAmount})
			currentOperation.count = currentOperation.count - removeAmount
			addToSlot = addToSlot + removeAmount
			if currentOperation.count == 0 then
				currentOperation = table.remove(oldPlan, 1)
			end
		end
		finalPlan[thisSlot] = thisPlan
	end
end

--NEW. A task for one step of a plan that Planner.plan has already worked out: the recipe to use, how many crafts, and where
--the ingredients come from (plan[turtleSlot] = list of {container, slot, count}). Nothing is decided here, and the task never
--considers another recipe: if this one cannot work, the plan has to be made again.
--stagingOutput says where the crafted items are put: a list of {key, slot, count}, whose chest and slot are filled in when
--the job reserves staging. nil means they go to storage, which is what the root task of a plan does.
--The task is NOT started: Job:runLevel does that.
function Task:newFromPlan(recipe, amount, plan, stagingOutput)
	local r = setmetatable({}, self)
	r.itemInfo = master.itemInfo[recipe.primaryOutput.uniqueKey]
	r.recipe = recipe
	r.amount = amount
	r.plan = plan
	r.stagingOutput = stagingOutput
	r.childTasks = {}
	r:setStatus("waiting")
	return r
end

--NEW. The turtle checks what it was given before it crafts. `expect[slot] = {key, count}` is what the host says it loaded
--(key is name|nbt); `read(slot)` gives the item details of a turtle slot (name, count, nbt and the key) or nil. Returns one entry
--for every slot that is not right: the slot, what was expected, and what is there. More than the expected count is fine; the
--wrong item, too few, or anything in a slot that should be empty is not.
function Task.inventoryMismatches(expect, read)
	local mismatches = {}
	for slot = 1, 16 do
		local want = expect[slot]
		local have = read(slot)
		if want then
			if not have or have.uniqueKey ~= want.key or have.count < want.count then
				table.insert(mismatches, {slot = slot, expected = want.key, expectedCount = want.count, found = have and have.uniqueKey, foundCount = have and have.count})
			end
		elseif have then
			table.insert(mismatches, {slot = slot, found = have.uniqueKey, foundCount = have.count})
		end
	end
	return mismatches
end

--NEW. Is `key` anywhere in a crafter's inventory ({slot -> details with a uniqueKey})?
function Task.holds(inventory, key)
	for _, gid in pairs(inventory) do
		if gid.uniqueKey == key then
			return true
		end
	end
	return false
end

--NEW. A readable name for an item key
function Task.itemName(key)
	local item = master.storage[key]
	if item then
		return item.gid.displayName
	end
	local info = master.itemInfo[key]
	return info and info.displayName or key
end

--NEW. What the turtle reported, for a message
function Task.describeFailure(result)
	if not result then
		return "the crafter did not answer"
	end
	local parts = {}
	for index, m in ipairs(result.mismatch or {}) do
		if index > 3 then
			table.insert(parts, "...")
			break
		end
		local text = "turtle slot " .. m.slot .. ": "
		if m.expected then
			text = text .. "expected " .. m.expectedCount .. " x " .. Task.itemName(m.expected) .. ", " .. (m.found and ("found " .. m.foundCount .. " x " .. Task.itemName(m.found)) or "found nothing")
		else
			text = text .. "found " .. m.foundCount .. " x " .. Task.itemName(m.found) .. " where nothing should be"
		end
		table.insert(parts, text)
	end
	if #parts > 0 then
		return table.concat(parts, "; ")
	end
	return tostring(result.status or "the craft failed")
end

--NEW. The turtle reports name, count and nbt of what it holds (a detailed read would cost a tick per slot). Storing an item
--that storage has never seen needs its full details, so for those, and only those, ask the turtle once.
function Task.completeGid(station, slot, gid)
	gid.uniqueKey = gid.name .. "|" .. (gid.nbt or "0")
	if not master.storage[gid.uniqueKey] then
		local getSlot = myTalker:requestFrom(master.turtles[station].computerID, "getTurtleInventory", {
			slots = {slot},
			detailed = true
		})
		local detailed = getSlot[slot]
		if detailed then
			for field, value in pairs(detailed) do
				gid[field] = value
			end
			gid.uniqueKey = gid.name .. "|" .. (gid.nbt or "0")
		end
	end
	return gid
end

--NEW. How many tasks are using or waiting for a crafter
local function stationLoad(station)
	return (station.task and 1 or 0) + #station.queue
end

--NEW. The crafter with the fewest tasks (running + waiting) that is not blocked. Ties go to the lowest name.
--Returns nil when every crafter is blocked or missing.
function Task.pickStation()
	local best = nil
	local bestLoad = nil
	for name, station in pairs(master.turtleTask) do
		--A blocked crafter still holds items nobody could take; it is not used until it has been emptied
		if not station.blocked then
			local load = stationLoad(station)
			if not best or load < bestLoad or (load == bestLoad and name < best.peripheralName) then
				best = station
				bestLoad = load
			end
		end
	end
	return best
end

--NEW. A crafter where fewer tasks would be ahead of this one than where it waits now (or nil). A blocked crafter is
--worth leaving whatever the alternative looks like.
function Task:betterStation()
	local here = master.turtleTask[self.station]
	local ahead = math.huge
	if not here.blocked then
		ahead = (here.task and 1 or 0)
		for index, queued in ipairs(here.queue) do
			if queued == self then
				ahead = ahead + index - 1
				break
			end
		end
	end
	local best = nil
	for name, station in pairs(master.turtleTask) do
		if name ~= self.station and not station.blocked then
			local load = stationLoad(station)
			if load < ahead or (load == ahead and best and name < best.peripheralName) then
				best = station
				ahead = load
			end
		end
	end
	return best
end

function Task:joinQueue(station)
	self.station = station.peripheralName
	table.insert(station.queue, self)
	self:setStatus("waiting")
end

function Task:leaveQueue()
	local queue = master.turtleTask[self.station].queue
	for index, queued in ipairs(queue) do
		if queued == self then
			table.remove(queue, index)
			break
		end
	end
end

--Queues belong to the crafters (one each), and hold tasks, never jobs. A task joins the one with the fewest tasks.
function Task:enterQueue()
	if self.cancelled then return end
	
	if self.recipe.recipeType == "crafting" then
		local station = Task.pickStation()
		if not station then
			self:fail("no crafter is available (every crafter is blocked or missing)")
			return
		end
		asdf("Adding task to queue: " .. station.peripheralName)
		self:joinQueue(station)
		self:manageStation()
	else
		asdf("Wrong recipe type dumbass: " .. tostring(self.recipe.recipeType))
	end
end

--Wait for this task's turn. While waiting, move to any crafter where fewer tasks are ahead, so that no crafter
--sits idle while a task waits at another.
function Task:manageStation()
	while true do
		if self.cancelled then
			self:setStatus("cancelled")
			self:leaveQueue()
			return
		end
		local station = master.turtleTask[self.station]
		if not station.blocked and station.task == nil and station.queue[1] == self then
			table.remove(station.queue, 1)
			self:startCraft()
			return
		end
		local better = self:betterStation()
		if better then
			asdf("Moving to " .. better.peripheralName .. ": fewer tasks are waiting there")
			self:leaveQueue()
			self:joinQueue(better)
		else
			os.sleep()		--Nothing to do yet: look again next tick (a crafter may have become free, or the job may have failed)
		end
	end
end

--@ marker Task:startCraft: load the turtle, craft, import the result
function Task:startCraft()
	asdf("Beginning craft")
	master.turtleTask[self.station].task = self
	if self.job then
		self.job:taskStarted(self)
	end
	self:setStatus("crafting")
	
	--Which item belongs in which turtle slot. The turtle checks what it is given against this, so the host does not have to look.
	local itemOfTurtleSlot = {}
	for _, ingredient in ipairs(self.recipe.recipeDataCompressed) do
		for _, turtleSlot in ipairs(bitmaskToArray(ingredient.slots)) do
			itemOfTurtleSlot[turtleSlot] = ingredient.uniqueKey
		end
	end
	
	self.remainingCrafts = self.amount
	while self.remainingCrafts > 0 do
		if self.cancelled then
			--The job has failed: stop here, between batches (the crafter is empty after every batch)
			self:setStatus("cancelled")
			master.turtleTask[self.station].task = nil
			if self.job then
				self.job:taskStopped(self)
			end
			return
		end
		local batchSize = math.min(self.remainingCrafts, self.recipe.maxBatching)
		
		--Every turtle slot needs batchSize items (one per craft), possibly taken from several places
		local expect = {}
		local sources = {}		--The containers this batch is taken from
		local transfers = {}
		for thisSlot, thisPlan in pairs(self.plan) do
			local needed = batchSize
			expect[thisSlot] = {key = itemOfTurtleSlot[thisSlot], count = batchSize}
			for _, thisOperation in ipairs(thisPlan) do
				if needed > 0 and thisOperation.count > 0 then
					local amount = math.min(thisOperation.count, needed)
					sources[thisOperation.container] = true
					local thisTransfer = thisOperation.container:checkout(self.station, thisOperation.slot, amount, thisSlot, self.job)
					thisOperation.count = thisOperation.count - thisTransfer
					needed = needed - thisTransfer
					if thisTransfer < amount then
						--(Container:checkout has already read that container again, so the model is right by now)
						for i = #transfers, 1, -1 do
							if transfers[i].container == thisOperation.container.name then
								table.remove(transfers, i)
							end
						end
						if #transfers > 0 then
							local newPacket = myTalker:makePacket("broadcast_cartCheckout", {
								transfers = transfers
							})
							myTalker:broadcastPacket(newPacket)
						end
						return self:fail("could not take items out of " .. thisOperation.container.name)
					end
					if thisTransfer > 0 and thisOperation.container.type ~= "staging" then
						table.insert(transfers, {container = thisOperation.container.name, slot = thisOperation.slot, count = thisTransfer})
					end
				end
			end
		end
		local newPacket = myTalker:makePacket("broadcast_cartCheckout", {
			transfers = transfers
		})
		myTalker:broadcastPacket(newPacket)
		
		--Tell turtle to craft and await all done signal. It first checks that it holds exactly what was loaded, and afterwards
		--that it made what the recipe says. Only accept the reply of THIS crafter: with several crafters working at once,
		--the first rec_turtleDoCraft to arrive may belong to a different task.
		local turtleID = master.turtles[self.station].computerID
		local result = myTalker:requestFrom(turtleID, "turtleDoCraft", {
			amount = batchSize,
			expect = expect,
			product = self.recipe.primaryOutput.uniqueKey
		}, function(packet)
			return packet.sender == turtleID
		end, true)
		
		if result and result.success then
			asdf("Craft was a success!")
			local stored, why = self:importResult(result.inventory, batchSize)
			if not stored then
				return self:fail(why)
			end
			self.remainingCrafts = self.remainingCrafts - batchSize
		else
			--The turtle did not hold what the host loaded: the model was wrong about where it came from, so read those containers again
			if result and result.mismatch then
				for container in pairs(sources) do
					container:resync()
				end
			end
			return self:fail(Task.describeFailure(result), result and result.inventory)
		end
	end
	
	master.turtleTask[self.station].task = nil
	self:finish()
end

--NEW. Take what the craft produced out of the turtle. Like Container's importTurtleSlots, this looks at
--EVERY slot, because a big batch can spread over several slots.
--  Intermediate items go into the staging slots the Planner reserved for this task.
--  The finished product, and anything else (aux outputs left in the grid), go into normal storage.
function Task:importResult(inventory, batches)
	local temp = Container:new(self.station, inventory)	--The turtle, seen as a container
	local outputKey = self.recipe.primaryOutput.uniqueKey
	local problem = nil
	
	--Every slot is dealt with, even after one of them fails: whatever can be moved out is moved out
	for slot, gid in pairs(inventory) do
		if self.stagingOutput and gid.uniqueKey == outputKey then
			local toPlace = gid.count
			for _, staged in ipairs(self.stagingOutput) do
				staged.placed = staged.placed or 0
				local amount = math.min(staged.count - staged.placed, toPlace)
				if amount > 0 then
					local moved = peripheral.call(staged.container.name, "pullItems", self.station, slot, amount, staged.slot)
					staged.placed = staged.placed + moved
					toPlace = toPlace - moved
				end
			end
			if toPlace > 0 then
				problem = problem or ("could not put " .. toPlace .. " x " .. Task.itemName(gid.uniqueKey) .. " into staging: it is still in the crafter")
			end
		else
			Task.completeGid(self.station, slot, gid)
			local left = temp:exportItemToStorage("", slot, self.job)
			if left and left > 0 then
				problem = problem or ("could not store " .. left .. " x " .. Task.itemName(gid.uniqueKey) .. ": it is still in the crafter")
			end
		end
	end
	return problem == nil, problem
end

function Task:finish()
	self:setStatus("done")
	if self.job then
		self.job:taskFinished(self, true)
	end
end

function Task:fail(reason, inventory)
	asdf("Task failed: " .. tostring(reason))
	self.failed = reason
	self:setStatus("custom", {
		status = reason,
		isError = true
	})
	if self.station then
		--The crafter is still ours (station.task == self) while we empty it, so nothing else starts on it
		self:evacuateCrafter(inventory)
		if master.turtleTask[self.station].task == self then
			master.turtleTask[self.station].task = nil
		end
	end
	if self.job then
		self.job:taskFinished(self, false, reason)
	end
end

--NEW. A crafter that still holds items after a failure is emptied (see Recovery.emptyCrafter); if that is not possible it is blocked.
--`inventory` is what the crafter reported about itself (nil: read it).
function Task:evacuateCrafter(inventory)
	if not Recovery.emptyCrafter(self.station, self.job, inventory) then
		Recovery.blockCrafter(self.station)
	end
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