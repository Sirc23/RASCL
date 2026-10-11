Scanner = {}
Scanner.__index = Scanner

function Scanner:new(maxThreads, tasks, doInitStuff)
	local r = setmetatable({}, self)
	
	r.maxThreads = maxThreads
	r.model = {}
	r.initialScan = (tasks == nil or tasks == {})
	
	r.tasks = tasks or {}
	
	if #r.tasks == 0 then
		for p, container in pairs(master.containers) do
			table.insert(r.tasks, {name = p})
		end
	end
	
	return r:initScan(r.tasks, doInitStuff)
end

function Scanner:scannerThread(peripheralName, slot)
	local p = peripheral.wrap(peripheralName)
	if not slot then
		--master.model.current[peripheralName] = false
		local isStorage = (master.containers[peripheralName].type == "storage")
		
		self.model.missing[peripheralName] = not peripheral.isPresent(peripheralName)
		
		if not self.model.missing[peripheralName] then
			self.model.sizes[peripheralName] = p.size()
		end
		
		if isStorage and not self.model.missing[peripheralName] then
			self.model.inventory[peripheralName] = {}
			local list = p.list()
			
			for slot, value in pairs(list) do
				if not value.nbt then value.nbt = "0" end
				local uniqueKey = value.name .. "|" .. value.nbt
				value.uniqueKey = uniqueKey
				if not self.model.items[uniqueKey] then
					self.model.items[uniqueKey] = {
						name = value.name,
						nbt = value.nbt,
						count = value.count,
						uniqueKey = uniqueKey,
						containers = {}
					}
					table.insert(self.tasks, {name = peripheralName, slot = slot})
				else
					self.model.items[uniqueKey].count = self.model.items[uniqueKey].count + value.count
				end
				if not self.model.items[uniqueKey].containers[peripheralName] then
					self.model.items[uniqueKey].containers[peripheralName] = {slot}
				else
					table.insert(self.model.items[uniqueKey].containers[peripheralName], slot)
				end
				self.model.inventory[peripheralName][slot] = value
			end
		else
			self.model.inventory[peripheralName] = nil
		end
		
	else
		local gid = p.getItemDetail(slot)
		if not gid.nbt then gid.nbt = "0" end
		local uniqueKey = gid.name .. "|" .. gid.nbt
		gid.count = self.model.items[uniqueKey].count
		gid.uniqueKey = uniqueKey
		gid.containers = self.model.items[uniqueKey].containers
		
		local tags = {}
		for i,_ in pairs(gid.tags) do
			table.insert(tags, i)
		end
		gid.tags = tags
		
		gid.nameNoMod = string.sub(gid.name, string.find(gid.name, ":")+1, 999) --oak_log
		gid.modID = string.sub(gid.name, 0, string.find(gid.name, ":")-1) --minecraft
		gid.modName = master.mods[gid.modID] --Minecraft
		
		self.model.items[uniqueKey] = gid
	end
end

function Scanner:initScan(tasks, doInitStuff)
	self.model = {
		inventory = {},
		sizes = {},
		items = {},
		missing = {}
	}
	
	self.currentThreads = math.min(math.floor(self.maxThreads / #self.tasks) * #self.tasks, self.maxThreads)
	local threads = {}
	local scanStart = os.clock()
	local addNewThreads = true
	repeat
		
		while #threads < self.currentThreads and #self.tasks > 0 and addNewThreads do
			local task = table.remove(self.tasks, 1)
			local co
			if not task.slot then
				co = basalt.schedule(function()
					self:scannerThread(task.name)
				end)
			else
				co = basalt.schedule(function()
					self:scannerThread(task.name, task.slot)
				end)
			end
			table.insert(threads, {co = co, task = task.name .. "@" .. tostring(task.slot)})
			coroutine.resume(co)
			if (#threads >= self.currentThreads or #self.tasks <= 0) then
				addNewThreads = false
			end
		end
			
		local deleteThreads = {}
		
		for index, co in ipairs(threads) do

			if coroutine.status(co.co) == "dead" then
				table.insert(deleteThreads, index)
			end
		end
		
		while (#deleteThreads > 0) do
			local thisThread = table.remove(deleteThreads, 1)
			table.remove(threads, thisThread)
			
			for index, otherThread in ipairs(deleteThreads) do
				if thisThread < otherThread then
					deleteThreads[index] = otherThread - 1
				end
			end
		end
		
		addNewThreads = (#threads == 0)
		
		os.sleep()
		
	until #self.tasks == 0 and #threads == 0
	
	return self.model
end