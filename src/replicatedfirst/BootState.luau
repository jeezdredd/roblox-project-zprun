--!strict

local BootState = {}

local ready = false
local waiters: { thread } = {}

function BootState.isReady(): boolean
	return ready
end

function BootState.setReady()
	if ready then
		return
	end
	ready = true
	local pending = waiters
	waiters = {}
	for _, thread in pending do
		task.spawn(thread)
	end
end

function BootState.awaitReady(timeout: number?)
	if ready then
		return
	end
	local thread = coroutine.running()
	table.insert(waiters, thread)
	if timeout then
		task.delay(timeout, function()
			if ready then
				return
			end
			local index = table.find(waiters, thread)
			if index then
				table.remove(waiters, index)
				task.spawn(thread)
			end
		end)
	end
	coroutine.yield()
end

return BootState
