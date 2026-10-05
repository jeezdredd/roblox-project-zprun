#!/usr/bin/env python3
"""The scene splitter on a synthetic city.

Run from the repository root:  python3 tests/cityimport/run.py

The scene is generated here (no real asset is read or committed): a 120 m ground grid
with planar UVs and a 2048 px texture, a finely subdivided 10 m building over the
triangle cap, small props instanced around one spot and one mirrored, all under a
turned and moved root node. Checks the flattening to world space and the scale, the
cells, the triangle cap (split, lossless), the merge of small meshes, the collision
hints, the texture cap, the winding of mirrored nodes, decimation with locked borders
(no cracks between cells, UVs carried over), the .gltf reader, layout.json, the Luau
layout module and the manifest rows. Exits non-zero when any check failed.
"""

import base64
import io
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "city_import"))

import emit_layout  # noqa: E402
import gltf_io  # noqa: E402
import split_scene  # noqa: E402

failures = 0
SCALE = 1 / 0.28

try:
    import pyfqmr  # noqa: F401
    import scipy  # noqa: F401

    HAVE_DECIMATION = True
except ImportError:
    HAVE_DECIMATION = False


def check(name, condition, detail=""):
    global failures
    if not condition:
        failures += 1
        print(f"  FAIL {name}" + (f" ({detail})" if detail else ""))


def group(name, body):
    before = failures
    try:
        body()
    except Exception as error:
        import traceback

        traceback.print_exc()
        check(f"{name} raised", False, f"{type(error).__name__}: {error}")
    print(("ok   " if failures == before else "FAIL ") + name)


# The synthetic scene ------------------------------------------------------------------

GROUND = 120.0
GROUND_STEPS = 40
BUILDING = 10.0
BUILDING_STEPS = 40  # 6 faces x 40 x 40 x 2 = 19200 triangles, over the 18000 cap
PROP = 0.5
ROOT_YAW = 90.0
ROOT_MOVE = (10.0, 0.0, 0.0)


def grid(steps, size):
    xs = np.linspace(-size / 2, size / 2, steps + 1)
    gx, gz = np.meshgrid(xs, xs, indexing="ij")
    positions = np.stack([gx.ravel(), np.zeros(gx.size), gz.ravel()], axis=1)
    uvs = np.stack([(gx.ravel() + size / 2) / size, (gz.ravel() + size / 2) / size], axis=1)
    triangles = []
    for i in range(steps):
        for j in range(steps):
            a = i * (steps + 1) + j
            b = a + 1
            c = a + steps + 1
            d = c + 1
            # counter-clockwise seen from above (+Y)
            triangles += [[a, b, c], [b, d, c]]
    return positions, uvs, np.array(triangles)


def box(steps, size):
    """A box with every face a steps x steps grid; outward winding and normals."""
    positions, normals, uvs, triangles = [], [], [], []
    half = size / 2
    faces = [
        (np.array([1, 0, 0]), np.array([0, 0, -1]), np.array([0, 1, 0])),
        (np.array([-1, 0, 0]), np.array([0, 0, 1]), np.array([0, 1, 0])),
        (np.array([0, 1, 0]), np.array([1, 0, 0]), np.array([0, 0, -1])),
        (np.array([0, -1, 0]), np.array([1, 0, 0]), np.array([0, 0, 1])),
        (np.array([0, 0, 1]), np.array([1, 0, 0]), np.array([0, 1, 0])),
        (np.array([0, 0, -1]), np.array([-1, 0, 0]), np.array([0, 1, 0])),
    ]
    for normal, u_axis, v_axis in faces:
        base = len(positions)
        for i in range(steps + 1):
            for j in range(steps + 1):
                u = -half + size * i / steps
                v = -half + size * j / steps
                positions.append(normal * half + u_axis * u + v_axis * v)
                normals.append(normal)
                uvs.append([i / steps, j / steps])
        for i in range(steps):
            for j in range(steps):
                a = base + i * (steps + 1) + j
                b = a + 1
                c = a + steps + 1
                d = c + 1
                triangles += [[a, c, b], [b, c, d]]
    positions = np.array(positions, dtype=np.float64)
    triangles = np.array(triangles)
    # make every face wind outward (cross product along the face normal)
    p = positions[triangles]
    cross = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    face_normal = np.array(normals)[triangles[:, 0]]
    flip = (cross * face_normal).sum(axis=1) < 0
    triangles[flip] = triangles[flip][:, [0, 2, 1]]
    return positions, np.array(normals, dtype=np.float64), np.array(uvs, dtype=np.float64), triangles


