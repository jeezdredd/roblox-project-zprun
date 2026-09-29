#!/usr/bin/env python3
"""Read a glTF 2.0 file (.gltf + .bin or .glb) and pull out what the viewmodel needs:
meshes, materials, the skin (joint hierarchy with rest transforms) and every animation
sampled at a fixed rate as per-joint local transforms.

No Blender. numpy only.

    python3 gltf_anim.py report  scene.gltf
    python3 gltf_anim.py bake    scene.gltf out.json [--fps 30] [--extra NODE ...] [--skin-fix JSON]

`bake` writes, per clip and joint, the change from the rest pose in model space and in
Roblox axes (the importer turns glTF 180 degrees about Y and keeps metres as studs). The
importer drops bones without skin weights and folds their transforms into the children,
so local transforms do not survive import; a model-space change applied to each imported
bone's own rest world does. Joints a clip never moves are left out of that clip.
--extra bakes nodes that carry no skin (the camera bone) and records their rest world.
--calibrate JSON UNIT aligns the bind pose to the bones Roblox built (see roblox_rest/);
UNIT is the UnitScale the rig was uploaded with.
--skin-fix JSON repairs a skin whose inverse bind matrices do not match its vertex data
(see skin_fixes/ and apply_skin_fix below); strip_glb.py applies the same file.
"""

import base64
import json
import os
import struct
import sys

import numpy as np

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
NORMALIZE = {np.int8: 127.0, np.uint8: 255.0, np.int16: 32767.0, np.uint16: 65535.0}


# ---------------------------------------------------------------- loading

class Gltf:
    def __init__(self, path):
        self.path = path
        self.dir = os.path.dirname(os.path.abspath(path))
        raw = open(path, "rb").read()
        glb_bin = None
        if raw[:4] == b"glTF":
            _, _, length = struct.unpack_from("<III", raw, 0)
            offset = 12
            doc = None
            while offset < length:
                chunk_len, chunk_type = struct.unpack_from("<II", raw, offset)
                data = raw[offset + 8: offset + 8 + chunk_len]
                if chunk_type == 0x4E4F534A:
                    doc = json.loads(data.decode("utf-8"))
                elif chunk_type == 0x004E4942:
                    glb_bin = data
                offset += 8 + chunk_len
        else:
            doc = json.loads(raw.decode("utf-8"))
        self.doc = doc
        # accessor index -> replacement data (float64 rows), set by apply_skin_fix
        self.override = {}
        self.buffers = []
        for i, buf in enumerate(doc.get("buffers", [])):
            uri = buf.get("uri")
            if uri is None:
                self.buffers.append(glb_bin)
            elif uri.startswith("data:"):
                self.buffers.append(base64.b64decode(uri.split(",", 1)[1]))
            else:
                self.buffers.append(open(os.path.join(self.dir, uri), "rb").read())

    def accessor(self, index):
        if index in self.override:
            return self.override[index].copy()
        acc = self.doc["accessors"][index]
        dtype = COMPONENT[acc["componentType"]]
        width = WIDTH[acc["type"]]
        count = acc["count"]
        if "bufferView" in acc:
            view = self.doc["bufferViews"][acc["bufferView"]]
            buf = self.buffers[view["buffer"]]
            start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            itemsize = np.dtype(dtype).itemsize * width
            stride = view.get("byteStride", itemsize)
            if stride == itemsize:
                out = np.frombuffer(buf, dtype, count * width, start).reshape(count, width)
            else:
                rows = [np.frombuffer(buf, dtype, width, start + i * stride) for i in range(count)]
                out = np.stack(rows)
        else:
            out = np.zeros((count, width), dtype)
        out = out.astype(np.float64)
        if acc.get("normalized") and dtype in NORMALIZE:
            out = out / NORMALIZE[dtype]
        if "sparse" in acc:
            sp = acc["sparse"]
            iv = self.doc["bufferViews"][sp["indices"]["bufferView"]]
            idx = np.frombuffer(self.buffers[iv["buffer"]], COMPONENT[sp["indices"]["componentType"]], sp["count"],
                                iv.get("byteOffset", 0) + sp["indices"].get("byteOffset", 0))
            vv = self.doc["bufferViews"][sp["values"]["bufferView"]]
            vals = np.frombuffer(self.buffers[vv["buffer"]], dtype, sp["count"] * width,
                                 vv.get("byteOffset", 0) + sp["values"].get("byteOffset", 0)).reshape(-1, width)
            out = out.copy()
            out[idx.astype(int)] = vals
        return out


