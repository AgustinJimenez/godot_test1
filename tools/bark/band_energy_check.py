"""How much of the photograph's detail the boulder bake has at each size of feature (radially averaged power spectrum, ours as a percent
of the photograph's) for colour, height and the normal map, plus the kurtosis (peakiness) of the band-passed detail. 100 % is a match.
Bakes through square_compare with optional --param overrides:  python band_energy_check.py '{"fine_cm": 0.6}'"""
import sys, subprocess, cv2, numpy as np
from scipy.stats import kurtosis
sys.path.insert(0,'E:/repo/godot_projects/godot_test1/tools/bark')
import extract_features as ef
G="E:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"; P="E:/repo/godot_projects/godot_test1"; D=P+'/tools/bark/bark_downloads/rock_boulder_dry_'
rs=lambda x:cv2.resize(x,(1024,1024),interpolation=cv2.INTER_AREA).astype(np.float32)/255.0
ph_col=rs(cv2.imread(D+'diff.jpg')); ph_h=ef.load(D+'disp.png'); ph_n=rs(cv2.imread(D+'nor_gl.jpg'))[...,2]
def spectrum(x):
    x=x-x.mean(); win=np.outer(np.hanning(1024),np.hanning(1024)); F=np.abs(np.fft.fftshift(np.fft.fft2(x*win)))**2
    y,xx=np.indices(F.shape); r=np.hypot(y-512,xx-512).astype(int)
    return np.bincount(r.ravel(),F.ravel())/np.maximum(np.bincount(r.ravel()),1)
bands=[(16,32,'5.6-11'),(32,64,'2.8-5.6'),(64,128,'1.4-2.8'),(128,256,'0.7-1.4'),(256,512,'0.35-0.7')]
def run(params,tag):
    args=[G,"--path",P,"res://tests/manual/world/square_compare.tscn","--","--surface=9","--shot=E:/Temp/x.png","--save-bake=E:/Temp/b_%s.png"%tag,"--save-maps=E:/Temp/m_%s"%tag]+["--param=%s:%g"%kv for kv in params.items()]
    subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=200)
    ob=cv2.imread('E:/Temp/b_%s.png'%tag,cv2.IMREAD_UNCHANGED).astype(np.float32)/255.0
    on=rs(cv2.imread('E:/Temp/m_%s_0.png'%tag))[...,2]
    out=[]
    for name,a,b in (('colour',ph_col.mean(2),ob[...,:3].mean(2)),('height',ph_h,ob[...,3]),('normal',ph_n,on)):
        sa,sb=spectrum(a),spectrum(b)
        out.append('%s: '%name+' '.join('%s cm %3.0f%%'%(lab,100*sb[lo:hi].sum()/sa[lo:hi].sum()) for lo,hi,lab in bands))
    g=lambda x,sg:cv2.GaussianBlur(x,(0,0),sg)
    kp=[];ko=[]
    for sg in (1.0,2.0,4.0):
        a=ph_col.mean(2); b=ob[...,:3].mean(2); kp.append(kurtosis((g(a,sg)-g(a,2*sg)).ravel())); ko.append(kurtosis((g(b,sg)-g(b,2*sg)).ravel()))
        a=ph_h; b=ob[...,3]; kp.append(kurtosis((g(a,sg)-g(a,2*sg)).ravel())); ko.append(kurtosis((g(b,sg)-g(b,2*sg)).ravel()))
    out.append('kurtosis (photo | ours) colour 1/2/4px: %.1f/%.1f/%.1f | %.1f/%.1f/%.1f   height 1/2/4px: %.1f/%.1f/%.1f | %.1f/%.1f/%.1f'%(kp[0],kp[2],kp[4],ko[0],ko[2],ko[4],kp[1],kp[3],kp[5],ko[1],ko[3],ko[5]))
    return out
if __name__=='__main__':
    import json
    params=json.loads(sys.argv[1]) if len(sys.argv)>1 else {}
    for line in run(params,'t'): print(line)
