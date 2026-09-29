from arm import *
def P(b): return clusters[f'mixamorig:{b}']['TL'][:3,3]
def rot(axis, deg, pivot):
    axis=np.asarray(axis,float); axis=axis/np.linalg.norm(axis); t=np.radians(deg)
    K=np.array([[0,-axis[2],axis[1]],[axis[2],0,-axis[0]],[-axis[1],axis[0],0]])
    R=np.eye(3)+np.sin(t)*K+(1-np.cos(t))*K@K
    M=np.eye(4); M[:3,:3]=R; M[:3,3]=pivot-R@pivot; return M
def palm_normal(side):
    n=np.cross(P(f'{side}HandIndex1')-P(f'{side}HandPinky1'), P(f'{side}HandMiddle1')-P(f'{side}Hand'))
    n/=np.linalg.norm(n)
    return n if n[1]<0 else -n
def pose_side(side, curls, thumb, wrist=None):
    """curls: {finger:(a1,a2,a3)} degrees; thumb: dict(swing=, curl=(a1,a2,a3))
    wrist: optional 4x4 world rotation about the wrist applied to the hand and fingers
    returns deformation matrix per bone index (bind->posed), identity for others"""
    D=np.tile(np.eye(4),(len(BONES),1,1))
    n=palm_normal(side)
    for fing,angs in curls.items():
        acc=np.eye(4)
        for j in (1,2,3):
            b=f'{side}Hand{fing}{j}'
            d=P(f'{side}Hand{fing}{j+1}')-P(b); d/=np.linalg.norm(d)
            ax=np.cross(d,n)
            acc=acc@rot(ax,angs[j-1],P(b))
            D[BI['mixamorig:'+b]]=acc
            if j==3: D[BI[f'mixamorig:{side}Hand{fing}4']]=acc
    # thumb: swing about the palm normal toward the palm centre, then curl about its own bend axis
    acc=np.eye(4)
    for j in (1,2,3):
        b=f'{side}HandThumb{j}'
        d=P(f'{side}HandThumb{j+1}')-P(b); d/=np.linalg.norm(d)
        if j==1:
            for ax_name,deg in thumb.get('j1',[]):
                ax={'n':n,'d':d,'c':np.cross(d,n)}[ax_name]
                acc=acc@rot(ax,deg,P(b))
        else:
            acc=acc@rot(np.cross(d,n),thumb['curl'][j-2],P(b))
        D[BI['mixamorig:'+b]]=acc
        if j==3: D[BI[f'mixamorig:{side}HandThumb4']]=acc
    if wrist is not None:
        D[BI[f'mixamorig:{side}Hand']]=wrist
        for b in BONES:
            if b.startswith(f'mixamorig:{side}Hand') and b!=f'mixamorig:{side}Hand':
                D[BI[b]]=wrist@D[BI[b]]
    return D
def skin(D):
    # linear blend: v' = sum w_b D_b v
    Vh=np.c_[V,np.ones(len(V))]
    out=np.zeros((len(V),3))
    for b in range(len(BONES)):
        w=Wm[:,b]
        if not w.any(): continue
        m=w>0
        out[m]+=w[m,None]*(Vh[m]@D[b].T)[:,:3]
    rest=1-Wm.sum(1)
    out+=rest[:,None]*V
    return out
