import json,struct,numpy as np,sys
from PIL import Image
from render import render, look
def read_glb(p):
    b=open(p,'rb').read(); jl=struct.unpack_from('<I',b,12)[0]; g=json.loads(b[20:20+jl]); bin_=b[20+jl+8:]
    def acc(i,dt,w):
        a=g['accessors'][i]; v=g['bufferViews'][a['bufferView']]
        return np.frombuffer(bin_[v['byteOffset']:v['byteOffset']+v['byteLength']],dtype=dt).reshape(-1,w) if w>1 else np.frombuffer(bin_[v['byteOffset']:v['byteOffset']+v['byteLength']],dtype=dt)
    return acc(0,'<f4',3),acc(2,'<f4',2),acc(3,'<u4',1).reshape(-1,3)
rig=json.load(open('out/rig.json'))
ims=[]
for s in ('R','L'):
    e=rig['sides'][s]; tex=np.asarray(Image.open(f'out/Arm{s}_Color.png'))
    Ph,Uh,Fh=read_glb(f'out/Hand{s}.glb'); Pf,Uf,Ff=read_glb(f'out/Forearm{s}.glb')
    Ph=Ph+e['Hand']['center']
    R=np.array(e['foreRot']); Pf=(Pf+e['Forearm']['center'])@R.T+e['wrist']
    pos=np.vstack([Ph,Pf]); F=np.vstack([Fh,Ff+len(Ph)]); UV=np.vstack([Uh,Uf]); UV=UV.copy(); UV[:,1]=1-UV[:,1]
    for eye in ([1.2,1.0,2.2] if s=='R' else [-1.2,1.0,2.2], [0,3,0.01]):
        ims.append(render(pos,F,UV[F],[tex],np.zeros(len(F),int),look(np.array(eye),np.array([0,0,0.5])),ortho=1.1,size=(400,400)))
out=Image.new('RGB',(800,800)); [out.paste(im,((i%2)*400,(i//2)*400)) for i,im in enumerate(ims)]; out.save('/tmp/verify.png')
