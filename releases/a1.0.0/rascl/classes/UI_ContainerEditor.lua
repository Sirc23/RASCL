UI_ContainerEditor = {}
UI_ContainerEditor.__index = UI_ContainerEditor

function UI_ContainerEditor:new(container, parentContainer)
	local r = setmetatable({}, self)
	
	r.container = container
	
	r.foreground = parentContainer:addScrollFrame({
		width = termX - 2,
        height = termY - 1,
        x = 2,
        y = 1,
        z = 10,
        background = colors.gray
    })
	r.foreground:addBorder({
		color = colors.yellow,
		top = true,
		left = true,
		right = true,
		bottom = true
	})
		
		r.ui_label = r:initLabel(r.foreground, container.displayName)
		r.ui_storageType = r:initStorageType(r.foreground, container.type)
		r.ui_ok = r:initOk(r.foreground)
		r.ui_size = r:initSize(r.foreground)
		r.ui_allItems = r:initAllItems(r.foreground)
		r.ui_filter = r:initFilter(r.foreground)
		r.ui_snapshot = r:initSnapshot(r.foreground)
		--Add stats about container later
	
	return r
end

function UI_ContainerEditor:destroy()
	self.foreground:destroy()
	ui_containerManager.currentEditor = nil
end

function UI_ContainerEditor:initLabel(container, name)
	local r = container:addLabel({
        height = 1,
        x = 1,
        y = 1,
		text = " " .. name .. " ",
        foreground = colors.black,
		background = colors.yellow,
		backgroundEnabled = true
    })
	
	return r
end

function UI_ContainerEditor:initStorageType(container, storageType)
	local r = container:addDropDown({
        width = container.width - 8,
        height = 1,
        x = 2,
        y = 2,
		z = 200,
        background = colors.black,
        foreground = colors.white,
		dropdownHeight = 7
    })
	r:onSelect(function(element, index)
        element.text = element._values.items[index].text
        self.ui_filter.visible = (element.text == "storage")
		if element.text == "storage" then
			self.ui_filter.update()
		end
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		r:setItems({
			{
				text = "storage",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "input",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "output",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "ignore",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "crafting-input",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "crafting-output",
				background = colors.black,
				foreground = colors.white
			}
		})
		
		r.text = storageType
		
		for _,v in pairs(r._values.items) do
			if(v.text == r.text) then
				v.selected = true
				break
			end
		end
	end)
	
	r.update()
	
	return r
end

