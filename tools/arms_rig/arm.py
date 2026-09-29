from load import *
from PIL import Image
import numpy as np
BONES=list(clusters)
BI={b:i for i,b in enumerate(BONES)}
Wm=np.zeros((len(V),len(BONES)))
for b,c in clusters.items(): Wm[c['idx'],BI[b]]=c['w']
Wm/=Wm.sum(1,keepdims=True)+1e-12
dom=Wm.argmax(1)
# triangulate (fan) keeping polygon-vertex indices
tri_pv=[]; tri_mat=[]
for i,p in enumerate(polys):
    for j in range(1,len(p)-1):
        tri_pv.append((p[0],p[j],p[j+1])); tri_mat.append(MAT[i])
tri_pv=np.array(tri_pv); tri_mat=np.array(tri_mat)
tri_v=np.vectorize(vidx)(tri_pv)
tri_uv=UV[UVI[tri_pv]]
_tex={}
def texs(size=1024):
    if size not in _tex:
        _tex[size]=[np.asarray(Image.open(f'{TEX}/Ch15_100{k}_Diffuse.png').resize((size,size))) for k in (1,2)]
    return _tex[size]
def side_bones(side):  # side 'Right'/'Left'
    fore=[BI[f'mixamorig:{side}ForeArm']]
    hand=[BI[b] for b in BONES if b.startswith(f'mixamorig:{side}Hand')]
    return fore,hand
