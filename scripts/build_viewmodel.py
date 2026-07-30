#!/usr/bin/env python3
"""Turn a rig dump taken from Studio into a Rojo .model.json.

Only geometry goes into the model file. Joints are deliberately left out and created at
runtime instead, for two reasons:

  - MeshPart.MeshId cannot be written by a script in any context available to us, so the
    meshes have to arrive as instances that Rojo mounts. That is what this file is for.
  - Rojo's JSON model format has no way to express a Ref property, which is what Part0
    and Part1 are. Creating joints from a script works fine, so the joint layout lives in
    src/shared/config/ViewmodelRigConfig.luau where it stays readable.

Usage:
    python3 scripts/build_viewmodel.py pistol
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEWMODELS = os.path.join(ROOT, "assets", "viewmodels")


def parse_dump(path):
    parts, joints = [], []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith(("PART|", "JOINT|")):
                continue
            fields = line.split("|")
            # the header rows spell their own column names, so skip them
            if fields[1] == "name" or fields[1] == "class":
                continue
            if fields[0] == "PART":
                parts.append(fields[1:])
            else:
                joints.append(fields[1:])
    return parts, joints


def cframe(values):
    numbers = [float(v) for v in values]
    if len(numbers) != 12:
        raise ValueError(f"expected 12 CFrame components, got {len(numbers)}")
    return numbers


def build_part(fields):
    (
        name,
        size_x,
        size_y,
        size_z,
        mesh_id,
        texture_id,
        color_r,
        color_g,
        color_b,
        material,
        transparency,
    ) = fields[:11]
    cf = cframe(fields[11:23])

    class_name = "MeshPart" if mesh_id else "Part"
    properties = {
        "Size": [float(size_x), float(size_y), float(size_z)],
        "CFrame": cf,
        "Color": [float(color_r), float(color_g), float(color_b)],
        "Material": material,
        "Transparency": float(transparency),
        # Only the rig root is anchored, and that root is the arms rig rather than any
        # part of the weapon, so nothing here may be anchored.
        "Anchored": False,
        "CanCollide": False,
        "CanQuery": False,
        "CanTouch": False,
        "CastShadow": False,
        "Massless": True,
    }
    if mesh_id:
        properties["MeshId"] = f"rbxassetid://{mesh_id}"
        if texture_id:
            properties["TextureID"] = f"rbxassetid://{texture_id}"

    return {"className": class_name, "name": name, "properties": properties}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    name = sys.argv[1]
    dump_path = os.path.join(VIEWMODELS, f"{name}.rig.txt")
    if not os.path.exists(dump_path):
        print(f"no dump at {dump_path}")
        return 1

    parts, joints = parse_dump(dump_path)
    if not any(p[0] == "Main" for p in parts):
        print("dump has no `Main` part; it is the PrimaryPart and is required")
        return 1

    model = {
        "className": "Model",
        "properties": {"Name": name.capitalize()},
        "children": [build_part(p) for p in parts],
    }

    out_path = os.path.join(VIEWMODELS, f"{name}.model.json")
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(model, handle, indent=2)
        handle.write("\n")

    meshes = sum(1 for p in parts if p[4])
    motors = sum(1 for j in joints if j[0] == "Motor6D")
    print(f"wrote {out_path}")
    print(f"  {len(parts)} parts ({meshes} with meshes)")
    print(f"  {len(joints)} joints recorded in the dump ({motors} Motor6D), created at runtime")
    return 0


if __name__ == "__main__":
    sys.exit(main())
