"""Read a Quixel Megascans surface (Bridge or Fab download) and turn it into the three
or four 1024 px maps a Roblox MaterialVariant takes.

Library half of tools/megascans/import_surface.py; tests/megascans/run.py drives it on
synthetic surfaces. Pillow and numpy only. Nothing here writes inside the repository
except where the caller points it (assets/fab/, which is gitignored): Fab content is
never committed, the repository is public. See docs/environment/megascans.md.
"""

import json
import os
import re
import shutil
import tempfile
import zipfile

import numpy as np
from PIL import Image

SIZE = 1024
LICENCE = "Fab Standard License (Quixel Megascans)"
MANIFEST_PREFIX = "texture/surface/megascans/"
FAB_TEXTURES = "assets/fab/textures"
VARIANT_PREFIX = "TFZ_MS_"

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".tif", ".tiff", ".tga", ".bmp")

# Enum.Material items a MaterialVariant can sit on (Glass, Neon, ForceField, Air and
# Water take no variants and are left out)
BASE_MATERIALS = (
    "Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles",
    "Cobblestone", "Concrete", "CorrodedMetal", "CrackedLava", "DiamondPlate", "Fabric",
    "Foil", "Glacier", "Granite", "Grass", "Ground", "Ice", "LeafyGrass", "Leather",
    "Limestone", "Marble", "Metal", "Mud", "Pavement", "Pebble", "Plaster", "Plastic",
    "Rock", "RoofShingles", "Rubber", "Salt", "Sand", "Sandstone", "Slate",
    "SmoothPlastic", "Snow", "Wood", "WoodPlanks",
)
METAL_MATERIALS = ("Metal", "CorrodedMetal", "DiamondPlate", "Foil")
PATTERNS = ("Regular", "Organic")

# Words in the surface's name, categories or tags that suggest a base material, in
# priority order (the first hit wins), for when --base-material is not given
MATERIAL_HINTS = (
    ("rust", "CorrodedMetal"), ("corroded", "CorrodedMetal"), ("metal", "Metal"),
    ("asphalt", "Asphalt"), ("cobblestone", "Cobblestone"), ("brick", "Brick"),
    ("concrete", "Concrete"), ("plaster", "Plaster"), ("pavement", "Pavement"),
    ("gravel", "Pebble"), ("pebble", "Pebble"), ("sand", "Sand"), ("grass", "Grass"),
    ("moss", "LeafyGrass"), ("mud", "Mud"), ("soil", "Ground"), ("dirt", "Ground"),
    ("ground", "Ground"), ("slate", "Slate"), ("rock", "Rock"), ("stone", "Rock"),
    ("cliff", "Rock"), ("plank", "WoodPlanks"), ("wood", "Wood"), ("tile", "CeramicTiles"),
    ("fabric", "Fabric"), ("snow", "Snow"), ("ice", "Ice"),
)

# map kind -> file name endings (separators removed, lower case); the first list entry
# a file matches decides its kind, a lower rank is preferred within a kind
MAP_SUFFIXES = (
    ("albedo", ("albedo", "basecolor", "basecolour", "diffuse", "color", "colour")),
    ("normal_gl", ("normalgl", "normalopengl", "nrmgl")),
    ("normal_dx", ("normaldx", "normaldirectx", "nrmdx")),
    ("normal", ("normal", "nrm", "normalbump")),
    ("roughness", ("roughness", "rough")),
    ("gloss", ("gloss", "glossiness")),
    ("orm", ("orm", "arm", "occlusionroughnessmetallic")),
    ("ao", ("ao", "ambientocclusion", "occlusion")),
    ("displacement", ("displacement", "height", "disp")),
    ("metalness", ("metalness", "metallic", "metal")),
)
SKIP_WORDS = ("preview", "thumb", "thumbnail", "icon")
RESOLUTION = re.compile(r"^(?:\d+k|\d{3,5}(?:px)?|lod\d+)$")


class SurfaceError(Exception):
    pass


# Reading the surface --------------------------------------------------------------


