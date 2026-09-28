"""Retarget humanoid clips from a glTF/GLB library onto Roblox R15 KeyframeSequences.

Run headless:

    blender -b --python glb_to_keyframes.py -- --library path/to/pack.glb \
        --clip Zombie_Walk_Fwd_Loop=zombie/walk_shuffle:loop \
        --output ../../assets/animation

Each --clip is SOURCE_ACTION=slot[:flags]. Flags: loop (seamless loop, horizontal
root travel stripped), once (plays through, root translation kept), priority=N.

Source rigs use the Unreal mannequin bone names (pelvis, spine_03, upperarm_l ...),
which is what the Quaternius Universal Animation Library ships. Nothing here authors
motion: it samples the source action at 30 fps, expresses every joint as the child's
world-space rotation relative to its parent's, converts Blender Z-up to Roblox Y-up
and writes the poses in the Roblox XML model format that the manifest upload accepts.
"""

import argparse
import math
import os
import sys
import uuid

try:
    import bpy
    from mathutils import Matrix, Quaternion, Vector
except ImportError:
    bpy = None

SAMPLE_FPS = 30
STUDS_PER_METRE = 3.2

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

PART_BONE_CANDIDATES = {
    "LowerTorso": ("pelvis", "DEF-hips", "mixamorig:Hips", "Hips"),
    "UpperTorso": ("spine_03", "DEF-spine.003", "mixamorig:Spine2", "Spine2"),
    "Head": ("Head", "DEF-head", "mixamorig:Head"),
    "LeftUpperArm": ("upperarm_l", "DEF-upper_arm.L", "mixamorig:LeftArm", "LeftArm"),
    "LeftLowerArm": ("lowerarm_l", "DEF-forearm.L", "mixamorig:LeftForeArm", "LeftForeArm"),
    "LeftHand": ("hand_l", "DEF-hand.L", "mixamorig:LeftHand", "LeftHand"),
    "RightUpperArm": ("upperarm_r", "DEF-upper_arm.R", "mixamorig:RightArm", "RightArm"),
    "RightLowerArm": ("lowerarm_r", "DEF-forearm.R", "mixamorig:RightForeArm", "RightForeArm"),
    "RightHand": ("hand_r", "DEF-hand.R", "mixamorig:RightHand", "RightHand"),
    "LeftUpperLeg": ("thigh_l", "DEF-thigh.L", "mixamorig:LeftUpLeg", "LeftUpLeg"),
    "LeftLowerLeg": ("calf_l", "DEF-shin.L", "mixamorig:LeftLeg", "LeftLeg"),
    "LeftFoot": ("foot_l", "DEF-foot.L", "mixamorig:LeftFoot", "LeftFoot"),
    "RightUpperLeg": ("thigh_r", "DEF-thigh.R", "mixamorig:RightUpLeg", "RightUpLeg"),
    "RightLowerLeg": ("calf_r", "DEF-shin.R", "mixamorig:RightLeg", "RightLeg"),
    "RightFoot": ("foot_r", "DEF-foot.R", "mixamorig:RightFoot", "RightFoot"),
}

PART_BONE = {}

PRIORITY_TOKENS = {"idle": 0, "movement": 1, "action": 2, "action2": 3, "action3": 4, "action4": 5}

BLENDER_TO_ROBLOX = Matrix(((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)))


class ClipSpec:
    def __init__(self, action, slot, flags):
        self.action = action
        self.slot = slot
        self.loop = "loop" in flags
        self.priority = PRIORITY_TOKENS["movement" if self.loop else "action"]
        for flag in flags:
            if flag.startswith("priority="):
                value = flag.split("=", 1)[1]
                self.priority = PRIORITY_TOKENS.get(value, int(value) if value.isdigit() else self.priority)


def parse_clip(text):
    source, _, rest = text.partition("=")
    slot, _, flag_text = rest.partition(":")
    flags = [flag for flag in flag_text.split(",") if flag]
    if not source or not slot:
        raise SystemExit(f"bad --clip '{text}', expected SOURCE=slot[:flags]")
    return ClipSpec(source, slot, flags)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, help="glTF/GLB file holding the source actions")
    parser.add_argument("--clip", action="append", default=[], help="SOURCE_ACTION=slot[:loop|once,priority=name]")
    parser.add_argument("--output", required=True, help="folder that receives <slot>.rbxmx")
    parser.add_argument("--fps", type=int, default=SAMPLE_FPS)
    parser.add_argument("--scale", type=float, default=STUDS_PER_METRE)
    parser.add_argument("--posture", default="", help="PART=rotationScale,... scales that joint's whole rotation in every clip, e.g. UpperTorso=0.4,LowerTorso=0.6")
    return parser.parse_args(argv)


def parse_posture(text):
    result = {}
    for item in text.split(","):
        if not item:
            continue
        part, _, value = item.partition("=")
        result[part] = float(value)
    return result


def scale_rotation(rotation, factor):
    quaternion = rotation.to_quaternion()
    return Quaternion(quaternion.axis, quaternion.angle * factor).to_matrix()


def find_armature():
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            return obj
    raise SystemExit("no armature in library")


