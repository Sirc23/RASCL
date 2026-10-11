Item = {}
Item.__index = Item

function Item:new(gid, denyUI)
	local r = setmetatable({}, self)
	
	--All item properties are managed via the gid, which is also stored in master.model.items[uniqueKey]
	r.gid = gid
	--See Scanner.lua for the up-to-date list of fields available in gid
	
	--name = minecraft:oak_log
	--displayName = Oak Log
	--nameNoMod = oak_log
	--modID = minecraft
	--modName = Minecraft
	
	--uniqueKey = minecraft:oak_log|0
	
	--count = 5
	--maxCount = 64
	--nbt = Hex code
	--tags = {"minecraft:logs", "minecraft:oak_logs"}
	--containers = {"minecraft:chest_1"}
	
	r.lastAccessed = getUnix() --Unix timestamp
	
	r.cartCount = 0
	
	r.uiStock = nil
	r.uiCart = nil
	
	if not denyUI and r.gid.count > 0 then
		--r.uiStock = r:makeUI(ui_stockManager)
	end
	
	return r
end

function Item:destroy()
	--Only use this function if you are rescanning the entire system
	self:setCart(0)
	self:destroyStockUI()
	self:destroyCartUI()
	
	for thisContainerName, inSlots in pairs(self.gid.containers) do
		self:removeContainer(thisContainerName)
	end
end

function Item:addContainer(containerName, inSlots)
	if not self.gid.containers[containerName] then
		self.gid.containers[containerName] = inSlots
	else
		for _, slot in pairs(inSlots) do
			if searchTable(self.gid.containers[containerName], slot) == -1 then
				table.insert(self.gid.containers[containerName], slot)
			end
		end
	end
end

function Item:removeContainer(containerName)
	self.gid.containers[containerName] = nil
end

function Item:inContainer(container)
	return (searchTable(self.containers, container) ~= -1)
end

function Item:addStock(amount)
	self.lastAccessed = getUnix()
	local newCount = self.gid.count + amount
	if newCount > 0 and self.gid.count == 0 and not self.uiStock then
		--self.uiStock = self:makeUI(ui_stockManager)
		ui_stockManager:refreshUI()
	end
	self.gid.count = newCount
	self:updateUI()
end

function Item:removeStock(amount, keepCart)
	self.lastAccessed = getUnix()
	local newCount = math.max(0, self.gid.count - amount)
	
	--If keepCart is true, we hold off on clamping the amount of items in cart, in case the number of items added back is equal or greater than the items removed
	if not keepCart then
		self:removeCart(amount)
	end
	if newCount == 0 and self.gid.count > 0 then
		self:destroyStockUI(true)
		self:destroyCartUI(true)
	end
	self.gid.count = newCount
	self:updateUI()
end

function Item:setStock(amount)
	amount = amount or self.gid.count
	if(amount > self.gid.count) then
		self:addStock(amount - self.gid.count)
	else
		self:removeStock(self.gid.count - amount)
	end
end

function Item:addCart(amount)
	local newCount = math.min(cartItemsLeft + self.cartCount, self.gid.count, self.cartCount + amount)
	cartItemsLeft = math.max(0, cartItemsLeft + (self.cartCount - newCount))
	if(newCount > 0 and self.cartCount == 0) then
		self.uiCart = self:makeUI(ui_cartManager)
		ui_cartManager:refreshUI()
	end
	self.cartCount = newCount
	ui_stockManager.ui_label:update()
	ui_cartManager.ui_label:update()
	self:updateUI()
end

function Item:removeCart(amount)
	local newCount = math.max(0, self.cartCount - amount)
	local oldCount = self.cartCount
	cartItemsLeft = math.min(tonumber(config.max_cart_size), cartItemsLeft + (self.cartCount - newCount))
	if(newCount == 0 and oldCount > 0) then
		self:destroyCartUI(true)
	end
	self.cartCount = newCount
	if oldCount ~= newCount then
		ui_stockManager.ui_label:update()
		ui_cartManager.ui_label:update()
		self:updateUI()
	end
