# Norður — meteo, strade e aurora per viaggiare in Islanda

App iOS nativa (SwiftUI, iOS 17+, iPhone e iPad) che riunisce in un'unica schermata
tutte le informazioni utili per un viaggio in Islanda con più mezzi.
Nessuna chiave API: usa solo fonti pubbliche e ufficiali.

## Cosa fa

| Schermata | Contenuto | Fonte |
|---|---|---|
| **Oggi** | Allerte meteo ufficiali che coprono il punto in cui sei, condizioni attuali, rischio guida nelle prossime 12 h (raffiche, ghiaccio, neve), aurora stanotte, strade vicine, mare, terremoti, avvisi SafeTravel | tutte |
| **Meteo** | Grafici 48 h di temperatura/pioggia e vento/raffiche (soglia 25 m/s), ora per ora con rischio fulmini, 16 giorni, mare (onde, periodo, swell, rischio *sneaker waves* sulle spiagge e per i traghetti), qualità dell'aria e SO₂ vulcanico | Open-Meteo (forecast, marine, CAMS) |
| **Aurora** | Punteggio 0–100 ora per ora (Kp previsto × cielo sereno × buio), Kp 3 giorni, ovale OVATION sopra di te, Bz e velocità del vento solare | NOAA SWPC + Open-Meteo |
| **Strade** | Tutti i tratti con ghiaccio, neve, impraticabili o chiusi; ~200 stazioni meteo stradali con vento, raffiche e temperatura dell'asfalto | Vegagerðin (dati di umferdin.is) |
| **Allerte** | Allerte gialle/arancioni/rosse con descrizione, validità e poligono sulla mappa | Veðurstofa Íslands (IMO, CAP) |
| **Terremoti e vulcani** | Scosse delle ultime 48 h con mappa e filtro magnitudo, link a pericoli vulcanici e gas | IMO |
| **Mappa** | Livelli attivabili: poligoni delle allerte, stazioni stradali colorate per rischio (numero = raffica), terremoti, tappe del viaggio | — |
| **Viaggio** | Tappe con data, notti e mezzo (auto, aereo, traghetto, bus, trekking, barca). Per ogni tappa: meteo del giorno, allerte valide in quelle date, mare se arrivi via nave; per ogni tratta in auto: condizioni attuali delle stazioni lungo il percorso e indicazioni in Apple Mappe | — |
| **Info & SOS** | 112, numero alternativo 599-0112, piano di viaggio SafeTravel, link a voli KEF, bus, traghetti, strade F; impostazioni notifiche; stato delle fonti | — |

Extra:
- **Funziona offline**: l'ultima risposta di ogni fonte resta in cache e viene mostrata con l'indicazione "Offline · dati di …" quando manca il segnale.
- **Notifiche in background**: nuove allerte arancioni/rosse (opzionale anche gialle) nella tua zona o nelle tappe dei prossimi 3 giorni, e notti con buona probabilità di aurora.
- **Qualsiasi luogo del mondo**: meteo, mare e aurora funzionano ovunque (ricerca con Apple Maps); allerte, strade e terremoti sono specifici per l'Islanda.

## Come installarla sul tuo iPhone

Serve un Mac con **Xcode 16 o successivo** (gratuito sul Mac App Store).

1. Apri `ios/Nordur/Nordur.xcodeproj` in Xcode.
2. Seleziona il target **Nordur** → *Signing & Capabilities* → scegli il tuo **Team**
   (basta un Apple ID gratuito; con l'Apple Developer Program l'app non scade dopo 7 giorni).
   Se il bundle id `it.lorenzosavini.nordur` è già occupato, cambialo.
3. Collega l'iPhone, attiva la *Modalità sviluppatore* (Impostazioni → Privacy e sicurezza) e premi ▶︎ Run.

In alternativa il progetto si può rigenerare con XcodeGen: `brew install xcodegen && cd ios/Nordur && xcodegen generate`.

## Struttura

```
Nordur/
  App/        entry point, TabView, background refresh
  Core/       HTTP con cache offline, date, geometria, formattazione, scala di rischio
  Models/     luoghi (preset islandesi) e tappe del viaggio
  Services/   Open-Meteo, IMO (allerte + terremoti), Vegagerðin, NOAA SWPC, SafeTravel
  State/      AppModel (dati), TripStore (itinerario su disco), LocationManager, Notifier
  Views/      schermate SwiftUI (Charts + MapKit)
```

## Soglie usate

- **Vento** (m/s): medio ≥10 attenzione, ≥15 rischioso, ≥20 pericoloso; raffiche ≥18 / ≥25 / ≥30.
- **Ghiaccio**: temperatura ≤1 °C con precipitazioni, oppure neve.
- **Spiagge** (onde anomale): onde ≥1,5 m o periodo lungo ≥12 s alzano il rischio.
- **Aurora**: Kp necessario stimato dalla latitudine (in Islanda ~2), moltiplicato per la frazione di cielo sereno nelle ore di buio.

Sono indicazioni di supporto: in caso di dubbio valgono sempre vedur.is, umferdin.is e safetravel.is.
