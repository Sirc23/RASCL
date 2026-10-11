UI_Stock = {}
UI_Stock.__index = UI_Stock

function UI_Stock:new(container, pickMode)
	local r = setmetatable({}, self)
	r.currentItemStats = nil
	r.pickMode = pickMode or false
	
	r.f_sortName = function(a,b)
		return (a.gid.displayName <= b.gid.displayName)
	end
	
	r.f_sortMod = function(a,b)
		local c = (a.gid.modName ~= b.gid.modName)
		return (a.gid.modName <= b.gid.modName and c)
			or (a.gid.displayName <= b.gid.displayName and not c)
	end
	
	r.f_sortAmount = function(a,b)
		local c = (a.gid.count ~= b.gid.count)
		return (a.gid.count >= b.gid.count and c)
			or (a.gid.displayName <= b.gid.displayName and not c)
	end
	
	r.f_sortAccessed = function(a,b)
		local c = (a.lastAccessed ~= b.lastAccessed)
		return (a.lastAccessed >= b.lastAccessed and c)
			or (a.gid.displayName <= b.gid.displayName and not c)
	end
	
	r.search = ""
	r.loose = true
	r.sort = "amount"
	r.sortFunction = r.f_sortName
	r.sortDescending = true
	r.numItems = 0
	
	r.foreground = container:addFrame({
		width = container.width,
		height = container.height,
		x = 1,
		y = 1,
		background = colors.lightGray
	})
		r.ui_search = r:initSearch(r.foreground)
		r.ui_doSearch = r:initDoSearch(r.foreground)
		r.ui_quickSend = r:initQuickSend(r.foreground)
		r.ui_label = r:initLabel(r.foreground)
		r.ui_sort = r:initSort(r.foreground)
		r.ui_sortDescending = r:initSortDescending(r.foreground)
		r.ui_loose = r:initLoose(r.foreground)
	
		r.background = r:initBackground(r.foreground)
		
		local nothing = r.foreground:addFrame({
			width = 18 + (termX % 2),
			height = 1,
			x = math.ceil(termX/2) - 9 - (termX % 2),
			y = container.height - 1,
			z = 0,
			background = colors.gray
		})
		
		r.ui_currentPage = r:initCurrentPage(r.foreground)
		r.ui_firstPage = r:initFirstPage(r.foreground)
		r.ui_previousPage = r:initPreviousPage(r.foreground)
		r.ui_nextPage = r:initNextPage(r.foreground)
		r.ui_lastPage = r:initLastPage(r.foreground)
	if r.pickMode then
		r.pickedItem = nil
		r:refreshUI()
		while not r.pickedItem do
			os.sleep()
		end
		r.foreground:destroy()
		return r.pickedItem
	else
		return r
	end
end

function UI_Stock:refreshUI()
	if not self.refreshScheduled then
		self.refreshScheduled = true
		basalt.schedule(function()
			os.sleep()
			self:sortUI({}, true)
		end)
	end
end

