#!/usr/bin/env python3
"""Closes the loop of a baked looping KeyframeSequence (.rbxmx).

A looping AnimationTrack wraps from its last keyframe straight to its first without
interpolating, so a clip whose last pose is not its first pops once per cycle. Some
source clips run a little past their own loop point (the Sketchfab walker run ends about
0.1 s into its next cycle: 38 degrees on the right calf at the wrap). This finds, among
the last frames, the one closest to the first pose (summed rotation error over every
pose), drops the keyframes after it and sets it to the first pose exactly.

    python3 tools/zombie_pack/close_loop.py CLIP.rbxmx [--search 8] [--write]

Without --write it only reports. The clip must be uploaded again after a write.
"""

import argparse
import math
import sys
import xml.etree.ElementTree as ET

AXES = ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")


def rotation(cframe):
    values = {child.tag: float(child.text) for child in cframe}
    return [values[axis] for axis in AXES]


def angle(a, b):
    trace = sum(x * y for x, y in zip(a, b))
    return math.degrees(math.acos(max(-1.0, min(1.0, (trace - 1) / 2))))


def poses(keyframe):
    """Pose path (names from the keyframe down) -> its CoordinateFrame element."""
    out = {}

    def walk(item, path):
        for child in item.findall("Item"):
            if child.get("class") != "Pose":
                continue
            name = child.find("Properties/string[@name='Name']").text
            key = path + (name,)
            out[key] = child.find("Properties/CoordinateFrame[@name='CFrame']")
            walk(child, key)

    walk(keyframe, ())
    return out


def keyframe_time(keyframe):
    return float(keyframe.find("Properties/float[@name='Time']").text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("clip")
    parser.add_argument("--search", type=int, default=8, help="how many last frames to consider")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    tree = ET.parse(args.clip)
    sequence = tree.getroot().find("Item")
    loop = sequence.find("Properties/bool[@name='Loop']")
    if loop is None or loop.text != "true":
        sys.exit(f"{args.clip}: not a looping clip")
    keyframes = sorted((item for item in sequence.findall("Item") if item.get("class") == "Keyframe"), key=keyframe_time)
    first = poses(keyframes[0])
    first_rot = {key: rotation(cf) for key, cf in first.items()}

    def error(keyframe):
        other = poses(keyframe)
        errors = [angle(first_rot[key], rotation(cf)) for key, cf in other.items() if key in first_rot]
        return sum(errors), max(errors)

    start = max(len(keyframes) // 2, len(keyframes) - args.search)
    scored = [(error(keyframes[i]), i) for i in range(start, len(keyframes))]
    for (total, worst), i in scored:
        print(f"  {keyframe_time(keyframes[i]):.3f}s  sum {total:7.1f}  max {worst:5.1f}")
    (_, worst_last), _ = scored[-1]
    (best_total, best_worst), best = min(scored)
    print(f"seam now {worst_last:.1f} deg; best loop point {keyframe_time(keyframes[best]):.3f}s ({best_worst:.1f} deg off the first pose)")
    if not args.write:
        return
    for keyframe in keyframes[best + 1:]:
        sequence.remove(keyframe)
    for key, cf in poses(keyframes[best]).items():
        source = first.get(key)
        if source is None:
            continue
        for child, value in zip(cf, source):
            child.text = value.text
    tree.write(args.clip, encoding="utf-8")
    print(f"wrote {args.clip}: {best + 1} keyframes, length {keyframe_time(keyframes[best]):.3f}s, closed on the first pose")


if __name__ == "__main__":
    main()
