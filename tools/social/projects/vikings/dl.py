import hashlib, urllib.parse, urllib.request, time, os, json
UA={"User-Agent":"NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
F=[("krohg","Christian Krohg - Leiv Eirikson discovering America - Google Art Project.jpg",6912,"Christian Krohg, 1893 · public domain"),
("erik","Eric the Red.png",339,"Arngrímur Jónsson, Gronlandia (1688) · public domain"),
("flatey","GKS 1005 fol., 0005v - 15.jpg",3651,"Flateyjarbók, 14th c. · public domain"),
("ship","Gokstad ship - IMG 9148.jpg",3264,"Photo: Daderot · public domain"),
("eiriks","The Ruin at Eriksstadir.jpg",4080,"Photo: AdAstraBoink · CC0"),
("columbus","Portrait of a Man, Said to be Christopher Columbus (born about 1446, died 1506) MET DT369.jpg",3064,"Sebastiano del Piombo, 1519 · public domain"),
("aster","L'Anse Aux Meadows, Newfoundland (ASTER).jpg",1639,"Image: NASA/METI/AIST/Japan Space Systems · public domain"),
("reenact","Authentic Viking recreation.jpg",2272,"Photo: Dylan Kereluk · CC BY 2.0"),
("longhouse","L'Anse aux Meadows, recreated long house.jpg",3840,"Photo: D. Gordon E. Robertson · CC BY-SA 3.0"),
("statue","Leif the Lucky (48994808056).jpg",5472,"Photo: Rob Oo · CC BY 2.0")]
meta={}
for k,n,w,cr in F:
    meta[k]=cr
    if os.path.exists(k+".img") and os.path.getsize(k+".img")>1000: continue
    name=n.replace(" ","_"); h=hashlib.md5(name.encode()).hexdigest(); q=urllib.parse.quote(name)
    url=(f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/{1920 if w > 1920 else 1280}px-{q}" if w > 1280   # originals get 429'd from cloud IPs: use standard thumb sizes
           else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}")
    if url.endswith(".png") and w>1920: url+=".png"
    for t in range(8):
        try: d=urllib.request.urlopen(urllib.request.Request(url,headers=UA),timeout=120).read(); open(k+".img","wb").write(d); print("ok",k,len(d),flush=True); break
        except Exception as e: print("err",k,str(e)[:50],flush=True); time.sleep(40)
    time.sleep(25)
json.dump(meta,open("credits.json","w"),ensure_ascii=False,indent=1)
