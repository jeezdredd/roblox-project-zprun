"""Batch retarget Mixamo FBX clips onto a Roblox R15 rig.

Run headless:

    blender -b -P retarget_mixamo.py -- --input input --output output

Reads every .fbx in the input folder, maps Mixamo bone names onto R15 bone
names, strips root motion from in-place clips, validates loop seams and frame
rate, and writes one .blend and one .fbx per clip into the output folder.

Nothing here authors animation. It only transfers existing keyframes from one
skeleton naming scheme to another; see docs/asset-policy.md.
"""

import argparse
import os
import sys

try:
    import bpy
except ImportError:  # allows --help and linting outside Blender
    bpy = None

# Mixamo rigs prefix every bone with "mixamorig:". R15 uses these part names as
# the motor/bone names in the Roblox animation exporter.
BONE_MAP = {
    "Hips": "LowerTorso",
    "Spine": "UpperTorso",
    "Spine1": "UpperTorso",
    "Spine2": "UpperTorso",
    "Neck": "Head",
    "Head": "Head",
    "LeftShoulder": "LeftUpperArm",
    "LeftArm": "LeftUpperArm",
    "LeftForeArm": "LeftLowerArm",
    "LeftHand": "LeftHand",
    "RightShoulder": "RightUpperArm",
    "RightArm": "RightUpperArm",
    "RightForeArm": "RightLowerArm",
    "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpperLeg",
    "LeftLeg": "LeftLowerLeg",
    "LeftFoot": "LeftFoot",
    "RightUpLeg": "RightUpperLeg",
    "RightLeg": "RightLowerLeg",
    "RightFoot": "RightFoot",
}

LOOP_SLOTS = {
    "zombie_idle_a",
    "zombie_idle_b",
    "zombie_walk_shuffle",
    "zombie_run_ragged",
    "zombie_feeding",
    "player_run",
    "player_strafe_left",
    "player_strafe_right",
}

IN_PLACE_SLOTS = LOOP_SLOTS

ROOT_DRIFT_LIMIT = 1.0


class ClipReport:
    def __init__(self, name):
        self.name = name
        self.warnings = []
        self.errors = []

    def warn(self, message):
        self.warnings.append(message)

    def fail(self, message):
        self.errors.append(message)

    def emit(self):
        status = "FAIL" if self.errors else ("WARN" if self.warnings else "OK")
        print(f"[{status}] {self.name}")
        for message in self.errors:
            print(f"    error: {message}")
        for message in self.warnings:
            print(f"    warning: {message}")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="input")
    parser.add_argument("--output", default="output")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--loop-threshold", type=float, default=0.02)
    parser.add_argument("--root-drift", type=float, default=ROOT_DRIFT_LIMIT)
    return parser.parse_args(argv)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.actions):
        bpy.data.actions.remove(block)


def find_armature():
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def strip_prefix(name):
    return name.split(":")[-1]


def rename_bones(armature, report):
    for bone in armature.data.bones:
        base = strip_prefix(bone.name)
        mapped = BONE_MAP.get(base)
        if mapped is None:
            report.warn(f"bone '{bone.name}' has no R15 mapping, left untouched")
            continue
        bone.name = mapped


def frame_positions(armature, bone_name):
    positions = []
    scene = bpy.context.scene
    pose_bone = armature.pose.bones.get(bone_name)
    if pose_bone is None:
        return positions
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        positions.append(pose_bone.matrix.translation.copy())
    return positions


def strip_root_motion(armature, report):
    root = armature.pose.bones.get("LowerTorso")
    if root is None:
        report.warn("no LowerTorso bone, root motion not stripped")
        return
    action = armature.animation_data.action if armature.animation_data else None
    if action is None:
        report.fail("clip has no action")
        return

    path = f'pose.bones["LowerTorso"].location'
    removed = 0
    for curve in list(action.fcurves):
        if curve.data_path != path:
            continue
        if curve.array_index in (0, 1):  # X and Y travel; keep Z bob
            action.fcurves.remove(curve)
            removed += 1
    if removed == 0:
        report.warn("no horizontal root curves found to strip")


def check_root_drift(armature, report, limit):
    positions = frame_positions(armature, "LowerTorso")
    if len(positions) < 2:
        return
    drift = (positions[-1] - positions[0]).length
    if drift > limit:
        report.warn(f"root travels {drift:.2f} units across the clip; expected in-place")


def check_loop_seam(armature, report, threshold):
    scene = bpy.context.scene
    if not armature.animation_data or not armature.animation_data.action:
        return
    first = {}
    scene.frame_set(scene.frame_start)
    for bone in armature.pose.bones:
        first[bone.name] = bone.matrix.copy()
    scene.frame_set(scene.frame_end)
    worst_bone = None
    worst_delta = 0.0
    for bone in armature.pose.bones:
        start = first.get(bone.name)
        if start is None:
            continue
        delta = (bone.matrix.translation - start.translation).length
        if delta > worst_delta:
            worst_delta = delta
            worst_bone = bone.name
    if worst_delta > threshold:
        report.warn(
            f"loop seam mismatch: '{worst_bone}' differs by {worst_delta:.3f} between first and last frame"
        )


def check_fps(report, expected):
    actual = bpy.context.scene.render.fps
    if actual != expected:
        report.warn(f"frame rate is {actual}, expected {expected}")


def process(path, output_dir, args):
    slot = os.path.splitext(os.path.basename(path))[0]
    report = ClipReport(slot)

    clear_scene()
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)

    armature = find_armature()
    if armature is None:
        report.fail("no armature found in the FBX")
        report.emit()
        return False

    check_fps(report, args.fps)
    rename_bones(armature, report)

    if slot in IN_PLACE_SLOTS:
        strip_root_motion(armature, report)
        check_root_drift(armature, report, args.root_drift)
    if slot in LOOP_SLOTS:
        check_loop_seam(armature, report, args.loop_threshold)

    os.makedirs(output_dir, exist_ok=True)
    blend_path = os.path.join(output_dir, f"{slot}.blend")
    fbx_path = os.path.join(output_dir, f"{slot}.fbx")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.fbx(filepath=fbx_path, add_leaf_bones=False, bake_anim=True)

    report.emit()
    return not report.errors


def main():
    if bpy is None:
        print("this script must run inside Blender: blender -b -P retarget_mixamo.py -- --help")
        return 1

    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    args = parse_args(argv)

    if not os.path.isdir(args.input):
        print(f"input folder not found: {args.input}")
        return 1

    sources = sorted(
        os.path.join(args.input, name)
        for name in os.listdir(args.input)
        if name.lower().endswith(".fbx")
    )
    if not sources:
        print(f"no .fbx files in {args.input}")
        return 1

    failures = 0
    for path in sources:
        if not process(path, args.output, args):
            failures += 1

    print(f"\n{len(sources) - failures}/{len(sources)} clips converted into {args.output}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
