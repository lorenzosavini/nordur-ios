<?php
// Norður launch list API, for PHP 7.4+ and MySQL/MariaDB (phpMyAdmin).
//
// Public
//   GET  ?lead=status                      launch status, controller's details, ready
//   POST ?lead=subscribe  {email, name, lang, interests[], travel, consentPrivacy, consentUpdates,
//                          policyVersion, consentPrivacyText, consentText, hp, elapsed}
//   GET  ?lead=confirm&t=ID.TOKEN          double opt-in, then back to the site
//   GET  ?lead=unsubscribe&t=ID.TOKEN      withdrawal, then back to the site
//   POST ?lead=forget {t}                  erase everything at once
// Admin (header X-Admin-Token from ?admin=login)
//   GET  ?admin=setup                      {needed}: no admin yet
//   POST ?admin=setup {email, password}    first admin (only while there is none)
//   POST ?admin=login {email, password}    {token}
//   POST ?admin=logout · POST ?admin=password {password, newPassword}
//   GET  ?admin=leads · GET ?admin=export (CSV) · DELETE ?admin=lead&id=
//   PUT  ?admin=status {status, legal} · POST ?admin=send {subject, text, lang, test, offset, campaign}
//   POST ?admin=reconfirm {offset} · GET ?admin=campaigns
declare(strict_types=1);

header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: strict-origin-when-cross-origin');

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) fail(503, 'not_configured');
$C = require $configFile;
require __DIR__ . '/mail.php';

const LANGS = ['it', 'en', 'de', 'fr', 'es'];
const INTERESTS = ['aurora', 'weather', 'roads', 'trip', 'drive', 'other'];
const PHASES = ['idea', 'development', 'beta', 'testflight', 'review', 'launched'];
const EMAIL_RE = '/^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/';

function fail(int $code, string $error): void { out($code, ['error' => $error]); }
function out(int $code, $body): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    if (!headers_sent() && !in_array('Cache-Control', array_map(fn($h) => explode(':', $h)[0], headers_list()), true)) header('Cache-Control: no-store');
    echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
function body(): array {
    $raw = file_get_contents('php://input') ?: '';
    $j = json_decode($raw, true);
    return is_array($j) ? $j : [];
}
function now(): string { return gmdate('Y-m-d H:i:s'); }
function iso(?string $dt): ?string { return $dt ? str_replace(' ', 'T', $dt) . 'Z' : null; }
function str($v, int $max): string { return mb_substr(trim((string)($v ?? '')), 0, $max); }

function db(): PDO {
    static $pdo = null;
    global $C;
    if ($pdo) return $pdo;
    try {
        $pdo = new PDO("mysql:host={$C['db_host']};dbname={$C['db_name']};charset=utf8mb4", $C['db_user'], $C['db_pass'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC, PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        $pdo->exec("SET time_zone = '+00:00'");
    } catch (Throwable $e) {
        error_log('nordur db: ' . $e->getMessage());
        fail(503, 'database');
    }
    // First request: the tables are created if they are not there yet.
    if (!$pdo->query("SHOW TABLES LIKE 'nordur_limits'")->fetch()) {
        foreach (array_filter(array_map('trim', explode(';', preg_replace('/^--.*$/m', '', file_get_contents(__DIR__ . '/schema.sql'))))) as $sql) $pdo->exec($sql);
    }
    return $pdo;
}
function q(string $sql, array $p = []): PDOStatement { $s = db()->prepare($sql); $s->execute($p); return $s; }

/** IPv4 without the last block, IPv6 without the last 80 bits: enough as proof, not enough to point at a device. */
function short_ip(): string {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    if (strpos($ip, '.') !== false) return implode('.', array_slice(explode('.', $ip), 0, 3)) . '.0';
    if (strpos($ip, ':') !== false) return implode(':', array_slice(explode(':', $ip), 0, 3)) . '::';
    return '';
}
function limited(string $what, int $max): bool {
    $k = $what . ':' . hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? '?') . __DIR__);
    $hour = intdiv(time(), 3600);
    q('INSERT INTO nordur_limits (k, hour, n) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE n = n + 1', [$k, $hour]);
    if (random_int(1, 50) === 1) q('DELETE FROM nordur_limits WHERE hour < ?', [$hour - 24]);
    return (int)q('SELECT n FROM nordur_limits WHERE k = ? AND hour = ?', [$k, $hour])->fetchColumn() > $max;
}
function esc(string $s): string { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }

