Recipe = {}
Recipe.__index = Recipe

function Recipe:extract(data, keepAsList)
	r = {}
	for _, thisInfo in pairs(data) do
		local thisInfoID = thisInfo.itemInfoID
		local thisCount = thisInfo.count
		local thisSlots = thisInfo.slots
		
		local thisItemInfo = master.itemInfoIDs[thisInfoID]
		local thisEntry = {
			uniqueKey = thisItemInfo.uniqueKey,
			displayName = thisItemInfo.displayName,
			count = thisCount,
		}
		if thisSlots and keepAsList then
			thisEntry.slots = thisSlots
		end
		thisEntry.tags = {}
		for _, thisTagID in pairs(thisItemInfo.tags) do
			local thisTag = master.tagIDs[thisTagID].tag
			table.insert(thisEntry.tags, thisTag)
		end
		
		if thisSlots and not keepAsList then
			local slotArray = bitmaskToArray(thisSlots)
			for _, i in pairs(slotArray) do
				local d = deepCopy(thisEntry)
				d.slot = i
				d.count = 1
				table.insert(r, d)
			end
		else
			table.insert(r, thisEntry)
		end
	end
	return r
end

function Recipe:new(recipeCSV, suppressReferences)
	local r = setmetatable({}, self)
	
	r.newRecipe = (recipeCSV == nil)
	
	if not r.newRecipe then
		r:setFromCSV(recipeCSV, suppressReferences)
	end
	r.ui = nil
	
	return r
end

function Recipe:setFromCSV(recipeCSV, suppressReferences)
	self.CSV = recipeCSV
	--All item properties are managed via the gid, which is also stored in master.model.items[uniqueKey]
	self.primaryOutput = textutils.unserialiseJSON(self.CSV.primary_output, {nbt_style = true})
	self.primaryOutput = self:extract({self.primaryOutput})[1]
	--[[
	primaryOutput format:
	{
		uniqueKey = string,
		displayName = string,
		count = int,
		tags = {"minecraft:logs", ...}
		name = string,
		nbt = string
	}
	--]]
	
	self.auxillaryOutputs = textutils.unserialiseJSON(self.CSV.auxillary_outputs, {nbt_style = true})
	self.auxillaryOutputs = self:extract(self.auxillaryOutputs)
	--auxillaryOutputs is an array where each entry is formatted like primaryOutput
	
	local nbt_split = splitString(self.primaryOutput.uniqueKey, "|")
	self.primaryOutput.name = nbt_split[1]
	self.primaryOutput.nbt = nbt_split[2]
	
	local mod_split = splitString(self.primaryOutput.name, ":")
	self.mod = mod_split[1]
	self.modName = master.mods[self.mod] or "Undefined"
	self.nameNoMod = mod_split[2]
	
	
	self.processing = (tonumber(self.CSV.processing) == 1)
	self.recipeType = "processing" and self.processing or "crafting"
	self.priority = tonumber(self.CSV.priority)
	self.recipeDataRaw = textutils.unserialiseJSON(self.CSV.recipe_data, {nbt_style = true})
	self.recipeDataCompressed = self:extract(self.recipeDataRaw, true)
	--[[
		recipeDataCompressed is an array where each entry is of this format:
		{
			uniqueKey = string,
			displayName = string,
			count = int,
			slots = int, --Compressed bit representation
			tags = {}
		}
	--]]
	self.recipeDataDecompressed = self:extract(self.recipeDataRaw)
	--[[
		recipeDataDecompressed is an array where each entry is of this format:
		{
			uniqueKey = string,
			displayName = string,
			count = 1,
			slot = int,
			tags = {}
		}
	--]]
	self.maxBatching = tonumber(self.CSV.maxBatching)
	self.input = self.CSV.input
	self.output = self.CSV.output
	self.uniqueID = self.primaryOutput.uniqueKey .. "|" .. self.priority
end

function Recipe:destroy()
	if self.primaryOutput then
		local deleteThis = nil
		for i, value in pairs(master.recipes[self.primaryOutput.uniqueKey]) do
			if value == self then
				deleteThis = i
				break
			end
		end
		if deleteThis then
			table.remove(master.recipes[self.primaryOutput.uniqueKey], deleteThis)
			if #master.recipes[self.primaryOutput.uniqueKey] == 0 then
				master.recipes[self.primaryOutput.uniqueKey] = nil
			end
		end
	end
	
	csv.delete(config.recipes, function(row) return
		row["primary_output"] == self.CSV.primary_output and
		row["priority"] == tostring(self.CSV.priority) and
		row["processing"] == tostring(self.CSV.processing)
	end)
	
	self:destroyUI()
	ui_recipeManager:refreshUI()
	ui_craftManager:refreshUI()
	self = nil
end

