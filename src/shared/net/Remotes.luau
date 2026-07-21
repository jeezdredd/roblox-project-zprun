--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"

Remotes.Event = table.freeze({
	SquadSnapshot = "SquadSnapshot",
	SquadUpdateConfig = "SquadUpdateConfig",
	SquadToggleModifier = "SquadToggleModifier",
	SquadLaunch = "SquadLaunch",
	SquadLeave = "SquadLeave",
})

local folder: Folder? = nil

local function getFolder(): Folder
	local current = folder
	if current then
		return current
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			folder = existing
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
		return created
	end
	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	folder = waited
	return waited
end

function Remotes.getEvent(name: string): RemoteEvent
	local parent = getFolder()
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
		return remote
	end
	return parent:WaitForChild(name) :: RemoteEvent
end

function Remotes.init()
	for _, name in Remotes.Event do
		Remotes.getEvent(name)
	end
end

return Remotes
