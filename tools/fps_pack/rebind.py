#!/usr/bin/env python3
"""Move a pack's bind pose to a frame of one of its clips.

    python3 rebind.py in.glb out.glb [--clip Idle] [--time 0]

Some packs bind their skins far from where the animations hold them (the FPS Essentials
Kit rigs from 3ds Max bind at the scene origin while every clip places the arms about
ten metres away at the Max camera), so every baked delta carries that offset and
overflows emit_luau.py's int16 range. glTF channels store absolute local transforms,
so the bind can move without touching the clips: each skinned vertex is posed at the
chosen frame, each joint's inverse bind becomes old_ibm * rest_world * pose_world^-1
(this keeps whatever scale convention the skin used, rigidify.py's unit included), and
every node's rest transform becomes its pose at that frame.
"""

import copy
import sys

import numpy as np

from gltf_anim import Gltf, clips, local_at, node_rest, trs_matrix, world_matrices
from rigidify import FLOAT, Writer


def main():
    args = sys.argv[1:]
    src, dst = args[0], args[1]
    clip_name = args[args.index("--clip") + 1] if "--clip" in args else "Idle"
    time = float(args[args.index("--time") + 1]) if "--time" in args else 0.0
    g = Gltf(src)
    if len(g.buffers) != 1:
        raise SystemExit("expected a single-buffer GLB")
    doc = copy.deepcopy(g.doc)
    w = Writer(doc, g.buffers[0])
    nodes = doc["nodes"]
    count = len(nodes)
    rest = {i: node_rest(n) for i, n in enumerate(nodes)}
    rest_world = world_matrices(doc, {i: trs_matrix(*rest[i]) for i in range(count)})
    clip = next((c for c in clips(g) if c["name"] == clip_name), None)
    if clip is None:
        raise SystemExit(f"no clip named {clip_name}")
    pose_trs = {i: local_at(rest, clip["channels"], i, time) for i in range(count)}
    pose_world = world_matrices(doc, {i: trs_matrix(*pose_trs[i]) for i in range(count)})
    names = {n.get("name", ""): i for i, n in enumerate(nodes)}
    center_name = args[args.index("--center") + 1] if "--center" in args else "[Helper] Camera.Point"
    center = pose_world[names[center_name]][:3, 3].copy() if center_name in names else np.zeros(3)
    shift = np.eye(4)
    shift[:3, 3] = -center
    pose_world = {i: shift @ m for i, m in pose_world.items()}
    has_parent = {c for n in nodes for c in n.get("children", [])}
    roots = {i for i in range(count) if i not in has_parent}

    posings = {}
    world_space = {}
    for skin_index, skin in enumerate(g.doc.get("skins", [])):
        joints = skin["joints"]
        old_ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        rigid = skin.get("name") == "WeaponParts"
        world_space[skin_index] = not rigid
        if rigid:
            posings[skin_index] = np.stack([pose_world[j] @ np.linalg.inv(rest_world[j]) for j in joints])
            new_ibm = np.stack([old_ibm[k] @ rest_world[j] @ np.linalg.inv(pose_world[j]) for k, j in enumerate(joints)])
        else:
            posings[skin_index] = np.stack([pose_world[j] @ old_ibm[k] for k, j in enumerate(joints)])
            new_ibm = np.stack([np.linalg.inv(pose_world[j]) for j in joints])
        doc["skins"][skin_index]["inverseBindMatrices"] = w.add(
            new_ibm.transpose(0, 2, 1).reshape(len(joints), 16).astype(np.float32), "MAT4", FLOAT)

    scene = doc["scenes"][doc.get("scene", 0)]
    for index, node in enumerate(nodes):
        if "mesh" not in node or "skin" not in node:
            continue
        posing = posings[node["skin"]]
        if world_space[node["skin"]]:
            for other in nodes:
                if index in other.get("children", []):
                    other["children"].remove(index)
                    if not other["children"]:
                        other.pop("children")
            if index not in scene["nodes"]:
                scene["nodes"].append(index)
            pose_trs[index] = (np.zeros(3), np.array([0.0, 0.0, 0.0, 1.0]), np.ones(3))
        mesh = copy.deepcopy(g.doc["meshes"][node["mesh"]])
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            jidx = g.accessor(attrs["JOINTS_0"]).astype(int)
            wts = g.accessor(attrs["WEIGHTS_0"])
            wts = wts / np.maximum(wts.sum(1, keepdims=True), 1e-9)
            blend = np.einsum("vk,vkab->vab", wts, posing[jidx])
            pos = g.accessor(attrs["POSITION"])
            posed = np.einsum("vab,vb->va", blend, np.c_[pos, np.ones(len(pos))])[:, :3]
            attrs["POSITION"] = w.add(posed.astype(np.float32), "VEC3", FLOAT, 34962, minmax=True)
            if "NORMAL" in attrs:
                nrm = np.einsum("vab,vb->va", blend[:, :3, :3], g.accessor(attrs["NORMAL"]))
                nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
                attrs["NORMAL"] = w.add(nrm.astype(np.float32), "VEC3", FLOAT, 34962)
            if "TANGENT" in attrs:
                tan = g.accessor(attrs["TANGENT"])
                t3 = np.einsum("vab,vb->va", blend[:, :3, :3], tan[:, :3])
                t3 /= np.maximum(np.linalg.norm(t3, axis=1, keepdims=True), 1e-9)
                attrs["TANGENT"] = w.add(np.c_[t3, tan[:, 3:4]].astype(np.float32), "VEC4", FLOAT, 34962)
        doc["meshes"][node["mesh"]] = mesh

    for i, node in enumerate(nodes):
        t, r, s = pose_trs[i]
        if i in roots:
            t = np.asarray(t, float) - center
        node.pop("matrix", None)
        node["translation"] = [float(x) for x in t]
        node["rotation"] = [float(x) for x in r]
        node["scale"] = [float(x) for x in s]

    shifted = {}
    for anim in doc.get("animations", []):
        for ch in anim["channels"]:
            tgt = ch["target"]
            if tgt.get("path") != "translation" or tgt.get("node") not in roots:
                continue
            sampler = anim["samplers"][ch["sampler"]]
            key = sampler["output"]
            if key not in shifted:
                values = g.accessor(key) - center
                shifted[key] = w.add(values.astype(np.float32), "VEC3", FLOAT, minmax=True)
            sampler["output"] = shifted[key]
    print(f"centred on {center_name if center_name in names else 'origin'} at {np.round(center, 3)}")

    w.write(dst)
    print(f"rebound {src} at {clip_name} t={time:g} -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
