import hashlib, urllib.parse, urllib.request, time, os
UA={"User-Agent":"NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
F=[("silfra1","SCUBA Silfra.jpg",2448),("bridge","Bridge Between Continents Iceland Travel Photography (132467725).jpeg",1200),("silfra4","Silfra tectonic plates landscape.jpg",12122)]
for k,n,w in F:
    if os.path.exists(k+".jpg"): continue
    name=n.replace(" ","_"); h=hashlib.md5(name.encode()).hexdigest(); q=urllib.parse.quote(name)
    url=f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/1280px-{q}" if w>1280 else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}"
    for t in range(6):
        time.sleep(45)
        try: d=urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=120).read(); open(k+".jpg","wb").write(d); print("ok",k,flush=True); break
        except Exception as e: print("err",k,str(e)[:60],flush=True)
