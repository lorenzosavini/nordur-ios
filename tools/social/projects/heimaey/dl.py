"""Download Commons media for the Heimaey 1973 reel into the cwd (slowly: Wikimedia rate-limits cloud IPs).
Usage: cd <work>/heimaey && python dl.py"""
import hashlib, urllib.parse, urllib.request, time, os, json, subprocess
UA = {"User-Agent": "NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"}
F = [  # key, Commons file, original width, on-screen credit
 ("town73", "The town of Vestmannaeyjar and the harbor during the eruption of Eldfell in 1973.jpg", 640, "Photo: Jack Lockwood, USGS, 1973 · Public domain"),
 ("simkin", "Вестманнаэйяр (вулкан).jpg", 640, "Photo: Tom Simkin, Smithsonian, 1973 · Public domain"),
 ("street", "Lava flow advances down a Heimaey street.jpg", 400, "Photo: Richard S. Williams, USGS, 1973 · Public domain"),
 ("ship", "Ship pumping seawater onto the forward margin of the Heimaey lava flow,.jpg", 400, "Photo: Sigurgeir Jónasson / USGS, 1973 · Public domain"),
 ("steam", "Steam rising from water-cooled lava flows, Heimaey.jpg", 500, "Photo: USGS, 1973 · Public domain"),
 ("fired", "Building fired by lava from Eldfell eruption in 1973.jpg", 1100, "Photo: Óskar Elías Björnsson, 1973 · CC BY 2.0"),
 ("buried", "Houses buried by ash from Edlfell.jpg", 364, "Photo: USGS, 1973 · Public domain"),
 ("thermo", "Cooling Lava of Volcanic Eruption on Heimaey in Iceland - 1973-08-20 2233 - NASA Nighttime Aerial Thermograph.jpg", 742, "NASA thermal image, 20 Aug 1973 · Public domain"),
 ("after", "The town of Vestmannaeyjar and the harbor after the eruption. Eldfell in 1973.jpg", 454, "Photo: Robin Holcomb, USGS, 1973 · Public domain"),
 ("ash74", "Vestmannaeyjar Vulkanasche 1.jpg", 10338, "Photo: Christian Bickel, 1974 · CC BY-SA 2.0 de"),
 ("museum", "Eldfell - museum of the eruption, house under the tefra.jpg", 4752, "Photo: Szilas · Public domain"),
 ("view", "View from the Eldfell towards SW; left in the foreground the smaller craters of the last eruption.jpg", 4752, "Photo: Szilas · Public domain"),
 ("twovol", "Heimaey with two volcanoes (9626349296).jpg", 1500, "Photo: Jasmin Engelhart (bekassine) · CC BY-SA 2.0"),
 ("today", "Heimaey in June 2024 43.jpg", 3060, "Photo: Hornstrandir1 · CC BY-SA 4.0"),
 ("harbour", "Puerto de Vestmannaeyjar, Heimaey, Islas Vestman, Suðurland, Islandia, 2014-08-17, DD 007.JPG", 5419, "Photo: Diego Delso · CC BY-SA 4.0"),
]
V = [("v_lava", "Basaltic lava flow eruption (early morning, 23 March 2021) (Geldingadalur Valley, Iceland) 3.webm", "720p.vp9.webm",
      "Lava footage: Geldingadalur 2021, James St. John · CC BY 2.0")]
def path(n):
    name = n.replace(" ", "_"); h = hashlib.md5(name.encode()).hexdigest(); return h, urllib.parse.quote(name)
def get(urls, out):
    for t in range(10):
        u = urls[t % len(urls)]
        try: d = urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=300).read(); open(out, "wb").write(d); print("ok", out, len(d), flush=True); return True
        except Exception as e: print("err", out, str(e)[:50], flush=True); time.sleep(40)
meta = json.load(open("credits.json")) if os.path.exists("credits.json") else {}
for k, n, w, cr in F:
    meta[k] = cr
    if os.path.exists(k + ".img") and os.path.getsize(k + ".img") > 1000: continue
    h, q = path(n); base = f"https://upload.wikimedia.org/wikipedia/commons"
    urls = ([f"{base}/thumb/{h[0]}/{h[:2]}/{q}/{1920 if w > 1920 else 1280}px-{q}"] if w > 1280 else [f"{base}/{h[0]}/{h[:2]}/{q}"])
    if 500 < w <= 1280: urls.append(f"{base}/thumb/{h[0]}/{h[:2]}/{q}/500px-{q}")       # standard thumb widths as fallback
    if 330 < w <= 500: urls.append(f"{base}/thumb/{h[0]}/{h[:2]}/{q}/330px-{q}")
    get(urls, k + ".img"); time.sleep(30)
for k, n, mode, cr in V:
    meta[k] = cr
    if os.path.exists(k + ".webm") and os.path.getsize(k + ".webm") > 100000: continue
    h, q = path(n); get([f"https://upload.wikimedia.org/wikipedia/commons/transcoded/{h[0]}/{h[:2]}/{q}/{q}.{mode}"], k + ".webm")
json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
