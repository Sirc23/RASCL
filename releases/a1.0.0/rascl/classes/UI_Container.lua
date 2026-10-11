UI_Container = {}
UI_Container.__index = UI_Container

function UI_Container:new(container)
	local r = setmetatable({}, self)
	
	r.currentEditor = nil
	
	r.foreground = container:addFrame({
        width = termX,
        height = termY,
        x = 1,
        y = 1,
        background = colors.lightGray,
		name = "Containers"
    })
	
		r.ui_search = r:initSearch(r.foreground)
		r.ui_doSearch = r:initDoSearch(r.foreground)
		r.ui_update = r:initUpdate(r.foreground)
		r.ui_cull = r:initCull(r.foreground)
		r.ui_subtab = r.foreground:addTabControl({
			width = r.foreground.width - 2,
			height = termY - r.ui_update.height - 3,
			x = 2,
			y = r.ui_update.y + r.ui_update.height + 1,
			headerBackground = colors.lightGray,
			activeTabBackground = colors.yellow,
			background = colors.lightGray,
			scrollableTab = true
		})
			local activeTab = r.ui_subtab:newTab("Active")
			r.ui_activeTab = activeTab:addScrollFrame({
				width = r.foreground.width - 2,
				height = r.ui_subtab.height - 3,
				x = 1,
				y = 1,
				background = colors.gray,
				showScrollBar = true,
				scrollBarColor = colors.white,
				scrollBarBackgroundColor = colors.lightGray,
				scrollBarBackgroundColor2 = colors.gray,
			})
			
			local nothingActive = activeTab:addFrame({
				width = 18 + (termX % 2),
				height = 1,
				x = math.ceil(termX/2) - 8 - (termX % 2)  - r.ui_subtab.x + 1,
				y = container.height - 5,
				z = -2,
				background = colors.gray
			})
			
			local inactiveTab = r.ui_subtab:newTab("Inactive")
			r.ui_inactiveTab = inactiveTab:addScrollFrame({
				width = r.foreground.width - 2,
				height = r.ui_subtab.height - 3,
				x = 1,
				y = 1,
				background = colors.gray,
				showScrollBar = true,
				scrollBarColor = colors.white,
				scrollBarBackgroundColor = colors.lightGray,
				scrollBarBackgroundColor2 = colors.gray
			})
			
			local nothingInactive = inactiveTab:addFrame({
				width = 18 + (termX % 2),
				height = 1,
				x = math.ceil(termX/2) - 8 - (termX % 2)  - r.ui_subtab.x + 1,
				y = container.height - 5,
				z = -20,
				background = colors.gray
			})
		
		
		r.ui_activeCurrentPage = r:initActiveCurrentPage(activeTab)
		r.ui_activeFirstPage = r:initActiveFirstPage(activeTab)
		r.ui_activePreviousPage = r:initActivePreviousPage(activeTab)
		r.ui_activeNextPage = r:initActiveNextPage(activeTab)
		r.ui_activeLastPage = r:initActiveLastPage(activeTab)
		
		r.ui_inactiveCurrentPage = r:initInactiveCurrentPage(inactiveTab)
		r.ui_inactiveFirstPage = r:initInactiveFirstPage(inactiveTab)
		r.ui_inactivePreviousPage = r:initInactivePreviousPage(inactiveTab)
		r.ui_inactiveNextPage = r:initInactiveNextPage(inactiveTab)
		r.ui_inactiveLastPage = r:initInactiveLastPage(inactiveTab)
	
	r:update(r.ui_activeTab, r.ui_inactiveTab)
	
	return r
end

function UI_Container:initSearch(container)
	local r = container:addInput({
        width = container.width - (toboolean(config.auto_search) and 2 or 5),
        height = 1,
        x = 2,
        y = 2,
        background = colors.black,
        foreground = colors.white,
        placeholder = "Search",
		name = "search"
    })
	r.lastSearched = math.floor(os.epoch("utc")/50)
	r.validate = bindFunctionToInstance(r, function(element, doSearch)
		if doSearch then
			local currentMoment = math.floor(os.epoch("utc")/50)
			element.lastSearched = currentMoment
			basalt.schedule(function()
				local s = element.text
				s = string.lower(s)
				element.text = s
				os.sleep(0.6)
				if element.lastSearched == currentMoment then
					--Trim text to remove whitespaces
					s = s:match("^%s*(.-)%s*$")
					element.text = s
					self:scheduleUpdate()
				end
			end)
		end
	end)
	
	
	r:onKeyUp(function(element, key)
		if ((shiftDown or ctrlDown) and (key == keys.backspace)) or (ctrlDown and (key == keys.a)) then
			element.text = ""
		elseif(ctrlDown and (key == keys.v)) then
			element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
			element.cursorPos = element.cursorPos + #master.clipboard
		end
		element.validate((toboolean(config.auto_search) and true or (key == keys.enter)))
		
    end)
	r:listenEvent("paste", false)
	
	r:onBlur(function(element)
		element.validate(true)
	end)
	
	return r
