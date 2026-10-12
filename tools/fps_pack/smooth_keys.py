#!/usr/bin/env python3
"""Smooths one frame of a baked first-person clip module (tools/fps_pack/emit_luau.py
output) in place: for every track of CLIP whose bone matches REGEX, the key at FRAME is
replaced by the halfway pose between the keys at FRAME-1 and FRAME+1 (positions averaged,
rotations slerped the short way), so a one-frame spike disappears and a one-frame snap is
spread over two frames.

    python3 tools/fps_pack/smooth_keys.py MODULE.luau CLIP FRAME REGEX [--write]
    python3 tools/fps_pack/smooth_keys.py MODULE.luau CLIP FRAME --set ROWS.txt [--write]

The tracks are model-space changes, one per bone, so blending each on its own does not
keep a finger on its hand through a large turn. `--set` writes keys worked out with the
bone hierarchy instead: ROWS.txt holds one `bone|x,y,z,qx,qy,qz,qw` line per bone (the
model-space change, translation in the module's units), from a Studio pass that blends
each bone's pose relative to its parent between the neighbouring frames and composes
them down the arm.

Without --write it only reports what would change. Found with the Studio pop check: the
Uzi pack's ReloadEmpty lifts the whole left arm for frame 11 only (the hand jumped about
70 px up and back on screen) while the fingers flip 176 degrees in that one frame.
A re-emit from the baked JSON drops these edits; run this again after one.
"""

import base64
import math
import re
import struct
import sys

POS_Q = 2000
ROT_Q = 32767
CLIP_RE = r'\["{clip}"\]\s*=\s*\{{\s*duration\s*=\s*[\d.]+,\s*frames\s*=\s*\d+,\s*tracks\s*=\s*\{{(.*?)\n\t\t\}},'
TRACK_RE = re.compile(r'(\["([^"]+)"\]\s*=\s*")([A-Za-z0-9+/=]*)(")')


def decode(text):
    data = base64.b64decode(text + "=" * (-len(text) % 4))
    count = struct.unpack_from("<H", data, 0)[0]
    keys = []
    for i in range(count):
        frame = struct.unpack_from("<H", data, 2 + i * 16)[0]
        values = struct.unpack_from("<7h", data, 4 + i * 16)
        keys.append([frame, list(values)])
    return keys


def encode(keys):
    data = bytearray(struct.pack("<H", len(keys)))
    for frame, values in keys:
        data += struct.pack("<H7h", frame, *values)
    return base64.b64encode(bytes(data)).decode("ascii")


def slerp(a, b, u):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = [-x for x in b], -dot
    if dot > 0.9995:
        out = [x + u * (y - x) for x, y in zip(a, b)]
    else:
        theta = math.acos(min(1.0, dot))
        s = math.sin(theta)
        wa, wb = math.sin((1 - u) * theta) / s, math.sin(u * theta) / s
        out = [wa * x + wb * y for x, y in zip(a, b)]
    norm = math.sqrt(sum(x * x for x in out)) or 1.0
    return [x / norm for x in out]


def angle(a, b):
    dot = abs(sum(x * y for x, y in zip(a, b)))
    return math.degrees(2 * math.acos(min(1.0, dot)))


def main():
    args = [a for a in sys.argv[1:] if a != "--write"]
    write = "--write" in sys.argv
    rows = None
    if "--set" in args:
        at = args.index("--set")
        rows = {}
        for line in open(args[at + 1]):
            parts = line.strip().split("|")
            if len(parts) >= 2 and parts[0]:
                rows[parts[0]] = [float(x) for x in parts[1].split(",")]
        args = args[:at] + ["^(" + "|".join(re.escape(name) for name in rows) + ")$"]
    if len(args) != 4:
        print(__doc__)
        return 1
    path, clip, frame, pattern = args[0], args[1], int(args[2]), re.compile(args[3])
    source = open(path).read()
    match = re.search(CLIP_RE.format(clip=re.escape(clip)), source, re.S)
    if not match:
        raise SystemExit(f"{path}: no clip {clip!r}")
    body = match.group(1)
    changed = 0

    def fix(m):
        nonlocal changed
        bone, text = m.group(2), m.group(3)
        if not pattern.search(bone):
            return m.group(0)
        keys = decode(text)
        by_frame = {k[0]: k for k in keys}
        if rows is not None:
            value = rows[bone]
            new = [round(v * POS_Q) for v in value[:3]] + [max(-ROT_Q, min(ROT_Q, round(v * ROT_Q))) for v in value[3:]]
            if any(abs(v) > 32767 for v in new[:3]):
                raise SystemExit(f"{bone}: translation out of the int16 range")
            if frame in by_frame:
                old = by_frame[frame][1]
                print(f"  {bone}: frame {frame} turned {angle([v / ROT_Q for v in old[3:]], [v / ROT_Q for v in new[3:]]):.0f} deg, moved {math.dist([v / POS_Q for v in old[:3]], value[:3]):.2f}")
                by_frame[frame][1] = new
            else:
                keys.append([frame, new])
                keys.sort(key=lambda k: k[0])
                print(f"  {bone}: frame {frame} key added")
            changed += 1
            return m.group(1) + encode(keys) + m.group(4)
        if not all(f in by_frame for f in (frame - 1, frame, frame + 1)):
            return m.group(0)
        before, here, after = (by_frame[f][1] for f in (frame - 1, frame, frame + 1))
        qa = [v / ROT_Q for v in before[3:]]
        qb = [v / ROT_Q for v in after[3:]]
        q = slerp(qa, qb, 0.5)
        pos = [round((x + y) / 2) for x, y in zip(before[:3], after[:3])]
        new = pos + [max(-ROT_Q, min(ROT_Q, round(v * ROT_Q))) for v in q]
        old_turn = angle([v / ROT_Q for v in before[3:]], [v / ROT_Q for v in here[3:]])
        new_turn = angle(qa, q)
        shift = math.dist([v / POS_Q for v in here[:3]], [v / POS_Q for v in new[:3]])
        print(f"  {bone}: frame {frame} turn from the frame before {old_turn:.0f} -> {new_turn:.0f} deg, moved {shift:.2f}")
        by_frame[frame][1] = new
        changed += 1
        return m.group(1) + encode(keys) + m.group(4)

    new_body = TRACK_RE.sub(fix, body)
    print(f"{clip} frame {frame}: {changed} tracks")
    if write and changed:
        start, end = match.span(1)
        open(path, "w").write(source[:start] + new_body + source[end:])
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
