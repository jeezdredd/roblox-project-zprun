#!/usr/bin/env python3
"""Retarget Mixamo clips (Collada .dae, exported "With Skin") onto Roblox R15
KeyframeSequences. No Blender: numpy + the standard library.

    python3 tools/animation_pipeline/dae_to_keyframes.py \
        --clip "path/Zombie Walk.dae=zombie/walk_a:loop" \
        --output assets/animation [--posture UpperTorso=0.8] [--speed 1.0]

Each --clip is DAE=slot[:flags]; flags as in glb_to_keyframes.py: loop (seamless loop,
horizontal root travel stripped), once (root translation kept), seated (no root
translation at all: the seat weld holds the root), priority=NAME|N, trim=START-END
(seconds).

Same transfer as glb_to_keyframes.py: every R15 part takes its source bone's world-space
rotation change from the rest pose, expressed relative to its parent part's change, in
Roblox axes. Rest is the bind pose (inverse bind matrices); Mixamo writes the first frame
of the clip into the node matrices, so those are not a rest pose. Mixamo exports are Y-up
in centimetres facing +Z; Roblox faces -Z, so axes turn 180 degrees about Y. R15 rests
with the arms down while the Mixamo bind is a T-pose, so the arm, forearm and hand carry a
rest offset (straight down onto the bone's bind direction) before the parent-relative step.
"""

import argparse
import os
import sys
import uuid
import xml.etree.ElementTree as ET

import numpy as np

NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}
SAMPLE_FPS = 30
STUDS_PER_METRE = 3.2
FLIP = np.diag([-1.0, 1.0, -1.0])

PART_TREE = {
    "HumanoidRootPart": None,
    "LowerTorso": "HumanoidRootPart",
    "UpperTorso": "LowerTorso",
    "Head": "UpperTorso",
    "LeftUpperArm": "UpperTorso",
    "LeftLowerArm": "LeftUpperArm",
    "LeftHand": "LeftLowerArm",
    "RightUpperArm": "UpperTorso",
    "RightLowerArm": "RightUpperArm",
    "RightHand": "RightLowerArm",
    "LeftUpperLeg": "LowerTorso",
    "LeftLowerLeg": "LeftUpperLeg",
    "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "LowerTorso",
    "RightLowerLeg": "RightUpperLeg",
    "RightFoot": "RightLowerLeg",
}

PART_BONE = {
    "LowerTorso": "Hips",
    "UpperTorso": "Spine2",
    "Head": "Head",
    "LeftUpperArm": "LeftArm",
    "LeftLowerArm": "LeftForeArm",
    "LeftHand": "LeftHand",
    "RightUpperArm": "RightArm",
    "RightLowerArm": "RightForeArm",
    "RightHand": "RightHand",
    "LeftUpperLeg": "LeftUpLeg",
    "LeftLowerLeg": "LeftLeg",
    "LeftFoot": "LeftFoot",
    "RightUpperLeg": "RightUpLeg",
    "RightLowerLeg": "RightLeg",
    "RightFoot": "RightFoot",
}

PRIORITY_TOKENS = {"idle": 0, "movement": 1, "action": 2, "action2": 3, "action3": 4, "action4": 5}


class ClipSpec:
    def __init__(self, text):
        source, _, rest = text.rpartition("=")
        slot, _, flag_text = rest.partition(":")
        flags = [f for f in flag_text.split(",") if f]
        if not source or not slot:
            raise SystemExit(f"bad --clip '{text}', expected DAE=slot[:flags]")
        self.source, self.slot = source, slot
        self.loop = "loop" in flags
        self.seated = "seated" in flags
        self.priority = PRIORITY_TOKENS["movement" if self.loop else "action"]
        self.trim = None
        for flag in flags:
            if flag.startswith("priority="):
                value = flag.split("=", 1)[1]
                self.priority = PRIORITY_TOKENS.get(value, int(value) if value.isdigit() else self.priority)
            if flag.startswith("trim="):
                a, b = flag.split("=", 1)[1].split("-")
                self.trim = (float(a), float(b))


def strip_prefix(name):
    for prefix in ("mixamorig_", "mixamorig:", "mixamorig1_", "mixamorig2_"):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def floats(el):
    return np.array([float(x) for x in el.text.split()]) if el is not None and el.text else np.array([])


