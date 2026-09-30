"""Write the soldier parts as Luau data modules for an Edit-mode preview through EditableMesh.

The modules land in src/shared/_SoldierPreview (git-ignored), Rojo syncs them into
ReplicatedStorage.Shared._SoldierPreview, and a Studio command-bar snippet builds the
rig from them before anything is uploaded. Delete the folder after the check.

    python3 tools/character_rig/studio_preview.py
"""
import base64
import json
import os
import struct

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "assets", "character", "soldier", "source")
OUT = os.path.join(ROOT, "src", "shared", "_SoldierPreview")
PREVIEW_TEX = 256


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + jlen])
    binary = data[20 + jlen + 8:]
    out = []
    for acc in g["accessors"]:
        view = g["bufferViews"][acc["bufferView"]]
        dt = "<f4" if acc["componentType"] == 5126 else "<u4"
        n = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[acc["type"]]
        arr = np.frombuffer(binary, dtype=dt, count=acc["count"] * n, offset=view["byteOffset"]).reshape(-1, n) if n > 1 else \
            np.frombuffer(binary, dtype=dt, count=acc["count"], offset=view["byteOffset"])
        out.append(arr)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    rig = json.load(open(os.path.join(SRC, "rig.json")))
    for name, info in rig["parts"].items():
        if name == "HumanoidRootPart":
            continue
        P, N, UV, F = read_glb(os.path.join(SRC, name + ".glb"))
        P = P * np.array([-1, 1, -1], np.float32)   # what the glTF importer does
        N = N * np.array([-1, 1, -1], np.float32)
        blob = struct.pack("<II", len(P), len(F) // 3) + P.astype("<f4").tobytes() + N.astype("<f4").tobytes() \
            + UV.astype("<f4").tobytes() + F.astype("<u4").tobytes()
        text = base64.b64encode(blob).decode()
        with open(os.path.join(OUT, name + ".luau"), "w") as h:
            h.write(f'return {{ group = "{info["group"]}", data = "{text}" }}\n')
    for group in rig["groups"]:
        im = Image.open(os.path.join(SRC, f"{group}_Color.png")).convert("RGBA").resize((PREVIEW_TEX, PREVIEW_TEX), Image.LANCZOS)
        text = base64.b64encode(im.tobytes()).decode()
        with open(os.path.join(OUT, f"Tex_{group}.luau"), "w") as h:
            h.write(f'return {{ size = {PREVIEW_TEX}, data = "{text}" }}\n')
    with open(os.path.join(OUT, "Rig.luau"), "w") as h:
        h.write("return game:GetService('HttpService'):JSONDecode([==[" + json.dumps(rig) + "]==])\n")
    print("wrote", len(os.listdir(OUT)), "modules to", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