// ——— Settings ———

function settings(): array {
    $s = q("SELECT k, v FROM nordur_settings WHERE k IN ('status', 'legal')")->fetchAll(PDO::FETCH_KEY_PAIR);
    $status = json_decode($s['status'] ?? '', true) ?: ['phase' => 'beta', 'progress' => 70, 'note' => new stdClass(), 'items' => [], 'updatedAt' => null, 'showCount' => false, 'appStoreUrl' => ''];
    $legal = json_decode($s['legal'] ?? '', true) ?: ['controller' => '', 'email' => '', 'address' => '', 'vat' => '', 'hosting' => ''];
    return [$status, $legal];
}
function legal_ready(array $l): bool { return !empty($l['controller']) && !empty($l['email']); }
function site_url(): string { global $C; return rtrim($C['site_url'] ?? '', '/'); }
function api_url(): string { return site_url() . '/api/index.php'; }

// ——— E-mails ———

const MAIL = [
    'it' => ["Norður: conferma l'iscrizione", ["Ciao{name},", "grazie per esserti iscritto agli aggiornamenti su Norður, l'app per viaggiare in Islanda: aurora, meteo, strade e viaggio.", "Per confermare che l'indirizzo è tuo e iniziare a ricevere le novità e l'avviso del lancio, apri il link qui sotto. Se non sei stato tu, ignora questa email: senza conferma non ti scriveremo più."], "Conferma l'iscrizione", "Ricevi questa email perché ti sei iscritto su {site}. Non vuoi più riceverle? Cancellati qui: {unsub}"],
    'en' => ["Norður: confirm your sign-up", ["Hi{name},", "thanks for signing up for updates on Norður, the app for travelling in Iceland: aurora, weather, roads and your trip.", "To confirm this address is yours and start receiving news and the launch notice, open the link below. If it wasn't you, ignore this e-mail: without confirmation we won't write again."], "Confirm sign-up", "You receive this e-mail because you signed up on {site}. Don't want them any more? Unsubscribe here: {unsub}"],
    'de' => ["Norður: Anmeldung bestätigen", ["Hallo{name},", "danke für deine Anmeldung zu den Neuigkeiten über Norður, die App für Reisen in Island: Polarlicht, Wetter, Straßen und Reise.", "Öffne den Link unten, um zu bestätigen, dass die Adresse dir gehört, und Neuigkeiten sowie die Nachricht zum Start zu erhalten. Warst du das nicht, ignoriere diese E-Mail: Ohne Bestätigung schreiben wir dir nicht mehr."], "Anmeldung bestätigen", "Du erhältst diese E-Mail, weil du dich auf {site} angemeldet hast. Keine E-Mails mehr? Hier abmelden: {unsub}"],
    'fr' => ["Norður : confirmez votre inscription", ["Bonjour{name},", "merci de vous être inscrit aux nouvelles de Norður, l'application pour voyager en Islande : aurores, météo, routes et voyage.", "Pour confirmer que cette adresse est la vôtre et recevoir les nouveautés et l'annonce du lancement, ouvrez le lien ci-dessous. Si ce n'était pas vous, ignorez cet e-mail : sans confirmation, nous ne vous écrirons plus."], "Confirmer l'inscription", "Vous recevez cet e-mail car vous vous êtes inscrit sur {site}. Vous ne souhaitez plus en recevoir ? Désinscrivez-vous ici : {unsub}"],
    'es' => ["Norður: confirma tu suscripción", ["Hola{name},", "gracias por suscribirte a las novedades de Norður, la app para viajar por Islandia: auroras, tiempo, carreteras y viaje.", "Para confirmar que la dirección es tuya y empezar a recibir novedades y el aviso del lanzamiento, abre el enlace de abajo. Si no has sido tú, ignora este correo: sin confirmación no volveremos a escribirte."], "Confirmar suscripción", "Recibes este correo porque te suscribiste en {site}. ¿Ya no quieres recibirlos? Date de baja aquí: {unsub}"],
];

