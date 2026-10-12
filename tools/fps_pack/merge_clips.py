#!/usr/bin/env python3
"""Merge one-clip-per-file GLBs (FBX2glTF output of a Unity kit's <Weapon>@<Clip>.FBX) into one.

    python3 merge_clips.py base.glb out.glb --name Draw [--clip Name=file.glb ...]
        [--idle Draw] [--drop-mesh REGEX] [--albedo IMG] [--normal IMG] [--material REGEX]

The base file keeps its nodes, meshes and skins; its first animation is renamed --name.
Each --clip file contributes its first animation, its channels re-targeted to the base's
nodes by name. --idle adds an Idle clip holding the last frame of that clip (the kit has
no idle). --drop-mesh removes helper meshes by node name. --albedo and --normal embed
textures into every material whose name matches --material (FBX2glTF cannot find the
kit's textures at the paths the FBX recorded). Nodes sharing a name (the kit nests a second
x_wrist_l under x_wrist_l) get _2, _3 by depth in every file, so channels, bakes and
Roblox bones stay one per node.
"""

import copy
import re
import sys

import numpy as np

from gltf_anim import Gltf
from rigidify import FLOAT, Writer

WIDTHS = {"translation": "VEC3", "rotation": "VEC4", "scale": "VEC3"}


def options(args, flag):
    return [args[i + 1] for i, a in enumerate(args) if a == flag]


def option(args, flag, default=None):
    found = options(args, flag)
    return found[0] if found else default


def unique_names(doc):
    par = {c: i for i, n in enumerate(doc["nodes"]) for c in n.get("children", [])}

    def depth(i):
        d = 0
        while i in par:
            i = par[i]
            d += 1
        return d

    groups = {}
    for i, n in enumerate(doc["nodes"]):
        groups.setdefault(n.get("name"), []).append(i)
    renamed = []
    for name, found in groups.items():
        if name is None or len(found) < 2:
            continue
        for k, i in enumerate(sorted(found, key=lambda j: (depth(j), j))[1:], start=2):
            doc["nodes"][i]["name"] = f"{name}_{k}"
            renamed.append(doc["nodes"][i]["name"])
    return renamed


def add_animation(doc, w, g, anim, name, node_map):
    samplers, channels, cache = [], [], {}
    for ch in anim["channels"]:
        target = ch["target"]
        node = node_map.get(target.get("node"))
        width = WIDTHS.get(target.get("path"))
        if node is None or width is None:
            continue
        smp = anim["samplers"][ch["sampler"]]
        times = g.accessor(smp["input"]).astype(np.float32).reshape(-1, 1)
        values = g.accessor(smp["output"]).astype(np.float32)
        samplers.append({
            "input": w.add(times, "SCALAR", FLOAT, minmax=True),
            "output": w.add(values, width, FLOAT),
            "interpolation": smp.get("interpolation", "LINEAR"),
        })
        cache[len(samplers) - 1] = values
        channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": target["path"]}})
    doc.setdefault("animations", []).append({"name": name, "samplers": samplers, "channels": channels})
    return cache


def held_last_frame(doc, w, source, values_by_sampler, name):
    samplers, channels = [], []
    for ch in source["channels"]:
        values = values_by_sampler[ch["sampler"]]
        last = values[-1:]
        samplers.append({
            "input": w.add(np.array([[0.0], [1.0 / 30.0]], np.float32), "SCALAR", FLOAT, minmax=True),
            "output": w.add(np.vstack([last, last]).astype(np.float32), WIDTHS[ch["target"]["path"]], FLOAT),
            "interpolation": "LINEAR",
        })
        channels.append({"sampler": len(samplers) - 1, "target": dict(ch["target"])})
    doc["animations"].append({"name": name, "samplers": samplers, "channels": channels})


def embed_image(doc, w, path):
    data = open(path, "rb").read()
    while len(w.blob) % 4:
        w.blob.append(0)
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(w.blob), "byteLength": len(data)})
    w.blob += data
    mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    doc.setdefault("images", []).append({"bufferView": len(doc["bufferViews"]) - 1, "mimeType": mime})
    doc.setdefault("textures", []).append({"source": len(doc["images"]) - 1})
    return len(doc["textures"]) - 1


def main():
    args = sys.argv[1:]
    base_path, out_path = args[0], args[1]
    base = Gltf(base_path)
    doc = copy.deepcopy(base.doc)
    renamed = unique_names(doc)
    if renamed:
        print(f"renamed duplicate nodes: {renamed}")
    w = Writer(doc, base.buffers[0])
    names = {n.get("name"): i for i, n in enumerate(doc["nodes"])}
    caches = {}

    first = (doc.get("animations") or [None])[0]
    doc["animations"] = []
    base_name = option(args, "--name", "Base")
    if first is not None:
        caches[base_name] = add_animation(doc, w, base, first, base_name, {i: i for i in range(len(doc["nodes"]))})

    for spec in options(args, "--clip"):
        clip_name, path = spec.split("=", 1)
        other = Gltf(path)
        unique_names(other.doc)
        anim = (other.doc.get("animations") or [None])[0]
        if anim is None:
            continue
        node_map = {i: names[n.get("name")] for i, n in enumerate(other.doc["nodes"]) if n.get("name") in names}
        caches[clip_name] = add_animation(doc, w, other, anim, clip_name, node_map)
        print(f"clip {clip_name}: {len(doc['animations'][-1]['channels'])} channels")

    idle_from = option(args, "--idle")
    if idle_from:
        source = next((a for a in doc["animations"] if a["name"] == idle_from), None)
        if source is not None:
            held_last_frame(doc, w, source, caches[idle_from], "Idle")

    drop = option(args, "--drop-mesh")
    if drop:
        pattern = re.compile(drop)
        for node in doc["nodes"]:
            if "mesh" in node and pattern.search(node.get("name", "")):
                node.pop("mesh")
                node.pop("skin", None)

    albedo, normal = option(args, "--albedo"), option(args, "--normal")
    material_re = re.compile(option(args, "--material", ".*"))
    base_tex = embed_image(doc, w, albedo) if albedo else None
    normal_tex = embed_image(doc, w, normal) if normal else None
    for mat in doc.get("materials", []):
        if not material_re.search(mat.get("name", "")):
            continue
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        if base_tex is not None:
            pbr["baseColorTexture"] = {"index": base_tex}
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
        if normal_tex is not None:
            mat["normalTexture"] = {"index": normal_tex}

    w.write(out_path)
    print(f"merged {len(doc['animations'])} clips -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
