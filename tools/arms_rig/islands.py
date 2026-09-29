import numpy as np
def uv_islands(tri_uvidx):
    """union-find on UV-index connectivity; tri_uvidx (T,3) -> island label per tri"""
    parent={}
    def f(x):
        while parent.setdefault(x,x)!=x:
            parent[x]=parent[parent[x]]; x=parent[x]
        return x
    for a,b,c in tri_uvidx:
        ra,rb,rc=f(a),f(b),f(c); parent[rb]=ra; parent[f(c)]=ra
    return np.array([f(t[0]) for t in tri_uvidx])
