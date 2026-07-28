--!strict

local TextureUtil = {}

local ALL_FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

function TextureUtil.applyFace(part: BasePart, face: Enum.NormalId, textureId: number, studsPerTile: number)
	if textureId <= 0 then
		return
	end
	local texture = Instance.new("Texture")
	texture.Texture = "rbxassetid://" .. tostring(textureId)
	texture.Face = face
	texture.StudsPerTileU = studsPerTile
	texture.StudsPerTileV = studsPerTile
	texture.Parent = part
end

function TextureUtil.applyFaces(part: BasePart, faces: { Enum.NormalId }, textureId: number, studsPerTile: number)
	for _, face in faces do
		TextureUtil.applyFace(part, face, textureId, studsPerTile)
	end
end

function TextureUtil.applyAll(part: BasePart, textureId: number, studsPerTile: number)
	TextureUtil.applyFaces(part, ALL_FACES, textureId, studsPerTile)
end

function TextureUtil.applySides(part: BasePart, textureId: number, studsPerTile: number)
	TextureUtil.applyFaces(part, {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}, textureId, studsPerTile)
end

return TextureUtil
