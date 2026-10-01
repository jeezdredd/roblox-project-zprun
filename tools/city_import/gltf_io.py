"""Minimal glTF 2.0 reading and writing for static scenes (tools/city_import).

Reads .glb and .gltf (external or data-URI buffers and images): the default scene's
node tree with world matrices, triangle primitives (POSITION, NORMAL, TEXCOORD_0,
indices), materials (metallic-roughness, normal map, alpha mode, double sided) and
their images. Skins, morph targets, animations, cameras, lights, extra UV sets and
vertex colours are not read; sparse accessors stop the run. numpy and Pillow only.
"""

import base64
import io
import json
import os
import struct

import numpy as np

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

COMPONENTS = {
    5120: (np.int8, 127.0),
    5121: (np.uint8, 255.0),
    5122: (np.int16, 32767.0),
    5123: (np.uint16, 65535.0),
    5125: (np.uint32, None),
    5126: (np.float32, None),
}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


class GltfError(Exception):
    pass


# Reading --------------------------------------------------------------------------


def _data_uri(uri):
    header, _, data = uri.partition(",")
    if ";base64" not in header:
        raise GltfError(f"unsupported data URI {header[:40]}")
    return base64.b64decode(data)


class Document:
    def __init__(self, doc, buffers, base_dir):
        self.doc = doc
        self.buffers = buffers
        self.base_dir = base_dir
        self.notes = []

    def view_bytes(self, index):
        view = self.doc["bufferViews"][index]
        data = self.buffers[view["buffer"]]
        start = view.get("byteOffset", 0)
        return data[start:start + view["byteLength"]], view.get("byteStride")

    def accessor(self, index):
        accessor = self.doc["accessors"][index]
        if "sparse" in accessor:
            raise GltfError(f"accessor {index} is sparse, which is not supported")
        dtype, scale = COMPONENTS[accessor["componentType"]]
        width = WIDTH[accessor["type"]]
        count = accessor["count"]
        if "bufferView" not in accessor:
            return np.zeros((count, width), dtype=np.float32)
        data, stride = self.view_bytes(accessor["bufferView"])
        offset = accessor.get("byteOffset", 0)
        item = np.dtype(dtype).itemsize
        if stride and stride != item * width:
            raw = np.frombuffer(data, dtype=np.uint8, count=stride * (count - 1) + item * width, offset=offset)
            rows = np.lib.stride_tricks.as_strided(raw, shape=(count, item * width), strides=(stride, 1))
            values = np.frombuffer(np.ascontiguousarray(rows).tobytes(), dtype=dtype).reshape(count, width)
        else:
            values = np.frombuffer(data, dtype=dtype, count=count * width, offset=offset).reshape(count, width)
        if accessor.get("normalized") and scale:
            return np.maximum(values.astype(np.float32) / scale, -1.0)
        return values

    def image_bytes(self, index):
        image = self.doc["images"][index]
        if "bufferView" in image:
            data, _ = self.view_bytes(image["bufferView"])
            return bytes(data), image.get("mimeType", "image/png")
        uri = image.get("uri", "")
        if uri.startswith("data:"):
            mime = uri[5:].split(";", 1)[0]
            return _data_uri(uri), mime
        path = os.path.join(self.base_dir, uri.replace("%20", " "))
        with open(path, "rb") as handle:
            data = handle.read()
        return data, "image/jpeg" if path.lower().endswith((".jpg", ".jpeg")) else "image/png"


def load(path):
    base_dir = os.path.dirname(os.path.abspath(path))
    with open(path, "rb") as handle:
        blob = handle.read()
    bin_chunk = None
    if blob[:4] == b"glTF":
        magic, version, _ = struct.unpack_from("<III", blob, 0)
        if magic != GLB_MAGIC or version != 2:
            raise GltfError(f"{path}: not a glTF 2.0 binary")
        offset = 12
        doc = None
        while offset < len(blob):
            length, kind = struct.unpack_from("<II", blob, offset)
            chunk = blob[offset + 8:offset + 8 + length]
            if kind == CHUNK_JSON:
                doc = json.loads(chunk.decode("utf-8"))
            elif kind == CHUNK_BIN:
                bin_chunk = chunk
            offset += 8 + length
        if doc is None:
            raise GltfError(f"{path}: no JSON chunk")
    else:
        doc = json.loads(blob.decode("utf-8"))
    buffers = []
    for buffer in doc.get("buffers", []):
        uri = buffer.get("uri")
        if uri is None:
            if bin_chunk is None:
                raise GltfError(f"{path}: buffer without data")
            buffers.append(bin_chunk)
        elif uri.startswith("data:"):
            buffers.append(_data_uri(uri))
        else:
            with open(os.path.join(base_dir, uri.replace("%20", " ")), "rb") as handle:
                buffers.append(handle.read())
    return Document(doc, buffers, base_dir)


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ], dtype=np.float64)


