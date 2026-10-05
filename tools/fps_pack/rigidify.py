#!/usr/bin/env python3
"""Turn a pack whose weapon is made of rigid meshes hanging under joint nodes into one the
Roblox importer animates, and start every clip at time zero.

    python3 rigidify.py in.glb out.glb [--joint-regex REGEX]

Roblox imports bones only from skins: a mesh that is not skinned stays a loose MeshPart
and does not follow its parent joint (the Fab BarcodeGames M4 and G17 packs: the arms are
skinned, the receiver, magazines, bolt and trigger are plain meshes under Main_j_049,
Mag1_j_050 and so on). Each such mesh becomes skinned to its nearest ancestor whose name
matches --joint-regex (default `_j_\\d+$`), weight 1: its vertices are moved into the
scene's rest world, it gets JOINTS_0/WEIGHTS_0, and a new skin over those joints carries
their inverse rest worlds. The mesh node moves to the scene root without a transform, as
glTF asks of skinned meshes.

Fab's converter also writes every take of a multi-take FBX on one timeline (Reload
0.03-3.67 s, Reload_Empty 3.70-7.50 s, ...): each animation's times are shifted so the
clip starts at 0, which is what gltf_anim.py bake samples from.
"""

import copy
import json
import os
import re
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gltf_anim import Gltf, node_rest, parents, trs_matrix, world_matrices  # noqa: E402

FLOAT, UBYTE, USHORT = 5126, 5121, 5123


class Writer:
    def __init__(self, doc, blob):
        self.doc = doc
        self.blob = bytearray(blob)

    def add(self, array, gltf_type, component, target=None, minmax=False):
        data = np.ascontiguousarray(array)
        while len(self.blob) % 4:
            self.blob.append(0)
        view = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": data.nbytes}
        if target:
            view["target"] = target
        self.blob += data.tobytes()
        self.doc["bufferViews"].append(view)
        count = data.shape[0]
        acc = {"bufferView": len(self.doc["bufferViews"]) - 1, "componentType": component, "count": count, "type": gltf_type}
        if minmax:
            flat = data.reshape(count, -1).astype(np.float64)
            acc["min"] = [float(x) for x in flat.min(0)]
            acc["max"] = [float(x) for x in flat.max(0)]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def write(self, path):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc["buffers"] = [{"byteLength": len(self.blob)}]
        js = json.dumps(self.doc, separators=(",", ":")).encode("utf-8")
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(self.blob), 0x004E4942))
            f.write(self.blob)