class Dae:
    def __init__(self, path):
        root = ET.parse(path).getroot()
        unit = root.find("c:asset/c:unit", NS)
        self.metres = float(unit.get("meter")) if unit is not None else 1.0
        # node tree: joint name -> (parent name, local rest matrix)
        self.parent, self.local, self.order = {}, {}, []

        def walk(node, parent, parent_world):
            name = strip_prefix(node.get("name") or node.get("id") or "")
            m = np.eye(4)
            mat = node.find("c:matrix", NS)
            if mat is not None:
                m = floats(mat).reshape(4, 4)
            self.parent[name] = parent
            self.local[name] = m
            self.order.append(name)
            for child in node.findall("c:node", NS):
                walk(child, name, None)

        for scene in root.findall(".//c:library_visual_scenes/c:visual_scene", NS):
            for node in scene.findall("c:node", NS):
                walk(node, None, None)
        # bind pose from the skin controller
        self.bind = {}
        for skin in root.findall(".//c:library_controllers/c:controller/c:skin", NS):
            bsm = floats(skin.find("c:bind_shape_matrix", NS)).reshape(4, 4)
            sources = {s.get("id"): s for s in skin.findall("c:source", NS)}
            joints_input = skin.find("c:joints/c:input[@semantic='JOINT']", NS)
            ibm_input = skin.find("c:joints/c:input[@semantic='INV_BIND_MATRIX']", NS)
            names = sources[joints_input.get("source")[1:]].find("c:Name_array", NS).text.split()
            ibms = floats(sources[ibm_input.get("source")[1:]].find("c:float_array", NS)).reshape(-1, 4, 4)
            for name, ibm in zip(names, ibms):
                self.bind.setdefault(strip_prefix(name), np.linalg.inv(ibm) @ bsm)
        # sampled matrix animation per joint
        self.anim = {}
        for anim in root.findall(".//c:library_animations//c:animation", NS):
            channel = anim.find("c:channel", NS)
            if channel is None:
                continue
            target = strip_prefix(channel.get("target").split("/")[0])
            sampler = anim.find("c:sampler", NS)
            inputs = {i.get("semantic"): i.get("source")[1:] for i in sampler.findall("c:input", NS)}
            srcs = {s.get("id"): s for s in anim.findall("c:source", NS)}
            times = floats(srcs[inputs["INPUT"]].find("c:float_array", NS))
            values = floats(srcs[inputs["OUTPUT"]].find("c:float_array", NS)).reshape(-1, 4, 4)
            self.anim[target] = (times, values)
        self.duration = max((t[-1] for t, _ in self.anim.values()), default=0.0)

    def local_at(self, name, t):
        if name not in self.anim:
            return self.local[name]
        times, values = self.anim[name]
        if t <= times[0]:
            return values[0]
        if t >= times[-1]:
            return values[-1]
        k = int(np.searchsorted(times, t, side="right")) - 1
        u = (t - times[k]) / max(times[k + 1] - times[k], 1e-9)
        a, b = values[k], values[k + 1]
        # rotation by slerp through quaternions, translation linear
        qa, qb = mat_to_quat(orthonormal(a[:3, :3])), mat_to_quat(orthonormal(b[:3, :3]))
        m = np.eye(4)
        m[:3, :3] = quat_to_mat(slerp(qa, qb, u))
        m[:3, 3] = a[:3, 3] * (1 - u) + b[:3, 3] * u
        return m

    def world_at(self, t):
        out = {}
        for name in self.order:
            m = self.local_at(name, t)
            p = self.parent[name]
            out[name] = (out[p] @ m) if p is not None else m
        return out


def orthonormal(m):
    u, _, vt = np.linalg.svd(m)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def slerp(a, b, u):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        q = a + u * (b - a)
        return q / np.linalg.norm(q)
    th = np.arccos(d)
    return (np.sin((1 - u) * th) * a + np.sin(u * th) * b) / np.sin(th)


def scale_rotation(r, factor):
    q = mat_to_quat(r)
    angle = 2 * np.arccos(np.clip(q[3], -1, 1))
    if angle < 1e-6:
        return r
    axis = q[:3] / np.sin(angle / 2)
    a = angle * factor
    return quat_to_mat(np.array([*(axis * np.sin(a / 2)), np.cos(a / 2)]))


# R15 rests with the arms hanging straight down, the Mixamo bind is a T-pose. The arm,
# forearm and hand take a rest offset: the rotation that turns "straight down" onto the
# bone's bind direction, so a clip's delta from the T-pose lands on the arms-down rig.
REST_CHILD = {
    "LeftUpperArm": ("LeftArm", "LeftForeArm"),
    "LeftLowerArm": ("LeftForeArm", "LeftHand"),
    "LeftHand": ("LeftHand", "LeftHandMiddle1"),
    "RightUpperArm": ("RightArm", "RightForeArm"),
    "RightLowerArm": ("RightForeArm", "RightHand"),
    "RightHand": ("RightHand", "RightHandMiddle1"),
}


