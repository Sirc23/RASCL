UI_ConfigEditor = {}
UI_ConfigEditor.__index = UI_ConfigEditor

function UI_ConfigEditor:new(container, isServer)
	local r = setmetatable({}, self)
	r.isServer = isServer
	r.sourceTable = isServer and config.server_config or config.client_config
	
	r.foreground = container
		
		r.ui_reboot = r:initReboot(r.foreground)
		r.ui_table = r:initTable(r.foreground)
		r.ui_label = r:initLabel(r.foreground)
	
	r:rebuildTable()
	
	return r
end

function UI_ConfigEditor:initReboot(container)
	local r = container:addButton({
		width = 6,
		height = 1,
		x = container.width - 5,
		y = container.height - 1,
		z = 10,
		autoSize = false,
		background = self.isServer and colors.red or colors.blue,
		foreground = colors.black,
		text = "Reboot"
	})
	
	r:setBackgroundState("clicked", colors.gray)
	r:onClick(function(element)
		element.proceed = nil
		if self.isServer then
			if isHost then
				basalt.schedule(function()
					local proceed = self:prompt()
					if proceed then
						local newPacket = myTalker:makePacket("broadcast_reboot", {})
						myTalker:broadcastPacket(newPacket)
						os.reboot()
					end
				end)
			else
				basalt.schedule(function()
					local proceed = self:prompt()
					if proceed then
						local newPacket = myTalker:makePacket("send_reboot", {})
						myTalker:sendPacket(newPacket, myTalker.host)
						os.reboot()
					end
				end)
			end
		else
			if isHost then
				basalt.schedule(function()
					local proceed = self:prompt()
					if proceed then
						local newPacket = myTalker:makePacket("broadcast_reboot", {})
						myTalker:broadcastPacket(newPacket)
						os.reboot()
					end
				end)
			else
				os.reboot()
			end
		end
	end)
	
	return r
end

function UI_ConfigEditor:initTable(container)
	local r = container:addTable({
        width = container.width,
        height = container.height - 2,
        x = 1,
        y = 1,
        background = colors.gray,
		foreground = colors.white,
        selectedBackground = colors.yellow,
		selectedForeground = colors.black,
        scrollBarColor = colors.white,
        scrollBarBackgroundColor = colors.gray,
        columns = {{"Key", width = math.floor(container.width / 2)}, {name = "Value", width = math.ceil(container.width / 2)}},
		name = "table"
    })
	r:onRowSelect(function(element, rowIndex, row)
		self:updateConfig(element.parent, row._data.cells[1])
	end)
	
	return r
end

function UI_ConfigEditor:initLabel(container)
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
		text = "Key" .. string.rep("\128", math.floor(container.width/2) - 3) .. "Value"
	})
	
	return r
end

function UI_ConfigEditor:rebuildTable()
	local localCurrentRow = self.ui_table:getSelectedRow()
	local localCurrentName = nil
	if localCurrentRow then
		localCurrentName = localCurrentRow._data.cells[1]
	end
	self.ui_table:clearData()
	local index = 1
	for _, thisItem in ipairs(csv.select(self.sourceTable, function(row) return true end)) do
        self.ui_table:addRow(thisItem.key, thisItem.value)
		if thisItem.key == localCurrentName then
			self.ui_table:getRow(index)._data.selected = true
		end
		index = index + 1
    end
	
end

