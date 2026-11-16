function searchTable(tab, val)
    for i, v in pairs(tab) do
        if v == val then return i end
    end
    return -1
end

function startsWith(str, start)
    return str:sub(1, #start) == start
end

function toboolean(val)
	return (val == "true")
end

function splitString(s, delim)
	local r = s .. delim
	local a = {}
	for w in r:gmatch("(.-)" .. delim) do
			table.insert(a, w)
	end
	return a
end

--Only supply one argument to this function
function deepCopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepCopy(orig_key, copies)] = deepCopy(orig_value, copies)
            end
            setmetatable(copy, deepCopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function getUnix()
	return math.floor(os.epoch("utc")/1000)
end

--Converts an array with numerical keys into a bitmask integer, where a valid key represents the bit number that should have a 1
function arrayToBitmask(a)
	local b = 0
	for i, v in pairs(a) do
		b = b + math.pow(2, i - 1)
	end
	return b
end

--Converts a bitmask integer into an array where the key represents the bit number and the value represents the bit at that position
function bitmaskToArray(b, n)
	n = n or 16
	local t = 0
	local a = {}
	for i = 1, n do
		t = bit32.band(b, 1)
		b = bit32.rshift(b, 1)
		if t == 1 then
			table.insert(a, i)
		end
	end
	
	return a
end

function bindFunctionToInstance(instance, func)
	return function(...)
		return func(instance, ...)
	end
end

function getUniqueID(size)
    local template = string.rep('x', size)
    return string.gsub(template, '[x]', function (c)
        local v = math.random(0, 15)
        return string.format('%x', v)
    end)
end

function capitalizeWords(str)
	local output, num = str:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)
	return output
end

function asdf(text)
	local debugLog = basalt.getMainFrame():getChild("currentTab/Debug/debugLog")
	
	if debugMode and debugLog then
		table.insert(debugLog.lines, tostring(os.date("%M %S")) .. ": " .. tostring(text))
		if #debugLog.lines > 12 then
			debugLog.scrollY = debugLog.scrollY + 1
		end
	end
end

--Abbreviates a number X to use no more than N characters
function abbreviate(x, n)
	x = math.floor(x)
	local s = string.format("%.0f", x)
	if #s <= n then return s end
	
	local suffixes = {"k", "m", "b", "t", "q"}
	for i = #suffixes, 1, -1 do
		local scale = 1000 ^ i
		if x >= scale then
			local whole = string.format("%.0f", math.floor(x / scale))
			local decimals = math.min(math.max(n - #whole - 2, 0), 3 * i)
			
			local frac = ""
			if decimals > 0 then
				local f = math.floor((x % scale) / (scale / 10 ^ decimals))
				frac = string.format("%0" .. decimals .. ".0f", f):gsub("0+$", "")
				if frac ~= "" then frac = "." .. frac end
			end
			
			return whole .. frac .. suffixes[i]
		end
	end
	
	return s
end

function tableToString(tbl, indent)
    indent = indent or 0
    local formatting = string.rep("  ", indent)
    local result = "{\n"
    
    for k, v in pairs(tbl) do
        local key_str = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
        local val_str
        
        if type(v) == "table" then
            val_str = tableToString(v, indent + 1)
        elseif type(v) == "string" then
            val_str = '"' .. v .. '"'
        else
            val_str = tostring(v)
        end
        
        result = result .. formatting .. "  [" .. key_str .. "] = " .. val_str .. ",\n"
    end
    
    result = result .. formatting .. "}"
    return result
end

function splashScreen(startText, nextText)
	term.setCursorPos(1, 1)
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.black)
	term.clear()
	local tX = math.ceil((termX - #startText - 6)/2)
	local height = 6
	if nextText then height = 7 end
	for j = 4, height do
		term.setCursorPos(tX, j)
		term.blit(string.rep(" ", #startText + 6), string.rep("f", #startText + 6), string.rep("8", #startText + 6))
	end
	term.setCursorPos(tX, 5)
	term.blit("   " .. startText .. "   ", string.rep("f", #startText + 6), string.rep("8", #startText + 6))
	if nextText then
		term.setCursorPos(math.ceil((termX - #nextText)/2), 6)
		term.blit(nextText, string.rep("f", #nextText), string.rep("8", #nextText))
	end
end

function findModem()
	--Find modem and turn it on
	local hasModem = false
	for _, thisPeripheral in pairs(peripheral.getNames()) do
		if peripheral.hasType(thisPeripheral, "modem") and peripheral.call(thisPeripheral, "isWireless") then
			rednet.open(thisPeripheral)
			return thisPeripheral, peripheral.wrap(thisPeripheral)
		end
	end
	
	term.clear()
	term.setCursorPos(1, 1)
	error("No modem found. Attach a modem and restart the PC.")
end


--Quick select implementation (https://en.wikipedia.org/wiki/Quickselect)
--This algorithm returns the kth-smallest element of the list, within the bounds of left and right (inclusive).
--We don't particularly care about that. What matter is this algorithm operates on the list itself, guaranteeing that all indicies smaller than k have a value smaller than the value at k; all indicies larger than k have a value larger than the value at k.
function qs(list, left, right, k, f)
	if not list or not #list or #list == 0 then return end
	if #list < 2 then return end
    while true do
        if left == right then
            return list[left]
        end
        pivotIndex = math.random(left, right) --This is optimal
        pivotIndex = qs_partition(list, left, right, pivotIndex, f)
        if k == pivotIndex then
            return list[k]
        elseif k < pivotIndex then
            right = pivotIndex - 1
        else
            left = pivotIndex + 1
        end
    end
end

function qs_partition(list, left, right, pivotIndex, f)
    local pivotValue = list[pivotIndex]
    list[pivotIndex], list[right] = qs_swap(list[pivotIndex], list[right])
    local storeIndex = left
    for i = left, right - 1 do
        if f(list[i], pivotValue) then -- <=
            list[storeIndex], list[i] = qs_swap(list[storeIndex], list[i])
            storeIndex = storeIndex + 1
        end
    end
    list[right], list[storeIndex] = qs_swap(list[right], list[storeIndex])
    return storeIndex
end

function qs_swap(a, b)
    return b, a
end