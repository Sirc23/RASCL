UI_RecipeEditorCraft = {}
UI_RecipeEditorCraft.__index = UI_RecipeEditorCraft
UI_RecipeEditorCraft.slots = {1,2,3,5,6,7,9,10,11}


NoTurtlesMessage = "No crafting turtles"

function UI_RecipeEditorCraft:new(recipe, container)
	local r = setmetatable({}, self)
	
	r.recipe = recipe
	
	
	r.foreground = container:addFrame({
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
			local thisSlot = UI_RecipeEditorCraft.slots[i]
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
			if inventory[thisSlot] then
				thisBtn.text = inventory[thisSlot].displayName .. " (" .. tostring(inventory[thisSlot].count) .. ")"
				thisBtn.text = thisBtn.text .. string.rep("\128", math.max(0, container.width - #thisBtn.text))
				thisBtn.item = inventory[thisSlot].name
				if inventory[thisSlot].count > 1 then
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
	local functionArray = {}
	for index, slot in ipairs(UI_RecipeEditorCraft.slots) do
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
	
	local recipeFormat = {}
	recipeFormat.primary_output = {}
	recipeFormat.auxillary_outputs = {}
	recipeFormat.processing = 0
	recipeFormat.recipe_data = {}
	recipeFormat.input = ""
	recipeFormat.output = ""
	recipeFormat.maxBatching = 1024
	
	local itemReferences = {}
	
	local gids = self:getInventory()
	for slot, thisGid in pairs(gids) do
		recipeFormat.maxBatching = math.min(recipeFormat.maxBatching, thisGid.maxCount)
		thisGid.uniqueKey = thisGid.name .. "|" .. (thisGid.nbt or "0")
		if not itemReferences[thisGid.uniqueKey] then
			itemReferences[thisGid.uniqueKey] = {
				uniqueKey = thisGid.uniqueKey,
				displayName = thisGid.displayName,
				gid = thisGid
			}
		end
		
		recipeFormat.recipe_data[slot] = {
			uniqueKey = thisGid.uniqueKey,
			count = thisGid.count
		}
	end
	
	turtle.craft(1)
	
	local primaryGid = turtle.getItemDetail(4, true)
	primaryGid.uniqueKey = primaryGid.name .. "|" .. (primaryGid.nbt or "0")
	recipeFormat.maxBatching = math.min(recipeFormat.maxBatching, primaryGid.maxCount)
	
	if not itemReferences[primaryGid.uniqueKey] then
		itemReferences[primaryGid.uniqueKey] = {
			uniqueKey = primaryGid.uniqueKey,
			displayName = primaryGid.displayName,
			gid = primaryGid
		}
	end
	
	recipeFormat.primary_output = {
		uniqueKey = primaryGid.uniqueKey,
		count = primaryGid.count
	}
	
	local outputGids = self:getInventory()
	for slot, thisGid in pairs(outputGids) do
		thisGid.uniqueKey = thisGid.name .. "|" .. (thisGid.nbt or "0")
		
		if not itemReferences[thisGid.uniqueKey] then
			itemReferences[thisGid.uniqueKey] = {
				uniqueKey = thisGid.uniqueKey,
				displayName = thisGid.displayName,
				gid = thisGid
			}
		end
		
		table.insert(recipeFormat.auxillary_outputs, {
			uniqueKey = thisGid.uniqueKey,
			count = thisGid.count
		})
	end
	
	--Secondary table updates
	local referenceChanges = {}
	for uniqueKey, info in pairs(itemReferences) do
		local thisReference = master.itemInfo[uniqueKey]
		local theseReferences = nil
		if not thisReference then
		theseReferences = master.itemInfoIDs.addItemInfo({
				uniqueKey = uniqueKey,
				displayName = info.displayName,
				tags = info.tags
			}, info.gid)
		
		else
			theseReferences = master.itemInfoIDs.incrementItemInfo(uniqueKey)
		end
		for _, thisChange in ipairs(theseReferences) do
			table.insert(referenceChanges, thisChange)
		end
	end
	--Add broadcast here
	local newPacket = myTalker:makePacket("broadcast_referenceChanges", {
		referenceChanges = referenceChanges
	})
	myTalker:broadcastPacket(newPacket)
	
	outputGids[4] = primaryGid
	
	local newPacket = myTalker:makePacket("send_importTurtleSlots", {
		computerID = os.getComputerID(),
		inventory = outputGids
	})
	myTalker:sendPacket(newPacket, myTalker.host)
	
	os.sleep()
	
	for slot, value in pairs(recipeFormat.recipe_data) do
		value.itemInfoID = master.itemInfo[value.uniqueKey].itemInfoID
		value.uniqueKey = nil
	end
	
	local primaryOutputUniqueKey = recipeFormat.primary_output.uniqueKey
	local recipesList = master.recipes[primaryOutputUniqueKey]
	
	recipeFormat.primary_output.itemInfoID = master.itemInfo[recipeFormat.primary_output.uniqueKey].itemInfoID
	recipeFormat.primary_output.uniqueKey = nil
	
	for slot, value in pairs(recipeFormat.auxillary_outputs) do
		value.itemInfoID = master.itemInfo[value.uniqueKey].itemInfoID
		value.uniqueKey = nil
	end
	
	
	
	recipeFormat.primary_output = textutils.serialiseJSON(recipeFormat.primary_output, {nbt_style = true})
	recipeFormat.auxillary_outputs = textutils.serialiseJSON(recipeFormat.auxillary_outputs, {nbt_style = true})
	recipeFormat.recipe_data = textutils.serialiseJSON(master:compress(recipeFormat.recipe_data), {nbt_style = true})
	
	local maxPriority = 0
	for _, v in pairs(recipesList or {}) do
		maxPriority = math.max(maxPriority, v.priority)
	end
	recipeFormat.priority = maxPriority + 1
	
	
	
	newPacket = myTalker:makePacket("broadcast_addRecipe", {
		recipeFormat = recipeFormat,
		primaryOutputUniqueKey = primaryOutputUniqueKey
	})
	myTalker:broadcastPacket(newPacket)
	
	local recipeObj = Recipe:new(recipeFormat)
	if not recipesList then
		master.recipes[recipeObj.primaryOutput.uniqueKey] = {recipeObj}
	else
		table.insert(master.recipes[recipeObj.primaryOutput.uniqueKey], recipeObj)
		table.sort(master.recipes[recipeObj.primaryOutput.uniqueKey], function(a,b)
			return a.priority < b.priority
		end)
	end
	
	csv.insert(config.recipes, recipeFormat)
	ui_recipeManager:refreshUI()
	ui_craftManager:refreshUI()
end