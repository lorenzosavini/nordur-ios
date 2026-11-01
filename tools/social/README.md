# Norður social content toolkit

Python + ffmpeg pipeline used to make Norður's Instagram/TikTok reels and carousels.
Everything renders on CPU (1080×1920, 30 fps). Media is downloaded at run time, never committed.

## Setup (fresh container)
```
pip install numpy pillow opencv-python-headless soundfile kokoro-onnx
mkdir -p work/avatar && cd work/avatar
curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
```
Fonts: `site/landing/fonts` (Barlow Condensed, IBM Plex). Logo: generate with the app icon or reuse `site/landing/img/icon.png`.

## Tools
- `tools/reelkit.py` – frame loop, ffmpeg writer, captions, CTA card.
- `tools/fx.py` – overlay system: photo cards/polaroids that enter (pop, drop, spin, left/right/up, zoom) and exit (fade, slide, shrink), stamps, grain.
- `tools/geo.py` + `tools/paper.py` – Mapzen Terrarium DEM tiles (AWS, public) → stylised dark "paper-cut" relief (no Google/Apple maps).
- `tools/rift3.py` – reel "This crack is tearing Iceland in two" (final, delivered).
- `tools/vik_reel.py` – reel "Columbus wasn't first" (Leif Erikson). Needs media in `<work>/vik/` (see `projects/vikings/dl.py`, `dl2.py`), `natl.png` (N. Atlantic paper map: `geo.dem(-72,40,18,73.5,5)` → `paper.papercut` ×2, rift3 DARK palette), voice timeline in `<work>/vik/voice/`.
- `tools/jol_reel.py` – reel "Iceland's Christmas is terrifying" (13 Yule Lads, Grýla, Leppalúði, Yule Cat). Media in `<work>/jol/` (`projects/jol/dl.py`), `ice.png` (Iceland paper map, `geo.dem(-25,63.2,-13,66.7,7)`), voice in `<work>/jol/voice/`. Characters are original drawings (the 1932 illustrations are under copyright).
- Run any reel as `python tools/<reel>.py <work> site/landing/fonts <out_dir> [frame numbers…]`: with frame numbers it only saves those test PNGs (fast), without it renders the mp4.
- `tools/wind_reel.py`, `quake_reel.py`, `sun_reel.py`, `quiz_reel.py` – data-driven animated reels.
- `tools/carousels_v3.py`, `posts_v2.py`, `lore.py`, `plib.py`, `deco.py` – carousels/posts (1080×1350).
- Wikimedia from cloud IPs: originals usually get HTTP 429; standard thumbnail widths (1280/1920px) and transcodes go through after a few retries. Go slowly (~30 s per file). For long videos fetch only the needed seconds with `ffmpeg -ss … -i <transcode url> -t …` (see `projects/vikings/dl2.py`).
- `tools/commons_dl2.py` – downloads Commons thumbnails via upload.wikimedia.org (the API is rate-limited from cloud IPs: query it with WebFetch, download with this script slowly).

## Voice
`projects/*/narrate.py <avatar_dir> <out_dir>` + `voice/script.json` → `narration.wav` + `timeline.json` (Kokoro voice `am_michael`, speed 1.02, en-US). `say` can respell Icelandic names for the TTS (e.g. "Greela" for Grýla); captions use `show`.

## House rules (from the owner)
- English content; dark app palette: BG #07090C, accent #FF5A1F, aurora #3DE0A8, blue #78AAFF.
- Only free-licence media (PD, CC0, CC BY, CC BY-SA), credited on screen and in the caption. Every image used once across all posts.
- Every fact verified on reliable sources; skip anything sources disagree on.
- Not only maps: mix footage, paintings, manuscripts, photos, stamps, data graphics. Many overlays with in/out transitions, hooks every ~10 s, word-by-word captions, chapter bar.
- Check sample frames before delivering; deliver mp4 + caption + 5 hashtags.
