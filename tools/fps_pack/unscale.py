#!/usr/bin/env python3
"""Take every node scale out of a pack, keeping its shape and its clips.

    python3 unscale.py in.glb out.glb

Roblox reads a joint's world scale from the skin's inverse bind and stretches the mesh by
it, so a rig whose nodes carry scale (3ds Max exports through Blender: armatures at 0.0197,
weapon controllers at 0.0342) imports many times too large and bakes huge deltas. With
uniform, constant scales a node's unscaled local transform is its translation times its
parents' accumulated scale and its own rotation, so rest transforms and translation
channels are multiplied by that factor, scale channels are dropped, skinned vertices move
to world space (posed by their old skin at rest) and every inverse bind becomes the inverse
of the joint's unscaled rest world. Non-uniform or animated scales are reported and refused.
"""

import copy
import sys

import numpy as np

from gltf_anim import Gltf, node_rest, parents, trs_matrix, world_matrices
from rigidify import FLOAT, Writer


def uniform(scale):
    s = np.asarray(scale, float)
    if np.ptp(s) > 1e-4 * max(abs(s).max(), 1e-9):
        raise SystemExit(f"non-uniform scale {s}")
    return float(s[0])


def main():
    src, dst = sys.argv[1], sys.argv[2]
    g = Gltf(src)
    if len(g.buffers) != 1:
        raise SystemExit("expected a single-buffer GLB")
    doc = copy.deepcopy(g.doc)
    w = Writer(doc, g.buffers[0])
    nodes = doc["nodes"]
    count = len(nodes)
    par = parents(doc)
    rest = {i: node_rest(n) for i, n in enumerate(nodes)}
    rest_world = world_matrices(doc, {i: trs_matrix(*rest[i]) for i in range(count)})

    own = {i: uniform(rest[i][2]) for i in range(count)}
    accumulated = {}

    def parent_scale(i):
        if i in accumulated:
            return accumulated[i]
        p = par.get(i)
        value = 1.0 if p is None else parent_scale(p) * own[p]
        accumulated[i] = value
        return value

    for anim in g.doc.get("animations", []):
        for ch in anim["channels"]:
            if ch["target"].get("path") == "scale":
                values = g.accessor(anim["samplers"][ch["sampler"]]["output"])
                node = ch["target"]["node"]
                if np.abs(values - own[node]).max() > 1e-4 * max(abs(own[node]), 1e-9):
                    raise SystemExit(f"animated scale on {nodes[node].get('name')}")

    def unscaled(m):
        out = m.copy()
        out[:3, :3] = m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0)[None, :]
        return out

    for skin_index, skin in enumerate(g.doc.get("skins", [])):
        joints = list(skin["joints"])
        chain = []
        for j in joints:
            p = par.get(j)
            while p is not None and p not in joints and p not in chain:
                chain.append(p)
                p = par.get(p)
        doc["skins"][skin_index]["joints"] = joints + chain
        if "inverseBindMatrices" in skin:
            old_ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        else:
            old_ibm = np.stack([np.eye(4)] * len(joints))
        rigid = skin.get("name") == "WeaponParts"
        posing = np.stack([np.eye(4) if rigid else rest_world[j] @ old_ibm[k] for k, j in enumerate(joints)])
        all_joints = joints + chain
        new_ibm = np.stack([np.linalg.inv(unscaled(rest_world[j])) for j in all_joints])
        doc["skins"][skin_index]["inverseBindMatrices"] = w.add(
            new_ibm.transpose(0, 2, 1).reshape(len(all_joints), 16).astype(np.float32), "MAT4", FLOAT)
        doc["skins"][skin_index].pop("skeleton", None)
        for i, node in enumerate(nodes):
            if node.get("skin") != skin_index or "mesh" not in node:
                continue
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
            p = par.get(i)
            if p is not None:
                nodes[p]["children"] = [c for c in nodes[p]["children"] if c != i]
                if not nodes[p]["children"]:
                    nodes[p].pop("children")
                scene = doc["scenes"][doc.get("scene", 0)]
                if i not in scene["nodes"]:
                    scene["nodes"].append(i)
            for key in ("translation", "rotation", "scale", "matrix"):
                node.pop(key, None)

    moved = {i for i, n in enumerate(nodes) if "mesh" in n and "skin" in n}
    for i, node in enumerate(nodes):
        if i in moved:
            continue
        t, r, s = rest[i]
        node.pop("matrix", None)
        node["translation"] = [float(x) for x in np.asarray(t, float) * parent_scale(i)]
        node["rotation"] = [float(x) for x in r]
        node.pop("scale", None)

    scaled = {}
    for anim in doc.get("animations", []):
        keep = []
        for ch in anim["channels"]:
            path = ch["target"].get("path")
            node = ch["target"].get("node")
            if path == "scale":
                continue
            if path == "translation" and node is not None:
                sampler = anim["samplers"][ch["sampler"]]
                key = (sampler["output"], parent_scale(node))
                if key not in scaled:
                    scaled[key] = w.add((g.accessor(sampler["output"]) * key[1]).astype(np.float32), "VEC3", FLOAT, minmax=True)
                sampler["output"] = scaled[key]
            keep.append(ch)
        anim["channels"] = keep

    w.write(dst)
    print(f"unscaled {src} -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
