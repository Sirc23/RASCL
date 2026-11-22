--[[
	StorageView.lua  (NEW)

	Container.planImport decides where items would be stored. It asks a "view" four things: which slots the
	item is already in, what is in a slot, how big a container is, and whether a container may be used.
	Nothing is ever copied: every answer comes from the live model.

	  StorageView.live(job)      reads the live model. Used by Container:exportItemToStorage, which then really moves items.
	  StorageView.scratch(job)   reads the live model too, plus a small list of slots that earlier plans in the same
	                             session have already claimed. Used to ask "would all of this fit?" without moving anything:
	                             plan one item, record() its slots, plan the next, and it cannot get the same slots.

	Import reservations (master.importReservations, see Planner.reserveStorage) make slots belong to a job:
	a reserved slot looks occupied to everybody, so no other plan or import can choose it. The job that owns it
	finds it again through reservedFor(item), which Container.planImport looks at first.

	`claimed` belongs to one view (it is created inside scratch()) and disappears with it. Reservations are what
	live on between plans and between tasks.
]]

StorageView = {}
StorageView.__index = StorageView

local RESERVED = {uniqueKey = "<reserved>", count = math.huge}	--What a reserved slot looks like to everyone

function StorageView.live(job)
	return setmetatable({job = job}, StorageView)
end

function StorageView.scratch(job)
	return setmetatable({job = job, claimed = {}}, StorageView)	--claimed[containerName][slot] = {uniqueKey, count}
end

--containerName -> list of slots that (the model says) hold this item.
--The Item already knows which containers it is in, so nothing has to be searched.
function StorageView:holders(item)
	return item.gid.containers
end

--What is really in a slot ({uniqueKey, count}, or nil if empty), including slots earlier plans in this view claimed
function StorageView:realContents(containerName, slot)
	if self.claimed then
		local claimedHere = self.claimed[containerName]
		if claimedHere and claimedHere[slot] then
			return claimedHere[slot]
		end
	end
	return master.containers[containerName].inventory[slot]
end

--What planImport's passes see: a slot reserved for an import looks full, so nobody plans into it by accident
function StorageView:contents(containerName, slot)
	local reserved = master.importReservations and master.importReservations[containerName]
	if reserved and reserved[slot] then
		return RESERVED
	end
	return self:realContents(containerName, slot)
end

--The slots reserved for THIS job and this item: {containerName, slot, remaining}
function StorageView:reservedFor(item)
	if not self.job or not self.job.storageReservations then
		return {}
	end
	return self.job.storageReservations[item.gid.uniqueKey] or {}
end

function StorageView:sizeOf(containerName)
	return master.model.sizes[containerName]
end

--Is this container present and allowed to receive items?
function StorageView:usable(containerName)
	local container = master.containers[containerName]
	return container ~= nil and not container:missing()
end

--Scratch only: pretend the plan returned by Container.planImport was carried out
function StorageView:record(plan, uniqueKey)
	for _, op in ipairs(plan) do
		local claimedHere = self.claimed[op.containerName]
		if not claimedHere then
			claimedHere = {}
			self.claimed[op.containerName] = claimedHere
		end
		local existing = self:realContents(op.containerName, op.toSlot)
		claimedHere[op.toSlot] = {
			uniqueKey = uniqueKey,
			count = (existing and existing.count or 0) + op.count
		}
	end
end
