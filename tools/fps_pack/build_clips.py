#!/usr/bin/env python3
"""Bake and emit the viewmodel clip modules for every FPS pack in PACKS.

    python3 tools/fps_pack/build_clips.py [--src DIR] [--only CLASS]

--src is the folder holding the downloaded Sketchfab glb files (default
~/Downloads/fps_packs). Writes src/shared/viewmodel_clips/<Class>Clips.luau. The scale
must match the UnitScale node strip_glb.py put on the uploaded rig (see the manifest note
of viewmodel/fps/<class>/rig).
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "src", "shared", "viewmodel_clips")

# class -> (glb file, rig scale, extra nodes to bake[, skin fix[, skip regex]]). The skin
# fix (skin_fixes/, see gltf_anim.apply_skin_fix) must be the one strip_glb.py used for
# the uploaded rig. `skip` drops tracks of unweighted Rigify helpers the importer kept as
# ancestors: an untracked bone stays at rest and its children are still solved in model
# space, so they only cost size.
PACKS = {
    "Pistol": ("fps_pack_pistol.glb", 1.0, ["CB-Head_0116"]),
    "Rifle": ("fps_pack_ak47.glb", 2.961, ["Camera", "CB-Head_0108"]),
    "Shotgun": ("fps_pack_saps12.glb", 1.2218, ["Camera", "CB-Head_0104"]),
    "SMG": ("fps_pack_uzi.glb", 3.0, ["Camera"], "skin_fixes/smg.json", r"^(_rootJoint|root_|torso_|ORG-|MCH-|tweak_|spine_fk)"),
}

PREFIXES = ("RIG_UE5_Comando_AK__", "RIG_UE5_Comando_AK_", "RIG_UE5_Comando_", "rig|")


def clip_name(raw):
    for p in PREFIXES:
        if raw.startswith(p):
            raw = raw[len(p):]
            break
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[_\s]+", raw) if part)


def main():
    args = sys.argv[1:]
    src = os.path.expanduser(args[args.index("--src") + 1] if "--src" in args else "~/Downloads/fps_packs")
    os.makedirs(OUT, exist_ok=True)
    sys.path.insert(0, HERE)
    import json
    from gltf_anim import bake

    only = args[args.index("--only") + 1] if "--only" in args else None
    for cls, entry in PACKS.items():
        if only and cls != only:
            continue
        file, scale, extras = entry[:3]
        fix = os.path.join(HERE, entry[3]) if len(entry) > 3 and entry[3] else None
        skip = ["--skip", entry[4]] if len(entry) > 4 else []
        baked = os.path.join("/tmp", f"{cls}_baked.json")
        print(f"== {cls}")
        cal_path = os.path.join(HERE, "roblox_rest", f"{cls}.json")
        cal = (cal_path, scale) if os.path.exists(cal_path) else None
        bake(os.path.join(src, file), baked, 30.0, extras, cal, fix)
        data = json.load(open(baked))
        renames = []
        for clip in data["clips"]:
            if clip["duration"] <= 0:
                continue
            renames += ["--rename", f"{clip['name']}={clip_name(clip['name'])}"]
        out = os.path.join(OUT, f"{cls}Clips.luau")
        subprocess.run([sys.executable, os.path.join(HERE, "emit_luau.py"), baked, out, "--scale", str(scale), *renames, *skip],
                       check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
