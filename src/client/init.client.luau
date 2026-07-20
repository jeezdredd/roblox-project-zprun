--!strict

local InputController = require(script.controllers.InputController)
local CameraController = require(script.controllers.CameraController)
local RunController = require(script.controllers.RunController)

InputController.init()
CameraController.init()
RunController.init()

print("[TaskForceZ][Client] Client started")
