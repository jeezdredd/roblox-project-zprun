#!/usr/bin/env python3
"""Split a large static scene (GLB or glTF) into upload-sized cells for Roblox.

    python3 tools/city_import/split_scene.py <scene.glb> --out <dir>
        [--max-tris 18000] [--texture 1024] [--cell 64] [--scale S]
        [--over-cap split|decimate] [--decimate R] [--merge-size 4]
        [--map <name> --license TEXT --source TEXT] [--replace]

1. Flattens the node tree to world space and scales it to studs (--scale, default the
   project's metre: WorldMeshConfig.METRE = 1 / 0.28 studs per glTF unit).
2. Puts every mesh into a square cell of --cell studs on the ground plane by the centre
   of its bounds; a mesh wider than a cell (roads, terrain) is cut along the triangles,
   each going to the cell its centroid is in. Cut edges keep their exact vertices on
   both sides, so cells meet without cracks.
3. In each cell, meshes smaller than --merge-size studs that share a material become
   one mesh (clutter, no collision); bigger meshes stay their own.
4. A mesh over --max-tris (Roblox takes 20k per MeshPart) is split along its longest
   axis until every piece fits (lossless), or with --over-cap decimate simplified first
   with its borders locked. --decimate R simplifies every mesh to R of its triangles.
   Simplification (pyfqmr) works on the welded surface and moves UVs and normals over
   from the original triangles, so seams and cell borders stay put.
5. Shrinks every texture so its longest side is at most --texture px.
6. Writes <out>/cells/<cell>.glb (one node per mesh, named <cell>_<nnn>, geometry about
   the mesh's own centre and turned 180 degrees about Y because the Roblox glTF importer
   turns meshes that way) and <out>/layout.json (per cell: position, size, materials,
   triangle and texture counts, and per mesh its offset, size, triangles and a
   collision hint: none, box or hull).
7. With --map, adds one pending manifest row per cell (model/maps/<map>/<cell>) and
   writes the Luau layout module (src/shared/prebuilt/<map>.luau) for PrebuiltMaps.

See docs/environment/prebuilt-maps.md.
"""

import argparse
import io
import json
import math
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import emit_layout  # noqa: E402
import gltf_io  # noqa: E402

LAYOUT_VERSION = 1
MAP_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
FLAT_HEIGHT = 1.0
THIN_RATIO = 0.05
MIN_SIZE = 0.05


class SceneError(Exception):
    pass


# Geometry helpers -------------------------------------------------------------------


class Group:
    """Triangles of one material on their own vertex arrays."""

    def __init__(self, material, positions, normals, uvs, triangles, members, merged=False, max_member=0.0):
        self.material = material
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.triangles = triangles
        self.members = members
        self.merged = merged
        self.max_member = max_member

    @property
    def count(self):
        return int(len(self.triangles))

    def bounds(self):
        return self.positions.min(axis=0), self.positions.max(axis=0)


def compact(positions, normals, uvs, triangles):
    used, inverse = np.unique(triangles.reshape(-1), return_inverse=True)
    return positions[used], normals[used], uvs[used], inverse.reshape(-1, 3).astype(np.int64)


def subset(group, mask):
    p, n, uv, t = compact(group.positions, group.normals, group.uvs, group.triangles[mask])
    return Group(group.material, p, n, uv, t, group.members, group.merged, group.max_member)


def concat(material, parts, merged, max_member):
    positions, normals, uvs, triangles, members = [], [], [], [], []
    offset = 0
    for part in parts:
        positions.append(part.positions)
        normals.append(part.normals)
        uvs.append(part.uvs)
        triangles.append(part.triangles + offset)
        offset += len(part.positions)
        members.extend(part.members)
    return Group(material, np.concatenate(positions), np.concatenate(normals), np.concatenate(uvs),
                 np.concatenate(triangles), members, merged, max_member)


def drop_degenerate(group):
    area = np.linalg.norm(gltf_io.face_normals(group.positions, group.triangles), axis=1)
    keep = area > 1e-12
    if keep.all():
        return group
    return subset(group, keep)


def centroids(group):
    return group.positions[group.triangles].mean(axis=1)


def split_to_cap(group, cap):
    """Halves along the longest axis of the triangle centroids (median cut) until every
    piece has at most cap triangles. Lossless: the halves share the cut edges' vertices."""
    if group.count <= cap:
        return [group]
    centres = centroids(group)
    axis = int(np.argmax(centres.max(axis=0) - centres.min(axis=0)))
    order = np.argsort(centres[:, axis], kind="stable")
    half = group.count // 2
    first = np.zeros(group.count, dtype=bool)
    first[order[:half]] = True
    return split_to_cap(subset(group, first), cap) + split_to_cap(subset(group, ~first), cap)