# ---------------------------------------------------------------- math

def quat_norm(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


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


def trs_matrix(t, r, s):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(r) * np.asarray(s)[None, :]
    m[:3, 3] = t
    return m


def decompose(m):
    t = m[:3, 3].copy()
    s = np.linalg.norm(m[:3, :3], axis=0)
    r = mat_to_quat(m[:3, :3] / s[None, :])
    return t, r, s


def slerp(a, b, u):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        return quat_norm(a + u * (b - a))
    th = np.arccos(d)
    return (np.sin((1 - u) * th) * a + np.sin(u * th) * b) / np.sin(th)


# ---------------------------------------------------------------- scene

def node_rest(node):
    if "matrix" in node:
        m = np.array(node["matrix"], float).reshape(4, 4).T
        return decompose(m)
    return (np.array(node.get("translation", [0, 0, 0]), float),
            np.array(node.get("rotation", [0, 0, 0, 1]), float),
            np.array(node.get("scale", [1, 1, 1]), float))


def parents(doc):
    out = {}
    for i, node in enumerate(doc.get("nodes", [])):
        for c in node.get("children", []):
            out[c] = i
    return out


def node_name(doc, i):
    return doc["nodes"][i].get("name") or f"node{i}"


def sample_channel(times, values, interp, path, t):
    width = values.shape[1]
    if interp == "CUBICSPLINE":
        values = values.reshape(len(times), 3, width)
    if t <= times[0]:
        v = values[0][1] if interp == "CUBICSPLINE" else values[0]
        return quat_norm(v) if path == "rotation" else v
    if t >= times[-1]:
        v = values[-1][1] if interp == "CUBICSPLINE" else values[-1]
        return quat_norm(v) if path == "rotation" else v
    k = int(np.searchsorted(times, t, side="right")) - 1
    t0, t1 = times[k], times[k + 1]
    dt = t1 - t0
    u = (t - t0) / dt if dt > 0 else 0.0
    if interp == "STEP":
        v = values[k]
    elif interp == "CUBICSPLINE":
        p0, m0 = values[k][1], values[k][2] * dt
        p1, m1 = values[k + 1][1], values[k + 1][0] * dt
        u2, u3 = u * u, u * u * u
        v = (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1
    elif path == "rotation":
        return slerp(quat_norm(values[k]), quat_norm(values[k + 1]), u)
    else:
        v = values[k] * (1 - u) + values[k + 1] * u
    return quat_norm(v) if path == "rotation" else v


def clips(g):
    doc = g.doc
    out = []
    for ai, anim in enumerate(doc.get("animations", [])):
        chans = []
        duration = 0.0
        for ch in anim["channels"]:
            tgt = ch["target"]
            if "node" not in tgt or tgt["path"] == "weights":
                continue
            smp = anim["samplers"][ch["sampler"]]
            times = g.accessor(smp["input"])[:, 0]
            values = g.accessor(smp["output"])
            duration = max(duration, float(times[-1]))
            chans.append((tgt["node"], tgt["path"], times, values, smp.get("interpolation", "LINEAR")))
        out.append({"name": anim.get("name") or f"anim{ai}", "duration": duration, "channels": chans})
    return out


def local_at(rest, chans, node, t):
    tr, rr, sr = rest[node]
    for n, path, times, values, interp in chans:
        if n != node:
            continue
        v = sample_channel(times, values, interp, path, t)
        if path == "translation":
            tr = v
        elif path == "rotation":
            rr = v
        elif path == "scale":
            sr = v
    return tr, rr, sr



# ---------------------------------------------------------------- skin repair

def load_skin_fix(path):
    fix = json.load(open(path))
    return {
        "meshes": fix.get("meshes"),
        "vertex": np.array(fix["vertex"], float) if "vertex" in fix else None,
        "ibm_post": np.array(fix["ibm_post"], float) if "ibm_post" in fix else None,
    }


def apply_skin_fix(g, fix):
    """Repairs a skin whose inverse bind matrices were written for another mesh's space.

    Sketchfab's glTF export merges every skinned mesh of an FBX into one skin but keeps
    a single set of inverse bind matrices, computed for the first mesh (in the Uzi pack a
    scaled background plane), and stores the other meshes' vertices in a mangled space.
    Standard skinning then gives a mesh thousands of units wide next to bones in metres,
    which is what Roblox imported. `fix` holds two matrices derived from the pack's source
    FBX (Transform/TransformLink of its skin clusters):
      vertex:   maps the stored POSITION/NORMAL/TANGENT data of the meshes matching the
                `meshes` regex into the skinned mesh node's space;
      ibm_post: IBM' = IBM @ ibm_post, so every joint binds at its true bind pose in
                that space.
    Joints whose repaired bind is not rigid (unweighted Rigify helpers that had no
    cluster) are bound at their node rest pose instead. Returns {accessor: array} of the
    vertex attributes it rewrote (strip_glb.py writes those into the new buffer)."""
    import re
    doc = g.doc
    rest_local = {i: trs_matrix(*node_rest(n)) for i, n in enumerate(doc.get("nodes", []))}
    rest_world = world_matrices(doc, rest_local)
    changed = {}
    pattern = re.compile(fix["meshes"]) if fix.get("meshes") else None
    if fix.get("ibm_post") is not None:
        done = set()
        for ni, node in enumerate(doc.get("nodes", [])):
            if "mesh" not in node or "skin" not in node or node["skin"] in done:
                continue
            done.add(node["skin"])
            skin = doc["skins"][node["skin"]]
            acc = skin["inverseBindMatrices"]
            ibm = g.accessor(acc).reshape(-1, 4, 4).transpose(0, 2, 1)
            out = []
            for j, m in zip(skin["joints"], ibm):
                m2 = m @ fix["ibm_post"]
                sv = np.linalg.svd(np.linalg.inv(m2)[:3, :3])[1]
                if abs(sv.max() - 1) > 0.01 or abs(sv.min() - 1) > 0.01:
                    m2 = np.linalg.inv(rest_world[j]) @ rest_world[ni]
                out.append(m2)
            g.override[acc] = np.array(out).transpose(0, 2, 1).reshape(-1, 16)
            changed[acc] = g.override[acc]
    vertex = fix.get("vertex")
    if vertex is not None:
        lin = vertex[:3, :3]
        seen = set()
        for mesh in doc.get("meshes", []):
            if pattern and not pattern.search(mesh.get("name", "")):
                continue
            for prim in mesh["primitives"]:
                attrs = prim["attributes"]
                if "POSITION" in attrs and attrs["POSITION"] not in seen:
                    seen.add(attrs["POSITION"])
                    p = g.accessor(attrs["POSITION"])
                    g.override[attrs["POSITION"]] = p @ lin.T + vertex[:3, 3]
                    changed[attrs["POSITION"]] = g.override[attrs["POSITION"]]
                for key in ("NORMAL", "TANGENT"):
                    if key in attrs and attrs[key] not in seen:
                        seen.add(attrs[key])
                        v = g.accessor(attrs[key])
                        d = v[:, :3] @ lin.T
                        d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-12)
                        g.override[attrs[key]] = np.c_[d, v[:, 3:]] if v.shape[1] > 3 else d
                        changed[attrs[key]] = g.override[attrs[key]]
    return changed

# ---------------------------------------------------------------- commands

def report(path):
    g = Gltf(path)
    doc = g.doc
    print("file", os.path.basename(path), "generator", doc.get("asset", {}).get("generator"))
    tris_total = 0
    for mi, mesh in enumerate(doc.get("meshes", [])):
        tris = 0
        for prim in mesh["primitives"]:
            if "indices" in prim:
                tris += doc["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += doc["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
        tris_total += tris
        mats = [doc["materials"][p["material"]].get("name") if "material" in p else None for p in mesh["primitives"]]
        users = [node_name(doc, i) for i, n in enumerate(doc["nodes"]) if n.get("mesh") == mi]
        skinned = any("skin" in n for n in doc["nodes"] if n.get("mesh") == mi)
        print(f"mesh {mi} {mesh.get('name')!r} tris={tris} skinned={skinned} nodes={users} materials={mats}")
    print("triangles total", tris_total)
    for ti, tex in enumerate(doc.get("images", [])):
        print("image", ti, tex.get("name"), tex.get("uri") or tex.get("mimeType"))
    par = parents(doc)
    for si, skin in enumerate(doc.get("skins", [])):
        joints = skin["joints"]
        print(f"skin {si} {skin.get('name')!r} joints={len(joints)}")
        for j in joints:
            depth, p = 0, par.get(j)
            while p is not None:
                depth, p = depth + 1, par.get(p)
            print("  " * (depth + 1) + node_name(doc, j))
    for c in clips(g):
        nodes = sorted({node_name(doc, ch[0]) for ch in c["channels"]})
        print(f"anim {c['name']!r} duration={c['duration']:.3f}s channels={len(c['channels'])} nodes={len(nodes)}")


FLIP = np.diag([-1.0, 1.0, -1.0, 1.0])  # Roblox's glTF importer turns the scene 180 degrees about Y


def world_matrices(doc, local):
    """local: {node: 4x4}. Returns {node: 4x4 world} for every node."""
    par = parents(doc)
    out = {}

    def get(i):
        if i in out:
            return out[i]
        m = local[i]
        p = par.get(i)
        if p is not None:
            m = get(p) @ m
        out[i] = m
        return m

    for i in local:
        get(i)
    return out


def bake(path, out_path, fps=30.0, extra=(), calibrate=None, skin_fix=None):
    """Per clip and joint, the model-space change from the rest pose, in Roblox axes:
    D(t) = F * G(t) * G_rest^-1 * F^-1. At runtime the target world of an imported bone
    is D(t) * restWorld, whatever hierarchy the importer rebuilt. `extra` names nodes
    without skin weights to bake as well (the camera bone), with their rest world."""
    g = Gltf(path)
    if skin_fix:
        apply_skin_fix(g, load_skin_fix(skin_fix))
    doc = g.doc
    n_nodes = len(doc.get("nodes", []))
    rest = {i: node_rest(n) for i, n in enumerate(doc.get("nodes", []))}
    rest_local = {i: trs_matrix(*rest[i]) for i in range(n_nodes)}
    rest_world = world_matrices(doc, rest_local)
    # only joints that carry skin weights, and their ancestors: Roblox's importer drops the
    # rest (Rigify control and mechanism bones), so baking them is wasted space
    par = parents(doc)
    weighted = set()
    for ni, node in enumerate(doc.get("nodes", [])):
        if "mesh" not in node or "skin" not in node:
            continue
        skin_joints = doc["skins"][node["skin"]]["joints"]
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            attrs = prim["attributes"]
            for set_index in range(4):
                jk, wk = f"JOINTS_{set_index}", f"WEIGHTS_{set_index}"
                if jk not in attrs or wk not in attrs:
                    break
                js = g.accessor(attrs[jk]).astype(int)
                ws = g.accessor(attrs[wk])
                for idx in np.unique(js[ws > 1e-4]):
                    weighted.add(skin_joints[int(idx)])
    keep = set()
    for j in weighted:
        while j is not None and j not in keep:
            keep.add(j)
            j = par.get(j)
    joints = []
    for skin in doc.get("skins", []):
        for j in skin["joints"]:
            if j not in joints and j in keep:
                joints.append(j)
    names = {node_name(doc, i): i for i in range(n_nodes)}
    extras = [names[e] for e in extra if e in names]
    result = {"source": os.path.basename(path), "fps": fps, "space": "roblox-model-delta", "extras": {}, "clips": []}
    for e in extras:
        m = FLIP @ rest_world[e] @ FLIP
        t, r, s = decompose(m)
        result["extras"][node_name(doc, e)] = [round(float(x), 5) for x in (*t, *r)]
    # Roblox builds each bone at its bind pose (the pose the mesh was skinned in), which
    # is not always the node's rest transform: some packs store the first frame of an
    # animation there. Bind world = skinned mesh node world * inverse bind matrix.
    bind_world = {}
    for ni, node in enumerate(doc.get("nodes", [])):
        if "mesh" not in node or "skin" not in node:
            continue
        skin = doc["skins"][node["skin"]]
        if "inverseBindMatrices" not in skin:
            continue
        ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        for j, m in zip(skin["joints"], ibm):
            if j not in bind_world:
                bind_world[j] = rest_world[ni] @ np.linalg.inv(m)
    if calibrate:
        # Roblox's importer does not build every skin from the same reference: in the
        # Sketchfab UE packs the arms come in at the bind pose turned 90 degrees about X,
        # while a weapon skin may come in at the node rest pose instead. The bone positions
        # Roblox actually built (read in Studio, tools/fps_pack/roblox_rest) decide:
        # fit one similarity from the file's bind pose on the largest skin, then per skin
        # keep whichever of (fitted bind, node rest) lands on the Roblox bones.
        cal_path, unit = calibrate
        cal = json.load(open(cal_path))["bones"]
        skin_of = {}
        for ni, node in enumerate(doc.get("nodes", [])):
            if "mesh" in node and "skin" in node:
                for j in doc["skins"][node["skin"]]["joints"]:
                    skin_of.setdefault(j, node["skin"])
        points = {}
        for name, pos in cal.items():
            j = names.get(name)
            if j is not None and j in bind_world:
                points.setdefault(skin_of.get(j), []).append((j, np.array([-pos[0], pos[1], -pos[2]]) / unit))
        biggest = max(points, key=lambda k: len(points[k]))
        src = np.array([bind_world[j][:3, 3] for j, _ in points[biggest]])
        dst = np.array([p for _, p in points[biggest]])
        mu_s, mu_d = src.mean(0), dst.mean(0)
        cov = (dst - mu_d).T @ (src - mu_s) / len(src)
        U, S, Vt = np.linalg.svd(cov)
        D = np.diag([1, 1, np.sign(np.linalg.det(U @ Vt))])
        R = U @ D @ Vt
        var = ((src - mu_s) ** 2).sum(1).mean()
        scale_fit = np.trace(np.diag(S) @ D) / var if var > 1e-12 else 1.0
        X = np.eye(4)
        X[:3, :3] = scale_fit * R
        X[:3, 3] = mu_d - scale_fit * R @ mu_s
        choice = {}
        for skin, pts in points.items():
            err_bind = np.mean([np.linalg.norm((X @ bind_world[j])[:3, 3] - p) for j, p in pts])
            err_rest = np.mean([np.linalg.norm(rest_world[j][:3, 3] - p) for j, p in pts])
            choice[skin] = "bind" if err_bind <= err_rest else "rest"
            print(f"calibration skin {skin}: {len(pts)} bones, bind err {err_bind * unit:.4f}, rest err {err_rest * unit:.4f} -> {choice[skin]}")
        fitted = {}
        for j, m in bind_world.items():
            if choice.get(skin_of.get(j), "bind") == "bind":
                fitted[j] = X @ m
            else:
                fitted[j] = rest_world[j]
        bind_world = fitted
    rest_for = {j: bind_world.get(j, rest_world[j]) for j in joints + extras}
    inv_rest = {j: np.linalg.inv(rest_for[j]) for j in joints + extras}
    for c in clips(g):
        frames = max(1, int(round(c["duration"] * fps)) + 1)
        by_node = {}
        for ch in c["channels"]:
            by_node.setdefault(ch[0], []).append(ch)
        rows = {j: [] for j in joints + extras}
        for f in range(frames):
            t = min(f / fps, c["duration"])
            local = dict(rest_local)
            for node, chans in by_node.items():
                local[node] = trs_matrix(*local_at(rest, chans, node, t))
            world = world_matrices(doc, local)
            for j in joints + extras:
                d = FLIP @ world[j] @ inv_rest[j] @ FLIP
                tt, rr, _ = decompose(d)
                if rr[3] < 0:
                    rr = -rr
                rows[j].append([round(float(x), 5) for x in (*tt, *rr)])
        tracks = {}
        for j, r in rows.items():
            arr = np.array(r)
            if np.abs(arr[:, :3]).max() < 1e-4 and np.abs(arr[:, 3:6]).max() < 1e-4:
                continue
            tracks[node_name(doc, j)] = r
        result["clips"].append({"name": c["name"], "duration": round(c["duration"], 5), "frames": frames, "tracks": tracks})
        print(f"clip {c['name']!r} {c['duration']:.2f}s frames={frames} moving joints={len(tracks)}")
    with open(out_path, "w") as handle:
        json.dump(result, handle, separators=(",", ":"))
    print("wrote", out_path)


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "report":
        report(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "bake":
        fps = float(sys.argv[sys.argv.index("--fps") + 1]) if "--fps" in sys.argv else 30.0
        extra = [sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--extra"]
        cal = None
        if "--calibrate" in sys.argv:
            k = sys.argv.index("--calibrate")
            cal = (sys.argv[k + 1], float(sys.argv[k + 2]))
        fix = sys.argv[sys.argv.index("--skin-fix") + 1] if "--skin-fix" in sys.argv else None
        bake(sys.argv[2], sys.argv[3], fps, extra, cal, fix)
    else:
        print(__doc__)
        sys.exit(1)
