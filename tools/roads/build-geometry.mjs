// Road-section geometry for the map: the lines of every serviced road section
// (Vegagerðin), keyed by the same section id /api/roads uses (IDBUTUR).
//
// Source: the vector tiles behind umferdin.is (PMTiles, layer roads_vg), read at
// zoom 9, joined across tiles, simplified (Douglas–Peucker, ~60 m) and stored as
// delta-encoded integer coordinates (1e-4°, ~10 m) in backend/public/roadgeom.json,
// served as a static file by nordur-api. Road geometry changes rarely: rerun
// when Vegagerðin publishes new tiles.
//
//   npm i pmtiles@3 @mapbox/vector-tile@1 pbf@3   (in a scratch folder)
//   node tools/roads/build-geometry.mjs backend/public/roadgeom.json
import { PMTiles } from "pmtiles";
import { VectorTile } from "@mapbox/vector-tile";
import Protobuf from "pbf";
import { writeFileSync } from "node:fs";

const URL = "https://umferdin.is/tiles/map.pmtiles";
const Z = 9, BOUNDS = [-24.6, 63.25, -13.4, 66.6];
const out = process.argv[2] || "roadgeom.json";

const tileX = (lon) => Math.floor(((lon + 180) / 360) * 2 ** Z);
const tileY = (lat) => {
  const r = (lat * Math.PI) / 180;
  return Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** Z);
};

const pm = new PMTiles(URL);
const lines = new Map(); // id -> [[lon, lat], ...][]
let tiles = 0;
for (let x = tileX(BOUNDS[0]); x <= tileX(BOUNDS[2]); x++) {
  for (let y = tileY(BOUNDS[3]); y <= tileY(BOUNDS[1]); y++) {
    const t = await pm.getZxy(Z, x, y);
    if (!t?.data) continue;
    tiles++;
    const layer = new VectorTile(new Protobuf(new Uint8Array(t.data))).layers.roads_vg;
    if (!layer) continue;
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      const id = f.properties.IDBUTUR;
      if (id == null) continue;
      const gj = f.toGeoJSON(x, y, Z).geometry;
      const parts = gj.type === "LineString" ? [gj.coordinates] : gj.type === "MultiLineString" ? gj.coordinates : [];
      const list = lines.get(String(id)) || [];
      list.push(...parts);
      lines.set(String(id), list);
    }
  }
}

// Join pieces cut at tile edges (shared end points within ~30 m).
const near = (a, b) => Math.abs(a[0] - b[0]) < 3e-4 && Math.abs(a[1] - b[1]) < 3e-4;
function join(parts) {
  const pool = parts.map((p) => p.slice());
  const done = [];
  while (pool.length) {
    let cur = pool.pop(), grew = true;
    while (grew) {
      grew = false;
      for (let i = 0; i < pool.length; i++) {
        const p = pool[i];
        if (near(cur[cur.length - 1], p[0])) cur = cur.concat(p.slice(1));
        else if (near(cur[cur.length - 1], p[p.length - 1])) cur = cur.concat(p.slice(0, -1).reverse());
        else if (near(cur[0], p[p.length - 1])) cur = p.concat(cur.slice(1));
        else if (near(cur[0], p[0])) cur = p.slice().reverse().concat(cur.slice(1));
        else continue;
        pool.splice(i, 1); grew = true; break;
      }
    }
    done.push(cur);
  }
  return done;
}

// Douglas–Peucker in degrees (longitude scaled by cos(lat)).
function simplify(pts, eps = 0.00055) {
  if (pts.length < 3) return pts;
  const k = Math.cos((pts[0][1] * Math.PI) / 180);
  const keep = new Uint8Array(pts.length); keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    let max = 0, idx = -1;
    const ax = pts[a][0] * k, ay = pts[a][1], bx = pts[b][0] * k, by = pts[b][1];
    const dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1e-12;
    for (let i = a + 1; i < b; i++) {
      const d = Math.abs((pts[i][0] * k - ax) * dy - (pts[i][1] - ay) * dx) / len;
      if (d > max) { max = d; idx = i; }
    }
    if (max > eps) { keep[idx] = 1; stack.push([a, idx], [idx, b]); }
  }
  return pts.filter((_, i) => keep[i]);
}

const sections = {};
let points = 0;
for (const [id, parts] of lines) {
  sections[id] = join(parts).map((line) => {
    const s = simplify(line);
    points += s.length;
    let px = 0, py = 0;
    return s.flatMap(([lon, lat]) => {
      const x = Math.round(lon * 1e4), y = Math.round(lat * 1e4);
      const d = [x - px, y - py]; px = x; py = y;
      return d;
    });
  });
}
const header = await pm.getMetadata().catch(() => ({}));
writeFileSync(out, JSON.stringify({
  source: "Vegagerðin · umferdin.is (roads_vg)", generated: new Date().toISOString(), zoom: Z, scale: 1e4,
  encoding: "per line: delta-encoded [lon, lat] integer pairs, first pair absolute", attribution: header.attribution || null,
  sections,
}));
console.log({ tiles, sections: Object.keys(sections).length, points });
