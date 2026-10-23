# Sito di Norður

Landing, informativa privacy e cookie, pannello admin e API per la lista di
lancio. Serve un hosting con **PHP 7.4 o più recente** e un database
**MySQL/MariaDB** (quello che si gestisce da phpMyAdmin). Nessuna libreria da
installare.

## Installazione

1. **Database.** Dal pannello dell'hosting crea un database MySQL e il suo
   utente (molti hosting lo creano già). In phpMyAdmin apri il database e
   importa `api/schema.sql` (scheda *Importa*). Se lo salti, le tabelle
   vengono create da sole alla prima visita.
2. **File.** Carica tutto il contenuto di questa cartella nella cartella
   pubblica del dominio (`public_html`, `www` o `htdocs`), con le sottocartelle.
3. **Configurazione.** Sull'hosting, nella cartella `api/`, copia
   `config.sample.php` in `config.php` e compilalo: dati del database,
   indirizzo del sito, casella email per l'invio. `config.php` resta solo
   sull'hosting: non va su GitHub e la pubblicazione automatica non lo tocca.
4. **Admin.** Apri `https://tuodominio/admin/`: al primo accesso scegli email e
   password dell'amministratore. Poi compila *Dati del titolare* (titolare,
   email per la privacy, fornitore di hosting): solo allora il modulo della
   landing si apre.
5. **Prova le email** con *Mandala a me (prova)* nel pannello.

## Dove stanno i dati

Tutto nel database, tabelle con prefisso `nordur_`:

| Tabella | Contenuto |
|---|---|
| `nordur_leads` | iscritti: email, nome, lingua, interessi, periodo di viaggio, stato |
| `nordur_consents` | prove del consenso: testo accettato, versione informativa, data, IP abbreviato, browser, pagina |
| `nordur_events` | storico: iscrizione, conferma, email inviate, cancellazione |
| `nordur_settings` | stato del lancio e dati del titolare mostrati sul sito |
| `nordur_campaigns` | aggiornamenti inviati |
| `nordur_admins`, `nordur_sessions` | amministratori (password cifrata con hash) e accessi |
| `nordur_limits` | limite di tentativi contro gli abusi |

Chi non conferma entro 60 giorni e chi si è cancellato da più di 30 giorni
viene eliminato automaticamente.

## Aggiornamenti automatici

Ogni modifica alla cartella `site/` su GitHub viene pubblicata sull'hosting dal
workflow `.github/workflows/site-deploy.yml`, con le credenziali FTP/SFTP
salvate come *secret* del repository (vedi l'intestazione del workflow).

## File

- `index.html` landing · `legal.html` privacy e cookie · `admin/` pannello
- `api/index.php` API · `api/mail.php` invio email · `api/schema.sql` tabelle · `api/config.sample.php` modello di configurazione
- `config.js` indirizzo dell'API
- `landing/` stile, testi nelle 5 lingue (`i18n.js`), script, immagini, video, font