function UI_ContainerEditor:initOk(container)
	local r = container:addButton({
        width = 4,
        height = 1,
        x = container.width - 5,
        y = self.ui_storageType.y,
        background = colors.green,
        text = " ok "
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
        if not isHost then
			local changes = self:getChanges()
			if changes.type == "storage" and not changes.filter then return end
			local containerName = self.container.name
			self:destroy()
			local newPacket = myTalker:makePacket("send_containerEditorSave", {
				containerName = self.container.name,
				changes = changes
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			local changes = self:getChanges()
			if changes.type == "storage" and not changes.filter then return end
			local newPacket = myTalker:makePacket("broadcast_containerEditorSave", {
				containerName = self.container.name,
				changes = changes
			})
			myTalker:broadcastPacket(newPacket)
			element.runButton(element)
		end
    end)
	r.runButton = function(element)
		self.container:saveChanges(self:getChanges())
        self:destroy()
	end
	
	return r
end

function UI_ContainerEditor:initSize(container)
	local r = container:addLabel({
		width = container.width - 8,
		height = 1,
		x = 2,
		y = self.ui_ok.y + 1,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Size: " .. tostring(master.model.sizes[self.container.name])
	})
	
	return r
end

function UI_ContainerEditor:initAllItems(container)
	local r = container:addButton({
		width = 4,
		height = 1,
		x = container.width - 5,
		y = self.ui_size.y,
		background = colors.blue,
		foreground = colors.black,
		text = "item",
		visible = self.container.type == "storage" and not master.model.missing[self.container.name],
		name = "slotFilter"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		if element.text == "item" then
			element.text = "slot"
		else
			element.text = "item"
		end
		self.ui_snapshot.update()
	end)
	
	return r
end


function UI_ContainerEditor:initFilter(container)
	local r = container:addDropDown({
        width = container.width - 2,
        height = 1,
        x = 2,
        y = self.ui_allItems.y + 2,
		z = 100,
        background = colors.black,
        foreground = colors.white
    })
	r:onSelect(function(element, index)
        element.text = element._values.items[index].text
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		--Populate list from visible filters
		element.visible = (self.ui_storageType.text == "storage")
		if not element.visible then
			element:setItems({})
			element.text = ""
		else
			local names = {}
			for _, thisFilter in ipairs(master.filters) do
				if thisFilter.visible then
					table.insert(names, {
						text = thisFilter.name,
					background = colors.black,
					foreground = colors.white
					})
				end
			end
			if(#names > r.dropdownHeight) then
				table.insert(names, {
					text = "",
					background = colors.black,
					foreground = colors.white,
					separator = true
				}) --Dropdown scroll bug
			end
			
			element:setItems(names)
			
			element.text = self.container.allocation
			for _,v in pairs(element._values.items) do
				if(v.text == element.text) then
					v.selected = true
					break
				end
			end
			
		end
	end)
	
	r.update()
	
	return r
end

function UI_ContainerEditor:initSnapshot(container)
	local r = container:addTable({
		width = container.width - 2,
		height = container.height - self.ui_filter.y - 1,
		x = 2,
		y = self.ui_filter.y + 1,
		background = colors.lightGray,
		foreground = colors.black,
		selectedBackground = colors.lightGray,
		selectedForeground = colors.black,
		scrollBarColor = colors.white,
		scrollBarBackgroundColor = colors.gray,
        columns = {{"", width = 4}, {name = "Name", width = container.width - 8}, {name = "#", width = 3}},
		name = "table",
		visible = self.container.type == "storage" and not master.model.missing[self.container.name]
	})
	
	r:onRowSelect(function(element, rowIndex, row)
		if element.hiddenData[rowIndex] ~= "" then
			ui_stockManager:showItemStats(element.hiddenData[rowIndex], true)
		end
	end)
	
	r.hiddenData = {}
	
	r.update = bindFunctionToInstance(r, function(element)
		if element.visible then
			element:clearData()
			element.hiddenData = {}
			local display = {}
			for index = 1, master.model.sizes[self.container.name] do
				local thisItem = master.model.inventory[self.container.name][index]
				if thisItem or self.ui_allItems.text == "slot" then
					local displayName = ""
					if thisItem then displayName = master.storage[thisItem.uniqueKey].gid.displayName end
					local count = ""
					if thisItem then count = thisItem.count end
					local uniqueKey = ""
					if thisItem then uniqueKey = thisItem.uniqueKey end
					table.insert(display, {index = index, displayName = displayName, count = count, uniqueKey = uniqueKey})
				end
			end
			table.sort(display, function(a,b) return a.index < b.index end)
			for index, thisItem in ipairs(display) do
				if thisItem or self.ui_allItems.text == "slot" then
					element:addRow(thisItem.index, thisItem.displayName, thisItem.count)
					table.insert(element.hiddenData, thisItem.uniqueKey)
				end
			end
		end
	end)
	
	if r.visible then
		r.update()
		
		local titles = container:addLabel({
			width = container.width - 2,
			height = 1,
			x = 2,
			y = r.y,
			z = 10,
			autoSize = false,
			background = colors.orange,
			foreground = colors.black,
			backgroundEnabled = true,
			text = string.rep("\128", 3) .. "Name" .. string.rep(" ", container.width - 14) .. "#\128\128"
		})
	end
	
	return r
end

function UI_ContainerEditor:getChanges()
	local r = {
		type = self.ui_storageType.text,
		filter = nil
	}
	if self.ui_filter.text and self.ui_storageType.text == "storage" then
		r.filter = self.ui_filter.text
	end
	
	return r
end