def texture_png(width=2048, height=1024):
    xs = np.linspace(0, 255, width, dtype=np.float32)
    ys = np.linspace(0, 255, height, dtype=np.float32)
    rgb = np.stack([np.tile(xs, (height, 1)), np.tile(ys[:, None], (1, width)), np.full((height, width), 90.0)], axis=2)
    buffer = io.BytesIO()
    Image.fromarray(rgb.astype(np.uint8)).save(buffer, "PNG")
    return buffer.getvalue()


def quat_y(degrees):
    half = math.radians(degrees) / 2
    return [0.0, math.sin(half), 0.0, math.cos(half)]


class SceneBuilder:
    def __init__(self):
        self.doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [], "meshes": [],
                    "materials": [], "accessors": [], "bufferViews": [], "buffers": [], "images": [], "textures": []}
        self.blob = bytearray()

    def view(self, data):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)})
        self.blob.extend(data)
        return len(self.doc["bufferViews"]) - 1

    def accessor(self, array, component, kind):
        view = self.view(np.ascontiguousarray(array).tobytes())
        entry = {"bufferView": view, "componentType": component, "count": int(len(array)), "type": kind}
        if kind == "VEC3":
            entry["min"] = array.min(axis=0).tolist()
            entry["max"] = array.max(axis=0).tolist()
        self.doc["accessors"].append(entry)
        return len(self.doc["accessors"]) - 1

    def mesh(self, name, positions, normals, uvs, triangles, material):
        primitive = {
            "attributes": {
                "POSITION": self.accessor(positions.astype("<f4"), 5126, "VEC3"),
                "NORMAL": self.accessor(normals.astype("<f4"), 5126, "VEC3"),
                "TEXCOORD_0": self.accessor(uvs.astype("<f4"), 5126, "VEC2"),
            },
            "indices": self.accessor(triangles.reshape(-1).astype("<u4"), 5125, "SCALAR"),
            "material": material,
        }
        self.doc["meshes"].append({"name": name, "primitives": [primitive]})
        return len(self.doc["meshes"]) - 1

    def node(self, **fields):
        self.doc["nodes"].append(fields)
        return len(self.doc["nodes"]) - 1

    def glb(self):
        doc = dict(self.doc)
        doc["buffers"] = [{"byteLength": len(self.blob)}]
        text = json.dumps(doc).encode()
        while len(text) % 4:
            text += b" "
        blob = bytes(self.blob) + b"\0" * ((4 - len(self.blob) % 4) % 4)
        return (struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(blob)) + struct.pack("<II", len(text), 0x4E4F534A)
                + text + struct.pack("<II", len(blob), 0x004E4942) + blob)

    def gltf(self):
        doc = dict(self.doc)
        doc["buffers"] = [{"byteLength": len(self.blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(self.blob)).decode()}]
        return json.dumps(doc).encode()


PROP_SPOTS = [(-13.0, 0.25, 30.0), (-12.0, 0.25, 31.0), (-11.5, 0.25, 30.5), (-11.0, 0.25, 29.5)]
MIRRORED_SPOT = (-10.5, 0.25, 30.0)
BUILDING_AT = (-20.0, 5.0, -20.0)


