<?php
// E-mail sending for the launch list: the hosting's mail() or a mailbox by
// SMTP (SSL on 465, STARTTLS on 587), no libraries needed.

function nordur_mailer(array $c): ?string {
    if (($c['mail_transport'] ?? '') === 'smtp' && !empty($c['smtp_host']) && !empty($c['smtp_user'])) return 'smtp';
    if (($c['mail_transport'] ?? '') === 'mail' && function_exists('mail')) return 'mail';
    return null;
}

function nordur_header_encode(string $s): string {
    return preg_match('/[^\x20-\x7e]/', $s) ? '=?UTF-8?B?' . base64_encode($s) . '?=' : $s;
}

/** "Name <addr>" -> [name, addr] */
function nordur_parse_from(string $from): array {
    if (preg_match('/^\s*(.*?)\s*<([^>]+)>\s*$/', $from, $m)) return [trim($m[1], '" '), $m[2]];
    return ['', trim($from)];
}

function nordur_message(array $c, string $to, string $subject, string $text, string $html, array &$headersOut): string {
    [$fromName, $fromAddr] = nordur_parse_from($c['mail_from'] ?? '');
    $boundary = 'nordur_' . bin2hex(random_bytes(8));
    $domain = substr(strrchr($fromAddr, '@') ?: '@localhost', 1);
    $headersOut = [
        'From' => ($fromName !== '' ? nordur_header_encode($fromName) . ' ' : '') . "<$fromAddr>",
        'Reply-To' => $c['mail_reply_to'] ?: $fromAddr,
        'MIME-Version' => '1.0',
        'Content-Type' => "multipart/alternative; boundary=\"$boundary\"",
        'Message-ID' => '<' . bin2hex(random_bytes(12)) . "@$domain>",
        'Date' => date(DATE_RFC2822),
        'X-Mailer' => 'Norður',
    ];
    $part = fn($type, $body) => "--$boundary\r\nContent-Type: $type; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
        . rtrim(chunk_split(base64_encode($body), 76, "\r\n")) . "\r\n";
    return $part('text/plain', $text) . $part('text/html', $html) . "--$boundary--\r\n";
}

function nordur_send_mail(array $c, string $to, string $subject, string $text, string $html): bool {
    $mailer = nordur_mailer($c);
    if (!$mailer) return false;
    $headers = [];
    $body = nordur_message($c, $to, $subject, $text, $html, $headers);
    if ($mailer === 'mail') {
        $h = '';
        foreach ($headers as $k => $v) $h .= "$k: $v\r\n";
        [, $fromAddr] = nordur_parse_from($c['mail_from'] ?? '');
        return @mail($to, nordur_header_encode($subject), $body, rtrim($h), "-f$fromAddr");
    }
    try {
        nordur_smtp($c, $to, $subject, $body, $headers);
        return true;
    } catch (Throwable $e) {
        error_log('nordur smtp: ' . $e->getMessage());
        return false;
    }
}

function nordur_smtp(array $c, string $to, string $subject, string $body, array $headers): void {
    $port = (int)($c['smtp_port'] ?? 465);
    $host = $c['smtp_host'];
    // 'ssl' (usually port 465) or 'tls' = STARTTLS (usually 587)
    $ssl = ($c['smtp_secure'] ?? ($port === 465 ? 'ssl' : 'tls')) === 'ssl';
    $verify = ($c['smtp_verify'] ?? true) !== false;
    $ctx = stream_context_create(['ssl' => ['verify_peer' => $verify, 'verify_peer_name' => $verify, 'allow_self_signed' => !$verify, 'SNI_enabled' => true, 'peer_name' => $host]]);
    $fp = @stream_socket_client(($ssl ? 'ssl://' : 'tcp://') . "$host:$port", $errno, $errstr, 15, STREAM_CLIENT_CONNECT, $ctx);
    if (!$fp) throw new RuntimeException("connect $errstr");
    stream_set_timeout($fp, 20);
    $read = function () use ($fp) {
        $out = '';
        while (($line = fgets($fp, 1024)) !== false) {
            $out .= $line;
            if (strlen($line) < 4 || $line[3] === ' ') break;
        }
        return $out;
    };
    $cmd = function (string $line, array $ok) use ($fp, $read) {
        if ($line !== '') fwrite($fp, $line . "\r\n");
        $r = $read();
        if (!in_array((int)substr($r, 0, 3), $ok, true)) throw new RuntimeException(trim(preg_replace('/AUTH.*/', 'AUTH', $line)) . ' -> ' . trim($r));
        return $r;
    };
    $me = $_SERVER['SERVER_NAME'] ?? 'localhost';
    $cmd('', [220]);
    $cmd("EHLO $me", [250]);
    if (!$ssl) {
        $cmd('STARTTLS', [220]);
        if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) throw new RuntimeException('starttls');
        $cmd("EHLO $me", [250]);
    }
    $cmd('AUTH LOGIN', [334]);
    $cmd(base64_encode($c['smtp_user']), [334]);
    $cmd(base64_encode($c['smtp_pass'] ?? ''), [235]);
    [, $fromAddr] = nordur_parse_from($c['mail_from'] ?? $c['smtp_user']);
    $cmd("MAIL FROM:<$fromAddr>", [250]);
    $cmd("RCPT TO:<$to>", [250, 251]);
    $cmd('DATA', [354]);
    $h = "To: <$to>\r\nSubject: " . nordur_header_encode($subject) . "\r\n";
    foreach ($headers as $k => $v) $h .= "$k: $v\r\n";
    // Dot-stuffing: a line starting with "." gets a second one.
    $data = preg_replace('/^\./m', '..', $h . "\r\n" . $body);
    fwrite($fp, $data . "\r\n.\r\n");
    $cmd('', [250]);
    @fwrite($fp, "QUIT\r\n");
    fclose($fp);
}
