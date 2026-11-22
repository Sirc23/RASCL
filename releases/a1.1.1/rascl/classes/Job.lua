--[[
	Job.lua  (NEW)

	Carries out what Planner.plan worked out.

	  local job, reason = Job.start(recipes, amount)	--plans, reserves everything, and runs the job in its own coroutine

	The life of a job
	  1. PLAN AND RESERVE (Job.start): Planner.plan, then Planner.admit, in the same stretch of code. Nothing in between yields,
	     so the model cannot change and nothing has to be checked again. The staging slots, the ingredients and the output
	     slots are reserved exactly as planned. One attempt: if anything cannot be reserved the job is refused at once,
	     holds nothing, and never waits or retries. Only then is the job scheduled to run.
	  2. The tasks enter the crafters' queues (Task:enterQueue). A job is never queued itself; its tasks are.
	  3. The levels run one after another. Tasks of one level run side by side on as many crafters as are free. Nothing is
	     checked first: a task takes its items out of the containers and counts what arrived, and the turtle checks that it
	     holds exactly what the host says it loaded (name and nbt of every slot) before it crafts, and that it made what the
	     recipe says afterwards. If anything is not as expected the task fails, its crafter is emptied from the turtle's own
	     report, the containers the items came from are read again so that the model is right, and the job stops.
	  4. Nothing is repaired or retried. Items that were staged go back to storage with the cleanup, so running the job
	     again simply takes them from there.
	  5. CLEAN UP: the ingredient reservations are dropped at once, what is left in staging goes back to storage (empty
	     slots are released, slots that cannot be emptied stay reserved as stranded, see Recovery), and the output slots
	     are released after that export has been attempted.

	Nothing here uses events. Everything that waits (for a crafter, for tasks to finish) sleeps one
	tick with os.sleep() and looks again at the variables the other coroutines keep up to date.

	If something goes wrong after items have started to move, every task empties its own crafter (Task:fail) and the
	cleanup above runs. The job ends when its tasks end: whatever could not be put back is Recovery's problem, not the job's.
]]

Job = {}
Job.__index = Job

function Job:new(levels, stagingSlotsNeeded, outputContainer, name, ledger)
	local r = setmetatable({}, self)
	r.levels = levels
	r.stagingSlotsNeeded = stagingSlotsNeeded
	r.outputContainer = outputContainer
	r.ledger = ledger
	r.storageNeeds = ledger and ledger.storageNeeds		--What will be imported at the end (from Planner.plan)
	r.name = name or "job"
	r.status = "starting"
	r.pending = 0		--Tasks of the current level that have not finished yet
	r.running = 0		--Tasks that have started moving items and have not ended yet
	r.executing = false	--Has any item started to move into a crafter?
	r.failure = nil
	r.warnings = {}
	return r
end

--Plan a request, reserve everything it needs, and start it in its own coroutine. This is what the craft screen and a
--remote computer's request call.
--Returns the job (already running). If the request cannot be planned it returns nil and the reason. If it was planned but
--could not be reserved it returns nil, the reason, the kind of refusal, and the job (which never ran).
--job.finished becomes true when the job has ended.
--@ marker Job.start: plan, reserve, run
function Job.start(recipes, amount, outputContainerName, name)
	local outputContainer = master.containers[outputContainerName]
	if (outputContainer == nil) or outputContainer.type ~= "output" or outputContainer:missing() then
		outputContainerName = nil
		outputContainer = nil
	end
	
	local levels, stagingSlots, ledger = Planner.plan(recipes, amount, outputContainer)
	if not levels then
		return nil, stagingSlots
	end
	local job = Job:new(levels, stagingSlots, outputContainer, name, ledger)
	local admitted, reason, kind = Planner.admit(job)
	if not admitted then
		job.status = "refused"
		job.failure = reason
		job.refusal = kind
		job.finished = true
		return nil, reason, kind, job
	end
	job.status = "queued"
	basalt.schedule(function()
		job:run()
	end)
	return job
end

--Runs the levels, then cleans up. Blocks until the job has ended.
--@ marker Job:run: the levels, then cleanup
function Job:run()
	for number, level in ipairs(self.levels) do
		self.status = "level " .. number
		self:runLevel(level)
		if self.failure then
			break
		end
	end
	
	--Tasks that are in the middle of a batch finish it first, so that nothing is taken from under them
	while self.running > 0 do
		os.sleep()
	end
	
	self.status = "cleaning up"
	self:cleanup()
	self.status = self.failure and "failed" or "done"
	self.finished = true
	return self.failure == nil, self.failure
end

--Start every task of a level, then wait until all of them are done (or the job has failed)
function Job:runLevel(level)
	self.pending = #level
	for _, task in ipairs(level) do
		task.job = self
		basalt.schedule(function()
			task:enterQueue()
		end)
	end
	while self.pending > 0 and not self.failure do
		os.sleep()
	end
end

--A task has started moving items / has stopped / has finished (or failed)
function Job:taskStarted(task)
	task.counted = true
	self.running = self.running + 1
	self.executing = true		--From here on items move, so a failure needs the full cleanup
end

function Job:taskStopped(task)
	if task.counted then
		task.counted = false
		self.running = self.running - 1
	end
end

--Called by a task when it has finished (or failed)
function Job:taskFinished(task, ok, reason)
	if task.counted then
		task.counted = false
		self.running = self.running - 1
	end
	if ok then
		self.pending = self.pending - 1
	else
		self:fail((task.itemInfo and (task.itemInfo.displayName .. ": ") or "") .. tostring(reason))
	end
end

--Something went wrong: the first reason wins, and every task that has not finished is told to stop
--(the ones waiting for a crafter notice on their next look, the ones working stop between batches)
function Job:fail(reason)
	if not self.failure then
		self.failure = reason
	end
	for _, level in ipairs(self.levels) do
		for _, task in ipairs(level) do
			task.cancelled = true
		end
	end
end

--Give everything back. Runs when no task of the job is moving items any more.
--@ marker Job:cleanup: release what is reserved, return what is in staging
function Job:cleanup()
	if self.failure and not self.executing then
		Planner.releaseAll(self)			--Not one item has moved: just give everything back
		return
	end
	Planner.releaseStock(self)				--Ingredients: immediately
	self:flushStaging()						--Surplus (and whatever a failure left) goes back to storage
	Planner.releaseStorage(self)			--Output slots: after the export has been attempted
end

--Whatever is still in this job's staging slots goes to normal storage. Empty slots are released; a slot whose items
--cannot go back stays reserved as "stranded" until Recovery can empty it.
function Job:flushStaging()
	for _, level in ipairs(self.levels) do
		for _, task in ipairs(level) do
			for _, staged in ipairs(task.stagingOutput or {}) do
				local left = staged.container:exportItemToStorage(staged.key, staged.slot, self)
				if left and left > 0 then
					table.insert(self.warnings, left .. " x " .. staged.key .. " could not be returned to storage")
					Recovery.strand(staged.container, staged.slot, staged.key, left)
				end
			end
		end
	end
	Planner.releaseStagingSlots(self)
end