def build_scene():
    s = SceneBuilder()
    image = s.view(texture_png())
    s.doc["images"].append({"bufferView": image, "mimeType": "image/png"})
    s.doc["textures"].append({"source": 0})
    s.doc["materials"] = [
        {"name": "Asphalt", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}},
        {"name": "Brick wall", "pbrMetallicRoughness": {"baseColorFactor": [0.6, 0.3, 0.2, 1.0]}},
        {"name": "Props", "pbrMetallicRoughness": {"baseColorFactor": [0.3, 0.3, 0.3, 1.0]}},
    ]
    g_pos, g_uv, g_tri = grid(GROUND_STEPS, GROUND)
    ground = s.mesh("Ground", g_pos, np.tile([0.0, 1.0, 0.0], (len(g_pos), 1)), g_uv, g_tri, 0)
    b_pos, b_nrm, b_uv, b_tri = box(BUILDING_STEPS, BUILDING)
    building = s.mesh("Tower", b_pos, b_nrm, b_uv, b_tri, 1)
    p_pos, p_nrm, p_uv, p_tri = box(2, PROP)
    prop = s.mesh("Crate", p_pos, p_nrm, p_uv, p_tri, 2)
    root = s.node(name="Scene", rotation=quat_y(ROOT_YAW), translation=list(ROOT_MOVE), children=[])
    children = [
        s.node(name="Ground", mesh=ground),
        s.node(name="Tower", mesh=building, translation=list(BUILDING_AT)),
    ]
    props = s.node(name="Props", children=[])
    s.doc["nodes"][props]["children"] = [s.node(name=f"Crate{i}", mesh=prop, translation=list(spot)) for i, spot in enumerate(PROP_SPOTS)]
    s.doc["nodes"][props]["children"].append(s.node(name="CrateMirrored", mesh=prop, translation=list(MIRRORED_SPOT), scale=[-1.0, 1.0, 1.0]))
    children.append(props)
    s.doc["nodes"][root]["children"] = children
    return s, {"ground": (g_pos, g_uv, g_tri), "building": b_tri, "prop": p_tri}


def root_matrix():
    m = np.eye(4)
    m[:3, :3] = gltf_io.quat_matrix(quat_y(ROOT_YAW))
    m[:3, 3] = ROOT_MOVE
    return m


def expected_world_triangles(parts):
    """Triangle centroids of the whole scene in studs, the way it should come out."""
    root = root_matrix()
    out = []

    def add(positions, triangles, local):
        world = root @ local
        p = positions @ world[:3, :3].T + world[:3, 3]
        out.append(p[triangles].mean(axis=1) * SCALE)

    g_pos, _, g_tri = parts["ground"]
    add(g_pos, g_tri, np.eye(4))
    b_pos, _, _, b_tri = box(BUILDING_STEPS, BUILDING)
    move = np.eye(4)
    move[:3, 3] = BUILDING_AT
    add(b_pos, b_tri, move)
    p_pos, _, _, p_tri = box(2, PROP)
    for spot in PROP_SPOTS + [MIRRORED_SPOT]:
        local = np.eye(4)
        local[:3, 3] = spot
        if spot == MIRRORED_SPOT:
            local[0, 0] = -1.0
        add(p_pos, p_tri, local)
    return np.concatenate(out)


def read_cells(out_dir, layout):
    """Every output mesh back in world space: name -> (positions, normals, uvs, triangles)."""
    meshes = {}
    for cell in layout["cells"]:
        document = gltf_io.load(os.path.join(out_dir, cell["file"]))
        entries = {m["name"]: m for m in cell["meshes"]}
        for piece in gltf_io.pieces(document):
            entry = entries[piece.name]
            centre = np.array(cell["position"]) + np.array(entry["offset"])
            turn = np.array([-1.0, 1.0, -1.0])
            meshes[piece.name] = (piece.positions * turn + centre, piece.normals * turn, piece.uvs, piece.triangles, cell, entry, document)
    return meshes


def sorted_rows(array, digits=2):
    rounded = np.round(array, digits)
    return rounded[np.lexsort(rounded.T[::-1])]


# Tests -------------------------------------------------------------------------------


