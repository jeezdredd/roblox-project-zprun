#!/usr/bin/env python3
"""Write a GLB that keeps only the chosen meshes (with their skins, node tree, materials and
textures) and drops animations and everything unreferenced, for upload to Roblox.

    python3 strip_glb.py in.glb out.glb [--mesh REGEX ...] [--root-scale S] [--skin-fix JSON]

Without --mesh every mesh is kept. --root-scale wraps the scene in a scaled node, for packs
authored in centimetres without a unit node (Roblox clamps parts at 2048 studs); bake
with emit_luau.py --scale of the same factor. Nodes that pointed at a dropped mesh keep their place in
the tree but lose the mesh reference. --skin-fix rewrites vertex data and inverse bind
matrices of a broken Sketchfab skin (gltf_anim.apply_skin_fix, files in skin_fixes/) and
flips the triangle winding of any primitive whose normals end up facing inward.
"""

import json
import re
import struct
import sys

import numpy as np

from gltf_anim import Gltf, apply_skin_fix, load_skin_fix

NP_TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def winding_agrees(positions, normals, tris):
    """Share of triangles whose geometric normal points the same way as their vertex normals."""
    a, b, c = positions[tris[:, 0]], positions[tris[:, 1]], positions[tris[:, 2]]
    face = np.cross(b - a, c - a)
    vert = normals[tris[:, 0]] + normals[tris[:, 1]] + normals[tris[:, 2]]
    return float(((face * vert).sum(1) > 0).mean())


