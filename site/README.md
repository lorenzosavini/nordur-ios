# Sito di Norður

Sito statico (HTML, CSS, JavaScript, immagini, video e font): funziona su
qualsiasi hosting, senza PHP né database. Iscrizioni, stato del lancio e
pannello admin parlano con il server di Norður (`config.js`).

## Installazione

1. Carica tutto il contenuto di questa cartella nella cartella pubblica del
   dominio (di solito `public_html` o `www`), mantenendo le sottocartelle.
2. Apri il dominio: la landing è `index.html`, privacy e cookie `legal.html`,
   il pannello `admin/`.
3. Comunica il dominio: il server lo usa per i link nelle email (conferma e
   cancellazione), variabile `SITE_URL` del progetto nordur-api su Vercel.

## Aggiornamenti automatici

Ogni modifica alla cartella `site/` su GitHub viene pubblicata sull'hosting
dal workflow `.github/workflows/site-deploy.yml`, con le credenziali FTP/SFTP
salvate come secret del repository (vedi l'intestazione del workflow).

## File

- `index.html` landing · `legal.html` privacy e cookie · `admin/` pannello
- `config.js` indirizzo del server
- `landing/` stile, testi nelle 5 lingue (`i18n.js`), script, immagini, video, font
