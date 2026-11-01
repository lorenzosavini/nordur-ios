"""Download Commons media for the Reynisfjara reel into the cwd (slowly: Wikimedia rate-limits cloud IPs)."""
import hashlib, urllib.parse, urllib.request, time, os, json, subprocess
UA = {"User-Agent": "NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
F = [("waves", "Waves crashing on rocks at Reynisfjara beach (16469631985).jpg", 3975, "Photo: sergejf · CC BY-SA 2.0"),
     ("surf", "Reynisfjara-08-Brandung-2018-gje.jpg", 5184, "Photo: Gerd Eichmann · CC BY 4.0"),
     ("hazsys", "Reynisfjara Beach Hazard System.jpg", 1698, "Photo: Strwiki2017 · CC BY-SA 4.0"),
     ("hazsign", "Reynisfjara Beach Hazards Sign.jpg", 1890, "Photo: Strwiki2017 · CC BY-SA 4.0"),
     ("warning", "Reynisfjara warning.jpg", 4032, "Photo: Codas · CC BY-SA 4.0"),
     ("basalt", "Columnar basalts at Reynisfjara, Iceland.jpg", 4928, "Photo: Olga Ernst · CC BY-SA 4.0"),
     ("cave", "Cave Hálsanefshellir at Reynisfjara, Iceland.jpg", 4928, "Photo: Olga Ernst · CC BY-SA 4.0"),
     ("stacks", "Reynisdrangar Sea Stacks at Reynisfjara Beach.jpg", 6017, "Photo: Redido964 · CC0"),
     ("winter", "Winter Waves (Unsplash).jpg", 5472, "Photo: Tim Trad · CC0"),
     ("winds", "Winds at Reynisfjara (16283740927).jpg", 3264, "Photo: sergejf · CC BY-SA 2.0"),
     ("beach19", "Reynisfjara 2019.jpg", 3264, "Photo: Steven Lek · CC BY-SA 4.0"),
     ("lowsun", "Low Sun and Black Sand.jpg", 7228, "Photo: Eric Kilby · CC BY-SA 2.0"),
     ("froad", "Fjallabaksleið nyrðri(F208)13(js).jpg", 7952, "Photo: Jerzy Strzelecki · CC BY-SA 4.0"),
     ("sheep", "Sheep crossing road in eastern Iceland, July 2019.jpg", 3568, "Photo: Alexander Grebenkov · CC BY 3.0"),
     ("ring", "Route 1 in Mýrdalshreppur municipality, Iceland, 20240720 0909 2856.jpg", 5728, "Photo: Jakub Hałun · CC BY 4.0"),
     ("ring2", "View of Route 1 and Reynisfjall mountain in Mýrdalshreppur municipality, Iceland, 20240719 1945 2815.jpg", 5296, "Photo: Jakub Hałun · CC BY 4.0")]
VID = [("v_windy", "Windy day at Reynisfjara beach in Iceland.webm", "Video: Alexander Grebenkov · CC BY 3.0")]
def path(n):
    name = n.replace(" ", "_"); h = hashlib.md5(name.encode()).hexdigest(); return h, urllib.parse.quote(name)
meta = json.load(open("credits.json")) if os.path.exists("credits.json") else {}
for k, n, cr in VID:
    meta[k] = cr
    if os.path.exists(k + ".mp4") and os.path.getsize(k + ".mp4") > 100000: continue
    h, q = path(n)
    for mode in ("1080p.vp9.webm", "720p.vp9.webm", "720p.webm"):
        url = f"https://upload.wikimedia.org/wikipedia/commons/transcoded/{h[0]}/{h[:2]}/{q}/{q}.{mode}"
        for t in range(4):
            r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-user_agent", UA["User-Agent"], "-i", url, "-t", "40", "-an", "-c:v", "libx264", "-crf", "14", k + ".mp4"])
            if r.returncode == 0 and os.path.getsize(k + ".mp4") > 100000: print("ok", k, mode, flush=True); break
            print("err", k, mode, flush=True); time.sleep(40)
        if os.path.exists(k + ".mp4") and os.path.getsize(k + ".mp4") > 100000: break
    time.sleep(30)
for k, n, w, cr in F:
    meta[k] = cr
    if os.path.exists(k + ".img") and os.path.getsize(k + ".img") > 1000: continue
    h, q = path(n)
    sizes = [s for s in (1920, 1280, 960) if s < w] or [None]
    for t in range(9):
        sz = sizes[t % len(sizes)]                       # rotate standard thumb widths: some are cached, some get 429'd
        url = (f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/{sz}px-{q}" if sz
               else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}")
        try: d = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read(); open(k + ".img", "wb").write(d); print("ok", k, len(d), flush=True); break
        except Exception as e: print("err", k, str(e)[:50], flush=True); time.sleep(40)
    json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
    time.sleep(30)
json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
