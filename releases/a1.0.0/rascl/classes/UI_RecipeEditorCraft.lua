UI_RecipeEditorCraft = {}
UI_RecipeEditorCraft.__index = UI_RecipeEditorCraft

NoTurtlesMessage = "No crafting turtles"

function UI_RecipeEditorCraft:new(recipe, container)
	local r = setmetatable({}, self)
	
	r.recipe = recipe
	
	
	r.foreground = container:addScrollFrame({
		width = container.width,
        height = container.height,
        x = 1,
        y = 1,
        z = 10,
		scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.lightGray,
        scrollBarBackgroundColor2 = colors.gray,
        background = colors.lightGray
    })
		
		r.ui_learn = r:initLearn(r.foreground)
		r.ui_cancel = r:initCancel(r.foreground)
		
		r.ui_ingredientsLabel = r:initIngredientsLabel(r.foreground)
		r.ui_ingredientsTable = r:initIngredientsTable(r.foreground)
		
		r.ui_priority = r:initPriority(r.foreground)
		basalt.schedule(function()
			local timeoutFunction = function()
				os.sleep(1)
			end
			local mainFunction = function()
				local event, name = os.pullEvent("turtle_inventory")
				r.ui_ingredientsTable.rebuildTable()
			end
			while r.foreground do
				parallel.waitForAny(timeoutFunction, mainFunction)
			end
		end)
	return r
end

function UI_RecipeEditorCraft:destroy()
	self.foreground:destroy()
	self.foreground = nil
end


function UI_RecipeEditorCraft:initLearn(container)
	local r = container:addButton({
		width = 6,
		height = 1,
		x = 1,
		y = 1,
		background = colors.green,
		foreground = colors.black,
		visible = false,
		text = "Learn!",
		name = "learn"
	})
	r:onClick(function(element)
		self:learn()
		
		self:destroy()
	end)
	
	return r
end


function UI_RecipeEditorCraft:initCancel(container)
	local r = container:addButton({
		width = 6,
		height = 1,
		x = container.width - 5,
		y = 1,
		background = colors.red,
		foreground = colors.black,
		text = "cancel",
		name = "cancel"
	})
	r:onClick(function(element)
		self.recipe:destroy()
		self:destroy()
	end)
	
	return r
end


function UI_RecipeEditorCraft:initIngredientsLabel(container)
	local r = container:addLabel({
		width = container.width,
		height = 1,
		x = 1,
		y = self.ui_learn.y + 1,
		background = colors.orange,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Items" .. string.rep(" ", container.width - 15 - 3) .. "Priority: ",
		name = "ingredientsLabel"
	})
	
	return r
end

function UI_RecipeEditorCraft:initPriority(container)
	local r = container:addInput({
			width = 3,
			height = 1,
			x = #self.ui_ingredientsLabel.text + 1,
			y = self.ui_ingredientsLabel.y,
			background = colors.black,
			foreground = colors.white,
			text = "0",
			name = "priority"
		})
	
	r:onScroll(function(element, direction)
		--Determine direction of scroll and increase/decrease number by a set amount
		local t = tonumber(element.text) - (direction * cartAmount)
		--Clamp number to bounds
		t = math.max(0, t)
		t = math.min(99, t)
		element.text = tostring(t)
	end)
	
	r.oldNumber = "0"
	r:onKeyUp(function(element, key)
		--Remove all non-digits from string
		element.text = element.text:gsub("%D", "")
		if element.oldNumber == "0" then
			element.text = element.text:gsub("^0*", "")
			element.text = element.text:gsub("0*$", "")
		end
		if(element.text == "") then element.text = "0" end
		--Limit input to max number of digits
		element.text = element.text:sub(0, 3)
		
		local t = tonumber(element.text)
		--Clamp number to bounds
		t = math.max(0, t)
		t = math.min(99, t)
		element.text = tostring(t)
		element.oldNumber = element.text
		element.viewOffset = 0
		element.cursorPos = math.min(3, element.cursorPos)
		
	end)
	
	return r
end

