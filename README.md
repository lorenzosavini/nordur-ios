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
| **Guida** | Registrazione GPS del percorso in auto, contachilometri, storico, pianificazione percorso con meteo | GPS, Apple Mappe |
| **Info & SOS** | 112, numero alternativo 599-0112, piano di viaggio SafeTravel, link a voli KEF, bus, traghetti, strade F; impostazioni notifiche; stato delle fonti | — |

### Novità della versione 1.1

| Funzione | Dettagli |
|---|---|
| **Allerte in tempo reale** | Centro allerte con storico, filtri e badge. Controlla allerte IMO (anche gialle, opzionale), raffiche sopra soglia vicino a te (stazioni stradali live), strade chiuse/impraticabili nel raggio scelto, terremoti oltre magnitudo/distanza (sempre se ≥ M4,5), avvisi SafeTravel rossi/arancioni, aurora probabile, cambi di stato/orario/gate dei voli seguiti, nuovi avvisi Herjólfur, superamento del limite di velocità. Ogni evento notifica una sola volta; le condizioni che persistono (raffiche) si riattivano dopo 3 ore. Notifiche *time-sensitive* per i livelli rischioso/pericoloso, avvisi vocali in italiano durante la guida. |
| **Quando controlla** | ogni 5 min ad app aperta · ogni 5 min durante la registrazione di un percorso (anche a schermo bloccato) · a ogni spostamento significativo con posizione «Sempre» (iOS riattiva l'app anche se chiusa) · refresh in background di iOS. |
| **Registrazione GPS in auto** | Traccia a schermo bloccato (pallino blu), filtro del rumore GPS, km percorsi, durata totale e in movimento, velocità attuale/media/massima, dislivello, quota, soste, tempo oltre il limite, **contachilometri** dell'auto (inserisci i km al ritiro del noleggio, si aggiorna a ogni percorso), carburante e costo stimati, distributore più vicino. Ripresa automatica se l'app viene chiusa durante la registrazione. Storico con km totali e per giorno, mappa colorata per velocità, grafico velocità/quota, export **GPX**. |
| **Live Activity e Dynamic Island** | Durante la guida: km, tempo, velocità, media, contachilometri e ultima allerta sulla schermata di blocco. |
| **Widget** | «Condizioni» (piccolo, medio, schermata di blocco circolare/rettangolare/in linea): temperatura, vento/raffiche colorati per rischio, allerta IMO, aurora; «Aurora stanotte». Luogo configurabile (posizione attuale o località islandesi). |
| **Meteo lungo il percorso** | Percorso Apple Mappe, previsione per ogni punto ogni 25 km **all'ora in cui ci passerai**, allerte IMO valide al passaggio, stazioni e tratti critici lungo la strada, webcam, distributori; tasto per avviare la navigazione. Disponibile dalla tab Guida e da ogni tratta del Viaggio. |
| **Webcam stradali** | ~170 siti / ~500 telecamere Vegagerðin: vicine a te nella schermata Oggi, livello sulla mappa, lungo il percorso, elenco con ricerca. |
| **Voli e traghetti** | Tabellone di Keflavík in tempo reale (partenze/arrivi, stato, gate, nastro bagagli), stella per seguire un volo; avviso del giorno di Herjólfur; link Baldur, Smyril Line, Strætó, Flybus. |
| **Offline** | «Pacchetto offline» scarica tutto prima di entrare in zone senza rete; distributori e colonnine EV (OpenStreetMap) salvati sul telefono e mostrati su mappa e in Oggi; istruzioni per le mappe offline di Apple Mappe. |

Già presenti dalla 1.0: funziona offline con l'ultima copia di ogni fonte, meteo/mare/aurora ovunque nel mondo.

## Come installarla sul tuo iPhone

Serve un Mac con **Xcode 16 o successivo** (gratuito sul Mac App Store).

1. Apri `Nordur.xcodeproj` in Xcode.
2. Seleziona il target **Nordur** → *Signing & Capabilities* → scegli il tuo **Team**
   (basta un Apple ID gratuito; con l'Apple Developer Program l'app non scade dopo 7 giorni).
   Se il bundle id `it.lorenzosavini.nordur` è già occupato, cambialo.
   Fallo per **entrambi i target**: `Nordur` e `NordurWidgets` (il widget usa il bundle id `it.lorenzosavini.nordur.widgets`).
3. Collega l'iPhone, attiva la *Modalità sviluppatore* (Impostazioni → Privacy e sicurezza) e premi ▶︎ Run.
4. Al primo avvio concedi posizione e notifiche. Per le allerte anche ad app chiusa: Info & SOS › Allerte e notifiche › «Controlli in background» e poi posizione «Sempre».

In alternativa il progetto si può rigenerare con XcodeGen: `brew install xcodegen && xcodegen generate`.

## Struttura

```
Shared/           codice comune ad app e widget
  Core/           HTTP con cache offline, date, geometria, formattazione, scala di rischio
  Models/         luoghi, tappe, percorsi GPS (DriveMath), motore allerte (AlertEngine), Live Activity
  Services/       Open-Meteo, IMO, Vegagerðin (strade + webcam), NOAA SWPC, SafeTravel,
                  voli KEF + Herjólfur, distributori OSM, meteo lungo il percorso
Nordur/           app
  App/            entry point, tab, refresh in background
  State/          AppModel, TripStore, LocationManager, AlertCenter, DriveRecorder, DriveStore, RoutePlanner
  Views/          schermate SwiftUI (Charts + MapKit)
NordurWidgets/    widget, widget aurora, Live Activity
```

## Soglie usate

- **Vento** (m/s): medio ≥10 attenzione, ≥15 rischioso, ≥20 pericoloso; raffiche ≥18 / ≥25 / ≥30.
- **Ghiaccio**: temperatura ≤1 °C con precipitazioni, oppure neve.
- **Spiagge** (onde anomale): onde ≥1,5 m o periodo lungo ≥12 s alzano il rischio.
- **Aurora**: Kp necessario stimato dalla latitudine (in Islanda ~2), moltiplicato per la frazione di cielo sereno nelle ore di buio.

Sono indicazioni di supporto: in caso di dubbio valgono sempre vedur.is, umferdin.is e safetravel.is.
