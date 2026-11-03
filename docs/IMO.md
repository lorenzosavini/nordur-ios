# vedur.is come fonte principale del meteo

> **Un solo nome.** vedur.is è il sito di Veðurstofa Íslands, l'istituto meteorologico islandese (in inglese Icelandic Met Office, IMO). Nell'app è sempre chiamato **vedur.is**.
>
> **Ordine di affidabilità** (un bollino su ogni dato meteo): 1. *vedur.is · misurato* (stazione, ultimi 10–60 min) → 2. *vedur.is · previsto* (stazione vicina e alla stessa quota) → 3. *Modello* (MET Norway, poi Open-Meteo), solo dove vedur.is non dà il dato. Una fonte più in basso non sostituisce mai un valore di una più in alto. In Meteo l'ordine visivo è lo stesso: Adesso (misurato), prossime 48 ore, 10 giorni (barra blu = vedur.is, grigia = modello), testo del meteorologo, confronto (a richiesta), mare, aria, fonti. Pagina «Da dove vengono i dati» in Impostazioni e Info.

Verificato il 3 novembre 2026 sulla documentazione ufficiale e su risposte reali del servizio.

## Fonti ufficiali

- **Guida al servizio XML**: [vedur.is › Um Veðurstofuna › Gagnaveita (XML)](https://www.vedur.is/um-vi/vefurinn/xml/).
  - Il PDF *Leiðbeiningar um notkun XML-þjónustu Veðurstofu Íslands* (17/10/2018) è in [/media/vedurstofan/XMLthjonusta.pdf](https://www.vedur.is/media/vedurstofan/XMLthjonusta.pdf).
- **Condizioni d'uso**: [vedur.is › Notkunarskilmálar](https://www.vedur.is/um-vi/vefurinn/notkunarskilmalar/).
- **Indirizzo del servizio**: `https://xmlweather.vedur.is/`. È gratuito e aperto a tutti, senza registrazione.

## Cosa dice la guida

- **Previsioni automatiche per stazione** (`type=forec`):
  - restituiscono `atime` (ora di analisi, cioè di emissione) e, per ogni passo, `ftime`;
  - le date sono nel formato `YYYY-MM-DD hh:mm:ss`, ora islandese (UTC).
  - IMO compone la previsione con più modelli (oggi `ig` e `ecm-is`, vedi `type=forec-info`) e può cambiarne la composizione, i passi e la lunghezza in qualsiasi momento, senza avvisare. L'app quindi legge orizzonte e passi da ogni risposta.
- **Osservazioni** (`type=obs`):
  - `time=1h` restituisce l'ultima misura oraria;
  - le stazioni automatiche misurano ogni ora, quelle con personale ogni 3 ore;
  - `anytime=1` restituisce l'ultima misura disponibile, anche più vecchia.
- **Grandezze** (`params`):

  | Codice | Grandezza |
  |---|---|
  | `F` | vento medio (m/s) |
  | `FX` | vento massimo |
  | `FG` | raffica massima |
  | `D` | direzione |
  | `T` | temperatura (°C) |
  | `W` | tempo, in testo |
  | `V` | visibilità |
  | `N` | nuvolosità (%) |
  | `P` | pressione (hPa) |
  | `RH` | umidità (%) |
  | `TD` | punto di rugiada |
  | `R` | precipitazione (mm) |
  | `SND`, `SNC` | neve |
  | `SED` | mare |
  | `RTE` | temperatura della strada |

  Non tutte compaiono nelle previsioni automatiche.
- **Errori**: una stazione senza dati ha `valid="0"` e un messaggio in `err`.
- **Frequenza**: non scaricare troppo spesso; gli indirizzi IP che caricano troppo i server possono essere bloccati.

## Cosa risponde davvero (3/11/2026)

**Previsione** per Reykjavík (stazione 1), Höfn (5544) e altre, chiedendo `params=F;D;T;W;N;R;TD`:

- **Campi presenti:** `F`, `D`, `T`, `W`, `N`, `R`, `TD`.
- **Campi assenti:** `FG` (raffiche), `FX`, `P`, `RH`, `V`. IMO non li fornisce nella previsione, anche se chiesti.
- **Passi:**
  - orari per circa 72 ore (71 passi);
  - poi ogni 3 ore fino a circa 5,5 giorni;
  - poi ogni 6 ore fino a circa 9,5 giorni.
  - In tutto 108 passi, con emissione alle 12:00 e ultimo passo il 13/11 alle 00:00.
- **`R`:** è la quantità caduta nel passo. Nei passi da 3 o 6 ore l'app la divide sulle ore del passo; i valori reali sono coerenti con il testo («Light rain» = 2,4 mm in 6 ore).

**Osservazione** (`time=1h`):

- **Campi:** `F`, `FX`, `FG` (raffica dell'ultima ora), `D`, `T`, `P`, `RH`, `R`, `TD`.
- **Formato:** i decimali possono usare la virgola (`7,1`).

## Condizioni d'uso

I dati sono liberi da usare, anche per fini commerciali. Valgono tre condizioni:

- va citata la fonte, cioè da dove e quando sono stati scaricati;
- va tenuto chiaro cosa viene da Veðurstofa Íslands e cosa da altri;
- IMO non garantisce disponibilità né accuratezza.

L'app cita sempre la fonte:

- **Meteo:** fonte, stazione, ora di emissione, orizzonte e ora del download («Aggiornato …»).
- **Oggi:** «Veðurstofa Íslands · stazione».
- **Osservazione:** stazione e ora della misura.
- **Percorso:** «IMO · stazione» o «Modelli» per ogni punto.
- **Tappe:** «Fonte: …».

## Come lo usa Norður

1. **Scelta della stazione** (`IMOForecast.candidates`).
   - Una stazione rappresenta un luogo solo se è entro 25 km e con meno di 200 m di dislivello, oppure fino a 35 km con meno di 100 m.
   - Si sceglie quella con il punteggio migliore: distanza + dislivello/20.
   - La quota del luogo arriva da Open-Meteo, quella delle stazioni dal modello del terreno Copernicus (Open-Meteo Elevation, già salvata in `imo-stations.json`).
   - In Islanda costa ed entroterra differiscono soprattutto per quota: fiordi, valli, altopiani.
   - Senza la quota del luogo conta solo la distanza (25 km).
   - Oltre questi limiti, per esempio negli Altopiani, valgono i modelli.
2. **Previsione** (`WeatherService.official`). Per tutto l'orizzonte della previsione IMO:
   - **Da IMO:** temperatura, vento medio, direzione, tempo, nuvolosità e precipitazione.
   - **Interpolazione oraria:** temperatura, vento e nuvole tra un passo e l'altro; direzione dal passo più vicino; tempo del passo a cui appartiene l'ora; pioggia del passo divisa per le sue ore.
   - **Temperatura percepita:** quella dei modelli, spostata della stessa differenza di temperatura.
   - **Raffiche:** IMO non le dà. Restano quelle dei modelli, mai sotto il vento medio IMO.
   - **Dai modelli (MET Norway, poi Open-Meteo):** probabilità di pioggia, nuvole basse, medie e alte, nebbia, visibilità, neve in cm, CAPE. Si usano anche dopo l'orizzonte IMO, se nessuna stazione è adatta o se vedur.is non risponde.
   - I modelli non sovrascrivono mai un valore IMO.
3. **Adesso**: l'osservazione della stazione più vicina (entro 30 km, misura delle ultime 2 ore), mostrata in Oggi e in Meteo.
   - Mostra vento medio e direzione, raffica misurata, temperatura e ora.
4. **Dove vale la previsione combinata**: Oggi, Meteo (con il confronto IMO e MET ora per ora), tappe del viaggio, avvisi di vento sulle tappe e dove sei, widget Condizioni e Tappa di oggi, Live Activity (tramite gli avvisi), e lungo il percorso. Sul percorso ogni punto usa la stazione adatta, con una sola richiesta ogni 20 stazioni.
5. **Cache**:
   - previsioni 20 minuti, osservazioni 10 minuti;
   - la copia salvata resta disponibile offline, come per gli altri servizi.
6. **Test**: `Tests/EngineTests/main.swift` verifica parsing, interpolazione e scelta della stazione su campioni reali del 3/11/2026.

## Tutto il resto che vedur.is pubblica (Parte 6, 3/11/2026)

Oltre a previsioni per stazione, allerte (CAP) e terremoti, l'app ora usa:

| Dato | Fonte | Dove nell'app | Aggiornamento |
|---|---|---|---|
| **Previsioni scritte dai meteorologi**: Islanda (36 ore e prossimi giorni, con la tendenza), area della capitale, le 10 regioni (30–39: Miðhálendið … Suðausturland), situazione generale, 9 zone di mare (51–59) | `xmlweather.vedur.is/?type=txt` | Meteo: il testo della regione del luogo; pagina «Previsioni dei meteorologi» con tutti i testi | 30 min |
| **Osservazione oraria completa**: anche `FX` (vento massimo dell'ora), `TD`, e nelle stazioni con personale `W`, `V` (visibilità), `N` (nuvolosità), `SND`/`SNC` (neve e suolo), `SED` (mare) | `xmlweather.vedur.is/?type=obs` | Blocco «Adesso» in Oggi e Meteo | 10 min |
| **Misure ogni 10 minuti** delle stazioni automatiche (vento, raffica, temperatura, umidità, rugiada, pressione) | `api.vedur.is/weather/observations/aws/10min/latest` | Blocco «Adesso» (le più recenti vincono, il resto dall'osservazione oraria) | 5 min |
| **Umidità prevista**: dalla temperatura e dal punto di rugiada IMO (formula di Magnus) | previsione per stazione (`T`, `TD`) | «Adesso» delle previsioni | — |
| **Stato dei vulcani**: livello di allerta IMO (VALS), codice colore per l'aviazione (VONA), dal quando, e il bollettino settimanale | `api.vedur.is/volcanoes` (`/volcanoes`, `/vwr`) tramite nordur-api `/api/volcanoes` (i bollettini sono 1 MB: il server li riduce a ~10 KB); senza server, direttamente `api.vedur.is` (solo i codici) | Vulcani e terremoti: «Stato dei vulcani» | 30 min |

- **Regione del luogo:** ogni stazione di `imo-stations.json` ha il campo `area`, preso dal link ufficiale della stazione su vedur.is (`/areas/<regione>/`). Il luogo prende la regione della stazione più vicina entro 60 km.
- **Lingua:** i testi di Islanda, prossimi giorni e situazione generale partono dalla versione inglese scritta da IMO (testi 7, 27, 42). Regioni e mare esistono solo in islandese e vengono tradotti dal servizio di traduzione di nordur-api. I nomi dei luoghi non vengono tradotti.

### Cosa di vedur.is resta fuori, e perché

- **`RTE` (temperatura della strada):** è sempre vuoto nelle stazioni IMO; le stazioni stradali sono di Vegagerðin e l'app le mostra già nella sezione Strade.
- **Dispersione dei gas (`api.vedur.is/dispersion`):** le simulazioni pubbliche sono scenari tecnici, senza una previsione per località utilizzabile in automatico. Resta il link alla previsione dei gas vulcanici.
- **Ghiacciai (`/glaciers`), GIS, EPOS, Meteoalarm:** dati scientifici (bilancio di massa, fronti glaciali, sismologia grezza) o un doppione delle allerte CAP già mostrate.
- **Dati storici (`/rodeo`, medie mensili e annuali):** non servono a chi viaggia.

## Aggiornamento a ogni pubblicazione e mappa corretta (Parte 7)

### Quanto spesso pubblica IMO (verificato il 3/11/2026)

- **Previsioni per stazione:** circa ogni 3 ore, qualche ora dopo l'ora di analisi. Alle 19:44 l'ultima era quella delle 15:00, che combina i modelli `ig` (15:00) ed `ecm-is` (12:00).
- **Testi:** più volte al giorno, ognuno a orari suoi.
- **Osservazioni:** ogni ora, più le misure ogni 10 minuti delle stazioni automatiche, disponibili circa 4 minuti dopo.

### Come l'app segue i cambiamenti

1. nordur-api `/api/live` controlla al massimo una volta al minuto, per tutti gli utenti, quattro dati di vedur.is con richieste minime:
   - ora di emissione delle previsioni per stazione;
   - ora dell'ultima osservazione oraria;
   - ora dell'ultima misura a 10 minuti;
   - un'impronta delle ore di scrittura dei testi.

   Restituisce questi dati e la versione della griglia della mappa.
2. Con l'app aperta, ogni minuto l'app legge `/api/live` (`AppModel.followIMO`) e ricarica solo ciò che è cambiato:
   - nuova emissione → previsione del luogo;
   - nuova misura → blocco «Adesso»;
   - nuovi testi → previsioni dei meteorologi;
   - nuova griglia → mappa.

   Dopo una ricarica aggiorna anche avvisi e widget.
3. Ogni risposta salvata sul telefono ricorda con quale emissione è stata scaricata (`IMOLive.useCached`).
   - Finché vedur.is non pubblica niente di nuovo, si usa la copia salvata, fino a 6 ore.
   - Appena pubblica, la copia viene scartata.
   - Se `/api/live` non risponde, valgono i tempi di prima: 20 minuti per le previsioni, 10 per le osservazioni, 30 per i testi.
4. **Vulcani:** codici controllati ogni 5 minuti sul server, bollettino settimanale ogni ora.

### Mappa: modelli corretti con le stazioni IMO

vedur.is non pubblica la griglia del suo modello in formato aperto. La mappa resta quindi la griglia Open-Meteo (0,3° × 0,6°, 48 ore), ma corretta sul server (`backend/lib/blend.js`) ogni volta che cambia una delle sue fonti:

- **Previsione:** per ogni ora e ogni stazione IMO si calcola la differenza tra IMO e il modello in quel punto, per vento medio, direzione, temperatura, nuvolosità e pioggia.
- **Diffusione:** la differenza si applica ai punti della griglia rappresentati dalla stazione:
  - peso pieno fino a 30 km, nullo oltre 60 (vedur.is come base: il modello resta da solo solo dove nessuna stazione arriva, zone velate sulla mappa);
  - peso pieno fino a 100 m di dislivello, nullo oltre 300;
  - più stazioni vicine si mediano.
- **Ora attuale:** si usano le misure degli ultimi 10 minuti (vento, raffica, direzione, temperatura), non più vecchie di 30 minuti. Nelle 3 ore successive sfumano nella previsione.
- **Raffiche:** quelle del modello, corrette con la raffica misurata per l'ora attuale e mai sotto il vento medio corretto (stessa regola della sezione Meteo).
- **Neve:** solo modello.
- **Limiti di sicurezza:**
  - differenze limitate (temperatura ±6 °C, vento ±8 m/s, raffica ±10 m/s, nuvole ±60%, pioggia ±3 mm/h);
  - il vento corretto resta almeno il 40% di quello del modello, così una stazione riparata non calma un'intera cella di 30 km.
- **Sulla mappa:**
  - i punti delle stazioni IMO mostrano il loro valore all'ora scelta: misurato adesso, previsto dopo;
  - toccando la mappa, la scheda mostra la stazione IMO più vicina entro 25 km;
  - la fonte compare come «Modelli corretti con Veðurstofa Íslands», con l'ora delle misure e dell'emissione.
- **Test:** `backend/test/blend.test.mjs`. Il 3/11/2026 alle 19:52 la correzione ha usato 244 stazioni e modificato 173 dei 260 punti.

## Notifiche: da cosa partono

| Avviso | Fonte, in ordine di affidabilità |
|---|---|
| **Allerte meteo** (gialla/arancione/rossa) | vedur.is: dove sei, alle tappe nei giorni in cui ci sarai, nei luoghi seguiti. |
| **Raffiche forti vicino a te** | Raffiche **misurate**: stazioni vedur.is (ogni 10 minuti, misure non più vecchie di 30 minuti) e stazioni stradali Vegagerðin, entro il raggio scelto. Vale la più forte oltre la soglia; l'avviso dice da quale rete viene. |
| **In arrivo a una tappa** (nuovo) | Quando sei a 2–30 km da una tappa di oggi, una volta al giorno per tappa. Contiene la misura vedur.is più vicina alla tappa, vento e raffiche delle prossime 3 ore (previsione vedur.is, altrimenti modello, indicato) e l'allerta in corso lì. |
| **Vento, pioggia, neve sui tratti del viaggio e dove sei** | Previsione per ogni punto: vedur.is dove c'è una stazione adatta, modello altrove. Le previsioni salvate dagli avvisi vengono riscaricate appena vedur.is emette una nuova previsione, altrimenti ogni 30 minuti. |
| **Strade, terremoti, SafeTravel, aurora, voli, traghetto, pedaggi** | Vegagerðin, vedur.is, SafeTravel, NOAA/GFZ/NASA, Isavia, Herjólfur, fonti ufficiali dei pedaggi. |
