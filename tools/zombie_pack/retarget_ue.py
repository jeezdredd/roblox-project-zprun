#!/usr/bin/env python3
"""Retargets clips made on Epic's UE5 Manny skeleton (the Fab "Zombies UEFN Manny"
animation pack, FBX converted to GLB with FBX2glTF) onto the zombie rigs that
build_zombie_anims.py bakes for, and writes them in the same KeyframeSequence format.

    python3 tools/zombie_pack/retarget_ue.py --anims DIR --rigs DIR --out DIR [--only Hazmat]

The pack is Fab content (Fab Standard License): the GLBs and the baked clips stay out of
the repository (assets/fab/ is gitignored); only this script is committed.

Method, per frame, in the rig file's own space:
  * G turns the Manny's heading onto the rig's (both glTF, Y up: a turn about Y laying
    the hip lines on each other), so a world-space rotation change of a Manny bone
    becomes D = G * (A_s(t) * B_s^-1) * G^-1 on the rig.
  * A aligns the rig's bind direction of each mapped bone (bone to its mapped child) with
    the Manny's: the minimal turn for limbs, a full frame (direction plus the left vector)
    for the hips and the chest. The rig bone's world rotation is D * A * B_t, so arms in a
    T-pose bind follow a Manny in an A-pose bind without lifting.
  * Unmapped rig bones keep their rest pose relative to their parent; positions come from
    the rest offsets turned by the parent's change, the hips from the Manny's pelvis path
    scaled by the leg lengths. "Bind" below is the node rest pose of the skin joints, the
    space the animated node worlds come in.
"""

import argparse
import glob
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "fps_pack"))
import build_zombie_anims as bza  # noqa: E402
from gltf_anim import Gltf, clips, local_at, node_name, node_rest, parents, trs_matrix, world_matrices  # noqa: E402

FINGERS = {"thumb": 3, "index": 3, "middle": 3, "ring": 3, "pinky": 3}

# Manny bone -> rig bone (rig names without the importer's _NN suffix)
MIXAMO = {"pelvis": "mixamorig:Hips", "spine_01": "mixamorig:Spine", "spine_03": "mixamorig:Spine1",
          "spine_05": "mixamorig:Spine2", "neck_01": "mixamorig:Neck", "head": "mixamorig:Head"}
for side, Side in (("l", "Left"), ("r", "Right")):
    MIXAMO.update({
        f"clavicle_{side}": f"mixamorig:{Side}Shoulder", f"upperarm_{side}": f"mixamorig:{Side}Arm",
        f"lowerarm_{side}": f"mixamorig:{Side}ForeArm", f"hand_{side}": f"mixamorig:{Side}Hand",
        f"thigh_{side}": f"mixamorig:{Side}UpLeg", f"calf_{side}": f"mixamorig:{Side}Leg",
        f"foot_{side}": f"mixamorig:{Side}Foot", f"ball_{side}": f"mixamorig:{Side}ToeBase",
    })
    for finger, count in FINGERS.items():
        for k in range(1, count + 1):
            MIXAMO[f"{finger}_0{k}_{side}"] = f"mixamorig:{Side}Hand{finger.capitalize()}{k}"

BIPED = {"pelvis": "Base HumanPelvis", "spine_01": "Base HumanSpine1", "spine_03": "Base HumanSpine2",
         "spine_05": "Base HumanRibcage", "neck_01": "Base HumanNeck", "head": "Base HumanHead",
         "clavicle_r": "Base HumanRArmCollarbone", "upperarm_r": "Base HumanRArmUpperarm",
         "lowerarm_r": "Base HumanRArmForearm", "hand_r": "Base HumanRArmPalm",
         "clavicle_l": "Base HumanLArmCollarbone", "upperarm_l": "Base HumanLArmUpperarm",
         "lowerarm_l": "Base HumanLArmForearm", "hand_l": "Base HumanLArmPalm",
         "thigh_r": "Base HumanRThigh", "calf_r": "Base HumanRCalf", "foot_r": "Base HumanRFoot",
         "ball_r": "Base HumanRDigit11",
         "thigh_l": "Base HumanLLegThigh", "calf_l": "Base HumanLLegCalf", "foot_l": "Base HumanLLegFoot",
         "ball_l": "Base HumanLLegDigit11"}
for side, S_ in (("l", "L"), ("r", "R")):
    BIPED[f"thumb_01_{side}"] = f"Base Human{S_}ArmDigit11"
    BIPED[f"thumb_02_{side}"] = f"Base Human{S_}ArmDigit12"
    for finger, digit in (("index", 2), ("middle", 3), ("ring", 4), ("pinky", 5)):
        for k in range(1, 4):
            BIPED[f"{finger}_0{k}_{side}"] = f"Base Human{S_}ArmDigit{digit}{k}"

