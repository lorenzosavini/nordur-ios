# Installare Norður sull'iPhone

Ci sono tre strade. Le prime due sono gratuite (l'app va reinstallata ogni 7 giorni), la terza serve per usarla a lungo e distribuirla.

## A · Dal Mac con Xcode (gratis, account Apple personale)

1. Installa Xcode 26 dal Mac App Store.
2. Scarica il progetto:

   ```sh
   git clone https://github.com/lorenzosavini/nordur-ios.git
   ```

3. Apri `Nordur.xcodeproj`.
4. In Xcode › Settings › Accounts aggiungi il tuo Apple ID.
5. Seleziona il progetto, poi i target **Nordur** e **NordurWidgets**, poi la scheda *Signing & Capabilities*.
   - Spunta *Automatically manage signing*.
   - Come *Team* scegli il tuo nome (Personal Team).
   - Se il bundle ID `it.lorenzosavini.nordur` risulta occupato, cambialo in entrambi i target. Il widget deve restare `<bundle app>.widgets`.
6. Collega l'iPhone con il cavo.
   - Sull'iPhone attiva Impostazioni › Privacy e sicurezza › **Modalità sviluppatore**.
   - In Xcode scegli l'iPhone come destinazione e premi ▶︎.
7. Al primo avvio vai in Impostazioni › Generali › VPN e gestione dispositivi, e autorizza il certificato.

Con un account gratuito l'app scade dopo **7 giorni**: basta reinstallarla da Xcode. Con l'Apple Developer Program (99 €/anno) dura un anno e si può usare TestFlight.

## A2 · Senza Xcode: Sideloadly (gratis, Windows o Mac)

La CI produce a ogni commit un `.ipa` per iPhone non firmato: lo firma Sideloadly con il tuo Apple ID.

1. Scarica **Nordur.ipa**: <https://github.com/lorenzosavini/nordur-ios/raw/ci-screenshots/Nordur.ipa>
2. Installa **Sideloadly** da <https://sideloadly.io> (su Windows serve anche iTunes e iCloud nella versione dal sito Apple, non dal Microsoft Store).
3. Collega l'iPhone con il cavo, sblocca e tocca «Autorizza» su «Vuoi autorizzare questo computer?».
4. In Sideloadly trascina `Nordur.ipa`, scegli l'iPhone, scrivi il tuo Apple ID e premi **Start**. Inserisci la password dell'Apple ID quando la chiede (va solo ad Apple).
   - Se dà errore sul bundle ID, in *Advanced options* attiva **Change bundle ID** (es. `it.tuonome.nordur`).
5. Sull'iPhone:
   - Impostazioni › Generali › **VPN e gestione dispositivi** › il tuo Apple ID › **Autorizza**;
   - Impostazioni › Privacy e sicurezza › **Modalità sviluppatore** › attiva e riavvia (iOS lo chiede la prima volta).
6. Apri Norður.

Dopo 7 giorni l'app non si apre più: ripeti il punto 4 (i dati restano, se reinstalli sopra senza eliminarla). Con un account gratuito puoi avere al massimo 3 app installate così.

## B · TestFlight (Apple Developer Program)

1. Su [App Store Connect](https://appstoreconnect.apple.com) crea l'app con bundle ID `it.lorenzosavini.nordur`. Registra anche `it.lorenzosavini.nordur.widgets` in Certificates, Identifiers & Profiles.
2. In App Store Connect › Utenti e accessi › Integrazioni › **Chiavi API** crea una chiave con ruolo *App Manager* e scarica il file `.p8`.
3. Nel repository GitHub, in Settings › Secrets and variables › Actions, aggiungi questi secret:

   | Secret | Valore |
   |---|---|
   | `APPLE_TEAM_ID` | Team ID (developer.apple.com › Membership) |
   | `ASC_KEY_ID` | ID della chiave |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_PRIVATE_KEY` | contenuto del file `.p8` |

4. In GitHub › Actions › **TestFlight** › *Run workflow*: l'app viene archiviata, firmata e caricata.
5. Dopo l'elaborazione di Apple (10–30 min), installala dall'app TestFlight sull'iPhone.

## Cosa verificare sul dispositivo

Queste funzioni non si possono provare nel simulatore della CI:

1. **Posizione "Sempre"**: al primo avvio concedi "Mentre usi l'app", poi accetta "Cambia in Sempre" quando iOS lo propone. Altrimenti vai in Impostazioni › Norður › Posizione › Sempre.
2. **Allerte ad app chiusa**: chiudi l'app, spostati di qualche km (in auto) e controlla che arrivino le notifiche delle allerte vicine.
3. **Registrazione di un percorso**: avviala, blocca lo schermo e verifica la Live Activity sulla schermata di blocco e nella Dynamic Island.
4. **Account**:
   - registrati e salva il codice di recupero;
   - aggiungi una tappa, chiudi l'app;
   - disinstallala, reinstallala e accedi: la tappa deve tornare.
5. **Widget**: aggiungi i widget "Condizioni" e "Aurora" alla schermata Home.
6. **Aurora**: di sera, sotto un cielo sereno, controlla l'orizzonte del terreno e la direzione indicata. Segnala un avvistamento con "Ho visto l'aurora".
