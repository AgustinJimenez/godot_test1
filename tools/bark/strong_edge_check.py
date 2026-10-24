import sys, cv2, numpy as np
sys.path.insert(0,'E:/repo/godot_projects/godot_test1/tools/bark')
import extract_features as ef
photo=ef.load('E:/repo/godot_projects/godot_test1/tools/bark/bark_downloads/rock_boulder_dry_disp.png')
bake=cv2.imread('E:/Temp/b_t.png',cv2.IMREAD_UNCHANGED)[...,3].astype(np.float32)/255.0
g=lambda h:(lambda sm:np.hypot(cv2.Sobel(sm,cv2.CV_32F,1,0),cv2.Sobel(sm,cv2.CV_32F,0,1))/8.0)(cv2.GaussianBlur(h,(0,0),1.5))
gp,gb=g(photo),g(bake); strong=gp>np.percentile(gp,97)
a=gp[strong]-gp[strong].mean(); b=gb[strong]-gb[strong].mean()
print('strong edges: bake gradient %.0f%% of photo, edge-map correlation there %.2f ; whole-tile gradient 99th pct bake %.4f photo %.4f'%(100*gb[strong].mean()/gp[strong].mean(),(a*b).sum()/np.sqrt((a*a).sum()*(b*b).sum()),np.percentile(gb,99),np.percentile(gp,99)))