def test_split(base):
    scene, parts = build_scene()
    path = os.path.join(base, "city.glb")
    with open(path, "wb") as handle:
        handle.write(scene.glb())
    out = os.path.join(base, "out_split")
    layout = split_scene.split(path, out, max_tris=18000, texture=1024, cell=64.0, root=ROOT)
    check("scale is the project metre", abs(layout["scale"] - round(SCALE, 6)) < 1e-9, str(layout["scale"]))
    meshes = read_cells(out, layout)

    expected = expected_world_triangles(parts)
    got = np.concatenate([m[0][m[3]].mean(axis=1) for m in meshes.values()])
    check("every triangle kept (split is lossless)", len(got) == len(expected), f"{len(got)} vs {len(expected)}")
    if len(got) == len(expected):
        diff = np.abs(sorted_rows(got) - sorted_rows(expected)).max()
        check("world positions after flattening, scale and the turn", diff < 0.02, f"max diff {diff}")
    check("layout totals", layout["totals"]["triangles"] == len(expected) and layout["totals"]["meshes"] == len(meshes))

    check("every mesh under the cap", all(len(m[3]) <= 18000 for m in meshes.values()), str(max(len(m[3]) for m in meshes.values())))
    tower = [m for m in meshes.values() if m[5]["material"] == "Brick_wall"]
    check("the tower is split in two", len(tower) == 2 and sum(len(m[3]) for m in tower) == len(parts["building"]), str([len(m[3]) for m in tower]))
    check("tower pieces stay in one cell", len({m[4]["name"] for m in tower}) == 1)
    check("tower collision is hull", all(m[5]["collision"] == "hull" for m in tower))

    ground = [m for m in meshes.values() if m[5]["material"] == "Asphalt"]
    cells_with_ground = {m[4]["name"] for m in ground}
    check("the ground is cut across cells", len(cells_with_ground) >= 25, str(len(cells_with_ground)))
    check("flat ground (wider than a cell) gets the default decomposition, every cut piece", all(m[5]["collision"] == "default" for m in ground), str({m[5]["collision"] for m in ground}))
    for mesh in ground:
        centres = mesh[0][mesh[3]].mean(axis=1)
        cell = mesh[4]
        name = cell["name"]
        ix = (1 if name[2] == "p" else -1) * int(name[3:6])
        iz = (1 if name[7] == "p" else -1) * int(name[8:11])
        tol = 1e-3
        inside = (centres[:, 0] >= ix * 64 - tol) & (centres[:, 0] < (ix + 1) * 64 + tol) & (centres[:, 2] >= iz * 64 - tol) & (centres[:, 2] < (iz + 1) * 64 + tol)
        if not inside.all():
            check(f"ground triangles of {name} have their centroid in the cell", False)
            break

    props = [m for m in meshes.values() if m[5]["material"] == "Props"]
    check("small props merged into one mesh", len(props) == 1 and len(props[0][3]) == 5 * len(parts["prop"]), str([len(m[3]) for m in props]))
    check("merged props have no collision", all(m[5]["collision"] == "none" for m in props))
    check("merged props list their sources", props and len(props[0][5]["sources"]) == 5)

    for name, mesh in meshes.items():
        positions, normals, _, triangles = mesh[:4]
        face = gltf_io.face_normals(positions, triangles)
        face /= np.maximum(np.linalg.norm(face, axis=1, keepdims=True), 1e-12)
        vertex = normals[triangles].mean(axis=1)
        agree = ((face * vertex).sum(axis=1) > 0).mean()
        if agree < 0.999:
            check(f"{name} winding matches its normals (mirrored nodes flipped)", False, f"{agree:.3f}")
        check(f"{name} normals unit length", np.abs(np.linalg.norm(normals, axis=1) - 1).max() < 1e-3)

    for cell in layout["cells"]:
        document = gltf_io.load(os.path.join(out, cell["file"]))
        for index in range(len(document.doc.get("images", []))):
            data, _ = document.image_bytes(index)
            size = gltf_io.decode_image(data).size
            check(f"{cell['name']} texture under the cap", max(size) <= 1024 and size == (1024, 512), str(size))
        names = [n["name"] for n in document.doc["nodes"]]
        check(f"{cell['name']} node names match the layout", sorted(names) == sorted(m["name"] for m in cell["meshes"]))
        check(f"{cell['name']} texture count", cell["textures"] == len(document.doc.get("images", [])))
    check("texture shared once per cell", all(c["textures"] <= 1 for c in layout["cells"]))

    gltf_path = os.path.join(base, "city.gltf")
    with open(gltf_path, "wb") as handle:
        handle.write(scene.gltf())
    again = split_scene.split(gltf_path, os.path.join(base, "out_gltf"), root=ROOT)
    check(".gltf with a data URI reads the same", again["totals"] == layout["totals"], f"{again['totals']} vs {layout['totals']}")
    return path, layout


