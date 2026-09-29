import json, struct, sys
from preview import *
from islands import uv_islands
from PIL import Image

STUDS_PER_CM = 0.041          # matches the M4A1 viewmodel: 3.25 studs for an ~80 cm rifle
ATLAS = 1024
MARGIN = 8

GRIPS = {
    # right hand on the pistol grip: index along the trigger, three fingers wrapped
    'Right': dict(curls={'Index': (20, 25, 15), 'Middle': (75, 85, 55), 'Ring': (78, 88, 55), 'Pinky': (80, 85, 55)},
                  thumb={'j1': [('d', -40), ('n', 25)], 'curl': (25, 30)}, radius=2.2, depth=3.2),
    # left hand under the handguard: all four fingers wrapped, a looser grip
    'Left': dict(curls={'Index': (50, 60, 40), 'Middle': (55, 65, 45), 'Ring': (58, 68, 45), 'Pinky': (60, 70, 45)},
                 thumb={'j1': [('d', 40), ('n', -20)], 'curl': (20, 25)}, radius=3.6, depth=4.4),
}

def _Rx(a):
    a = np.radians(a); c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def _Ry(a):
    a = np.radians(a); c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

# forearm relative to hand, in the forearm frame (same values ViewmodelConfig used to
# apply at runtime as ARM_WRIST_BEND)
# upper arm kept past the elbow: long enough that the cut end never enters the frame
ELBOW_EXTENSION_CM = 20.0

WRIST_BEND = {'Right': _Ry(28) @ _Rx(-1.6), 'Left': _Ry(-26)}

def frames(side):
    n = palm_normal(side)
    wrist = P(side + 'Hand'); elbow = P(side + 'ForeArm')
    fwd = P(side + 'HandMiddle1') - wrist; fwd /= np.linalg.norm(fwd)
    Z = -fwd; Y = -n - np.dot(-n, Z) * Z; Y /= np.linalg.norm(Y); X = np.cross(Y, Z)
    hand = np.stack([X, Y, Z])                     # rows: local axes in world
    fz = elbow - wrist; fz /= np.linalg.norm(fz)
    fy = Y - np.dot(Y, fz) * fz; fy /= np.linalg.norm(fy); fx = np.cross(fy, fz)
    fore = np.stack([fx, fy, fz])
    g = GRIPS[side]
    pc = (P(side + 'HandIndex1') + P(side + 'HandPinky1')) / 2 * 0.6 + wrist * 0.4
    grip = pc + n * g['depth']
    fr = dict(hand=hand, fore=fore, grip=grip, wrist=wrist, elbow=elbow, n=n)
    # Bake the wrist bend into the mesh: the hand turns about the wrist so that the
    # forearm sits at WRIST_BEND relative to it. With the bend in the geometry the hand
    # and forearm parts meet exactly at rest and no crack opens at the cuff.
    M = fore.T
    Rw = M @ np.linalg.inv(WRIST_BEND[side]) @ M.T
    W = np.eye(4); W[:3, :3] = Rw; W[:3, 3] = wrist - Rw @ wrist
    fr['W'] = W
    fr['hand'] = hand @ Rw.T
    fr['grip'] = Rw @ (grip - wrist) + wrist
    return fr

def select(side, fr):
    fore, hand = side_bones(side)
    upper = BI[f'mixamorig:{side}Arm']
    hsel = np.isin(dom, hand)
    fsel = np.isin(dom, fore + [upper])
    # clean cut ELBOW_EXTENSION_CM past the elbow, measured along the forearm axis
    t = (V - fr['wrist']) @ fr['fore'][2]
    limit = np.linalg.norm(fr["elbow"] - fr["wrist"]) + ELBOW_EXTENSION_CM
    fsel &= t <= limit
    Th = np.where(hsel[tri_v].sum(1) >= 2)[0]
    Tf = np.where((fsel[tri_v].sum(1) >= 2) & ~(hsel[tri_v].sum(1) >= 2) & (t[tri_v] <= limit).all(1))[0]
    return Th, Tf

