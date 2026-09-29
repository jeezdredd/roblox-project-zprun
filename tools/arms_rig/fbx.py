"""Minimal binary FBX 7.x reader."""
import struct, zlib
import numpy as np


class Node:
    __slots__ = ("name", "props", "children")

    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def findall(self, name):
        return [c for c in self.children if c.name == name]

    def __repr__(self):
        return f"<{self.name} {[p if not isinstance(p,(bytes,np.ndarray)) else type(p).__name__ for p in self.props][:4]} ({len(self.children)})>"


ARR = {b"f": ("<f4", 4), b"d": ("<f8", 8), b"l": ("<i8", 8), b"i": ("<i4", 4), b"b": ("?", 1)}


def _prop(buf, o):
    t = buf[o:o + 1]; o += 1
    if t == b"Y": return struct.unpack_from("<h", buf, o)[0], o + 2
    if t == b"C": return bool(buf[o]), o + 1
    if t == b"I": return struct.unpack_from("<i", buf, o)[0], o + 4
    if t == b"F": return struct.unpack_from("<f", buf, o)[0], o + 4
    if t == b"D": return struct.unpack_from("<d", buf, o)[0], o + 8
    if t == b"L": return struct.unpack_from("<q", buf, o)[0], o + 8
    if t in (b"S", b"R"):
        n = struct.unpack_from("<I", buf, o)[0]; o += 4
        v = bytes(buf[o:o + n]); o += n
        return (v.decode("utf-8", "replace") if t == b"S" else v), o
    if t in ARR:
        n, enc, clen = struct.unpack_from("<III", buf, o); o += 12
        raw = bytes(buf[o:o + clen]); o += clen
        if enc == 1: raw = zlib.decompress(raw)
        dt, _ = ARR[t]
        return np.frombuffer(raw, dtype=dt, count=n), o
    raise ValueError(f"bad prop type {t} at {o}")


def _node(buf, o, v64):
    if v64:
        end, nprops, plen = struct.unpack_from("<QQQ", buf, o); o += 24
    else:
        end, nprops, plen = struct.unpack_from("<III", buf, o); o += 12
    nlen = buf[o]; o += 1
    if end == 0:
        return None, o
    name = bytes(buf[o:o + nlen]).decode(); o += nlen
    props = []
    for _ in range(nprops):
        p, o = _prop(buf, o); props.append(p)
    children = []
    sentinel = 25 if v64 else 13
    while o < end:
        if end - o == sentinel and not any(buf[o:end]):
            o = end; break
        c, o = _node(buf, o, v64)
        if c is None: break
        children.append(c)
    return Node(name, props, children), end


def load(path):
    buf = memoryview(open(path, "rb").read())
    assert bytes(buf[:18]) == b"Kaydara FBX Binary"
    ver = struct.unpack_from("<I", buf, 23)[0]
    v64 = ver >= 7500
    o = 27
    top = []
    while o < len(buf) - 200:
        n, o = _node(buf, o, v64)
        if n is None: break
        top.append(n)
    return ver, Node("root", [], top)
