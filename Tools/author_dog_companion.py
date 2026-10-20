"""Author companion clips on the two shipped Quaternius rigs (Python + numpy).

Run from the project root. Original geometry/animations remain byte-for-byte in
buffer 0. Generated buffer/accessors are replaced on rerun. Limb IK maintains
paw contact while the chest lowers; this does not repurpose the Death clip.
"""
import base64
import json
from pathlib import Path
import numpy as np

NAMES = ['Companion_LieDown', 'Companion_Sleep', 'Companion_Rise', 'Companion_Pet', 'Companion_Sniff',
         'Companion_Eat', 'Companion_Fed']

def rotation(q):
    x,y,z,w=q
    return np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w], [2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w], [2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])

def quat(m):
    # Stable conversion, including rotations close to pi.
    k=np.array([[m[0,0]-m[1,1]-m[2,2], m[0,1]+m[1,0], m[0,2]+m[2,0],m[2,1]-m[1,2]],
                [m[0,1]+m[1,0],m[1,1]-m[0,0]-m[2,2],m[1,2]+m[2,1],m[0,2]-m[2,0]],
                [m[0,2]+m[2,0],m[1,2]+m[2,1],m[2,2]-m[0,0]-m[1,1],m[1,0]-m[0,1]],
                [m[2,1]-m[1,2],m[0,2]-m[2,0],m[1,0]-m[0,1],np.trace(m)]])/3
    _,vectors=np.linalg.eigh(k);q=vectors[:,-1]
    return q if q[3]>=0 else -q

def axis_x(a):
    c,s=np.cos(a),np.sin(a)
    return np.array([[1,0,0],[0,c,-s],[0,s,c]])

def axis_y(a):
    c,s=np.cos(a),np.sin(a)
    return np.array([[c,0,s],[0,1,0],[-s,0,c]])

def axis_z(a):
    c,s=np.cos(a),np.sin(a)
    return np.array([[c,-s,0],[s,c,0],[0,0,1]])

def smooth(x):
    x=np.clip(x,0,1);return x*x*(3-2*x)

def aim(a,b):
    a=a/np.linalg.norm(a);b=b/np.linalg.norm(b);v=np.cross(a,b);c=np.dot(a,b)
    k=np.array([[0,-v[2],v[1]],[v[2],0,-v[0]],[-v[1],v[0],0]])
    return np.eye(3)+k+k@k/max(1e-8,1+c)

def elbow(start,end,l1,l2,backwards=True):
    # Bend in the sagittal plane, maintaining bone lengths.
    delta=end-start;dist=np.linalg.norm(delta);direction=delta/dist
    along=(l1*l1-l2*l2+dist*dist)/(2*dist)
    height=np.sqrt(max(0,l1*l1-along*along))
    side=np.array([0,direction[2],-direction[1]])
    if (side[2]>0)==backwards:side=-side
    return start+direction*along+side*height

