UI_Recipes = {}
UI_Recipes.__index = UI_Recipes

function UI_Recipes:new(container)
	local r = setmetatable({}, self)
	
	r.f_sortName = function(a,b)
		return (a.primaryOutput.displayName <= b.primaryOutput.displayName)
	end
	
	r.f_sortMod = function(a,b)
		local c = (a.outputMod ~= b.outputMod)
		return (master.mods[a.primaryOutput.mod] <= master.mods[b.primaryOutput.mod] and c)
			or (a.primaryOutput.displayName <= b.primaryOutput.displayName and not c)
	end
	
	r.f_sortType = function(a,b)
		local c = (a.recipeType ~= b.recipeType)
		return	(a.recipeType <= b.recipeType and c)
			or (a.primaryOutput.displayName <= b.primaryOutput.displayName and not c)
		end
	
	r.search = ""
	r.loose = true
	r.sort = "name"
	r.sortFunction = r.f_sortName
	r.sortDescending = true
	r.numRecipes = 0
	
	r.foreground = container:addFrame({
		width = container.width,
		height = container.height,
		x = 1,
		y = 1,
		background = colors.lightGray
	})
		r.ui_search = r:initSearch(r.foreground)
		r.ui_doSearch = r:initDoSearch(r.foreground)
		r.ui_add = r:initAdd(r.foreground)
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
	
		return r
end

function UI_Recipes:refreshUI()
	if not self.refreshScheduled then
		self.refreshScheduled = true
		basalt.schedule(function()
			os.sleep()
			self:sortUI({}, true)
		end)
	end
end

function UI_Recipes:sortUI(changes, forceReordering)
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
	
	local validRecipes = {}
	
	for _, thisRecipe in pairs(master.recipes) do
		local matchesFilter = thisRecipe:matchesSearch({
			search = self.search,
			loose = self.loose
		})
		
		if matchesFilter then
			table.insert(validRecipes, thisRecipe)
		end
		thisRecipe:destroyUI()
		
	end
	self.numRecipes = #validRecipes
	local pageSize = tonumber(config.entries_per_page)
	
	if math.ceil(#validRecipes / pageSize) < self.ui_currentPage.number() then
		self.ui_currentPage.update(math.ceil(#validRecipes / pageSize))
	end
	local currentPage = self.ui_currentPage.number()
	
	local minEntry = math.min((currentPage-1) * pageSize + 1, #validRecipes)
	local maxEntry = math.min(currentPage * pageSize, #validRecipes)
	
	qs(validRecipes, 1, #validRecipes, maxEntry, finalSort)
	qs(validRecipes, 1, maxEntry, minEntry, finalSort)
	
	local recipeSortArray = {}
	for index = minEntry, maxEntry do
		table.insert(recipeSortArray, validRecipes[index])
	end
	
	table.sort(recipeSortArray, finalSort)
	
	local i = 1
	local color = colors.magenta
	
	for _, thisRecipe in pairs(recipeSortArray) do
		local ui = thisRecipe:makeUI(self)
		thisRecipe.ui = ui
		ui.y = i
		ui.visible = true
		i = i + 2
		
		ui.background = color
		if color == colors.pink then
			color = colors.magenta
		else
			color = colors.pink
		end
		
	end
	if self.refreshScheduled then
		self.refreshScheduled = false
	end
end

function UI_Recipes:changePage()
	self:refreshUI()
	self.background.offsetY = 0
end

function UI_Recipes:initSearch(container)
	
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

function UI_Recipes:initDoSearch(container)
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

function UI_Recipes:initAdd(container)
	local r = container:addButton({
		width = 3,
        height = 1,
        x = container.width - 2,
        y = self.ui_search.y + 1,
		background = colors.green,
		foreground = colors.black,
        text = "Add",
		name = "add",
    })
	r:onClick(function(element)
		local c = element.parent
		local newFrame = c:addFrame({
			width = c.width,
			height = c.height,
			x = 1,
			y = 1,
			background = colors.lightGray
		})
		--TODO: Auto select processing recipe if not isCrafter
		local craft = newFrame:addButton({
			width = newFrame.width,
			height = 3,
			x = 1,
			y = 2,
			background = colors.lightBlue,
			foreground = colors.black,
			text = "Crafting",
			visible = isCrafter
		})
		craft:onClick(function(element2)
			newFrame:destroy()
			local newRecipe = Recipe:new()
			UI_RecipeEditorCraft:new(newRecipe, element.parent)
		end)
		
		local notCrafter = newFrame:addButton({
			width = newFrame.width,
			height = 3,
			x = 1,
			y = 2,
			autoSize = false,
			background = colors.gray,
			foreground = colors.white,
			text = "Not a valid turtle",
			visible = not isCrafter
		})
		local process = newFrame:addButton({
			width = newFrame.width,
			height = 3,
			x = 1,
			y = craft.y + craft.height + 3,
			background = colors.lightBlue,
			foreground = colors.black,
			text = "Processing"
		})
	end)
	return r
end

function UI_Recipes:initSort(container)
	local r = {}
	
	--local label = container:getChild("label")
	
	local f = function(element)
		self:sortUI({sort=element.name})
	end
	
	local b = container:addButton({
		width = 1,
        height = 1,
        x = 1,
        y = self.ui_search.y + 1,
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
        y = b.y,
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
        y = b.y,
        background = colors.lightGray,
        text = "t",
		name = "type"
	})
	:setBackgroundState("clicked", colors.gray)
	b.sortFunction = self.f_sortType
	b.doSort = bindFunctionToInstance(b, f)
	b:onClick(f)
	table.insert(r, b)
	
	
	for _, element in pairs(r) do
		if element.name == "name" then
			element.background = colors.lightBlue
			self.sortFunction = element.sortFunction
		else
			element.background = colors.lightGray
		end
	end
	
	
	return r
end

function UI_Recipes:initSortDescending(container)
	local r = container:addButton({
        width = 1,
        height = 1,
        x = self.ui_sort[#self.ui_sort].x + 1,
        y = self.ui_search.y + 1,
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

function UI_Recipes:initLoose(container)
	local ui_descending = container:getChild("descending")
	local r = container:addButton({
        width = 1,
        height = 1,
        x = ui_descending.x + ui_descending.width + 1,
        y = self.ui_sortDescending.y,
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

function UI_Recipes:initBackground(container)
	local r = container:addScrollFrame({
		width = container.width,
        height = container.height - 5,
        x = 1,
        y = self.ui_sortDescending.y + 2,
        background = colors.gray,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.lightGray,
        scrollBarBackgroundColor2 = colors.gray,
		name = "background"
	})
	return r
end

function UI_Recipes:initCurrentPage(container)
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
        t = math.min(math.max(1, math.ceil(self.numRecipes / tonumber(config.entries_per_page))), t)
		
		element.text = string.rep("\128", math.max(element.width - #tostring(t), 0)) .. tostring(t)
	end)
	
	r.number = bindFunctionToInstance(r, function(element)
		local t = string.gsub(element.text, "\128", "")
		return tonumber(t)
	end)
	
	return r
end

function UI_Recipes:initFirstPage(container)
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

function UI_Recipes:initPreviousPage(container)
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

function UI_Recipes:initNextPage(container)
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

function UI_Recipes:initLastPage(container)
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
		self.ui_currentPage.update(math.ceil(self.numRecipes / tonumber(config.entries_per_page)))
		self:changePage()
	end)
	
	return r
end