def classify(filename):
    """The map kind a file name ends with, or None. Resolution and LOD tokens at the
    end (Albedo_2K, Normal_LOD0) are ignored."""
    stem, extension = os.path.splitext(os.path.basename(filename))
    if extension.lower() not in IMAGE_EXTENSIONS:
        return None
    tokens = [token for token in re.split(r"[_\-\s.]+", stem.lower()) if token]
    if any(word in tokens for word in SKIP_WORDS):
        return None
    while tokens and RESOLUTION.match(tokens[-1]):
        tokens.pop()
    if not tokens:
        return None
    for length in (3, 2, 1):
        if len(tokens) < length:
            continue
        ending = "".join(tokens[-length:])
        for kind, suffixes in MAP_SUFFIXES:
            if ending in suffixes:
                return kind
    return None


def _score_json(data):
    if not isinstance(data, dict):
        return -1
    keys = ("id", "name", "meta", "categories", "tags", "semanticTags", "physicalSize", "maps")
    return sum(1 for key in keys if key in data)


def find_metadata(files):
    """The Megascans JSON among the surface's files (the one that looks most like
    surface metadata). None when there is no JSON at all."""
    best, best_score = None, 0
    for path in sorted(files):
        if not path.lower().endswith(".json"):
            continue
        try:
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            continue
        score = _score_json(data)
        if score > best_score:
            best, best_score = (path, data), score
    return best


def _image_width(path):
    try:
        with Image.open(path) as image:
            return image.size[0]
    except OSError:
        return 0


def find_maps(files):
    """kind -> path. With several candidates for one kind (two resolutions, a JPG and a
    PNG), the smallest at least SIZE wide wins, else the largest."""
    candidates = {}
    for path in sorted(files):
        kind = classify(path)
        if kind:
            candidates.setdefault(kind, []).append(path)
    chosen = {}
    for kind, paths in candidates.items():
        sized = sorted(((_image_width(p), p) for p in paths), key=lambda item: (item[0], item[1]))
        big_enough = [item for item in sized if item[0] >= SIZE]
        chosen[kind] = (big_enough[0] if big_enough else sized[-1])[1]
    return chosen


def layout_of(files, metadata_path, metadata):
    """"bridge" for a Bridge export (<id>.json beside maps named <id>_...), else "fab".
    Only reported, the reading is the same for both."""
    asset_id = str((metadata or {}).get("id") or "")
    if metadata_path and asset_id:
        stem = os.path.splitext(os.path.basename(metadata_path))[0]
        if stem.lower() != asset_id.lower():
            return "fab"
        siblings = [f for f in files if os.path.dirname(f) == os.path.dirname(metadata_path) and classify(f)]
        if siblings and all(os.path.basename(f).lower().startswith(stem.lower() + "_") for f in siblings):
            return "bridge"
    return "fab"


class Surface:
    def __init__(self, root, files, metadata_path, metadata, maps):
        self.root = root
        self.files = files
        self.metadata_path = metadata_path
        self.metadata = metadata or {}
        self.maps = maps
        self.layout = layout_of(files, metadata_path, metadata)

    @property
    def asset_id(self):
        value = self.metadata.get("id") or self.metadata.get("assetId")
        return str(value) if value else None

    @property
    def name(self):
        return str(self.metadata.get("name") or self.asset_id or os.path.basename(self.root.rstrip(os.sep)))

    def words(self):
        """Lower-case words from the name, categories and tags, for guessing."""
        parts = [self.name]
        for key in ("categories", "tags"):
            value = self.metadata.get(key)
            if isinstance(value, list):
                parts.extend(str(item) for item in value)
        semantic = self.metadata.get("semanticTags")
        if isinstance(semantic, dict):
            parts.extend(str(item) for value in semantic.values() for item in (value if isinstance(value, list) else [value]))
        return " ".join(parts).lower()

    def found(self):
        return sorted(os.path.relpath(f, self.root) for f in self.files)


def list_files(folder):
    out = []
    for directory, _, names in os.walk(folder):
        for name in names:
            if name.startswith("._") or "__MACOSX" in directory:
                continue
            out.append(os.path.join(directory, name))
    return out


def read_surface(folder):
    files = list_files(folder)
    metadata = find_metadata(files)
    metadata_path, data = metadata if metadata else (None, None)
    return Surface(folder, files, metadata_path, data, find_maps(files))


