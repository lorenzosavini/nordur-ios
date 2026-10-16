# Previsione dell'aurora in Norður

Questo documento descrive come l'app stima l'aurora: fonti, calcoli, frequenze e limiti.
L'app tiene separati tre risultati:

1. **Attività aurorale**: cosa dicono modelli e misure sull'aurora.
2. **Osservabilità locale**: se da quel luogo e in quell'ora si potrebbe vederla.
3. **Affidabilità**: quanto fidarsi delle due risposte precedenti.

## Architettura

```
NOAA SWPC · GFZ · NASA DONKI · MET Norway
            │  (backend nordur-api, Vercel: ingestione, normalizzazione,
            │   validazione, cache CDN, archivio, backtest)
            ▼
 /api/aurora   /api/sites   /api/backtest   /api/sightings
            │
            ▼  (app iOS)
 AuroraState ─► AuroraEngine ◄─ meteo del luogo (MET Norway + Open-Meteo)
                    │            Astro (Sole, Luna)
                    ▼
   AuroraView · notifiche · widget
```

Le fonti scientifiche vengono interrogate dal backend, non dai telefoni.
`/api/aurora` resta in cache CDN per 60 s, quindi NOAA, GFZ e NASA ricevono al massimo una richiesta al minuto, qualunque sia il numero di utenti.
Se il backend non risponde, l'app ripiega su NOAA diretto (previsione del Kp e OVATION) con meno funzioni.

| Modulo | File |
|---|---|
| Ingestione e normalizzazione | `backend/lib/sources.js`, `backend/lib/donki.js`, `backend/api/sites.js` |
| Validazione e affidabilità delle fonti | `backend/lib/fetch.js` (timeout, retry con backoff, circuit breaker), `backend/api/aurora.js` (stato ok/stale/error) |
| Analisi del vento solare | `backend/lib/solarwind.js` |
| Kp combinato | `backend/lib/kp.js` |
| Archivio storico e validazione | `backend/lib/archive.js`, `backend/api/backtest.js` |
| Avvistamenti | `backend/api/sightings.js` |
| Motore di visibilità e geometria | `Shared/Services/AuroraEngine.swift` |
| Astronomia | `Shared/Services/Astro.swift` |
| Modelli dati e località | `Shared/Services/AuroraState.swift`, `Shared/Services/AuroraSites.swift` |
| Notifiche | `Shared/Models/Alerts.swift` (`AlertEngine.auroraEvents`) |
| Interfaccia | `Nordur/Views/AuroraView.swift`, `AuroraLiveView.swift` |

## Fonti verificate

Tutti gli endpoint sono stati interrogati realmente il 16/10/2026, con verifica di schema, unità e timestamp.

| Fonte | Endpoint | Uso | Aggiornamento |
|---|---|---|---|
| NOAA SWPC | `products/noaa-planetary-k-index-forecast.json` | Kp a blocchi di 3 h, con etichette observed/estimated/predicted | 3 h |
| NOAA SWPC | `json/planetary_k_index_1m.json` | Kp stimato al minuto (provvisorio) | 1 min |
| NOAA SWPC | `json/rtsw/rtsw_mag_1m.json`, `rtsw_wind_1m.json` | Bt, By/Bz GSM, velocità, densità, temperatura, flag di qualità; solo il satellite `active` (oggi SOLAR1, con ACE e IMAP in riserva) | 1 min |
| NOAA SWPC | `json/rtsw/rtsw_ephemerides_1h.json` | posizione X_GSE del satellite, per il tempo di propagazione | 1 h |
| NOAA SWPC | `json/ovation_aurora_latest.json` | griglia OVATION 1°×1°, con orari di osservazione e di previsione | 5 min |
| NOAA SWPC | `text/aurora-nowcast-hemi-power.txt` | potenza emisferica (GW) | 5 min |
| NOAA SWPC | `json/enlil_time_series.json` | WSA-ENLIL alla Terra: velocità, densità, nube CME, fino a +5 giorni | per ogni nuova esecuzione |
| NOAA SWPC | `products/noaa-scales.json`, `products/alerts.json` | scale G; avvisi K-index, con annullamenti ed estensioni | evento |
| NOAA SWPC | `text/27-day-outlook.txt`, `json/45-day-forecast.json` | Kp massimo e Ap giornalieri a lungo termine | settimanale / giornaliero |
| GFZ Potsdam | `kp.gfz.de/app/json/` (CC BY 4.0) | Kp ufficiale (definitivo/preliminare) per confronto e per il backtest | 3 h |
| NASA CCMC | DONKI `GST`, `WSAEnlilSimulations`, `FLR` | tempeste, arrivi di CME con il Kp atteso da NASA, brillamenti M/X | 30 min |
| MET Norway | `locationforecast/2.0/complete` | nubi per strati (basse/medie/alte), nebbia | 30 min (backend), a ogni aggiornamento meteo (app) |
| Open-Meteo | `v1/forecast` | strati nuvolosi e visibilità oltre l'orizzonte di MET | aggiornamento meteo dell'app |