def skin_normals(D):
    """per polygon-vertex normals rotated by the blended bone rotation"""
    R = np.einsum('vb,bij->vij', Wm, D[:, :3, :3])
    rest = 1 - Wm.sum(1)
    R += rest[:, None, None] * np.eye(3)
    pv_v = np.vectorize(vidx)(np.arange(len(PVI)))
    N = np.einsum('pij,pj->pi', R[pv_v], NRM)
    return N / (np.linalg.norm(N, axis=1, keepdims=True) + 1e-12)

def pack(rects, scale, size):
    """shelf packing; rects: list of (w,h) source px. returns positions or None"""
    order = sorted(range(len(rects)), key=lambda i: -rects[i][1])
    x = y = shelf = 0; pos = [None] * len(rects)
    for i in order:
        w = int(np.ceil(rects[i][0] * scale)) + 2; h = int(np.ceil(rects[i][1] * scale)) + 2
        if w > size: return None
        if x + w > size: x = 0; y += shelf; shelf = 0
        if y + h > size: return None
        pos[i] = (x + 1, y + 1); x += w; shelf = max(shelf, h)
    return pos

SRC = {}
def src(kind, mat):
    key = (kind, mat)
    if key not in SRC:
        im = Image.open(f'{TEX}/Ch15_100{mat + 1}_{kind}.png')
        if kind == 'Glossiness':
            im = Image.eval(im.convert('L'), lambda p: 255 - p)   # roughness = 1 - gloss
        SRC[key] = im.convert('RGB') if kind != 'Glossiness' else im
    return SRC[key]

