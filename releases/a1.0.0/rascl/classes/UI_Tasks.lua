UI_Tasks = {}
UI_Tasks.__index = UI_Tasks

function UI_Tasks:new(container)
	local r = setmetatable({}, self)
	r.currentItemStats = nil
	
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

function UI_Tasks:refreshUI()
	if not self.refreshScheduled then
		self.refreshScheduled = true
		basalt.schedule(function()
			os.sleep()
			self:sortUI()
		end)
	end
end

function UI_Tasks:sortUI()
	
	
	--self.background.offsetY = 0
	
	local finalSort = function(a,b)
		if self.sortDescending then
			return self.sortFunction(a,b)
		else
			return self.sortFunction(b,a)
		end
	end
	
	local validRecipes = {}
	
	for _, thisRecipe in pairs(config.recipes) do
		
		local matchesFilter = thisItem:matchesSearch({
			search = self.search,
			loose = self.loose
		})
		
		if matchesFilter then
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

function UI_Tasks:changePage()
	self:refreshUI()
	self.background.offsetY = 0
end

function UI_Tasks:initSearch(container)
	
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

function UI_Tasks:initDoSearch(container)
	local ui_search = container:getChild("search")
	local r = container:addButton({
        width = 2,
        height = 1,
        x = self.ui_search.x + self.ui_search.width,
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

function UI_Tasks:initLabel(container)
	local r = container:addLabel({
        height = 1,
        x = container.width - (3) - 6,
        y = self.ui_search.y + 1,
        text = "Tasks: 0  ",
		name = "label"
    })
	r.update = bindFunctionToInstance(r, function(element)
        local padding = "%-" .. tostring(3) .. "s"
        local t = "Tasks: " .. string.format(padding, tostring(0))
        element.text = t
	end)
	r.update()
	return r
end

function UI_Tasks:initSort(container)
	local r = {}
	
	--local label = container:getChild("label")
	
	local f = function(element)
		self:sortUI({sort=element.name})
	end
	
	local b = container:addButton({
		width = 1,
        height = 1,
        x = 1,
        y = self.ui_label.y,
        background = colors.lightBlue,
        text = "n",
		name = "name"
	})
	:setBackgroundState("clicked", colors.gray)
	
	b.sortFunction = self.f_sortName
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

function UI_Tasks:initSortDescending(container)
	local r = container:addButton({
        width = 1,
        height = 1,
        x = self.ui_sort[#self.ui_sort].x + 1,
        y = self.ui_label.y,
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

function UI_Tasks:initLoose(container)
	local ui_descending = container:getChild("descending")
	local r = container:addButton({
        width = 1,
        height = 1,
        x = ui_descending.x + ui_descending.width + 1,
        y = self.ui_label.y,
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

function UI_Tasks:initBackground(container)
	local r = container:addScrollFrame({
		width = container.width,
        height = container.height - 5,
        x = 1,
        y = self.ui_label.y + 2,
        background = colors.gray,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.lightGray,
        scrollBarBackgroundColor2 = colors.gray,
		name = "background"
	})
	return r
end

function UI_Tasks:initCurrentPage(container)
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

function UI_Tasks:initFirstPage(container)
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

function UI_Tasks:initPreviousPage(container)
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

function UI_Tasks:initNextPage(container)
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

function UI_Tasks:initLastPage(container)
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
