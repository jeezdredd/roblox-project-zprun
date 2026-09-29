#!/usr/bin/env python3
"""Turn the clips of the Sketchfab zombie packs into Roblox KeyframeSequences (.rbxmx) that
animate the Bones Roblox built when the rig was imported. No Blender.

    python3 tools/zombie_pack/build_zombie_anims.py [--src ~/Downloads/zombie_packs] [--only Walker]

For every rig in RIGS:
  * roblox_bones.json holds the imported Bone tree (names, parents, local CFrames),
    read in Studio after the Model upload.
  * The file's bind pose (skinned mesh node world x inverse bind matrix) is fitted onto
    those bones with one similarity M (checked: residual 0 for all three packs).
  * N maps the file's node space onto the rig: the glTF 180-degree turn about Y, the
    upload's UnitScale and M's translation (the holder part's offset).
  * Per frame and bone: target = N * G(t) * bind^-1 * M^-1 * restWorld, and the Pose
    CFrame (Bone.Transform) = boneCFrame^-1 * parentTarget^-1 * target.
Loops lose their horizontal root travel; the travel per second, or the planted foot's
speed for in-place clips, is written to clips.json as the clip's ground speed so the
server can set the playback speed that keeps the feet planted.
Poses are named after the instance tree: HumanoidRootPart > Rig > bones (ZombieFactory
renames the part that holds the Bones to "Rig").
"""

import argparse
import json
import os
import sys
import uuid

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "fps_pack"))
from gltf_anim import Gltf, clips, decompose, local_at, node_name, node_rest, trs_matrix, world_matrices  # noqa: E402

FLIP = np.diag([-1.0, 1.0, -1.0, 1.0])
OUT = os.path.join(ROOT, "assets", "animation", "zombie_sf")
FPS = 20

# rig -> glb, upload UnitScale, foot bone name fragments, clips: source -> (slot, loop, priority)
RIGS = {
    "Walker": {
        "file": "z_pxl.glb",
        "unit": 2.76,
        "feet": ("LLegFoot", "RFoot"),
        "clips": {
            "Idle": ("idle", True, "idle"),
            "Walk": ("walk_a", True, "movement"),
            "Walk1": ("walk_b", True, "movement"),
            "Run": ("run", True, "movement"),
            "Attack": ("attack", False, "action"),
            "FallingBack": ("death_back", False, "action2"),
            "FallingForward": ("death_forward", False, "action2"),
        },
    },
    "Hazmat": {
        "file": "z_hazmat.glb",
        "unit": 3.05,
        "feet": ("LeftFoot", "RightFoot"),
        "clips": {
            "Zombie_Idle": ("idle", True, "idle"),
            "Zombie_Walk_Root": ("walk_a", True, "movement"),
            "Zombie_EnemySpotted": ("spotted", False, "action"),
            "Zombie_Skill": ("attack", False, "action"),
        },
    },
    "Ghoul": {
        "file": "z_stas.glb",
        "unit": 2.04,
        "feet": ("Bone.016.L", "Bone.016.R"),
        "clips": {
            "STATIK": ("idle", True, "idle"),
            "STATIK2": ("idle_b", True, "idle"),
            "step": ("walk_a", True, "movement"),
            "spid step": ("walk_b", True, "movement"),
            "run": ("run", True, "movement"),
            "run.002": ("run_b", True, "movement"),
            "ATACK1": ("attack", False, "action"),
            "ATACK2": ("attack_b", False, "action"),
            "DEAD1": ("death_back", False, "action2"),
            "DEAD2": ("death_forward", False, "action2"),
            "FTAC4": ("hit", False, "action3"),
        },
    },
}

PRIORITY = {"idle": 0, "movement": 1, "action": 2, "action2": 3, "action3": 4, "action4": 5}


def cf(c):
    m = np.eye(4)
    m[:3, 3] = c[:3]
    m[:3, :3] = np.array(c[3:]).reshape(3, 3)
    return m


def rigid(m):
    """Orthonormal rotation + translation part of a similarity matrix."""
    u, _, vt = np.linalg.svd(m[:3, :3])
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    out = np.eye(4)
    out[:3, :3] = r
    out[:3, 3] = m[:3, 3]
    return out


