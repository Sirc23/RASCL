RemotePeripheral = {}
RemotePeripheral.__index = RemotePeripheral

function RemotePeripheral:new(name)
	local r = setmetatable({}, self)
	
	r.name = name
	
	r.init = function(containerName)
		--Do not directly execute this within a return statement
		local data = r:call("rpInit", containerName)
		return data
	end
	
	local exists = r.init(name)
	if not exists then return nil end
	
	r.size = function()
		--Do not directly execute this within a return statement
		local data = r:call("rpSize")
		return data
	end

	r.list = function()
		--Do not directly execute this within a return statement
		local data = r:call("rpList")
		return data
	end
	
	r.getItemDetail = function(slot)
		--Do not directly execute this within a return statement
		local data = r:call("rpGetItemDetail", slot)
		return data
	end

	r.getItemLimit = function(slot)
		--Do not directly execute this within a return statement
		local data = r:call("rpGetItemLimit", slot)
		return data
	end

	r.pushItems = function(toName, fromSlot, limit, toSlot)
		--Do not directly execute this within a return statement
		local data = r:call("rpPushItems", toName, fromSlot, limit, toSlot)
		return data
	end

	r.pullItems = function(fromName, fromSlot, limit, toSlot)
		--Do not directly execute this within a return statement
		local data = r:call("rpPullItems", fromName, fromSlot, limit, toSlot)
		return data
	end
	
	return r
end

function RemotePeripheral:call(command, ...)
    local data = {containerName = self.name}
    local args = {...}
	
	--Calling frame 1 is this function
	--Level 2 is the function that called this function
    local calling_frame = 2 
    
    local i = 1
    while true do
        -- Get the name of the argument from the calling function
        local name = debug.getlocal(calling_frame, i)
        if not name then break end -- No more parameters
        
        -- Use this name as an index; assign it the value passed from the vararg (...)
        data[name] = args[i]
        i = i + 1
    end
	
	return myTalker:request(command, data, function(packet)
		return self.name == packet.data.containerName
	end)
end

function RemotePeripheral:destroy()
	
end