def build_side(side, outdir):
    g = GRIPS[side]; fr = frames(side)
    D = pose_side(side, g['curls'], g['thumb'], fr['W'])
    Vp = skin(D); Np = skin_normals(D)
    Th, Tf = select(side, fr)
    T = np.r_[Th, Tf]
    S = 4096
    # --- atlas: one crop per (material, uv island)
    lab = np.zeros(len(T), dtype=np.int64)
    keys = []
    for mi in (0, 1):
        m = tri_mat[T] == mi
        if not m.any(): continue
        isl = uv_islands(UVI[tri_pv[T[m]]])
        for l in np.unique(isl):
            keys.append((mi, l)); lab[np.where(m)[0][isl == l]] = len(keys) - 1
    px = np.stack([tri_uv[T][..., 0] * S, (1 - tri_uv[T][..., 1]) * S], -1)  # (t,3,2) image px
    rects = []
    for k in range(len(keys)):
        p = px[lab == k].reshape(-1, 2)
        lo = np.floor(p.min(0)) - MARGIN; hi = np.ceil(p.max(0)) + MARGIN
        lo = np.clip(lo, 0, S); hi = np.clip(hi, 0, S)
        rects.append((lo, hi))
    sizes = [(hi - lo) for lo, hi in rects]
    lo_s, hi_s = 0.05, 1.0
    for _ in range(30):
        mid = (lo_s + hi_s) / 2
        if pack(sizes, mid, ATLAS): lo_s = mid
        else: hi_s = mid
    scale = lo_s; pos = pack(sizes, scale, ATLAS)
    atlases = {}
    for kind in ('Diffuse', 'Normal', 'Glossiness'):
        mode = 'L' if kind == 'Glossiness' else 'RGB'
        fill = 128 if kind == 'Glossiness' else ((128, 128, 255) if kind == 'Normal' else (60, 60, 60))
        at = Image.new(mode, (ATLAS, ATLAS), fill)
        for k, (mi, _) in enumerate(keys):
            lo, hi = rects[k]
            crop = src(kind, mi).crop((int(lo[0]), int(lo[1]), int(hi[0]), int(hi[1])))
            w = max(1, int(round((hi[0] - lo[0]) * scale))); h = max(1, int(round((hi[1] - lo[1]) * scale)))
            at.paste(crop.resize((w, h), Image.LANCZOS), pos[k])
        atlases[kind] = at
    newuv = np.zeros_like(px)
    for k in range(len(keys)):
        lo, _ = rects[k]; m = lab == k
        newuv[m] = ((px[m] - lo) * scale + np.array(pos[k])) / ATLAS
    # --- geometry per part, welded on (vertex, new uv)
    parts = {}
    for pname, TT, frame, origin in (('Hand', np.arange(len(Th)), fr['hand'], fr['grip']),
                                      ('Forearm', np.arange(len(Th), len(T)), fr['fore'], fr['wrist'])):
        corners_pv = tri_pv[T[TT]].reshape(-1)
        corners_uv = newuv[TT].reshape(-1, 2)
        key = np.c_[np.vectorize(vidx)(corners_pv), np.round(corners_uv * 65536)].astype(np.int64)
        uniq, inv = np.unique(key, axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        pos3 = Vp[uniq[:, 0]]
        uvs = np.zeros((len(uniq), 2)); uvs[inv] = corners_uv
        nrm = np.zeros((len(uniq), 3)); np.add.at(nrm, inv, Np[corners_pv])
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        F = inv.reshape(-1, 3)
        # into the part's local frame, studs
        loc = (pos3 - origin) @ frame.T * STUDS_PER_CM
        nl = nrm @ frame.T
        lo3, hi3 = loc.min(0), loc.max(0); c = (lo3 + hi3) / 2
        parts[pname] = dict(P=loc - c, N=nl, UV=uvs, F=F, center=c, size=hi3 - lo3)
    # hand->forearm relation: forearm origin (wrist) and rotation, expressed in the hand frame
    wrist_in_hand = (fr['wrist'] - fr['grip']) @ fr['hand'].T * STUDS_PER_CM
    fore_rot_in_hand = fr['hand'] @ fr['fore'].T   # columns: forearm axes in hand frame
    return parts, atlases, dict(scale=scale, wrist=wrist_in_hand, foreRot=fore_rot_in_hand)

def write_glb(path, Pp, N, UV, F):
    blobs = [Pp.astype('<f4').tobytes(), N.astype('<f4').tobytes(), UV.astype('<f4').tobytes(), F.astype('<u4').tobytes()]
    offs = np.cumsum([0] + [len(b) for b in blobs])[:-1]
    bin_chunk = b''.join(blobs)
    g = {"asset": {"version": "2.0", "generator": "tfz-arms"}, "scene": 0, "scenes": [{"nodes": [0]}],
         "nodes": [{"mesh": 0, "name": "mesh"}],
         "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "mode": 4}]}],
         "buffers": [{"byteLength": len(bin_chunk)}],
         "bufferViews": [{"buffer": 0, "byteOffset": int(offs[i]), "byteLength": len(blobs[i]), "target": 34963 if i == 3 else 34962} for i in range(4)],
         "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(Pp), "type": "VEC3", "min": Pp.min(0).tolist(), "max": Pp.max(0).tolist()},
                       {"bufferView": 1, "componentType": 5126, "count": len(Pp), "type": "VEC3"},
                       {"bufferView": 2, "componentType": 5126, "count": len(Pp), "type": "VEC2"},
                       {"bufferView": 3, "componentType": 5125, "count": int(F.size), "type": "SCALAR"}]}
    j = json.dumps(g, separators=(',', ':')).encode()
    while len(j) % 4: j += b' '
    with open(path, 'wb') as h:
        h.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(bin_chunk)))
        h.write(struct.pack('<II', len(j), 0x4E4F534A)); h.write(j)
        h.write(struct.pack('<II', len(bin_chunk), 0x004E4942)); h.write(bin_chunk)

if __name__ == '__main__':
    import os
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    rig = {"studsPerCm": STUDS_PER_CM, "sides": {}}
    for side in ('Right', 'Left'):
        s = 'R' if side == 'Right' else 'L'
        parts, at, info = build_side(side, out)
        at['Diffuse'].save(f'{out}/Arm{s}_Color.png', optimize=True)
        at['Normal'].save(f'{out}/Arm{s}_Normal.png', optimize=True)
        at['Glossiness'].save(f'{out}/Arm{s}_Roughness.png', optimize=True)
        entry = {}
        for pn, p in parts.items():
            write_glb(f'{out}/{pn}{s}.glb', p['P'], p['N'], p['UV'], p['F'])
            entry[pn] = {"center": p['center'].round(4).tolist(), "size": p['size'].round(4).tolist(), "tris": int(len(p['F']))}
        entry["wrist"] = info['wrist'].round(4).tolist()
        entry["foreRot"] = info['foreRot'].round(5).tolist()
        rig["sides"][s] = entry
    json.dump(rig, open(f'{out}/rig.json', 'w'), indent=1)
    print(json.dumps(rig)[:1500])
