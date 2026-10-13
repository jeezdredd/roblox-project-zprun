#!/usr/bin/env python3
"""Build an FPS Essentials Kit weapon (Unity Asset Store, bought by the owner) for Roblox.

    python3 build_kit.py rig WEAPON      FBX2glTF clips -> <weapon>_rig.glb to upload
    python3 build_kit.py rest WEAPON     roblox_rest/<WEAPON>.json from the joined rig
    python3 build_kit.py clips WEAPON    bake against roblox_rest/<WEAPON>.json -> src/shared/unity

The kit ships one FBX per clip (<Weapon>@<Clip>.FBX). Each is converted by FBX2glTF
(local/fbx2gltf, Blender breaks these 3ds Max rigs), then merge_clips.py (duplicate node
names made unique, Idle held from the last Draw frame, textures embedded), rigidify.py
(rigid weapon parts skinned to their animated parent), unscale.py, join_arms.py (arms and
weapon in one mesh and one skin, a primitive per material) and strip_glb.py. Roblox
builds these bones at the joined rig's rest worlds with X and Z negated (checked against
Studio dumps of the G36C, MP7 and M590 rigs on 2026-10-13, equal to 1e-4), so `rest` writes
the calibration file without a Studio dump. The G36C files are in centimetres and the MP7
and M590 files in inches, so their scale (importScale) is 4.29 and 4.29 x 2.54.
"""

import json
import os
import subprocess
import sys

from gltf_anim import Gltf, node_rest, trs_matrix, world_matrices

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
KIT = os.path.join(ROOT, "assets", "unity", "fps-essentials-kit")
CONVERTED = os.path.join(KIT, "converted")
FBX = os.path.join(CONVERTED, "fbx2gltf")
FBX2GLTF = os.path.join(ROOT, "local", "fbx2gltf", "FBX2glTF-macos-x86_64", "FBX2glTF-macos-x86_64")

WEAPONS = {
    "G36C": {
        "folder": "G36C",
        "clips": {"Draw": "Draw", "ReloadEmpty": "CompleteReload", "Reload": "Reload", "Fire": "Fire", "FireAim": "FireAim", "Hide": "Hide", "Melee": "Melee", "Vault": "Vault"},
        "joints": "_Controller$",
        "material": "^02 - Default$",
        "albedo": "Textures/Weapons/G36C/G36C_Albedo.jpg",
        "normal": "Textures/Weapons/G36C/G36C_Normal.jpg",
        "scale": 4.29,
    },
    "MP7": {
        "folder": "MP7",
        "clips": {"Draw": "Draw", "ReloadEmpty": "CompleteReload", "Reload": "Reload", "Fire": "Fire", "FireAim": "FireAim", "Hide": "Hide", "Melee": "Melee", "Vault": "Vault"},
        "joints": "^[A-Z][A-Z ]*$",
        "material": "^gun$",
        "albedo": "Textures/Weapons/MP7/MP7_Albedo.tga",
        "normal": "Textures/Weapons/MP7/MP7_Normal.tga",
        "scale": 10.897,
    },
    "M590": {
        "folder": "M590",
        "clips": {"Draw": "Draw", "Fire": "Fire", "FireAim": "FireAim", "Hide": "Hide", "Melee": "Melee", "ReloadStart": "ReloadStart", "ShellIn": "ShellInLoop", "ReloadEnd": "ReloadEnd", "Vault": "Vault"},
        "joints": "^[A-Z][A-Z ]*$",
        "material": "^gun$",
        "albedo": "Textures/Weapons/M590/590_D.tga",
        "normal": "Textures/Weapons/M590/590_N.tga",
        "scale": 10.897,
    },
}


def run(*args):
    print("$", " ".join(os.path.basename(a) if os.path.isabs(a) else a for a in args))
    subprocess.run(args, check=True, cwd=HERE)


