UI_Cart = {}
UI_Cart.__index = UI_Cart
NoContainersMessage = "No outputs"

function UI_Cart:new(container)
	local r = setmetatable({}, self)
	
	r.foreground = container
		r.ui_output = r:initOutput(r.foreground)
		r.ui_send = r:initSend(r.foreground)
		r.ui_label = r:initLabel(r.foreground)
		r.ui_refresh = r:initRefresh(r.foreground)
		r.ui_clear = r:initClear(r.foreground)
	
		r.background = r:initBackground(r.foreground)
	return r
end

function UI_Cart:refreshUI()
	if not self.refreshScheduled then
		self.refreshScheduled = true
		basalt.schedule(function()
			os.sleep()
			self:sortUI()
			self.refreshScheduled = false
		end)
	end
end

function UI_Cart:sortUI()
	
	local i = 1
	local color = colors.orange
	for _, thisItem in pairs(self.background.children) do
		thisItem.y = i
		i = i + 2
		
		thisItem.background = color
		if color == colors.orange then
			color = colors.yellow
		else
			color = colors.orange
		end
	end
end

function UI_Cart:initOutput(container)
	local r = container:addDropDown({
        width = ui_cart.width,
        height = 1,
        x = 1,
        y = 1,
		z = 10,
        background = colors.black,
        foreground = colors.white,
		name = "output"
    })
	r:onSelect(function(element, index)
        local selectedName = element._values.items[index].text
		element.text = selectedName
    end)
	
	r.scheduleUpdate = bindFunctionToInstance(r, function(element)
		if not element.updateScheduled then
			element.updateScheduled = true
			basalt.schedule(function()
				os.sleep()
				element.update()
				element.updateScheduled = false
			end)
		end
	end)
	
	r.update = bindFunctionToInstance(r, function(element)
		local list = {}
		for _, thisContainer in pairs(master.containers) do
			if thisContainer.type == "output" and not thisContainer:missing() then
				table.insert(list, thisContainer)
			end
		end
		
		table.sort(list, function(a,b)
			local c = (a.container ~= b.container)
			return (a.container < b.container and c)
				or (a.number < b.number and not c)
		end)
		
		local outputChests = {}
		for _, thisContainer in pairs(list) do
			table.insert(outputChests, {
				text = thisContainer.displayName,
				background = colors.black,
				foreground = colors.white
			})
		end
		
		if(#outputChests > 0) then
			if(#outputChests > element.dropdownHeight) then
				table.insert(outputChests, {
					text = "",
					background = colors.black,
					foreground = colors.white,
					separator = true
				}) --Dropdown scroll bug
			end
			element:setItems(outputChests)
			element.text = outputChests[1].text
			element._values.items[1].selected = true
		else
			element:setItems({
				{
					text = NoContainersMessage,
					background = colors.black,
					foreground = colors.red
				}
			})
			element.text = element._values.items[1].text
			element._values.items[1].selected = true
		end
	end)
	
	r.setSelected = bindFunctionToInstance(r, function(element, name)
		for index, thisValue in pairs(r._values.items) do
			if thisValue.text == name then
				r.text = element._values.items[index].text
				r._values.items[index].selected = true
			else
				r._values.items[index].selected = false
			end
		end
	end)
	
	r.update()
	
	return r
end

function UI_Cart:initSend(container)
	local output = container:getChild("output")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = container.width - 1,
        y = self.ui_output.y + 1,
        background = colors.green,
        text = "\187\187",
		name = "send"
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		basalt.schedule(function()
			local cart = {}
			for _, thisCartItem in pairs(self.background.children) do
				table.insert(cart, {
					uniqueKey = thisCartItem.item.gid.uniqueKey,
					amount = thisCartItem.item.cartCount
				})
			end
			
			if cart == {} then return end
			local didSendCart
			local transfers
			
			if isHost then
				didSendCart, transfers = self:sendCart(cart, self.ui_output.text)
			else
				
				didSendCart = myTalker:request("cartCheckout", {
					cart = cart,
					outputContainerName = self.ui_output.text
				})
			end
			
			if didSendCart then
				--Clear cart
				self.ui_clear:fireEvent("mouse_click")
				ui_stockManager.ui_quickSend.foreground = colors.black
				element.foreground = colors.black
				
				if isHost then
					newPacket = myTalker:makePacket("broadcast_cartCheckout", {
						transfers = transfers
					})
					myTalker:broadcastPacket(newPacket)
				end
			else
				ui_stockManager.ui_quickSend.foreground = colors.red
				element.foreground = colors.red
			end
		end)
    end)
	
	return r
end

function UI_Cart:initLabel(container)
	local r = container:addLabel({
        height = 1,
        x = container.width - (2 * #config.max_cart_size) - 4,
        y = self.ui_send.y,
        text = "\04" .. "0/" .. tostring(config.max_cart_size),
		name = "label"
    })
	r.update = bindFunctionToInstance(r, function(element)
		local padding = "%-" .. tostring(#config.max_cart_size) .. "s"
        local t = "\04" .. string.format(padding, tostring(tonumber(config.max_cart_size) - cartItemsLeft)) .. "/" .. string.format(padding, tostring(config.max_cart_size))
        element.text = t
	end)
	r.update()
	return r
end

function UI_Cart:initRefresh(container)
	local r = container:addButton({
        width = 7,
        height = 1,
        x = container.width - 6,
        y = -30,
        background = colors.orange,
        text = "refresh",
		name = "refresh"
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
        self.ui_output.scheduleUpdate()
    end)
	
	return r
end

function UI_Cart:initClear(container)
	local r = container:addButton({
        width = 5,
        height = 1,
        x = 1,
        y = self.ui_send.y,
        background = colors.red,
        text = "clear",
        name = "clear"
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		--Copy elements to an array that keeps references after they are removed as children so that the for loop does not skip an index when the array gets shorter
		local temporaryItems = {}
        for _, thisCartItem in pairs(self.background.children) do
			table.insert(temporaryItems, thisCartItem)
		end
		for _, thisCartItem in pairs(temporaryItems) do
			thisCartItem.item:removeCart(thisCartItem.item.cartCount)
        end
    end)
	
	return r
end

function UI_Cart:initBackground(container)
	local r = container:addScrollFrame({
		width = container.width,
        height = container.height - (self.ui_send.y + 2),
        x = 1,
        y = self.ui_send.y + 2,
        background = colors.gray,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.lightGray,
        scrollBarBackgroundColor2 = colors.gray,
		name = "background"
	})
	
	return r
end

function UI_Cart:sendCart(cart, outputContainer)
	--A checkout is already running, do not start a second one
	if self.checkoutRunning then return false end
	if not outputContainer or outputContainer == "" or outputContainer == NoContainersMessage then return false end

	--Find destination container name
	local foundContainer = false
	for _, thisContainer in pairs(master.containers) do
		if outputContainer == thisContainer.displayName then
			outputContainer = thisContainer.name
			foundContainer = true
			break
		end
	end

	if not foundContainer then return false end
	
	self.checkoutRunning = true
	local transfers = {}
	--basalt.schedule(function()
		--Develop checkout plan
		--TODO: Parallelize this with basalt.schedule
		local finalPlan = {}
		for _, thisCartItem in pairs(cart) do
			local uniqueKey = thisCartItem.uniqueKey
			local item = master.storage[uniqueKey]
			if item then
				local thisPlan = item:buildCheckoutPlan(thisCartItem.amount)
				if thisPlan ~= nil then
					table.insert(finalPlan, thisPlan)
				end
			end
		end

		--Perform movement operations
		for _, thisPlan in pairs(finalPlan) do
			for _, thisOperation in pairs(thisPlan) do
				local thisContainer = thisOperation.container
				local thisTransfer = thisContainer:checkout(outputContainer, thisOperation.slot, thisOperation.count)
				thisOperation.count = thisTransfer
				thisOperation.container = thisContainer.name
				table.insert(transfers, thisOperation)
			end
		end
		ui_stockManager:refreshUI()
		self.checkoutRunning = false
	--end)
	return true, transfers
end