function mail_layout(array $paragraphs, ?array $button, string $footer): string {
    $body = '';
    foreach ($paragraphs as $p) $body .= '<p style="margin:0 0 14px;font-size:15px;line-height:1.55;color:#0a0a0a">' . nl2br(esc($p)) . '</p>';
    $cta = $button ? '<p style="margin:8px 0 22px"><a href="' . esc($button[0]) . '" style="display:inline-block;background:#f04a00;color:#fff;text-decoration:none;font:600 14px/1 -apple-system,Helvetica,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;padding:14px 20px">' . esc($button[1]) . '</a></p>' : '';
    return '<!doctype html><html><body style="margin:0;background:#f4f4f2;font-family:-apple-system,Helvetica,Arial,sans-serif"><table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:28px 12px">'
        . '<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#fff;border-top:4px solid #0a0a0a">'
        . '<tr><td style="padding:26px 28px 6px;font:700 30px/1 \'Arial Narrow\',Arial,sans-serif;letter-spacing:.02em;text-transform:uppercase;color:#0a0a0a">Norður<span style="color:#00a37a">.</span></td></tr>'
        . "<tr><td style=\"padding:16px 28px 8px\">$body$cta</td></tr>"
        . '<tr><td style="padding:14px 28px 24px;border-top:1px solid rgba(0,0,0,.13);font-size:12px;line-height:1.5;color:#4f4f4f">' . esc($footer) . '</td></tr>'
        . '</table></td></tr></table></body></html>';
}
function link_token(array $lead): string { return $lead['id'] . '.' . $lead['token']; }
function footer_for(array $lead): string {
    $m = MAIL[$lead['lang']] ?? MAIL['en'];
    $unsub = api_url() . '?lead=unsubscribe&t=' . link_token($lead);
    return str_replace(['{site}', '{unsub}'], [preg_replace('#^https?://#', '', site_url()), $unsub], $m[3]);
}
function send_confirmation(array $lead): bool {
    global $C;
    $m = MAIL[$lead['lang']] ?? MAIL['en'];
    $href = api_url() . '?lead=confirm&t=' . link_token($lead);
    $paragraphs = array_map(fn($p) => str_replace('{name}', $lead['name'] !== '' ? ' ' . $lead['name'] : '', $p), $m[1]);
    $footer = footer_for($lead);
    return nordur_send_mail($C, $lead['email'], $m[0], implode("\n\n", $paragraphs) . "\n\n{$m[2]}: $href\n\n$footer", mail_layout($paragraphs, [$href, $m[2]], $footer));
}
function send_update(array $lead, string $subject, string $text): bool {
    global $C;
    $body = str_replace('{name}', $lead['name'] ?? '', $text);
    $footer = footer_for($lead);
    return nordur_send_mail($C, $lead['email'], $subject, "$body\n\n—\n$footer", mail_layout(preg_split('/\n{2,}/', $body), null, $footer));
}
function event(int $leadId, string $type): void { q('INSERT INTO nordur_events (lead_id, type, created_at) VALUES (?, ?, ?)', [$leadId, $type, now()]); }
function consent(int $leadId, string $type, bool $accepted, string $text = '', string $version = ''): void {
    q('INSERT INTO nordur_consents (lead_id, type, accepted, text, policy_version, ip, user_agent, source, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
        $leadId, $type, $accepted ? 1 : 0, mb_substr($text, 0, 600), mb_substr($version, 0, 40), short_ip(),
        mb_substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 300), mb_substr((string)($_SERVER['HTTP_REFERER'] ?? ''), 0, 300), now(),
    ]);
}