def weld(positions, tolerance=1e-5):
    keys = np.round(positions / tolerance).astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return positions[first], inverse.reshape(-1)


def _barycentric(points, a, b, c):
    """Barycentric weights of points in the planes of triangles (a, b, c), by least
    squares (points off the triangle extrapolate, which is exact for affine UVs)."""
    e1 = b - a
    e2 = c - a
    d = points - a
    d11 = (e1 * e1).sum(-1)
    d12 = (e1 * e2).sum(-1)
    d22 = (e2 * e2).sum(-1)
    p1 = (d * e1).sum(-1)
    p2 = (d * e2).sum(-1)
    det = d11 * d22 - d12 * d12
    det = np.where(np.abs(det) < 1e-20, 1e-20, det)
    v = (d22 * p1 - d12 * p2) / det
    w = (d11 * p2 - d12 * p1) / det
    return np.stack([1 - v - w, v, w], axis=-1)


def decimate(group, target):
    """Simplify to about target triangles with the borders locked (pyfqmr), then move
    each corner's UV and normal over from the nearest original triangle. Returns the
    group unchanged when there is nothing to gain."""
    if target >= group.count:
        return group
    try:
        import pyfqmr
        from scipy.spatial import cKDTree
    except ImportError as error:
        raise SceneError(f"decimation needs pyfqmr and scipy (pip install pyfqmr scipy): {error}")
    welded, remap = weld(group.positions)
    faces = remap[group.triangles]
    simplifier = pyfqmr.Simplify()
    simplifier.setMesh(welded.astype(np.float64), faces.astype(np.int32))
    simplifier.simplify_mesh(target_count=int(target), aggressiveness=7, preserve_border=True, verbose=False)
    out_positions, out_faces, _ = simplifier.getMesh()
    out_positions = np.asarray(out_positions, dtype=np.float64)
    out_faces = np.asarray(out_faces, dtype=np.int64)
    if len(out_faces) == 0 or len(out_faces) >= group.count:
        return group

    original = group.positions[group.triangles]
    tree = cKDTree(original.mean(axis=1))
    corners = out_positions[out_faces]
    _, nearest = tree.query(corners.mean(axis=1))
    source = group.triangles[nearest]
    a, b, c = (group.positions[source[:, i]] for i in range(3))
    weights = _barycentric(corners, a[:, None, :], b[:, None, :], c[:, None, :])
    uv = (weights[..., None] * group.uvs[source][:, None, :, :]).sum(axis=2)
    normal = (weights[..., None] * group.normals[source][:, None, :, :]).sum(axis=2)
    length = np.linalg.norm(normal, axis=-1, keepdims=True)
    length[length == 0] = 1.0
    normal = normal / length
    # per-corner vertices so a UV seam can keep two UVs at one position
    positions = corners.reshape(-1, 3)
    normals = normal.reshape(-1, 3)
    uvs = uv.reshape(-1, 2)
    triangles = np.arange(len(positions), dtype=np.int64).reshape(-1, 3)
    keys = np.concatenate([np.round(positions / 1e-5), np.round(uvs / 1e-5), np.round(normals / 1e-3)], axis=1).astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return Group(group.material, positions[first], normals[first], uvs[first], inverse.reshape(-1)[triangles],
                 group.members, group.merged, group.max_member)


def collision_hint(size, merged, small):
    if merged or max(size) < small:
        return "none"
    if size[1] <= FLAT_HEIGHT or min(size) / max(max(size), 1e-9) < THIN_RATIO:
        return "box"
    return "hull"


# Cells -------------------------------------------------------------------------------


def cell_index(x, cell):
    return int(math.floor(x / cell))


def cell_name(ix, iz):
    def code(value):
        return ("p" if value >= 0 else "m") + f"{abs(value):03d}"

    return f"c_{code(ix)}_{code(iz)}"


def piece_group(piece, scale):
    positions = piece.positions * scale
    group = Group(piece.material, positions, piece.normals, piece.uvs, piece.triangles, [piece.name])
    return drop_degenerate(group)