def border_vertices(positions, triangles):
    """Vertices on open edges, with the mesh welded by position first (a UV or normal
    seam is not a border)."""
    welded, remap = split_scene.weld(positions, 1e-4)
    positions, triangles = welded, remap[triangles]
    edges = np.sort(np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]]), axis=1)
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    return positions[np.unique(unique[counts == 1])]


def test_decimate(base, path):
    out = os.path.join(base, "out_decimate")
    layout = split_scene.split(path, out, ratio=0.3, root=ROOT)
    meshes = read_cells(out, layout)
    ground = [m for m in meshes.values() if m[5]["material"] == "Asphalt"]
    total = sum(len(m[3]) for m in ground)
    before = 2 * GROUND_STEPS * GROUND_STEPS
    check("the ground is simplified", total < 0.75 * before, f"{total} of {before}")

    # no cracks: every border vertex inside the ground's outline is shared with another piece
    half = GROUND / 2 * SCALE
    root = root_matrix()
    inverse = np.linalg.inv(root)
    owners = {}
    for index, mesh in enumerate(ground):
        for point in border_vertices(mesh[0], mesh[3]):
            owners.setdefault(tuple(np.round(point, 2)), set()).add(index)
    lonely = 0
    for point, who in owners.items():
        local = (inverse @ np.array([point[0] / SCALE, point[1] / SCALE, point[2] / SCALE, 1.0]))[:3] * SCALE
        on_outline = abs(abs(local[0]) - half) < 0.05 or abs(abs(local[2]) - half) < 0.05
        if not on_outline and len(who) < 2:
            lonely += 1
    check("cells meet without cracks (border vertices shared)", lonely == 0, f"{lonely} unshared border vertices")

    # UVs carried over: the ground's UV is its planar position
    worst = 0.0
    for mesh in ground:
        world = mesh[0] / SCALE
        local = (np.c_[world, np.ones(len(world))] @ inverse.T)[:, :3]
        expected = np.stack([(local[:, 0] + GROUND / 2) / GROUND, (local[:, 2] + GROUND / 2) / GROUND], axis=1)
        worst = max(worst, float(np.abs(mesh[2] - expected).max()))
    check("UVs carried over through decimation", worst < 2e-3, f"max UV error {worst}")

    capped = split_scene.split(path, os.path.join(base, "out_capped"), max_tris=6000, over_cap="decimate", root=ROOT)
    capped_meshes = read_cells(os.path.join(base, "out_capped"), capped)
    check("over-cap decimation keeps the cap", all(len(m[3]) <= 6000 for m in capped_meshes.values()))


