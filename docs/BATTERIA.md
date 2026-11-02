# Batteria durante la registrazione guida

Scelte in `Nordur/State/DriveRecorder.swift`, verificate per il field test (6–13 novembre).

## GPS

| | Normale | Risparmio batteria |
|---|---|---|
| `desiredAccuracy` | `kCLLocationAccuracyBest` | `kCLLocationAccuracyNearestTenMeters` |
| `distanceFilter` | 5 m | 5 m |
| `activityType` | `.automotiveNavigation` | uguale |
| `pausesLocationUpdatesAutomatically` | `false` | `false` |

- **Best, non BestForNavigation.** `BestForNavigation` fonde altri sensori ed è pensato per un telefono sotto carica; per la traccia bastano pochi metri. `DriveMath` scarta comunque i fix peggiori di 35 m.
- **Il filtro di distanza resta 5 m in entrambe le modalità.** I fix da fermi servono a `DriveMath` per distinguere una sosta dal tempo di guida: con un filtro più largo, dopo una sosta di 10 minuti il primo fix in movimento conterebbe tutti i 10 minuti come guida. I fix a meno di 10 m dall'ultimo non vengono salvati, quindi 5 m non aggiunge punti alla traccia.
- **Niente pausa automatica.** Con `pausesLocationUpdatesAutomatically = true` iOS fermerebbe il GPS a un semaforo lungo o in coda a un traghetto e la registrazione non ripartirebbe da sola in background.
- **In background**: `allowsBackgroundLocationUpdates` + `CLBackgroundActivitySession` (pillola blu) solo durante la registrazione; spenti alla fine o con *Scarta*. In pausa il GPS è fermo (`stopUpdatingLocation`).

## Frequenze

| | Normale | Risparmio |
|---|---|---|
| Live Activity | al massimo ogni 30 s | ogni 90 s |
| Salvataggio della guida in corso (ripristino dopo un crash) | ogni 30 s | ogni 60 s |
| Strada davanti (`RoadWatch.refresh`, calcolo locale) | ogni 20 s | ogni 60 s |
| Dati stradali Vegagerðin | ogni 5 min | ogni 5 min |
| Controllo allerte | ogni 5 min | ogni 5 min |

- La Live Activity viene aggiornata **subito** quando cambia l'allerta mostrata (nuova stazione a rischio, nuova allerta), altrimenti solo allo scadere dell'intervallo **e** se qualcosa di visibile è cambiato (≥ 0,1 km, ≥ 3 km/h, prossima tappa). Il tempo trascorso sulla schermata di blocco scorre da solo (`Text(_, style: .timer)`), senza update.
- Il confronto delle allerte usa un'identità stabile (stazione + livello di rischio, o id dell'allerta), non il testo «tra N km», che cambierebbe a ogni chilometro.

## Modalità risparmio

Interruttore in *Viaggio › Guida › Auto e chilometraggio › Risparmio batteria in guida* (chiave `drive.batterySaver`). Si attiva da sola quando l'iPhone è in **Risparmio energetico** (`ProcessInfo.isLowPowerModeEnabled`, notifica `NSProcessInfoPowerStateDidChange`: il profilo cambia anche a guida in corso).

Le allerte di sicurezza (raffiche, strade chiuse, allerte IMO) non vengono rallentate: cambia solo quanto spesso si ridisegna la Live Activity e quanto spesso si ricalcola la strada davanti.

## Cosa misurare sul campo

- Percentuale di batteria persa in un'ora di guida, schermo bloccato, con e senza risparmio (Impostazioni › Batteria mostra il consumo per app).
- Che la traccia resti continua in background anche dopo soste lunghe (benzinaio, traghetto).
- Che la Live Activity mostri le allerte appena compaiono.
