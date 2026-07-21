--!strict

local ReplicatedFirst = game:GetService("ReplicatedFirst")

local BootState = require(ReplicatedFirst:WaitForChild("BootState"))
local BootConfig = require(ReplicatedFirst:WaitForChild("BootConfig"))

local FlowController = require(script.controllers.FlowController)
local SquadController = require(script.controllers.SquadController)
local DeathController = require(script.controllers.DeathController)
local SettingsService = require(script.systems.SettingsService)
local MusicController = require(script.systems.MusicController)
local FpsCounter = require(script.systems.FpsCounter)
local SettingsApply = require(script.systems.SettingsApply)
local GoreController = require(script.systems.GoreController)
local HudGui = require(script.ui.HudGui)
local GoreWarningGui = require(script.ui.GoreWarningGui)

BootState.awaitReady(BootConfig.READY_TIMEOUT)

SettingsService.init()
MusicController.init()
FpsCounter.init()
SettingsApply.init()
GoreController.init()

FlowController.init()
SquadController.init()
DeathController.init()

HudGui.init()
GoreWarningGui.showOnce()

print("[TaskForceZ][Client] Client started")
