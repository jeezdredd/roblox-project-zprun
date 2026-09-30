from pose import *
from render import *
def cylinder(center, axis, radius, length, seg=24):
    axis=np.asarray(axis,float); axis/=np.linalg.norm(axis)
    u=np.cross(axis,[0,1,0.3]); u/=np.linalg.norm(u); v=np.cross(axis,u)
    pts=[]; 
    for s in (-0.5,0.5):
        for k in range(seg):
            a=2*np.pi*k/seg; pts.append(center+axis*s*length+radius*(np.cos(a)*u+np.sin(a)*v))
    tris=[]
    for k in range(seg):
        a,b=k,(k+1)%seg; tris+= [(a,b,seg+a),(b,seg+b,seg+a)]
    return np.array(pts),np.array(tris)
def show(Vp, T, extra=None, dist=40, ortho=11, path='/tmp/pose.png', views=None):
    pos=Vp; tris=tri_v[T]; uvs=tri_uv[T]; tm=tri_mat[T]; tx=list(texs())+[np.full((4,4,3),150,np.uint8)]
    if extra is not None:
        ep,et=extra; off=len(pos); pos=np.vstack([pos,ep]); tris=np.vstack([tris,et+off])
        uvs=np.vstack([uvs,np.zeros((len(et),3,2))]); tm=np.r_[tm,np.full(len(et),2)]
    c=Vp[tri_v[T]].reshape(-1,3).mean(0)
    views=views or [[0,0,1],[0,-1,0.001],[-1,0,0],[0.6,0.6,0.6]]
    ims=[render(pos,tris,uvs,tx,tm,look(c+np.array(e)*dist,c),ortho=ortho,size=(400,400)) for e in views]
    out=Image.new('RGB',(800,800)); [out.paste(im,((i%2)*400,(i//2)*400)) for i,im in enumerate(ims)]; out.save(path)
