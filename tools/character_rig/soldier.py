"""Third-person soldier body: the Mixamo "Swat Guy" split into the 15 R15 parts.

No Blender. Reuses the FBX reader, skinning and texture packing in tools/arms_rig:
  1. the arm chains are skinned from the bind T-pose to hang straight down (upper arm,
     forearm and hand each point down), fingers take the same grip as the first-person
     arms; linear blend skinning keeps the shoulders smooth,
  2. every triangle goes to the R15 part whose bones carry most of its weight, and seam
     triangles (a vertex with at least SEAM_WEIGHT on another part) go to both, so a bent
     joint does not open a gap,
  3. four texture groups (head, torso, arms, legs) are repacked into 1024 atlases from the
     two 4096 Mixamo materials: colour, normal and roughness (1 - glossiness).

Output in assets/character/soldier/source/:
  <Part>.glb            one mesh per R15 part, centred on its bounding box, in the Mixamo
                        axes (+Z forward) because the Roblox glTF importer turns meshes
                        180 degrees about Y, which lands them facing -Z like R15
  <Group>_<Map>.png     atlases, Group in Head/Torso/Arms/Legs, Map in Color/Normal/Roughness
  rig.json              studs per cm, part centres and sizes and joint pivots in Roblox
                        character space (feet at y = 0, facing -Z), hip height, and the
                        grip point of each fist relative to its hand part

    python3 tools/character_rig/soldier.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "arms_rig"))

from build import GRIPS, pack, skin_normals, src, write_glb  # noqa: E402
from islands import uv_islands  # noqa: E402
from pose import *  # noqa: E402,F401,F403

STUDS_PER_CM = 0.03       # 181 cm soldier -> 5.4 studs, close to the stock R15 height
ATLAS = 1024
MARGIN = 8
SEAM_WEIGHT = 0.4
OUT = os.path.join(ROOT, "assets", "character", "soldier", "source")

PART_OF = {
    "Hips": "LowerTorso", "Spine": "LowerTorso",
    "Spine1": "UpperTorso", "Spine2": "UpperTorso", "LeftShoulder": "UpperTorso", "RightShoulder": "UpperTorso",
    "Neck": "Head", "Head": "Head", "HeadTop_End": "Head",
}
for _s in ("Left", "Right"):
    PART_OF.update({
        f"{_s}Arm": f"{_s}UpperArm", f"{_s}ForeArm": f"{_s}LowerArm",
        f"{_s}UpLeg": f"{_s}UpperLeg", f"{_s}Leg": f"{_s}LowerLeg",
        f"{_s}Foot": f"{_s}Foot", f"{_s}ToeBase": f"{_s}Foot", f"{_s}Toe_End": f"{_s}Foot",
    })
PARTS = ["HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
         "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
BODY = PARTS[1:]
GROUPS = {
    "Head": ["Head"],
    "Torso": ["UpperTorso", "LowerTorso"],
    "Arms": ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"],
    "Legs": ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"],
}


def part_of(bone):
    b = bone.replace("mixamorig:", "")
    if b in PART_OF:
        return PART_OF[b]
    for s in ("Left", "Right"):
        if b.startswith(s + "Hand"):
            return s + "Hand"
    raise KeyError(b)


def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(np.dot(a, b)); s = np.linalg.norm(v)
    if s < 1e-9:
        return np.eye(3)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K * ((1 - c) / (s * s))


def about(R, pivot):
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = pivot - R @ pivot
    return M


def apply(M, p):
    return M[:3, :3] @ p + M[:3, 3]


def rest_pose():
    """bind -> arms-down deformation per bone, and the posed joint positions (cm)"""
    D = np.tile(np.eye(4), (len(BONES), 1, 1))
    joints = {}
    down = np.array([0.0, -1.0, 0.0])
    for side in ("Left", "Right"):
        fingers = pose_side(side, GRIPS[side]["curls"], GRIPS[side]["thumb"])
        sh, el, wr, mid = P(side + "Arm"), P(side + "ForeArm"), P(side + "Hand"), P(side + "HandMiddle1")
        M1 = about(rot_between(el - sh, down), sh)
        el1, wr1 = apply(M1, el), apply(M1, wr)
        M2 = about(rot_between(wr1 - el1, down), el1) @ M1
        wr2, mid2 = apply(M2, wr), apply(M2, mid)
        M3 = about(rot_between(mid2 - wr2, down), wr2) @ M2
        D[BI[f"mixamorig:{side}Arm"]] = M1
        D[BI[f"mixamorig:{side}ForeArm"]] = M2
        for b in BONES:
            if b.startswith(f"mixamorig:{side}Hand"):
                D[BI[b]] = M3 @ fingers[BI[b]]
        # the fist's centre, where a weapon grip sits (same point as the first-person arms)
        n = palm_normal(side)
        pc = (P(side + "HandIndex1") + P(side + "HandPinky1")) / 2 * 0.6 + wr * 0.4
        joints[side + "Grip"] = apply(M3, pc + n * GRIPS[side]["depth"])
        joints[side + "Shoulder"] = sh
        joints[side + "Elbow"] = el1
        joints[side + "Wrist"] = wr2
        joints[side + "Hip"] = P(side + "UpLeg")
        joints[side + "Knee"] = P(side + "Leg")
        joints[side + "Ankle"] = P(side + "Foot")
    joints["Root"] = P("Hips")
    joints["Waist"] = P("Spine1")
    joints["Neck"] = P("Neck")
    return D, joints


JOINT_PARTS = {
    "Root": ("HumanoidRootPart", "LowerTorso"), "Waist": ("LowerTorso", "UpperTorso"), "Neck": ("UpperTorso", "Head"),
}
for _s in ("Left", "Right"):
    JOINT_PARTS.update({
        f"{_s}Shoulder": ("UpperTorso", f"{_s}UpperArm"), f"{_s}Elbow": (f"{_s}UpperArm", f"{_s}LowerArm"),
        f"{_s}Wrist": (f"{_s}LowerArm", f"{_s}Hand"), f"{_s}Hip": ("LowerTorso", f"{_s}UpperLeg"),
        f"{_s}Knee": (f"{_s}UpperLeg", f"{_s}LowerLeg"), f"{_s}Ankle": (f"{_s}LowerLeg", f"{_s}Foot"),
    })


def to_roblox(p, ground):
    """Mixamo cm (+Z forward) -> Roblox studs (-Z forward), feet at y = 0"""
    q = np.array(p, float) * STUDS_PER_CM
    q[..., 1] -= ground * STUDS_PER_CM
    q[..., 0] *= -1; q[..., 2] *= -1
    return q


def main():
    os.makedirs(OUT, exist_ok=True)
    D, joints = rest_pose()
    Vp = skin(D)
    Np = skin_normals(D)
    ground = float(Vp[:, 1].min())

    # per-vertex weight per R15 part
    Wp = np.zeros((len(V), len(BODY)))
    col = {p: i for i, p in enumerate(BODY)}
    for b in BONES:
        Wp[:, col[part_of(b)]] += Wm[:, BI[b]]
    tri_w = Wp[tri_v]                      # (T,3,parts)
    primary = tri_w.sum(1).argmax(1)
    member = {p: (primary == i) | (tri_w[:, :, i].max(1) >= SEAM_WEIGHT) for p, i in col.items()}

    rig = {"studsPerCm": STUDS_PER_CM, "parts": {}, "joints": [], "groups": {}}
    for group, names in GROUPS.items():
        T = np.where(np.any([member[n] for n in names], axis=0))[0]
        S = 4096
        lab = np.zeros(len(T), dtype=np.int64); keys = []
        for mi in (0, 1):
            m = tri_mat[T] == mi
            if not m.any():
                continue
            isl = uv_islands(UVI[tri_pv[T[m]]])
            for l in np.unique(isl):
                keys.append((mi, l)); lab[np.where(m)[0][isl == l]] = len(keys) - 1
        px = np.stack([tri_uv[T][..., 0] * S, (1 - tri_uv[T][..., 1]) * S], -1)
        rects = []
        for k in range(len(keys)):
            p = px[lab == k].reshape(-1, 2)
            lo = np.clip(np.floor(p.min(0)) - MARGIN, 0, S); hi = np.clip(np.ceil(p.max(0)) + MARGIN, 0, S)
            rects.append((lo, hi))
        sizes = [hi - lo for lo, hi in rects]
        lo_s, hi_s = 0.02, 1.0
        for _ in range(30):
            mid = (lo_s + hi_s) / 2
            if pack(sizes, mid, ATLAS):
                lo_s = mid
            else:
                hi_s = mid
        scale = lo_s; pos = pack(sizes, scale, ATLAS)
        for kind, suffix in (("Diffuse", "Color"), ("Normal", "Normal"), ("Glossiness", "Roughness")):
            mode = "L" if kind == "Glossiness" else "RGB"
            fill = 128 if kind == "Glossiness" else ((128, 128, 255) if kind == "Normal" else (60, 60, 60))
            at = Image.new(mode, (ATLAS, ATLAS), fill)
            for k, (mi, _) in enumerate(keys):
                lo, hi = rects[k]
                crop = src(kind, mi).crop((int(lo[0]), int(lo[1]), int(hi[0]), int(hi[1])))
                w = max(1, int(round((hi[0] - lo[0]) * scale))); h = max(1, int(round((hi[1] - lo[1]) * scale)))
                at.paste(crop.resize((w, h), Image.LANCZOS), pos[k])
            at.save(os.path.join(OUT, f"{group}_{suffix}.png"), optimize=True)
        newuv = np.zeros_like(px)
        for k in range(len(keys)):
            lo, _ = rects[k]; m = lab == k
            newuv[m] = ((px[m] - lo) * scale + np.array(pos[k])) / ATLAS
        newuv[..., 1] = 1 - newuv[..., 1]          # image rows -> glTF uv (v down from the top)
        rig["groups"][group] = {"parts": names, "texelScale": round(scale, 4)}
        index_of = {t: i for i, t in enumerate(T)}
        for name in names:
            TT = np.array([index_of[t] for t in np.where(member[name])[0]])
            corners_pv = tri_pv[T[TT]].reshape(-1)
            corners_uv = newuv[TT].reshape(-1, 2)
            key = np.c_[np.vectorize(vidx)(corners_pv), np.round(corners_uv * 65536)].astype(np.int64)
            uniq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.reshape(-1)
            pos3 = Vp[uniq[:, 0]]
            uvs = np.zeros((len(uniq), 2)); uvs[inv] = corners_uv
            nrm = np.zeros((len(uniq), 3)); np.add.at(nrm, inv, Np[corners_pv])
            nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
            F = inv.reshape(-1, 3)
            loc = pos3 * STUDS_PER_CM
            lo3, hi3 = loc.min(0), loc.max(0); c = (lo3 + hi3) / 2
            write_glb(os.path.join(OUT, f"{name}.glb"), loc - c, nrm, uvs, F)
            centre = to_roblox(c / STUDS_PER_CM, ground)
            rig["parts"][name] = {"centre": centre.round(4).tolist(), "size": (hi3 - lo3).round(4).tolist(),
                                  "group": group, "tris": int(len(F))}

    for jname, (p0, p1) in JOINT_PARTS.items():
        rig["joints"].append({"name": jname, "part0": p0, "part1": p1,
                              "pivot": to_roblox(joints[jname], ground).round(4).tolist()})
    rig["grips"] = {}
    for side in ("Left", "Right"):
        grip = to_roblox(joints[side + "Grip"], ground)
        rig["grips"][side] = (grip - np.array(rig["parts"][side + "Hand"]["centre"])).round(4).tolist()
    root = to_roblox(joints["Root"], ground)
    rig["parts"]["HumanoidRootPart"] = {"centre": root.round(4).tolist(), "size": [2, 2, 1], "group": None, "tris": 0}
    rig["hipHeight"] = round(float(root[1]) - 1.0, 4)
    rig["height"] = round(float((Vp[:, 1].max() - ground) * STUDS_PER_CM), 4)
    with open(os.path.join(OUT, "rig.json"), "w") as handle:
        json.dump(rig, handle, indent=1)
    for name in BODY:
        p = rig["parts"][name]
        print(f"{name:14s} centre {p['centre']} size {p['size']} tris {p['tris']}")
    print("height", rig["height"], "hipHeight", rig["hipHeight"])


if __name__ == "__main__":
    main()
