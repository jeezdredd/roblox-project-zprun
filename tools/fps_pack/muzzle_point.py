#!/usr/bin/env python3
"""Find a first-person pack's muzzle from its geometry.

    python3 muzzle_point.py rig.glb --material REGEX [--clip Idle] [--time 0] [--bone NAME] [--forward +z|-z]

Poses the skinned primitives whose material matches REGEX at the clip time, takes the
camera forward along --forward in file space (Roblox imports these rigs turned 180 degrees
about Y, so its -Z look is the file's +Z, the default), keeps the vertices in the most
forward 1.5 percent of the weapon's length along its long axis and averages them into
the barrel tip. The tip and the barrel direction are carried back to the bind pose
through the skinning matrix of each vertex, which is the rest pose Roblox builds, and
printed in Roblox root space (X and Z negated) in file units; the game multiplies them by
RIG_SCALE and importScale.
With --bone the same point is printed in that joint's rest frame.
"""

import re
import sys

import numpy as np

from gltf_anim import Gltf, clips, local_at, node_rest, trs_matrix, world_matrices


def option(args, flag, default=None):
    return args[args.index(flag) + 1] if flag in args else default


def main():
    args = sys.argv[1:]
    g = Gltf(args[0])
    doc = g.doc
    pattern = re.compile(option(args, "--material", ".*"))
    clip_name = option(args, "--clip", "Idle")
    time = float(option(args, "--time", "0"))
    rest = {i: node_rest(n) for i, n in enumerate(doc["nodes"])}
    rest_world = world_matrices(doc, {i: trs_matrix(*rest[i]) for i in rest})
    clip = next((c for c in clips(g) if c["name"] == clip_name), None)
    if clip is None:
        raise SystemExit(f"no clip {clip_name}")
    posed_world = world_matrices(doc, {i: trs_matrix(*local_at(rest, clip["channels"], i, time)) for i in rest})

    bind_points, posed_points, skin_mats = [], [], []
    for node in doc["nodes"]:
        if "mesh" not in node or "skin" not in node:
            continue
        skin = doc["skins"][node["skin"]]
        joints = skin["joints"]
        ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        posing = np.stack([posed_world[j] @ ibm[k] for k, j in enumerate(joints)])
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            material = doc["materials"][prim["material"]].get("name", "") if "material" in prim else ""
            if not pattern.search(material):
                continue
            a = prim["attributes"]
            pos = g.accessor(a["POSITION"])
            jnt = g.accessor(a["JOINTS_0"]).astype(int)
            wts = g.accessor(a["WEIGHTS_0"])
            wts = wts / np.maximum(wts.sum(1, keepdims=True), 1e-9)
            blend = np.einsum("vk,vkab->vab", wts, posing[jnt])
            posed = np.einsum("vab,vb->va", blend, np.c_[pos, np.ones(len(pos))])[:, :3]
            bind_points.append(pos)
            posed_points.append(posed)
            skin_mats.append(blend)
    if not bind_points:
        raise SystemExit("no primitive matched --material")
    bind = np.vstack(bind_points)
    posed = np.vstack(posed_points)
    mats = np.concatenate(skin_mats)

    centre = posed.mean(0)
    _, _, vt = np.linalg.svd(posed - centre, full_matrices=False)
    axis = vt[0]
    forward = 1.0 if option(args, "--forward", "+z") == "+z" else -1.0
    if axis[2] * forward < 0:
        axis = -axis
    along = (posed - centre) @ axis
    length = along.max() - along.min()
    tip = along >= along.max() - 0.015 * length
    tip_posed = posed[tip].mean(0)
    tip_bind = bind[tip].mean(0)
    rotation = mats[tip].mean(0)[:3, :3]
    direction_bind = np.linalg.solve(rotation, axis)
    direction_bind /= np.linalg.norm(direction_bind)

    print(f"vertices {len(bind)}, tip vertices {int(tip.sum())}, weapon length {length:.4f}")
    print(f"idle tip {np.round(tip_posed, 4).tolist()} axis {np.round(axis, 4).tolist()}")
    flip = np.array([-1.0, 1.0, -1.0])
    print(f"rest muzzle position {np.round(tip_bind * flip, 4).tolist()}")
    print(f"rest muzzle direction {np.round(direction_bind * flip, 4).tolist()}")
    bone = option(args, "--bone")
    if bone:
        index = next(i for i, n in enumerate(doc["nodes"]) if n.get("name") == bone)
        inverse = np.linalg.inv(rest_world[index])
        local = inverse @ np.r_[tip_bind, 1.0]
        print(f"in {bone} rest frame {np.round(local[:3], 4).tolist()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