class opened_source:
    """Context manager: a folder as is, or a zip extracted into a temporary directory in
    the system temp dir (outside the repository), removed on exit."""

    def __init__(self, path):
        self.path = path
        self.temp = None

    def __enter__(self):
        if os.path.isdir(self.path):
            return self.path
        if zipfile.is_zipfile(self.path):
            self.temp = tempfile.mkdtemp(prefix="megascans-")
            with zipfile.ZipFile(self.path) as archive:
                for member in archive.infolist():
                    base = os.path.realpath(self.temp)
                    target = os.path.realpath(os.path.join(self.temp, member.filename))
                    if target != base and not target.startswith(base + os.sep):
                        raise SurfaceError(f"unsafe path in the zip: {member.filename}")
                archive.extractall(self.temp)
            return self.temp
        raise SurfaceError(f"not a folder or a zip: {self.path}")

    def __exit__(self, *_):
        if self.temp:
            shutil.rmtree(self.temp, ignore_errors=True)


# Physical size and studs per tile -------------------------------------------------

UNITS = {"m": 1.0, "meter": 1.0, "meters": 1.0, "metre": 1.0, "metres": 1.0, "cm": 0.01, "mm": 0.001}
SIZE_TEXT = re.compile(
    r"(\d+(?:\.\d+)?)\s*(mm|cm|m)?\s*(?:x|\*|×|by)\s*(\d+(?:\.\d+)?)\s*(mm|cm|meters?|metres?|m)?",
    re.IGNORECASE,
)
SINGLE_TEXT = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*(mm|cm|meters?|metres?|m)?\s*$", re.IGNORECASE)
SIZE_KEYS = ("physicalSize", "physical_size", "scanArea", "scan_area", "size", "tileSize", "realWorldSize")


def _size_from_text(text):
    match = SIZE_TEXT.search(text)
    if match:
        unit = (match.group(4) or match.group(2) or "m").lower()
        scale = UNITS.get(unit, 1.0)
        return float(match.group(1)) * scale, float(match.group(3)) * scale
    match = SINGLE_TEXT.match(text)
    if match:
        scale = UNITS.get((match.group(2) or "m").lower(), 1.0)
        return float(match.group(1)) * scale, float(match.group(1)) * scale
    return None


def _size_from_value(value):
    if isinstance(value, (int, float)) and value > 0:
        return float(value), float(value)
    if isinstance(value, str):
        return _size_from_text(value)
    if isinstance(value, (list, tuple)) and len(value) >= 2 and all(isinstance(v, (int, float)) for v in value[:2]):
        return float(value[0]), float(value[1])
    if isinstance(value, dict):
        scale = UNITS.get(str(value.get("unit", "m")).lower(), 1.0)
        for wide, high in (("width", "height"), ("x", "y"), ("width", "length")):
            if isinstance(value.get(wide), (int, float)) and isinstance(value.get(high), (int, float)):
                return float(value[wide]) * scale, float(value[high]) * scale
        if "value" in value:
            return _size_from_value(value["value"])
    return None


def physical_size(metadata):
    """(width, height) in metres from the Megascans JSON, or None. Looks at a top level
    size key, then the "meta" list Bridge writes ({"key": "scanArea", "value": "2x2 m"})."""
    for key in SIZE_KEYS:
        if key in metadata:
            size = _size_from_value(metadata[key])
            if size:
                return size
    for item in metadata.get("meta") or []:
        if not isinstance(item, dict):
            continue
        label = f"{item.get('key', '')} {item.get('name', '')}".lower().replace(" ", "")
        if any(word in label for word in ("scanarea", "physicalsize", "size", "dimension")):
            size = _size_from_value(item.get("value"))
            if size:
                return size
    return None


def studs_per_metre(root):
    """The project's metre in studs (WorldMeshConfig: local METRE = 1 / 0.28)."""
    path = os.path.join(root, "src", "shared", "config", "WorldMeshConfig.luau")
    with open(path, encoding="utf-8") as handle:
        match = re.search(r"local\s+METRE\s*=\s*1\s*/\s*([0-9.]+)", handle.read())
    if not match:
        raise SurfaceError(f"no METRE constant in {path}")
    return 1.0 / float(match.group(1))


