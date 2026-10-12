"""Merge a Unity Asset Store first-person weapon's per-clip FBX files into one GLB.

    Blender -b --factory-startup --python tools/fps_pack/kit_fbx_to_glb.py -- \
        <folder> <Weapon> <out.glb> [<albedo> [<normal>]]

The FPS Essentials Kit ships one FBX per clip (<Weapon>@<Clip>.FBX, exported from 3ds Max)
holding both arms, their two armatures, the weapon as object-animated rigid meshes and a
crowd of helpers, lights and a camera. This keeps the first clip's objects, removes lights,
cameras and helper spheres, re-binds any arm mesh Blender's importer left unbound (the
right arm: its vertices sit in another frame than its bones, so a similarity, reflection
allowed, is fitted between vertex-group centroids and bone midpoints and applied before
binding), stacks every clip as an NLA track named after it, adds an Idle track holding the
last frame of Draw, attaches the weapon textures and exports one GLB with one animation
per track. Run rigidify.py, rebind.py, strip_glb.py and gltf_anim.py bake on the result.
"""

import os
import re
import sys

import bmesh
import bpy
import numpy as np
from io_scene_fbx import parse_fbx
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
folder, weapon, out_path = args[0], args[1], args[2]
albedo = args[3] if len(args) > 3 else None
normal = args[4] if len(args) > 4 else None

SUFFIX = re.compile(r"\.\d{3}$")


def clean(name):
    return SUFFIX.sub("", name)


def clip_files():
    files = {}
    for name in sorted(os.listdir(folder)):
        match = re.match(rf"^{re.escape(weapon)}@(.+)\.fbx$", name, re.IGNORECASE)
        if match:
            files[re.sub(r"[^A-Za-z0-9]+", "", match.group(1).title())] = os.path.join(folder, name)
    return files


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False, use_anim=True)
    return [o for o in bpy.data.objects if o not in before]


def push_strip(obj, track_name, action, frame_from=None, frame_to=None):
    data = obj.animation_data or obj.animation_data_create()
    track = data.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, int(action.frame_range[0]), action)
    if frame_from is not None:
        strip.action_frame_start = frame_from
        strip.action_frame_end = frame_to
    return strip


def group_pairs(mesh, armature):
    world = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    src, dst = [], []
    for group in mesh.vertex_groups:
        bone = armature.data.bones.get(group.name)
        if bone is None:
            continue
        pts = [world[v.index] for v in mesh.data.vertices if any(e.group == group.index and e.weight > 0.6 for e in v.groups)]
        if len(pts) < 5:
            continue
        src.append(np.mean(np.array([tuple(p) for p in pts]), axis=0))
        dst.append(np.array(tuple(armature.matrix_world @ ((bone.head_local + bone.tail_local) / 2))))
    return np.array(src), np.array(dst)


def fit_similarity(src, dst):
    mu_s, mu_d = src.mean(0), dst.mean(0)
    cov = (dst - mu_d).T @ (src - mu_s) / len(src)
    u, s, vt = np.linalg.svd(cov)
    rot = u @ vt
    var = ((src - mu_s) ** 2).sum() / len(src)
    scale = s.sum() / var if var > 1e-12 else 1.0
    out = np.eye(4)
    out[:3, :3] = scale * rot
    out[:3, 3] = mu_d - scale * rot @ mu_s
    residual = float(np.sqrt((((src @ out[:3, :3].T) + out[:3, 3] - dst) ** 2).sum(1).mean()))
    return out, residual


def fbx_name(prop):
    return prop.split(b"\x00\x01")[0].decode("utf-8", "replace")


def fbx_matrix(values):
    arr = list(values)
    return Matrix([arr[0:4], arr[4:8], arr[8:12], arr[12:16]]).transposed()


def fbx_clusters(path, mesh_name):
    root, _ = parse_fbx.parse(path)
    objects = next(e for e in root.elems if e.id == b"Objects")
    connections = next(e for e in root.elems if e.id == b"Connections")
    by_uid = {e.props[0]: e for e in objects.elems if e.props}
    parent_of = {}
    children_of = {}
    for c in connections.elems:
        if c.id == b"C" and c.props[0] == b"OO":
            parent_of.setdefault(c.props[1], []).append(c.props[2])
            children_of.setdefault(c.props[2], []).append(c.props[1])
    model = next((uid for uid, e in by_uid.items() if e.id == b"Model" and fbx_name(e.props[1]) == mesh_name), None)
    geometry = next((uid for uid in children_of.get(model, []) if by_uid.get(uid) is not None and by_uid[uid].id == b"Geometry"), None)
    skin = next((uid for uid in children_of.get(geometry, []) if by_uid.get(uid) is not None and by_uid[uid].id == b"Deformer"), None)
    clusters = []
    for uid in children_of.get(skin, []):
        cluster = by_uid.get(uid)
        if cluster is None or cluster.id != b"Deformer":
            continue
        fields = {e.id: e.props[0] for e in cluster.elems if e.props}
        bone = next((fbx_name(by_uid[m].props[1]) for m in children_of.get(uid, []) if m in by_uid and by_uid[m].id == b"Model"), None)
        if bone is None or b"Indexes" not in fields:
            continue
        clusters.append((bone, list(fields[b"Indexes"]), list(fields[b"Weights"]), fbx_matrix(fields[b"Transform"]), fbx_matrix(fields[b"TransformLink"])))
    return clusters