function Recipe:referenceChanges()
	local itemReferences = {}
	
	for _, thisRecipeData in pairs(self.recipeDataCompressed) do
		itemReferences[thisRecipeData.uniqueKey] = {
			uniqueKey = thisRecipeData.uniqueKey,
			displayName = thisRecipeData.displayName
		}
	end
	
	if not itemReferences[self.primaryOutput.uniqueKey] then
		itemReferences[self.primaryOutput.uniqueKey] = {
			uniqueKey = self.primaryOutput.uniqueKey,
			displayName = self.primaryOutput.displayName
		}
	end
	
	for _, thisAuxillaryOutput in pairs(self.auxillaryOutputs) do
		if not itemReferences[thisAuxillaryOutput.uniqueKey] then
			itemReferences[thisAuxillaryOutput.uniqueKey] = {
				uniqueKey = thisAuxillaryOutput.uniqueKey,
				displayName = thisAuxillaryOutput.displayName
			}
		end
	end
	
	local referenceChanges = {}
	for uniqueKey, info in pairs(itemReferences) do
		local theseReferences = master.itemInfoIDs.decrementItemInfo(uniqueKey)
		
		for _, thisChange in ipairs(theseReferences) do
			table.insert(referenceChanges, thisChange)
		end
	end
	--Add broadcast here
	local newPacket = myTalker:makePacket("broadcast_referenceChanges", {
		referenceChanges = referenceChanges
	})
	myTalker:broadcastPacket(newPacket)
end

function Recipe:matchesSearch(options)
	local search = options.search or ""
	search = string.lower(search)
	local loose = options.loose or (options.loose == nil and true)
	
	local qualifier = string.sub(search, 0, 1)
	local searchScope = "name"
	if qualifier == "$" then
		searchScope = "type"
		search = string.sub(search, 2)
	end
	
	if not loose then
		search = "^" .. search .. "$"
	end
	
	local bypass = ((search == "" and loose) or (search == "^$"))
	
	local match = bypass
	if bypass then --Don't search
	elseif searchScope == "name" then
		match = (string.find(string.lower(self.primaryOutput.displayName), search, 1, loose) ~= nil)
	elseif searchScope == "type" then
		match = (string.find(string.lower(self.recipeType), search, 1, loose) ~= nil)
	else
		--Invalid search scope, stop gracefully
		--break
		return false
	end
	
	return match
	
	
end

function Recipe:makeUI(uiManager)
	local container = uiManager.background
    local thisRecipe = container:addFrame({
        width = container.width,
        height = 2,
        x = 1,
        y = -100,
        background = colors.magenta,
        name = self.primaryOutput.uniqueKey
    })
	
	thisRecipe.recipe = self
	
	local topLabel = thisRecipe:addLabel({
        width = thisRecipe.width,
        height = 1,
        x = 1,
        y = 1,
        backgroundEnabled = false,
        foreground = colors.black,
		name = "topLabel"
    })
	
	local bottomLabel = thisRecipe:addLabel({
        width = thisRecipe.width,
        height = 1,
        x = 1,
        y = 2,
        backgroundEnabled = false,
        foreground = colors.black,
        name = "bottomLabel"
    })
	
	local delete = thisRecipe:addButton({
		width = 1,
		height = 1,
		x = thisRecipe.width - 2,
		y = 1,
		background = colors.red,
		foreground = colors.black,
		text = "X",
		name = "delete"
	})
	delete:setBackgroundState("clicked", colors.gray)
	delete:onClick(function(element)
		if isHost then
			local newPacket = myTalker:makePacket("broadcast_deleteRecipe", {
				uniqueKey = self.primaryOutput.uniqueKey,
				uniqueID = self.uniqueID
			})
			myTalker:broadcastPacket(newPacket)
			self:referenceChanges()
			self:destroy()
		else
			local newPacket = myTalker:makePacket("send_deleteRecipe", {
				uniqueKey = self.primaryOutput.uniqueKey,
				uniqueID = self.uniqueID
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		end
	end)
	
	topLabel.update = bindFunctionToInstance(topLabel, function(element)
		local t = element.parent.recipe.primaryOutput.displayName
		--Create top delimiter
        t = t .. string.rep("\175", math.max(0, element.width - #t))
        element.text = t
	end)
	
	bottomLabel.update = bindFunctionToInstance(bottomLabel, function(element)
		local t = capitalizeWords(element.parent.recipe.recipeType)
		
		--Create bottom delimiter
        t = t .. string.rep("_", math.max(0, element.width - #t))
        element.text = t
	end)
	
	thisRecipe.update = bindFunctionToInstance(thisRecipe, function(element)
		topLabel.update()
		bottomLabel.update()
	end)
	
	thisRecipe.update()
    return thisRecipe
end

function Recipe:updateUI()
	if self.ui then
		self.ui:update()
	end
end

function Recipe:destroyUI(refreshUI)
	if self.ui then
		self.ui:destroy()
		if refreshUI then
			ui_recipeManager:refreshUI()
		end
	end
	self.ui = nil
end