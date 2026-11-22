UI_ContainerEditor = {}
UI_ContainerEditor.__index = UI_ContainerEditor

function UI_ContainerEditor:new(container, parentContainer)
	local r = setmetatable({}, self)
	
	r.container = container
	
	r.foreground = parentContainer:addFrame({
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
		r.ui_snapshotLabel = r:initSnapshotLabel(r.foreground)
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
		dropdownHeight = master.numContainerTypes
    })
	r:onSelect(function(element, index)
        element.text = element._values.items[index].text
        self.ui_filter.visible = (master.containerTypes[element.text].storageType)
		self.ui_snapshot.visible = (master.containerTypes[self.container.type].storageType) and (master.containerTypes[element.text].storageType)
		self.ui_snapshotLabel.visible = (master.containerTypes[self.container.type].storageType) and (master.containerTypes[element.text].storageType)
		
		if master.containerTypes[element.text].storageType then
			self.ui_filter.update()
		end
		self.ui_size.updateLabel()
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		local items = {}
		for name, thisContainerType in pairs(master.containerTypes) do
			table.insert(items, {
				text = name,
				background = colors.black,
				foreground = colors.white,
				displayOrder = thisContainerType.displayOrder
			})
		end
		table.sort(items, function(a,b) return a.displayOrder < b.displayOrder end)
		r:setItems(items)
		
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
			if master.containerTypes[changes.type].storageType and not changes.filter then return end
			local containerName = self.container.name
			self:destroy()
			local newPacket = myTalker:makePacket("send_containerEditorSave", {
				containerName = self.container.name,
				changes = changes
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			local changes = self:getChanges()
			if master.containerTypes[changes.type].storageType and not changes.filter then return end
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
	
	r.updateLabel = bindFunctionToInstance(r, function(element)
		if master.containerTypes[self.ui_storageType.text].storageType and master.containerTypes[self.container.type].storageType and not self.container:missing() then
			if not element.button then
				element.button = element.parent:addButton({
					width = element.width,
					height = element.height,
					x = element.x,
					y = element.y,
					z = element.z + 10,
					background = colors.white,
					foreground = colors.black,
					backgroundEnabled = false,
					text = ""
				})
				element.button.slotMode = false
				element.button:onClick(function(element2)
					element2.slotMode = not element2.slotMode
					element.updateLabel()
					element2.width = element.width
				end)
			end
			local slotsFilled = 0
			local itemsFilled = 0
			for _, thisSlot in pairs(master.containers[self.container.name].inventory) do
				slotsFilled = slotsFilled + 1
				itemsFilled = itemsFilled + (thisSlot.count * (64 / master.storage[thisSlot.uniqueKey].gid.maxCount))
			end
			--Check if slot mode or item mode
			local top = element.button.slotMode and slotsFilled or itemsFilled
			local bottom = master.model.sizes[self.container.name] * (element.button.slotMode and 1 or 64)
			local div = bottom == 0 and 0 or (top*100)/bottom
			element.text = tostring(abbreviate(top,4)) .. "/" .. tostring(abbreviate(bottom,4)) .. " (" .. tostring(math.floor(div)) .. "%)"
		else
			element.text = "Size: " .. tostring(master.model.sizes[self.container.name])
			if element.button then
				element.button:destroy()
				element.button = nil
			end
		end
	end)
	
	r.updateLabel()
	
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
		visible = master.containerTypes[self.container.type].storageType and not master.model.missing[self.container.name],
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
		element.visible = (master.containerTypes[self.ui_storageType.text].storageType)
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

function UI_ContainerEditor:initSnapshotLabel(container)
	local r = container:addLabel({
			width = container.width - 2,
			height = 1,
			x = 2,
			y = self.ui_filter.y + 1,
			z = 10,
			autoSize = false,
			background = colors.orange,
			foreground = colors.black,
			backgroundEnabled = true,
			name = "snapshotLabel",
			text = string.rep("\128", 3) .. "Name" .. string.rep(" ", container.width - 14) .. "#\128\128",
			visible = master.containerTypes[self.container.type].storageType
		})
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
		visible = master.containerTypes[self.container.type].storageType and not master.model.missing[self.container.name]
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
	end
	
	return r
end

function UI_ContainerEditor:getChanges()
	local r = {
		type = self.ui_storageType.text,
		filter = nil
	}
	if self.ui_filter.text and master.containerTypes[self.ui_storageType.text].storageType then
		r.filter = self.ui_filter.text
	end
	
	return r
end