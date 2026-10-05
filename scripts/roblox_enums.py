"""Roblox enum item names the asset scripts check against (no engine access here).

VARIANT_BASE_MATERIALS: the Enum.Material items a MaterialVariant can sit on (Glass,
Neon, ForceField, Air and Water take no variants and are left out). Used by
tools/megascans (--base-material) and scripts/sync_configs.py (the manifest's
Megascans settings).
"""

VARIANT_BASE_MATERIALS = (
    "Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles",
    "Cobblestone", "Concrete", "CorrodedMetal", "CrackedLava", "DiamondPlate", "Fabric",
    "Foil", "Glacier", "Granite", "Grass", "Ground", "Ice", "LeafyGrass", "Leather",
    "Limestone", "Marble", "Metal", "Mud", "Pavement", "Pebble", "Plaster", "Plastic",
    "Rock", "RoofShingles", "Rubber", "Salt", "Sand", "Sandstone", "Slate",
    "SmoothPlastic", "Snow", "Wood", "WoodPlanks",
)
