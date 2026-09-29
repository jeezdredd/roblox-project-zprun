"""Tiny numpy rasterizer for previews: textured, lambert-shaded, z-buffered."""
import numpy as np
from PIL import Image


def look(eye, target, up=(0, 1, 0)):
    eye, target, up = map(lambda a: np.asarray(a, float), (eye, target, up))
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, np.stack([r, u, -f])  # rows: camera axes


def render(pos, tris, uvs, texs, tex_of_tri, cam, fov=40, size=(640, 480), ortho=None, bg=(40, 44, 52)):
    """pos: (N,3) world verts, tris: (T,3) vertex idx, uvs: (T,3,2), texs: list of HxWx3 arrays."""
    W, H = size
    eye, R = cam
    pc = (pos - eye) @ R.T  # camera space, looking -Z
    z = -pc[:, 2]
    if ortho:
        sx = pc[:, 0] / ortho * (H / 2) + W / 2
        sy = -pc[:, 1] / ortho * (H / 2) + H / 2
    else:
        fpx = (H / 2) / np.tan(np.radians(fov) / 2)
        zz = np.maximum(z, 1e-3)
        sx = pc[:, 0] / zz * fpx + W / 2
        sy = -pc[:, 1] / zz * fpx + H / 2
    img = np.zeros((H, W, 3), float); img[:] = bg
    zb = np.full((H, W), np.inf)
    light = np.array([0.4, 0.8, 0.45]); light /= np.linalg.norm(light)
    wn = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
    wn /= np.linalg.norm(wn, axis=1, keepdims=True) + 1e-12
    for t in range(len(tris)):
        a, b, c = tris[t]
        if min(z[a], z[b], z[c]) <= 1e-3 and not ortho:
            continue
        xs = np.array([sx[a], sx[b], sx[c]]); ys = np.array([sy[a], sy[b], sy[c]])
        x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
        y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
        if x0 > x1 or y0 > y1:
            continue
        den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
        l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
        l2 = 1 - l0 - l1
        m = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not m.any():
            continue
        zz = l0 * z[a] + l1 * z[b] + l2 * z[c]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= zz < sub
        if not m.any():
            continue
        sub[m] = zz[m]
        tex = texs[tex_of_tri[t]]
        th, tw = tex.shape[:2]
        uv = l0[m, None] * uvs[t, 0] + l1[m, None] * uvs[t, 1] + l2[m, None] * uvs[t, 2]
        px = np.clip((uv[:, 0] % 1) * tw, 0, tw - 1).astype(int)
        py = np.clip((1 - uv[:, 1] % 1) * th, 0, th - 1).astype(int)
        col = tex[py, px, :3].astype(float)
        n = wn[t]
        view = eye - pos[a]
        if np.dot(n, view) < 0:
            n = -n
        shade = 0.45 + 0.55 * max(0.0, float(np.dot(n, light)))
        img[y0:y1 + 1, x0:x1 + 1][m] = col * shade
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
