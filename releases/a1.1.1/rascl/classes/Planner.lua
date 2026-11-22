--[[
	Planner.lua  (NEW)

	Turns "craft N of X" into a list of tasks arranged in levels, working out recursively which
	ingredients can come from storage and which have to be crafted first.

	  levels, stagingSlotsNeeded = Planner.plan(recipes, amount)      (or nil, reason)

	  levels[1]  tasks that only need items already in storage
	  levels[2]  tasks that need something crafted by a task in levels[1]  ... and so on
	  levels[#levels] is the task the user asked for, always alone.
	  Tasks in the same level do not depend on each other and may run in parallel.

	Vocabulary
	  step     one item type that has to be crafted. Each step becomes exactly one Task.
	  ledger   scratch pad the planner works on: stock left, the steps, and what to take from storage.
	  staging  a chest that holds crafted intermediate items until the tasks that need them run.

	Simplifications (on purpose, to keep the algorithm easy to follow)
	  * One staging chest per job (the whole tree): a parent usually needs items from several children,
	    and a task may only reference one staging chest.
	  * A staging slot is never reused, even if a later step would empty it.
	  * Aux outputs (items left in the grid after a craft) go to normal storage, never into staging,
	    and are not used as ingredients within the same plan.
]]

Planner = {}

local STAGING = "staging"	--Stands in for the staging chest in plan operations until a chest is reserved
local blocker				--The item that made planning fail (used for the error message)

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

--Steps store an index, never the Recipe object itself, so that deepCopy() of the ledger stays cheap
local function recipeOf(key, step)
	return master.recipes[key][step.recipeIndex]
end

--Units of `key` still unclaimed in normal storage
local function stockOf(ledger, key)
	if ledger.stock[key] == nil then
		local item = master.storage[key]
		ledger.stock[key] = item and item:available() or 0		--What is not already promised to another job
	end
	return ledger.stock[key]
end

--A copy of `path` with `key` added
local function withKey(path, key)
	local copy = {}
	for k in pairs(path) do
		copy[k] = true
	end
	copy[key] = true
	return copy
end

--Undo a failed attempt by putting back what the ledger looked like before it
local function restore(ledger, snapshot)
	for k in pairs(ledger) do
		ledger[k] = nil
	end
	for k, v in pairs(snapshot) do
		ledger[k] = v
	end
end

--How many of this item fit in one slot? The real value if the item is known, otherwise a safe guess.
function Planner.stackSize(key, fallback)
	local item = master.storage[key]
	return (item and item.gid.maxCount) or fallback
end

--An Item for any uniqueKey, even one that has never been in storage.
--A throwaway Item is NOT added to master.storage, so it is never counted as stock.
function Planner.describeItem(uniqueKey, fallbackStack)
	local known = master.storage[uniqueKey]
	if known then
		return known
	end
	--Never been in storage: rebuild what a scan would have found, from what the recipes know about it
	local info = master.itemInfo[uniqueKey]
	local nameAndNbt = splitString(uniqueKey, "|")
	local modAndName = splitString(nameAndNbt[1], ":")
	local tags = {}
	for _, tagID in pairs(info and info.tags or {}) do
		table.insert(tags, master.tagIDs[tagID].tag)
	end
	return Item:new({
		name = nameAndNbt[1],
		nbt = nameAndNbt[2],
		uniqueKey = uniqueKey,
		displayName = info and info.displayName or nameAndNbt[1],
		modID = modAndName[1],
		nameNoMod = modAndName[2],
		modName = master.mods[modAndName[1]],
		tags = tags,
		count = 0,
		maxCount = fallbackStack,
		containers = {}
	}, true)
end

------------------------------------------------------------------------
-- STEP 1: decide what has to be crafted
-- Rule for every ingredient: use what is in storage, craft the rest.
-- Always look steps up by key (ledger.steps[key]): restore() swaps in fresh tables,
-- so a step table fetched earlier may be out of date.
------------------------------------------------------------------------

local makeAvailable	--supply() and makeAvailable() call each other

--`consumerKey` needs `needed` units of `key`.
local function supply(ledger, consumerKey, key, needed, path)
	local consumer = ledger.steps[consumerKey]
	consumer.uses[key] = consumer.uses[key] or {fromStock = 0, fromStep = 0}
	local use = consumer.uses[key]
	
	local fromStock = math.min(needed, stockOf(ledger, key))
	ledger.stock[key] = ledger.stock[key] - fromStock
	ledger.draws[key] = (ledger.draws[key] or 0) + fromStock
	use.fromStock = use.fromStock + fromStock
	
	local fromStep = needed - fromStock	--The rest has to be crafted
	if fromStep == 0 then
		return true
	end
	use.fromStep = use.fromStep + fromStep
	consumer.children[key] = true		--The consumer has to wait for key's step
	return makeAvailable(ledger, key, fromStep, path)
end

--Do `crafts` more crafts of step `key`, and supply everything those crafts use up.
local function addCrafts(ledger, key, crafts, path)
	local step = ledger.steps[key]
	local recipe = recipeOf(key, step)
	step.crafts = step.crafts + crafts
	step.produced = step.produced + crafts * recipe.primaryOutput.count
	
	local deeper = withKey(path, key)
	for _, ingredient in ipairs(recipe.recipeDataCompressed) do
		--ingredient.count = how many grid slots use it = units needed per craft
		if not supply(ledger, key, ingredient.uniqueKey, ingredient.count * crafts, deeper) then
			return false
		end
	end
	return true
end

--Create the step for `key` with the first recipe that works (recipes are kept in priority order).
--wanted = {units = n} for an ingredient, or {crafts = n} for the item the user asked for.
local function startStep(ledger, key, wanted, path)
	local foundRecipe = false
	local recipes = master.recipes[key] or {}
	--Only a recipe that has another one after it needs a snapshot. If the LAST recipe fails, the failure goes up to the step
	--that asked for this one, which restores ITS snapshot (or the whole plan fails), so nothing here has to be undone.
	local lastCrafting = 0
	for index, recipe in ipairs(recipes) do
		if recipe.recipeType == "crafting" then
			lastCrafting = index
		end
	end
	for index, recipe in ipairs(recipes) do
		if recipe.recipeType == "crafting" then
			foundRecipe = true
			local snapshot = index < lastCrafting and deepCopy(ledger) or nil
			ledger.steps[key] = {
				recipeIndex = index,
				crafts = 0,
				produced = 0,
				taken = wanted.units or 0,	--Units already promised to consumers
				uses = {},					--ingredient -> {fromStock, fromStep}
				children = {}				--Steps this one must wait for
			}
			local crafts = wanted.crafts and math.ceil(wanted.crafts / recipe.primaryOutput.count) or math.ceil(wanted.units / recipe.primaryOutput.count)
			if addCrafts(ledger, key, crafts, path) then
				return true
			end
			if snapshot then
				restore(ledger, snapshot)	--This recipe failed: forget everything it did and try the next one
			end
		end
	end
	if not foundRecipe then
		local item = master.storage[key]
		local name = Planner.describeItem(key, 1).gid.displayName
		if item and item.reserved > 0 then
			blocker = "Need " .. name
		else
			blocker = "Need " .. name
		end
	end
	return false
end

makeAvailable = function(ledger, key, needed, path)
	if path[key] then
		--key is already being crafted further up the chain: a loop (like ingot <-> block)
		blocker = key .. " needs itself (circular recipes)"
		return false
	end
	local step = ledger.steps[key]
	if step then
		--Someone already crafts this item: use its spare units first
		local spare = step.produced - step.taken
		step.taken = step.taken + needed
		if spare >= needed then
			return true
		end
		local perCraft = recipeOf(key, step).primaryOutput.count
		return addCrafts(ledger, key, math.ceil((needed - spare) / perCraft), path)
	end
	return startStep(ledger, key, {units = needed}, path)
end

------------------------------------------------------------------------
-- STEP 2 helpers: is there room in normal storage, and keep that room for this job
------------------------------------------------------------------------

--Everything that will be imported into normal storage when the job is done, as
--uniqueKey -> {quantity = how many, stack = a safe stack size if the item has never been in storage}
function Planner.storageNeeds(ledger, rootKey, outputUnits)
	local needs = {}
	local function need(key, quantity, stack)
		if quantity > 0 then
			needs[key] = needs[key] or {quantity = 0, stack = stack}
			needs[key].quantity = needs[key].quantity + quantity
		end
	end
	for key, step in pairs(ledger.steps) do
		local recipe = recipeOf(key, step)
		if key == rootKey then
			need(key, step.produced - (outputUnits or 0), recipe.maxBatching)				--The finished product
		else
			need(key, step.produced - step.taken, recipe.maxBatching)	--Surplus left in staging, flushed out at the end
		end
		for _, aux in ipairs(recipe.auxillaryOutputs) do
			need(aux.uniqueKey, aux.count * step.crafts, 1)				--Left in the grid after every craft
		end
	end
	return needs
end

--Decide where all of `needs` would go. Nothing is moved and nothing is kept: the scratch view only remembers
--the slots earlier items in this list claimed, so two items are never planned into the same empty slot.
--Slots reserved by other jobs look full. Space freed by items that get used up is not counted (the safe assumption).
--Returns true and plans[uniqueKey] = plan, or false and the reason.
function Planner.planStorage(needs, job)
	--Sorted, so that the same problem is always reported first
	local keys = {}
	for key in pairs(needs) do
		table.insert(keys, key)
	end
	table.sort(keys)
	
	local view = StorageView.scratch(job)
	local plans = {}
	for _, key in ipairs(keys) do
		local item = Planner.describeItem(key, needs[key].stack)
		local plan, left = Container.planImport(item, needs[key].quantity, view)
		if left > 0 then
			return false, "no room in storage for " .. left .. " x " .. item.gid.displayName
		end
		view:record(plan, key)
		plans[key] = plan
	end
	return true, plans
end

--Plan time: would it all fit right now? Reserves nothing. The slots it found are kept in ledger.storagePlan, and
--Planner.admit reserves exactly those, in the same stretch of code, instead of working them out a second time.
function Planner.checkStorageRoom(ledger, rootKey, outputUnits)
	local needs = Planner.storageNeeds(ledger, rootKey, outputUnits)
	ledger.storageNeeds = needs
	local ok, result = Planner.planStorage(needs, nil)
	if not ok then
		return false, result
	end
	ledger.storagePlan = result		--key -> the slots (as planImport made them) that item would be stored in
	return true
end

--Keep the slots of one item's plan for `job`.
local function commitKey(job, key, plan)
	master.importReservations = master.importReservations or {}
	job.storageReservations = job.storageReservations or {}
	job.storageReservations[key] = {}
	for _, op in ipairs(plan) do
		local entry = {containerName = op.containerName, slot = op.toSlot, job = job, uniqueKey = key, remaining = op.count}
		master.importReservations[op.containerName] = master.importReservations[op.containerName] or {}
		master.importReservations[op.containerName][op.toSlot] = entry
		table.insert(job.storageReservations[key], entry)
	end
end

--Keep the slots in `plans` (from Planner.planStorage) for `job`.
local function commitStorage(job, plans)
	job.storageReservations = {}
	for key, plan in pairs(plans) do
		commitKey(job, key, plan)
	end
end
Planner.commitStorage = commitStorage

--Plan and keep the slots for everything `job` will import, in one go. All or nothing.
function Planner.reserveStorage(job, needs)
	local ok, plans = Planner.planStorage(needs, job)
	if not ok then
		return false, plans
	end
	commitStorage(job, plans)
	return true
end

--Something of this reservation has been stored: keep track of what is still expected
function Planner.consumeReservation(job, uniqueKey, containerName, slot, amount)
	local entries = job.storageReservations and job.storageReservations[uniqueKey]
	for index, entry in ipairs(entries or {}) do
		if entry.containerName == containerName and entry.slot == slot then
			entry.remaining = entry.remaining - amount
			if entry.remaining <= 0 then
				master.importReservations[containerName][slot] = nil	--Fully used: the slot now holds the item for real
				table.remove(entries, index)
			end
			return
		end
	end
end

--The job is over (done or failed): give back whatever it did not use
function Planner.releaseStorage(job)
	for _, entries in pairs(job.storageReservations or {}) do
		for _, entry in ipairs(entries) do
			master.importReservations[entry.containerName][entry.slot] = nil
		end
	end
	job.storageReservations = nil
end

------------------------------------------------------------------------
-- STEP 4 helper: hand out supplies
------------------------------------------------------------------------

--Remove `n` units from the front of a supply list and return them as a new list of operations.
--Operations look exactly like the ones Item:buildCheckoutPlan returns: {container, slot, count}.
local function takeOps(supplyList, n)
	local taken = {}
	while n > 0 do
		local first = supplyList[1]
		local amount = math.min(first.count, n)
		table.insert(taken, {container = first.container, slot = first.slot, count = amount})
		first.count = first.count - amount
		n = n - amount
		if first.count == 0 then
			table.remove(supplyList, 1)
		end
	end
	return taken
end

--A copy of a checkout plan: takeOps() cuts the copy up, the original stays as planned
local function copyOps(ops)
	local copy = {}
	for _, op in ipairs(ops) do
		table.insert(copy, {container = op.container, slot = op.slot, count = op.count})
	end
	return copy
end

local function shortage(key)
	local item = master.storage[key]
	return "Need " .. item.gid.displayName
end

--One checkout plan per item that has to come out of storage, for the total every step needs.
--Returns item -> list of {container, slot, count}, or nil and the reason.
function Planner.checkoutPlans(ledger)
	local stockSupply = {}
	for key, units in pairs(ledger.draws) do
		if units > 0 then
			stockSupply[key] = master.storage[key]:buildCheckoutPlan(units)
			if not stockSupply[key] then
				return nil, shortage(key)
			end
		end
	end
	return stockSupply
end

--Work out, for every task, which slot of its crafter gets what from where, in today's plan format.
--stockSupply is consumed (takeOps cuts pieces off the front of each list).
function Planner.fillPlans(ledger, tasks, stockSupply)
	local stagedSupply = {}
	for key, step in pairs(ledger.steps) do
		if step.staged then
			stagedSupply[key] = {}
			for _, staged in ipairs(step.staged) do
				--Before a staging chest is reserved this is the placeholder; afterwards it is the real chest and slot
				table.insert(stagedSupply[key], {container = staged.container or STAGING, slot = staged.slot, count = staged.count})
			end
		end
	end
	for key, step in pairs(ledger.steps) do
		local recipe = recipeOf(key, step)
		local plan = {}
		for _, ingredient in ipairs(recipe.recipeDataCompressed) do
			local use = step.uses[ingredient.uniqueKey]
			local ops = takeOps(stockSupply[ingredient.uniqueKey], use.fromStock)				--From normal storage
			for _, op in ipairs(takeOps(stagedSupply[ingredient.uniqueKey], use.fromStep)) do	--From staging
				table.insert(ops, op)
			end
			Task.addToSlotPlan(plan, ops, bitmaskToArray(ingredient.slots), ingredient.count * step.crafts)
		end
		tasks[key].plan = plan
	end
end

------------------------------------------------------------------------
-- The planner
------------------------------------------------------------------------

--amount = number of crafts of the item the user asked for (the same meaning as Task:new's amount)
function Planner.plan(recipes, amount, outputContainer)
	local rootKey = recipes[1].primaryOutput.uniqueKey
	local ledger = {stock = {}, steps = {}, draws = {}}
	blocker = nil
	
	--@ marker STEP 1: work out every step and where every ingredient comes from
	if not startStep(ledger, rootKey, {crafts = amount}, {}) then
		return nil, blocker or "No recipe works"
	end
	
	--@ marker STEP 2: check there is room in normal storage for the products
	local outputUnits = outputContainer and amount or 0
	local hasRoom, roomProblem = Planner.checkStorageRoom(ledger, rootKey, outputUnits)
	if not hasRoom then
		return nil, roomProblem
	end
	
	--@ marker STEP 3: arrange the steps into levels
	--A step's level = 1 + the highest level among the steps it waits for
	local heights = {}
	local function heightOf(key, visiting)
		if heights[key] then
			return heights[key]
		end
		if visiting[key] then
			return nil	--Circular wait: cannot be ordered
		end
		visiting[key] = true
		local tallest = 0
		for childKey in pairs(ledger.steps[key].children) do
			local h = heightOf(childKey, visiting)
			if not h then
				return nil
			end
			tallest = math.max(tallest, h)
		end
		visiting[key] = nil
		heights[key] = tallest + 1
		return heights[key]
	end
	if not heightOf(rootKey, {}) then
		return nil, "Circular dependency found"
	end
	
	local keysByLevel = {}
	for key in pairs(ledger.steps) do
		local level = heights[key]
		keysByLevel[level] = keysByLevel[level] or {}
		table.insert(keysByLevel[level], key)
	end
	
	--@ marker STEP 4: give every intermediate item its own staging slots
	--Numbers here are RELATIVE (1, 2, 3...). They become real chest slots once a chest is reserved.
	local stagingSlotsNeeded = 0
	for level = 1, #keysByLevel do
		for _, key in ipairs(keysByLevel[level]) do
			if key ~= rootKey then
				local step = ledger.steps[key]
				--maxBatching never exceeds the stack size, so it is a safe stack size for unknown items
				local stack = Planner.stackSize(key, recipeOf(key, step).maxBatching)
				step.staged = {}
				local left = step.produced
				while left > 0 do
					local count = math.min(stack, left)
					stagingSlotsNeeded = stagingSlotsNeeded + 1
					table.insert(step.staged, {key = key, slot = stagingSlotsNeeded, count = count})
					left = left - count
				end
			end
		end
	end
	
	--@ marker STEP 5: take items out of storage: ONE checkout plan per item, shared out between steps
	--buildCheckoutPlan runs once per item, for the total every step needs from storage.
	--fillPlans() then splits that list with takeOps(), so no two steps are told to take the same items.
	local stockSupply, supplyProblem = Planner.checkoutPlans(ledger)
	if not stockSupply then
		return nil, supplyProblem
	end
	--Remember what was planned for each item (one entry per slot). Planner.admit reserves exactly this.
	ledger.stockPlan = {}
	for key, ops in pairs(stockSupply) do
		ledger.stockPlan[key] = copyOps(ops)
	end
	
	--@ marker STEP 6: build one Task per step, with its plan in today's format
	--plan[turtleSlot] = list of {container, slot, count}
	local tasks = {}
	for key, step in pairs(ledger.steps) do
		--step.staged says where its crafted items must be put (nil for the root: they go to storage)
		local delivery = nil
		if key == rootKey and outputContainer then
			delivery = {container = outputContainer, count = outputUnits, delivered = 0}
		end
		tasks[key] = Task:newFromPlan(recipeOf(key, step), step.crafts, {}, step.staged, delivery)
	end
	Planner.fillPlans(ledger, tasks, stockSupply)
	for key, step in pairs(ledger.steps) do
		for childKey in pairs(step.children) do
			tasks[key]:addChild(tasks[childKey])
		end
	end
	
	local levels = {}
	for key, task in pairs(tasks) do
		local level = heights[key]
		levels[level] = levels[level] or {}
		table.insert(levels[level], task)
	end
	return levels, stagingSlotsNeeded, ledger
end

------------------------------------------------------------------------
-- STOCK RESERVATION (ingredients a job will take out of storage)
-- master.stockReservations[container][slot] = units reserved in that slot, by all jobs together
-- item.reserved = units reserved for the item, by all jobs together (Item:available subtracts it)
------------------------------------------------------------------------

--Keep `ops` (a checkout plan) for `job`
local function commitStock(job, key, ops)
	master.stockReservations = master.stockReservations or {}
	job.stockReservations = job.stockReservations or {}
	job.stockReservations[key] = job.stockReservations[key] or {}
	for _, op in ipairs(ops) do
		local slots = master.stockReservations[op.container.name] or {}
		master.stockReservations[op.container.name] = slots
		slots[op.slot] = (slots[op.slot] or 0) + op.count
		master.storage[key].reserved = master.storage[key].reserved + op.count
		table.insert(job.stockReservations[key], {containerName = op.container.name, slot = op.slot, remaining = op.count})
	end
end

--Promise `units` of one item to `job`. Returns true, or false when that many are not available.
function Planner.reserveItemUnits(job, key, units)
	local item = master.storage[key]
	local ops = item and item:buildCheckoutPlan(units)
	if not ops then
		return false
	end
	commitStock(job, key, ops)
	return true
end

--The keys of a table in a fixed order, so that the same problem is always reported first
local function sortedKeys(t)
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--Some of the reserved stock has been taken out of its slot: it is no longer "reserved", it is simply gone from the stock
function Planner.consumeStock(job, uniqueKey, containerName, slot, amount)
	local entries = job.stockReservations and job.stockReservations[uniqueKey]
	for index, entry in ipairs(entries or {}) do
		if entry.containerName == containerName and entry.slot == slot then
			local used = math.min(amount, entry.remaining)
			entry.remaining = entry.remaining - used
			master.stockReservations[containerName][slot] = master.stockReservations[containerName][slot] - used
			master.storage[uniqueKey].reserved = master.storage[uniqueKey].reserved - used
			if entry.remaining <= 0 then
				table.remove(entries, index)
			end
			return
		end
	end
end

--Give back what `job` has reserved of one item
function Planner.releaseItemStock(job, key)
	for _, entry in ipairs(job.stockReservations and job.stockReservations[key] or {}) do
		master.stockReservations[entry.containerName][entry.slot] = master.stockReservations[entry.containerName][entry.slot] - entry.remaining
		master.storage[key].reserved = master.storage[key].reserved - entry.remaining
	end
	if job.stockReservations then
		job.stockReservations[key] = nil
	end
end

--The job is over (done or failed): whatever it reserved and did not take is free again
function Planner.releaseStock(job)
	for key in pairs(job.stockReservations or {}) do
		Planner.releaseItemStock(job, key)
	end
	job.stockReservations = nil
end

------------------------------------------------------------------------
-- ADMISSION: everything a job needs, reserved in one go, one attempt
------------------------------------------------------------------------

--Give back everything `job` has reserved. (Slots that now hold stranded items are not the job's any more.)
function Planner.releaseAll(job)
	Planner.releaseStock(job)
	Planner.releaseStorage(job)
	Planner.releaseStagingSlots(job)
end

--Reserves everything a job needs, exactly as planned: staging slots, then the ingredients and the output slots.
--Job.start calls this right after Planner.plan, in the same stretch of code. Nothing in between yields, so the model cannot have
--changed since the plan was made, and nothing has to be checked again. One attempt: if anything cannot be reserved the job is
--refused at once and keeps nothing. Returns true, or false, the reason and the kind of refusal ("crafters", "never" or "busy").
--(Not enough stock, or no room in storage, is already known to Planner.plan, which then makes no plan at all.)
--@ marker Planner.admit: reserve everything the plan needs, or refuse the job
function Planner.admit(job)
	if not Task.pickStation() then
		return false, "no crafter can be used right now (every crafter is blocked or missing)", "crafters"
	end
	
	if job.stagingSlotsNeeded > 0 then
		local result, free = Planner.reserveStagingSlots(job, job.stagingSlotsNeeded)
		if result == "never" then
			return false, "staging can never hold this job: it needs " .. job.stagingSlotsNeeded .. " slots, and the staging chests can give out fewer (the last " .. Planner.STAGING_HEADROOM .. " slots of each are kept free)", "never"
		elseif result == "busy" then
			return false, "staging is busy: " .. job.stagingSlotsNeeded .. " slots are needed but only " .. free .. " are free right now", "busy"
		end
		Planner.useReservedStaging(job.levels, job)
	end
	
	for _, key in ipairs(sortedKeys(job.ledger.stockPlan)) do
		commitStock(job, key, job.ledger.stockPlan[key])
	end
	commitStorage(job, job.ledger.storagePlan or {})
	return true
end

------------------------------------------------------------------------
-- STAGING RESERVATION
-- Slots may come from several staging chests. The last STAGING_HEADROOM slots of every chest are never handed out
-- to a job: they stay free for emergencies (parking items that could not be stored, see Recovery).
------------------------------------------------------------------------

Planner.STAGING_HEADROOM = 4

--containerName -> { [slot] = job }. Created on first use: master does not exist yet when this file loads.
local function reservations()
	master.stagingReservations = master.stagingReservations or {}
	return master.stagingReservations
end

--The staging chests that are present, in a fixed order
local function stagingChests()
	local chests = {}
	for _, container in pairs(master.containers) do
		if container.type == "staging" and not container:missing() then
			table.insert(chests, container)
		end
	end
	table.sort(chests, function(a, b) return a.name < b.name end)
	return chests
end

--How many slots of a chest may be given to a job
local function admissibleSlots(container)
	return math.max(0, master.model.sizes[container.name] - Planner.STAGING_HEADROOM)
end

--One attempt to reserve `count` slots, in as many staging chests as it takes. Nothing waits.
--Returns "reserved", "busy" (enough slots exist, but not free right now) or "never" (no combination of chests could ever
--give that many), and the number of slots that are free right now.
--@ marker Reserve staging slots
function Planner.reserveStagingSlots(job, count)
	local chests = stagingChests()
	local capacity = 0
	for _, chest in ipairs(chests) do
		capacity = capacity + admissibleSlots(chest)
	end
	if count > capacity then
		return "never", 0
	end
	
	local found = {}
	for _, chest in ipairs(chests) do
		local reserved = reservations()[chest.name] or {}
		for slot = 1, admissibleSlots(chest) do
			if #found < count and not reserved[slot] then
				table.insert(found, {container = chest, slot = slot})
			end
		end
	end
	if #found < count then
		return "busy", #found
	end
	
	job.stagingSlots = {}		--relative slot i -> {container, slot}
	job.stagingChests = {}		--the chests used, in order
	local seen = {}
	for index, entry in ipairs(found) do
		reservations()[entry.container.name] = reservations()[entry.container.name] or {}
		reservations()[entry.container.name][entry.slot] = job
		job.stagingSlots[index] = entry
		if not seen[entry.container.name] then
			seen[entry.container.name] = true
			table.insert(job.stagingChests, entry.container)
		end
	end
	return "reserved", #found
end

--Give back the staging slots that are still this job's (a slot that now holds stranded items is not ours any more)
function Planner.releaseStagingSlots(job)
	for _, entry in ipairs(job.stagingSlots or {}) do
		local reserved = reservations()[entry.container.name]
		if reserved and reserved[entry.slot] == job then
			reserved[entry.slot] = nil
		end
	end
end

--Replace the placeholder in every plan with the reserved chest and slot.
function Planner.useReservedStaging(levels, job)
	for _, level in ipairs(levels) do
		for _, task in ipairs(level) do
			for _, slotPlan in pairs(task.plan) do
				for _, op in ipairs(slotPlan) do
					if op.container == STAGING then
						local entry = job.stagingSlots[op.slot]
						op.container = entry.container
						op.slot = entry.slot
					end
				end
			end
			for _, out in ipairs(task.stagingOutput or {}) do
				local entry = job.stagingSlots[out.slot]
				out.container = entry.container
				out.slot = entry.slot
			end
		end
	end
end
