# Veðurstofa Íslands (IMO) come fonte principale del meteo

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
