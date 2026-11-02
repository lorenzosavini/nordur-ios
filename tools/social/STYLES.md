# Norður social — 5 graphic formats to rotate

Alternate these so the feed never looks like the same video twice. Every format keeps the house rules in `README.md`
(free-licence media credited, verified facts, 1080×1920 @ 30 fps for reels).

| # | Format | Look | Sound | Best for | Toolkit |
|---|--------|------|-------|----------|---------|
| 1 | **Documentary** | Dark app palette (BG `#07090C`, accent `#FF5A1F`, aurora `#3DE0A8`), paper-cut relief maps, archive photos full-bleed, chapter bar, word-by-word captions | Male narrator (Kokoro `am_michael`), synthesized SFX, ducked music bed | History & safety stories (Heimaey, Reynisfjara, Sólheimasandur, Vikings) — 45–75 s | `reelkit.py`, `motionkit.py`, `geo.py` + `paper.py`, `sfxkit.py`, `*_reel.py` |
| 2 | **Travel notebook** | Light paper texture, polaroids taped at an angle, handwritten notes and doodled arrows, stamps, warm colours | Female narrator, soft acoustic bed | Itineraries, "3 days in…", packing, tips — 30–45 s | `fx.py` (`frame_photo(style="polaroid")`, `stamp`), handwriting font to add |
| 3 | **Retro VHS / 70s** | Film grain, faded colours, chromatic split, scan lines, orange date stamp in the corner (`'87 JUL 14`), 4:3 inset | Lo-fi/synth music, tape hiss, no voice or a short one | Nostalgia, "Iceland in 1973", old photos, myths & folklore — 20–40 s | `motionkit.py` (archive look, chromatic split, grain) |
| 4 | **Text + trending sound (TikTok)** | Real footage full-screen, big white captions with a thick black outline, white label chips, sticker graphics on flat colour (aurora green / orange), cuts on a 120 BPM grid (0.5 / 1 / 2 s), tiny logo + `nordur.info` only in the last second | **Silent export** — the trending sound is picked inside TikTok/Reels | Memes and trends: starter packs, "wait for it", expectation vs reality, POV, "tell me without telling me" — 7–15 s, built for rewatch/loops | `tiktok.py` (+ `tiktok_batch1.py` as example) |
| 5 | **Minimal infographic** | Flat solid colours, flat illustrations/icons (`icons/`), giant numbers that count up, one fact per screen, lots of white space | Upbeat music, no voice | Stats & records: wind speeds, daylight hours, prices, distances — 15–30 s and carousels | `wind_reel.py`, `sun_reel.py`, `quiz_reel.py`, `carousels_v3.py` |

## Rotation
A simple weekly cycle: Documentary → TikTok → Infographic → Notebook → TikTok → Retro VHS → (repeat).
TikTok-format posts are the cheapest to make, so they can appear twice a week; documentaries at most once.

## Format 4 cheat sheet (`tiktok.py`)
- `Video(path, start, dur, xshift)` / `Photo(path, focus, z)` → full-screen 9:16 sources (only the needed seconds are decoded).
- `caption(im, text, t, t0, t1, y, size, anim="pop|slam|up|wobble|type")` — outlined TikTok text; `box=(r,g,b)` for label chips.
- `punch`, `flash`, `shake` on the list of cut times keep the edit on the beat; `beat(n)` = n beats at the set BPM.
- `sticker(layer)` / `place(...)` for die-cut stickers that pop in; `endcard(im, t, total, icon)` for the last-second logo.
- `render(frame, total, out, procs=4)` writes a silent mp4 in parallel chunks; pass `test=[frames]` to save PNG checks first.
- Captions avoid the TikTok UI: keep text between y = 0.08 and 0.80 of the frame, credits at bottom-left above the caption area.