function UI_ConfigEditor:updateConfig(container, key)
	local r = container:addFrame({
		width = container.width,
		height = container.height - 1,
		x = 1,
		y = 1,
		background = colors.lightGray,
		foreground = colors.black,
		name = "bg"
	})
	
	local ui = r:addFrame({
		width = container.width - 2,
		height = 6,
		x = 2,
		y = 1,
		background = colors.lightGray,
		foreground = colors.black,
		name = "frame"
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
		text = " " .. key .. " ",
        foreground = colors.black,
		background = colors.yellow,
		backgroundEnabled = true
    })
	
	local currentValueLabel = ui:addLabel({
		height = 1,
		x = 2,
		y = label.y + 1,
		foreground = colors.black,
		text = "Current Value:"
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
	
	ok.doUpdate = bindFunctionToInstance(ok, function(element)
		
		if self.isServer and not isHost then
			local newPacket = myTalker:makePacket("send_serverConfigChange", {
				key = key,
				value = ui:getChild("input").text
			})
			myTalker:sendPacket(newPacket, myTalker.host)
		elseif self.isServer and isHost then
			local newPacket = myTalker:makePacket("broadcast_serverConfigChange", {
				key = key,
				value = ui:getChild("input").text
			})
			myTalker:broadcastPacket(newPacket)
		end
		
		config[key] = ui:getChild("input").text
		csv.update(self.sourceTable, function(row)
			return row["key"] == key
		end,
		function(row)
			row["value"] = config[key]
		end)
	end)
	
	ok:onClick(function(element)
		if not ui:getChild("input").text or ui:getChild("input").text == "" then
		
		elseif key == "server_hostname" or key == "server_protocol" then
			basalt.schedule(function()
				local proceed = self:prompt()
				if proceed then
					element.doUpdate()
					if isHost then
						local newPacket = myTalker:makePacket("broadcast_reboot", {})
						myTalker:broadcastPacket(newPacket)
					else
						local newPacket = myTalker:makePacket("send_reboot", {})
						myTalker:sendPacket(newPacket, myTalker.host)
					end
					
					os.reboot()
				end
			end)
		else
			element.doUpdate()
		end
		element:setCursor(-100, -100, true, colors.white)
		self:rebuildTable()
		self.foreground:getChild("bg"):destroy()
	end)
	
	local currentValue = ui:addLabel({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = currentValueLabel.y + 1,
		autoSize = false,
		foreground = colors.black,
		text = config[key]
	})
	
	local newValueLabel = ui:addLabel({
		height = 1,
		x = 2,
		y = currentValue.y + 1,
		foreground = colors.black,
		text = "New Value:"
	})
	
	local newValueInput = ui:addInput({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = newValueLabel.y + 1,
		autoSize = false,
		background = colors.black,
		foreground = colors.white,
		name = "input"
	})
	
	newValueInput:onKeyUp(function(element, key)
		if(ctrlDown and (key == keys.v)) then
			element.text = string.sub(element.text, 1, element.cursorPos - 1) .. master.clipboard .. string.sub(element.text, element.cursorPos, #element.text)
			element.cursorPos = element.cursorPos + #master.clipboard
		end
		
		local s = element.text
		s = string.lower(s)
		element.text = s
		--Trim text to remove whitespaces
		s = s:match("^%s*(.-)%s*$")
		--Only allow a-z, 0-9, -, _, and :
		s = s:gsub("[^a-z0-9%-%_%:]", "")
		element.text = s
    end)
	newValueInput:listenEvent("paste", false)
	
	
	
	return r
end

function UI_ConfigEditor:prompt()
	local proceed = nil
	local r = basalt.getMainFrame():addFrame({
		width = basalt.getMainFrame().width + 2,
		height = basalt.getMainFrame().height + 1,
		x = 1,
		y = 1,
		z = 9999,
		background = colors.black
	})
	
	local ui = r:addFrame({
		width = 18 + (termX % 2),
		height = 6,
		x = math.ceil((2 + termX - 18) / 2),
		y = 4,
		background = colors.lightGray
	})
	ui:addBorder({
		color = colors.yellow,
		top = true,
		left = true,
		right = true,
		bottom = true
	})
	local label1 = ui:addLabel({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = 2,
		foreground = colors.black,
		text = " Restarting all "
	})
	local label2 = ui:addLabel({
		width = ui.width - 2,
		height = 1,
		x = 2,
		y = 3,
		foreground = colors.black,
		text = "  clients. Ok?  "
	})
	local ok = ui:addButton({
		width = 4,
		height = 1,
		x = 2,
		y = 5,
		background = colors.green,
		foreground = colors.black,
		text = " Ok "
	})
	ok:onClick(function(element2)
		proceed = true
		r:destroy()
	end)
	
	local back = ui:addButton({
		width = 4,
		height = 1,
		x = ui.width - 4,
		y = 5,
		background = colors.red,
		foreground = colors.black,
		text = "Back"
	})
	back:onClick(function(element2)
		proceed = false
		r:destroy()
	end)
	
	while proceed == nil do
		os.sleep()
	end
	
	return proceed
end