#!/usr/bin/env python3
"""The Megascans importer on synthetic surfaces.

Run from the repository root:  python3 tests/megascans/run.py

Every map is generated here, in a temporary directory, from a known height field:
no Megascans file is read or committed (Fab content never enters the repository).
Covers both layouts (a Bridge export folder and a Fab download zip), the map suffix
matching, the 1024 px outputs, the DirectX to OpenGL normal conversion and its
detection from the displacement map, the AO multiply in linear light, the studs per
tile maths, the manifest rows, the generated variants (sync_configs.py), the Fab file
rules (fab_files.py) and the gitignore. Exits non-zero when any check failed.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from contextlib import redirect_stdout

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "megascans"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import fab_files  # noqa: E402
import import_surface  # noqa: E402
import surface as ms  # noqa: E402
import sync_configs  # noqa: E402

failures = 0


def check(name, condition, detail=""):
    global failures
    if not condition:
        failures += 1
        print(f"  FAIL {name}" + (f" ({detail})" if detail else ""))


def group(name, body):
    before = failures
    try:
        body()
    except Exception as error:  # a crash is a failed group, not a stopped run
        check(f"{name} raised", False, f"{type(error).__name__}: {error}")
    print(("ok   " if failures == before else "FAIL ") + name)


# Synthetic maps ---------------------------------------------------------------------

N = 64
ALBEDO = (0.5, 0.4, 0.3)
AO = 0.25


def height_field(size=N):
    rows, cols = np.mgrid[0:size, 0:size].astype(np.float32) / size
    h = 0.5 + 0.25 * np.sin(2 * np.pi * 3 * cols) * np.cos(2 * np.pi * 2 * rows) + 0.2 * np.sin(2 * np.pi * rows)
    return np.clip(h, 0.0, 1.0)


def normals_from(height, convention, strength=4.0):
    """RGB 0..1. OpenGL: x = -dh/dcol, y = +dh/drow (rows run down, green points up)."""
    size = height.shape[0]
    x = -np.gradient(height, axis=1) * size / strength
    y = np.gradient(height, axis=0) * size / strength
    if convention == "directx":
        y = -y
    vectors = np.stack([x, y, np.ones_like(x)], axis=2)
    vectors /= np.linalg.norm(vectors, axis=2, keepdims=True)
    return (vectors + 1.0) * 0.5


def to8(values):
    return (np.clip(values, 0, 1) * 255 + 0.5).astype(np.uint8)


def write_rgb(path, rgb):
    Image.fromarray(to8(rgb)).save(path)


def write_gray(path, gray, sixteen=False):
    if sixteen:
        Image.fromarray((np.clip(gray, 0, 1) * 65535 + 0.5).astype(np.uint16)).save(path)
    else:
        Image.fromarray(to8(gray)).save(path)


def constant_rgb(color):
    return np.ones((N, N, 3), dtype=np.float32) * np.array(color, dtype=np.float32)


def constant_gray(value):
    return np.full((N, N), value, dtype=np.float32)


def roughness_field():
    rows, cols = np.mgrid[0:N, 0:N].astype(np.float32) / N
    return 0.3 + 0.4 * cols


def make_bridge(base, asset_id="tbdpec3r"):
    """Bridge export: <name>_<id>/<id>.json with <id>_2K_<Map> beside it. Unlabelled
    OpenGL normal, JPG roughness, 16-bit displacement, a preview to skip."""
    folder = os.path.join(base, "Downloaded", "surface", f"asphalt_cracked_{asset_id}")
    os.makedirs(folder)
    meta = {
        "id": asset_id,
        "name": "Cracked Asphalt",
        "categories": ["surface", "asphalt"],
        "tags": ["road", "cracked"],
        "meta": [
            {"key": "scanArea", "name": "Scan Area", "value": "2x2 m"},
            {"key": "tileable", "name": "Tileable", "value": True},
        ],
    }
    with open(os.path.join(folder, f"{asset_id}.json"), "w") as handle:
        json.dump(meta, handle)
    height = height_field()
    write_rgb(os.path.join(folder, f"{asset_id}_2K_Albedo.png"), constant_rgb(ALBEDO))
    write_rgb(os.path.join(folder, f"{asset_id}_2K_Normal.png"), normals_from(height, "opengl"))
    Image.fromarray(to8(roughness_field())).convert("RGB").save(os.path.join(folder, f"{asset_id}_2K_Roughness.jpg"), quality=95)
    write_gray(os.path.join(folder, f"{asset_id}_2K_AO.png"), constant_gray(AO))
    write_gray(os.path.join(folder, f"{asset_id}_2K_Displacement.png"), height, sixteen=True)
    write_rgb(os.path.join(folder, f"{asset_id}_Preview.png"), constant_rgb((1, 0, 0)))
    return folder


def make_fab_zip(base, normal_name="Normal_DX", normal_convention="directx", with_height=True, size_text="200 x 200 cm"):
    """Fab download: a zip with one folder, maps named <Asset>_2K_<Map>, a JSON with a
    top-level physical size."""
    folder = os.path.join(base, "fab_src", "Cracked_Asphalt_tbdpec3r_2K")
    os.makedirs(folder)
    meta = {"id": "tbdpec3r", "name": "Cracked Asphalt", "physicalSize": size_text, "tags": ["asphalt"]}
    with open(os.path.join(folder, "Cracked_Asphalt.json"), "w") as handle:
        json.dump(meta, handle)
    height = height_field()
    write_rgb(os.path.join(folder, "Cracked_Asphalt_2K_BaseColor.png"), constant_rgb(ALBEDO))
    write_rgb(os.path.join(folder, f"Cracked_Asphalt_2K_{normal_name}.png"), normals_from(height, normal_convention))
    write_gray(os.path.join(folder, "Cracked_Asphalt_2K_Roughness.png"), roughness_field())
    write_gray(os.path.join(folder, "Cracked_Asphalt_2K_AO.png"), constant_gray(AO))
    if with_height:
        write_gray(os.path.join(folder, "Cracked_Asphalt_2K_Height.png"), height)
    path = os.path.join(base, "Cracked_Asphalt_tbdpec3r_2K.zip")
    with zipfile.ZipFile(path, "w") as archive:
        for name in sorted(os.listdir(folder)):
            archive.write(os.path.join(folder, name), f"Cracked_Asphalt_tbdpec3r_2K/{name}")
    shutil.rmtree(os.path.join(base, "fab_src"))
    return path


def make_metal(base):
    """Fab layout, metal: BaseColor, NormalGL and an ORM map (R AO, G roughness, B metal)."""
    folder = os.path.join(base, "Rusty_Metal_sb0kv2p_2K")
    os.makedirs(folder)
    with open(os.path.join(folder, "Rusty_Metal.json"), "w") as handle:
        json.dump({"id": "sb0kv2p", "name": "Rusty Metal Sheet", "physicalSize": {"width": 1.5, "height": 1.5, "unit": "m"}, "categories": ["metal", "rust"]}, handle)
    write_rgb(os.path.join(folder, "Rusty_Metal_2K_BaseColor.png"), constant_rgb((0.4, 0.25, 0.15)))
    write_rgb(os.path.join(folder, "Rusty_Metal_2K_NormalGL.png"), normals_from(height_field(), "opengl"))
    orm = np.stack([constant_gray(1.0), constant_gray(0.6), constant_gray(0.8)], axis=2)
    write_rgb(os.path.join(folder, "Rusty_Metal_2K_ORM.png"), orm)
    return folder


def temp_root(base):
    """A minimal repository root for the importer: the manifest, the metre constant
    and MaterialUtil (for --replaces), copied from the real one."""
    root = os.path.join(base, "repo")
    for relative in ("src/shared/config/WorldMeshConfig.luau", "src/shared/util/MaterialUtil.luau"):
        os.makedirs(os.path.dirname(os.path.join(root, relative)), exist_ok=True)
        shutil.copy(os.path.join(ROOT, relative), os.path.join(root, relative))
    os.makedirs(os.path.join(root, "assets"))
    with open(os.path.join(root, "assets", "manifest.json"), "w") as handle:
        json.dump({}, handle)
    return root


def run_import(argv):
    out = io.StringIO()
    with redirect_stdout(out):
        code = import_surface.run(argv)
    return code, out.getvalue()


def read_png(path):
    with Image.open(path) as image:
        return image.mode, image.size, np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0


# Tests ------------------------------------------------------------------------------


def test_suffixes():
    cases = {
        "tbdpec3r_2K_Albedo.jpg": "albedo",
        "T_Asphalt_4K_BaseColor.png": "albedo",
        "x_Diffuse.tif": "albedo",
        "x_2K_Normal.jpg": "normal",
        "x_2K_NormalBump.jpg": "normal",
        "x_Normal_LOD0.png": "normal",
        "x_2K_Normal_GL.png": "normal_gl",
        "x_2K_NormalDX.png": "normal_dx",
        "x_2K_Normal_DirectX.png": "normal_dx",
        "x_2K_ROUGHNESS.PNG": "roughness",
        "x_Gloss.jpg": "gloss",
        "x_2K_AO.jpg": "ao",
        "x_Ambient_Occlusion.png": "ao",
        "x_2K_Displacement.exr": None,
        "x_2K_Displacement.tif": "displacement",
        "x_Height.png": "displacement",
        "x_2K_Metalness.jpg": "metalness",
        "x_ORM.png": "orm",
        "x_2K_Cavity.jpg": None,
        "x_2K_Specular.jpg": None,
        "x_Preview.png": None,
        "x_2K_Albedo_thumb.png": None,
        "notes.txt": None,
    }
    for name, kind in cases.items():
        check(f"classify {name}", ms.classify(name) == kind, str(ms.classify(name)))


def test_studs():
    per_metre = ms.studs_per_metre(ROOT)
    check("metre constant is 1 / 0.28", abs(per_metre - 1 / 0.28) < 1e-9, str(per_metre))
    cases = (
        ({"meta": [{"key": "scanArea", "value": "2x2 m"}]}, 7.14),
        ({"physicalSize": "200 x 200 cm"}, 7.14),
        ({"physicalSize": {"width": 1.5, "height": 1.5, "unit": "m"}}, 5.36),
        ({"meta": [{"name": "Physical Size", "value": "3 x 1.5"}]}, 10.71),
        ({"size": "4m"}, 14.29),
        ({"physicalSize": [2, 2]}, 7.14),
        ({"meta": [{"key": "scanArea", "value": "1500 x 1500 mm"}]}, 5.36),
    )
    for meta, expected in cases:
        got = ms.studs_per_tile(meta, per_metre)
        check(f"studs for {json.dumps(meta)}", got == expected, f"{got} != {expected}")
    check("override wins", ms.studs_per_tile({"physicalSize": "2x2 m"}, per_metre, 12) == 12)
    try:
        ms.studs_per_tile({"name": "x"}, per_metre)
        check("no size fails", False)
    except ms.SurfaceError as error:
        check("no size names the flag", "--studs-per-tile" in str(error))


def test_normal_maths():
    height = height_field(128)
    gl = normals_from(height, "opengl")
    dx = normals_from(height, "directx")
    converted = ms.to_opengl(dx.copy(), "directx")
    check("DirectX green flipped to OpenGL", np.abs(converted - gl).max() < 1e-4, str(np.abs(converted - gl).max()))
    check("OpenGL kept", np.abs(ms.to_opengl(gl.copy(), "opengl") - gl).max() < 1e-4)
    check("red and blue untouched", np.abs(converted[:, :, [0, 2]] - dx[:, :, [0, 2]]).max() < 1e-4)
    vectors = converted * 2 - 1
    check("unit length", np.abs(np.linalg.norm(vectors, axis=2) - 1).max() < 1e-4)
    check("detect OpenGL", ms.detect_convention(gl, height) == "opengl")
    check("detect DirectX", ms.detect_convention(dx, height) == "directx")
    flat = np.ones_like(gl) * np.array([0.5, 0.5, 1.0])
    check("flat map undetermined", ms.detect_convention(flat, height) is None)
    check("unrelated height undetermined", ms.detect_convention(gl, height_field(128).T * 0 + 0.5) is None)


def test_ao_maths():
    albedo = constant_rgb(ALBEDO)
    ao = constant_gray(AO)
    for strength in (0.0, 0.5, 1.0):
        got = ms.ao_multiply(albedo, ao, strength)[0, 0]
        factor = 1 - strength * (1 - AO)
        expected = ms.linear_to_srgb(ms.srgb_to_linear(np.array(ALBEDO)) * factor)
        check(f"AO multiply at {strength}", np.abs(got - expected).max() < 1e-6, f"{got} vs {expected}")
    check("strength 0 is the albedo", np.abs(ms.ao_multiply(albedo, ao, 0.0) - albedo).max() < 1e-6)
    check("white AO changes nothing", np.abs(ms.ao_multiply(albedo, constant_gray(1.0), 1.0) - albedo).max() < 1e-6)
    try:
        ms.ao_multiply(albedo, ao, 1.5)
        check("strength over 1 fails", False)
    except ms.SurfaceError:
        pass


def expected_color(strength):
    factor = 1 - strength * (1 - AO)
    return ms.linear_to_srgb(ms.srgb_to_linear(np.array(ALBEDO)) * factor)


def test_bridge_layout(base):
    folder = make_bridge(base)
    surface = ms.read_surface(os.path.dirname(os.path.dirname(folder)))
    check("bridge layout", surface.layout == "bridge", surface.layout)
    check("bridge id and name", surface.asset_id == "tbdpec3r" and surface.name == "Cracked Asphalt")
    check("preview skipped", all("Preview" not in path for path in surface.maps.values()))
    check("bridge guess", ms.guess_base_material(surface) == "Asphalt")
    out = os.path.join(base, "out_bridge")
    result = ms.process(surface, out, "asphalt_cracked", "Asphalt", 0.5)
    check("bridge writes three maps", sorted(result["files"]) == ["color", "normal", "roughness"], str(sorted(result["files"])))
    for suffix, path in result["files"].items():
        mode, size, _ = read_png(path)
        check(f"bridge {suffix} is 1024 RGB PNG", size == (1024, 1024) and mode == "RGB", f"{mode} {size}")
        check(f"bridge {suffix} named", os.path.basename(path) == f"asphalt_cracked_{suffix}.png")
    _, _, color = read_png(result["files"]["color"])
    check("bridge AO multiplied", np.abs(color.mean(axis=(0, 1)) - expected_color(0.5)).max() < 1.5 / 255, str(color.mean(axis=(0, 1))))
    check("unlabelled normal read from displacement", result["normal"] == ("opengl", "unlabelled, read from the displacement map"), str(result["normal"]))
    _, _, rough = read_png(result["files"]["roughness"])
    check("roughness gradient kept", abs(rough[:, 8, 0].mean() - (0.3 + 0.4 * 8 / 1024)) < 0.03 and abs(rough[:, -8, 0].mean() - 0.7) < 0.03)
    return result


def test_fab_layout(base, bridge_result):
    path = make_fab_zip(base)
    with ms.opened_source(path) as folder:
        temp = folder
        surface = ms.read_surface(folder)
        check("fab layout", surface.layout == "fab", surface.layout)
        out = os.path.join(base, "out_fab")
        result = ms.process(surface, out, "asphalt_cracked", "Asphalt", 0.5)
    check("zip extracted outside the repository", not os.path.realpath(temp).startswith(ROOT + os.sep))
    check("zip temp removed", not os.path.exists(temp))
    check("named DX normal", result["normal"] == ("directx", "named DX"), str(result["normal"]))
    _, _, fab_normal = read_png(result["files"]["normal"])
    _, _, bridge_normal = read_png(bridge_result["files"]["normal"])
    check("DX normal converted to the same map as the GL one", np.abs(fab_normal - bridge_normal).max() <= 2.5 / 255, str(np.abs(fab_normal - bridge_normal).max() * 255))
    _, _, color = read_png(result["files"]["color"])
    check("fab AO multiplied", np.abs(color.mean(axis=(0, 1)) - expected_color(0.5)).max() < 1.5 / 255)
    check("fab studs from cm", ms.studs_per_tile(surface.metadata, 1 / 0.28) == 7.14)


def test_normal_choice(base):
    sub = os.path.join(base, "unlabelled_dx")
    os.makedirs(sub)
    path = make_fab_zip(sub, normal_name="Normal", normal_convention="directx")
    with ms.opened_source(path) as folder:
        result = ms.process(ms.read_surface(folder), os.path.join(sub, "out"), "x", "Asphalt")
        check("unlabelled DX detected", result["normal"][0] == "directx", str(result["normal"]))
        forced = ms.process(ms.read_surface(folder), os.path.join(sub, "out"), "x", "Asphalt", normal_convention="opengl")
        check("forced convention wins", forced["normal"] == ("opengl", "--normal-convention"))
    sub = os.path.join(base, "unlabelled_no_height")
    os.makedirs(sub)
    path = make_fab_zip(sub, normal_name="Normal", normal_convention="opengl", with_height=False)
    with ms.opened_source(path) as folder:
        result = ms.process(ms.read_surface(folder), os.path.join(sub, "out"), "x", "Asphalt")
        check("unlabelled without height is OpenGL", result["normal"] == ("opengl", "unlabelled, OpenGL by default"), str(result["normal"]))
        check("the fallback warns", any("--normal-convention" in w for w in result["warnings"]), str(result["warnings"]))
    with ms.opened_source(make_fab_zip(os.path.join(base, "labelled"), normal_name="Normal_DX")) as folder:
        labelled = ms.process(ms.read_surface(folder), os.path.join(base, "labelled_out"), "x", "Asphalt")
        check("a labelled map does not warn", labelled["warnings"] == [], str(labelled["warnings"]))


def test_guards(base):
    # whole words only
    class Words:
        def __init__(self, text):
            self.text = text

        def words(self):
            return self.text

    check("sand inside sandstone is not Sand", ms.guess_base_material(Words("sandstone wall surface")) is None)
    check("plural counts", ms.guess_base_material(Words("old red bricks")) == "Brick")
    check("rust inside trust is not metal", ms.guess_base_material(Words("trusty floor concrete")) == "Concrete")
    check("whole word hits", ms.guess_base_material(Words("forest ground leaves")) == "Ground")

    # the size range
    for meta in ({"physicalSize": "200"}, {"physicalSize": "0.01 m"}, {"physicalSize": "80x80 m"}):
        try:
            ms.studs_per_tile(meta, 1 / 0.28)
            check(f"size {meta} refused", False)
        except ms.SurfaceError as error:
            check(f"size {meta} names the flag", "--studs-per-tile" in str(error))
    check("an in-range size passes", ms.studs_per_tile({"physicalSize": "50 m"}, 1 / 0.28) == round(50 / 0.28, 2))

    # non-square maps
    folder = os.path.join(base, "wide")
    os.makedirs(folder)
    write_rgb(os.path.join(folder, "w_Albedo.png"), np.ones((32, 64, 3)) * 0.5)
    write_rgb(os.path.join(folder, "w_NormalGL.png"), normals_from(height_field(), "opengl"))
    write_gray(os.path.join(folder, "w_Roughness.png"), roughness_field())
    try:
        ms.process(ms.read_surface(folder), os.path.join(base, "wide_out"), "w", "Concrete")
        check("a non-square map is refused", False)
    except ms.SurfaceError as error:
        check("the refusal names the map and the flag", "w_Albedo.png" in str(error) and "--allow-non-square" in str(error), str(error))
    allowed = ms.process(ms.read_surface(folder), os.path.join(base, "wide_out"), "w", "Concrete", allow_non_square=True)
    check("allowed with a warning", any("not square" in w for w in allowed["warnings"]))

    # --override needs --base-material
    root = temp_root(os.path.join(base, "override"))
    source = make_bridge(os.path.join(base, "override_src"))
    try:
        run_import([source, "--slot", "asphalt", "--override", "--root", root, "--no-sync"])
        check("--override without --base-material refused", False)
    except ms.SurfaceError as error:
        check("the refusal names --base-material", "--base-material" in str(error))
    code, _ = run_import([source, "--slot", "asphalt", "--override", "--base-material", "Asphalt", "--root", root, "--no-sync"])
    check("--override with --base-material runs", code == 0)

    # a slot never touches a slot it is a prefix of, and variant names never collide
    code, _ = run_import([source, "--slot", "asphalt_old", "--root", root, "--no-sync"])
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        manifest = json.load(handle)
    code, _ = run_import([source, "--slot", "asphalt", "--base-material", "Asphalt", "--override", "--root", root, "--no-sync"])
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        after = json.load(handle)
    old_keys = [k for k in manifest if "asphalt_old_" in k]
    check("re-importing asphalt keeps asphalt_old", old_keys and all(k in after for k in old_keys))
    try:
        run_import([source, "--slot", "asphalt_old2", "--root", root, "--no-sync"])
        run_import([source, "--slot", "asphalt_old_2", "--root", root, "--no-sync"])
        check("clashing variant names refused", False)
    except ms.SurfaceError as error:
        check("the clash names the variant", "TFZ_MS_AsphaltOld2" in str(error), str(error))

    # a refused re-import leaves assets/fab/textures alone
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        manifest = json.load(handle)
    for key in [k for k in manifest if "/asphalt_" in k and k.rsplit("/", 1)[1].startswith("asphalt_") and k.rsplit("_", 1)[0].endswith("/asphalt")]:
        manifest[key]["assetId"] = 77
    with open(os.path.join(root, "assets", "manifest.json"), "w") as handle:
        json.dump(manifest, handle)
    textures = os.path.join(root, "assets", "fab", "textures")
    before = {name: os.path.getmtime(os.path.join(textures, name)) for name in os.listdir(textures)}
    other = make_bridge(os.path.join(base, "other_src"), asset_id="zzzz0000")
    try:
        run_import([other, "--slot", "asphalt", "--base-material", "Asphalt", "--root", root, "--no-sync"])
        check("re-import of an uploaded slot refused", False)
    except ms.SurfaceError:
        pass
    after_files = {name: os.path.getmtime(os.path.join(textures, name)) for name in os.listdir(textures)}
    check("the refused import wrote no map", after_files == before)


def test_metal(base):
    folder = make_metal(base)
    surface = ms.read_surface(folder)
    check("metal guess", ms.guess_base_material(surface) == "CorrodedMetal")
    result = ms.process(surface, os.path.join(base, "out_metal"), "metal_rusty", "CorrodedMetal", 0.5)
    check("metal writes four maps", sorted(result["files"]) == ["color", "metalness", "normal", "roughness"], str(sorted(result["files"])))
    _, size, metal = read_png(result["files"]["metalness"])
    check("metalness from ORM blue", size == (1024, 1024) and abs(metal.mean() - 0.8) < 1.5 / 255)
    _, _, rough = read_png(result["files"]["roughness"])
    check("roughness from ORM green", abs(rough.mean() - 0.6) < 1.5 / 255)
    _, _, color = read_png(result["files"]["color"])
    check("ORM red is AO (white: no darkening)", np.abs(color.mean(axis=(0, 1)) - np.array([0.4, 0.25, 0.15])).max() < 1.5 / 255)
    plain = ms.process(surface, os.path.join(base, "out_metal_plain"), "metal_plain", "Concrete", 0.5)
    check("no metalness off metal", "metalness" not in plain["files"])

    gloss_dir = os.path.join(base, "gloss_surface")
    os.makedirs(gloss_dir)
    write_rgb(os.path.join(gloss_dir, "g_Albedo.png"), constant_rgb(ALBEDO))
    write_rgb(os.path.join(gloss_dir, "g_Normal.png"), normals_from(height_field(), "opengl"))
    write_gray(os.path.join(gloss_dir, "g_Gloss.png"), constant_gray(0.2))
    glossy = ms.process(ms.read_surface(gloss_dir), os.path.join(base, "out_gloss"), "g", "Concrete")
    _, _, rough = read_png(glossy["files"]["roughness"])
    check("roughness is 1 - gloss", abs(rough.mean() - 0.8) < 1.5 / 255)
    check("no AO noted", any("no AO" in note for note in glossy["notes"]))


def test_missing_map(base):
    folder = os.path.join(base, "incomplete")
    os.makedirs(folder)
    write_rgb(os.path.join(folder, "x_2K_Albedo.png"), constant_rgb(ALBEDO))
    write_gray(os.path.join(folder, "x_2K_Roughness.png"), roughness_field())
    write_gray(os.path.join(folder, "x_2K_Cavity.png"), roughness_field())
    try:
        ms.process(ms.read_surface(folder), os.path.join(base, "out_incomplete"), "x", "Concrete")
        check("missing normal fails", False)
    except ms.SurfaceError as error:
        text = str(error)
        check("names the missing map", "missing normal" in text, text)
        check("lists what was found", "x_2K_Cavity.png" in text and "x_2K_Albedo.png" in text, text)
        check("lists what was recognised", "albedo=x_2K_Albedo.png" in text, text)


def test_import_and_rows(base):
    root = temp_root(base)
    source = make_bridge(os.path.join(base, "src_bridge"))
    argv = [source, "--slot", "asphalt_cracked", "--replaces", "TFZ_AsphaltCracked", "--pattern", "Organic", "--root", root, "--no-sync"]
    code, out = run_import(argv)
    check("import ran", code == 0, out)
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        manifest = json.load(handle)
    keys = sorted(manifest)
    expected = [f"texture/surface/megascans/asphalt_cracked_{s}" for s in ("color", "normal", "roughness")]
    check("three rows", keys == expected, str(keys))
    for key in expected:
        row = manifest.get(key, {})
        suffix = key.rsplit("_", 1)[1]
        check(f"{suffix} pending", row.get("status") == "pending" and row.get("assetId") == 0)
        check(f"{suffix} licence", row.get("license") == "Fab Standard License (Quixel Megascans)")
        check(f"{suffix} source", row.get("source") == "https://quixel.com/megascans/home?assetId=tbdpec3r", row.get("source"))
        check(f"{suffix} file under assets/fab", row.get("file") == f"assets/fab/textures/asphalt_cracked_{suffix}.png", row.get("file"))
        check(f"{suffix} file written", os.path.exists(os.path.join(root, row.get("file", "missing"))))
        check(f"{suffix} note names the asset", "Cracked Asphalt (tbdpec3r)" in row.get("note", ""), row.get("note"))
    material = manifest[expected[0]].get("material", {})
    check("material settings", material == {
        "variant": "TFZ_MS_AsphaltCracked",
        "asset": "Cracked Asphalt",
        "baseMaterial": "Asphalt",
        "studsPerTile": 7.14,
        "pattern": "Organic",
        "override": False,
        "replaces": "TFZ_AsphaltCracked",
    }, json.dumps(material))
    check("normal note says OpenGL", "OpenGL as delivered" in manifest[expected[1]]["note"])

    try:
        import_surface.run([source, "--slot", "other", "--replaces", "TFZ_Nope", "--root", root, "--no-sync"])
        check("unknown --replaces fails", False)
    except ms.SurfaceError:
        pass
    try:
        import_surface.run([source, "--slot", "Bad-Slot", "--root", root, "--no-sync"])
        check("bad slot fails", False)
    except ms.SurfaceError:
        pass

    # an uploaded slot is not re-imported by accident
    for key in expected:
        manifest[key]["assetId"] = 1000 + expected.index(key)
        manifest[key]["status"] = "approved"
    with open(os.path.join(root, "assets", "manifest.json"), "w") as handle:
        json.dump(manifest, handle)
    try:
        run_import(argv)
        check("re-import without --replace fails", False)
    except ms.SurfaceError as error:
        check("re-import names --replace", "--replace" in str(error))
    code, _ = run_import(argv + ["--replace", "--studs-per-tile", "10"])
    with open(os.path.join(root, "assets", "manifest.json")) as handle:
        again = json.load(handle)
    check("re-import with --replace resets the ids", code == 0 and all(again[k]["assetId"] == 0 for k in expected))
    check("studs flag", again[expected[0]]["material"]["studsPerTile"] == 10)

    # a source inside the repository is refused, except under the gitignored assets/fab/
    for inside, allowed in ((os.path.join(ROOT, "tests"), False), (os.path.join(ROOT, "assets", "fab", "x"), True), (base, True)):
        try:
            import_surface.check_source_location(inside, ROOT)
            check(f"location {inside}", allowed)
        except ms.SurfaceError:
            check(f"location {inside}", not allowed)
    return again


def test_generated(manifest):
    with open(os.path.join(ROOT, "default.project.json")) as handle:
        project_text = handle.read()
    sets = sync_configs.megascans_sets(manifest)
    check("one set, pending", len(sets) == 1 and not sets[0]["ready"])
    check("pending: project unchanged", sync_configs.render_project(sets, project_text) == project_text)
    check("pending: empty list", "name =" not in sync_configs.render_megascans(sets))
    check("no sets: project round-trips", sync_configs.render_project([], project_text) == project_text)

    uploaded = json.loads(json.dumps(manifest))
    for index, suffix in enumerate(("color", "normal", "roughness")):
        uploaded[f"texture/surface/megascans/asphalt_cracked_{suffix}"]["assetId"] = 111 + index
    uploaded["texture/surface/megascans/asphalt_cracked_color"]["material"]["override"] = True
    sets = sync_configs.megascans_sets(uploaded)
    check("uploaded set ready", sets[0]["ready"])
    project = json.loads(sync_configs.render_project(sets, project_text))
    variant = project["tree"]["MaterialService"].get("TFZ_MS_AsphaltCracked")
    check("variant declared", variant == {
        "$className": "MaterialVariant",
        "$properties": {
            "BaseMaterial": "Asphalt",
            "ColorMap": "rbxassetid://111",
            "NormalMap": "rbxassetid://112",
            "RoughnessMap": "rbxassetid://113",
            "StudsPerTile": 10,
            "MaterialPattern": "Organic",
        },
    }, json.dumps(variant))
    check("built-in variants kept", "TFZ_AsphaltCracked" in project["tree"]["MaterialService"])
    again = sync_configs.render_project(sets, sync_configs.render_project(sets, project_text))
    check("regeneration is stable", again == sync_configs.render_project(sets, project_text))
    listing = sync_configs.render_megascans(sets)
    for line in ('name = "TFZ_MS_AsphaltCracked",', 'baseMaterial = "Asphalt",', "color = 111,", "normal = 112,",
                 "roughness = 113,", "studsPerTile = 10,", "override = true,", 'replaces = "TFZ_AsphaltCracked",'):
        check(f"list has {line}", line in listing, listing)
    check("list has no metalness", "metalness" not in listing)

    rejected = json.loads(json.dumps(uploaded))
    rejected["texture/surface/megascans/asphalt_cracked_normal"]["status"] = "rejected"
    check("a rejected map keeps the variant out", not sync_configs.megascans_sets(rejected)[0]["ready"])
    bad_base = json.loads(json.dumps(uploaded))
    bad_base["texture/surface/megascans/asphalt_cracked_color"]["material"]["baseMaterial"] = "Glass"
    try:
        sync_configs.megascans_sets(bad_base)
        check("a base material a variant cannot use fails", False)
    except sync_configs.MegascansError:
        pass
    twin = json.loads(json.dumps(uploaded))
    for suffix in ("color", "normal", "roughness"):
        twin[f"texture/surface/megascans/asphalt_cracked2_{suffix}"] = json.loads(json.dumps(uploaded[f"texture/surface/megascans/asphalt_cracked_{suffix}"]))
    try:
        sync_configs.megascans_sets(twin)
        check("two slots with one variant name fail", False)
    except sync_configs.MegascansError:
        pass
    check("an empty list is return {}", sync_configs.render_megascans([]).rstrip().endswith("return {}"))
    broken = json.loads(json.dumps(uploaded))
    del broken["texture/surface/megascans/asphalt_cracked_roughness"]
    try:
        sync_configs.megascans_sets(broken)
        check("a set without roughness fails", False)
    except sync_configs.MegascansError:
        pass


def test_fab_rules(base):
    fab_row = {"license": "Fab Standard License (Quixel Megascans)", "file": "assets/fab/textures/x_color.png", "assetId": 0}
    check("pending Fab row without its file is a problem", len(fab_files.problems({"a": fab_row}, base)) == 1)
    check("uploaded Fab row without its file is fine", fab_files.problems({"a": dict(fab_row, assetId=5)}, base) == [])
    os.makedirs(os.path.join(base, "assets", "fab", "textures"), exist_ok=True)
    open(os.path.join(base, "assets", "fab", "textures", "x_color.png"), "w").close()
    check("pending Fab row with its file is fine", fab_files.problems({"a": fab_row}, base) == [])
    check("pending Fab row with its file fails the pre-commit check", len(fab_files.problems({"a": fab_row}, base, require_ids=True)) == 1)
    check("uploaded Fab row passes the pre-commit check", fab_files.problems({"a": dict(fab_row, assetId=5)}, base, require_ids=True) == [])
    outside = dict(fab_row, file="assets/textures/x_color.png", assetId=5)
    check("Fab licence outside assets/fab is a problem", len(fab_files.problems({"a": outside}, base)) == 1)

    with open(os.path.join(ROOT, "assets", "manifest.json")) as handle:
        manifest = json.load(handle)
    check("the real manifest keeps the Fab rules", fab_files.problems(manifest, ROOT, require_ids=True) == [], str(fab_files.problems(manifest, ROOT, require_ids=True)))


def test_gitignore():
    # src/shared/fab/ holds the baked first-person clip modules of the Fab weapon packs
    for path in ("assets/fab/textures/asphalt_cracked_color.png", "assets/fab/source.zip", "src/shared/fab/M4Clips.luau"):
        ignored = subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT).returncode == 0
        check(f"{path} is gitignored", ignored)
    tracked = subprocess.run(["git", "ls-files", "assets/fab"], cwd=ROOT, capture_output=True, text=True).stdout
    check("nothing tracked under assets/fab", tracked.strip() == "", tracked)
    listing = "src/shared/config/MegascansMaterials.luau"
    check("the generated list is not ignored", subprocess.run(["git", "check-ignore", "-q", listing], cwd=ROOT).returncode != 0)


def main():
    base = tempfile.mkdtemp(prefix="megascans-test-")
    try:
        group("map suffixes", test_suffixes)
        group("studs per tile", test_studs)
        group("normal conversion and detection", test_normal_maths)
        group("AO multiply", test_ao_maths)
        holder = {}
        group("Bridge layout", lambda: holder.setdefault("bridge", test_bridge_layout(os.path.join(base, "bridge"))))
        if "bridge" in holder:
            group("Fab layout (zip)", lambda: test_fab_layout(os.path.join(base, "fab"), holder["bridge"]))
        group("normal convention choice", lambda: test_normal_choice(os.path.join(base, "choice")))
        group("metal, ORM and gloss", lambda: test_metal(os.path.join(base, "metal")))
        group("missing map", lambda: test_missing_map(os.path.join(base, "missing")))
        group("guards (words, size, square, override, slots, refused import)", lambda: test_guards(os.path.join(base, "guards")))
        group("import and manifest rows", lambda: holder.setdefault("manifest", test_import_and_rows(os.path.join(base, "import"))))
        if "manifest" in holder:
            group("generated variants", lambda: test_generated(holder["manifest"]))
        group("Fab file rules", lambda: test_fab_rules(os.path.join(base, "rules")))
        group("gitignore", test_gitignore)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    if failures:
        print(f"{failures} check(s) failed")
        return 1
    print("all megascans importer tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