end

function UI_Container:initDoSearch(container)
	local ui_search = container:getChild("search")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = termX - 2,
        y = 2,
        background = colors.blue,
        text = "go",
		name = "doSearch",
		visible = not toboolean(config.auto_search)
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		ui_search:fireEvent("onKey", keys.enter)
    end)
	return r
end

function UI_Container:initUpdate(container)
	local r = container:addButton({
        width = 7,
        height = 1,
        x = 2,
        y = 3,
		background = colors.blue,
        text = "Recount",
		name = "update"
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		if not isHost then
			local newPacket = myTalker:makePacket("send_containerInitUpdate", {})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			element.runButton(element)
        end
    end)
	r.runButton = function(element)
		self.ui_activeTab:clear()
		self.ui_inactiveTab:clear()
		
		basalt.schedule(function() master:defineContainers(master.ui_mainMenu) end)
	end
	
	return r
end

function UI_Container:initCull(container)
	local r = container:addButton({
		width = 4,
        height = 1,
        x = termX - 4,
        y = 3,
		background = colors.red,
        text = "Cull",
		name = "cull"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		if not isHost then
			local newPacket = myTalker:makePacket("send_containerInitCull", {})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			element.runButton(element)
			local newPacket = myTalker:makePacket("broadcast_containerInitCull", {})
			myTalker:broadcastPacket(newPacket)
        end
    end)
	r.runButton = function(element)
		for index, thisContainer in pairs(master.containers) do
			if thisContainer:missing() then
				csv.delete(config.containers, function(row)
					return row["name"] == thisContainer.name
				end)
				thisContainer:destroy()
			end
		end
		self:update()
	end
	
	return r
end

function UI_Container:scheduleUpdate()
	if not self.updateScheduled then
		self.updateScheduled = true
		basalt.schedule(function()
			os.sleep()
			self:update()
			self.updateScheduled = false
		end)
	end
end

function UI_Container:update(activeTab, inactiveTab)
	local ui_activeTab = activeTab or self.ui_activeTab
	local ui_inactiveTab = inactiveTab or self.ui_inactiveTab
	
	ui_activeTab:clear()
	ui_inactiveTab:clear()
	self.numActiveItems = 0
	self.numInactiveItems = 0
	
	ui_activeTab.offsetY = 0
	ui_inactiveTab.offsetY = 0
	
	local active_offset = 1
	local inactive_offset = 1
	local activeList = {}
	local inactiveList = {}
	
	local sortFunction = function(a,b)
		local c = (a.container ~= b.container)
		return (a.container < b.container and c)
			or (a.number < b.number and not c)
	end
	
	for _, container in pairs(master.containers) do
		local isActive = (not container:missing()) and
			((container.type == "storage" and container.allocation and container.allocation ~= "") or
			  (container.type == "input") or
			  (container.type == "output") or
			  (container.type == "crafting-input") or
			  (container.type == "crafting-output")
			)
		local isValid = string.find(string.lower(container.displayName), (self.ui_search.text or ""), 1, true) ~= nil
		isValid = isValid or (container.type == "storage" and string.find(string.lower(container.filter.name), (self.ui_search.text or ""), 1, true) ~= nil)
			
		if isActive and isValid then
			table.insert(activeList, container)
			self.numActiveItems = self.numActiveItems + 1
		elseif isValid then
			table.insert(inactiveList, container)
			self.numInactiveItems = self.numInactiveItems + 1
		end
	end
	
	local pageSize = tonumber(config.entries_per_page)
	
	if math.ceil(#activeList / pageSize) < self.ui_activeCurrentPage.number() then
		self.ui_activeCurrentPage.update(math.ceil(#activeList / pageSize))
	end
	if math.ceil(#inactiveList / pageSize) < self.ui_inactiveCurrentPage.number() then
		self.ui_inactiveCurrentPage.update(math.ceil(#inactiveList / pageSize))
	end
	
	local currentActivePage = self.ui_activeCurrentPage.number()
	local currentInactivePage = self.ui_inactiveCurrentPage.number()
	
	local minActiveEntry = math.min((currentActivePage-1) * pageSize + 1, #activeList)
	local maxActiveEntry = math.min(currentActivePage * pageSize, #activeList)
	local minInactiveEntry = math.min((currentInactivePage-1) * pageSize + 1, #inactiveList)
	local maxInactiveEntry = math.min(currentInactivePage * pageSize, #inactiveList)
	
	qs(activeList, 1, #activeList, maxActiveEntry, sortFunction)
	qs(activeList, 1, maxActiveEntry, minActiveEntry, sortFunction)
	qs(inactiveList, 1, #inactiveList, maxInactiveEntry, sortFunction)
	qs(inactiveList, 1, maxInactiveEntry, minInactiveEntry, sortFunction)
	
	local finalActiveList = {}
	local finalInactiveList = {}
	
	for index = minActiveEntry, maxActiveEntry do
		table.insert(finalActiveList, activeList[index])
	end
	for index = minInactiveEntry, maxInactiveEntry do
		table.insert(finalInactiveList, inactiveList[index])
	end
	
	table.sort(finalActiveList, sortFunction)
	table.sort(finalInactiveList, sortFunction)
	
	
	for _, container in pairs(finalActiveList) do
		local newButton = self:makeUI(container, ui_activeTab)
		newButton.y = active_offset
		
		if container.type == "storage" or container.type == "input" or container.type == "output" then
			if newButton.y % 4 == 1 then
				newButton.background = colors.lime
			else
				newButton.background = colors.green
			end
		else
			if newButton.y % 4 == 1 then
				newButton.background = colors.yellow
			else
				newButton.background = colors.orange
			end
		end
		active_offset = active_offset + 2
	end
	for _, container in pairs(finalInactiveList) do
		local newButton = self:makeUI(container, ui_inactiveTab)
		newButton.y = inactive_offset
		inactive_offset = inactive_offset + 2
	end
end


function UI_Container:makeUI(containerObject, parentContainer)
	local r = parentContainer:addFrame({
        width = parentContainer.width,
        height = 2,
        x = 1,
        y = -100,
        background = colors.green,
        name = containerObject.displayName,
    })
	
	r.update = bindFunctionToInstance(r, function(element)
		local topLabel = r:getChild("topLabel")
		topLabel.update()
		local bottomLabel = r:getChild("bottomLabel")
		bottomLabel.update()
		if startsWith(bottomLabel.text, "detached") then
			element.background = colors.red
		elseif startsWith(bottomLabel.text, "unassigned") then
			element.background = colors.purple
		elseif containerObject.type == "ignore" then
			element.background = colors.blue
		else
			element.background = colors.green
		end
	end)
	
	r.container = containerObject
	
	local topLabel = r:addLabel({
        width = r.width,
        height = 1,
        x = 1,
        y = 1,
        backgroundEnabled = false,
        foreground = colors.black,
		name = "topLabel"
    })
	
	local bottomLabel = r:addLabel({
        width = r.width,
        height = 1,
        x = 1,
        y = 2,
        backgroundEnabled = false,
        foreground = colors.black,
        name = "bottomLabel"
    })
	
	local button = r:addButton({
		width = r.width - 1,
		height = 2,
		x = 1,
		z = 5,
		text = "",
		backgroundEnabled = false
	})
	
	button:setBackgroundState("clicked", colors.lightGray)
	button:onClick(function(element)
		if self.currentEditor then
			self.currentEditor:destroy()
		end
		self.currentEditor = UI_ContainerEditor:new(element.parent.container, self.foreground)
	end)
	
	topLabel.update = bindFunctionToInstance(topLabel, function(element)
		local t = element.parent.name
		--Create top delimiter
        t = t .. string.rep("\175", element.width - #t)
        element.text = t
	end)
	
	bottomLabel.update = bindFunctionToInstance(bottomLabel, function(element)
		local t = element.parent.container.allocation
		if element.parent.container:missing() then
			t = "detached"
		elseif (not element.parent.container.allocation or element.parent.container.allocation == "") and element.parent.container.type == "storage" then
			t = "unassigned"
		elseif (element.parent.container.type == "input" or element.parent.container.type == "output") then
			t = "*> " .. element.parent.container.type
		elseif (element.parent.container.type ~= "storage") then
			t = "*> " .. element.parent.container.type
		end
		--Create bottom delimiter
        t = t .. string.rep("_", element.width - #t)
        element.text = t
	end)
	
	r.update()
	
	return r
end


function UI_Container:initActiveCurrentPage(container)
	local r = container:addLabel({
		width = 2 + (termX % 2),
		height = 1,
		autoSize = false,
		x = math.floor(termX / 2) - container.x + 1,
		y = container.height - 2,
		background = colors.black,
		backgroundEnabled = true,
		foreground = colors.white,
		text = string.rep("\128", 1 + (termX % 2)) .. "1"
	})
	r.lastScrolled = math.floor(os.epoch("utc")/50)
	r:onScroll(function(element, direction)
		self.ui_activeCurrentPage.update(self.ui_activeCurrentPage.number() - direction)
		local currentMoment = math.floor(os.epoch("utc")/50)
		element.lastScrolled = currentMoment
		basalt.schedule(function()
			os.sleep(0.6)
			if element.lastScrolled == currentMoment then
				--Change page
				self:changeActivePage()
			end
		end)
    end)
	
	r.update = bindFunctionToInstance(r, function(element, newValue)
		local t = newValue or 1
		--Clamp number to bounds
        t = math.max(1, t)
        t = math.min(math.max(1, math.ceil(self.numActiveItems / tonumber(config.entries_per_page))), t)
		
		element.text = string.rep("\128", math.max(element.width - #tostring(t), 0)) .. tostring(t)
	end)
	
	r.number = bindFunctionToInstance(r, function(element)
		local t = string.gsub(element.text, "\128", "")
		return tonumber(t)
	end)
	
	return r
end

function UI_Container:initActiveFirstPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_activeCurrentPage.x - 6,
		y = self.ui_activeCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\171\171"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_activeCurrentPage.update(1)
		self:changeActivePage()
	end)
	
	return r
end

function UI_Container:initActivePreviousPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_activeCurrentPage.x - 3,
		y = self.ui_activeCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\17-"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_activeCurrentPage.update(self.ui_activeCurrentPage.number() - 1)
		self:changeActivePage()
	end)
	
	return r
end

function UI_Container:initActiveNextPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_activeCurrentPage.x + self.ui_activeCurrentPage.width + 1,
		y = self.ui_activeCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "-\16"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_activeCurrentPage.update(self.ui_activeCurrentPage.number() + 1)
		self:changeActivePage()
	end)
	
	return r
end

function UI_Container:initActiveLastPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_activeCurrentPage.x + self.ui_activeCurrentPage.width + 4,
		y = self.ui_activeCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\187\187"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_activeCurrentPage.update(math.ceil(self.numItems / tonumber(config.entries_per_page)))
		self:changeActivePage()
	end)
	
	return r
end



function UI_Container:initInactiveCurrentPage(container)
	local r = container:addLabel({
		width = 2 + (termX % 2),
		height = 1,
		autoSize = false,
		x = math.floor(termX / 2) - container.x + 1,
		y = container.height - 2,
		background = colors.black,
		backgroundEnabled = true,
		foreground = colors.white,
		text = string.rep("\128", 1 + (termX % 2)) .. "1"
	})
	r.lastScrolled = math.floor(os.epoch("utc")/50)
	r:onScroll(function(element, direction)
		self.ui_inactiveCurrentPage.update(self.ui_inactiveCurrentPage.number() - direction)
		local currentMoment = math.floor(os.epoch("utc")/50)
		element.lastScrolled = currentMoment
		basalt.schedule(function()
			os.sleep(0.6)
			if element.lastScrolled == currentMoment then
				--Change page
				self:changeActivePage()
			end
		end)
    end)
	
	r.update = bindFunctionToInstance(r, function(element, newValue)
		local t = newValue or 1
		--Clamp number to bounds
        t = math.max(1, t)
        t = math.min(math.max(1, math.ceil(self.numInactiveItems / tonumber(config.entries_per_page))), t)
		
		element.text = string.rep("\128", math.max(element.width - #tostring(t), 0)) .. tostring(t)
	end)
	
	r.number = bindFunctionToInstance(r, function(element)
		local t = string.gsub(element.text, "\128", "")
		return tonumber(t)
	end)
	
	return r
end

function UI_Container:initInactiveFirstPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_inactiveCurrentPage.x - 6,
		y = self.ui_inactiveCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\171\171"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_inactiveCurrentPage.update(1)
		self:changeInactivePage()
	end)
	
	return r
end

function UI_Container:initInactivePreviousPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_inactiveCurrentPage.x - 3,
		y = self.ui_inactiveCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\17-"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_inactiveCurrentPage.update(self.ui_inactiveCurrentPage.number() - 1)
		self:changeInactivePage()
	end)
	
	return r
end

function UI_Container:initInactiveNextPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_inactiveCurrentPage.x + self.ui_inactiveCurrentPage.width + 1,
		y = self.ui_inactiveCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "-\16"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_inactiveCurrentPage.update(self.ui_inactiveCurrentPage.number() + 1)
		self:changeInactivePage()
	end)
	
	return r
end

function UI_Container:initInactiveLastPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_inactiveCurrentPage.x + self.ui_inactiveCurrentPage.width + 4,
		y = self.ui_inactiveCurrentPage.y,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\187\187"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_inactiveCurrentPage.update(math.ceil(self.numItems / tonumber(config.entries_per_page)))
		self:changeInactivePage()
	end)
	
	return r
end

function UI_Container:changeActivePage()
	self:scheduleUpdate()
end

function UI_Container:changeInactivePage()
	self:scheduleUpdate()
end