/** Withdrawn more than 30 days ago, or never confirmed within 60 days: erased. */
function cleanup(): void {
    q("DELETE FROM nordur_leads WHERE (erase_after IS NOT NULL AND erase_after < ?) OR (status = 'pending' AND created_at < ?)", [now(), gmdate('Y-m-d H:i:s', time() - 60 * 86400)]);
    q('DELETE FROM nordur_sessions WHERE expires_at < ?', [now()]);
}
function lead_from_token(?string $t): ?array {
    if (!preg_match('/^(\d{1,10})\.([0-9a-f]{32})$/', (string)$t, $m)) return null;
    $lead = q('SELECT * FROM nordur_leads WHERE id = ?', [(int)$m[1]])->fetch();
    return $lead && hash_equals($lead['token'], $m[2]) ? $lead : null;
}
function redirect(string $to): void { header('Cache-Control: no-store'); header("Location: $to", true, 303); exit; }

// ——— Public ———

function public_status(): void {
    global $C;
    [$status, $legal] = settings();
    $count = !empty($status['showCount']) ? (int)q("SELECT COUNT(*) FROM nordur_leads WHERE status <> 'unsubscribed'")->fetchColumn() : null;
    header('Cache-Control: public, max-age=60');
    out(200, ['status' => $status, 'legal' => $legal, 'ready' => legal_ready($legal), 'mail' => nordur_mailer($C) !== null, 'count' => $count]);
}

function subscribe(): void {
    global $C;
    $b = body();
    // Bots: a hidden field filled in, or the form sent within 2 s of opening the page.
    if (!empty($b['hp']) || ((int)($b['elapsed'] ?? 0) > 0 && (int)$b['elapsed'] < 2000)) out(200, ['ok' => true, 'status' => 'pending']);
    if (limited('subscribe', 8)) fail(429, 'too_many');
    $email = mb_strtolower(str($b['email'] ?? '', 254));
    if (!preg_match(EMAIL_RE, $email)) fail(400, 'email');
    if (($b['consentPrivacy'] ?? null) !== true || ($b['consentUpdates'] ?? null) !== true) fail(400, 'consent');
    [, $legal] = settings();
    if (!legal_ready($legal)) fail(503, 'not_ready');
    cleanup();
    $lang = in_array($b['lang'] ?? '', LANGS, true) ? $b['lang'] : 'en';
    $interests = implode(',', array_values(array_intersect(INTERESTS, is_array($b['interests'] ?? null) ? $b['interests'] : [])));
    $travel = preg_match('/^\d{4}-\d{2}$/', (string)($b['travel'] ?? '')) ? $b['travel'] : null;
    $name = str($b['name'] ?? '', 60);
    $version = str($b['policyVersion'] ?? '', 40);
    $lead = q('SELECT * FROM nordur_leads WHERE email = ?', [$email])->fetch();
    if (!$lead) {
        q('INSERT INTO nordur_leads (email, name, lang, interests, travel, status, token, created_at) VALUES (?, ?, ?, ?, ?, \'pending\', ?, ?)',
            [$email, $name, $lang, $interests, $travel, bin2hex(random_bytes(16)), now()]);
        $id = (int)db()->lastInsertId();
        event($id, 'subscribed');
    } else {
        $id = (int)$lead['id'];
        $wasOut = $lead['status'] === 'unsubscribed';
        q('UPDATE nordur_leads SET name = IF(? = \'\', name, ?), lang = ?, interests = ?, travel = ?, status = IF(status = \'unsubscribed\', \'pending\', status), unsubscribed_at = IF(status = \'pending\', NULL, unsubscribed_at), erase_after = NULL WHERE id = ?',
            [$name, $name, $lang, $interests, $travel, $id]);
        event($id, $wasOut ? 'resubscribed' : 'subscribed_again');
    }
    consent($id, 'privacy', true, str($b['consentPrivacyText'] ?? '', 600), $version);
    consent($id, 'updates', true, str($b['consentText'] ?? '', 600), $version);
    $lead = q('SELECT * FROM nordur_leads WHERE id = ?', [$id])->fetch();
    if ($lead['status'] === 'pending' && nordur_mailer($C) && send_confirmation($lead)) {
        event($id, 'confirmation_sent');
        q('UPDATE nordur_leads SET last_mail_at = ? WHERE id = ?', [now(), $id]);
    }
    out(200, ['ok' => true, 'status' => $lead['status'], 'mail' => nordur_mailer($C) !== null]);
}