def assign(groups, cell):
    """cell key -> list of groups. A group no wider than a cell goes whole to the cell of
    its centre; a wider one is cut by triangle centroid."""
    cells = {}
    for group in groups:
        if group.count == 0:
            continue
        low, high = group.bounds()
        extent = high - low
        if max(extent[0], extent[2]) <= cell:
            centre = (low + high) / 2
            key = (cell_index(centre[0], cell), cell_index(centre[2], cell))
            cells.setdefault(key, []).append(group)
            continue
        centres = centroids(group)
        ix = np.floor(centres[:, 0] / cell).astype(np.int64)
        iz = np.floor(centres[:, 2] / cell).astype(np.int64)
        for key in sorted(set(zip(ix.tolist(), iz.tolist()))):
            mask = (ix == key[0]) & (iz == key[1])
            cells.setdefault(key, []).append(subset(group, mask))
    return cells


def cell_groups(groups, merge_size, cap, over_cap, ratio):
    """The meshes of one cell: small groups merged per material, the rest kept, every
    one decimated or split to fit the cap."""
    small, large = {}, []
    for group in groups:
        low, high = group.bounds()
        size = float((high - low).max())
        if size < merge_size:
            small.setdefault(group.material, []).append((group, size))
        else:
            large.append(group)
    out = []
    for material in sorted(small, key=lambda m: (-1 if m is None else m)):
        members = small[material]
        merged = concat(material, [g for g, _ in members], merged=True, max_member=max(s for _, s in members))
        out.append(merged)
    out.extend(large)

    final = []
    for group in out:
        if ratio < 1.0 and group.count > 64:
            group = decimate(group, max(1, int(math.ceil(group.count * ratio))))
        if group.count > cap and over_cap == "decimate":
            group = decimate(group, cap)
        final.extend(split_to_cap(group, cap))
    return final


# Materials and textures --------------------------------------------------------------


def material_name(doc, index):
    if index is None:
        return "default"
    material = doc.get("materials", [])[index]
    raw = material.get("name") or f"material{index}"
    return re.sub(r"[^A-Za-z0-9_]+", "_", raw).strip("_") or f"material{index}"


class TextureCache:
    """Source image index -> (bytes, mime) shrunk to the cap."""

    def __init__(self, document, cap):
        self.document = document
        self.cap = cap
        self.cache = {}
        self.sizes = {}

    def get(self, texture_index):
        doc = self.document.doc
        texture = doc["textures"][texture_index]
        source = texture.get("source")
        if source is None:
            for extension in (texture.get("extensions") or {}).values():
                source = extension.get("source", source)
        if source is None:
            return None
        if source not in self.cache:
            data, mime = self.document.image_bytes(source)
            image = gltf_io.decode_image(data)
            image.load()
            width, height = image.size
            longest = max(width, height)
            if longest > self.cap:
                factor = self.cap / longest
                image = image.resize((max(1, round(width * factor)), max(1, round(height * factor))), Image.LANCZOS)
            buffer = io.BytesIO()
            if mime == "image/jpeg" and image.mode in ("RGB", "L"):
                image.save(buffer, "JPEG", quality=90)
            else:
                mime = "image/png"
                image.save(buffer, "PNG")
            self.cache[source] = (buffer.getvalue(), mime)
            self.sizes[source] = image.size
        return source, self.cache[source]


def write_material(writer, document, textures, index, notes):
    if index is None:
        return writer.material({"name": "default", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}})
    source = document.doc["materials"][index]
    pbr = dict(source.get("pbrMetallicRoughness", {}))
    out = {"name": material_name(document.doc, index)}
    for key in ("alphaMode", "alphaCutoff", "doubleSided", "emissiveFactor"):
        if key in source:
            out[key] = source[key]

    def texture_ref(ref, extra=()):
        if not ref:
            return None
        if ref.get("texCoord", 0) != 0:
            notes.append(f"{out['name']}: a texture on a second UV set dropped")
            return None
        found = textures.get(ref["index"])
        if not found:
            return None
        key, (data, mime) = found
        result = {"index": writer.image(key, data, mime)}
        for name in extra:
            if name in ref:
                result[name] = ref[name]
        return result

    new_pbr = {}
    for key in ("baseColorFactor", "metallicFactor", "roughnessFactor"):
        if key in pbr:
            new_pbr[key] = pbr[key]
    for key in ("baseColorTexture", "metallicRoughnessTexture"):
        ref = texture_ref(pbr.get(key))
        if ref:
            new_pbr[key] = ref
    out["pbrMetallicRoughness"] = new_pbr
    normal = texture_ref(source.get("normalTexture"), ("scale",))
    if normal:
        out["normalTexture"] = normal
    emissive = texture_ref(source.get("emissiveTexture"))
    if emissive:
        out["emissiveTexture"] = emissive
    if source.get("extensions"):
        notes.append(f"{out['name']}: material extensions dropped ({', '.join(sorted(source['extensions']))})")
    return writer.material(out)


