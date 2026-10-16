# Sky-glow grid (light pollution)

`Shared/Services/SkyGlowGrid.swift` is generated from NASA Black Marble VNP46A4 (annual night lights).

1. Create an Earthdata Login account and a user token (urs.earthdata.nasa.gov › Generate Token).
2. Download the two tiles covering Iceland from Earthdata Cloud (the LAADS archive asks for a browser licence step, the cloud copy does not):

   ```sh
   for t in h15v02 h16v02; do
     url=$(curl -s "https://cmr.earthdata.nasa.gov/search/granules.json?short_name=VNP46A4&temporal=2025-01-01T00:00:00Z,2025-01-02T00:00:00Z&bounding_box=-24.5,63.3,-13.5,66.6" \
       | python3 -c "import json,sys; print([l['href'] for g in json.load(sys.stdin)['feed']['entry'] for l in g['links'] if l['href'].startswith('https://data.laadsdaac') and '$t' in l['href']][0])")
     curl -L --location-trusted -H "Authorization: Bearer $EARTHDATA_TOKEN" -o "data/$(basename "$url")" "$url"
   done
   ```

3. `pip install h5py numpy`, then `python3 build.py data .` writes `skyglow.npy` and `grid.json`. The Swift file is the quantised grid: q = round(40·log10(1 + S/0.01)), base64-encoded.

Never commit the token.
