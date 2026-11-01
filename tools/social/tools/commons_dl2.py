import hashlib, json, os, sys, time, urllib.request, urllib.parse
UA = {"User-Agent": "NordurContent/1.0 (https://nordur.info; content research)"}
OUT = sys.argv[1]; meta_p = os.path.join(OUT, "meta.json"); meta = json.load(open(meta_p))
PICKS = [l.split(" | ") for l in open(sys.argv[2]).read().strip().split("\n")]
for key, title, w, lic, artist in PICKS:
    name = title.replace("File:", "").replace(" ", "_"); h = hashlib.md5(name.encode()).hexdigest()
    q = urllib.parse.quote(name)
    url = (f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/1920px-{q}" if int(w) > 1920
           else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}")
    if url.lower().endswith((".png",)) is False and int(w) > 1600 and not q.lower().endswith((".jpg", ".jpeg")): url += ".jpg"
    p = os.path.join(OUT, key + ".jpg")
    for t in range(5):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
            open(p, "wb").write(data); break
        except Exception as e: print("retry", key, e); time.sleep(4)
    meta[key] = {"title": title, "credit": f"Photo: {artist} · {lic}", "page": "https://commons.wikimedia.org/wiki/" + q}
    print("ok", key, os.path.getsize(p) if os.path.exists(p) else 0); time.sleep(3)
json.dump(meta, open(meta_p, "w"), ensure_ascii=False, indent=1)
