"""Downloads the OpenStreetMap layers the app uses (shops, places to see) for
Iceland, area by area with generous timeouts and retries, and writes them in
the shape nordur-api serves: {updated, areas, elements:[{id, lat, lon, tags}]}.
Run by .github/workflows/osm-data.yml, which publishes them on the osm-data branch.
"""
import json, sys, time, urllib.parse, urllib.request
from datetime import datetime, timezone

MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
AREAS = [
    "63.2,-24.6,64.3,-21.0", "64.3,-24.6,66.6,-21.0", "63.2,-21.0,64.2,-18.5", "64.2,-21.0,66.6,-18.5",
    "63.2,-18.5,64.6,-16.0", "64.6,-18.5,66.6,-16.0", "63.2,-16.0,65.0,-13.4", "65.0,-16.0,66.6,-13.4",
]
# Keep in step with OSM_LAYERS in backend/api/roads.js.
LAYERS = {
    "shops": {
        "filters": ['nwr["shop"~"^(supermarket|convenience|mall|alcohol|department_store)$"]'],
        "keep": ["shop", "name", "brand", "operator", "opening_hours", "addr:city", "addr:place"],
        "min": 50,
    },
    "sights": {
        "filters": [
            'nwr["tourism"~"^(attraction|viewpoint|museum)$"]["name"]',
            'nwr["natural"~"^(waterfall|hot_spring|geyser|cave_entrance|arch|volcano|glacier|beach)$"]["name"]',
            'nwr["waterway"="waterfall"]["name"]',
            'nwr["amenity"="public_bath"]["name"]',
            'nwr["leisure"="swimming_pool"]["name"~"laug|lagoon",i]["access"!="private"]',
        ],
        "keep": ["tourism", "natural", "waterway", "amenity", "leisure", "name", "name:en", "wikipedia", "wikidata",
                 "description", "description:en", "fee", "opening_hours", "ele"],
        "min": 200,
    },
}
UA = "nordur-osm-data (github.com/lorenzosavini/nordur-ios)"


def query(layer, bbox):
    body = "[out:json][timeout:170];(" + "".join(f"{f}({bbox});" for f in layer["filters"]) + ");out center tags;"
    data = urllib.parse.urlencode({"data": body}).encode()
    last = None
    for attempt in range(6):
        endpoint = MIRRORS[attempt % len(MIRRORS)]
        try:
            req = urllib.request.Request(endpoint, data=data, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=200) as r:
                j = json.load(r)
            if j.get("remark") and not j.get("elements"):
                raise RuntimeError(j["remark"])
            return j.get("elements", [])
        except Exception as e:  # busy mirror, timeout, HTML error page
            last = e
            print(f"  {bbox} {endpoint}: {e}", file=sys.stderr)
            time.sleep(15 * (attempt + 1))
    raise RuntimeError(f"{bbox}: {last}")


def compact(elements, keep):
    out = []
    for e in elements:
        lat = e.get("lat", (e.get("center") or {}).get("lat"))
        lon = e.get("lon", (e.get("center") or {}).get("lon"))
        tags = e.get("tags") or {}
        if lat is None or lon is None or not tags:
            continue
        out.append({"id": e["id"], "lat": round(lat, 5), "lon": round(lon, 5),
                    "tags": {k: str(tags[k])[:300] for k in keep if k in tags}})
    return out


def main(out_dir):
    for name, layer in LAYERS.items():
        seen, elements = set(), []
        for bbox in AREAS:
            for e in compact(query(layer, bbox), layer["keep"]):
                if e["id"] not in seen:
                    seen.add(e["id"])
                    elements.append(e)
            print(f"{name} {bbox}: {len(elements)} so far")
            time.sleep(5)
        if len(elements) < layer["min"]:
            raise SystemExit(f"{name}: only {len(elements)} elements")
        doc = {"updated": datetime.now(timezone.utc).isoformat(timespec="seconds"), "areas": f"{len(AREAS)}/{len(AREAS)}", "elements": elements}
        with open(f"{out_dir}/{name}.json", "w") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        print(f"{name}: {len(elements)} elements")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