def rebind_from_fbx(obj, owner, path):
    clusters = fbx_clusters(path, obj.name)
    if not clusters:
        return False
    mesh = obj.data
    total = [None] * len(mesh.vertices)
    weight_sum = [0.0] * len(mesh.vertices)
    for bone_name, indexes, weights, transform, link in clusters:
        bone = owner.data.bones.get(bone_name)
        if bone is None:
            continue
        loc, rot, _ = link.decompose()
        unscaled_link = Matrix.LocRotScale(loc, rot, None)
        carry = owner.matrix_world @ bone.matrix_local @ unscaled_link.inverted() @ transform
        for index, weight in zip(indexes, weights):
            if weight <= 0 or index >= len(mesh.vertices):
                continue
            moved = (carry @ mesh.vertices[index].co) * weight
            total[index] = moved if total[index] is None else total[index] + moved
            weight_sum[index] += weight
    for vertex, moved, weight in zip(mesh.vertices, total, weight_sum):
        if moved is not None and weight > 0:
            vertex.co = moved / weight
    print(f"FBXBIND {obj.name}: {len(clusters)} clusters")
    return True


def bind_unbound_meshes(path):
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or not obj.vertex_groups:
            continue
        if any(m.type == "ARMATURE" and m.object for m in obj.modifiers):
            continue
        groups = {g.name for g in obj.vertex_groups}
        owner = max(armatures, key=lambda a: len(groups & {b.name for b in a.data.bones}), default=None)
        if owner is None or not groups & {b.name for b in owner.data.bones}:
            continue
        mesh = obj.data
        if rebind_from_fbx(obj, owner, path):
            world = Matrix.Identity(4)
        else:
            src, dst = group_pairs(obj, owner)
            before = float(np.sqrt(((src - dst) ** 2).sum(1).mean()))
            fit, residual = fit_similarity(src, dst)
            print(f"FIT {obj.name}: mean offset {before:.3f} -> residual {residual:.3f} (det {np.linalg.det(fit[:3, :3]):+.3f})")
            world = Matrix([list(row) for row in fit]) @ obj.matrix_world
            mesh.transform(world)
        if world.to_3x3().determinant() < 0:
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(mesh)
            bm.free()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        for m in list(obj.modifiers):
            if m.type == "ARMATURE":
                obj.modifiers.remove(m)
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = owner
        print(f"BOUND {obj.name} -> {owner.name}")


bpy.ops.wm.read_factory_settings(use_empty=True)
clips = clip_files()
base_clip = "Draw" if "Draw" in clips else next(iter(clips))
for obj in import_fbx(clips[base_clip]):
    if obj.type in ("LIGHT", "CAMERA") or clean(obj.name).startswith("Sphere"):
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.context.scene.frame_set(0)
bind_unbound_meshes(clips[base_clip])
base = {clean(o.name): o for o in bpy.data.objects}

draw_actions = {}
for name, obj in base.items():
    data = obj.animation_data
    if data and data.action:
        data.action.use_fake_user = True
        draw_actions[name] = data.action
        push_strip(obj, base_clip, data.action)
        data.action = None
for name, action in draw_actions.items():
    end = int(action.frame_range[1])
    push_strip(base[name], "Idle", action, max(end - 1, int(action.frame_range[0])), end)

for clip, path in clips.items():
    if clip == base_clip:
        continue
    imported = import_fbx(path)
    for obj in imported:
        data = obj.animation_data
        target = base.get(clean(obj.name))
        if data and data.action and target is not None:
            data.action.use_fake_user = True
            push_strip(target, clip, data.action)
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)

if albedo:
    for obj in base.values():
        if obj.type != "MESH" or obj.name.startswith("#"):
            continue
        for slot in obj.material_slots:
            mat = slot.material
            if not mat or not mat.use_nodes:
                continue
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(albedo, check_existing=True)
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
            if normal:
                ntex = nodes.new("ShaderNodeTexImage")
                ntex.image = bpy.data.images.load(normal, check_existing=True)
                ntex.image.colorspace_settings.name = "Non-Color"
                nmap = nodes.new("ShaderNodeNormalMap")
                links.new(ntex.outputs["Color"], nmap.inputs["Color"])
                links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

for img in list(bpy.data.images):
    if img.filepath and not os.path.exists(bpy.path.abspath(img.filepath)):
        bpy.data.images.remove(img)

print("CLIPS", ["Idle"] + list(clips))
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,
    export_frame_step=1,
    export_skins=True,
    export_yup=True,
    export_lights=False,
    export_cameras=False,
    export_extras=False,
)
print("WROTE", out_path)
