UI_FilterEditor = {}
UI_FilterEditor.__index = UI_FilterEditor

function UI_FilterEditor:new(filter, container)
	local r = setmetatable({}, self)
	
	changedState = {
		name = filter.name,
		any = filter.any,
		whitelist = filter.whitelist,
		visible = filter.visible,
		filterType = filter.filterType,
		items = deepCopy(filter.items)
	}
	
	r.filter = filter
	r.originalFilterName = filter.name
	r.originalFilterType = filter.filterType
	
	r.foreground = container:addFrame({
        width = termX,
        height = termY - 1,
        x = 1,
        y = 2,
        background = colors.lightGray
    })
		
		r.ui_filterName = r:initFilterName(r.foreground)
		r.ui_ok = r:initOk(r.foreground)
		r.ui_delete = r:initDelete(r.foreground)
		r.ui_filterType = r:initFilterType(r.foreground)
		r.ui_whitelist = r:initWhitelist(r.foreground)
		r.ui_any = r:initAny(r.foreground)
		r.ui_visible = r:initVisible(r.foreground)
		--r.ui_debug = r:initDebug(r.foreground)
		
		r.background = r:initBackground(r.foreground)
			r.ui_addFilter = r:initAddFilter(r.background)
	
	r:loadItems()
	
	return r
end

function UI_FilterEditor:destroy()
	self:clearChildren()
	self.foreground:destroy()
	self.filter = nil
end

function UI_FilterEditor:initFilterName(container)
	local r = container:addInput({
        width = termX - 7,
        height = 1,
        x = 2,
        y = 1,
        background = colors.black,
        foreground = colors.white,
        text = self.filter.name,
        placeholder = "Filter name",
		name = "filterName"
    })
	r:onKeyUp(function(element, key)
		element.text = string.sub(string.gsub(element.text, "|", "-"), 1, 16)
		changedState.name = element.text or ""
		element.foreground = colors.white
		if(ctrlDown and (key == keys.v)) then
			element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
			element.cursorPos = element.cursorPos + #master.clipboard
		end
	end)
	r:listenEvent("paste", false)
	
	return r
end

