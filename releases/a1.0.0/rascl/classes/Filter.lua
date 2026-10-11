Filter = {}
Filter.__index = Filter

function Filter:new(filterName)
	local r = setmetatable({}, self)
	r.name = ""
	r.containers = {}
	r:importFromCSV(filterName)
	
	return r
end

function Filter:destroy()
	
	--Update container allocation and filter
	local updateContainerUI = false
	for _, thisContainerName in pairs(self.containers) do
		local thisContainer = master.containers[thisContainerName]
		if thisContainer and thisContainer.allocation == self.name then
			thisContainer:saveChanges({type = thisContainer.type, filter = nil})
			updateContainerUI = true
		end
	end
	
	if updateContainerUI then
		ui_containerManager:scheduleUpdate()
	end
	
	for index, value in ipairs(master.filters) do
		if value == self then
			table.remove(master.filters, index)
			break
		end
	end
	
	csv.delete(config.filters, function(row)
		return row["name"] == self.name
	end)
	
	ui_filterManager:rebuildTable()
end

function Filter:exportToCSV()
	return {
		name = self.name,
		any = tostring(self.any),
		whitelist = tostring(self.whitelist),
		visible = tostring(self.visible),
		filterType = self.filterType,
		items = textutils.serialiseJSON(self.items)
	}
end

function Filter:importFromCSV(name)
	local csv_query = csv.select(config.filters, function(row)
		return row["name"] == name
	end)
	if #csv_query == 0 then return end
	local result = csv_query[1]
	self.name = result.name
	self.any = toboolean(result.any)
	self.whitelist = toboolean(result.whitelist)
	self.visible = toboolean(result.visible)
	self.filterType = result.filterType
	self.items = textutils.unserialiseJSON(result.items)
end

function Filter:updateCSV()
	local r = self:exportToCSV()
	
	csv.update(config.filters, function(row)
		return row["name"] == self.name
	end, function(row)
		for i,v in pairs(r) do
			row[i] = v
		end
	end)
end

function Filter:saveChanges(changes)
	if changes == nil then return false end
	if changes.name == nil then return false end
	if changes.any == nil then return false end
	if changes.whitelist == nil then return false end
	if changes.visible == nil then return false end
	if changes.filterType == nil or changes.filterType == "" then return false end
	if changes.items == nil then return false end
		
	for _, thisFilter in ipairs(master.filters) do
		if thisFilter.name == changes.name and changes.name ~= self.name then
			return false
		end
	end
	
	local originalName = self.name
	
	self.name = changes.name
	self.items = {}
	for _, thisEntry in pairs(changes.items) do
		table.insert(self.items, thisEntry)
	end
	
	self.any = changes.any
	self.whitelist = changes.whitelist
	self.visible = changes.visible
	self.filterType = changes.filterType
	
	csv.update(config.filters, function(row)
		return row["name"] == originalName
	end, function(row)
		local values = self:exportToCSV()
		values.name = self.name
		for index, value in pairs(values) do
			row[index] = value
		end
	end)
	
	--Update container allocation names
	local updateContainerUI = false
	if changes.name ~= originalName then
		for _, thisContainerName in pairs(self.containers) do
			local thisContainer = master.containers[thisContainerName]
			if thisContainer and thisContainer.allocation == originalName then
				thisContainer:saveChanges({type = thisContainer.type, filter = changes.name})
				updateContainerUI = true
			end
		end
	end
	
	if updateContainerUI then
		ui_containerManager:scheduleUpdate()
	end
	
	return true
end

function Filter:containsItem(item)
    local end_on_first_match = (self.whitelist == self.any)
    local pass_on_match = self.any
	
    for i,v in ipairs(self.items) do
        local matched = false
        if(item.gid.name == v and self.filterType == "item") then
            if end_on_first_match then
                return pass_on_match
            end
            matched = true
        elseif(item.gid.modID == v and self.filterType == "mod") then
            if end_on_first_match then
                return pass_on_match
            end
            matched = true
        elseif(self.filterType == "attribute") then
            for _,w in ipairs(item.gid.tags) do
                if w == v then
                    matched = true
                    break
                end
            end
            if matched and end_on_first_match then
                return pass_on_match
            end
        elseif(self.filterType == "filter") then
			local newFilter = nil
			for _, thisFilter in ipairs(master.filters) do
				if(thisFilter.name == v) then
					newFilter = thisFilter
					break
				end
			end
			if newFilter then
				matched = newFilter:containsItem(item)
				if matched and end_on_first_match then
					return pass_on_match
				end
			else
				--Filter does not exist
			end
        end
        if not matched and not end_on_first_match then
            return pass_on_match
        end
    end
    return not pass_on_match
end

function Filter:inContainer(container)
	return (searchTable(self.containers, container) ~= -1)
end

function Filter:addContainer(container)
	if(not self:inContainer(container)) then
		table.insert(self.containers, container)
	end
end

function Filter:removeContainer(container)
	local index = searchTable(self.containers, container)
	if index ~= -1 then
		table.remove(self.containers, index)
	end
end

function findFilter(filterName)
	if not filterName then return nil end
	for _, thisFilter in ipairs(master.filters) do
		if thisFilter.name == filterName then
			return thisFilter
		end
	end
	return nil
end