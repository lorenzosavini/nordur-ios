# nordur-api

Backend per gli account di Norður (Vercel, funzioni Node + Vercel Blob privato).

- `POST /api/auth` `{mode: "register"|"login", email, password}` → `{token, userId, email}`
- `GET /api/data` → elenco documenti dell'account
- `GET|PUT|DELETE /api/data?doc=<nome>` → singolo documento `{payload, updatedAt}`
- `GET /api/health`
- `GET /api/grid` → previsione 48 h sulla griglia della mappa (260 punti Open-Meteo, aggiornata una volta all'ora per tutti, cache CDN 1 h)

I documenti sono cifrati (AES-256-GCM) con una chiave derivata da `APP_SECRET`; le password sono salvate con scrypt.
Variabili richieste: `APP_SECRET`, `BLOB_READ_WRITE_TOKEN`.

## Pannello dell'app e funzioni a pagamento

- Pannello: `https://nordur-api.vercel.app/admin/` (utenti, Pro regalato, sospensione, cancellazione ed export GDPR, moderazione degli avvistamenti, funzioni gratis/Pro/spente, prodotti App Store, avviso nell'app, registro delle azioni).
- Variabili: `ADMIN_PASSWORD` (almeno 12 caratteri, obbligatoria per attivarlo) e `ADMIN_TOTP_SECRET` (facoltativa, base32: con questa serve anche il codice a 6 cifre di un'app di autenticazione).
- `GET /api/health?config=1` (anche `/api/config`): la configurazione pubblica letta dall'app; `POST /api/health?admin=1` (anche `/api/admin`): le azioni del pannello.
- `POST /api/auth {mode: "me", email}` (Bearer): Pro regalato e stato dell'account.
- Notifiche push degli avvisi (APNs): `APNS_KEY` (contenuto del file .p8), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` (facoltativa, default `it.lorenzosavini.nordur`). I telefoni registrano il token con `POST /api/health?device=1`.
