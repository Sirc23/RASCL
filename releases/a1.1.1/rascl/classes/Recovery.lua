--[[
	Recovery.lua  (NEW)

	Looks after items that are somewhere they should not stay: in a crafter, or in a staging slot that no job
	is responsible for any more. A job ends when its tasks end; whatever it could not put back in storage is
	handed to Recovery, which keeps trying until it can.

	master.strandedItems     {container, slot, uniqueKey, count}   items sitting in staging slots that nobody owns
	master.stagingReservations[chest][slot] = {stranded = true}      keeps such a slot from being handed to a job
	master.turtleTask[crafter].blocked = true                        the crafter still holds items; no task is given to it

	Everything here is derived from what is physically there, so it can be rebuilt after a restart:
	Recovery.reconcileStaging() and Recovery.reconcileCrafter() look at the staging chests and a crafter and adopt whatever they find.
]]

Recovery = {}

--The staging containers of a job, in the order they were reserved (none for a job without staging)
local function jobChests(job)
	return job and (job.stagingChests or (job.stagingContainer and {job.stagingContainer})) or {}
end

--What is physically inside a crafter right now, as slot -> item details, read over the wired network.
function Recovery.readCrafter(station)
	return myTalker:requestFrom(master.turtles[station].computerID, "getTurtleInventory", {
		slots = "all",
		detailed = true
	})
end

--This staging slot now holds items that belong to no job. Keep it reserved until they are back in storage.
function Recovery.strand(chest, slot, uniqueKey, count)
	master.stagingReservations = master.stagingReservations or {}
	master.stagingReservations[chest.name] = master.stagingReservations[chest.name] or {}
	master.stagingReservations[chest.name][slot] = {name = "stranded items", stranded = true}
	master.strandedItems = master.strandedItems or {}
	table.insert(master.strandedItems, {container = chest, slot = slot, uniqueKey = uniqueKey, count = count})
	Recovery.start()
end

--Put `count` items of crafter slot `slot` into staging slots that nobody has reserved and that are really empty:
--first in the staging chests of the failed job, then in the others. Any unreserved slot may be used, including the few
--that admission never hands out. Returns how many are still in the crafter.
function Recovery.parkInStaging(station, slot, gid, count, job)
	local chests = {}
	local mine = {}
	for _, chest in ipairs(jobChests(job)) do
		table.insert(chests, chest)
		mine[chest.name] = true
	end
	local others = {}
	for _, container in pairs(master.containers) do
		if container.type == "staging" and not mine[container.name] and not container:missing() then
			table.insert(others, container)
		end
	end
	table.sort(others, function(a, b) return a.name < b.name end)
	for _, container in ipairs(others) do
		table.insert(chests, container)
	end
	
	for _, chest in ipairs(chests) do
		local physically = peripheral.call(chest.name, "list")
		local reserved = master.stagingReservations and master.stagingReservations[chest.name] or {}
		for toSlot = 1, master.model.sizes[chest.name] do
			if count <= 0 then
				return 0
			end
			if not reserved[toSlot] and physically[toSlot] == nil then
				local moved = peripheral.call(chest.name, "pullItems", station, slot, count, toSlot)
				if moved > 0 then
					count = count - moved
					Recovery.strand(chest, toSlot, gid.uniqueKey, moved)
				end
			end
		end
	end
	return count
end

--Empty a crafter completely. Storage first; what storage cannot take goes into staging. `reported` is what the crafter
--said it holds (the failed craft's reply); without it the crafter is read, which costs a tick per slot.
--Returns true when the crafter is empty.
function Recovery.emptyCrafter(station, job, reported)
	local inventory = reported or Recovery.readCrafter(station)
	if next(inventory) == nil then
		return true
	end
	local temp = Container:new(station, inventory)
	local allGone = true
	for slot, gid in pairs(inventory) do
		if reported then
			Task.completeGid(station, slot, gid)
		end
		local left = temp:exportItemToStorage("", slot, job)
		if left == nil then
			left = gid.count	--(not allowed to import: nothing was moved)
		end
		if left > 0 then
			left = Recovery.parkInStaging(station, slot, gid, left, job)
		end
		if left > 0 then
			allGone = false
		end
	end
	return allGone
end

--The crafter still holds items and there is nowhere to put them. Keep tasks away from it until it is empty.
function Recovery.blockCrafter(station)
	master.turtleTask[station].blocked = true
	asdf("Crafter " .. station .. " is blocked: it still holds items and there is no room anywhere")
	Recovery.start()
end

--Try to move whatever is physically in a staging slot into storage. Returns its uniqueKey and how many could not be moved.
function Recovery.clearStagingSlot(chest, slot, job)
	local gid = peripheral.call(chest.name, "getItemDetail", slot)
	if not gid then
		return nil, 0
	end
	local uniqueKey = gid.name .. "|" .. (gid.nbt or "0")
	local left = chest:exportItemToStorage(uniqueKey, slot, job)
	if left == nil then
		left = gid.count
	end
	return uniqueKey, left
end

--Is there anything left to recover: stranded items in staging, or a blocked crafter?
function Recovery.hasWork()
	if master.strandedItems and #master.strandedItems > 0 then
		return true
	end
	for _, station in pairs(master.turtleTask) do
		if station.blocked then
			return true
		end
	end
	return false
end

--Try again: stranded items back into storage, blocked crafters emptied.
function Recovery.recover()
	--The model learned about whatever was in the way (a full chest, a swapped item). That may be gone by now, and nothing
	--would tell the model: read the containers that disagreed with it again before trying to store anything.
	for containerName in pairs(master.suspectContainers or {}) do
		master.containers[containerName]:resync()
	end
	local stranded = master.strandedItems or {}
	for index = #stranded, 1, -1 do
		local entry = stranded[index]
		local left = entry.container:exportItemToStorage(entry.uniqueKey, entry.slot)
		if left == nil then
			left = entry.count
		end
		if left == 0 then
			master.stagingReservations[entry.container.name][entry.slot] = nil
			table.remove(stranded, index)
		else
			entry.count = left
		end
	end
	for name, station in pairs(master.turtleTask) do
		if station.blocked and Recovery.emptyCrafter(name, nil) then
			station.blocked = nil
			asdf("Crafter " .. name .. " is empty again")
		end
	end
end

--Check every few seconds until everything is recovered (only one such loop runs at a time)
function Recovery.start()
	if master.recovering then
		return
	end
	master.recovering = true
	basalt.schedule(function()
		while Recovery.hasWork() do
			os.sleep(5)
			Recovery.recover()
		end
		master.suspectContainers = {}
		master.recovering = false
	end)
end

--After a restart nothing is remembered but what is physically there. Anything in a staging chest belongs to no job:
--adopt it, and let the recovery loop put it back into storage. Call this ONCE, when the host has defined its containers.
--@ marker Recovery.reconcileStaging: adopt whatever a restart left in the staging chests
function Recovery.reconcileStaging()
	for _, container in pairs(master.containers) do
		if container.type == "staging" and not container:missing() then
			for slot, listed in pairs(peripheral.call(container.name, "list")) do
				Recovery.strand(container, slot, listed.name .. "|" .. (listed.nbt or "0"), listed.count)
			end
		end
	end
end