def main():
    args = sys.argv[1:]
    src, dst = args[0], args[1]
    patterns = [re.compile(args[i + 1]) for i, a in enumerate(args) if a == "--mesh"]
    root_scale = float(args[args.index("--root-scale") + 1]) if "--root-scale" in args else None
    g = Gltf(src)
    replaced = {}
    if "--skin-fix" in args:
        replaced = apply_skin_fix(g, load_skin_fix(args[args.index("--skin-fix") + 1]))
        for mesh in g.doc.get("meshes", []):
            for prim in mesh["primitives"]:
                attrs = prim["attributes"]
                if attrs.get("POSITION") not in replaced or "NORMAL" not in attrs or "indices" not in prim:
                    continue
                tris = g.accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
                share = winding_agrees(g.accessor(attrs["POSITION"]), g.accessor(attrs["NORMAL"]), tris)
                if share < 0.5:
                    replaced[prim["indices"]] = tris[:, ::-1].reshape(-1, 1).astype(np.float64)
                print(f"skin fix {mesh.get('name')}: normals agree with winding on {share:.1%}"
                      + (" -> winding flipped" if share < 0.5 else ""))
    doc = json.loads(json.dumps(g.doc))
    doc.pop("animations", None)
    if root_scale:
        scene = doc["scenes"][doc.get("scene", 0)]
        doc["nodes"].append({"name": "UnitScale", "scale": [root_scale] * 3, "children": scene["nodes"]})
        scene["nodes"] = [len(doc["nodes"]) - 1]

    keep_mesh = [not patterns or any(p.search(m.get("name", "")) for p in patterns) for m in doc.get("meshes", [])]
    mesh_map, meshes = {}, []
    for i, m in enumerate(doc.get("meshes", [])):
        if keep_mesh[i]:
            mesh_map[i] = len(meshes)
            meshes.append(m)
    doc["meshes"] = meshes
    used_skins = set()
    for node in doc["nodes"]:
        if "mesh" in node:
            if node["mesh"] in mesh_map:
                node["mesh"] = mesh_map[node["mesh"]]
                if "skin" in node:
                    used_skins.add(node["skin"])
            else:
                node.pop("mesh")
                node.pop("skin", None)
    skin_map, skins = {}, []
    for i, s in enumerate(doc.get("skins", [])):
        if i in used_skins:
            skin_map[i] = len(skins)
            skins.append(s)
    doc["skins"] = skins
    for node in doc["nodes"]:
        if "skin" in node:
            node["skin"] = skin_map[node["skin"]]

    # accessors, materials, textures, images still referenced
    acc_used, mat_used = set(), set()
    for m in meshes:
        for p in m["primitives"]:
            acc_used.update(p["attributes"].values())
            if "indices" in p:
                acc_used.add(p["indices"])
            if "material" in p:
                mat_used.add(p["material"])
            p.pop("targets", None)
    for s in skins:
        if "inverseBindMatrices" in s:
            acc_used.add(s["inverseBindMatrices"])

    def tex_refs(obj, out):
        if isinstance(obj, dict):
            if "index" in obj:
                out.add(obj["index"])
            for v in obj.values():
                tex_refs(v, out)
        elif isinstance(obj, list):
            for v in obj:
                tex_refs(v, out)

    mat_map, materials = {}, []
    for i, mat in enumerate(doc.get("materials", [])):
        if i in mat_used:
            mat_map[i] = len(materials)
            materials.append(mat)
    doc["materials"] = materials
    for m in meshes:
        for p in m["primitives"]:
            if "material" in p:
                p["material"] = mat_map[p["material"]]
    tex_used = set()
    tex_refs(materials, tex_used)
    tex_map, textures = {}, []
    for i, t in enumerate(doc.get("textures", [])):
        if i in tex_used:
            tex_map[i] = len(textures)
            textures.append(t)
    doc["textures"] = textures

    def remap_tex(obj):
        if isinstance(obj, dict):
            if "index" in obj and obj["index"] in tex_map:
                obj["index"] = tex_map[obj["index"]]
            for v in obj.values():
                remap_tex(v)
        elif isinstance(obj, list):
            for v in obj:
                remap_tex(v)

    remap_tex(materials)
    img_used = {t["source"] for t in textures if "source" in t}
    img_map, images = {}, []
    for i, im in enumerate(doc.get("images", [])):
        if i in img_used:
            img_map[i] = len(images)
            images.append(im)
    doc["images"] = images
    for t in textures:
        if "source" in t:
            t["source"] = img_map[t["source"]]

    # rebuild one buffer from the views that are still referenced
    views_needed = set()
    for a in acc_used:
        acc = doc["accessors"][a]
        if "bufferView" in acc and a not in replaced:
            views_needed.add(acc["bufferView"])
    for im in images:
        if "bufferView" in im:
            views_needed.add(im["bufferView"])
    blob = bytearray()
    view_map, views = {}, []
    for i in sorted(views_needed):
        v = dict(doc["bufferViews"][i])
        data = g.buffers[v["buffer"]][v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        while len(blob) % 4:
            blob.append(0)
        v["buffer"] = 0
        v["byteOffset"] = len(blob)
        blob += data
        view_map[i] = len(views)
        views.append(v)
    acc_map, accessors = {}, []
    for i in sorted(acc_used):
        a = dict(doc["accessors"][i])
        if i in replaced:
            data = np.ascontiguousarray(replaced[i].astype(NP_TYPES[a["componentType"]]))
            while len(blob) % 4:
                blob.append(0)
            view = {"buffer": 0, "byteOffset": len(blob), "byteLength": data.nbytes}
            if a["type"] != "SCALAR" and a["type"] not in ("MAT2", "MAT3", "MAT4"):
                view["byteStride"] = data.shape[1] * data.itemsize
            blob += data.tobytes()
            views.append(view)
            a["bufferView"] = len(views) - 1
            a["byteOffset"] = 0
            if "min" in a:
                a["min"] = [float(x) for x in data.reshape(a["count"], -1).min(0)]
                a["max"] = [float(x) for x in data.reshape(a["count"], -1).max(0)]
        elif "bufferView" in a:
            a["bufferView"] = view_map[a["bufferView"]]
        a.pop("sparse", None)
        acc_map[i] = len(accessors)
        accessors.append(a)
    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
    for s in skins:
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for im in images:
        if "bufferView" in im:
            im["bufferView"] = view_map[im["bufferView"]]
    doc["accessors"] = accessors
    doc["bufferViews"] = views
    doc["buffers"] = [{"byteLength": len(blob)}]
    for key in ("samplers", "textures", "images", "materials", "skins"):
        if key in doc and not doc[key]:
            doc.pop(key)

    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(dst, "wb") as handle:
        handle.write(b"glTF" + struct.pack("<II", 2, total))
        handle.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        handle.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    tris = sum(doc["accessors"][p["indices"]]["count"] // 3 for m in meshes for p in m["primitives"] if "indices" in p)
    print(f"wrote {dst}: {len(meshes)} meshes, {tris} tris, {len(images)} images, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    sys.exit(main())