class Rig:
    def __init__(self,path,reset_generated=True):
        self.path=path;self.d=json.loads(path.read_text());d=self.d
        old=d.get('extras',{}).get('companionAuthoring')
        if old and reset_generated:
            for key,count in old.items():d[key]=d[key][:count]
        self.counts={key:len(d[key]) for key in ['buffers','bufferViews','accessors','animations']}
        self.buffers=[base64.b64decode(b['uri'].split(',')[1]) for b in d['buffers']]
        self.nodes=d['nodes'];self.names={n.get('name'):i for i,n in enumerate(self.nodes)}
        self.parents={ch:i for i,n in enumerate(self.nodes) for ch in n.get('children',[])}
        self.t=np.array([n.get('translation',[0,0,0]) for n in self.nodes],float)
        self.q=np.array([n.get('rotation',[0,0,0,1]) for n in self.nodes],float)
        self.s=np.array([n.get('scale',[1,1,1]) for n in self.nodes],float)
        self.bind=self.world(self.t,self.q);self.original=self.vertices(self.t,self.q)
        self.floor=self.original[:,1].min();self.scale=.7/np.ptp(self.original,axis=0)[[0,2]].max()
        self.generated=bytearray()
    def acc(self,i):
        a=self.d['accessors'][i];v=self.d['bufferViews'][a['bufferView']];dt={5126:'<f4',5123:'<u2',5121:'u1',5125:'<u4'}[a['componentType']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];size=np.dtype(dt).itemsize
        return np.ndarray((a['count'],n),dtype=dt,buffer=self.buffers[v['buffer']],offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',n*size),size)).astype(float)
    def world(self,t,q):
        result={}
        def visit(i):
            if i in result:return result[i]
            m=np.eye(4);m[:3,:3]=rotation(q[i])@np.diag(self.s[i]);m[:3,3]=t[i]
            result[i]=visit(self.parents[i])@m if i in self.parents else m
            return result[i]
        for i in range(len(self.nodes)):visit(i)
        return result
    def vertices(self,t,q):
        w=self.world(t,q);out=[]
        for n in self.nodes:
            if 'mesh' not in n:continue
            for p in self.d['meshes'][n['mesh']]['primitives']:
                a=p['attributes'];pos=self.acc(a['POSITION']);p4=np.c_[pos,np.ones(len(pos))]
                skin=self.d['skins'][n['skin']];ib=self.acc(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
                mats=np.array([w[j]@inv for j,inv in zip(skin['joints'],ib)]);js=self.acc(a['JOINTS_0']).astype(int);ws=self.acc(a['WEIGHTS_0'])
                out.append(sum(np.einsum('nij,nj->ni',mats[js[:,k]],p4)*ws[:,k,None] for k in range(4))[:,:3])
        return np.concatenate(out)
    def pose(self,lower=0,head=0,breath=0,wag=0,tilt=0,skull=None,roll=0):
        t=self.t.copy();q=self.q.copy();idx=self.names
        def pos(name):return self.world(t,q)[idx[name]][:3,3]
        def orient(name,r):
            i=idx[name];p=self.world(t,q)[self.parents[i]][:3,:3]
            q[i]=quat(np.linalg.inv(p)@r)
        def point(name,end,bind_end):
            i=idx[name];origin=pos(name)
            orient(name,aim(bind_end-self.bind[i][:3,3],end-origin)@self.bind[i][:3,:3])
        body=idx['Body'];t[body,1]-=.96*lower;t[body,1]+=breath
        # Paws are separate weighted IK bones in these rigs: translate them along
        # the floor; articulated shoulder/elbow and hip/hock chains follow them.
        for side in ['L','R']:
            f=f'FrontUpperLeg.{side}';lo=f'FrontLowerLeg.{side}';foot=f'IKFrontLeg.{side}'
            a=pos(f);b=self.bind[idx[lo]][:3,3];c=self.bind[idx[foot]][:3,3].copy()
            c[2]+=.52*lower
            l1=np.linalg.norm(b-self.bind[idx[f]][:3,3]);l2=np.linalg.norm(self.bind[idx[foot]][:3,3]-b)
            joint=elbow(a,c,l1,l2)
            point(f,joint,b);point(lo,c,self.bind[idx[foot]][:3,3]);t[idx[foot]]+=c-self.bind[idx[foot]][:3,3]
            hip=f'BackLeg.{side}';knee=f'BackUpperLeg.{side}';hock=f'BackLowerLeg.{side}';foot=f'IKBackLeg.{side}'
            a=pos(hip);bk=self.bind[idx[knee]][:3,3];bh=self.bind[idx[hock]][:3,3];bf=self.bind[idx[foot]][:3,3]
            # Thigh folds forward; hock folds back beneath the haunch.
            direction=bk-self.bind[idx[hip]][:3,3]
            direction=axis_x(-.37*lower)@direction
            target=a+direction
            point(hip,target,bk)
            c=bf.copy();c[2]+=.20*lower
            joint=elbow(pos(knee),c,np.linalg.norm(bh-bk),np.linalg.norm(bf-bh))
            point(knee,joint,bh);point(hock,c,bf);t[idx[foot]]+=c-bf
        # Lower the neck after the chest settles, leaving a soft, attentive head.
        for name,angle in [('Neck1',1.40),('Neck2',.60)]:
            i=idx[name];orient(name,axis_x(angle*head)@self.world(t,q)[i][:3,:3])
        # Neck3 owns the skull AND both ear roots; Head is only the muzzle.
        # Counter-rotate the complete skull so lowering never folds the ears
        # through the forehead or stretches the face.
        i=idx['Neck3']
        orient('Neck3',axis_x(.22*head if skull is None else skull)@axis_y(tilt)@axis_z(roll)@self.bind[i][:3,:3])
        i=idx['Tail1'];orient('Tail1',axis_y(wag)@axis_x(-.65*lower)@self.bind[i][:3,:3])
        return t,q
    def accessor(self,values,typ):
        a=np.asarray(values,dtype='<f4');offset=len(self.generated);self.generated.extend(a.tobytes())
        view=len(self.d['bufferViews']);self.d['bufferViews'].append({'buffer':self.counts['buffers'],'byteOffset':offset,'byteLength':a.nbytes})
        out={'bufferView':view,'componentType':5126,'count':len(a),'type':typ}
        if typ=='SCALAR':out.update(min=[float(a.min())],max=[float(a.max())])
        i=len(self.d['accessors']);self.d['accessors'].append(out);return i
    def clip(self,name,duration,pose):
        times=np.linspace(0,duration,round(duration*24)+1);frames=[pose(float(t)) for t in times]
        timeAcc=self.accessor(times,'SCALAR');endsAcc=self.accessor([0,duration],'SCALAR');anim={'name':name,'channels':[],'samplers':[]}
        # Include every joint so no previous locomotion track remains active.
        joints=self.d['skins'][0]['joints']
        for i in joints:
            for path,k,typ in [('translation',0,'VEC3'),('rotation',1,'VEC4')]:
                vals=np.array([f[k][i] for f in frames])
                if k==1:
                    for j in range(1,len(vals)):
                        if np.dot(vals[j-1],vals[j])<0:vals[j]*=-1
                constant=np.max(np.abs(vals-vals[0])) < 1e-7
                sampler=len(anim['samplers']);anim['samplers'].append({'input':endsAcc if constant else timeAcc,'output':self.accessor(vals[[0,-1]] if constant else vals,typ),'interpolation':'LINEAR'})
                anim['channels'].append({'sampler':sampler,'target':{'node':i,'path':path}})
        self.d['animations'].append(anim)
        mins=np.array([self.vertices(*f)[:,1].min() for f in frames])
        print(self.path.stem,name,'lowest paw',round((mins.min()-self.floor)*self.scale,4),'height',round(np.ptp(self.vertices(*frames[-1]),axis=0)[1]*self.scale,3))
        assert mins.min()>=self.floor-.025, (name,mins.min())
    def save(self):
        self.d['buffers'].append({'byteLength':len(self.generated),'uri':'data:application/octet-stream;base64,'+base64.b64encode(self.generated).decode()})
        self.d.setdefault('extras',{})['companionAuthoring']=self.counts
        self.path.write_text(json.dumps(self.d,indent=4,separators=(',', ' : ')))

def author(r):
    def settle(t):return r.pose(lower=smooth(t/1.35),head=smooth((t-.8)/1.4))
    r.clip(NAMES[0],2.2,settle)
    r.clip(NAMES[1],4.8,lambda t:r.pose(1,1,breath=.009*(1-np.cos(2*np.pi*t/4.8))))
    r.clip(NAMES[2],1.8,lambda t:r.pose(lower=1-smooth((t-.35)/1.45),head=1-smooth(t/.9)))
    r.clip(NAMES[3],2.4,lambda t:r.pose(wag=.30*np.sin(t*2*np.pi*2.5)*np.sin(np.pi*t/2.4)**2,tilt=.13*np.sin(np.pi*t/2.4)**2))
    r.clip(NAMES[4],3.2,lambda t:r.pose(head=.80*np.sin(np.pi*t/3.2)**2,tilt=.10*np.sin(t*2*np.pi/1.6)*np.sin(np.pi*t/3.2)**2))
    def eating(t):
        # Keep the back and all four paws supporting the dog. Only a small
        # crouch and the neck bring the muzzle to the low bowl; no lying pose.
        engaged=smooth(t/.95)*(1-smooth((t-5.35)/1.05))
        chewing=np.sin(2*np.pi*3.1*t)*engaged
        crouch=.46 if r.path.stem == 'husky' else .38
        return r.pose(lower=crouch*engaged,head=1.35*engaged+.018*chewing,
                      skull=1.42*engaged+.025*chewing,
                      breath=.004*engaged*np.sin(2*np.pi*t/2.0),
                      wag=.055*engaged*np.sin(2*np.pi*1.4*t),
                      tilt=.018*engaged*np.sin(2*np.pi*t/1.6))
    r.clip(NAMES[5],6.4,eating)
    def fed(t):
        response=smooth(t/.30)*(1-smooth((t-2.25)/.55))
        return r.pose(wag=.48*np.sin(t*2*np.pi*2.5)*response,
                      tilt=.15*response,roll=.08*response,
                      breath=.012*np.sin(np.pi*t/2.8)**2)
    r.clip(NAMES[6],2.8,fed)
    r.save()

if __name__=='__main__':
    for name in ['shiba','husky']:author(Rig(Path('Pilire/Animals3D')/(name+'.gltf')))