def test_manifest_and_luau(base, path):
    root = os.path.join(base, "repo")
    subprocess.run(["git", "init", "-q", root], check=True)
    shutil.copy(os.path.join(ROOT, ".gitignore"), os.path.join(root, ".gitignore"))
    os.makedirs(os.path.join(root, "src", "shared", "config"))
    shutil.copy(os.path.join(ROOT, "src", "shared", "config", "WorldMeshConfig.luau"), os.path.join(root, "src", "shared", "config"))
    os.makedirs(os.path.join(root, "assets"))
    with open(os.path.join(root, "assets", "manifest.json"), "w") as handle:
        json.dump({"model/maps/test_city/c_p099_p099": {"assetId": 0, "status": "pending"}}, handle)
    out = os.path.join(root, "assets", "maps", "test_city")
    argv = [path, "--out", out, "--map", "test_city", "--license", "CC0", "--source", "synthetic test scene", "--root", root]
    with redirect_stdout(io.StringIO()):
        code = split_scene.run(argv)
    check("run with --map", code == 0)
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        manifest = json.load(handle)
    with open(os.path.join(out, "layout.json")) as handle:
        layout = json.load(handle)
    keys = sorted(k for k in manifest if k.startswith("model/maps/test_city/"))
    check("one row per cell", keys == sorted(f"model/maps/test_city/{c['name']}" for c in layout["cells"]))
    check("a stale cell row is removed", "model/maps/test_city/c_p099_p099" not in manifest)
    row = manifest[keys[0]]
    check("rows pending with id 0", all(manifest[k]["status"] == "pending" and manifest[k]["assetId"] == 0 for k in keys))
    check("row file under the map's cells", row["file"].startswith("assets/maps/test_city/cells/") and row["file"].endswith(".glb"), row["file"])
    check("row licence and source", row["license"] == "CC0" and row["source"] == "synthetic test scene")
    check("layout names its map", layout["map"] == "test_city")

    module = emit_layout.module_path("test_city", root)
    check("Luau layout written", os.path.exists(module))
    with open(module) as handle:
        text = handle.read()
    check("Luau layout lists every cell", text.count("\t\t\tname = ") == len(layout["cells"]))
    check("Luau layout lists every mesh", text.count("{ name = ") == layout["totals"]["meshes"])
    check("Luau layout has no em or en dash", "\u2014" not in text and "\u2013" not in text)
    check("Luau layout up to date", emit_layout.write("test_city", layout, root, check=True))

    manifest[keys[0]]["assetId"] = 123
    with open(os.path.join(root, "assets", "manifest.json"), "w") as handle:
        json.dump(manifest, handle)
    try:
        with redirect_stdout(io.StringIO()):
            split_scene.run(argv)
        check("re-split of an uploaded map needs --replace", False)
    except split_scene.SceneError:
        pass
    for bad in (["--map", "Bad-Name", "--license", "x", "--source", "y"], ["--map", "ok_name"]):
        try:
            with redirect_stdout(io.StringIO()):
                split_scene.run([path, "--out", out, "--root", root] + bad)
            check(f"refused {bad}", False)
        except split_scene.SceneError:
            pass
    try:
        split_scene.manifest_rows("x", layout, base, root, "CC0", "s")
        check("--map outside the repository refused", False)
    except split_scene.SceneError:
        pass
    check("the layout module is server-side", os.path.relpath(emit_layout.module_path("test_city", root), root).startswith(os.path.join("src", "server", "prebuilt")))

    def refused(argv, why):
        try:
            with redirect_stdout(io.StringIO()):
                split_scene.run(argv)
            check(f"refused: {why}", False)
        except split_scene.SceneError:
            pass

    licence = ["--license", "CC0", "--source", "s"]
    refused([path, "--out", os.path.join(root, "assets", "maps", "end"), "--map", "end", "--root", root] + licence, "a Luau keyword as map name")
    refused([path, "--out", os.path.join(root, "assets", "maps", "other"), "--map", "test_city", "--root", root] + licence, "--out not assets/maps/<map>")
    refused([path, "--out", os.path.join(root, "src", "previews"), "--root", root], "--out inside the repository and not ignored")
    with redirect_stdout(io.StringIO()):
        code = split_scene.run([path, "--out", os.path.join(base, "preview_outside"), "--root", root])
    check("--out outside the repository is fine without --map", code == 0)


def test_hints():
    rng = np.random.default_rng(3)

    def cloud(sizes, flat_axis=None, tilt=0.0):
        points = rng.random((400, 3)) * np.array(sizes)
        if flat_axis is not None:
            points[:, flat_axis] = 0.0
        if tilt:
            c, s_ = np.cos(tilt), np.sin(tilt)
            points = points @ np.array([[c, -s_, 0], [s_, c, 0], [0, 0, 1]]).T
        return points

    hint = split_scene.collision_hint
    check("tiny is none", hint(cloud([2, 2, 2]), False, 4) == "none")
    check("flat slab is box", hint(cloud([60, 1, 60], flat_axis=1), False, 4) == "box")
    check("thin wall is box", hint(cloud([60, 20, 1], flat_axis=2), False, 4) == "box")
    check("a tilted sheet is still planar", hint(cloud([40, 1, 40], flat_axis=1, tilt=0.6), False, 4) == "box")
    check("a low but bumpy mesh is not a box", hint(cloud([40, 3, 40]), False, 4) == "hull")
    check("bulky is hull", hint(cloud([30, 30, 30]), False, 4) == "hull")
    check("wide flat ground is default", hint(cloud([300, 1, 300], flat_axis=1), True, 4) == "default")
    check("wide ground with relief is precise", hint(cloud([300, 12, 300]), True, 4) == "precise")
    check("cell names", split_scene.cell_name(0, -3) == "c_p000_m003" and split_scene.cell_name(-12, 7) == "c_m012_p007")


