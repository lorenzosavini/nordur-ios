# Third-party notices

The Norður source code is covered by [LICENSE](LICENSE). The components and data below belong to their owners and keep their own licenses.

## Bundled components

| Component | Files | License |
|---|---|---|
| IBM Plex Sans and IBM Plex Mono, © 2017 IBM Corp., Reserved Font Name "Plex" | `Shared/Fonts/IBMPlex*.ttf` | SIL Open Font License 1.1 (`Shared/Fonts/LICENSE-IBMPlex.txt`) |
| Barlow Condensed, © 2017 The Barlow Project Authors | `Shared/Fonts/BarlowCondensed*.ttf` | SIL Open Font License 1.1 (`Shared/Fonts/LICENSE-BarlowCondensed.txt`) |
| `@vercel/blob` (npm dependency of the backend, installed at build time) | `backend/package.json` | Apache License 2.0 |

## Reference data embedded in the code

| Data | Where | Source and terms |
|---|---|---|
| IGRF-13 dipole coefficients (epoch 2020.5) | `Shared/Services/AuroraEngine.swift` | International Association of Geomagnetism and Aeronomy (IAGA), International Geomagnetic Reference Field |
| Sky-glow grid for Iceland derived from NASA Black Marble VNP46A4 (2025 annual composite) | `Shared/Services/SkyGlowGrid.swift` | NASA LAADS DAAC / Earthdata, open data — Román, M.O. et al. (2018), NASA's Black Marble nighttime lights product suite |
| Corrected geomagnetic latitudes of magnetic observatories | `Shared/Services/AuroraEngine.swift` | Observatory metadata published by ISGI / INTERMAGNET; used as calibration points |

## Data services used at run time

None of this data is stored in the repository. The app and the backend request it while running, and each provider's terms apply.

| Provider | Data | Terms / attribution |
|---|---|---|
| NOAA Space Weather Prediction Center | Kp, solar wind (RTSW), OVATION aurora, WSA-ENLIL, alerts, outlooks | U.S. Government work, public domain |
| NASA Community Coordinated Modeling Center — DONKI | CMEs and space weather events | NASA open data |
| GFZ German Research Centre for Geosciences | Kp index | CC BY 4.0 — Matzka, J. et al., Geomagnetic Kp index, GFZ Data Services |
| MET Norway (api.met.no) | Locationforecast | CC BY 4.0 and NLOD 2.0 — "Data from MET Norway" |
| Open-Meteo | Weather, marine and air-quality forecasts | CC BY 4.0 — "Weather data by Open-Meteo.com" |
| Veðurstofa Íslands (Icelandic Met Office) | Warnings (CAP), station forecasts, earthquakes | Public data of the Icelandic Met Office |
| Vegagerðin (Icelandic Road Administration) | Road conditions, road weather stations, webcams | Public data of Vegagerðin |
| SafeTravel.is (ICE-SAR) | Travel alerts | Public information of SafeTravel |
| Isavia / Keflavík Airport, Herjólfur | Flights and ferry notices | Public information of the operators |
| OpenStreetMap contributors, via Overpass API | Fuel and charging stations | Open Database License (ODbL) — "© OpenStreetMap contributors" |
| OpenTopoData — EU-DEM v1.1 | Terrain elevation for the horizon profile | EU-DEM: Copernicus Land Monitoring Service, European Union |
| RainViewer | Precipitation radar tiles | RainViewer API terms |

The names and logos of the services above are trademarks of their owners. Norður is not affiliated with or endorsed by any of them.

## Photographs (hero images)

Bundled in `Nordur/Assets.xcassets/hero-*.imageset`, resized to 1400 px and
recompressed; otherwise unchanged. From Wikimedia Commons, under the licence of
each file (CC BY and CC BY-SA require attribution; CC BY-SA derivatives of the
image keep the same licence). Also credited in the app (Info › Crediti foto).

| Asset | File | Author | Licence |
|---|---|---|---|
| `hero-aurora` | [Church of light.jpg](https://commons.wikimedia.org/wiki/File:Church_of_light.jpg) | AstroAnthony | CC BY 4.0 |
| `hero-roads` | [Driving in Iceland can be challenging (40217475782).jpg](https://commons.wikimedia.org/wiki/File:Driving_in_Iceland_can_be_challenging_(40217475782).jpg) | Winniepix | CC BY 2.0 |
| `hero-weather` | [Crepuscular rays break through clouds in Iceland.jpg](https://commons.wikimedia.org/wiki/File:Crepuscular_rays_break_through_clouds_in_Iceland.jpg) | Thomas  Heins from Friesenheim, Deutschland | CC BY 4.0 |
| `hero-map` | [Iceland (15082529060).jpg](https://commons.wikimedia.org/wiki/File:Iceland_(15082529060).jpg) | NASA Goddard Space Flight Center from Greenbelt, MD, USA | Public domain |
| `hero-trip` | [Kirkjufell, Iceland (Unsplash LoKG7kKx7Zc).jpg](https://commons.wikimedia.org/wiki/File:Kirkjufell,_Iceland_(Unsplash_LoKG7kKx7Zc).jpg) | Steven Diaz stevendiazphoto | CC0 |
| `hero-volcano` | [Iceland's Fagradalsfjall volcano.png](https://commons.wikimedia.org/wiki/File:Iceland%27s_Fagradalsfjall_volcano.png) | Mokslo Sriuba | CC BY-SA 4.0 |
| `hero-drive` | [Saturday Winter Afternoon on the Road from the Factory, Iceland - panoramio.jpg](https://commons.wikimedia.org/wiki/File:Saturday_Winter_Afternoon_on_the_Road_from_the_Factory,_Iceland_-_panoramio.jpg) | Petr Kraumann | CC BY 3.0 |
