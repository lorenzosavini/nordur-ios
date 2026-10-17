#!/usr/bin/env python3
"""Downloads candidate hero photographs from Wikimedia Commons (free licences
only) with their author and licence, for picking by hand. Writes into <out>/.
Run by .github/workflows/hero-candidates.yml (Wikimedia rate-limits shared IPs).
"""
import json, re, sys, time, urllib.parse, urllib.request

UA = "NordurApp/1.0 (https://github.com/lorenzosavini/nordur-ios)"
OK = re.compile(r"^(CC0|Public domain|CC BY(-SA)? [0-9.]+)$", re.I)
TERMS = {
    "aurora": ["aurora borealis Iceland", "northern lights Iceland mountains"],
    "roads": ["Iceland road snow winter", "Iceland road mountains"],
    "weather": ["Iceland storm clouds", "Iceland dramatic sky"],
    "map": ["Iceland aerial view", "Vatnajökull aerial"],
    "trip": ["Kirkjufell", "Iceland landscape waterfall"],
    "volcano": ["Fagradalsfjall eruption", "Iceland volcano eruption lava"],
    "drive": ["Iceland Route 1 car", "Iceland ring road"],
    "sea": ["Reynisfjara", "Iceland coast waves"],
}
out = sys.argv[1]
meta = {}

def get(url):
    for attempt in range(5):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60).read()
        except Exception as e:
            print("retry", e, flush=True); time.sleep(20 * (attempt + 1))
    raise RuntimeError(url)

for key, queries in TERMS.items():
    picked = 0
    for q in queries:
        url = ("https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=20"
               "&gsrsearch=" + urllib.parse.quote(q + " filetype:bitmap") + "&prop=imageinfo&iiprop=url|size|extmetadata&iiurlwidth=1600")
        data = json.loads(get(url))
        pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 99))
        for p in pages:
            if picked >= 4: break
            ii = p["imageinfo"][0]; m = ii.get("extmetadata", {})
            lic = m.get("LicenseShortName", {}).get("value", "").strip()
            if not OK.match(lic) or ii["width"] < 1600 or ii["width"] < ii["height"]: continue
            artist = re.sub(r"<[^>]+>", "", m.get("Artist", {}).get("value", "")).strip()
            name = f"{key}-{picked + 1}.jpg"
            open(f"{out}/{name}", "wb").write(get(ii["thumburl"]))
            meta[name] = {"title": p["title"], "license": lic, "artist": artist, "page": ii["descriptionurl"],
                          "licenseUrl": m.get("LicenseUrl", {}).get("value", "")}
            picked += 1
            time.sleep(2)
        time.sleep(5)
    print(key, picked, flush=True)
json.dump(meta, open(f"{out}/credits.json", "w"), indent=1, ensure_ascii=False)