def test_reader(base):
    os.makedirs(base)
    # two meshes on one shared vertex buffer, far apart: each must keep its own bounds
    s = SceneBuilder()
    p_pos, p_nrm, p_uv, p_tri = box(1, 1.4)
    # near enough that the shared buffer's whole extent still fits in one cell (the bug:
    # each kiosk took the buffer's bounds); far enough to be twice the kiosk's size
    far = p_pos + np.array([8.0, 0.0, 5.0])
    positions = np.concatenate([p_pos, far])
    normals = np.concatenate([p_nrm, p_nrm])
    uvs = np.concatenate([p_uv, p_uv])
    s.doc["materials"] = [{"name": "Kiosk", "pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.5, 0.5, 1]}}]
    pos_acc = s.accessor(positions.astype("<f4"), 5126, "VEC3")
    nrm_acc = s.accessor(normals.astype("<f4"), 5126, "VEC3")
    uv_acc = s.accessor(uvs.astype("<f4"), 5126, "VEC2")
    for name, tris in (("KioskA", p_tri), ("KioskB", p_tri + len(p_pos))):
        index = s.accessor(tris.reshape(-1).astype("<u4"), 5125, "SCALAR")
        s.doc["meshes"].append({"name": name, "primitives": [{"attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc, "TEXCOORD_0": uv_acc}, "indices": index, "material": 0}]})
    root = s.node(name="Root", children=[])
    s.doc["nodes"][root]["children"] = [s.node(name="KioskA", mesh=0), s.node(name="KioskB", mesh=1)]
    shared = os.path.join(base, "shared.glb")
    with open(shared, "wb") as handle:
        handle.write(s.glb())
    layout = split_scene.split(shared, os.path.join(base, "shared_out"), root=ROOT, merge_size=1.0)
    sizes = [m["size"] for c in layout["cells"] for m in c["meshes"]]
    expected = 1.4 * SCALE
    check("each kiosk keeps its own 5 x 5 bounds", sizes and all(max(size) < expected + 0.01 for size in sizes), str(sizes))

    # a required extension the reader cannot honour
    draco = SceneBuilder()
    draco.doc["extensionsRequired"] = ["KHR_draco_mesh_compression"]
    draco.doc["extensionsUsed"] = ["KHR_draco_mesh_compression"]
    draco.node(name="Empty")
    draco_path = os.path.join(base, "draco.glb")
    with open(draco_path, "wb") as handle:
        handle.write(draco.glb())
    try:
        gltf_io.load(draco_path)
        check("Draco refused", False)
    except gltf_io.GltfError as error:
        check("the refusal names the extension", "KHR_draco_mesh_compression" in str(error))

    # KHR_texture_transform on the colour texture is baked into the UVs
    t = SceneBuilder()
    image = t.view(texture_png(64, 64))
    t.doc["images"].append({"bufferView": image, "mimeType": "image/png"})
    t.doc["textures"].append({"source": 0})
    transform = {"offset": [0.25, 0.5], "rotation": 0.3, "scale": [2.0, 3.0]}
    t.doc["materials"] = [{"name": "Tiled", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0, "extensions": {"KHR_texture_transform": transform}}}}]
    t.doc["extensionsUsed"] = ["KHR_texture_transform"]
    t.doc["extensionsRequired"] = ["KHR_texture_transform"]
    g_pos, g_uv, g_tri = grid(2, 4.0)
    t.mesh("Tile", g_pos, np.tile([0.0, 1.0, 0.0], (len(g_pos), 1)), g_uv, g_tri, 0)
    t.node(name="Tile", mesh=0)
    t_path = os.path.join(base, "transform.glb")
    with open(t_path, "wb") as handle:
        handle.write(t.glb())
    piece = gltf_io.pieces(gltf_io.load(t_path))[0]
    c, s_ = math.cos(0.3), math.sin(0.3)
    u, v = g_uv[:, 0] * 2.0, g_uv[:, 1] * 3.0
    expected_uv = np.stack([c * u + s_ * v + 0.25, -s_ * u + c * v + 0.5], axis=1)
    check("texture transform baked into the UVs", np.abs(piece.uvs - expected_uv).max() < 1e-5)

    # an external buffer whose file name has a space and a non-ASCII letter
    scene, _ = build_scene()
    folder = os.path.join(base, "external")
    os.makedirs(folder)
    name = "city b\u00e4ll.bin"
    with open(os.path.join(folder, name), "wb") as handle:
        handle.write(bytes(scene.blob))
    doc = dict(scene.doc)
    from urllib.parse import quote

    doc["buffers"] = [{"byteLength": len(scene.blob), "uri": quote(name)}]
    with open(os.path.join(folder, "city.gltf"), "w") as handle:
        json.dump(doc, handle)
    check("percent-encoded URIs resolve", len(gltf_io.pieces(gltf_io.load(os.path.join(folder, "city.gltf")))) > 0)


def test_two_sided(base):
    """A wall of two sheets back to back 0.02 m apart, the back one far finer: after
    simplification every triangle's normal must follow its own winding, not the other
    sheet's (its centroids are nearer than the coarse front's own)."""
    os.makedirs(base)
    s = SceneBuilder()
    s.doc["materials"] = [{"name": "Wall", "pbrMetallicRoughness": {"baseColorFactor": [0.6, 0.6, 0.6, 1]}}]
    f_pos, f_uv, f_tri = grid(12, 8.0)
    b_pos, b_uv, b_tri = grid(41, 8.0)
    front = f_pos[:, [0, 2, 1]] + np.array([0, 0, 0.01])
    back = b_pos[:, [0, 2, 1]] - np.array([0, 0, 0.01])
    p = np.concatenate([front, back])
    p_tri = np.concatenate([f_tri[:, [0, 2, 1]], b_tri + len(front)])
    faces = gltf_io.face_normals(p, p_tri)
    faces /= np.linalg.norm(faces, axis=1, keepdims=True)
    normals = np.zeros_like(p)
    normals[: len(front)] = faces[0]
    normals[len(front):] = faces[-1]
    s.mesh("Wall", p, normals, np.concatenate([f_uv, b_uv]), p_tri, 0)
    s.node(name="Wall", mesh=0)
    path = os.path.join(base, "wall.glb")
    with open(path, "wb") as handle:
        handle.write(s.glb())
    layout = split_scene.split(path, os.path.join(base, "out"), ratio=0.3, root=ROOT)
    meshes = read_cells(os.path.join(base, "out"), layout)
    worst = 1.0
    for mesh in meshes.values():
        positions, mesh_normals, _, triangles = mesh[:4]
        face = gltf_io.face_normals(positions, triangles)
        face /= np.maximum(np.linalg.norm(face, axis=1, keepdims=True), 1e-12)
        agree = ((face * mesh_normals[triangles].mean(axis=1)).sum(axis=1) > 0).mean()
        worst = min(worst, agree)
    check("every decimated triangle's normal follows its winding", worst > 0.999, f"{worst:.3f}")


def test_repo_layouts():
    import glob

    for path in sorted(glob.glob(os.path.join(ROOT, "assets", "maps", "*", "layout.json"))):
        with open(path) as handle:
            layout = json.load(handle)
        name = emit_layout.map_of(path, layout)
        check(f"{name} Luau layout up to date", emit_layout.write(name, layout, ROOT, check=True))


def main():
    base = tempfile.mkdtemp(prefix="cityimport-test-")
    try:
        group("collision hints and cell names", test_hints)
        holder = {}
        group("split (flatten, cells, cap, merge, textures, winding, .gltf)", lambda: holder.setdefault("split", test_split(base)))
        if "split" in holder:
            path, _ = holder["split"]
            if HAVE_DECIMATION:
                group("decimate (borders locked, UVs carried over)", lambda: test_decimate(base, path))
                group("decimation normals follow the winding (two-sided wall)", lambda: test_two_sided(os.path.join(base, "twosided")))
            else:
                print("skip decimate groups (pip install pyfqmr scipy)")
            group("manifest rows and the Luau layout", lambda: test_manifest_and_luau(base, path))
        group("reader: shared accessors, required extensions, texture transform, URIs", lambda: test_reader(os.path.join(base, "reader")))
        group("committed layouts match their Luau modules", test_repo_layouts)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    if failures:
        print(f"{failures} check(s) failed")
        return 1
    print("all city import tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
