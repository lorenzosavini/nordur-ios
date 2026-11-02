"""Slow Commons downloader: python -I dl.py <media_dir>. Videos via transcodes, photos via thumbs."""
import hashlib, urllib.parse, urllib.request, time, os, json, subprocess, sys
os.chdir(sys.argv[1])
UA = "NordurContent/1.0 (https://nordur.info; contact via website) python-urllib"
VID = [("v_strokkur", "Strokkur geyser eruption in Iceland.webm", "Alexander Grebenkov · CC BY 3.0"),
 ("v_horses", "Icelandic horses.webm", "Adon Metcalfe · CC BY 2.0"),
 ("v_windy", "Windy day at Reynisfjara beach in Iceland.webm", "Alexander Grebenkov · CC BY 3.0"),
 ("v_aurora", "Aurora-Iceland Northern Lights timelapse 2026-02-06.hd.webm", "G. Edward Johnson · CC BY 4.0"),
 ("v_aurora2", "002 Northern lights in the night sky over Mývatn in Iceland Video by Giles Laurent.webm", "Giles Laurent · CC BY-SA 4.0"),
 ("v_skoga", "Skógafoss waterfall in Iceland.webm", "Alexander Grebenkov · CC BY 3.0"),
 ("v_selja", "Seljalandsfoss waterfall in Iceland.webm", "Alexander Grebenkov · CC BY 3.0"),
 ("v_hotdog", "2022-0816 Reykjavik - Bæjarins Beztu Pylsur - hot dog prep.webm", "Bobak Ha'Eri · CC BY 3.0"),
 ("v_lagoon", "Blue Lagoon - iceland - 2018.webm", "Solitary Backpacker · CC BY 3.0"),
 ("v_godafoss", "201 Goðafoss in winter long exposure timelapse Video by Giles Laurent.webm", "Giles Laurent · CC BY-SA 4.0"),
 ("v_deildar", "Deildartunguhver hot spring in Iceland.webm", "Alexander Grebenkov · CC BY 3.0")]
F = [("p_ring", "Route 1 in Mýrdalshreppur municipality, Iceland, 20240720 0909 2856.jpg", 5728, "Jakub Hałun · CC BY 4.0"),
 ("p_ring2", "View of Route 1 and Reynisfjall mountain in Mýrdalshreppur municipality, Iceland, 20240719 1945 2815.jpg", 5296, "Jakub Hałun · CC BY 4.0"),
 ("p_rain", "It was a rainy day in Reykjavik (7864385996).jpg", 4940, "Helgi Halldórsson · CC BY-SA 2.0"),
 ("p_rain2", "Rainy Day Blues (3041712622).jpg", 2000, "cogdogblog · CC0"),
 ("p_drive", "Driving in Iceland can be challenging (40217475782).jpg", 4396, "Winniepix · CC BY 2.0"),
 ("p_blizzard", "Super Jeep vs. Blizzard! (16443721786).jpg", 4923, "sergejf · CC BY-SA 2.0"),
 ("p_snowroad", "Saturday Winter Afternoon on the Road from the Factory, Iceland - panoramio.jpg", 4224, "Petr Kraumann · CC BY 3.0"),
 ("p_icering", "Ice covered ringroad.jpg", 1312, "Debivort · CC BY-SA 3.0"),
 ("p_sheep", "Sheep crossing road in eastern Iceland, July 2019.jpg", 3568, "Alexander Grebenkov · CC BY 3.0"),
 ("p_sheep2", "Iceland - Sheep - Road Trip - Chordata - Mammalia (4889905981).jpg", 2816, "CGP Grey · CC BY 2.0"),
 ("p_midnight", "Fish Drying Racks in Midnight Sun.jpg", 8256, "Eric Kilby · CC BY-SA 2.0"),
 ("p_midnight2", "Curving Coast in Midnight Sun.jpg", 7048, "Eric Kilby · CC BY-SA 2.0"),
 ("p_hotspring", "Hot Spring Vigdisarhver and sign Iceland 2026-02-06 07-39-17.jpg", 8256, "G. Edward Johnson · CC BY 4.0"),
 ("p_skogacrowd", "Tourists in water clouds at Skógafoss.jpg", 3568, "Alexander Grebenkov · CC BY 3.0"),
 ("p_skogafog", "Skógafoss water fog.jpg", 3568, "Alexander Grebenkov · CC BY 3.0"),
 ("p_ok", "Okjökull glacier commemorative plaque on rock.jpg", 1873, "Dominic Boyer · CC BY-SA 4.0"),
 ("p_galga", "Galgahraun Aug. 2018 02.jpg", 2560, "Hornstrandir1 · CC BY-SA 4.0"),
 ("p_beer", "Cheers! (8156634061).jpg", 3168, "Christine Zenino · CC BY 2.0"),
 ("p_beer2", "Gull beer bottle (2797943732).jpg", 3465, "Didier Baertschiger · CC BY-SA 2.0"),
 ("p_sunrise", "Sunrise In Reykjavík (136704923).jpeg", 2048, "Cameron Pickett · CC BY 3.0"),
 ("p_winsun", "Winter Sun (372748374).jpg", 1200, "Axel Kristinsson · CC BY 2.0"),
 ("p_hotdog", "Bæjarins beztu pylsur, Reykjavík.JPG", 1600, "Wilhelm Thomas Fiege · CC BY-SA 3.0"),
 ("p_misty", "Misty landscape in Iceland (54779372576).jpg", 4327, "Thomas Heins · CC BY 4.0")]
def path(n):
    name = n.replace(" ", "_"); h = hashlib.md5(name.encode()).hexdigest(); return h, urllib.parse.quote(name)
meta = json.load(open("credits.json")) if os.path.exists("credits.json") else {}
def ok(p, mn): return os.path.exists(p) and os.path.getsize(p) > mn
for k, n, cr in VID:
    meta[k] = {"title": n, "credit": "Video: " + cr}; json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
    if ok(k + ".mp4", 100000): continue
    h, q = path(n)
    for mode in ("1080p.vp9.webm", "720p.vp9.webm", "1080p.webm", "720p.webm", "480p.vp9.webm"):
        url = f"https://upload.wikimedia.org/wikipedia/commons/transcoded/{h[0]}/{h[:2]}/{q}/{q}.{mode}"
        for t in range(3):
            r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-user_agent", UA, "-i", url, "-t", "60", "-an", "-c:v", "libx264", "-crf", "14", k + ".mp4"])
            if r.returncode == 0 and ok(k + ".mp4", 100000): print("ok", k, mode, flush=True); break
            print("err", k, mode, flush=True); time.sleep(30)
        if ok(k + ".mp4", 100000): break
    time.sleep(30)
for k, n, w, cr in F:
    meta[k] = {"title": n, "credit": "Photo: " + cr}; json.dump(meta, open("credits.json", "w"), ensure_ascii=False, indent=1)
    if ok(k + ".img", 1000): continue
    h, q = path(n)
    sizes = [s for s in (1920, 1280) if s < w] or [None]
    for t in range(8):
        sz = sizes[t % len(sizes)]
        url = (f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/{sz}px-{q}" if sz
               else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}")
        try: d = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=120).read(); open(k + ".img", "wb").write(d); print("ok", k, len(d), flush=True); break
        except Exception as e: print("err", k, str(e)[:50], flush=True); time.sleep(35)
    time.sleep(30)
print("ALL DONE")