function UI_Stock:sortUI(changes, forceReordering)
	local resort = forceReordering or false
	if not forceReordering and changes then
		for index, value in pairs(changes) do
			if index == "search" and value ~= self.search then
				self.search = value
				resort = true
				
				if self.search == nil then self.search = "" end
			elseif index == "loose" and value ~= self.loose then
				self.loose = value
				resort = true
				
				if self.loose then self.ui_loose.text = "*"
				else self.ui_loose.text = "=" end
			elseif index == "sort" and value ~= self.sort then
				self.sort = value
				resort = true
				
				for _, element in pairs(self.ui_sort) do
					if element.name == value then
						element.background = colors.lightBlue
						self.sortFunction = element.sortFunction
					else
						element.background = colors.lightGray
					end
				end
				
			elseif index == "sortDescending" and value ~= self.sortDescending then
				self.sortDescending = value
				resort = true
				
				if self.sortDescending then self.ui_sortDescending.text = "\25"
				else self.ui_sortDescending.text = "\24" end
			
			end
		end
	end
	
	if not resort then return end
	
	--self.background.offsetY = 0
	
	local finalSort = function(a,b)
		if self.sortDescending then
			return self.sortFunction(a,b)
		else
			return self.sortFunction(b,a)
		end
	end
	
	local validItems = {}
	
	for _, thisItem in pairs(master.storage) do
		
		local matchesFilter = thisItem:matchesSearch({
			search = self.search,
			loose = self.loose
		})
		
		if matchesFilter and thisItem.gid.count > 0 then
			table.insert(validItems, thisItem)
		end
		if not self.pickMode then
			thisItem:destroyStockUI()
		end
	end
	self.numItems = #validItems
	
	local pageSize = tonumber(config.entries_per_page)
	
	if math.ceil(#validItems / pageSize) < self.ui_currentPage.number() then
		self.ui_currentPage.update(math.ceil(#validItems / pageSize))
	end
	local currentPage = self.ui_currentPage.number()
	
	local minEntry = math.min((currentPage-1) * pageSize + 1, #validItems)
	local maxEntry = math.min(currentPage * pageSize, #validItems)
	
	qs(validItems, 1, #validItems, maxEntry, finalSort)
	qs(validItems, 1, maxEntry, minEntry, finalSort)
	
	local itemSortArray = {}
	for index = minEntry, maxEntry do
		table.insert(itemSortArray, validItems[index])
	end
	
	table.sort(itemSortArray, finalSort)
	
	local i = 1
	local color = colors.orange
	
	for _, thisItem in pairs(itemSortArray) do
		local ui = thisItem:makeUI(self)
		if not self.pickMode then
			thisItem.uiStock = ui
		end
		ui.y = i
		ui.visible = true
		i = i + 2
		
		ui.background = color
		if color == colors.orange then
			color = colors.yellow
		else
			color = colors.orange
		end
		
	end
	if self.refreshScheduled then
		self.refreshScheduled = false
	end
end

function UI_Stock:changePage()
	self:refreshUI()
	self.background.offsetY = 0
end

function UI_Stock:initSearch(container)
	
	local r = container:addInput({
        width = container.width - (toboolean(config.auto_search) and 0 or 3),
        height = 1,
        x = 1,
        y = 1,
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
				os.sleep(0.6)
				if element.lastSearched == currentMoment then
					local s = element.text
					s = string.lower(s)
					element.text = s
					--Trim text to remove whitespaces
					s = s:match("^%s*(.-)%s*$")
					element.text = s
					self:sortUI({search=(s)})
					self.background.offsetY = 0
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

function UI_Stock:initDoSearch(container)
	local ui_search = container:getChild("search")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = self.ui_search.x + self.ui_search.width + 1,
        y = 1,
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

function UI_Stock:initQuickSend(container)
	local ui_search = container:getChild("search")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = container.width - 1,
        y = self.ui_search.y + 1,
        background = colors.green,
        text = "\187\187",
		name = "quickSend",
		visible = not self.pickMode
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
        ui_cartManager.ui_send:fireEvent("mouse_click")
    end)
	return r
end

function UI_Stock:initLabel(container)
	local r = container:addLabel({
        height = 1,
        x = container.width - (2 * #config.max_cart_size) - 4,
        y = self.ui_quickSend.y,
        text = "\04" .. "0/" .. tostring(config.max_cart_size),
		name = "label",
		visible = not self.pickMode
    })
	r.update = bindFunctionToInstance(r, function(element)
        local padding = "%-" .. tostring(#config.max_cart_size) .. "s"
        local t = "\04" .. string.format(padding, tostring(tonumber(config.max_cart_size) - cartItemsLeft)) .. "/" .. string.format(padding, tostring(config.max_cart_size))
        element.text = t
	end)
	r.update()
	return r
end

function UI_Stock:initSort(container)
	local r = {}
	
	--local label = container:getChild("label")
	
	local f = function(element)
		self:sortUI({sort=element.name})
	end
	
	local b = container:addButton({
		width = 1,
        height = 1,
        x = 1,
        y = self.ui_quickSend.y,
        background = colors.lightBlue,
        text = "n",
		name = "name"
	})
	:setBackgroundState("clicked", colors.gray)
	
	b.sortFunction = self.f_sortName
	b.doSort = bindFunctionToInstance(b, f)
	b:onClick(f)
	table.insert(r, b)
	
	b = container:addButton({
		width = 1,
        height = 1,
        x = b.x + 1,
        y = self.ui_quickSend.y,
        background = colors.lightGray,
        text = "m",
		name = "mod"
	})
	:setBackgroundState("clicked", colors.gray)
	b.sortFunction = self.f_sortMod
	b.doSort = bindFunctionToInstance(b, f)
	b:onClick(f)
	table.insert(r, b)
	
	b = container:addButton({
		width = 1,
        height = 1,
        x = b.x + 1,
        y = self.ui_quickSend.y,
        background = colors.lightGray,
        text = "#",
		name = "amount"
	})
	:setBackgroundState("clicked", colors.gray)
	b.sortFunction = self.f_sortAmount
	b.doSort = bindFunctionToInstance(b, f)
	b:onClick(f)
	table.insert(r, b)
	
	b = container:addButton({
		width = 1,
        height = 1,
        x = b.x + 1,
        y = self.ui_quickSend.y,
        background = colors.lightGray,
        text = "a",
		name = "accessed"
	})
	:setBackgroundState("clicked", colors.gray)
	b.sortFunction = self.f_sortAccessed
	b.doSort = bindFunctionToInstance(b, f)
	b:onClick(f)
	table.insert(r, b)
	
	local preferredSortName = config.preferred_sort
	if(searchTable({"name", "mod", "amount", "accessed"}, preferredSortName) ~= -1) then
		for _, element in pairs(r) do
			if element.name == preferredSortName then
				element.background = colors.lightBlue
				self.sortFunction = element.sortFunction
			else
				element.background = colors.lightGray
			end
		end
	end
	
	return r
end

function UI_Stock:initSortDescending(container)
	local r = container:addButton({
        width = 1,
        height = 1,
        x = self.ui_sort[#self.ui_sort].x + 1,
        y = self.ui_quickSend.y,
        background = colors.orange,
        text = "\25", --Down arrow,
		name = "descending"
    })
	r:setBackgroundState("clicked", colors.gray)
    r:onClick(function(element)
        self:sortUI({sortDescending=(not self.sortDescending)})
    end)
	
	return r
end

function UI_Stock:initLoose(container)
	local ui_descending = container:getChild("descending")
	local r = container:addButton({
        width = 1,
        height = 1,
        x = ui_descending.x + ui_descending.width + 1,
        y = self.ui_quickSend.y,
        background = colors.orange,
        text = "*",
		name = "loose"
    })
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		self:sortUI({loose=(not self.loose)})
    end)
	return r
end

function UI_Stock:initBackground(container)
	local r = container:addScrollFrame({
		width = container.width,
        height = container.height - 5,
        x = 1,
        y = self.ui_quickSend.y + 2,
        background = colors.gray,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.lightGray,
        scrollBarBackgroundColor2 = colors.gray,
		name = "background"
	})
	return r
end

function UI_Stock:initCurrentPage(container)
	local r = container:addLabel({
		width = 2 + (termX % 2),
		height = 1,
		autoSize = false,
		x = math.floor(termX / 2) - container.x,
		y = container.height - 1,
		z = 2,
		background = colors.black,
		backgroundEnabled = true,
		foreground = colors.white,
		text = string.rep("\128", 1 + (termX % 2)) .. "1"
	})
	r.lastScrolled = math.floor(os.epoch("utc")/50)
	r:onScroll(function(element, direction)
		self.ui_currentPage.update(self.ui_currentPage.number() - direction)
		local currentMoment = math.floor(os.epoch("utc")/50)
		element.lastScrolled = currentMoment
		basalt.schedule(function()
			os.sleep(0.6)
			if element.lastScrolled == currentMoment then
				--Change page
				self:changePage()
			end
		end)
    end)
	
	r.update = bindFunctionToInstance(r, function(element, newValue)
		local t = newValue or 1
		--Clamp number to bounds
        t = math.max(1, t)
        t = math.min(math.max(1, math.ceil(self.numItems / tonumber(config.entries_per_page))), t)
		
		element.text = string.rep("\128", math.max(element.width - #tostring(t), 0)) .. tostring(t)
	end)
	
	r.number = bindFunctionToInstance(r, function(element)
		local t = string.gsub(element.text, "\128", "")
		return tonumber(t)
	end)
	
	return r
end

function UI_Stock:initFirstPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_currentPage.x - 6,
		y = self.ui_currentPage.y,
		z = 2,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\171\171"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_currentPage.update(1)
		self:changePage()
	end)
	
	return r
end

function UI_Stock:initPreviousPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_currentPage.x - 3,
		y = self.ui_currentPage.y,
		z = 2,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\17-"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_currentPage.update(self.ui_currentPage.number() - 1)
		self:changePage()
	end)
	
	return r
end

function UI_Stock:initNextPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_currentPage.x + self.ui_currentPage.width + 1,
		y = self.ui_currentPage.y,
		z = 2,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "-\16"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_currentPage.update(self.ui_currentPage.number() + 1)
		self:changePage()
	end)
	
	return r
end

function UI_Stock:initLastPage(container)
	local r = container:addButton({
		width = 2,
		height = 1,
		x = self.ui_currentPage.x + self.ui_currentPage.width + 4,
		y = self.ui_currentPage.y,
		z = 2,
		background = colors.lightBlue,
		foreground = colors.black,
		text = "\187\187"
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClickUp(function(element)
		self.ui_currentPage.update(math.ceil(self.numItems / tonumber(config.entries_per_page)))
		self:changePage()
	end)
	
	return r
end

function UI_Stock:showItemStats(uniqueKey, redirect)
	if master.storage[uniqueKey] then
		if self.currentItemStats then
			self.currentItemStats.destroyStuff()
			self.currentItemStats = nil
		end
		self.currentItemStats = self:makeItemStat(uniqueKey)
		if redirect then
			local navMenu = basalt.getMainFrame():getChild("navigationMenu")
			navMenu:fireEvent("node_select", master.menuNodes[1])
			master.ui_items:getChild("tabs"):setActiveTab(1)
		end
	end
end

function UI_Stock:makeItemStat(uniqueKey)
	local r = self.foreground.parent.parent.parent:addFrame({
		width = self.foreground.width - 2,
		height = self.foreground.height - 1,
		x = 2,
		y = 1,
		z = 600,
        background = colors.gray
	})
	
	r.destroyStuff = bindFunctionToInstance(r, function(element)
		element:destroy()
		element.bandaid:destroy()
	end)
	
	r:addBorder({
		color = colors.yellow,
		top = true,
		left = true,
		right = true,
		bottom = true
	})
	local bandaid = self.foreground.parent.parent.parent:addFrame({
		width = 1,
		height = 1,
		x = 1,
		y = 1,
		z = 600,
		background = colors.lightGray
	})
	r.bandaid = bandaid
	
	local label = r:addLabel({
        height = 1,
        x = 1,
        y = 1,
		text = " " .. master.storage[uniqueKey].gid.displayName .. " ",
        foreground = colors.black,
		background = colors.yellow,
		backgroundEnabled = true
    })
	
	local ok = r:addButton({
		width = 2,
		height = 1,
		x = r.width - 2,
		y = 2,
		background = colors.green,
		foreground = colors.black,
		text = "ok"
	})
	ok:onClick(function(element)
		r.destroyStuff()
		self.currentItemStats = nil
	end)
	
	local tags = r:addButton({
		width = 4,
		height = 1,
		x = ok.x - 5,
		y = ok.y,
		background = colors.blue,
		foreground = colors.black,
		text = "tags"
	})
	tags:setBackgroundState("clicked", colors.gray)
	tags:onClick(function(element)
		if not r:getChild("tags") then
			local tagTable = r:addTable({
				width = r:getChild("table").width,
				height = r:getChild("table").height,
				x = r:getChild("table").x,
				y = r:getChild("table").y,
				background = colors.lightGray,
				foreground = colors.black,
				selectedBackground = colors.lightGray,
				selectedForeground = colors.black,
				scrollBarColor = colors.white,
				scrollBarBackgroundColor = colors.gray,
				columns = {{"Tags", width = 999}},
				name = "tags"
			})
			
			for _, tag in pairs(master.storage[uniqueKey].gid.tags) do
				tagTable:addRow(tag)
			end
			
			tagTable:onRowSelect(function(element, rowIndex, row)
				master:copyToClipboard(row._data.cells[1])
			end)
			
			r:addLabel({
				width = r:getChild("title").width,
				height = r:getChild("title").height,
				x = r:getChild("title").x,
				y = r:getChild("title").y,
				z = 10,
			background = colors.orange,
			foreground = colors.black,
			backgroundEnabled = true,
			text = "Tags",
			name = "tagsTitle"
			})
		else
			r:getChild("tags"):destroy()
			r:getChild("tagsTitle"):destroy()
		end
    end)
	
	local total = r:addLabel({
		width = tags.x - 2,
		height = 1,
		x = 2,
		y = ok.y,
		autoSize = false,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Total: " .. tostring(master.storage[uniqueKey].gid.count)
	})
	
	local mod = r:addButton({
		width = r.width - 2,
		height = 1,
		x = 2,
		y = total.y + 1,
		autoSize = false,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Mod: " .. master.storage[uniqueKey].gid.modID .. string.rep("\128", r.width - 7 - #master.storage[uniqueKey].gid.modID)
	})
	mod:onClick(function(element)
		master:copyToClipboard(master.storage[uniqueKey].gid.modID)
	end)
	
	local name = r:addButton({
		width = r.width - 2,
		height = 1,
		x = 2,
		y = mod.y + 1,
		autoSize = false,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "ID : " .. master.storage[uniqueKey].gid.nameNoMod .. string.rep("\128", r.width - 7 - #master.storage[uniqueKey].gid.nameNoMod)
	})
	name:onClick(function(element)
		master:copyToClipboard(master.storage[uniqueKey].gid.nameNoMod)
	end)
	
	local nbt = r:addButton({
		width = r.width - 2,
		height = 1,
		x = 2,
		y = name.y + 1,
		autoSize = false,
		background = colors.lightGray,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "NBT: " .. master.storage[uniqueKey].gid.nbt .. string.rep("\128", r.width - 7 - #master.storage[uniqueKey].gid.nbt)
	})
	nbt:onClick(function(element)
		master:copyToClipboard(master.storage[uniqueKey].gid.nbt)
	end)
	
	local title = r:addLabel({
		width = r.width - 2,
		height = 1,
		x = 2,
		y = nbt.y + 2,
		z = 10,
		background = colors.orange,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Container" .. string.rep("\128", r.width - 6 - 10) .. "#",
		name = "title"
	})
	
	local snapshot = r:addTable({
		width = r.width - 2,
		height = r.height - title.y,
		x = 2,
		y = title.y,
		background = colors.lightGray,
		foreground = colors.black,
		selectedBackground = colors.lightGray,
		selectedForeground = colors.black,
		scrollBarColor = colors.white,
		scrollBarBackgroundColor = colors.gray,
        columns = {{"Container", width = r.width - 6}, {name = "#", width = 5}},
		name = "table"
	})
	
	snapshot.hiddenData = {}
	
	snapshot:onRowSelect(function(element, rowIndex, row)
		local containerName = element.hiddenData[rowIndex]
		if master.containers[containerName] then
			local navMenu = basalt.getMainFrame():getChild("navigationMenu")
			navMenu:fireEvent("node_select", master.menuNodes[3])
			if ui_containerManager.currentEditor then
				ui_containerManager.currentEditor:destroy()
			end
			ui_containerManager.currentEditor = UI_ContainerEditor:new(master.containers[containerName], ui_containerManager.foreground)
		end
	end)
	
	for thisContainerName, slots in pairs(master.storage[uniqueKey].gid.containers) do
		local amount = 0
		for _, thisSlot in pairs(slots) do
			amount = amount + master.model.inventory[thisContainerName][thisSlot].count
		end
		snapshot:addRow(master.containers[thisContainerName].displayName, amount)
		table.insert(snapshot.hiddenData, thisContainerName)
	end
	
	snapshot:sortByColumn(1)
	
	return r
end