function UI_FilterEditor:initOk(container)
	local filterName = container:getChild("filterName")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = filterName.x + filterName.width + 1,
        y = 1,
        background = colors.green,
        text = "ok",
		name = "ok"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		if changedState.name == "" then return end
		for _, thisFilter in ipairs(master.filters) do
			if thisFilter.name == changedState.name and changedState.name ~= self.filter.name then
				self.ui_filterName.foreground = colors.red
				return
			end
		end
		changedState.items = {}
		
		for _, thisEntry in pairs(self.background.children) do
			if thisEntry ~= self.ui_addFilter and thisEntry.name == "frame" then
				local insertThis = thisEntry.input.text
				if(changedState.filterType == "item" or changedState.filterType == "attribute") then
					--Trim text to remove whitespaces
					insertThis = insertThis:match("^%s*(.-)%s*$")
				end
				if(changedState.filterType == "mod") then
					insertThis = master.mod_ids[insertThis]
				end
				
				if insertThis and insertThis ~= "" then
					table.insert(changedState.items, insertThis)
				end
			end
		end
		
		if not isHost then
			local newPacket = myTalker:makePacket("send_filterUpdate", {
				filterName = self.filter.name,
				changedState = changedState
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			local newPacket = myTalker:makePacket("broadcast_filterUpdate", {
				filterName = self.filter.name,
				changedState = changedState
			})
			myTalker:broadcastPacket(newPacket)
			
			self.filter:saveChanges(changedState)
			ui_filterManager:rebuildTable()
		end
		
		self:destroy()
	end)
	
	return r
end

function UI_FilterEditor:initDelete(container)
	local ok = container:getChild("ok")
	local r = container:addButton({
        width = 1,
        height = 1,
        x = ok.x + ok.width + 1,
        y = ok.y,
        background = colors.red,
        text = "X",
		name = "delete"
    })
    r:setBackgroundState("clicked", colors.gray)
    r:onClick(function(element)
		if not isHost then
			local newPacket = myTalker:makePacket("send_filterDelete", {
				filterName = self.filter.name
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			local newPacket = myTalker:makePacket("broadcast_filterDelete", {
				filterName = self.filter.name
			})
			myTalker:broadcastPacket(newPacket)
			self.filter:destroy()
		end
		
		self.filter = nil
		self:destroy()
    end)
	
	return r
end

function UI_FilterEditor:initFilterType(container)
	local delete = container:getChild("delete")
	local r = container:addDropDown({
        width = 11,
        height = 1,
        x = 2,
        y = delete.y + 2,
        z = 10,
        background = colors.black,
        foreground = colors.white,
        text = self.filter.filterType,
		name = "filterType"
    })
    r:onSelect(function(element, index)
		local any = element.parent:getChild("any")
        local selectedName = element._values.items[index].text
		changedState.filterType = selectedName
        element.text = selectedName
        if(selectedName == "mod" or selectedName == "item") then
			changedState.any = true
			any.update()
        end
        
		self:clearChildren()
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		element:setItems({
			{
				text = "attribute",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "filter",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "item",
				background = colors.black,
				foreground = colors.white
			},
			{
				text = "mod",
				background = colors.black,
				foreground = colors.white
			}
		})
		
		if(changedState.filterType and changedState.filterType ~= "") then
			element.text = changedState.filterType
			for _,v in pairs(element._values.items) do
				if(v.text == changedState.filterType) then
					v.selected = true
					break
				end
			end
		else
			element.text = "item"
			element._values.items[3].selected = true
		end
	end)
	
	r.update()
	
	return r
end

function UI_FilterEditor:initWhitelist(container)
	local filterType = container:getChild("filterType")
	local delete = container:getChild("delete")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = filterType.x + filterType.width + 1,
        y = delete.y + 2,
        background = colors.white,
        foreground = colors.black,
        text = "WL",
		name = "whitelist"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
        changedState.whitelist = not changedState.whitelist
		element.update()
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		if changedState.whitelist then
			element.text = "WL"
            element.background = colors.white
            element.foreground = colors.black
		else
			element.text = "BL"
            element.background = colors.black
            element.foreground = colors.white
		end
	end)
	
	r.update()
	
	return r
end

function UI_FilterEditor:initAny(container)
	local whitelist = container:getChild("whitelist")
	local r = container:addButton({
        width = 3,
        height = 1,
        x = whitelist.x + whitelist.width + 1,
        y = whitelist.y,
        background = colors.orange,
        text = "any",
		name = "any"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		changedState.any = (not changedState.any or changedState.filterType == "item" or changedState.filterType == "mod")
		element.update()
    end)
	
	r.update = bindFunctionToInstance(r, function(element)
		if changedState.any then
			element.text = "any"
		else
			element.text = "all"
		end
	end)
	
	r.update()
	
	return r
end

function UI_FilterEditor:initVisible(container)
	local any = container:getChild("any")
	local r = container:addButton({
        width = 5,
        height = 1,
        x = any.x + any.width + 1,
        y = any.y,
        background = colors.orange,
        foreground = colors.black,
        text = " vis ",
		name = "visible"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		changedState.visible = not changedState.visible
		element.update()
	end)
	
	r.update = bindFunctionToInstance(r, function(element)
		if changedState.visible then
			element.text = " vis "
		else
			element.text = "invis"
		end
	end)
	
	r.update()
	
	return r
end

function UI_FilterEditor:initDebug(container)
	local r = container:addLabel({
		height = 1,
		x = 1,
		y = 2,
		background = colors.black,
		text = "Debug",
		name = "debug"
	})
	return r
end

function UI_FilterEditor:initBackground(container)
	local visible = container:getChild("visible")
	local r = container:addScrollFrame({
        width = termX - 2,
        height = container.height - 5,
        x = 2,
        y = visible.y + 2,
        background = colors.gray,
        scrollBarColor = colors.white,
        scrollBackgroundColor = colors.lightGray,
        scrollBackgroundColor2 = colors.gray,
		name = "background"
    })
	
	return r
end

function UI_FilterEditor:initAddFilter(container)
	local r = container:addButton({
            width = container.width - 6,
            height = 3,
            x = 4,
            y = 2,
            background = colors.green,
            text = "+",
			name = "add"
        })
		r:setBackgroundState("clicked", colors.gray)
        r:onClick(function(element)
            local newEntry = self:makeEntry(container)
			self:placeEntry(newEntry)
        end)
	
	return r
end

function UI_FilterEditor:makeEntry(container)
	
	local bgColor = colors.lime
	if(changedState.filterType == "mod") then
		bgColor = colors.blue
	elseif(changedState.filterType == "attribute") then
		bgColor = colors.orange
	elseif(changedState.filterType == "filter") then
		bgColor = colors.magenta
	end
	
	local thisEntry = container:addFrame({
		width = container.width,
		height = 2,
		x = 1,
		y = -100,
		z = 5,
		background = bgColor,
		foreground = colors.black,
		name = "frame"
	})
	
	thisEntry.filterType = changedState.filterType
	
	local del = thisEntry:addButton({
		width = 1,
		height = 1,
		x = thisEntry.width - 1,
		y = 2,
		z = 6,
		background = colors.red,
		text = "X",
		name = "del"
	})
	del:setBackgroundState("clicked", colors.gray)
	del:onClick(function(element)
		local currentHeight = element.parent.y
		for _, thisEntry in pairs(element.parent.parent.children) do
			if thisEntry.y >= currentHeight then
				thisEntry.y = thisEntry.y - element.parent.height
			end
		end
		element.parent.input:destroy()
		element.parent:destroy()
	end)
	
	thisEntry:addLabel({
		height = 1,
		x = 1,
		y = 2,
		foreground = colors.black,
		text = string.rep("_", thisEntry.width),
		name = "label"
	})
	
	local input
	--Due to the fact that children cannot render outside of the dimensions of their parent, the inputs cannot be parented to thisEntry, but to the container instead. Otherwise, dropdowns will not have their full selection visible to the user.
	if thisEntry.filterType == "mod" then
		input = container:addDropDown({
			width = thisEntry.width - 2,
			height = 1,
			x = thisEntry.x - 1 + 2,
			y = thisEntry.y - 1 + 1,
			z = 9999 - #container.children,
			background = colors.black,
			foreground = colors.white,
			dropdownHeight = 5,
			name = "input"
		})
		input:onSelect(function(element, index)
			local s = element._values.items[index].text
			element.text = s
		end)
		
		--Populate dropdown
		local mod_names = {}
		for _, v in pairs(master.mods) do
			table.insert(mod_names, {text = v})
		end
		table.sort(mod_names, function(a,b) return string.lower(a.text) < string.lower(b.text) end)
		if(#mod_names > input.dropdownHeight) then
			table.insert(mod_names, {text = "", separator = true}) --Dropdown scroll bug
		end
		input:setItems(mod_names)
		
		local picker = thisEntry:addButton({
			width = 4,
			height = 1,
			x = thisEntry.width - 6,
			y = 2,
			background = colors.cyan,
			foreground = colors.black,
			text = "pick"
		})
		picker:onClick(function(element)
			basalt.schedule(function()
				local pickedItem = UI_Stock:new(element.parent.parent.parent, true)
				input.text = pickedItem.gid.modName
				for index, tab in pairs(input._values.items) do
					tab.selected = false
					if tab.text == pickedItem.gid.modName then
						tab.selected = true
					end
				end
			end)
		end)
			
	elseif thisEntry.filterType == "filter" then
		input = container:addDropDown({
			width = thisEntry.width - 2,
			height = 1,
			x = thisEntry.x - 1 + 2,
			y = thisEntry.y - 1 + 1,
			z = 9999 - #container.children,
			background = colors.black,
			foreground = colors.white,
			dropdownHeight = 5,
			name = "input"
		})
		input:onSelect(function(element, index)
			element.text = element._values.items[index].text
		end)
		--Populate dropdown
		local filter_query = csv.select(config.filters)
		local filter_names = {}
		for _,v in pairs(filter_query) do
			table.insert(filter_names, {text = v["name"]})
		end
		if(#filter_names > input.dropdownHeight) then
			table.insert(filter_names, {text = "", separator = true}) --Dropdown scroll bug
		end
		input:setItems(filter_names)
		
	elseif thisEntry.filterType == "item" then
		input = container:addInput({
			width = thisEntry.width - 2,
			height = 1,
			x = thisEntry.x - 1 + 2,
			y = thisEntry.y - 1 + 1,
			z = 8,
			background = colors.black,
			foreground = colors.white,
			name = "input"
		})
		input:onKeyUp(function(element, key)
			string.gsub(element.text, "|", "-")
			if(ctrlDown and (key == keys.v)) then
				element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
				element.cursorPos = element.cursorPos + #master.clipboard
			end
		end)
		input:listenEvent("paste", false)
		
		local picker = thisEntry:addButton({
			width = 4,
			height = 1,
			x = thisEntry.width - 6,
			y = 2,
			background = colors.cyan,
			foreground = colors.black,
			text = "pick"
		})
		picker:onClick(function(element)
			basalt.schedule(function()
				local pickedItem = UI_Stock:new(element.parent.parent.parent, true)
				input.text = pickedItem.gid.name
			end)
		end)
	else
		input = container:addInput({
			width = thisEntry.width - 2,
			height = 1,
			x = thisEntry.x - 1 + 2,
			y = thisEntry.y - 1 + 1,
			z = 8,
			background = colors.black,
			foreground = colors.white,
			name = "input"
		})
		input:onKeyUp(function(element, key)
			string.gsub(element.text, "|", "-")
			if(ctrlDown and (key == keys.v)) then
				element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
				element.cursorPos = element.cursorPos + #master.clipboard
			end
		end)
		input:listenEvent("paste", false)
    end
	
	thisEntry.input = input
	--table.insert(thisEntry.children, input)
	
	thisEntry.setValue = bindFunctionToInstance(thisEntry, function(element, value)
		value = tostring(value)
		local input = thisEntry.input
		if element.filterType == "mod" or element.filterType == "filter" then
			input.text = value
			if element.filterType == "mod" then
				input.text = master.mods[value]
			end
			for _,v in pairs(input._values.items) do
				if(v.text == input.text) then
					v.selected = true
					break
				end
			end
		else
			input.text = value
		end
	end)
	
	return thisEntry
end

function UI_FilterEditor:clearChildren()
	for _, thisEntry in pairs(self.background.children) do
		if thisEntry ~= self.ui_addFilter then
			if thisEntry.input then
				thisEntry.input:setCursor(-100, -100, true, colors.white)
				thisEntry.input:destroy()
			end
			thisEntry:destroy()
		end
	end
	self.ui_addFilter.y = 2
	self.background.offsetY = 0
end

function UI_FilterEditor:loadItems()
	self:clearChildren()
	
	for _, thisItem in pairs(self.filter.items) do
		local newEntry = self:makeEntry(self.background)
		self:placeEntry(newEntry)
		newEntry.setValue(thisItem)
	end
end

function UI_FilterEditor:placeEntry(entry)
	entry.y = ((#entry.parent.children - 2)/2) * entry.height
	entry.input.y = entry.y
	self.ui_addFilter.y = ((#entry.parent.children)/2) * entry.height + 1
end