function confirm_lead(): void {
    $lead = lead_from_token($_GET['t'] ?? null);
    if (!$lead) redirect(site_url() . '/?confirmed=0');
    if ($lead['status'] === 'pending') {
        q("UPDATE nordur_leads SET status = 'confirmed', confirmed_at = ? WHERE id = ?", [now(), $lead['id']]);
        consent((int)$lead['id'], 'double_opt_in', true);
        event((int)$lead['id'], 'confirmed');
    }
    redirect(site_url() . '/?confirmed=1&lang=' . $lead['lang']);
}

function unsubscribe_lead(): void {
    $t = $_GET['t'] ?? '';
    $lead = lead_from_token($t);
    if (!$lead) redirect(site_url() . '/?unsubscribed=0');
    if ($lead['status'] !== 'unsubscribed') {
        // Kept a little as proof of the withdrawal, then erased.
        q("UPDATE nordur_leads SET status = 'unsubscribed', unsubscribed_at = ?, erase_after = ? WHERE id = ?", [now(), gmdate('Y-m-d H:i:s', time() + 30 * 86400), $lead['id']]);
        consent((int)$lead['id'], 'withdrawal', false);
        event((int)$lead['id'], 'unsubscribed');
    }
    redirect(site_url() . '/?unsubscribed=1&lang=' . $lead['lang'] . '&t=' . rawurlencode($t));
}

function forget(): void {
    $lead = lead_from_token(body()['t'] ?? null);
    if (!$lead) fail(400, 'token');
    q('DELETE FROM nordur_leads WHERE id = ?', [$lead['id']]);
    out(200, ['ok' => true]);
}

// ——— Admin ———

function admin_id(): ?int {
    $token = $_SERVER['HTTP_X_ADMIN_TOKEN'] ?? '';
    if (!preg_match('/^[0-9a-f]{64}$/', $token)) return null;
    $id = q('SELECT admin_id FROM nordur_sessions WHERE token_hash = ? AND expires_at > ?', [hash('sha256', $token), now()])->fetchColumn();
    return $id ? (int)$id : null;
}
function new_session(int $adminId): string {
    $token = bin2hex(random_bytes(32));
    q('INSERT INTO nordur_sessions (token_hash, admin_id, expires_at) VALUES (?, ?, ?)', [hash('sha256', $token), $adminId, gmdate('Y-m-d H:i:s', time() + 12 * 3600)]);
    q('UPDATE nordur_admins SET last_login_at = ? WHERE id = ?', [now(), $adminId]);
    return $token;
}

function lead_rows(): array {
    $leads = q('SELECT * FROM nordur_leads ORDER BY created_at DESC')->fetchAll();
    if (!$leads) return [];
    $byId = [];
    foreach ($leads as &$l) {
        $l['id'] = (int)$l['id'];
        $l['interests'] = $l['interests'] === '' ? [] : explode(',', $l['interests']);
        $l['consents'] = [];
        $l['events'] = [];
        foreach (['created_at' => 'createdAt', 'confirmed_at' => 'confirmedAt', 'unsubscribed_at' => 'unsubscribedAt', 'erase_after' => 'eraseAfter', 'last_mail_at' => 'lastMailAt'] as $k => $n) { $l[$n] = iso($l[$k]); unset($l[$k]); }
        unset($l['token']);
        $byId[$l['id']] = &$l;
    }
    unset($l);
    foreach (q('SELECT * FROM nordur_consents ORDER BY id')->fetchAll() as $c) {
        if (isset($byId[(int)$c['lead_id']])) $byId[(int)$c['lead_id']]['consents'][] = ['type' => $c['type'], 'accepted' => (bool)$c['accepted'], 'text' => $c['text'], 'version' => $c['policy_version'], 'ip' => $c['ip'], 'ua' => $c['user_agent'], 'source' => $c['source'], 'at' => iso($c['created_at'])];
    }
    foreach (q('SELECT * FROM nordur_events ORDER BY id')->fetchAll() as $e) {
        if (isset($byId[(int)$e['lead_id']])) $byId[(int)$e['lead_id']]['events'][] = ['t' => $e['type'], 'at' => iso($e['created_at'])];
    }
    return array_values($byId);
}

