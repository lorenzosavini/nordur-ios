<?php
// Copy this file to config.php (same folder) and fill it in with the data of
// your hosting. config.php is never published by the automatic deploy and
// never committed: the passwords stay on the hosting.
return [
    // Database (phpMyAdmin shows the name; host is usually "localhost")
    'db_host' => 'localhost',
    'db_name' => 'nome_database',
    'db_user' => 'utente_database',
    'db_pass' => 'password_database',

    // Public address of the site, without the final slash
    'site_url' => 'https://www.tuodominio.it',

    // E-mails: sender address (a mailbox of your domain works best)
    'mail_from'      => 'Norður <noreply@tuodominio.it>',
    'mail_reply_to'  => '',
    // 'mail' uses the hosting's PHP mail(); 'smtp' a mailbox of your domain
    'mail_transport' => 'smtp',
    'smtp_host'      => 'smtp.tuodominio.it',
    'smtp_port'      => 465,          // 465 = SSL, 587 = STARTTLS
    'smtp_secure'    => 'ssl',        // 'ssl' or 'tls' (STARTTLS)
    'smtp_user'      => 'noreply@tuodominio.it',
    'smtp_pass'      => 'password_casella',
];
