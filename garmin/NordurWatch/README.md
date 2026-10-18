# Norður per orologi Garmin (Connect IQ)

App per l'orologio: **raffiche** (colorate: arancione da 15 m/s, rosso da 20 m/s),
vento con direzione, temperatura e **Kp** dell'aurora (adesso / massimo nelle
prossime 24 h) dove ti trovi. L'orologio usa il proprio GPS e va online tramite
il telefono (app Garmin Connect aperta in background e Bluetooth attivo).
START (o un tocco sugli orologi touch) aggiorna, BACK esce.

## Provarla nel simulatore

1. Installa SDK Manager, VS Code ed estensione **Monkey C** (vedi la guida in chat o
   <https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/>).
2. In VS Code: **File › Apri cartella…** e scegli questa cartella `garmin/NordurWatch`
   (quella che contiene `manifest.xml`).
3. Palette dei comandi (**Cmd+Shift+P** su Mac, **Ctrl+Shift+P** su Windows):
   `Monkey C: Verify Installation`, poi la prima volta `Monkey C: Generate a Developer Key`.
4. **Run › Run Without Debugging** (Ctrl+F5) e scegli il modello di orologio:
   si apre il simulatore. Nel simulatore: **Settings › Set Position** per una
   posizione (es. 64.14, -21.94) e poi premi START sull'orologio.

## Installarla sul tuo orologio (senza store)

1. Se il tuo modello non è in `manifest.xml`: `Monkey C: Edit Products` e spunta il tuo orologio.
2. `Monkey C: Build for Device`, scegli l'orologio e una cartella: ottieni `NordurWatch.prg`.
3. Collega l'orologio al computer con il cavo: compare come disco (su Mac serve
   l'app *Android File Transfer* o *OpenMTP* per molti modelli).
4. Copia `NordurWatch.prg` in `GARMIN/APPS/` e scollega: l'app è nell'elenco delle attività/app.

Per pubblicarla sul Connect IQ Store: `Monkey C: Export Project` (file `.iq`)
e caricamento su <https://apps.garmin.com/developer/upload>.