def activate(armature, action):
    data = armature.animation_data
    if data is None:
        data = armature.animation_data_create()
    for track in data.nla_tracks:
        track.mute = True
    data.action = action
    if hasattr(data, "action_slot") and len(action.slots) > 0:
        data.action_slot = action.slots[0]


def rest_world(armature):
    world = armature.matrix_world
    result = {}
    for bone in armature.data.bones:
        matrix = world @ bone.matrix_local
        result[bone.name] = (matrix.to_3x3(), matrix.translation.copy())
    return result


def evaluated_world(armature):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = armature.evaluated_get(depsgraph)
    world = evaluated.matrix_world
    result = {}
    for pose_bone in evaluated.pose.bones:
        matrix = world @ pose_bone.matrix
        result[pose_bone.name] = (matrix.to_3x3(), matrix.translation.copy())
    return result


def delta_rotation(current, rest, bone):
    return current[bone][0] @ rest[bone][0].inverted()


def to_roblox_rotation(rotation):
    return BLENDER_TO_ROBLOX @ rotation @ BLENDER_TO_ROBLOX.inverted()


def to_roblox_vector(vector, scale):
    converted = BLENDER_TO_ROBLOX @ vector
    return converted * scale


def sample_pose(armature, rest, spec, scale, posture):
    current = evaluated_world(armature)
    poses = {}
    for part, bone in PART_BONE.items():
        parent_part = PART_TREE[part]
        parent_bone = PART_BONE.get(parent_part)
        child_delta = delta_rotation(current, rest, bone)
        if parent_bone:
            parent_delta = delta_rotation(current, rest, parent_bone)
            local = parent_delta.inverted() @ child_delta
        else:
            local = child_delta
        rotation = to_roblox_rotation(local)
        if part in posture:
            rotation = scale_rotation(rotation, posture[part])
        translation = Vector((0.0, 0.0, 0.0))
        if part == "LowerTorso":
            travel = current[bone][1] - rest[bone][1]
            translation = to_roblox_vector(travel, scale)
            if spec.loop:
                translation = Vector((0.0, translation.y, 0.0))
        poses[part] = (rotation, translation)
    return poses


def bake(armature, spec, fps, scale, posture):
    action = bpy.data.actions.get(spec.action)
    if action is None:
        raise SystemExit(f"action '{spec.action}' not found in library")
    activate(armature, action)
    scene = bpy.context.scene
    source_fps = scene.render.fps / scene.render.fps_base
    start, end = action.frame_range
    duration = (end - start) / source_fps
    rest = rest_world(armature)
    frames = []
    count = max(1, int(math.floor(duration * fps + 1e-6)))
    for index in range(count + 1):
        time = index / fps
        if time > duration + 1e-6:
            break
        source_frame = start + time * source_fps
        whole = int(math.floor(source_frame))
        scene.frame_set(whole, subframe=source_frame - whole)
        frames.append((time, sample_pose(armature, rest, spec, scale, posture)))
    if spec.loop and len(frames) > 1 and abs(frames[-1][0] - duration) > 1e-6:
        frames.append((duration, frames[0][1]))
    return frames, duration


def format_number(value):
    text = f"{value:.6g}"
    return "-0" if text == "-0" else text


def cframe_xml(rotation, translation):
    elements = [translation.x, translation.y, translation.z]
    for row in range(3):
        for column in range(3):
            elements.append(rotation[row][column])
    names = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    return "".join(f"<{name}>{format_number(value)}</{name}>" for name, value in zip(names, elements))


def referent():
    return "RBX" + uuid.uuid4().hex.upper()


def pose_xml(part, poses, depth):
    indent = "  " * depth
    if part == "HumanoidRootPart":
        rotation, translation, weight = Matrix.Identity(3), Vector((0.0, 0.0, 0.0)), 0
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
        lines.append(f'  <Properties><string name="Name">Keyframe</string><float name="Time">{format_number(time)}</float></Properties>')
        lines.append(pose_xml("HumanoidRootPart", poses, 2))
        lines.append(" </Item>")
    lines.append("</Item>")
    lines.append("</roblox>")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parse_args(argv)
    specs = [parse_clip(text) for text in args.clip]
    if not specs:
        raise SystemExit("no --clip given")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.library)
    armature = find_armature()
    missing = []
    for part, candidates in PART_BONE_CANDIDATES.items():
        found = next((name for name in candidates if name in armature.data.bones), None)
        if found is None:
            missing.append(part)
        else:
            PART_BONE[part] = found
    if missing:
        raise SystemExit(f"library rig lacks bones for: {missing}")

    posture = parse_posture(args.posture)
    for spec in specs:
        frames, duration = bake(armature, spec, args.fps, args.scale, posture)
        name = spec.slot.replace("/", "_")
        path = os.path.join(args.output, spec.slot + ".rbxmx")
        write_sequence(path, name, spec, frames)
        print(f"[OK] {spec.slot}: {spec.action} -> {len(frames)} keyframes, {duration:.2f}s, loop={spec.loop}, priority={spec.priority}")


if __name__ == "__main__":
    if bpy is None:
        raise SystemExit("run inside Blender: blender -b --python glb_to_keyframes.py -- ...")
    main()