def studs_per_tile(metadata, per_metre, override=None):
    """StudsPerTile for one tile of the surface: its physical width in studs, rounded to
    0.01. A non-square scan uses its width (MaterialVariant tiles uniformly)."""
    if override is not None:
        if override <= 0:
            raise SurfaceError("--studs-per-tile must be positive")
        return round(float(override), 2)
    size = physical_size(metadata)
    if not size:
        raise SurfaceError("no physical size in the surface JSON; pass --studs-per-tile")
    return round(size[0] * per_metre, 2)


# Map processing -------------------------------------------------------------------


def srgb_to_linear(values):
    return np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(values):
    values = np.clip(values, 0.0, 1.0)
    return np.where(values <= 0.0031308, values * 12.92, 1.055 * values ** (1 / 2.4) - 0.055)


def _resized(image, size=SIZE):
    if image.size == (size, size):
        return image
    return image.resize((size, size), Image.LANCZOS)


def load_rgb(path, size=SIZE):
    """float32 RGB in 0..1 at size x size."""
    with Image.open(path) as image:
        if image.mode in ("I;16", "I;16B", "I;16L", "I", "F"):
            gray = load_gray(path, size)
            return np.repeat(gray[:, :, None], 3, axis=2)
        rgb = _resized(image.convert("RGB"), size)
        return np.asarray(rgb, dtype=np.float32) / 255.0


def load_gray(path, size=SIZE, channel=None):
    """float32 0..1 at size x size. 16-bit and float images keep their precision; an RGB
    image is read from one channel when given (0, 1, 2), else its red channel."""
    with Image.open(path) as image:
        if image.mode in ("I;16", "I;16B", "I;16L", "I"):
            data = np.asarray(image, dtype=np.float32)
            top = 65535.0 if data.max() > 255 else 255.0
            gray = Image.fromarray((data / top).astype(np.float32))
        elif image.mode == "F":
            data = np.asarray(image, dtype=np.float32)
            span = float(data.max() - data.min()) or 1.0
            gray = Image.fromarray(((data - data.min()) / span).astype(np.float32))
        else:
            rgb = image.convert("RGB")
            band = rgb.split()[channel if channel is not None else 0]
            gray = Image.fromarray(np.asarray(band, dtype=np.float32) / 255.0)
        if gray.size != (size, size):
            gray = gray.resize((size, size), Image.LANCZOS)
        return np.clip(np.asarray(gray, dtype=np.float32), 0.0, 1.0)


def ao_multiply(albedo, ao, strength):
    """Albedo (sRGB, 0..1) darkened by ambient occlusion in linear light:
    linear(albedo) * (1 - strength * (1 - ao)), back to sRGB. Strength 0 leaves the
    albedo as it was; 1 multiplies by the AO map in full."""
    if not 0.0 <= strength <= 1.0:
        raise SurfaceError("--ao-strength must be between 0 and 1")
    factor = 1.0 - strength * (1.0 - ao)
    return linear_to_srgb(srgb_to_linear(albedo) * factor[:, :, None])


def normal_vectors(rgb):
    return rgb * 2.0 - 1.0


def to_opengl(rgb, convention):
    """A normal map (RGB 0..1) in OpenGL convention (green up, +Y), which is what
    Roblox's NormalMap expects. DirectX maps (green down, the Unreal convention) get
    their green channel inverted. Vectors are renormalised either way."""
    vectors = normal_vectors(rgb)
    if convention == "directx":
        vectors[:, :, 1] = -vectors[:, :, 1]
    elif convention != "opengl":
        raise SurfaceError(f"unknown normal convention {convention}")
    length = np.linalg.norm(vectors, axis=2, keepdims=True)
    length[length == 0] = 1.0
    vectors = vectors / length
    vectors[:, :, 2] = np.maximum(vectors[:, :, 2], 0.0)
    return np.clip((vectors + 1.0) * 0.5, 0.0, 1.0)


def _correlation(a, b):
    a = a - a.mean()
    b = b - b.mean()
    denominator = float(np.sqrt((a * a).sum() * (b * b).sum()))
    return float((a * b).sum()) / denominator if denominator else 0.0