**NASA DONKI** è stato spostato da CCMC il 30/09/2026 su `ccmc.gsfc.nasa.gov/DONKI-API/get/`. I vecchi host (`kauai`, `webtools`) rispondono con una pagina HTML di avviso e `api.nasa.gov/DONKI` restituisce 503. Verificato il 16/10/2026 su dati reali: tempeste geomagnetiche (GST), simulazioni WSA-ENLIL con Kp atteso e brillamenti (FLR). Se il servizio non risponde, l'app mostra l'ultima risposta completa come "copia salvata".

## Calcoli

### Vento solare (`solarwind.js`)

- Medie mobili a 5, 15, 30 e 60 minuti di Bz, By, Bt, V, n e Pdyn; minimi e massimi su 60 minuti.
- Persistenza del Bz verso sud:
  - minuti consecutivi con Bz < 0;
  - frazione dell'ultima ora con Bz ≤ −5 e con Bz ≤ −10 nT.
- Pressione dinamica Pdyn ≈ 1,6726·10⁻⁶ · n · V² nPa. Considera solo i protoni, quindi la pressione reale è di solito qualche % più alta.
- Andamento della pressione: rapporto tra la media degli ultimi 15 minuti e quella di un'ora prima.
- Accoppiamento di Newell (2007): dΦ/dt = V^4/3 · B_T^2/3 · sin^8/3(θc/2), con By e Bz in GSM.
- Kp ricavato dal vento solare (fit di Newell). È statistico e, in condizioni quiete, tende a sovrastimare (osservato: 3,0 contro 0–1,3 di NOAA). Per questo entra nel Kp combinato con peso 1, contro peso 2 della stima a terra.
- Candidati shock: confronto tra due finestre di 8 minuti; servono Δv ≥ 20 km/s, rapporto di densità ≥ 1,2 e rapporto di campo ≥ 1,2. Sono indicati come "candidato", non come shock confermato.
- Propagazione (ritardo piatto): t = X_GSE / |Vx|, con la posizione reale del satellite. Incertezza ±max(10 min, 15 %). La risposta di magnetosfera e ionosfera arriva dopo e non viene presentata come orario di comparsa dell'aurora.

### Kp (`kp.js`)

Osservato, stimato e previsto restano distinti. Il Kp combinato si costruisce per blocco:

- **Blocchi osservati**: valore NOAA, con quello GFZ accanto.
- **Blocco attuale**: media pesata di previsione NOAA (×1), stima NOAA al minuto (×2, se ha meno di 20 minuti) e Kp di Newell (×1).
- **Blocchi futuri**: previsione NOAA, alzata al Kp atteso da NASA quando una CME DONKI attraversa il blocco. La finestra si apre 6 h prima, per l'incertezza di ±7 h sull'arrivo. Si usa sempre il minimo della forbice NASA: CCMC segnala che il Kp derivato da ENLIL tende a sovrastimare.

Il Kp non viene mai usato come regola universale di visibilità.

### Latitudine geomagnetica e ovale (`AuroraEngine.swift`)

- Dipolo eccentrico (Fraser-Smith, coefficienti IGRF-13 2020,5): il dipolo centrato dava Reykjavík circa 4,8° troppo alta.
- Correzione verso la latitudine geomagnetica corretta (CGM): i residui di 39 osservatori ISGI sono interpolati con un kernel gaussiano (600 km, prior 0,02).
- Errore leave-one-out: 0,3° rms in Islanda e Scandinavia, 0,6° su tutti gli osservatori. Leirvogur risulta a circa 64,1° CGM, Tromsø a 66,9°.
- Bordo equatoriale dell'ovale: Λ = 66,5° − 2,05 · Kp, fit della tabella Kp–latitudine di NOAA, con incertezza di ±2–3°.
- Questo modello si usa solo oltre la validità di OVATION. La categoria "sopra di te" richiede almeno 2° oltre il bordo.

### Geometria di visibilità con OVATION