# The run -------------------------------------------------------------------------------


def studs_per_metre(root):
    path = os.path.join(root, "src", "shared", "config", "WorldMeshConfig.luau")
    with open(path, encoding="utf-8") as handle:
        match = re.search(r"local\s+METRE\s*=\s*1\s*/\s*([0-9.]+)", handle.read())
    if not match:
        raise SceneError(f"no METRE constant in {path}")
    return 1.0 / float(match.group(1))


def _round(values, digits=4):
    return [round(float(v), digits) for v in values]


def split(source, out_dir, max_tris=18000, texture=1024, cell=64.0, scale=None, over_cap="split",
          ratio=1.0, merge_size=4.0, small=4.0, root=REPO, map_name=None):
    """Run the whole split; returns the layout dict (also written to out_dir)."""
    if max_tris < 1 or texture < 1 or cell <= 0:
        raise SceneError("--max-tris, --texture and --cell must be positive")
    if not 0 < ratio <= 1:
        raise SceneError("--decimate must be in (0, 1]")
    scale = studs_per_metre(root) if scale is None else float(scale)
    document = gltf_io.load(source)
    groups = [piece_group(piece, scale) for piece in gltf_io.pieces(document)]
    if not any(g.count for g in groups):
        raise SceneError(f"{source}: no triangles in the default scene")
    cells = assign(groups, cell)
    textures = TextureCache(document, texture)
    notes = list(document.notes)

    cells_dir = os.path.join(out_dir, "cells")
    os.makedirs(cells_dir, exist_ok=True)
    for name in os.listdir(cells_dir):
        if name.endswith(".glb"):
            os.remove(os.path.join(cells_dir, name))

    layout_cells = []
    for key in sorted(cells):
        name = cell_name(*key)
        meshes = cell_groups(cells[key], merge_size, max_tris, over_cap, ratio)
        meshes.sort(key=lambda g: (material_name(document.doc, g.material), -g.count, g.members[0] if g.members else ""))
        lows = np.array([g.bounds()[0] for g in meshes])
        highs = np.array([g.bounds()[1] for g in meshes])
        low, high = lows.min(axis=0), highs.max(axis=0)
        position = (low + high) / 2

        writer = gltf_io.Writer()
        material_index = {}
        entries = []
        for index, group in enumerate(meshes):
            if group.material not in material_index:
                material_index[group.material] = write_material(writer, document, textures, group.material, notes)
            g_low, g_high = group.bounds()
            centre = (g_low + g_high) / 2
            size = np.maximum(g_high - g_low, MIN_SIZE)
            mesh_name = f"{name}_{index:03d}"
            # about the mesh's own centre, turned 180 degrees about Y (x and z negated):
            # the importer turns it back
            local = (group.positions - centre) * np.array([-1.0, 1.0, -1.0])
            normals = group.normals * np.array([-1.0, 1.0, -1.0])
            writer.mesh(mesh_name, local, normals, group.uvs, group.triangles, material_index[group.material], [0, 0, 0])
            entries.append({
                "name": mesh_name,
                "material": material_name(document.doc, group.material),
                "offset": _round(centre - position),
                "size": _round(size),
                "triangles": group.count,
                "collision": collision_hint(size, group.merged, small),
                "sources": sorted(set(group.members))[:8],
            })
        file_name = f"{name}.glb"
        writer.save(os.path.join(cells_dir, file_name))
        layout_cells.append({
            "name": name,
            "file": f"cells/{file_name}",
            "position": _round(position),
            "size": _round(np.maximum(high - low, MIN_SIZE)),
            "triangles": int(sum(e["triangles"] for e in entries)),
            "textures": len(writer.image_index),
            "materials": sorted({e["material"] for e in entries}),
            "meshes": entries,
        })

    layout = {
        "version": LAYOUT_VERSION,
        "map": map_name,
        "source": os.path.basename(source),
        "scale": round(scale, 6),
        "cell": cell,
        "maxTris": max_tris,
        "texture": texture,
        "turn": "geometry is turned 180 degrees about Y (x and z negated); the Roblox glTF importer turns it back",
        "cells": layout_cells,
        "totals": {
            "cells": len(layout_cells),
            "meshes": sum(len(c["meshes"]) for c in layout_cells),
            "triangles": sum(c["triangles"] for c in layout_cells),
            "textures": len(textures.cache),
        },
        "notes": sorted(set(notes)),
    }
    with open(os.path.join(out_dir, "layout.json"), "w", encoding="utf-8") as handle:
        json.dump(layout, handle, indent=1)
        handle.write("\n")
    return layout


