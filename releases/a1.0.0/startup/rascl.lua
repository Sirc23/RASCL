term.clear()
version = "1.0.0"
config = {}
--Load bootstrap file
local bootstrapFile = fs.open("/startup/rascl_bootstrap.txt", "r")
local line = bootstrapFile.readLine()
if not line then error("Bootstrap file not set") end
root = line .. "/"
bootstrapFile.close()

--Load config file
local configFile = fs.open(root .. "files.txt", "r")

while true do
    local line = configFile.readLine()
    if not line then break end
    local index = 0
    local key = ""
    for item in string.gmatch(line, "([^=]+)") do
        if(index == 0) then
            key = item
        else
			if key:match("_class$") then
				require(root .. item)
			else
				config[key] = root .. item
			end
        end
        index = index + 1
    end
end
configFile.close()

csv = require (config.csv)

for _, value in pairs(csv.select(config.client_config, function(row) return true end)) do
	config[value.key] = value.value
end
for _, value in pairs(csv.select(config.server_config, function(row) return true end)) do
	config[value.key] = value.value
end

--Turn on debug mode
debugMode = toboolean(config.debug_mode)

termX, termY = term.getSize()

--Cart amounts must be set up prior to the definitions for UI
cartAmount = 1
cartItemsLeft = tonumber(config.max_cart_size)

basalt = require(config.basalt)

parallelProcesses = {}

--Begin startup procedures
master = Startup:new()


--Verify CSV tables exist
master:validateTables()

--TODO: editing filter and then trying to deposit items into the chest causes problems

isHost = (config.computer_type == "host") and not pocket
isCrafter = false
local hasTable = false
local hasModem = false
if (config.computer_type == "crafter") and turtle then
	if turtle.getEquippedLeft() then
		hasTable = turtle.getEquippedLeft().name == "minecraft:crafting_table"
		hasModem = (turtle.getEquippedLeft().name == "computercraft:wireless_modem_normal" or turtle.getEquippedLeft().name == "computercraft:wireless_modem_advanced")
	end
	if turtle.getEquippedRight() then
		hasTable = hasTable or turtle.getEquippedRight().name == "minecraft:crafting_table"
		hasModem = hasModem or (turtle.getEquippedRight().name == "computercraft:wireless_modem_normal" or turtle.getEquippedRight().name == "computercraft:wireless_modem_advanced")
	end
	if hasTable and hasModem then
		isCrafter = true
		isHost =  false --Just to be 100% sure
	end
end

if isHost then
	splashScreen("Starting...")
else
	splashScreen("Connecting...")
end

myTalker = Talker:new(isHost, config.server_hostname)

shiftDown = false
ctrlDown = false

initialized = false
readyForInput = false

table.insert(parallelProcesses, function() basalt.run() end)
table.insert(parallelProcesses, function() master:initializeUI() end)
table.insert(parallelProcesses, function() myTalker:listenForMessages() end)
if isHost then
	table.insert(parallelProcesses, function() master:handleInputChests() end)
end
table.insert(parallelProcesses, function() master:peripheralAttachLoop() end)
table.insert(parallelProcesses, function() master:peripheralDetachLoop() end)

parallel.waitForAll(table.unpack(parallelProcesses))