def fit_similarity(src, dst):
    mu_s, mu_d = src.mean(0), dst.mean(0)
    cov = (dst - mu_d).T @ (src - mu_s) / len(src)
    U, S, Vt = np.linalg.svd(cov)
    D = np.diag([1, 1, np.sign(np.linalg.det(U @ Vt))])
    R = U @ D @ Vt
    s = np.trace(np.diag(S) @ D) / ((src - mu_s) ** 2).sum(1).mean()
    M = np.eye(4)
    M[:3, :3] = s * R
    M[:3, 3] = mu_d - s * R @ mu_s
    resid = np.sqrt((((M[:3, :3] @ src.T).T + M[:3, 3] - dst) ** 2).sum(1).mean())
    return M, s, resid


def fmt(v):
    text = f"{v:.5g}"
    return "0" if text in ("-0", "0") else text


def cframe_xml(m):
    vals = [*m[:3, 3], *m[:3, :3].reshape(-1)]
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    return "".join(f"<{n}>{fmt(v)}</{n}>" for n, v in zip(names, vals))


def ref():
    return "RBX" + uuid.uuid4().hex.upper()


def pose_xml(name, m, weight, children, depth):
    ind = " " * depth
    head = (f'{ind}<Item class="Pose" referent="{ref()}"><Properties><string name="Name">{name}</string>'
            f'<CoordinateFrame name="CFrame">{cframe_xml(m)}</CoordinateFrame><float name="Weight">{weight}</float>'
            f'<token name="EasingStyle">0</token><token name="EasingDirection">0</token></Properties>')
    if not children:
        return head + "</Item>"
    return head + "\n" + "\n".join(children) + f"\n{ind}</Item>"


