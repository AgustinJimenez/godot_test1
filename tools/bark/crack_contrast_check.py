"""Contrast along the detected thin cracks (3 px core minus a 7 to 15 px ring) in luminance, height, AO and roughness: photograph and bake.
Run after band_energy_check.py has baked E:/Temp/b_t.png and the maps (see that script)."""
import sys, cv2, numpy as np
sys.path.insert(0,'E:/repo/godot_projects/godot_test1/tools/bark')
import extract_features as ef
D='E:/repo/godot_projects/godot_test1/tools/bark/bark_downloads/rock_boulder_dry_'; N=1024
data=np.fromfile('E:/repo/godot_projects/godot_test1/systems/world_gen/boulder_cracks.bin',dtype=np.uint8).reshape(-1,6)
mask=np.zeros((N,N),np.uint8)
for r in data: mask[int(r[2])|(int(r[3])<<8),int(r[0])|(int(r[1])<<8)]=1
core=cv2.dilate(mask,np.ones((3,3),np.uint8))>0
ring=(cv2.dilate(mask,np.ones((15,15),np.uint8))>0)&~(cv2.dilate(mask,np.ones((7,7),np.uint8))>0)
ob=cv2.imread('E:/Temp/b_t.png',cv2.IMREAD_UNCHANGED).astype(np.float32)/255.0
ours={'luminance':ob[...,:3].mean(2),'height':ob[...,3]}
rs=lambda f:cv2.resize(cv2.imread(f,0),(N,N),interpolation=cv2.INTER_AREA).astype(np.float32)/255.0
ours['ambient occlusion']=rs('E:/Temp/m_t_1.png'); ours['roughness']=rs('E:/Temp/m_t_2.png')
ph={'luminance':cv2.resize(cv2.imread(D+'diff.jpg'),(N,N),interpolation=cv2.INTER_AREA).astype(np.float32).mean(2)/255.0,'height':ef.load(D+'disp.png'),'ambient occlusion':rs(D+'ao.jpg'),'roughness':rs(D+'rough.jpg')}
for k in ph:
    dp=ph[k][core].mean()-ph[k][ring].mean(); do=ours[k][core].mean()-ours[k][ring].mean()
    print('%-18s crack minus ring: photograph %+.4f  ours %+.4f'%(k,dp,do))