def main():
    args = sys.argv[1:]
    src, dst = args[0], args[1]
    joint_re = re.compile(args[args.index("--joint-regex") + 1] if "--joint-regex" in args else r"_j_\d+$")
    g = Gltf(src)
    if len(g.buffers) != 1:
        raise SystemExit("expected a single-buffer GLB")
    doc = copy.deepcopy(g.doc)
    w = Writer(doc, g.buffers[0])
    nodes = doc["nodes"]
    par = parents(doc)
    rest_local = {i: trs_matrix(*node_rest(n)) for i, n in enumerate(nodes)}
    rest_world = world_matrices(doc, rest_local)

    def joint_of(i):
        j = par.get(i)
        while j is not None:
            if joint_re.search(nodes[j].get("name", "")):
                return j
            j = par.get(j)
        return None

    rigid = [i for i, n in enumerate(nodes) if "mesh" in n and "skin" not in n]
    plan = []
    for i in rigid:
        j = joint_of(i)
        if j is None:
            print(f"left as is (no joint above): {nodes[i].get('name')}")
            continue
        plan.append((i, j))
    if not plan:
        print("nothing to rigidify")
    joints = sorted({j for _, j in plan})
    # every joint node under the weapon root keeps its place even if no mesh hangs on it
    for i, n in enumerate(nodes):
        if joint_re.search(n.get("name", "")) and i not in joints:
            joints.append(i)
    joints.sort()
    # Roblox bones carry no scale: a joint's bind is its rest world with the scale taken
    # out (the Fab M4's magazine joints are scaled x4.2), or a scaled joint would throw
    # its mesh across the scene. The vertices already sit in the rest world.
    # Roblox also reads the inverse bind's scale as the skin's unit (bone positions are
    # the rest translation times that scale), so every joint carries the same uniform
    # world scale as the joints of the pack's own skins (the Fab FBX conversion: 0.01).
    unit = 1.0
    for skin in g.doc.get("skins", []):
        if skin.get("joints"):
            unit = float(np.linalg.norm(rest_world[skin["joints"][0]][:3, 0]))
            break
    print(f"skin unit scale {unit:g}")

    def unscaled(m):
        out = m.copy()
        out[:3, :3] = m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0)[None, :] * unit
        return out

    ibm = np.stack([np.linalg.inv(unscaled(rest_world[j])).T for j in joints]).astype(np.float32).reshape(len(joints), 16)
    doc.setdefault("skins", []).append({"name": "WeaponParts", "joints": joints, "inverseBindMatrices": w.add(ibm, "MAT4", FLOAT)})
    skin_index = len(doc["skins"]) - 1

    scene = doc["scenes"][doc.get("scene", 0)]
    for i, j in plan:
        node = nodes[i]
        world = rest_world[i]
        normal_m = np.linalg.inv(world[:3, :3]).T
        mesh = copy.deepcopy(doc["meshes"][node["mesh"]])
        mesh["name"] = (mesh.get("name") or f"mesh{node['mesh']}") + "_skinned"
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = g.accessor(attrs["POSITION"])
            pos_w = (np.c_[pos, np.ones(len(pos))] @ world.T)[:, :3].astype(np.float32)
            attrs["POSITION"] = w.add(pos_w, "VEC3", FLOAT, 34962, minmax=True)
            if "NORMAL" in attrs:
                nrm = g.accessor(attrs["NORMAL"]) @ normal_m.T
                nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
                attrs["NORMAL"] = w.add(nrm.astype(np.float32), "VEC3", FLOAT, 34962)
            if "TANGENT" in attrs:
                tan = g.accessor(attrs["TANGENT"])
                t3 = tan[:, :3] @ world[:3, :3].T
                t3 /= np.maximum(np.linalg.norm(t3, axis=1, keepdims=True), 1e-9)
                attrs["TANGENT"] = w.add(np.c_[t3, tan[:, 3:4]].astype(np.float32), "VEC4", FLOAT, 34962)
            count = len(pos)
            jidx = np.zeros((count, 4), np.uint16)
            jidx[:, 0] = joints.index(j)
            weights = np.zeros((count, 4), np.float32)
            weights[:, 0] = 1.0
            attrs["JOINTS_0"] = w.add(jidx, "VEC4", USHORT, 34962)
            attrs["WEIGHTS_0"] = w.add(weights, "VEC4", FLOAT, 34962)
            # a mirrored node transform flips the winding
            if np.linalg.det(world[:3, :3]) < 0 and "indices" in prim:
                tris = g.accessor(prim["indices"]).astype(np.uint32).reshape(-1, 3)[:, ::-1].reshape(-1, 1)
                prim["indices"] = w.add(np.ascontiguousarray(tris), "SCALAR", 5125, 34963)
        doc["meshes"].append(mesh)
        nodes.append({"name": (node.get("name") or f"node{i}") + "_skinned", "mesh": len(doc["meshes"]) - 1, "skin": skin_index})
        scene["nodes"].append(len(nodes) - 1)
        node.pop("mesh")
        print(f"skinned {node.get('name')} -> {nodes[j].get('name')}")

    # every clip from time zero
    for anim in doc.get("animations", []):
        inputs = {s["input"] for s in anim["samplers"]}
        t0 = min(float(g.accessor(a)[:, 0].min()) for a in inputs)
        if t0 <= 1e-6:
            continue
        remap = {}
        for a in inputs:
            times = (g.accessor(a)[:, 0] - t0).astype(np.float32).reshape(-1, 1)
            remap[a] = w.add(times, "SCALAR", FLOAT, minmax=True)
        for s in anim["samplers"]:
            s["input"] = remap[s["input"]]
        print(f"clip {anim.get('name')}: shifted by {t0:.3f} s")

    w.write(dst)
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