function UI_RecipeEditorCraft:initIngredientsTable(container)
	local r = container:addFrame({
		width = container.width,
		height = 9,
		x = 1,
		y = self.ui_ingredientsLabel.y + 1,
		background = colors.gray,
		foreground = colors.white,
		name = "ingredientsTable"
	})
	
	
	r.rebuildTable = bindFunctionToInstance(r, function(element)
		element:clear()
		self.ui_learn.visible = false
		local inventory, isValid = self:getInventory()
		if not inventory then return end
		local canLearn = true
		for _, thisItem in pairs(inventory) do
			if thisItem.count > 1 then
				canLearn = false
				break
			end
		end
		self.ui_learn.visible = isValid and canLearn
		for i = 1,9 do
			local thisBtn = r:addButton({
				width = container.width,
				height = 1,
				x = 1,
				y = i,
				background = colors.gray,
				foreground = colors.black,
				text = "",
				name = tostring(i)
			})
			if inventory[i] then
				thisBtn.text = inventory[i].displayName .. " (" .. tostring(inventory[i].count) .. ")"
				thisBtn.text = thisBtn.text .. string.rep("\128", math.max(0, container.width - #thisBtn.text))
				thisBtn.item = inventory[i].name
				if inventory[i].count > 1 then
					thisBtn.foreground = colors.red
				end
			else
				thisBtn.item = nil
			end
			
			thisBtn:setBackgroundState("clicked", colors.gray)
			thisBtn:onClick(function(element)
				if element.item then
					master:copyToClipboard(element.item)
				end
			end)
		end
	end)
	
	basalt.schedule(function()
		r.rebuildTable()
	end)
	
	return r
end

function UI_RecipeEditorCraft:getInventory()
	local inventory = {}
	local slots = {1,2,3,5,6,7,9,10,11}
	local functionArray = {}
	for index, slot in ipairs(slots) do
		local f = function()
			inventory[slot] = turtle.getItemDetail(slot, true)
		end
		table.insert(functionArray, f)
	end
	parallel.waitForAll(table.unpack(functionArray))
	return inventory, turtle.craft(0)
end

function UI_RecipeEditorCraft:learn()
	turtle.select(4)
	--TODO: Ensure no recipes with this priority and output already exist
	--Problem: you don't know what the output is until you make it
	--Workaround: Force the priority to increment in this case
	
	local recipeFormat = {}
	recipeFormat.uniqueID = getUniqueID(8)
	recipeFormat.primary_output = {}
	recipeFormat.auxillary_outputs = {}
	recipeFormat.recipe_type = "crafting"
	recipeFormat.priority = tostring(self.ui_priority.text)
	recipeFormat.recipe_data = {}
	recipeFormat.input = ""
	recipeFormat.output = ""
	recipeFormat.maxBatching = 1024
	
	local gids = self:getInventory()
	for slot, thisGid in pairs(gids) do
		recipeFormat.maxBatching = math.min(recipeFormat.maxBatching, thisGid.maxCount)
		recipeFormat.recipe_data[slot] = {
			uniqueKey = thisGid.name .. "|" .. (thisGid.nbt or "0"),
			name = thisGid.name,
			nbt = thisGid.nbt or "0",
			displayName = thisGid.displayName,
			mod = thisGid.mod
		}
	end
	
	turtle.craft(1)
	
	local primaryGid = turtle.getItemDetail(4, true)
	primaryGid.uniqueKey = primaryGid.name .. "|" .. (primaryGid.nbt or "0")
	recipeFormat.uniqueID = primaryGid.uniqueKey .. "-" .. recipeFormat.uniqueID
	recipeFormat.primary_output = {
		count = primaryGid.count,
		chance = 1.0,
		uniqueKey = primaryGid.uniqueKey,
		name = primaryGid.name,
		nbt = primaryGid.nbt or "0",
		displayName = primaryGid.displayName,
		mod = primaryGid.mod
	}
	local newPacket = myTalker:makePacket("send_importTurtleSlot", {
		computerID = os.getComputerID(),
		slot = 4,
		gid = primaryGid
	})
	myTalker:sendPacket(newPacket, myTalker.host)
	os.sleep()
	
	local outputGids = self:getInventory()
	for slot, thisGid in pairs(outputGids) do
		thisGid.uniqueKey = thisGid.name .. "|" .. (thisGid.nbt or "0")
		recipeFormat.auxillary_outputs[slot] = {
			uniqueKey = thisGid.uniqueKey,
			name = thisGid.name,
			nbt = thisGid.nbt or "0",
			displayName = thisGid.displayName,
			mod = thisGid.mod
		}
		local newPacket = myTalker:makePacket("send_importTurtleSlot", {
			computerID = os.getComputerID(),
			slot = slot,
			gid = thisGid
		})
		myTalker:sendPacket(newPacket, myTalker.host)
		os.sleep()
	end
	
	recipeFormat.primary_output = textutils.serialiseJSON(recipeFormat.primary_output)
	recipeFormat.auxillary_outputs = textutils.serialiseJSON(master:compressRecipe(recipeFormat.auxillary_outputs))
	recipeFormat.recipe_data = textutils.serialiseJSON(master:compressRecipe(recipeFormat.recipe_data))
	
	newPacket = myTalker:makePacket("broadcast_updateRecipe", {
		recipe = recipeFormat
	})
	myTalker:broadcastPacket(newPacket)
	local recipeObj = Recipe:new(recipeFormat)
	master.recipes[recipeFormat.uniqueID] = recipeObj
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
	csv.insert(config.recipes, recipeFormat)
	ui_recipeManager:refreshUI()
	ui_craftManager:refreshUI()
end