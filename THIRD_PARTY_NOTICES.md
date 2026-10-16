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
| Windy.com | Embedded map | Windy.com embed terms |

The names and logos of the services above are trademarks of their owners. Norður is not affiliated with or endorsed by any of them.
