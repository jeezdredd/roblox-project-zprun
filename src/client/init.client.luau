--!strict

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local BootState = require(ReplicatedFirst:WaitForChild("BootState"))
local BootConfig = require(ReplicatedFirst:WaitForChild("BootConfig"))

local FlowController = require(script.controllers.FlowController)
local SquadController = require(script.controllers.SquadController)

BootState.awaitReady(BootConfig.READY_TIMEOUT)

FlowController.init()
SquadController.init()

print("[TaskForceZ][Client] Client started")
