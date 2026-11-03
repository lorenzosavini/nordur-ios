# Norður

App iOS (SwiftUI, iOS 17+) per viaggiare in Islanda: meteo, allerte ufficiali, strade, aurora, terremoti, voli e traghetti, registrazione GPS dei percorsi in auto.

## Funzioni

- **Oggi**: allerte IMO per la posizione, condizioni attuali, rischio di guida nelle prossime 12 ore, aurora, strade, webcam, voli seguiti, distributori, mare, terremoti, avvisi SafeTravel.
- **Meteo**: grafici a 48 ore, previsione oraria e a 16 giorni, mare, qualità dell'aria e SO₂.
- **Mappa**: livelli vento, raffiche, pioggia, neve, nuvole, temperatura, aurora e radar; slider sulle 48 ore, particelle del vento animate, valori al tocco. Sovrapposizioni: allerte, stazioni stradali, webcam, terremoti, distributori, viaggio. Mappa Windy integrata.
- **Guida**: registrazione GPS con km, tempi, velocità, dislivello, soste, contachilometri, consumo stimato; storico ed export GPX; Live Activity. Durante la guida, stazioni e tratti sulla strada davanti (lungo il percorso se è impostata una destinazione), aggiornati ogni 5 minuti, con avvisi vocali e notifiche.
- **Viaggio**: tappe con data e mezzo; meteo e allerte per ogni tappa; per le tratte in auto, previsione lungo il percorso all'ora di passaggio.
- **Allerte**: allerte IMO, raffiche vicine, strade chiuse, terremoti, SafeTravel, aurora, voli seguiti, Herjólfur, velocità. Controlli ogni 5 minuti ad app aperta o in guida, in background con posizione «Sempre».
- **Widget**: condizioni, aurora (piccolo, medio, schermata di blocco) e «Tappa di oggi» (da → a, km, quando partire per arrivare con la luce, allerte sul percorso; un tocco apre la tappa). La tappa arriva al widget tramite l'App Group `group.it.lorenzosavini.nordur`: con un'installazione senza App Group (es. `Nordur-senza-Salute.ipa`) il widget chiede di aprire l'app.
- **Live Activity in guida**: km, velocità, prossima tappa con km rimanenti e arrivo previsto, prossimo distributore, allerta vento/strada più rilevante; schermata di blocco e Dynamic Island. Aggiornamenti parsimoniosi: vedi [docs/BATTERIA.md](docs/BATTERIA.md).
- **Piscine e sorgenti calde** (Oggi › Terra, mare, servizi, e da *Da vedere*): piscine pubbliche, bagni termali e sorgenti naturali da OpenStreetMap su mappa e in lista per distanza, filtro piscine/sorgenti, «aperto ora» solo dove OSM ha l'orario, foto, indicazioni, aggiunta al viaggio, avviso di sicurezza sulle sorgenti naturali. Nessun prezzo o affollamento inventato. Funzione `explore.baths` configurabile dal pannello admin.
- **Pedaggi, tunnel e parcheggi a pagamento** (Strade › Pedaggi e parcheggi): catalogo curato a mano solo da fonti ufficiali (Vegagerðin, Spölur, Vaðlaheiðargöng, parchi nazionali, Náttúruverndarstofnun, Skatturinn, Reykjavík), servito da `/api/tolls` e modificabile dal pannello admin (scheda *Pedaggi*) senza nuova versione; in cache per l'offline. Ogni voce mostra «verificato il …» e «prezzi indicativi». Badge € e dettaglio sulle tappe il cui percorso (Apple Mappe) passa da un pedaggio o che arrivano a un parcheggio a pagamento, riepilogo «Costi stradali del viaggio» nelle valute scelte, avvisi in guida (avvicinamento a N km, impostabile; «paga entro 24 ore» dopo il passaggio con promemoria; arrivo al parcheggio) e riga nella Live Activity. Funzione `roads.tolls`.
- **Offline**: ultima copia di ogni fonte in cache; distributori e colonnine salvati sul telefono.

## Fonti

Veðurstofa Íslands (allerte CAP, terremoti), Vegagerðin (condizioni stradali, stazioni, webcam), Open-Meteo (previsioni, mare, qualità dell'aria), NOAA SWPC (Kp, OVATION, vento solare), RainViewer (radar), SafeTravel.is, kefairport.com, herjolfur.is, OpenStreetMap (distributori). Nessuna chiave API.

## Installazione

Serve Xcode 26 o successivo.

1. Apri `Nordur.xcodeproj`.
2. In *Signing & Capabilities* scegli il Team per i target `Nordur` e `NordurWidgets`.
3. Collega l'iPhone, attiva la Modalità sviluppatore e premi Run.

Con un Apple ID gratuito l'app va reinstallata ogni 7 giorni.

## Verifica automatica

Ogni push su `main` compila app e widget su GitHub Actions (macOS, Xcode), avvia l'app nel simulatore, simula un tratto di guida sulla Hringvegur e pubblica gli screenshot sul branch `ci-screenshots`.

## Struttura

```
Shared/          codice comune ad app e widget (modelli, servizi, motore allerte, calcoli di guida)
Nordur/          app: stato, schermate, mappa
NordurWidgets/   widget e Live Activity
```

## Licenza

Codice visibile ma non open source: tutti i diritti riservati. Vedi [LICENSE](LICENSE) e, per font e fonti dati di terzi, [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
