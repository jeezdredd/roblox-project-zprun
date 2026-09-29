import struct, json, numpy as np
def load(n):
    b=open(n+'.bin','rb').read()
    tex,nv,nf=struct.unpack('<qII',b[:16])
    v=np.frombuffer(b[16:16+nv*10],dtype=np.dtype([('x','<i2'),('y','<i2'),('z','<i2'),('u','<u2'),('v','<u2')]))
    P=np.stack([v['x'],v['y'],v['z']],1)/4000.0
    UV=np.stack([v['u'],v['v']],1)/65535.0
    F=np.frombuffer(b[16+nv*10:],dtype='<u2').reshape(-1,3).astype(int)
    return tex,P.copy(),UV,F

def rot_to(a,b):
    a=a/np.linalg.norm(a); b=b/np.linalg.norm(b)
    v=np.cross(a,b); c=np.dot(a,b); s=np.linalg.norm(v)
    if s<1e-8: return np.eye(3)
    K=np.array([[0,-v[2],v[1]],[v[2],0,-v[0]],[-v[1],v[0],0]])
    return np.eye(3)+K+K@K*((1-c)/(s*s))

parts={}   # name -> (tex, P, UV, F)
joints=[]  # (name, part0, part1, pivot)

def split(tex,P,UV,F,param,cuts,names):
    # param per vertex; cuts ascending; segment k = param in [cuts[k-1], cuts[k])
    seg=np.searchsorted(cuts,param,side='right')
    out={}
    for k,nm in enumerate(names):
        mask=np.any(seg[F]==k,axis=1)   # triangles touching the segment (seam triangles go to both)
        out[nm]=(tex,P,UV,F[mask])
    return out

# head
tex,P,UV,F=load('Head'); parts['Head']=(tex,P,UV,F)
# torso: waist
tex,P,UV,F=load('Torso')
WAIST=3.15
zc=float(np.median(P[:,2]))
res=split(tex,P,UV,F,P[:,1],[WAIST],['LowerTorso','UpperTorso']); parts.update(res)
neckY=float(load('Head')[1][:,1].min())+0.08
joints.append(('Waist','LowerTorso','UpperTorso',[0.0,WAIST,zc]))
joints.append(('Neck','UpperTorso','Head',[0.0,neckY,zc]))

# arms
arm_info={}
for side,src in (('Left','LArm'),('Right','RArm')):
    tex,P,UV,F=load(src)
    sgn=-1 if side=='Left' else 1
    xs=P[:,0]*sgn  # outward distance
    inner=P[xs<=xs.min()+0.12].mean(0); outer=P[xs>=xs.max()-0.12].mean(0)
    d=outer-inner; L=np.linalg.norm(d); d/=L
    shoulder=inner.copy(); shoulder[0]=sgn*0.58  # joint sits inside the torso edge
    shoulder[1]=inner[1]+0.05
    R=rot_to(d,np.array([0,-1,0.0]))
    Q=(P-shoulder)@R.T+shoulder
    t=(shoulder[1]-Q[:,1])  # distance down from shoulder after hanging
    tmax=t.max()
    elbow=0.47*tmax; wrist=0.82*tmax
    res=split(tex,Q,UV,F,t,[elbow,wrist],[side+'UpperArm',side+'LowerArm',side+'Hand'])
    parts.update(res)
    def at(tt):
        sel=Q[np.abs(t-tt)<0.06]; c=sel.mean(0); return [float(c[0]),float(shoulder[1]-tt),float(c[2])]
    joints.append((side+'Shoulder','UpperTorso',side+'UpperArm',[float(shoulder[0]),float(shoulder[1]),float(shoulder[2])]))
    joints.append((side+'Elbow',side+'UpperArm',side+'LowerArm',at(elbow)))
    joints.append((side+'Wrist',side+'LowerArm',side+'Hand',at(wrist)))
    arm_info[side]=dict(len=L,angle=float(np.degrees(np.arccos(-d[1]))))

