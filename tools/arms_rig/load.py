import os
import fbx, numpy as np
HERE=os.path.dirname(os.path.abspath(__file__))
ROOT=os.path.dirname(os.path.dirname(HERE))
P=os.environ.get('ARMS_FBX', os.path.join(ROOT,'assets','viewmodels','arms','source','swat_guy.fbx'))
TEX=os.path.join(HERE,'tex')   # embedded maps are unpacked here on first run (git-ignored)
ver,R=fbx.load(P)
O=R.find('Objects'); C=R.find('Connections')
objs={c.props[0]:c for c in O.children}
conns=[(c.props[0],c.props[1],c.props[2],c.props[3] if len(c.props)>3 else None) for c in C.children]
def name(n): return n.props[1].split('\x00')[0]
def p70(n):
    d={}
    P=n.find('Properties70')
    if P:
        for p in P.children: d[p.props[0]]=p.props[4:]
    return d
kids={}; parents={}
for t,a,b,pn in conns:
    kids.setdefault(b,[]).append((a,pn)); parents.setdefault(a,[]).append((b,pn))
geo=[o for o in objs.values() if o.name=='Geometry'][0]
V=geo.find('Vertices').props[0].reshape(-1,3).astype(np.float64)
PVI=geo.find('PolygonVertexIndex').props[0]
uvl=geo.find('LayerElementUV'); UV=uvl.find('UV').props[0].reshape(-1,2); UVI=uvl.find('UVIndex').props[0]
NRM=geo.find('LayerElementNormal').find('Normals').props[0].reshape(-1,3)
MAT=geo.find('LayerElementMaterial').find('Materials').props[0]
# polygons
polys=[]; start=0
for i,v in enumerate(PVI):
    if v<0:
        polys.append(list(range(start,i+1))); start=i+1
def vidx(k): v=PVI[k]; return v if v>=0 else ~v
# skin
clusters={}
for oid,o in objs.items():
    if o.name=='Deformer' and o.props[2]=='Cluster':
        bone=[objs[p] for p,_ in kids.get(oid,[]) if p in objs and objs[p].name=='Model']
        idx=o.find('Indexes'); w=o.find('Weights')
        clusters[name(bone[0])]=dict(idx=idx.props[0] if idx else np.zeros(0,int), w=w.props[0] if w else np.zeros(0),
            T=o.find('Transform').props[0].reshape(4,4).T, TL=o.find('TransformLink').props[0].reshape(4,4).T)
bonemodel={name(o):(oid,o) for oid,o in objs.items() if o.name=='Model' and o.props[2]=='LimbNode'}
boneparent={}
for n,(oid,o) in bonemodel.items():
    for p,_ in parents.get(oid,[]):
        if p in objs and objs[p].name=='Model' and objs[p].props[2]=='LimbNode': boneparent[n]=name(objs[p])

os.makedirs(TEX, exist_ok=True)
for _o in objs.values():
    if _o.name=='Video':
        _fn=os.path.join(TEX,_o.find('RelativeFilename').props[0].split('/')[-1])
        if not os.path.exists(_fn): open(_fn,'wb').write(_o.find('Content').props[0])
