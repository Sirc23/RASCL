Recipe = {}
Recipe.__index = Recipe

function Recipe:new(recipeCSV)
	local r = setmetatable({}, self)
	
	r.newRecipe = (recipeCSV == nil)
	
	if not r.newRecipe then
		r:setFromCSV(recipeCSV)
	end
	r.ui = nil
	
	return r
end

function Recipe:setFromCSV(recipeCSV)
	self.CSV = recipeCSV
	--All item properties are managed via the gid, which is also stored in master.model.items[uniqueKey]
	self.uniqueID = recipeCSV.uniqueID
	self.primaryOutput = textutils.unserialiseJSON(recipeCSV["primary_output"])
	
	self.auxillaryOutputs = textutils.unserialiseJSON(recipeCSV.auxillary_outputs)
	self.auxillaryOutputsDecompressed = master:decompressRecipe(self.auxillaryOutputs)
	local split = splitString(self.primaryOutput.uniqueKey, "|")
	self.primaryOutput.name = split[1]
	self.primaryOutput.nbt = split[2] or "0"
	self.primaryOutput.any = (#split ~= 2)
	
	self.recipeType = recipeCSV.recipe_type
	self.priority = tonumber(recipeCSV.priority)
	self.recipeData = textutils.unserialiseJSON(recipeCSV.recipe_data)
	self.recipeDataDecompressed = master:decompressRecipe(self.recipeData)
	self.maxBatching = tonumber(recipeCSV.maxBatching)
	self.input = recipeCSV.input
	self.output = recipeCSV.output
end

function Recipe:destroy()
	master.recipes[self.uniqueID] = nil
	csv.delete(config.recipes, function(row) return row["uniqueID"] == self.uniqueID end)
	
	self:destroyUI()
	ui_recipeManager:refreshUI()
	self = nil
end

function Recipe:matchesSearch(options)
	local search = options.search or ""
	search = string.lower(search)
	local loose = options.loose or (options.loose == nil and true)
	local inCart = options.inCart or false
	
	if inCart and self.cartCount == 0 then return false end
	
	local qualifier = string.sub(search, 0, 1)
	local searchScope = "name"
	if qualifier == "@" then
		searchScope = "mod"
		search = string.sub(search, 2)
	elseif qualifier == "#" then
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
		match = match or (string.find(string.lower(self.primaryOutput.name), search, 1, loose) ~= nil)
	elseif searchScope == "mod" then
		match = (string.find(string.lower(self.primaryOutput.mod), search, 1, loose) ~= nil)
		match = match or (string.find(string.lower(master.mods[self.primaryOutput.mod]), search, 1, loose) ~= nil)
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
				uniqueID = self.uniqueID
			})
			myTalker:broadcastPacket(newPacket)
			self:destroy()
		else
			local newPacket = myTalker:makePacket("send_deleteRecipe", {
				uniqueID = self.uniqueID
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		end
	end)
	
	topLabel.update = bindFunctionToInstance(topLabel, function(element)
		local t = element.parent.recipe.primaryOutput.displayName
		--local t = "help"
		--Create top delimiter
        t = t .. string.rep("\175", math.max(0, element.width - #t))
        element.text = t
	end)
	
	bottomLabel.update = bindFunctionToInstance(bottomLabel, function(element)
		local t = capitalizeWords(element.parent.recipe.recipeType)
		--local t = "me"
		
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