end

function Item:setCart(amount)
	amount = amount or self.cartCount
	if(amount < self.cartCount) then
		self:removeCart(self.cartCount - amount)
	else
		self:addCart(amount - self.cartCount)
	end
end

function Item:matchesSearch(options)
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
		searchScope = "tags"
		search = string.sub(search, 2)
	end
	
	if not loose then
		search = "^" .. search .. "$"
	end
	
	local bypass = ((search == "" and loose) or (search == "^$"))
	
	local match = bypass
	if bypass then --Don't search
	elseif searchScope == "name" then
		match = (string.find(string.lower(self.gid.displayName), search, 1, loose) ~= nil)
		match = match or (string.find(string.lower(self.gid.nameNoMod), search, 1, loose) ~= nil)
	elseif searchScope == "mod" then
		match = (string.find(string.lower(self.gid.modID), search, 1, loose) ~= nil)
		match = match or (string.find(string.lower(self.gid.modName), search, 1, loose) ~= nil)
	elseif searchScope == "tags" then
		for _,thisTag in pairs(self.gid.tags) do
			if(string.find(string.lower(thisTag), search) ~= nil) then
				match = true
				break
			end
		end
	else
		--Invalid search scope, stop gracefully
		--break
		return false
	end
	
	return match
	
	
end

function Item:buildCheckoutPlan(amount)
	--Data validation to ensure the algorithm does not hang looking for items that don't exist
	quantity = math.min(tonumber(config.max_cart_size), self.gid.count, amount or self.cartCount)
	local remaining = quantity
	local plan = {}
	
	for thisContainerName, inSlots in pairs(self.gid.containers) do
		local thisContainer = master.containers[thisContainerName]
		if thisContainer then
			for _, slot in ipairs(inSlots) do
				local amount = math.min(remaining, thisContainer.inventory[slot].count)
				table.insert(plan, {container = thisContainer, slot = slot, count = amount})
				remaining = remaining - amount
				if remaining <= 0 then
					return plan
				end
			end
		end
	end
	--If the plan has not finalized by now, do not checkout item
	return nil
end

