#!/usr/bin/env python3
"""Mesh side of the viewmodel pipeline: receive Studio exports, convert, record ids.

Usage:
    python3 scripts/mesh_pipeline.py serve <weapon>
    python3 scripts/mesh_pipeline.py convert <weapon>
    python3 scripts/mesh_pipeline.py finalize <weapon>

See tools/cube3d/README.md for the full flow.
"""

import argparse
import http.server
import json
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")
SOURCE_ROOT = os.path.join(ROOT, "assets", "viewmodels", "source")
PORT = 8973
SOURCE_LABEL = "Cube 3D (Roblox GenerationService), generated in Studio for this project"
LICENSE_LABEL = "Roblox generative AI output (project owner)"
CHUNK_PATTERN = re.compile(r"^(?P<stem>.+_tex)_(?P<w>\d+)x(?P<h>\d+)\.rgba(?:\.part(?P<part>\d+))?$")


def source_dir(weapon):
    path = os.path.join(SOURCE_ROOT, weapon)
    os.makedirs(path, exist_ok=True)
    return path


def load_manifest():
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(manifest):
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def upsert(manifest, key, file_path, asset_id=None, status=None):
    entry = manifest.get(key)
    if entry is None:
        entry = {
            "source": SOURCE_LABEL,
            "license": LICENSE_LABEL,
            "file": file_path,
            "assetId": 0,
            "status": "pending",
        }
        manifest[key] = entry
    entry["file"] = file_path
    if asset_id:
        entry["assetId"] = asset_id
    if status:
        entry["status"] = status
    return entry


def make_handler(weapon):
    out_dir = source_dir(weapon)

    class Handler(http.server.BaseHTTPRequestHandler):
        def send_bytes(self, body, content_type):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            name = os.path.basename(self.path.strip("/"))
            if name == "manifest.json":
                with open(MANIFEST, "rb") as handle:
                    self.send_bytes(handle.read(), "application/json")
                return
            path = os.path.join(out_dir, name)
            if name and os.path.exists(path):
                content_type = "image/png" if name.endswith(".png") else "application/octet-stream"
                with open(path, "rb") as handle:
                    self.send_bytes(handle.read(), content_type)
                return
            self.send_bytes(b"pong", "text/plain")

        def do_POST(self):
            name = os.path.basename(self.path.strip("/"))
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            with open(os.path.join(out_dir, name), "wb") as handle:
                handle.write(body)
            print(f"saved {name} ({length} bytes)", flush=True)
            self.send_bytes(b"ok", "text/plain")

        def log_message(self, *args):
            pass

    return Handler


def serve(weapon):
    print(f"receiving into {os.path.relpath(source_dir(weapon), ROOT)} on http://127.0.0.1:{PORT} (ctrl-c to stop)")
    http.server.HTTPServer(("127.0.0.1", PORT), make_handler(weapon)).serve_forever()


def parse_obj(path):
    positions, uvs, normals, tris = [], [], [], []
    with open(path) as handle:
        for line in handle:
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "v":
                positions.append(tuple(float(x) for x in parts[1:4]))
            elif parts[0] == "vt":
                uvs.append(tuple(float(x) for x in parts[1:3]))
            elif parts[0] == "vn":
                normals.append(tuple(float(x) for x in parts[1:4]))
            elif parts[0] == "f":
                corners = []
                for token in parts[1:]:
                    vi, ti, ni = (token.split("/") + ["", ""])[:3]
                    corners.append((int(vi) - 1, int(ti) - 1 if ti else None, int(ni) - 1 if ni else None))
                for k in range(1, len(corners) - 1):
                    tris.append((corners[0], corners[k], corners[k + 1]))
    return positions, uvs, normals, tris


def weld(positions, uvs, normals, tris):
    verts, index_of, indices = [], {}, []
    for tri in tris:
        for corner in tri:
            if corner not in index_of:
                index_of[corner] = len(verts)
                verts.append(corner)
            indices.append(index_of[corner])
    pos_out, uv_out, nrm_out = [], [], []
    for vi, ti, ni in verts:
        pos_out.append(positions[vi])
        uv_out.append(uvs[ti] if ti is not None else (0.0, 0.0))
        nrm_out.append(normals[ni] if ni is not None else (0.0, 1.0, 0.0))
    return pos_out, uv_out, nrm_out, indices