OVATION si usa solo dall'orario di osservazione fino a 45 minuti dopo l'orario di previsione, e solo se l'esecuzione ha meno di 40 minuti.

1. Si scandiscono le celle entro circa 1 300 km dall'osservatore.
2. Per ogni cella si calcolano la distanza ortodromica e l'elevazione dell'emissione: e = atan2(cos θ − R/(R+h), sin θ). Si usa h = 110 km (bordo inferiore del verde) e h = 200 km per le emissioni alte.
3. Si scelgono cella più forte, direzione e altezza sull'orizzonte. Le celle sotto la soglia di visualizzazione NOAA (10) vengono ignorate.

Categorie risultanti:

| Categoria | Elevazione |
|---|---|
| Sopra di te | ≥ 60° |
| Verso l'orizzonte | ≥ 15° |
| Molto bassa | ≥ 3°, oppure ≥ 5° per emissioni a 200 km |
| Non prevista | sotto queste soglie |

Il valore OVATION non viene presentato come probabilità di osservazione da terra.

### Orizzonte del terreno (`/api/horizon`)

- Quote dal DEM EU-DEM 25 m (OpenTopoData): 16 direzioni × 12 distanze, da 1 a 40 km.
- Correzione per curvatura terrestre e rifrazione (k = 0,13), occhi a 2 m dal suolo.
- Il profilo è calcolato una volta per luogo (coordinate arrotondate a 0,01°) e conservato sul telefono.
- Le celle OVATION sotto lo skyline + 1° non contano come visibili; nel modello Kp l'orizzonte verso il polo magnetico nasconde l'aurora bassa.
- Verifiche: Vík verso N 8,9–11°, Reykjavík verso NE 3° (Esja), Akureyri verso O 5–8°.

### Cielo, buio, Luna, luce

- **Nubi**: sovrapposizione casuale degli strati, sereno = (1−basse)·(1−medie)·(1−0,5·alte). Le nubi alte valgono metà, perché il cirro sottile lascia spesso passare l'aurora. Nebbia ≥ 50 % o visibilità < 1 km chiudono il cielo.
- **Buio**: altezza del Sole, con le classi giorno, civile, nautico, astronomico e notte. Fattori 0 / 0,05 / 0,5 / 0,85 / 1. Il crepuscolo nautico non è considerato impossibile.
- **Luna**: posizione topocentrica e frazione illuminata. Fattore 1 − 0,35 · illuminazione · altezza normalizzata.
- **Inquinamento luminoso**: indicatore basato sulla distanza dai centri principali (area di Reykjavík, Reykjanesbær, Akureyri, Selfoss). Non è un dato di brillanza del cielo (vedi limiti).

### Indice di osservabilità

indice = attività × sereno × buio × Luna × luce.

È un indice **euristico** in cinque classi, ciascuna mostrata con le ragioni principali:

| Classe | Indice |
|---|---|
| Molto sfavorevole | < 0,08 |
| Sfavorevole | < 0,20 |
| Moderatamente favorevole | < 0,35 |
| Favorevole | < 0,55 |
| Molto favorevole | ≥ 0,55 |

Non è una probabilità, e non viene mostrata nessuna percentuale. Per una probabilità calibrata, P(avvistamento | condizioni), servono osservazioni reali: le raccoglie `/api/sightings`.

### Affidabilità

| Livello | Quando |
|---|---|
| Alta | ora valutata con OVATION valido e vento solare aggiornato |
| Media | entro 24 h |
| Bassa | oltre 24 h, e sempre oltre 72 h |

Scende di un livello se il Kp previsto non è aggiornato, se manca la nuvolosità o se i due modelli meteo differiscono di oltre il 40 % di cielo sereno.

## Astronomia: verifiche

| Verifica | Riferimento | Risultato |
|---|---|---|
| Luna piena 23/04/2024 23:49 UTC | tabelle delle fasi | illuminazione 99,98 % |
| Luna nuova 08/04/2024 | tabelle delle fasi | 0 % |
| Eclissi totale da Mazatlán, 08/04/2024 18:18 UTC | Sole e Luna devono coincidere | differenza 0,02° in altezza, 0,75° in azimut |
| Tramonto a Reykjavík, 16/10/2026 | MET Norway Sunrise 3.0: 18:04 UTC | 18:05 UTC |
| Luna al culmine, Reykjavík, 16/10/2026 17:57 | MET Norway: −2,68° | −2,65° |

## Frequenze

