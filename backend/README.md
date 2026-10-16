# nordur-api

Backend per gli account di Norður (Vercel, funzioni Node + Vercel Blob privato).

- `POST /api/auth` `{mode: "register"|"login", email, password}` → `{token, userId, email}`
- `GET /api/data` → elenco documenti dell'account
- `GET|PUT|DELETE /api/data?doc=<nome>` → singolo documento `{payload, updatedAt}`
- `GET /api/health`

I documenti sono cifrati (AES-256-GCM) con una chiave derivata da `APP_SECRET`; le password sono salvate con scrypt.
Variabili richieste: `APP_SECRET`, `BLOB_READ_WRITE_TOKEN`.