def build_glb(pos, uv, nrm, indices, out_path):
    pos_bytes = b"".join(struct.pack("<fff", *p) for p in pos)
    nrm_bytes = b"".join(struct.pack("<fff", *n) for n in nrm)
    uv_bytes = b"".join(struct.pack("<ff", *t) for t in uv)
    idx_bytes = b"".join(struct.pack("<I", i) for i in indices)
    while len(idx_bytes) % 4:
        idx_bytes += b"\x00"

    blobs = [pos_bytes, nrm_bytes, uv_bytes, idx_bytes]
    offsets, cursor = [], 0
    for blob in blobs:
        offsets.append(cursor)
        cursor += len(blob)
    bin_chunk = b"".join(blobs)

    mins = [min(p[i] for p in pos) for i in range(3)]
    maxs = [max(p[i] for p in pos) for i in range(3)]

    gltf = {
        "asset": {"version": "2.0", "generator": "tfz-mesh-pipeline"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "mesh"}],
        "meshes": [{
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": 3,
                "mode": 4,
            }]
        }],
        "buffers": [{"byteLength": len(bin_chunk)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets[0], "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offsets[1], "byteLength": len(nrm_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offsets[2], "byteLength": len(uv_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offsets[3], "byteLength": len(idx_bytes), "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": mins, "max": maxs},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": len(indices), "type": "SCALAR"},
        ],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    while len(json_bytes) % 4:
        json_bytes += b" "

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_chunk)
    with open(out_path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        handle.write(bin_chunk)


def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, width, height, rgba):
    stride = width * 4
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(png_chunk(b"IHDR", header))
        handle.write(png_chunk(b"IDAT", zlib.compress(raw, 9)))
        handle.write(png_chunk(b"IEND", b""))


def convert_meshes(weapon, out_dir, manifest):
    converted = []
    for name in sorted(os.listdir(out_dir)):
        if not name.endswith(".obj") or not name.startswith(weapon + "_"):
            continue
        part = name[len(weapon) + 1:-4]
        src = os.path.join(out_dir, name)
        dst = os.path.join(out_dir, f"{weapon}_{part}.glb")
        positions, uvs, normals, tris = parse_obj(src)
        pos, uv, nrm, indices = weld(positions, uvs, normals, tris)
        build_glb(pos, uv, nrm, indices, dst)
        os.remove(src)
        upsert(manifest, f"viewmodel/{weapon}/model_{part.lower()}", os.path.relpath(dst, ROOT))
        converted.append(part)
        print(f"{part}: {len(pos)} verts, {len(indices) // 3} tris -> {os.path.basename(dst)} ({os.path.getsize(dst)} bytes)")
    return converted


def convert_textures(weapon, out_dir, manifest):
    groups = {}
    for name in os.listdir(out_dir):
        match = CHUNK_PATTERN.match(name)
        if not match or not name.startswith(weapon + "_"):
            continue
        key = (match.group("stem"), int(match.group("w")), int(match.group("h")))
        groups.setdefault(key, []).append((int(match.group("part") or 0), name))
    converted = []
    for (stem, width, height), chunks in sorted(groups.items()):
        rgba = b""
        for _, name in sorted(chunks):
            with open(os.path.join(out_dir, name), "rb") as handle:
                rgba += handle.read()
        expected = width * height * 4
        if len(rgba) != expected:
            print(f"skip  {stem}: got {len(rgba)} bytes, expected {expected}")
            continue
        dst = os.path.join(out_dir, f"{stem}.png")
        write_png(dst, width, height, rgba)
        for _, name in chunks:
            os.remove(os.path.join(out_dir, name))
        part = stem[len(weapon) + 1:-4]
        upsert(manifest, f"viewmodel/{weapon}/tex_{part.lower()}", os.path.relpath(dst, ROOT))
        converted.append(part)
        print(f"{part}: {width}x{height} -> {os.path.basename(dst)} ({os.path.getsize(dst)} bytes)")
    return converted


def convert(weapon):
    out_dir = source_dir(weapon)
    manifest = load_manifest()
    meshes = convert_meshes(weapon, out_dir, manifest)
    textures = convert_textures(weapon, out_dir, manifest)
    if not meshes and not textures:
        print(f"nothing to convert in {os.path.relpath(out_dir, ROOT)}")
        return 1
    save_manifest(manifest)
    print(f"manifest updated; next: python3 scripts/upload_assets.py --only viewmodel/{weapon}/")
    return 0


def finalize(weapon):
    out_dir = source_dir(weapon)
    ids_path = os.path.join(out_dir, f"{weapon}_meshids.json")
    if not os.path.exists(ids_path):
        print(f"no {os.path.relpath(ids_path, ROOT)}; run tools/cube3d/ImportMeshes.server.luau with the receiver up")
        return 1
    with open(ids_path, encoding="utf-8") as handle:
        mesh_ids = json.load(handle)
    manifest = load_manifest()
    for part, mesh_id in mesh_ids.items():
        model_entry = manifest.get(f"viewmodel/{weapon}/model_{part.lower()}")
        file_path = model_entry["file"] if model_entry else os.path.relpath(os.path.join(out_dir, f"{weapon}_{part}.glb"), ROOT)
        status = model_entry.get("status", "approved") if model_entry else "approved"
        upsert(manifest, f"viewmodel/{weapon}/mesh_{part.lower()}", file_path, int(mesh_id), status)
        print(f"mesh_{part.lower()} -> {mesh_id}")
    save_manifest(manifest)
    os.remove(ids_path)
    print("manifest updated; add LICENSES.md rows, then dump the rig with tools/cube3d/DumpRig.server.luau")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["serve", "convert", "finalize"])
    parser.add_argument("weapon", help="lowercase weapon name, e.g. rifle")
    arguments = parser.parse_args()
    if arguments.command == "serve":
        serve(arguments.weapon)
        return 0
    if arguments.command == "convert":
        return convert(arguments.weapon)
    return finalize(arguments.weapon)


if __name__ == "__main__":
    sys.exit(main())
