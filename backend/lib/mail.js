// Account e-mails (welcome, sign-in, password reset code, password changed,
// recovery code renewed, account deleted).
//
// Two ways to send, whichever is configured in the project's environment:
//   RESEND_API_KEY (+ MAIL_FROM, a sender on a domain verified at resend.com)
//   SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS (+ MAIL_FROM) — any SMTP
//     server: Gmail with an app password, Brevo, Mailgun, iCloud…
// Without either, nothing is sent and the endpoints keep working (password
// recovery then relies on the recovery code shown at sign-up).

const FROM = process.env.MAIL_FROM || (process.env.SMTP_USER ? `Norður <${process.env.SMTP_USER}>` : "Norður <onboarding@resend.dev>");

export const mailer = process.env.RESEND_API_KEY ? "resend" : process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS ? "smtp" : null;

let transport = null;
async function smtp() {
  if (!transport) {
    const { default: nodemailer } = await import("nodemailer");
    const port = Number(process.env.SMTP_PORT || 465);
    transport = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port,
      secure: port === 465,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
      connectionTimeout: 10000,
    });
  }
  return transport;
}

/** Sends one message; returns false (and logs) instead of throwing. */
export async function sendMail({ to, subject, text, html }) {
  if (!mailer) return false;
  try {
    if (mailer === "resend") {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: FROM, to: [to], subject, text, html }),
        signal: AbortSignal.timeout(10000),
      });
      if (!res.ok) throw new Error(`resend ${res.status}: ${(await res.text()).slice(0, 200)}`);
    } else {
      await (await smtp()).sendMail({ from: FROM, to, subject, text, html });
    }
    return true;
  } catch (e) {
    console.error("mail", e.message);
    return false;
  }
}

const escape = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

function layout(title, paragraphs, code) {
  const body = paragraphs.map((p) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.5;color:#1d232b">${escape(p)}</p>`).join("");
  const codeBlock = code
    ? `<p style="margin:6px 0 20px;font:700 30px/1.2 ui-monospace,Menlo,monospace;letter-spacing:6px;color:#0b1015;background:#eef3f7;padding:14px 18px;display:inline-block">${escape(code)}</p>`
    : "";
  return `<!doctype html><html><body style="margin:0;background:#f4f6f8;font-family:-apple-system,Helvetica,Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:28px 14px">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-top:4px solid #2ec4a6"><tr><td style="padding:26px 26px 18px">
<p style="margin:0 0 18px;font:700 13px/1 ui-monospace,Menlo,monospace;letter-spacing:3px;color:#2ec4a6">NORÐUR</p>
<h1 style="margin:0 0 16px;font-size:22px;line-height:1.25;color:#0b1015">${escape(title)}</h1>
${body}${codeBlock}
</td></tr></table>
<p style="max-width:520px;margin:14px auto 0;font-size:12px;line-height:1.5;color:#6b7680">Norður · ${escape(TEXT.footer)}</p>
</td></tr></table></body></html>`;
}

const TEXT = { footer: "Iceland weather, roads and aurora / Meteo, strade e aurora in Islanda" };

const MESSAGES = {
  it: {
    welcome: () => ["Benvenuto in Norður", [
      "Il tuo account è stato creato. Viaggio, percorsi e impostazioni vengono salvati e cifrati, e li ritrovi su un nuovo iPhone accedendo con questa email.",
      "Conserva il codice di recupero che l'app ti ha mostrato: serve se dimentichi la password e l'email non arriva.",
      "Se non hai creato tu questo account, ignora questa email.",
    ]],
    login: (when) => ["Nuovo accesso al tuo account", [
      `È stato effettuato l'accesso al tuo account Norður (${when}).`,
      "Se sei stato tu non devi fare nulla. Se non lo riconosci, apri l'app e cambia subito la password.",
    ]],
    resetCode: (code) => ["Codice per reimpostare la password", [
      "Hai chiesto di reimpostare la password di Norður. Inserisci questo codice nell'app: vale 15 minuti.",
    ], code],
    resetDone: (when) => ["Password reimpostata", [
      `La password del tuo account è stata reimpostata (${when}). Le sessioni sugli altri dispositivi restano valide finché non esci.`,
      "Se non sei stato tu, reimposta subito la password dall'app.",
    ]],
    changed: (when) => ["Password cambiata", [
      `La password del tuo account Norður è stata cambiata (${when}).`,
      "Se non sei stato tu, reimposta subito la password dall'app con «Password dimenticata».",
    ]],
    recovery: (when) => ["Nuovo codice di recupero", [
      `È stato generato un nuovo codice di recupero (${when}); quello precedente non vale più.`,
      "Se non sei stato tu, cambia subito la password dall'app.",
    ]],
    deleted: (when) => ["Account eliminato", [
      `Il tuo account Norður e tutti i dati salvati sul server sono stati eliminati (${when}).`,
      "Grazie per aver usato Norður. Puoi creare un nuovo account quando vuoi.",
    ]],
  },
  en: {
    welcome: () => ["Welcome to Norður", [
      "Your account has been created. Your trip, routes and settings are saved encrypted, and you get them back on a new iPhone by signing in with this e-mail.",
      "Keep the recovery code the app showed you: you need it if you forget your password and the e-mail does not arrive.",
      "If you did not create this account, ignore this e-mail.",
    ]],
    login: (when) => ["New sign-in to your account", [
      `Someone signed in to your Norður account (${when}).`,
      "If it was you, there is nothing to do. If you don't recognise it, open the app and change your password now.",
    ]],
    resetCode: (code) => ["Code to reset your password", [
      "You asked to reset your Norður password. Enter this code in the app: it is valid for 15 minutes.",
    ], code],
    resetDone: (when) => ["Password reset", [
      `Your account password was reset (${when}).`,
      "If it wasn't you, reset your password from the app now.",
    ]],
    changed: (when) => ["Password changed", [
      `Your Norður account password was changed (${when}).`,
      "If it wasn't you, reset it from the app now with “Forgot password”.",
    ]],
    recovery: (when) => ["New recovery code", [
      `A new recovery code was generated (${when}); the previous one no longer works.`,
      "If it wasn't you, change your password from the app now.",
    ]],
    deleted: (when) => ["Account deleted", [
      `Your Norður account and all the data stored on the server were deleted (${when}).`,
      "Thank you for using Norður.",
    ]],
  },
};

/** Builds and sends one of the account messages. */
export function accountMail(kind, to, lang, arg) {
  const l = lang === "en" ? "en" : "it";
  const when = new Date().toLocaleString(l === "en" ? "en-GB" : "it-IT", { timeZone: "Atlantic/Reykjavik", dateStyle: "medium", timeStyle: "short" }) + " GMT";
  const [title, paragraphs, code] = MESSAGES[l][kind](kind === "resetCode" ? arg : when);
  const text = [title, "", ...paragraphs, ...(code ? ["", code] : []), "", "— Norður"].join("\n");
  return sendMail({ to, subject: code ? `${title}: ${code}` : title, text, html: layout(title, paragraphs, code) });
}