def local_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    rotation = quat_matrix(node.get("rotation", [0, 0, 0, 1]))
    scale = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    m[:3, :3] = rotation * scale[None, :]
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


def scene_nodes(doc):
    """(node index, world matrix) for every node of the default scene, depth first."""
    scenes = doc.get("scenes") or []
    if scenes:
        roots = scenes[doc.get("scene", 0)].get("nodes", [])
    else:
        children = {c for node in doc.get("nodes", []) for c in node.get("children", [])}
        roots = [i for i in range(len(doc.get("nodes", []))) if i not in children]
    out = []
    stack = [(index, np.eye(4)) for index in reversed(roots)]
    while stack:
        index, parent = stack.pop()
        node = doc["nodes"][index]
        world = parent @ local_matrix(node)
        out.append((index, world))
        for child in reversed(node.get("children", [])):
            stack.append((child, world))
    return out


class Piece:
    """One triangle primitive in world space."""

    def __init__(self, name, material, positions, normals, uvs, triangles):
        self.name = name
        self.material = material
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.triangles = triangles

    @property
    def bounds(self):
        used = self.positions[np.unique(self.triangles)]
        return used.min(axis=0), used.max(axis=0)


def face_normals(positions, triangles):
    a, b, c = (positions[triangles[:, i]] for i in range(3))
    return np.cross(b - a, c - a)


def vertex_normals(positions, triangles):
    normals = np.zeros_like(positions)
    faces = face_normals(positions, triangles)
    for corner in range(3):
        np.add.at(normals, triangles[:, corner], faces)
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    length[length == 0] = 1.0
    return normals / length


def pieces(document):
    """Every triangle primitive of the default scene as a Piece, in world space."""
    doc = document.doc
    out = []
    for index, world in scene_nodes(doc):
        node = doc["nodes"][index]
        if "mesh" not in node:
            continue
        if "skin" in node:
            document.notes.append(f"node {node.get('name', index)}: skinned, read in its bind pose")
        mesh = doc["meshes"][node["mesh"]]
        name = node.get("name") or mesh.get("name") or f"node{index}"
        linear = world[:3, :3]
        normal_matrix = np.linalg.inv(linear).T if abs(np.linalg.det(linear)) > 1e-12 else linear
        mirrored = np.linalg.det(linear) < 0
        for p_index, primitive in enumerate(mesh.get("primitives", [])):
            mode = primitive.get("mode", 4)
            if mode != 4:
                document.notes.append(f"{name}: primitive {p_index} mode {mode} skipped (triangles only)")
                continue
            attributes = primitive.get("attributes", {})
            if "POSITION" not in attributes:
                continue
            local = document.accessor(attributes["POSITION"]).astype(np.float64)
            positions = local @ linear.T + world[:3, 3]
            count = len(positions)
            if "indices" in primitive:
                triangles = document.accessor(primitive["indices"]).astype(np.int64).reshape(-1, 3)
            else:
                triangles = np.arange(count - count % 3, dtype=np.int64).reshape(-1, 3)
            if mirrored:
                triangles = triangles[:, [0, 2, 1]]
            if "NORMAL" in attributes:
                normals = document.accessor(attributes["NORMAL"]).astype(np.float64) @ normal_matrix.T
                length = np.linalg.norm(normals, axis=1, keepdims=True)
                length[length == 0] = 1.0
                normals = normals / length
            else:
                normals = vertex_normals(positions, triangles)
            if "TEXCOORD_0" in attributes:
                uvs = document.accessor(attributes["TEXCOORD_0"]).astype(np.float64)
            else:
                uvs = np.zeros((count, 2))
            if any(key.startswith("COLOR_") for key in attributes):
                document.notes.append(f"{name}: vertex colours dropped")
            label = name if len(mesh.get("primitives", [])) == 1 else f"{name}_{p_index}"
            out.append(Piece(label, primitive.get("material"), positions, normals, uvs, triangles))
    return out


