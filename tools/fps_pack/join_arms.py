#!/usr/bin/env python3
"""Join several skinned meshes into one mesh with one skin.

    python3 join_arms.py in.glb out.glb --mesh REGEX [--name Arms]

Roblox's importer builds each bone once and gives it to one mesh, so packs whose arms are
two skinned meshes with separate skins over a shared ancestor chain (the FPS Essentials
Kit rigs through FBX2glTF) come in with most of one arm's bones missing. Joining the
matching mesh nodes into one primitive under one skin (the union of their joints, inverse
binds kept per joint) gives Roblox a single skeleton, as a character rig has.
"""

import copy
import re
import sys

import numpy as np

from gltf_anim import Gltf
from rigidify import FLOAT, Writer

USHORT, UINT = 5123, 5125


def main():
    args = sys.argv[1:]
    src, dst = args[0], args[1]
    pattern = re.compile(args[args.index("--mesh") + 1])
    name = args[args.index("--name") + 1] if "--name" in args else "Arms"
    g = Gltf(src)
    doc = copy.deepcopy(g.doc)
    w = Writer(doc, g.buffers[0])
    picked = [i for i, n in enumerate(doc["nodes"]) if "mesh" in n and "skin" in n and pattern.search(n.get("name", ""))]
    if len(picked) < 2:
        raise SystemExit(f"need two or more skinned meshes, matched {len(picked)}")
    joints, ibms = [], []
    groups = {}
    for i in picked:
        node = g.doc["nodes"][i]
        skin = g.doc["skins"][node["skin"]]
        skin_ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4)
        remap = []
        for k, j in enumerate(skin["joints"]):
            if j not in joints:
                joints.append(j)
                ibms.append(skin_ibm[k])
            remap.append(joints.index(j))
        remap = np.array(remap)
        for prim in g.doc["meshes"][node["mesh"]]["primitives"]:
            a = prim["attributes"]
            group = groups.setdefault(prim.get("material"), {"pos": [], "nrm": [], "uv": [], "jnt": [], "wgt": [], "idx": [], "offset": 0})
            p = g.accessor(a["POSITION"])
            group["pos"].append(p)
            group["nrm"].append(g.accessor(a["NORMAL"]) if "NORMAL" in a else np.zeros_like(p))
            group["uv"].append(g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else np.zeros((len(p), 2)))
            group["jnt"].append(remap[g.accessor(a["JOINTS_0"]).astype(int)])
            group["wgt"].append(g.accessor(a["WEIGHTS_0"]))
            tris = g.accessor(prim["indices"]).astype(np.int64).reshape(-1) if "indices" in prim else np.arange(len(p))
            group["idx"].append(tris + group["offset"])
            group["offset"] += len(p)
    prims = []
    vertices = 0
    for material, group in groups.items():
        attrs = {
            "POSITION": w.add(np.vstack(group["pos"]).astype(np.float32), "VEC3", FLOAT, 34962, minmax=True),
            "NORMAL": w.add(np.vstack(group["nrm"]).astype(np.float32), "VEC3", FLOAT, 34962),
            "TEXCOORD_0": w.add(np.vstack(group["uv"]).astype(np.float32), "VEC2", FLOAT, 34962),
            "JOINTS_0": w.add(np.vstack(group["jnt"]).astype(np.uint16), "VEC4", USHORT, 34962),
            "WEIGHTS_0": w.add(np.vstack(group["wgt"]).astype(np.float32), "VEC4", FLOAT, 34962),
        }
        prim = {"attributes": attrs, "indices": w.add(np.concatenate(group["idx"]).astype(np.uint32).reshape(-1, 1), "SCALAR", UINT, 34963)}
        if material is not None:
            prim["material"] = material
        prims.append(prim)
        vertices += group["offset"]
    offset = vertices
    doc["meshes"].append({"name": name, "primitives": prims})
    ibm = np.stack(ibms).astype(np.float32).reshape(len(joints), 16)
    doc["skins"].append({"name": name, "joints": joints, "inverseBindMatrices": w.add(ibm, "MAT4", FLOAT)})
    doc["nodes"].append({"name": name, "mesh": len(doc["meshes"]) - 1, "skin": len(doc["skins"]) - 1})
    scene = doc["scenes"][doc.get("scene", 0)]
    scene["nodes"].append(len(doc["nodes"]) - 1)
    for i in picked:
        doc["nodes"][i].pop("mesh")
        doc["nodes"][i].pop("skin")
    w.write(dst)
    print(f"joined {len(picked)} meshes into {name}: {offset} vertices, {len(joints)} joints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