function stats(array $leads): array {
    $s = ['total' => count($leads), 'status' => [], 'lang' => [], 'interests' => [], 'travel' => [], 'days' => []];
    foreach ($leads as $l) {
        $s['status'][$l['status']] = ($s['status'][$l['status']] ?? 0) + 1;
        $s['lang'][$l['lang']] = ($s['lang'][$l['lang']] ?? 0) + 1;
        foreach ($l['interests'] as $i) $s['interests'][$i] = ($s['interests'][$i] ?? 0) + 1;
        $t = $l['travel'] ?: '—';
        $s['travel'][$t] = ($s['travel'][$t] ?? 0) + 1;
        $d = substr((string)$l['createdAt'], 0, 10);
        $s['days'][$d] = ($s['days'][$d] ?? 0) + 1;
    }
    foreach (['status', 'lang', 'interests', 'travel', 'days'] as $k) $s[$k] = (object)$s[$k];
    return $s;
}

function csv(array $leads): string {
    $cell = fn($v) => '"' . str_replace('"', '""', (string)($v ?? '')) . '"';
    $rows = [implode(',', ['email', 'name', 'lang', 'status', 'created', 'confirmed', 'unsubscribed', 'interests', 'travel', 'privacy_consent_at', 'privacy_policy_version', 'updates_consent_at', 'updates_consent_text', 'consent_ip', 'double_opt_in_at', 'events'])];
    foreach ($leads as $l) {
        $last = function ($type) use ($l) { $f = array_values(array_filter($l['consents'], fn($c) => $c['type'] === $type)); return $f ? end($f) : []; };
        $p = $last('privacy'); $u = $last('updates'); $d = $last('double_opt_in');
        $rows[] = implode(',', array_map($cell, [$l['email'], $l['name'], $l['lang'], $l['status'], $l['createdAt'], $l['confirmedAt'], $l['unsubscribedAt'], implode(' ', $l['interests']), $l['travel'],
            $p['at'] ?? '', $p['version'] ?? '', $u['at'] ?? '', $u['text'] ?? '', $u['ip'] ?? '', $d['at'] ?? '', implode(' ', array_map(fn($e) => "{$e['t']}@{$e['at']}", $l['events']))]));
    }
    return "\xEF\xBB\xBF" . implode("\r\n", $rows);
}