RIGS = {
    "Hazmat": {"map": MIXAMO, "frames": {"pelvis": ("thigh_l", "thigh_r"), "spine_05": ("upperarm_l", "upperarm_r")}},
    "Walker": {"map": BIPED, "frames": {"pelvis": ("thigh_l", "thigh_r"), "spine_05": ("upperarm_l", "upperarm_r")}},
}

# Manny clip file -> (slot, loop, priority); the slots sit next to the rig's own
CLIPS = {
    "FN_Manny_Zombie_Idle": ("idle_ue", True, "idle"),
    "FN_Manny_Zombie_Walk": ("walk_ue", True, "movement"),
    "FN_Manny_Zombie_Run": ("run_ue", True, "movement"),
    "FN_Manny_Zombie_Crawl": ("crawl_ue", True, "movement"),
    "FN_Manny_Zombie_Attack": ("attack_ue", False, "action"),
    "FN_Manny_Zombie_Death": ("death_ue", False, "action2"),
}


def unit_rot(m):
    r = m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0)[None, :]
    u, _, vt = np.linalg.svd(r)
    out = u @ vt
    if np.linalg.det(out) < 0:
        u[:, -1] *= -1
        out = u @ vt
    return out


def frame(x_hint, y):
    y = y / np.linalg.norm(y)
    x = x_hint - y * (x_hint @ y)
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def min_turn(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-8:
        if c > 0:
            return np.eye(3)
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def skin_bind(g, rest_world):
    bind = {}
    for ni, node in enumerate(g.doc["nodes"]):
        if "mesh" in node and "skin" in node:
            skin = g.doc["skins"][node["skin"]]
            ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
            for j, m in zip(skin["joints"], ibm):
                bind.setdefault(j, rest_world[ni] @ np.linalg.inv(m))
    return bind


class Source:
    def __init__(self, path):
        self.g = Gltf(path)
        doc = self.g.doc
        self.doc = doc
        self.rest = {i: node_rest(n) for i, n in enumerate(doc["nodes"])}
        self.rest_local = {i: trs_matrix(*self.rest[i]) for i in self.rest}
        self.rest_world = world_matrices(doc, self.rest_local)
        # the reference pose is the node rest pose of the skin joints: the same space the
        # animated node worlds come in (a skin's bind can sit under a scaled mesh node)
        self.bind = {j: self.rest_world[j] for j in skin_bind(self.g, self.rest_world)}
        self.idx = {}
        for j in self.bind:
            self.idx[node_name(doc, j)] = j
        clip = max(clips(self.g), key=lambda c: c["duration"])
        self.duration = clip["duration"]
        self.by_node = {}
        for ch in clip["channels"]:
            self.by_node.setdefault(ch[0], []).append(ch)

    def pos(self, name):
        return self.bind[self.idx[name]][:3, 3]

    def world_at(self, t):
        loc = dict(self.rest_local)
        for node, chans in self.by_node.items():
            loc[node] = trs_matrix(*local_at(self.rest, chans, node, t))
        return world_matrices(self.doc, loc)


def retarget(ctx, spec, src):
    doc = ctx["doc"]
    # node rest worlds of the skin joints: build_zombie_anims feeds node worlds through P
    bind_t = {j: ctx["rest_world"][j] for j in ctx["bind"]}
    par = parents(doc)
    base = {}
    for j in bind_t:
        base[re.sub(r"_\d+$", "", node_name(doc, j))] = j
    mapping = {}
    for s_name, t_name in spec["map"].items():
        if s_name in src.idx and t_name in base:
            mapping[base[t_name]] = s_name
    rev = {s: t for t, s in mapping.items()}

    def tpos(j):
        return bind_t[j][:3, 3]

    # global frame: both files are glTF (Y up, facing +Z; build_zombie_anims' FLIP makes
    # file +Z the rig's forward in Roblox), so the Manny's world changes carry over as they
    # are. The rig's rest pose can be a posed stance (the Hazmat leans, turns and steps
    # out), so nothing is measured from it for the heading. `yaw` (degrees) is a per-rig
    # escape hatch.
    yaw = np.radians(spec.get("yaw", 0.0))
    c, s_ = np.cos(yaw), np.sin(yaw)
    G = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    # leg length (hip to knee to ankle) rather than hip height: a posed rest crouches
    def leg(pos, side):
        return np.linalg.norm(pos(f"calf_{side}") - pos(f"thigh_{side}")) + np.linalg.norm(pos(f"foot_{side}") - pos(f"calf_{side}"))
    hip_s = leg(src.pos, "l")
    hip_t = leg(lambda n: tpos(rev[n]), "l")
    ratio = hip_t / hip_s

    # the mapped child that gives each mapped rig bone its direction
    def mapped_child(j):
        best = None
        stack = [c for c in range(len(doc["nodes"])) if par.get(c) == j]
        while stack:
            c = stack.pop(0)
            if c in mapping:
                if best is None or mapping[c].startswith("middle_01") or mapping[c].startswith("spine") \
                        or mapping[c] in ("neck_01", "head", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r",
                                          "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"):
                    if best is None or not (mapping[best].startswith("middle_01") or mapping[best].startswith("spine")
                                            or mapping[best] in ("neck_01", "head")):
                        best = c
                continue
            stack.extend(x for x in range(len(doc["nodes"])) if par.get(x) == c)
        return best

    B_t = {j: unit_rot(bind_t[j]) for j in bind_t}
    B_s = {j: unit_rot(src.bind[j]) for j in src.bind}
    # parents first
    depth = {}
    for j in bind_t:
        d, k = 0, j
        while par.get(k) is not None:
            k = par[k]
            d += 1
        depth[j] = d
    order = sorted(bind_t, key=lambda j: depth[j])

    align = {}
    for j in order:
        if j not in mapping:
            continue
        s_name = mapping[j]
        c = mapped_child(j)
        if s_name in spec["frames"]:
            a, b = spec["frames"][s_name]
            child_s = src.pos("spine_01") if s_name == "pelvis" else src.pos("neck_01")
            child_t = tpos(rev["spine_01"]) if s_name == "pelvis" else tpos(rev["neck_01"])
            f_s = frame(G @ (src.pos(a) - src.pos(b)), G @ (child_s - src.pos(s_name)))
            f_t = frame(tpos(rev[a]) - tpos(rev[b]), child_t - tpos(j))
            align[j] = f_s @ f_t.T
        elif c is not None:
            d_t = tpos(c) - tpos(j)
            d_s = G @ (src.pos(mapping[c]) - src.pos(s_name))
            align[j] = min_turn(d_t, d_s)
        else:
            k = par.get(j)
            while k is not None and k not in align:
                k = par.get(k)
            align[j] = align[k] if k is not None else np.eye(3)

    pelvis_t = rev["pelvis"]
    pelvis_bind_s = src.pos("pelvis")
    scale_cols = {j: np.linalg.norm(bind_t[j][:3, :3], axis=0) for j in bind_t}

    def world_at(t):
        gs = src.world_at(t)
        rot = {}
        out = dict(ctx["rest_world"])
        for j in order:
            p = par.get(j)
            if j in mapping:
                s = src.idx[mapping[j]]
                D = G @ (unit_rot(gs[s]) @ B_s[s].T) @ G.T
                R = D @ align[j] @ B_t[j]
            elif p in rot:
                R = rot[p] @ B_t[p].T @ B_t[j]
            else:
                R = B_t[j]
            rot[j] = R
            if j == pelvis_t:
                pos = tpos(j) + G @ (gs[src.idx["pelvis"]][:3, 3] - pelvis_bind_s) * ratio
            elif p in rot:
                pos = out[p][:3, 3] + rot[p] @ B_t[p].T @ (tpos(j) - tpos(p))
            else:
                pos = tpos(j)
            m = np.eye(4)
            m[:3, :3] = R * scale_cols[j][None, :]
            m[:3, 3] = pos
            out[j] = m
        return out

    return world_at, len(mapping), ratio


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--anims", required=True)
    ap.add_argument("--rigs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    bones = json.load(open(os.path.join(HERE, "roblox_bones.json")))
    meta = {}
    for rig_name, spec in RIGS.items():
        if args.only and rig_name != args.only:
            continue
        ctx = bza.setup_rig(bza.RIGS[rig_name], args.rigs, bones[rig_name])
        out_dir = os.path.join(args.out, rig_name.lower())
        meta[rig_name] = {}
        for path in sorted(glob.glob(os.path.join(args.anims, "*.glb"))):
            stem = os.path.splitext(os.path.basename(path))[0]
            if stem not in CLIPS:
                continue
            slot, loop, priority = CLIPS[stem]
            src = Source(path)
            world_at, mapped, ratio = retarget(ctx, spec, src)
            print(f"{rig_name} <- {stem}: {mapped} bones mapped, hip ratio {ratio:.4f}")
            meta[rig_name][slot] = bza.bake_clip(ctx, rig_name, slot, loop, priority, src.duration, world_at, out_dir, stem)
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "clips.json"), "w") as handle:
        json.dump(meta, handle, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
