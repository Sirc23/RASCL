UI_ModEditor = {}
UI_ModEditor.__index = UI_ModEditor

function UI_ModEditor:new(container, isServer)
	local r = setmetatable({}, self)
	
	r.foreground = container:addFrame({
        width = container.width - 2,
        height = container.height,
        x = 2,
        y = 1,
        background = colors.lightGray,
		name = "Mods"
    })
		
		r.ui_table = r:initTable(r.foreground)
		r.ui_label = r:initLabel(r.foreground)
		r.ui_add = r:initAdd(r.foreground)
	
	r:rebuildTable()
	
	return r
end

function UI_ModEditor:initTable(container)
	local r = container:addTable({
        width = container.width,
        height = container.height - 2,
        x = 1,
        y = 2,
        background = colors.gray,
		foreground = colors.white,
        selectedBackground = colors.yellow,
		selectedForeground = colors.black,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.gray,
        columns = {{"Name", width = math.floor(container.width / 2)}, {name = "ID", width = math.ceil(container.width / 2)}},
		name = "table"
    })
	r:onRowSelect(function(element, rowIndex, row)
		self:updateMod(element.parent, row._data.cells[1], false)
	end)
	
	return r
end

function UI_ModEditor:initLabel(container)
	local r = container:addLabel({
		width = container.width,
		height = 1,
		x = 1,
		y = self.ui_table.y,
		z = 10,
		autoSize = false,
		background = colors.orange,
		foreground = colors.black,
		backgroundEnabled = true,
		text = "Name" .. string.rep("\128", math.floor(container.width/2) - 5) .. "ID"
	})
	
	return r
end

function UI_ModEditor:initAdd(container)
	local r = container:addButton({
		width = 9,
		height = 1,
		x = math.floor((container.width - 9)/2),
		y = container.height,
		background = colors.green,
		foreground = colors.black,
		text = " Add Mod "
	})
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		self:updateMod(element.parent, "New Mod", true)
	end)
	
	return r
end

function UI_ModEditor:rebuildTable()
	local localCurrentRow = self.ui_table:getSelectedRow()
	local localCurrentName = nil
	if localCurrentRow then
		localCurrentName = localCurrentRow._data.cells[1]
	end
	self.ui_table:clearData()
	local index = 1
	for _, thisItem in ipairs(csv.select(config.mods, function(row) return true end)) do
        self.ui_table:addRow(thisItem.name, thisItem.mod)
		if thisItem.mod == localCurrentName then
			self.ui_table:getRow(index)._data.selected = true
		end
		index = index + 1
    end
	
end

function UI_ModEditor:updateMod(container, name, newMod)
	local r = container:addFrame({
		width = container.width,
		height = container.height,
		x = 1,
		y = 1,
		background = colors.lightGray,
		foreground = colors.black,
		name = "bgMod"
	})
	
	local ui = r:addFrame({
		width = container.width - 2,
		height = 6,
		x = 2,
		y = 2,
		background = colors.lightGray,
		foreground = colors.black,
		name = "frameMod"
	})
	
	ui:addBorder({
		color = colors.yellow,
		top = true,
		left = true,
		right = true,
		bottom = true
	})
	
	local label = ui:addLabel({
        height = 1,
        x = 1,
        y = 1,
		text = " " .. name .. " ",
        foreground = colors.black,
		background = colors.yellow,
		backgroundEnabled = true
    })
	
	local modNameLabel = ui:addLabel({
		height = 1,
		x = 2,
		y = label.y + 1,
		foreground = colors.black,
		text = "Name:"
	})
	
	local ok = ui:addButton({
		width = 2,
		height = 1,
		x = ui.width - 2,
		y = 2,
		background = colors.green,
		foreground = colors.black,
		text = "ok"
	})
	
	ok.doUpdate = bindFunctionToInstance(ok, function(element, newMod)
		local modName = ui:getChild("modName").text
		local modID = ui:getChild("modID").text
		
		if not isHost then
			local newPacket = myTalker:makePacket("send_updateMod", {
				modName = modName,
				modID = modID,
				newMod = newMod
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		else
			local newPacket = myTalker:makePacket("broadcast_updateMod", {
				modName = modName,
				modID = modID,
				newMod = newMod
			})
			myTalker:broadcastPacket(newPacket)
		end
		master.mods[modID] = modName
		master.mod_ids[modName] = modID
		if newMod then
			csv.insert(config.mods, {
				name = modName,
				mod = modID
			})
		else
			csv.update(config.mods, function(row)
				return row["name"] == name
			end,
			function(row)
				row["name"] = modName
				row["mod"] = modID
			end)
		end
	end)
	
	ok:onClick(function(element)
		local modName = ui:getChild("modName").text
		local modID = ui:getChild("modID").text
		if modName == "" or modID == "" then
			return
		end
		
		for _, value in pairs(csv.select(config.mods, function(row) return true end)) do
			if value.name ~= name and value.name == modName then
				ui:getChild("modName").foreground = colors.red
				return
			elseif value.name ~= name and value.mod == modID then
				ui:getChild("modID").foreground = colors.red
				return
			end
		end
		element.doUpdate(newMod)
		
		element:setCursor(-100, -100, true, colors.white)
		self:rebuildTable()
		self.foreground:getChild("bgMod"):destroy()
	end)
	
	local modNameInput = ui:addInput({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = modNameLabel.y + 1,
		autoSize = false,
		background = colors.black,
		foreground = colors.white,
		text = name,
		name = "modName"
	})
	
	modNameInput:onKeyUp(function(element, key)
		element.foreground = colors.white
		if(ctrlDown and (key == keys.v)) then
			element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
			element.cursorPos = element.cursorPos + #master.clipboard
		end
		
		local s = element.text
		--Trim text to remove whitespaces
		s = s:gsub("^%s*", "")
		element.text = s
    end)
	modNameInput:listenEvent("paste", false)
	
	local modIDLabel = ui:addLabel({
		height = 1,
		x = 2,
		y = modNameInput.y + 1,
		foreground = colors.black,
		text = "Mod ID:"
	})
	
	local CSVQuery = csv.select(config.mods, function(row) return row["name"] == name end)
	local modid = ""
	if CSVQuery and #CSVQuery > 0 then
		modid = CSVQuery[1].mod
	end
	local modIDInput = ui:addInput({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = modIDLabel.y + 1,
		autoSize = false,
		background = colors.black,
		foreground = colors.white,
		text = modid,
		name = "modID"
	})
	
	modIDInput:onKeyUp(function(element, key)
		element.foreground = colors.white
		if(ctrlDown and (key == keys.v)) then
			element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
			element.cursorPos = element.cursorPos + #master.clipboard
		end
		
		local s = element.text
		s = string.lower(s)
		element.text = s
		--Trim text to remove whitespaces
		s = s:match("^%s*(.-)%s*$")
		--Only allow a-z, 0-9, -, and _
		s = s:gsub("[^a-z0-9%-%_]", "")
		element.text = s
    end)
	modIDInput:listenEvent("paste", false)
	
	
	
	return r
end