def build_rig(rig_name, cfg, src_dir, bones_json):
    g = Gltf(os.path.join(src_dir, cfg["file"]))
    doc = g.doc
    n_nodes = len(doc["nodes"])
    rest = {i: node_rest(nd) for i, nd in enumerate(doc["nodes"])}
    rest_local = {i: trs_matrix(*rest[i]) for i in range(n_nodes)}
    rest_world = world_matrices(doc, rest_local)
    names = {node_name(doc, i): i for i in range(n_nodes)}
    bind = {}
    for ni, node in enumerate(doc["nodes"]):
        if "mesh" in node and "skin" in node:
            skin = doc["skins"][node["skin"]]
            ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
            for j, m in zip(skin["joints"], ibm):
                bind.setdefault(j, rest_world[ni] @ np.linalg.inv(m))

    bones = bones_json["bones"]
    local = [cf(c) for _, _, c in bones]
    parent = [p - 1 for _, p, _ in bones]
    world = []
    for i in range(len(bones)):
        world.append(local[i] if parent[i] < 0 else world[parent[i]] @ local[i])
    joint = [names.get(b[0]) for b in bones]

    common = [i for i, j in enumerate(joint) if j is not None and j in bind and "rootJoint" not in bones[i][0]]
    src = np.array([bind[joint[i]][:3, 3] for i in common])
    dst = np.array([world[i][:3, 3] for i in common])
    M, s_bind, resid = fit_similarity(src, dst)
    unit = cfg["unit"]
    N = FLIP.copy()
    N[:3, :3] *= unit
    N[:3, 3] = M[:3, 3]
    print(f"{rig_name}: {len(common)} bones fitted, bind scale {s_bind:.4f}, residual {resid:.5f}")
    Minv = np.linalg.inv(M)
    # per bone: target(t) = N * G(t) * bind^-1 * M^-1 * restWorld = N * G(t) * P
    P = {}
    for i, j in enumerate(joint):
        if j is not None and j in bind:
            P[i] = np.linalg.inv(bind[j]) @ Minv @ world[i]

    feet = [i for i, b in enumerate(bones) if any(f in b[0] for f in cfg["feet"])]
    results = {}
    os.makedirs(os.path.join(OUT, rig_name.lower()), exist_ok=True)
    by_name = {c["name"]: c for c in clips(g)}
    for source, (slot, loop, priority) in cfg["clips"].items():
        clip = by_name.get(source)
        if clip is None:
            print(f"  missing clip {source!r}")
            continue
        duration = clip["duration"]
        count = max(1, int(round(duration * FPS)))
        by_node = {}
        for ch in clip["channels"]:
            by_node.setdefault(ch[0], []).append(ch)
        frames = []
        for k in range(count + 1):
            t = min(k / FPS, duration)
            loc = dict(rest_local)
            for node, chans in by_node.items():
                loc[node] = trs_matrix(*local_at(rest, chans, node, t))
            gw = world_matrices(doc, loc)
            targets = {}
            for i, j in enumerate(joint):
                if i in P:
                    targets[i] = rigid(N @ gw[j] @ P[i])
                else:
                    targets[i] = world[i] if parent[i] < 0 else None
            frames.append((t, targets))
        # bones without a file joint follow their parent rigidly
        for _, targets in frames:
            for i in range(len(bones)):
                if targets[i] is None:
                    targets[i] = targets[parent[i]] @ local[i]

        # root travel: the lowest-depth bone that moves is the hips
        depth = []
        for i in range(len(bones)):
            depth.append(0 if parent[i] < 0 else depth[parent[i]] + 1)
        hips = min((i for i in P if "rootJoint" not in bones[i][0]), key=lambda i: (depth[i], i))
        hips_path = np.array([f[1][hips][:3, 3] for f in frames])
        travel = hips_path[-1] - hips_path[0]
        travel[1] = 0
        speed = 0.0
        if loop and duration > 0:
            horizontal = np.linalg.norm(travel)
            if horizontal > 0.3:
                speed = horizontal / duration
                for k, (t, targets) in enumerate(frames):
                    shift = np.eye(4)
                    shift[:3, 3] = -travel * (t / duration)
                    for i in targets:
                        targets[i] = shift @ targets[i]
            elif feet:
                speeds = []
                for fi in feet:
                    path = np.array([f[1][fi][:3, 3] for f in frames])
                    low = path[:, 1].min()
                    for k in range(1, len(path)):
                        if path[k, 1] < low + 0.15 * unit and path[k - 1, 1] < low + 0.15 * unit:
                            d = path[k] - path[k - 1]
                            speeds.append(np.hypot(d[0], d[2]) * FPS)
                if speeds:
                    speed = float(np.median(speeds))

        # Transform per bone; drop bones that never move with no moving descendant
        transforms = []
        for t, targets in frames:
            row = []
            for i in range(len(bones)):
                parent_world = np.eye(4) if parent[i] < 0 else targets[parent[i]]
                row.append(np.linalg.inv(local[i]) @ np.linalg.inv(parent_world) @ targets[i])
            transforms.append(row)
        moving = [False] * len(bones)
        for i in range(len(bones)):
            arr = np.array([row[i] for row in transforms])
            if np.abs(arr - np.eye(4)).max() > 1e-4:
                moving[i] = True
        for i in reversed(range(len(bones))):
            if moving[i] and parent[i] >= 0:
                moving[parent[i]] = True
        children = {i: [c for c in range(len(bones)) if parent[c] == i] for i in range(-1, len(bones))}

        def pose_tree(i, row, depth):
            kids = [pose_tree(c, row, depth + 1) for c in children[i] if moving[c]]
            return pose_xml(bones[i][0], row[i], 1, kids, depth)

        lines = ['<roblox version="4">',
                 f'<Item class="KeyframeSequence" referent="{ref()}"><Properties><string name="Name">{rig_name.lower()}_{slot}</string>'
                 f'<bool name="Loop">{"true" if loop else "false"}</bool><token name="Priority">{PRIORITY[priority]}</token></Properties>']
        for (t, _), row in zip(frames, transforms):
            rig_children = [pose_tree(c, row, 3) for c in children[-1] if moving[c]]
            rig_pose = pose_xml("Rig", np.eye(4), 1, rig_children, 2)
            root_pose = pose_xml("HumanoidRootPart", np.eye(4), 0, [rig_pose], 1)
            lines.append(f'<Item class="Keyframe" referent="{ref()}"><Properties><string name="Name">Keyframe</string>'
                         f'<float name="Time">{fmt(t)}</float></Properties>')
            lines.append(root_pose)
            lines.append("</Item>")
        lines += ["</Item>", "</roblox>"]
        path = os.path.join(OUT, rig_name.lower(), f"{slot}.rbxmx")
        with open(path, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        size = os.path.getsize(path)
        results[slot] = {"source": source, "duration": round(duration, 4), "loop": loop,
                         "groundSpeed": round(speed, 3), "bones": sum(moving)}
        print(f"  {slot:14s} <- {source:20s} {duration:5.2f}s loop={loop!s:5s} speed={speed:5.2f} "
              f"bones={sum(moving)} {size / 1024:.0f} KB")
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="~/Downloads/zombie_packs")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    src = os.path.expanduser(args.src)
    bones = json.load(open(os.path.join(HERE, "roblox_bones.json")))
    meta_path = os.path.join(OUT, "clips.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for name, cfg in RIGS.items():
        if args.only and name != args.only:
            continue
        meta[name] = build_rig(name, cfg, src, bones[name])
    os.makedirs(OUT, exist_ok=True)
    with open(meta_path, "w") as handle:
        json.dump(meta, handle, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