def detect_convention(normal_rgb, height, threshold=0.2):
    """"opengl", "directx" or None, from how the normal map's slopes line up with the
    height map. Rows run top to bottom, so in OpenGL convention the green channel
    follows the height's increase down the rows and in DirectX it follows the decrease;
    the red channel (the same in both) must follow the height's decrease along the
    columns, or the reading is not trusted."""
    small = 256
    if normal_rgb.shape[0] > small:
        step = normal_rgb.shape[0] // small
        normal_rgb = normal_rgb[::step, ::step]
        height = height[::step, ::step]
    vectors = normal_vectors(normal_rgb)
    down_rows = np.gradient(height, axis=0)
    along_columns = np.gradient(height, axis=1)
    red = _correlation(vectors[:, :, 0], -along_columns)
    green = _correlation(vectors[:, :, 1], down_rows)
    if red < threshold or abs(green) < threshold:
        return None
    return "opengl" if green > 0 else "directx"


def save_rgb(path, rgb):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(data).save(path)


def save_gray(path, gray):
    """Written as RGB with three equal channels, like the existing roughness maps."""
    save_rgb(path, np.repeat(np.clip(gray, 0.0, 1.0)[:, :, None], 3, axis=2))


def is_metal(base_material):
    return base_material in METAL_MATERIALS


def guess_base_material(surface):
    words = surface.words()
    for word, material in MATERIAL_HINTS:
        if word in words:
            return material
    return None


def require_maps(surface, metal):
    maps = surface.maps
    missing = []
    if "albedo" not in maps:
        missing.append("albedo (Albedo, BaseColor, Diffuse, Color)")
    if not any(kind in maps for kind in ("normal", "normal_gl", "normal_dx")):
        missing.append("normal (Normal, NormalGL, NormalDX)")
    if not any(kind in maps for kind in ("roughness", "gloss", "orm")):
        missing.append("roughness (Roughness, Gloss, ORM)")
    if missing:
        listing = "\n  ".join(surface.found()) or "(no files)"
        recognised = ", ".join(f"{kind}={os.path.basename(path)}" for kind, path in sorted(maps.items())) or "none"
        raise SurfaceError(
            f"{surface.name}: missing {'; '.join(missing)}.\n"
            f"Maps recognised: {recognised}.\nFiles found:\n  {listing}"
        )
    notes = []
    if metal and "metalness" not in maps and "orm" not in maps:
        notes.append("metal surface without a Metalness map: no metalness map written")
    if "ao" not in maps and "orm" not in maps:
        notes.append("no AO map: the colour map is the albedo as is")
    return notes


def pick_normal(surface, forced=None, height=None):
    """(path, convention, how) for the normal map. A name that says GL or DX wins;
    an unlabelled Normal is checked against the displacement map when there is one,
    else taken as OpenGL, the convention raw Megascans normals ship in (Unreal-format
    downloads are DirectX and are usually labelled). --normal-convention overrides."""
    maps = surface.maps
    if "normal_gl" in maps:
        path, convention, how = maps["normal_gl"], "opengl", "named GL"
    elif "normal_dx" in maps:
        path, convention, how = maps["normal_dx"], "directx", "named DX"
    else:
        path, convention, how = maps["normal"], "opengl", "unlabelled, OpenGL by default"
        if height is not None:
            detected = detect_convention(load_rgb(path, 256), _resize_gray(height, 256))
            if detected:
                convention, how = detected, "unlabelled, read from the displacement map"
    if forced:
        convention, how = forced, "--normal-convention"
    return path, convention, how


def _resize_gray(gray, size):
    if gray.shape[0] == size:
        return gray
    image = Image.fromarray(gray.astype(np.float32)).resize((size, size), Image.LANCZOS)
    return np.asarray(image, dtype=np.float32)