# Manifest rows --------------------------------------------------------------------------


def manifest_rows(map_name, layout, out_dir, root, licence, source):
    relative = os.path.relpath(os.path.abspath(out_dir), os.path.abspath(root)).replace(os.sep, "/")
    if relative.startswith(".."):
        raise SceneError("--map needs --out inside the repository, so upload_assets.py can read the cells")
    rows = {}
    for cell in layout["cells"]:
        rows[f"model/maps/{map_name}/{cell['name']}"] = {
            "source": source,
            "license": licence,
            "file": f"{relative}/{cell['file']}",
            "assetId": 0,
            "status": "pending",
            "note": (f"Prebuilt map {map_name}, cell {cell['name']}: {len(cell['meshes'])} meshes, "
                     f"{cell['triangles']} triangles, {cell['textures']} textures, from {layout['source']}"),
        }
    return rows


def apply_rows(manifest, map_name, rows, replace=False):
    prefix = f"model/maps/{map_name}/"
    existing = [key for key in manifest if key.startswith(prefix)]
    uploaded = [key for key in existing if manifest[key].get("assetId")]
    if uploaded and not replace:
        raise SceneError(f"map {map_name} already has uploaded cells ({len(uploaded)}); pass --replace to split it again")
    for key in existing:
        if key not in rows:
            del manifest[key]
    manifest.update(rows)
    return [key for key in existing if key not in rows]


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("scene", help="the .glb or .gltf scene")
    parser.add_argument("--out", required=True, help="output folder (assets/maps/<map> for the manifest)")
    parser.add_argument("--max-tris", type=int, default=18000, help="triangle cap per mesh")
    parser.add_argument("--texture", type=int, default=1024, help="longest texture side in px")
    parser.add_argument("--cell", type=float, default=64.0, help="cell size in studs")
    parser.add_argument("--scale", type=float, help="studs per scene unit (default the project's metre)")
    parser.add_argument("--over-cap", choices=("split", "decimate"), default="split")
    parser.add_argument("--decimate", type=float, default=1.0, help="keep this share of every mesh's triangles")
    parser.add_argument("--merge-size", type=float, default=4.0, help="meshes smaller than this (studs) merge per material")
    parser.add_argument("--map", help="lower snake name: adds manifest rows and the Luau layout module")
    parser.add_argument("--license", help="licence text for the manifest rows (required with --map)")
    parser.add_argument("--source", help="where the scene came from (required with --map)")
    parser.add_argument("--replace", action="store_true", help="split a map again after its cells were uploaded")
    parser.add_argument("--root", default=REPO, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def run(argv):
    args = parse_args(argv)
    if args.map:
        if not MAP_NAME.match(args.map):
            raise SceneError("--map: lower case letters, digits and underscores, starting with a letter")
        if not args.license or not args.source:
            raise SceneError("--map needs --license and --source: every asset has a licence and a source")
    layout = split(args.scene, args.out, args.max_tris, args.texture, args.cell, args.scale, args.over_cap,
                   args.decimate, args.merge_size, args.merge_size, args.root, args.map)
    totals = layout["totals"]
    print(f"{layout['source']}: {totals['cells']} cells, {totals['meshes']} meshes, {totals['triangles']} triangles, "
          f"{totals['textures']} textures, scale {layout['scale']} studs per unit")
    for note in layout["notes"]:
        print(f"note: {note}")
    if args.map:
        manifest_path = os.path.join(args.root, "assets", "manifest.json")
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        removed = apply_rows(manifest, args.map, manifest_rows(args.map, layout, args.out, args.root, args.license, args.source), args.replace)
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        for key in removed:
            print(f"removed {key}")
        module = emit_layout.write(args.map, layout, args.root)
        print(f"wrote {os.path.relpath(module, args.root)}")
        if os.path.abspath(args.root) == os.path.abspath(REPO):
            for script in ("sync_configs.py", "sync_needed.py"):
                subprocess.run([sys.executable, os.path.join(args.root, "scripts", script)], cwd=args.root, check=True)
        print(f"next: python3 scripts/upload_assets.py --only model/maps/{args.map}/ && python3 scripts/sync_configs.py")
    return 0


def main():
    try:
        return run(sys.argv[1:])
    except (SceneError, gltf_io.GltfError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