def rotation_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.999999:
        axis = np.cross(a, [1.0, 0.0, 0.0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0.0, 0.0, 1.0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1 + c)


def rest_offsets(dae):
    """Roblox-axis rotation per part from the R15 rest onto the Mixamo bind pose."""
    offsets = {part: np.eye(3) for part in PART_BONE}
    down = np.array([0.0, -1.0, 0.0])
    for part, (bone, child) in REST_CHILD.items():
        if bone in dae.bind and child in dae.bind:
            direction = FLIP @ (dae.bind[child][:3, 3] - dae.bind[bone][:3, 3])
            offsets[part] = rotation_between(down, direction)
    offsets["LeftHand"] = offsets["LeftLowerArm"] if "LeftHandMiddle1" not in dae.bind else offsets["LeftHand"]
    offsets["RightHand"] = offsets["RightLowerArm"] if "RightHandMiddle1" not in dae.bind else offsets["RightHand"]
    return offsets


def sample_pose(dae, t, rest_rot, rest_hips, spec, scale, posture, offsets):
    world = dae.world_at(t)
    placed = {}
    for part, bone in PART_BONE.items():
        current = orthonormal(world[bone][:3, :3])
        delta = FLIP @ (current @ rest_rot[bone].T) @ FLIP
        placed[part] = delta @ offsets[part]
    poses = {}
    for part in PART_BONE:
        parent = PART_TREE[part]
        rotation = placed[part] if parent not in placed else placed[parent].T @ placed[part]
        if part in posture:
            rotation = scale_rotation(rotation, posture[part])
        translation = np.zeros(3)
        if part == "LowerTorso":
            travel = world[PART_BONE[part]][:3, 3] - rest_hips
            translation = FLIP @ travel * dae.metres * scale
            if spec.seated:
                translation = np.zeros(3)
            elif spec.loop:
                translation = np.array([0.0, translation[1], 0.0])
        poses[part] = (rotation, translation)
    return poses


def fmt(v):
    text = f"{v:.6g}"
    return "0" if text in ("-0", "0") else text


def cframe_xml(rotation, translation):
    values = [*translation, *rotation.reshape(-1)]
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    return "".join(f"<{n}>{fmt(v)}</{n}>" for n, v in zip(names, values))


def referent():
    return "RBX" + uuid.uuid4().hex.upper()


def pose_xml(part, poses, depth):
    indent = "  " * depth
    if part == "HumanoidRootPart":
        rotation, translation, weight = np.eye(3), np.zeros(3), 0
    else:
        rotation, translation = poses[part]
        weight = 1
    lines = [
        f'{indent}<Item class="Pose" referent="{referent()}">',
        f'{indent} <Properties><string name="Name">{part}</string><CoordinateFrame name="CFrame">{cframe_xml(rotation, translation)}</CoordinateFrame>'
        f'<float name="Weight">{weight}</float><token name="EasingStyle">0</token><token name="EasingDirection">0</token></Properties>',
    ]
    for child, parent in PART_TREE.items():
        if parent == part:
            lines.append(pose_xml(child, poses, depth + 1))
    lines.append(f"{indent}</Item>")
    return "\n".join(lines)


def write_sequence(path, name, spec, frames):
    lines = [
        '<roblox version="4">',
        f'<Item class="KeyframeSequence" referent="{referent()}">',
        f' <Properties><string name="Name">{name}</string><bool name="Loop">{"true" if spec.loop else "false"}</bool>'
        f'<token name="Priority">{spec.priority}</token></Properties>',
    ]
    for time, poses in frames:
        lines.append(f' <Item class="Keyframe" referent="{referent()}">')
        lines.append(f'  <Properties><string name="Name">Keyframe</string><float name="Time">{fmt(time)}</float></Properties>')
        lines.append(pose_xml("HumanoidRootPart", poses, 2))
        lines.append(" </Item>")
    lines += ["</Item>", "</roblox>"]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--clip", action="append", default=[], help="DAE=slot[:loop|once,priority=NAME,trim=A-B]")
    parser.add_argument("--output", required=True)
    parser.add_argument("--fps", type=int, default=SAMPLE_FPS)
    parser.add_argument("--scale", type=float, default=STUDS_PER_METRE)
    parser.add_argument("--posture", default="", help="PART=rotationScale,... e.g. UpperTorso=0.8")
    args = parser.parse_args()
    posture = {}
    for item in args.posture.split(","):
        if item:
            k, _, v = item.partition("=")
            posture[k] = float(v)
    for text in args.clip:
        spec = ClipSpec(text)
        dae = Dae(spec.source)
        missing = [b for b in PART_BONE.values() if b not in dae.bind]
        if missing:
            raise SystemExit(f"{spec.source}: no bind pose for {missing}")
        rest_rot = {b: orthonormal(dae.bind[b][:3, :3]) for b in PART_BONE.values()}
        rest_hips = dae.bind[PART_BONE["LowerTorso"]][:3, 3]
        offsets = rest_offsets(dae)
        start, end = spec.trim if spec.trim else (0.0, dae.duration)
        end = min(end, dae.duration)
        duration = end - start
        count = max(1, int(np.floor(duration * args.fps + 1e-6)))
        frames = []
        for i in range(count + 1):
            t = i / args.fps
            if t > duration + 1e-6:
                break
            frames.append((t, sample_pose(dae, start + t, rest_rot, rest_hips, spec, args.scale, posture, offsets)))
        if spec.loop and len(frames) > 1 and abs(frames[-1][0] - duration) > 1e-6:
            frames.append((duration, frames[0][1]))
        path = os.path.join(args.output, spec.slot + ".rbxmx")
        write_sequence(path, spec.slot.replace("/", "_"), spec, frames)
        print(f"[OK] {spec.slot}: {os.path.basename(spec.source)} -> {len(frames)} keyframes, {duration:.2f}s, loop={spec.loop}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