# legs
for side,src in (('Left','LLeg'),('Right','RLeg')):
    tex,P,UV,F=load(src)
    top=P[:,1].max()
    HIP=2.78; KNEE=1.45; ANKLE=0.36
    res=split(tex,P,UV,F,P[:,1],[ANKLE,KNEE],[side+'Foot',side+'LowerLeg',side+'UpperLeg'])
    parts.update(res)
    def ring(y):
        sel=P[np.abs(P[:,1]-y)<0.08]; c=sel.mean(0); return [float(c[0]),float(y),float(c[2])]
    hip=ring(2.55); hip[1]=HIP
    joints.append((side+'Hip','LowerTorso',side+'UpperLeg',hip))
    joints.append((side+'Knee',side+'UpperLeg',side+'LowerLeg',ring(KNEE)))
    joints.append((side+'Ankle',side+'LowerLeg',side+'Foot',ring(ANKLE+0.05)))

ROOT_Y=2.8
joints.insert(0,('Root','HumanoidRootPart','LowerTorso',[0.0,ROOT_Y,zc]))

def normals(P,F):
    N=np.zeros_like(P)
    fn=np.cross(P[F[:,1]]-P[F[:,0]],P[F[:,2]]-P[F[:,0]])
    for k in range(3): np.add.at(N,F[:,k],fn)
    n=np.linalg.norm(N,axis=1,keepdims=True); n[n==0]=1
    return N/n

def write_glb(path,P,N,UV,F):
    pos_bytes=P.astype('<f4').tobytes(); nrm_bytes=N.astype('<f4').tobytes(); uv_bytes=UV.astype('<f4').tobytes()
    idx_bytes=F.astype('<u4').tobytes()
    blobs=[pos_bytes,nrm_bytes,uv_bytes,idx_bytes]; offs=[]; cur=0
    for b in blobs: offs.append(cur); cur+=len(b)
    bin_chunk=b''.join(blobs)
    g={"asset":{"version":"2.0","generator":"tfz-zombie-split"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"name":"mesh"}],
       "meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"mode":4}]}],
       "buffers":[{"byteLength":len(bin_chunk)}],
       "bufferViews":[{"buffer":0,"byteOffset":offs[0],"byteLength":len(pos_bytes),"target":34962},{"buffer":0,"byteOffset":offs[1],"byteLength":len(nrm_bytes),"target":34962},{"buffer":0,"byteOffset":offs[2],"byteLength":len(uv_bytes),"target":34962},{"buffer":0,"byteOffset":offs[3],"byteLength":len(idx_bytes),"target":34963}],
       "accessors":[{"bufferView":0,"componentType":5126,"count":len(P),"type":"VEC3","min":P.min(0).tolist(),"max":P.max(0).tolist()},{"bufferView":1,"componentType":5126,"count":len(P),"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":len(P),"type":"VEC2"},{"bufferView":3,"componentType":5125,"count":int(F.size),"type":"SCALAR"}]}
    j=json.dumps(g,separators=(',',':')).encode()
    while len(j)%4: j+=b' '
    total=12+8+len(j)+8+len(bin_chunk)
    with open(path,'wb') as h:
        h.write(struct.pack('<III',0x46546C67,2,total)); h.write(struct.pack('<II',len(j),0x4E4F534A)); h.write(j)
        h.write(struct.pack('<II',len(bin_chunk),0x004E4942)); h.write(bin_chunk)

rig={"parts":{},"joints":[],"rootY":ROOT_Y,"arms":arm_info}
for nm,(tex,P,UV,F) in parts.items():
    used=np.unique(F); remap=-np.ones(len(P),int); remap[used]=np.arange(len(used))
    Pp=P[used]; UVp=UV[used]; Fp=remap[F]
    lo,hi=Pp.min(0),Pp.max(0); c=(lo+hi)/2
    Pc=Pp-c
    write_glb(f'out/{nm}.glb',Pc,normals(Pc,Fp),UVp,Fp)
    rig["parts"][nm]={"center":c.round(4).tolist(),"size":(hi-lo).round(4).tolist(),"texture":int(tex),"tris":int(len(Fp))}
for j in joints: rig["joints"].append({"name":j[0],"part0":j[1],"part1":j[2],"pivot":[round(x,4) for x in j[3]]})
json.dump(rig,open('out/rig.json','w'),indent=1)
for nm,p in rig["parts"].items(): print(nm,p['center'],p['size'],p['tris'])
for j in rig["joints"]: print(j)
print(arm_info)