function Item:makeUI(uiManager)
	local container = uiManager.background
    local thisItem = container:addFrame({
        width = container.width,
        height = 2,
        x = 1,
        y = -100,
        background = colors.orange,
        name = self.gid.uniqueKey
    })
	
	thisItem.item = self
	
	local topLabel = thisItem:addLabel({
        width = thisItem.width,
        height = 1,
        x = 1,
        y = 1,
        backgroundEnabled = false,
        foreground = colors.black,
		name = "topLabel"
    })
	
	local bottomLabel = thisItem:addLabel({
        width = thisItem.width,
        height = 1,
        x = 1,
        y = 2,
        backgroundEnabled = false,
        foreground = colors.black,
        name = "bottomLabel"
    })
	if not uiManager.pickMode then
		local quantity = thisItem:addInput({
			width = tonumber(#config.max_cart_size),
			height = 1,
			x = thisItem.width - tonumber(#config.max_cart_size) - 2,
			y = 2,
			background = colors.black,
			foreground = colors.white,
			text = "0",
			name = "quantity"
		})
		
		local add = thisItem:addButton({
			width = 1,
			height = 1,
			x = thisItem.width - tonumber(#config.max_cart_size) - 3,
			y = 2,
			background = colors.green,
			text = "+",
			name = "add"
		})
		add:setBackgroundState("clicked", colors.gray)
		
		local sub = thisItem:addButton({
			width = 1,
			height = 1,
			x = thisItem.width - 2,
			y = 2,
			background = colors.red,
			text = "-",
			name = "sub"
		})
		sub:setBackgroundState("clicked", colors.gray)
		
		local itemStats = thisItem:addButton({
			width = 1,
			height = 1,
			x = thisItem.width - tonumber(#config.max_cart_size) - 5,
			y = 2,
			z = 10,
			text = "i",
			background = colors.blue,
			foreground = colors.white
		})
		
		quantity:onScroll(function(element, direction)
			--Determine direction of scroll and increase/decrease number by a set amount
			local t = tonumber(element.text) - (direction * cartAmount)
			--Clamp number to bounds
			t = math.max(0, t)
			t = math.min(tonumber(config.max_cart_size), element.parent.item.gid.count, t)
			element.text = tostring(t)
		end)
	
		quantity.oldNumber = "0"
		quantity:onKeyUp(function(element, key)
			--Remove all non-digits from string
			element.text = element.text:gsub("%D", "")
			if element.oldNumber == "0" then
				element.text = element.text:gsub("^0*", "")
				element.text = element.text:gsub("0*$", "")
			end
			if(element.text == "") then element.text = "0" end
			--Limit input to max number of digits
			element.text = element.text:sub(0, #config.max_cart_size)
			
			local t = tonumber(element.text)
			--Clamp number to bounds
			t = math.max(0, t)
			t = math.min(tonumber(config.max_cart_size), element.parent.item.gid.count, t)
			element.text = tostring(t)
			element.oldNumber = element.text
			element.viewOffset = 0
			element.cursorPos = math.min(#config.max_cart_size, element.cursorPos)
			
		end)
		
		add:onClick(function(element)
			if quantity.text == "0" then
				quantity.text = tostring(cartAmount)
			end
			element.parent.item:addCart(tonumber(quantity.text))
			quantity.text = "0"
			bottomLabel.update()
		end)
		sub:onClick(function(element)
			if quantity.text == "0" then
				quantity.text = tostring(cartAmount)
			end
			element.parent.item:removeCart(tonumber(quantity.text))
			quantity.text = "0"
			bottomLabel.update()
		end)
		
		itemStats:onClick(function(element)
			ui_stockManager:showItemStats(self.gid.uniqueKey, true)
		end)
	else
		local picker = thisItem:addButton({
			width = 4,
			height = 1,
			x = thisItem.width - 5,
			y = 2,
			background = colors.cyan,
			foreground = colors.black,
			text = "pick"
		})
		picker:onClick(function(element)
			uiManager.pickedItem = thisItem.item
		end)
	end
	--[[
	local itemStats = thisItem:addButton({
		width = thisItem.width - tonumber(#config.max_cart_size) - 4,
		height = 2,
		x = 1,
		z = 10,
		text = "",
		backgroundEnabled = false
	})--]]
	
	topLabel.update = bindFunctionToInstance(topLabel, function(element)
		local t = element.parent.item.gid.displayName
		--Create top delimiter
        local t = t .. string.rep("\175", math.max(0, element.width - #t))
        element.text = t
	end)
	
	bottomLabel.update = bindFunctionToInstance(bottomLabel, function(element)
		local t = ""
		if not uiManager.pickMode then
			t = tostring(element.parent.item.gid.count) .. "\04" .. tostring(element.parent.item.cartCount)
		else
			t = element.parent.item.gid.modName
		end
		--Create bottom delimiter
        local t = t .. string.rep("_", math.max(0, element.width - #t))
        element.text = t
	end)
	
	thisItem.update = bindFunctionToInstance(thisItem, function(element)
		topLabel.update()
		bottomLabel.update()
	end)
	
	thisItem.update()
    return thisItem
end

function Item:updateUI()
	if self.uiStock then
		self.uiStock:update()
	end
	if self.uiCart then
		self.uiCart:update()
	end
	if ui_stockManager.sort == "amount" then
		ui_stockManager:refreshUI()
	end
end

function Item:destroyStockUI(refreshUI)
	if self.uiStock then
		self.uiStock:destroy()
		if refreshUI then
			ui_stockManager:refreshUI()
		end
	end
	self.uiStock = nil
end

function Item:destroyCartUI(refreshUI)
	if self.uiCart then
		self.uiCart:destroy()
		if refreshUI then
			ui_cartManager:refreshUI()
		end
	end
	self.uiCart = nil
	
end