def png(path):
    if path.lower().endswith((".jpg", ".jpeg", ".png")):
        return path
    out = os.path.join(CONVERTED, os.path.splitext(os.path.basename(path))[0].replace(" ", "_") + ".png")
    if not os.path.exists(out):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, out], check=True)
    return out


def converted(weapon, spec, clip):
    out = os.path.join(FBX, f"{weapon}_{clip}.glb")
    if not os.path.exists(out):
        source = os.path.join(KIT, "Models", "Weapons", spec["folder"], f"{weapon}@{clip}.FBX")
        subprocess.run([FBX2GLTF, "--binary", "--input", source, "--output", out[:-4]], check=True, cwd=CONVERTED, stdout=subprocess.DEVNULL)
    return out


def rig(weapon, spec):
    name = weapon.lower()
    full = os.path.join(CONVERTED, f"{name}_full.glb")
    files = {clip: converted(weapon, spec, source) for clip, source in spec["clips"].items()}
    args = ["python3", "merge_clips.py", files["Draw"], full, "--name", "Draw"]
    for clip, path in files.items():
        if clip != "Draw":
            args += ["--clip", f"{clip}={path}"]
    args += ["--idle", "Draw", "--drop-mesh", "^Sphere", "--material", spec["material"]]
    args += ["--albedo", png(os.path.join(KIT, spec["albedo"])), "--normal", png(os.path.join(KIT, spec["normal"]))]
    run(*args)
    rigid = os.path.join(CONVERTED, f"{name}_rigid.glb")
    unit = os.path.join(CONVERTED, f"{name}_unit.glb")
    joined = os.path.join(CONVERTED, f"{name}_joined.glb")
    out = os.path.join(CONVERTED, f"{name}_rig.glb")
    run("python3", "rigidify.py", full, rigid, "--joint-regex", spec["joints"])
    run("python3", "unscale.py", rigid, unit)
    run("python3", "join_arms.py", unit, joined, "--mesh", r"^(# Arm Male|.*_skinned$)", "--name", weapon)
    run("python3", "strip_glb.py", joined, out, "--mesh", f"^{weapon}$")
    print(f"rig ready: {out}")


def rest(weapon, spec):
    g = Gltf(os.path.join(CONVERTED, f"{weapon.lower()}_joined.glb"))
    doc = g.doc
    local = {i: trs_matrix(*node_rest(n)) for i, n in enumerate(doc["nodes"])}
    world = world_matrices(doc, local)
    joints = sorted({j for skin in doc.get("skins", []) for j in skin["joints"]})
    bones = {doc["nodes"][j]["name"]: [round(float(-world[j][0, 3]), 4), round(float(world[j][1, 3]), 4), round(float(-world[j][2, 3]), 4)] for j in joints}
    note = f"Rest positions (RootPart space, file units) of the FPS Essentials Kit {weapon} rig, from {weapon.lower()}_joined.glb with X and Z negated as Roblox imports it"
    out = os.path.join(HERE, "roblox_rest", f"{weapon}.json")
    with open(out, "w") as handle:
        json.dump({"note": note, "bones": bones}, handle, indent=1)
    print(f"wrote {out}: {len(bones)} bones")


def clips(weapon, spec):
    name = weapon.lower()
    unit = os.path.join(CONVERTED, f"{name}_unit.glb")
    baked = os.path.join(CONVERTED, f"{name}_baked.json")
    rest = os.path.join(HERE, "roblox_rest", f"{weapon}.json")
    out = os.path.join(ROOT, "src", "shared", "unity", f"{weapon}Clips.luau")
    run("python3", "gltf_anim.py", "bake", unit, baked, "--fps", "30", "--calibrate", rest, "1")
    run("python3", "emit_luau.py", baked, out, "--scale", str(spec["scale"]))


def main():
    step, weapon = sys.argv[1], sys.argv[2]
    spec = WEAPONS[weapon]
    {"rig": rig, "rest": rest, "clips": clips}[step](weapon, spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
