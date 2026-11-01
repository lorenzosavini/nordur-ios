"""Download Commons media for the Yule Lads reel into the cwd (slowly: Wikimedia rate-limits cloud IPs)."""
import hashlib, urllib.parse, urllib.request, time, os, json
UA = {"User-Agent": "NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
F = [("yulecat", "Gato de Yule em Reykjavík.jpg", 3024, "Photo: Christine Rondeau · CC BY 2.0"),
     ("laufa", "Various laufabrauð designs.jpg", 3854, "Photo: Surya Mjöll · CC BY 4.0"),
     ("cave", "Cave in Dimmuborgir lava field, Iceland, 20240716 1319 1478.jpg", 6056, "Photo: Jakub Hałun · CC BY 4.0"),
     ("kirkjan", "Kirkjan, Dimmuborgir, Iceland, 20240716 1309 1443.jpg", 3814, "Photo: Jakub Hałun · CC BY 4.0"),
     ("dimm", "Dimmuborgir lava field, Iceland, 20240716 1314 1462.jpg", 6000, "Photo: Jakub Hałun · CC BY 4.0"),
     ("lads", "Yule lads in Akureyri.jpg", 1513, "Photo: Lusinemarg · CC BY-SA 4.0"),
     ("odinstorg", "Odinstorg Reykjavik Dec 2020.jpg", 4160, "Photo: Akigka · CC BY-SA 4.0"),
     ("hallgrims", "Hallgrímskirkja - Last Christmas (3160371678).jpg", 4061, "Photo: Helgi Halldórsson · CC BY-SA 2.0"),
     ("house", "Christmas House (3083516200).jpg", 4272, "Photo: Helgi Halldórsson · CC BY-SA 2.0"),
     ("dec2014", "Iceland December 2014 (15383968363).jpg", 5966, "Photo: Bryan Ledgard · CC BY 2.0")]
meta = json.load(open("credits.json")) if os.path.exists("credits.json") else {}
for k, n, w, cr in F:
    meta[k] = cr
    if os.path.exists(k + ".img") and os.path.getsize(k + ".img") > 1000: continue
    name = n.replace(" ", "_"); h = hashlib.md5(name.encode()).hexdigest(); q = urllib.parse.quote(name)
    url = (f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/{1920 if w > 1920 else 1280}px-{q}" if w > 1280   # originals get 429'd from cloud IPs: use standard thumb sizes
           else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}")
    for t in range(8):
        try: d = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read(); open(k + ".img", "wb").write(d); print("ok", k, len(d), flush=True); break
        except Exception as e: print("err", k, str(e)[:50], flush=True); time.sleep(40)
    time.sleep(30)
json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
