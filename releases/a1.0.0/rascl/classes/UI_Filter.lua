UI_Filter = {}
UI_Filter.__index = UI_Filter

function UI_Filter:new(container)
	local r = setmetatable({}, self)
	
	r.foreground = container:addFrame({
        width = termX,
        height = termY + 1,
        x = 1,
        y = 1,
        background = colors.lightGray,
		name = "Filters"
    })
		
		r.ui_table = r:initTable(r.foreground)
		r.ui_add = r:initAdd(r.foreground)
		r.ui_header = r:initHeader(r.foreground)
			r.ui_moveUp = r:initMoveUp(r.ui_header)
			r.ui_moveDown = r:initMoveDown(r.ui_header)
			r.ui_edit = r:initEdit(r.ui_header)
	
	r:rebuildTable()
	
	return r
end

function UI_Filter:initTable(container)
	local r = container:addTable({
        width = termX,
        height = termY - 4,
        x = 1,
        y = 4,
        background = colors.gray,
		foreground = colors.white,
        selectedBackground = colors.yellow,
		selectedForeground = colors.black,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.gray,
        columns = {{"", width = 5}, {name = "", width = termX - 2}},
		name = "table"
    })
	
	return r
end

function UI_Filter:initAdd(container)
	local r = container:addButton({
        width = termX - 2,
        height = 1,
        x = 2,
        y = 2,
        text = "Add",
        background = colors.green,
		name = "add"
    })
    r:setBackgroundState("clicked", colors.gray)
    r:onClick(function(element)
		local uniqueID = getUniqueID(4)
		csv.insert(config.filters, {
			name = uniqueID,
			any = "true",
			whitelist = "true",
			visible = "true",
			filterType = "item",
			items = textutils.serialiseJSON({})
		})
		local newFilter = Filter:new(uniqueID)
		table.insert(master.filters, newFilter)
		
		UI_FilterEditor:new(newFilter, self.foreground)
    end)
	
	return r
end

function UI_Filter:initHeader(container)
	local r = container:addFrame({
        width = termX,
        height = 1,
        x = 1,
        y = 4,
        background = colors.orange,
		name = "header"
    })
	
	return r
end

function UI_Filter:initMoveUp(container)
	local r = container:addButton({
        width = 3,
        height = 1,
        x = math.floor(termX / 8),
        y = 1,
        text = "\24", --Up arrow
        background = colors.lightBlue,
		name = "moveUp"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		local currentRow = self.ui_table:getSelectedRow()
        if not currentRow then return end
		
		if not isHost then
			local newPacket = myTalker:makePacket("send_filterSwap", {
				currentRow = currentRow,
				direction = -1,
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			self:swapCurrentRow(currentRow, -1)
			local newPacket = myTalker:makePacket("broadcast_filterSwap", {
				currentRow = currentRow,
				direction = -1,
			})
			myTalker:broadcastPacket(newPacket)
		end
    end)
	
	return r
end

function UI_Filter:initMoveDown(container)
	local moveUp = container:getChild("moveUp")
	local r = container:addButton({
        width = 3,
        height = 1,
        x = moveUp.x + moveUp.width + 1,
        y = 1,
        text = "\25", --Down arrow
        background = colors.lightBlue,
		name = "moveDown"
    })
    r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		local currentRow = self.ui_table:getSelectedRow()
        if not currentRow then return end
		
		if not isHost then
			local newPacket = myTalker:makePacket("send_filterSwap", {
				currentRow = currentRow,
				direction = 1,
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			self:swapCurrentRow(currentRow, 1)
			local newPacket = myTalker:makePacket("broadcast_filterSwap", {
				currentRow = currentRow,
				direction = 1,
			})
			myTalker:broadcastPacket(newPacket)
		end
    end)
	
	return r
end

function UI_Filter:initEdit(container)
	local moveDown = container:getChild("moveDown")
	local r = container:addButton({
        width = 4,
        height = 1,
        x = moveDown.x + moveDown.width + 1,
        y = 1,
        text = "Edit",
        background = colors.red,
		name = "edit"
    })
    r:setBackgroundState("clicked", colors.gray)
    r:onClick(function(element)
        local currentRow = self.ui_table:getSelectedRow()
        if not currentRow then
            return
        end
        local rowIndex = currentRow._data.cells[1]
		UI_FilterEditor:new(master.filters[rowIndex], self.foreground)
    end)
	
	return r
end

function UI_Filter:swapCurrentRow(currentRow, offset)
        if not currentRow then return end
		local localCurrentRow = self.ui_table:getSelectedRow()
		local localCurrentIndex = nil
		if localCurrentRow then
			localCurrentIndex = localCurrentRow._data.cells[1]
		end
		
        local currentIndex = currentRow._data.cells[1]
        local currentName = currentRow._data.cells[2]
		
		local otherIndex = math.min(math.max(1, currentIndex + offset), #master.filters)
		if currentIndex == otherIndex then
			return
        end
        local otherName = self.ui_table:getRow(otherIndex)._data.cells[2]
		
		--Get data to swap
		local csv_query = csv.select(config.filters, function(row)
			return row["name"] == currentName or row["name"] == otherName
		end)
		
		if #csv_query ~= 2 then return end
		
		--Swap data in csv file
		csv.update(config.filters, function(row)
			return row["name"] == currentName or row["name"] == otherName
		end, function(row)
			if row["name"] == csv_query[1]["name"] then
				for i,v in pairs(csv_query[2]) do
					row[i] = v
				end
			elseif row["name"] == csv_query[2]["name"] then
				for i,v in pairs(csv_query[1]) do
					row[i] = v
				end
			end
		end)
		
		--Swap positions of filters in table
		master.filters[currentIndex], master.filters[otherIndex] = master.filters[otherIndex], master.filters[currentIndex]
		
		self:rebuildTable()
		if localCurrentIndex then
			if localCurrentIndex == currentIndex then
				self.ui_table:getRow(otherIndex)._data.selected = true
			elseif localCurrentIndex == otherIndex then
				self.ui_table:getRow(currentIndex)._data.selected = true
			else
				self.ui_table:getRow(localCurrentIndex)._data.selected = true
			end
		end
    end

function UI_Filter:rebuildTable()
	local localCurrentRow = self.ui_table:getSelectedRow()
	local localCurrentName = nil
	if localCurrentRow then
		localCurrentName = localCurrentRow._data.cells[2]
	end
	self.ui_table:clearData()
	local index = 1
	for _, thisFilter in ipairs(master.filters) do
        self.ui_table:addRow(index, thisFilter.name)
		if thisFilter.name == localCurrentName then
			self.ui_table:getRow(index)._data.selected = true
		end
		index = index + 1
    end
	
end