| Dato | Frequenza |
|---|---|
| Stato spaziale (backend) | cache 60 s, quindi vento solare e Kp al minuto e OVATION a ogni nuova esecuzione |
| DONKI | 30 min |
| Meteo delle località (MET) | 30 min |
| Archivio | uno snapshot per blocco Kp di 3 h, mai sovrascritto, scritto dal workflow GitHub ogni 3 h e dal cron giornaliero di Vercel |
| App | stato spaziale a ogni apertura, ogni 5 min in primo piano e a ogni controllo delle allerte; meteo a ogni aggiornamento del luogo |

## Notifiche aurora

Le notifiche partono da condizioni verificate nei dati. Hanno un cooldown (chiavi raggruppate per fascia di 3 h o per notte) e una scadenza, e non promettono mai un'aurora visibile.

- **Condizioni adesso**: classe ≥ quella scelta, cielo almeno in crepuscolo nautico, affidabilità ≥ media.
- **Finestra favorevole**: entro 6 h.
- **Bz persistente**: Bz ≤ −8 nT di media per 30 min e verso sud da almeno 30 minuti; solo con vento solare aggiornato.
- **Candidato shock**: nell'ultima ora.
- **Avvisi K-index NOAA**: attivi, con Kp ≥ soglia (predefinita 5).
- **CME NASA**: arrivo entro 36 h con Kp atteso ≥ soglia.
- **Nube CME di ENLIL NOAA**: arrivo entro 36 h.

## Validazione

`/api/backtest` confronta le previsioni archiviate (NOAA e combinata) con il Kp poi osservato: GFZ dove disponibile, altrimenti NOAA.

- Suddivisione per anticipo: 0–3 h, 3–24 h, 24–72 h.
- Metriche: MAE, bias, RMSE; per Kp ≥ 4 e Kp ≥ 5 anche tabella di contingenza, precisione, POD (recall) e FAR.
- Le previsioni sono deterministiche, quindi il Brier sullo 0/1 coincide con il tasso di errore.
- Servono circa 100 coppie (2 settimane di archivio) prima di trarre conclusioni.

La visibilità locale non è ancora validabile: richiede gli avvistamenti. L'assenza di segnalazioni non dimostra l'assenza di aurora.

## Test

- **Backend**: `node --test backend/test`, 11 test su tempi, pressione, Newell, shock, propagazione, medie Kp combinato, orizzonte e riepilogo DONKI. Eseguito anche in CI.
- **Motore**: `Tests/EngineTests/main.swift`, compilato in CI con i sorgenti reali tramite `swiftc`. Copre astronomia, latitudine CGM, orizzonte del terreno, geometria, nubi, classi, affidabilità e validità di OVATION.
- **Dati reali**: `/api/aurora` in produzione il 16/10/2026 ha risposto con tutte le 12 fonti "ok", NASA DONKI compreso dopo il cambio di host.

## Limiti noti

- **Inquinamento luminoso**: si usa un indicatore basato sulla distanza dai centri abitati. Il World Atlas 2015 (Falchi) è CC BY-NC 4.0 e si ottiene con un modulo di richiesta; VIIRS Black Marble (VNP46) richiede un account NASA Earthdata. Entrambi richiedono un'azione del proprietario dell'app.
- **Orizzonte**: risoluzione 25 m e 16 direzioni; edifici e alberi non sono nel DEM.
- **Magnetometri**: SuperMAG richiede registrazione e accettazione dei termini, quindi non è integrato. GFZ è integrato solo come Kp.
- **Latitudine geomagnetica**: approssimazione della CGM (0,3–0,6° rms), non il calcolo AACGM completo.
- **Indice di osservabilità**: euristico, da calibrare con gli avvistamenti.
- **Open-Meteo**: limita le richieste per IP; il confronto tra località usa quindi MET Norway dal backend.
- **Archivio**: un workflow GitHub pianificato (`aurora-archive.yml`, ogni 3 h al minuto 17) richiama `/api/aurora`; GitHub può ritardare i job pianificati di qualche minuto.

## Account e dati personali

- Registrazione con email e password (scrypt); nessuna email viene inviata.
- Recupero password con un codice di 16 caratteri mostrato alla registrazione, conservato solo come hash e rigenerato a ogni uso.
- Cambio password, nuovo codice di recupero ed eliminazione dell'account dall'app. L'eliminazione cancella backup, avvistamenti e utente, e revoca le sessioni esistenti.
- Informativa: `backend/public/privacy.html`; manifest `PrivacyInfo.xcprivacy` per app e widget.
