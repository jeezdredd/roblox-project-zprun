#!/usr/bin/env python3
"""Writes a pack rig's material textures as Roblox SurfaceAppearance maps.

    python3 tools/fps_pack/extract_surfaces.py RIG.glb OUT_DIR SURFACE=MATERIAL[:roughness,metalness] ...

Roblox's importer drops a material that carries only a base colour texture (the Fab G17
rig came in with no SurfaceAppearance at all), so the maps are uploaded as images and
mounted as SurfaceAppearance templates (scripts/sync_configs.py, texture/viewmodel/*),
which ViewmodelPacks puts on the meshes. For every SURFACE=MATERIAL pair this writes
OUT_DIR/<surface>_color.png and, when the glTF has them, _normal.png (glTF normals are
OpenGL convention, as Roblox wants) and _roughness.png / _metalness.png from the
metallicRoughness texture (G = roughness, B = metalness), each times the material's
roughnessFactor / metallicFactor as glTF defines them (the M4 pack's skin and glove carry
a full-white B channel under metallicFactor 0: read raw, the arms rendered as metal); the
colour is scaled by baseColorFactor in linear space (the importer ignores that factor too).
A map that comes out one flat value is written as an 8x8 image. A material with
alphaMode MASK keeps its colour alpha, cut at alphaCutoff to 0 or 255 (the template then
needs AlphaMode Transparency: the Hazmat's broken visor came in opaque grey under the
importer's Overlay); BLEND keeps it as it is. Constants after the colon
stand in for a missing metallicRoughness texture. Maps are scaled down to 1024 px, the
most Roblox keeps.

The textures of Fab packs are Fab content: OUT_DIR belongs under assets/fab/.
"""

import io
import json
import os
import struct
import sys

from PIL import Image

MAX_SIZE = 1024


def load(path):
    data = open(path, "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + length])
    offset = 20 + length
    blob_length = struct.unpack("<I", data[offset:offset + 4])[0]
    return doc, data[offset + 8:offset + 8 + blob_length]


def image(doc, blob, texture_index):
    source = doc["textures"][texture_index]["source"]
    view = doc["bufferViews"][doc["images"][source]["bufferView"]]
    start = view.get("byteOffset", 0)
    return Image.open(io.BytesIO(blob[start:start + view["byteLength"]]))


def fit(img):
    if max(img.size) > MAX_SIZE:
        scale = MAX_SIZE / max(img.size)
        img = img.resize((max(1, round(img.size[0] * scale)), max(1, round(img.size[1] * scale))), Image.LANCZOS)
    return img


def to_linear(value):
    c = value / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_srgb(linear):
    c = 12.92 * linear if linear <= 0.0031308 else 1.055 * linear ** (1 / 2.4) - 0.055
    return max(0, min(255, round(c * 255)))


def flat(value):
    return Image.new("L", (8, 8), max(0, min(255, round(value * 255))))


def scaled(channel, factor):
    """A metallicRoughness channel times its glTF factor; one flat value as an 8x8."""
    if factor != 1.0:
        channel = channel.point(lambda v: max(0, min(255, round(v * factor))))
    low, high = channel.getextrema()
    return flat(low / 255) if low == high else channel


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    rig, out_dir = sys.argv[1], sys.argv[2]
    doc, blob = load(rig)
    materials = {m.get("name"): m for m in doc.get("materials", [])}
    os.makedirs(out_dir, exist_ok=True)
    for spec in sys.argv[3:]:
        surface, _, rest = spec.partition("=")
        material_name, _, constants = rest.partition(":")
        material = materials.get(material_name)
        if material is None:
            raise SystemExit(f"{rig}: no material {material_name!r} (have {sorted(materials)})")
        pbr = material.get("pbrMetallicRoughness", {})
        written = []

        def save(img, suffix):
            path = os.path.join(out_dir, f"{surface}_{suffix}.png")
            img.save(path, optimize=True)
            written.append(suffix)

        base = pbr.get("baseColorTexture")
        if not base:
            raise SystemExit(f"{material_name}: no base colour texture")
        alpha_mode = material.get("alphaMode", "OPAQUE")
        source = image(doc, blob, base["index"])
        color = fit(source.convert("RGBA" if alpha_mode in ("MASK", "BLEND") else "RGB"))
        tint = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
        if any(abs(value - 1.0) > 1e-6 for value in tint[:3]):
            # the factor scales the linear colour; the texture is sRGB
            bands = color.split()
            tinted = [band.point(lambda v, f=f: to_srgb(to_linear(v) * f)) for band, f in zip(bands[:3], tint[:3])]
            color = Image.merge(color.mode, tinted + list(bands[3:]))
        if alpha_mode == "MASK":
            cutoff = round(float(material.get("alphaCutoff", 0.5)) * 255)
            bands = color.split()
            color = Image.merge("RGBA", list(bands[:3]) + [bands[3].point(lambda v: 255 if v >= cutoff else 0)])
        save(color, "color")
        normal = material.get("normalTexture")
        if normal:
            save(fit(image(doc, blob, normal["index"]).convert("RGB")), "normal")
        mr = pbr.get("metallicRoughnessTexture")
        if mr:
            channels = fit(image(doc, blob, mr["index"]).convert("RGB")).split()
            save(scaled(channels[1], float(pbr.get("roughnessFactor", 1.0))), "roughness")
            save(scaled(channels[2], float(pbr.get("metallicFactor", 1.0))), "metalness")
        elif constants:
            roughness, metalness = (float(x) for x in constants.split(","))
            save(flat(roughness), "roughness")
            save(flat(metalness), "metalness")
        note = f" (alpha {alpha_mode.lower()}: the template needs AlphaMode Transparency)" if alpha_mode in ("MASK", "BLEND") else ""
        print(f"{surface}: {material_name} -> {', '.join(written)}{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
