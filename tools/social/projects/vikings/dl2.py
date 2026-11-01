import hashlib, urllib.parse, urllib.request, time, os
UA={"User-Agent":"NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
import subprocess
# The Viking (1928, public domain) is 90 min / 420 MB: fetch only the 12 s we use (horned-helmet crew, ~39:56) via ranged reads.
U28 = "https://upload.wikimedia.org/wikipedia/commons/transcoded/a/ab/The_Viking_%281928%29.webm/The_Viking_%281928%29.webm.360p.mpeg4.mov"
if not os.path.exists("v_viking1928.mp4"):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-user_agent", UA["User-Agent"], "-ss", "2396", "-i", U28, "-t", "12", "-an", "-c:v", "libx264", "-crf", "14", "v_viking1928.mp4"])
F=[("v_ice","GreenlandReel Icebergs 2160APR.webm","1080p.vp9.webm"),("v_svea","Sailing Svea sailing among iceberg in Greenland magical landscape..webm","1080p.vp9.webm")]
for k,n,mode in F:
    if os.path.exists(k+".webm") and os.path.getsize(k+".webm")>100000: continue
    name=n.replace(" ","_"); h=hashlib.md5(name.encode()).hexdigest(); q=urllib.parse.quote(name)
    url=f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}" if mode=="orig" else f"https://upload.wikimedia.org/wikipedia/commons/transcoded/{h[0]}/{h[:2]}/{q}/{q}.{mode}"
    for t in range(8):
        try: d=urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=600).read(); open(k+".webm","wb").write(d); print("ok",k,len(d),flush=True); break
        except Exception as e: print("err",k,str(e)[:50],flush=True); time.sleep(45)
    time.sleep(25)