function admin(string $what, string $method): void {
    global $C;
    if ($what === 'setup') {
        $none = !(int)q('SELECT COUNT(*) FROM nordur_admins')->fetchColumn();
        if ($method === 'GET') out(200, ['needed' => $none]);
        if (!$none) fail(403, 'already_set_up');
        $b = body();
        $email = mb_strtolower(str($b['email'] ?? '', 254));
        if (!preg_match(EMAIL_RE, $email)) fail(400, 'email');
        if (mb_strlen((string)($b['password'] ?? '')) < 10) fail(400, 'weak_password');
        q('INSERT INTO nordur_admins (email, password_hash, created_at) VALUES (?, ?, ?)', [$email, password_hash((string)$b['password'], PASSWORD_DEFAULT), now()]);
        out(200, ['token' => new_session((int)db()->lastInsertId())]);
    }
    if ($what === 'login' && $method === 'POST') {
        if (limited('login', 10)) fail(429, 'too_many');
        $b = body();
        $a = q('SELECT * FROM nordur_admins WHERE email = ?', [mb_strtolower(str($b['email'] ?? '', 254))])->fetch();
        if (!$a || !password_verify((string)($b['password'] ?? ''), $a['password_hash'])) { usleep(400000); fail(401, 'wrong'); }
        out(200, ['token' => new_session((int)$a['id'])]);
    }
    $adminId = admin_id();
    if (!$adminId) fail(401, 'session');

    if ($what === 'logout' && $method === 'POST') {
        q('DELETE FROM nordur_sessions WHERE token_hash = ?', [hash('sha256', $_SERVER['HTTP_X_ADMIN_TOKEN'])]);
        out(200, ['ok' => true]);
    }
    if ($what === 'password' && $method === 'POST') {
        $b = body();
        $a = q('SELECT * FROM nordur_admins WHERE id = ?', [$adminId])->fetch();
        if (!password_verify((string)($b['password'] ?? ''), $a['password_hash'])) fail(401, 'wrong');
        if (mb_strlen((string)($b['newPassword'] ?? '')) < 10) fail(400, 'weak_password');
        q('UPDATE nordur_admins SET password_hash = ? WHERE id = ?', [password_hash((string)$b['newPassword'], PASSWORD_DEFAULT), $adminId]);
        q('DELETE FROM nordur_sessions WHERE admin_id = ? AND token_hash <> ?', [$adminId, hash('sha256', $_SERVER['HTTP_X_ADMIN_TOKEN'])]);
        out(200, ['ok' => true]);
    }
    if ($what === 'leads' && $method === 'GET') {
        cleanup();
        $leads = lead_rows();
        [$status, $legal] = settings();
        $me = q('SELECT email FROM nordur_admins WHERE id = ?', [$adminId])->fetchColumn();
        out(200, ['leads' => $leads, 'stats' => stats($leads), 'mail' => nordur_mailer($C), 'status' => $status, 'legal' => $legal, 'site' => site_url(), 'me' => $me]);
    }
    if ($what === 'export' && $method === 'GET') {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="nordur-iscritti-' . gmdate('Y-m-d') . '.csv"');
        header('Cache-Control: no-store');
        echo csv(lead_rows());
        exit;
    }
    if ($what === 'lead' && $method === 'DELETE') {
        q('DELETE FROM nordur_leads WHERE id = ?', [(int)($_GET['id'] ?? 0)]);
        out(200, ['ok' => true]);
    }
    if ($what === 'status' && $method === 'PUT') {
        $b = body();
        [$cs, $cl] = settings();
        $s = is_array($b['status'] ?? null) ? $b['status'] : $cs;
        $note = [];
        foreach (LANGS as $l) $note[$l] = str($s['note'][$l] ?? '', 600);
        $items = [];
        foreach (array_slice(is_array($s['items'] ?? null) ? $s['items'] : [], 0, 20) as $i) {
            $label = [];
            foreach (LANGS as $l) $label[$l] = str($i['label'][$l] ?? '', 120);
            $items[] = ['label' => $label, 'done' => !empty($i['done'])];
        }
        $status = [
            'phase' => in_array($s['phase'] ?? '', PHASES, true) ? $s['phase'] : $cs['phase'],
            'progress' => max(0, min(100, (int)round((float)($s['progress'] ?? 0)))),
            'note' => $note, 'items' => $items,
            'appStoreUrl' => preg_match('#^https://apps\.apple\.com/#', (string)($s['appStoreUrl'] ?? '')) ? $s['appStoreUrl'] : '',
            'showCount' => !empty($s['showCount']), 'updatedAt' => gmdate('c'),
            // Public key of the app uploaded to Appetize: the "try it in the browser" section.
            'appetize' => preg_match('/^[A-Za-z0-9_]{8,64}$/', (string)($s['appetize'] ?? '')) ? $s['appetize'] : '',
        ];
        $l = is_array($b['legal'] ?? null) ? $b['legal'] : $cl;
        $legal = ['controller' => str($l['controller'] ?? '', 120), 'email' => preg_match(EMAIL_RE, (string)($l['email'] ?? '')) ? $l['email'] : '',
            'address' => str($l['address'] ?? '', 200), 'vat' => str($l['vat'] ?? '', 40), 'hosting' => str($l['hosting'] ?? '', 160)];
        foreach (['status' => $status, 'legal' => $legal] as $k => $v) {
            q('INSERT INTO nordur_settings (k, v, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v), updated_at = VALUES(updated_at)', [$k, json_encode($v, JSON_UNESCAPED_UNICODE), now()]);
        }
        out(200, ['ok' => true, 'status' => $status, 'legal' => $legal]);
    }
    if ($what === 'send' && $method === 'POST') {
        if (!nordur_mailer($C)) fail(503, 'no_mailer');
        $b = body();
        $subject = str($b['subject'] ?? '', 150); $text = str($b['text'] ?? '', 20000);
        if ($subject === '' || $text === '') fail(400, 'empty');
        if (!empty($b['test'])) {
            $me = q('SELECT email FROM nordur_admins WHERE id = ?', [$adminId])->fetchColumn();
            $ok = send_update(['id' => 0, 'token' => str_repeat('0', 32), 'email' => $me, 'lang' => 'it', 'name' => ''], "[TEST] $subject", $text);
            out(200, ['sent' => $ok ? 1 : 0, 'next' => null, 'total' => 1]);
        }
        $lang = in_array($b['lang'] ?? '', LANGS, true) ? $b['lang'] : 'all';
        $where = "status = 'confirmed'" . ($lang === 'all' ? '' : ' AND lang = ' . db()->quote($lang));
        $total = (int)q("SELECT COUNT(*) FROM nordur_leads WHERE $where")->fetchColumn();
        $offset = max(0, (int)($b['offset'] ?? 0));
        $campaign = (int)($b['campaign'] ?? 0);
        if (!$campaign) {
            q('INSERT INTO nordur_campaigns (subject, body, lang, total, started_at) VALUES (?, ?, ?, ?, ?)', [$subject, $text, $lang, $total, now()]);
            $campaign = (int)db()->lastInsertId();
        }
        @set_time_limit(120);
        $sent = 0;
        foreach (q("SELECT * FROM nordur_leads WHERE $where ORDER BY id LIMIT 20 OFFSET $offset")->fetchAll() as $lead) {
            if (send_update($lead, $subject, $text)) {
                $sent++;
                event((int)$lead['id'], "mail:$campaign");
                q('UPDATE nordur_leads SET last_mail_at = ? WHERE id = ?', [now(), $lead['id']]);
            }
        }
        $next = $offset + 20 < $total ? $offset + 20 : null;
        q('UPDATE nordur_campaigns SET sent = sent + ?, finished_at = ? WHERE id = ?', [$sent, $next === null ? now() : null, $campaign]);
        out(200, ['sent' => $sent, 'next' => $next, 'total' => $total, 'campaign' => $campaign]);
    }
    if ($what === 'reconfirm' && $method === 'POST') {
        if (!nordur_mailer($C)) fail(503, 'no_mailer');
        $offset = max(0, (int)(body()['offset'] ?? 0));
        $total = (int)q("SELECT COUNT(*) FROM nordur_leads WHERE status = 'pending'")->fetchColumn();
        @set_time_limit(120);
        $sent = 0;
        foreach (q("SELECT * FROM nordur_leads WHERE status = 'pending' ORDER BY id LIMIT 20 OFFSET $offset")->fetchAll() as $lead) {
            if (send_confirmation($lead)) { $sent++; event((int)$lead['id'], 'confirmation_sent'); }
        }
        out(200, ['sent' => $sent, 'next' => $offset + 20 < $total ? $offset + 20 : null, 'total' => $total]);
    }
    if ($what === 'campaigns' && $method === 'GET') {
        $rows = q('SELECT id, subject, lang, total, sent, started_at, finished_at FROM nordur_campaigns ORDER BY id DESC LIMIT 100')->fetchAll();
        out(200, ['campaigns' => array_map(fn($c) => ['id' => (int)$c['id'], 'subject' => $c['subject'], 'lang' => $c['lang'], 'total' => (int)$c['total'], 'sent' => (int)$c['sent'], 'startedAt' => iso($c['started_at']), 'finishedAt' => iso($c['finished_at'])], $rows)]);
    }
    fail(404, 'unknown');
}

// ——— Router ———

try {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    if (isset($_GET['lead'])) {
        $lead = (string)$_GET['lead'];
        if ($lead === 'status') public_status();
        if ($lead === 'subscribe' && $method === 'POST') subscribe();
        if ($lead === 'confirm') confirm_lead();
        if ($lead === 'unsubscribe') unsubscribe_lead();
        if ($lead === 'forget' && $method === 'POST') forget();
    }
    if (isset($_GET['admin'])) admin((string)$_GET['admin'], $method);
    fail(404, 'unknown');
} catch (Throwable $e) {
    error_log('nordur: ' . $e->getMessage());
    fail(500, 'server');
}
