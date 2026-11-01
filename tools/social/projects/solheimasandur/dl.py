"""Media for the Sólheimasandur reel (sol_reel.py) → <work>/sol/. All Wikimedia Commons, free licences.
Commons rate-limits cloud IPs hard (HTTP 429 'robot policy' even on thumbnails): this tries upload.wikimedia.org
slowly; if every request 429s, fetch the printed URLs with WebFetch and copy the saved binaries to <key>.jpg.
Map: python -c "import geo,paper,numpy as np; e,o=geo.dem(-23.2,63.15,-13.6,65.1,9); ..." (see README) → map.png +
map_origin.json {"z":9,"x0":o[0],"y0":o[1]}, papercut with rift3's DARK_LAND/DARK_SEA, hill=0.2.
Usage: python dl.py <work>/sol"""
import hashlib, urllib.parse, urllib.request, subprocess, time, os, sys
UA = {"User-Agent": "NordurContent/1.0 (https://nordur.info; content research)"}
F = [  # key, Commons file, thumb width (None = original), credit
 ("ce", "Solheimasandur Plane Wreck (Unsplash SIczJ91He3c).jpg", 1280, "Christoffer Engström · CC0"),
 ("aj", "Sólheimasandur, Iceland (Unsplash).jpg", 1280, "Anders Jildén · CC0"),
 ("fuji", "R4D-8 VR-23 over Mt Fuji 1952.jpg", None, "US Navy (Naval Aviation News, Sept 1952) · Public domain"),
 ("stok", "Stokksnes - Hofn Air Station.jpg", 1280, "Syrio · CC BY-SA 4.0"),
 ("kef62", "Aerial view of the U.S. Naval Air Station Keflavik, Iceland, in 1962.jpg", None, "US Navy · Public domain"),
 ("r1820", "R-1820 engine of C-117D MCAS Iwakuni 1982.JPEG", 1280, "Cpl. L.G. Gyorfi, USMC · Public domain"),
 ("jh72", "Sólheimasandur, Iceland, 20240720 1204 2972.jpg", 1280, "Jakub Hałun · CC BY 4.0"),
 ("bf", "A broken plane on the floor (Unsplash).jpg", 1280, "Blair Fraser · CC0"),
 ("ch19", "CH-19E from NAS Keflavik off Iceland c1965.jpg", None, "US Navy (All Hands, July 1965) · Public domain"),
 ("jh47", "Douglas C-117 at Sólheimasandur, Iceland, 20240720 1151 2947.jpg", 1280, "Jakub Hałun · CC BY 4.0"),
 ("jh60", "Douglas C-117 at Sólheimasandur, Iceland, 20240720 1154 2960.jpg", 1280, "Jakub Hałun · CC BY 4.0"),
 ("sk59", "Sólheimasandur Plane Wreck, South Iceland (26145906759).jpg", 1280, "sikeri · CC BY 2.0"),
 ("hd161", "Sólheimasandur Iceland hdsr 2019 10 21 9999 161.jpg", 1280, "Hyppolyte de Saint-Rambert · CC BY-SA 4.0"),
 ("jh63", "Douglas C-117 at Sólheimasandur, Iceland, 20240720 1155 2963.jpg", 1280, "Jakub Hałun · CC BY 4.0"),
 ("jh69", "Douglas C-117 at Sólheimasandur, Iceland, 20240720 1202 2969.jpg", 1280, "Jakub Hałun · CC BY 4.0")]
VID = [("v_c47", "MJK 48271 Rosinenbomber 70 Jahre Berliner Luftbrücke (Flugplatz Wiesbaden-Erbenheim).webm", "Martin Kraft · CC BY 4.0"),
       ("v_storm", "Zamiec sniezna o wschodzie slonca na Babiej Gorze 20230304 063545.webm", "Jakub Hałun · CC BY-SA 4.0")]
def path(n): n = n.replace(" ", "_"); h = hashlib.md5(n.encode()).hexdigest(); return h, urllib.parse.quote(n)
if __name__ == "__main__":
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for k, n, cr in VID:
        h, q = path(n); p = os.path.join(out, k + ".mp4")
        if not os.path.exists(p):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-user_agent", UA["User-Agent"], "-i", f"https://upload.wikimedia.org/wikipedia/commons/transcoded/{h[0]}/{h[:2]}/{q}/{q}.1080p.vp9.webm", "-an", "-c:v", "libx264", "-crf", "14", p]); time.sleep(30)
    for k, n, w, cr in F:
        p = os.path.join(out, k + ".jpg")
        if os.path.exists(p): continue
        h, q = path(n); url = f"https://upload.wikimedia.org/wikipedia/commons/thumb/{h[0]}/{h[:2]}/{q}/{w}px-{q}" if w else f"https://upload.wikimedia.org/wikipedia/commons/{h[0]}/{h[:2]}/{q}"
        for t in range(4):
            try: open(p, "wb").write(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90).read()); print("ok", k); break
            except Exception as e: print("err", k, str(e)[:40], url); time.sleep(35)
        time.sleep(30)