# Writing --------------------------------------------------------------------------


class Writer:
    """Collects meshes, materials and images into one .glb."""

    def __init__(self, generator="tfz-city-import"):
        self.doc = {
            "asset": {"version": "2.0", "generator": generator},
            "scene": 0,
            "scenes": [{"nodes": []}],
            "nodes": [],
            "meshes": [],
            "materials": [],
            "textures": [],
            "images": [],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "accessors": [],
            "bufferViews": [],
            "buffers": [],
        }
        self.blob = bytearray()
        self.image_index = {}

    def _view(self, data, target=None):
        while len(self.blob) % 4:
            self.blob.append(0)
        view = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.blob.extend(data)
        self.doc["bufferViews"].append(view)
        return len(self.doc["bufferViews"]) - 1

    def _accessor(self, array, component, kind, target, bounds=False):
        view = self._view(np.ascontiguousarray(array).tobytes(), target)
        accessor = {"bufferView": view, "componentType": component, "count": int(len(array)), "type": kind}
        if bounds:
            accessor["min"] = [float(v) for v in array.min(axis=0)]
            accessor["max"] = [float(v) for v in array.max(axis=0)]
        self.doc["accessors"].append(accessor)
        return len(self.doc["accessors"]) - 1

    def image(self, key, data, mime):
        """One image per key (a cell reuses a texture across its meshes)."""
        if key in self.image_index:
            return self.image_index[key]
        view = self._view(data)
        self.doc["images"].append({"bufferView": view, "mimeType": mime, "name": str(key)})
        self.doc["textures"].append({"source": len(self.doc["images"]) - 1, "sampler": 0})
        index = len(self.doc["textures"]) - 1
        self.image_index[key] = index
        return index

    def material(self, material):
        self.doc["materials"].append(material)
        return len(self.doc["materials"]) - 1

    def mesh(self, name, positions, normals, uvs, triangles, material, translation):
        attributes = {
            "POSITION": self._accessor(positions.astype("<f4"), 5126, "VEC3", 34962, bounds=True),
            "NORMAL": self._accessor(normals.astype("<f4"), 5126, "VEC3", 34962),
            "TEXCOORD_0": self._accessor(uvs.astype("<f4"), 5126, "VEC2", 34962),
        }
        if len(positions) < 65536:
            indices = self._accessor(triangles.reshape(-1).astype("<u2"), 5123, "SCALAR", 34963)
        else:
            indices = self._accessor(triangles.reshape(-1).astype("<u4"), 5125, "SCALAR", 34963)
        primitive = {"attributes": attributes, "indices": indices, "mode": 4}
        if material is not None:
            primitive["material"] = material
        self.doc["meshes"].append({"name": name, "primitives": [primitive]})
        self.doc["nodes"].append({"name": name, "mesh": len(self.doc["meshes"]) - 1, "translation": [float(v) for v in translation]})
        self.doc["scenes"][0]["nodes"].append(len(self.doc["nodes"]) - 1)

    def save(self, path):
        doc = dict(self.doc)
        for key in ("materials", "textures", "images", "samplers"):
            if not doc[key]:
                del doc[key]
        if "textures" not in doc:
            doc.pop("samplers", None)
        while len(self.blob) % 4:
            self.blob.append(0)
        doc["buffers"] = [{"byteLength": len(self.blob)}]
        text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
        while len(text) % 4:
            text += b" "
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(struct.pack("<III", GLB_MAGIC, 2, 12 + 8 + len(text) + 8 + len(self.blob)))
            handle.write(struct.pack("<II", len(text), CHUNK_JSON))
            handle.write(text)
            handle.write(struct.pack("<II", len(self.blob), CHUNK_BIN))
            handle.write(bytes(self.blob))


def decode_image(data):
    from PIL import Image

    return Image.open(io.BytesIO(data))
