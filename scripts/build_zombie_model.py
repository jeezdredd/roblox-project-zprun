"""Write assets/zombies/<name>.model.json from the zombie mesh rows in the manifest.

Rows `zombie/mesh/<part>` hold the uploaded Model asset ids; rows `zombie/meshid/<part>`
hold the mesh ids read back in Studio (tools/cube3d/ImportZombieMeshes.server.luau).
The output mounts under ReplicatedStorage.ZombieMeshes.<Name> through default.project.json
and ZombieFactory clones its MeshParts instead of building primitives. Part sizes are the
rig's unscaled part sizes; ZombieFactory applies SCALE and colours at build time.

    python3 scripts/build_zombie_model.py walker
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")

PART_SIZES = {
    "Head": (1.1, 1.15, 1.1),
    "UpperTorso": (2.0, 1.6, 1.0),
    "LowerTorso": (2.0, 0.9, 1.0),
    "LeftUpperArm": (0.55, 1.8, 0.55),
    "RightUpperArm": (0.55, 1.8, 0.55),
    "LeftUpperLeg": (0.65, 1.9, 0.65),
    "RightUpperLeg": (0.65, 1.9, 0.65),
}


def mesh_id(manifest, part):
    entry = manifest.get("zombie/meshid/" + part.lower())
    if not entry:
        return 0
    try:
        return int(entry.get("assetId") or 0)
    except (TypeError, ValueError):
        return 0


def build(name):
    with open(MANIFEST, encoding="utf-8") as handle:
        manifest = json.load(handle)
    children = []
    missing = []
    for part, size in PART_SIZES.items():
        identifier = mesh_id(manifest, part)
        if identifier <= 0:
            missing.append(part)
        children.append({
            "className": "MeshPart",
            "name": part,
            "properties": {
                "Size": list(size),
                "CFrame": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                "Anchored": True,
                "CanCollide": False,
                "CanQuery": False,
                "CanTouch": False,
                "MeshId": "rbxassetid://" + str(identifier),
                "Material": "Fabric",
            },
        })
    model = {"className": "Model", "children": children}
    out_path = os.path.join(ROOT, "assets", "zombies", name + ".model.json")
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(model, handle, indent=2)
        handle.write("\n")
    print("wrote", os.path.relpath(out_path, ROOT), "missing mesh ids:", missing or "none")
    return 0


if __name__ == "__main__":
    sys.exit(build(sys.argv[1] if len(sys.argv) > 1 else "walker"))