def process(surface, out_dir, slot, base_material, ao_strength=0.5, normal_convention=None):
    """Write <slot>_color/normal/roughness[/metalness].png into out_dir. Returns
    {"files": {suffix: path}, "normal": (convention, how), "notes": [...]}."""
    metal = is_metal(base_material)
    notes = require_maps(surface, metal)
    maps = surface.maps
    orm = maps.get("orm")

    if "ao" in maps:
        ao = load_gray(maps["ao"])
    elif orm:
        ao = load_gray(orm, channel=0)
    else:
        ao = np.ones((SIZE, SIZE), dtype=np.float32)
    color = ao_multiply(load_rgb(maps["albedo"]), ao, ao_strength)

    height = load_gray(maps["displacement"], 256) if "displacement" in maps else None
    normal_path, convention, how = pick_normal(surface, normal_convention, height)
    normal = to_opengl(load_rgb(normal_path), convention)

    if "roughness" in maps:
        roughness = load_gray(maps["roughness"])
    elif "gloss" in maps:
        roughness = 1.0 - load_gray(maps["gloss"])
    else:
        roughness = load_gray(orm, channel=1)

    files = {}
    for suffix, write, data in (
        ("color", save_rgb, color),
        ("normal", save_rgb, normal),
        ("roughness", save_gray, roughness),
    ):
        path = os.path.join(out_dir, f"{slot}_{suffix}.png")
        write(path, data)
        files[suffix] = path
    if metal and ("metalness" in maps or orm):
        metalness = load_gray(maps["metalness"]) if "metalness" in maps else load_gray(orm, channel=2)
        path = os.path.join(out_dir, f"{slot}_metalness.png")
        save_gray(path, metalness)
        files["metalness"] = path
    elif not metal and "metalness" in maps:
        notes.append(f"Metalness map ignored: {base_material} is not a metal base material")
    return {"files": files, "normal": (convention, how), "notes": notes}


# Manifest rows --------------------------------------------------------------------

SLOT = re.compile(r"^[a-z][a-z0-9_]*$")


def variant_name(slot):
    return VARIANT_PREFIX + "".join(part[:1].upper() + part[1:] for part in slot.split("_") if part)


def check_slot(slot):
    if not SLOT.match(slot):
        raise SurfaceError(f"slot {slot!r}: use lower case letters, digits and underscores, starting with a letter")
    return slot


def source_for(surface, given=None):
    if given:
        return given
    if surface.asset_id:
        return f"https://quixel.com/megascans/home?assetId={surface.asset_id}"
    return "Fab (Quixel Megascans), owner's library"


def manifest_rows(slot, surface, suffixes, material, ao_strength, normal, source=None):
    """The manifest rows for one imported surface: one per map, pending with id 0,
    the file under assets/fab/textures (gitignored). The colour row carries the
    MaterialVariant settings that sync_configs.py reads."""
    convention, _ = normal
    asset = surface.name + (f" ({surface.asset_id})" if surface.asset_id else "")
    rows = {}
    for suffix in suffixes:
        row = {
            "source": source_for(surface, source),
            "license": LICENCE,
            "file": f"{FAB_TEXTURES}/{slot}_{suffix}.png",
            "assetId": 0,
            "status": "pending",
            "note": f"Megascans surface {asset}, {suffix} map at {SIZE} px",
        }
        if suffix == "color":
            row["note"] += f", albedo times AO at strength {ao_strength:g}"
            row["material"] = material
        elif suffix == "normal":
            row["note"] += f", {'green flipped from DirectX' if convention == 'directx' else 'OpenGL as delivered'}"
        rows[f"{MANIFEST_PREFIX}{slot}_{suffix}"] = row
    return rows


def apply_rows(manifest, slot, rows, replace=False):
    """Put the rows in the manifest (in place). Existing rows for the slot are
    replaced only with replace=True when any of them already has an asset id, so a
    stray re-import cannot drop uploaded ids. Returns the keys removed."""
    prefix = f"{MANIFEST_PREFIX}{slot}_"
    existing = [key for key in manifest if key.startswith(prefix)]
    uploaded = [key for key in existing if manifest[key].get("assetId")]
    if uploaded and not replace:
        raise SurfaceError(
            f"{slot} is already uploaded ({', '.join(uploaded)}); pass --replace to import it again "
            "(the rows go back to pending and need a new upload)"
        )
    removed = [key for key in existing if key not in rows]
    for key in removed:
        del manifest[key]
    for key, row in rows.items():
        manifest[key] = row
    return removed
