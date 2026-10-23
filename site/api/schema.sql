-- Norður · launch list database (MySQL 5.7+ / MariaDB 10.3+).
-- Import in phpMyAdmin (Importa) into the database chosen for the site.
-- The API also creates any missing table by itself at the first request.

CREATE TABLE IF NOT EXISTS nordur_leads (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  email           VARCHAR(254) NOT NULL,
  name            VARCHAR(60)  NOT NULL DEFAULT '',
  lang            CHAR(2)      NOT NULL DEFAULT 'en',
  interests       VARCHAR(120) NOT NULL DEFAULT '',
  travel          CHAR(7)      NULL,
  status          ENUM('pending','confirmed','unsubscribed') NOT NULL DEFAULT 'pending',
  token           CHAR(32)     NOT NULL,
  created_at      DATETIME     NOT NULL,
  confirmed_at    DATETIME     NULL,
  unsubscribed_at DATETIME     NULL,
  erase_after     DATETIME     NULL,
  last_mail_at    DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY email (email),
  KEY status (status),
  KEY created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Proof of consent: what was accepted, the text and policy version shown,
-- when, from which page, the IP shortened and the browser.
CREATE TABLE IF NOT EXISTS nordur_consents (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  lead_id        INT UNSIGNED NOT NULL,
  type           VARCHAR(20)  NOT NULL,
  accepted       TINYINT(1)   NOT NULL,
  text           TEXT         NULL,
  policy_version VARCHAR(40)  NOT NULL DEFAULT '',
  ip             VARCHAR(64)  NOT NULL DEFAULT '',
  user_agent     VARCHAR(300) NOT NULL DEFAULT '',
  source         VARCHAR(300) NOT NULL DEFAULT '',
  created_at     DATETIME     NOT NULL,
  PRIMARY KEY (id),
  KEY lead_id (lead_id),
  CONSTRAINT nordur_consents_lead FOREIGN KEY (lead_id) REFERENCES nordur_leads (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS nordur_events (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  lead_id    INT UNSIGNED NOT NULL,
  type       VARCHAR(40)  NOT NULL,
  created_at DATETIME     NOT NULL,
  PRIMARY KEY (id),
  KEY lead_id (lead_id),
  CONSTRAINT nordur_events_lead FOREIGN KEY (lead_id) REFERENCES nordur_leads (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Launch status and controller's details shown on the site (JSON).
CREATE TABLE IF NOT EXISTS nordur_settings (
  k          VARCHAR(40) NOT NULL,
  v          MEDIUMTEXT  NOT NULL,
  updated_at DATETIME    NOT NULL,
  PRIMARY KEY (k)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS nordur_campaigns (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  subject     VARCHAR(150) NOT NULL,
  body        MEDIUMTEXT   NOT NULL,
  lang        VARCHAR(3)   NOT NULL DEFAULT 'all',
  total       INT UNSIGNED NOT NULL DEFAULT 0,
  sent        INT UNSIGNED NOT NULL DEFAULT 0,
  started_at  DATETIME     NOT NULL,
  finished_at DATETIME     NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS nordur_admins (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  email         VARCHAR(254) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at    DATETIME     NOT NULL,
  last_login_at DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS nordur_sessions (
  token_hash CHAR(64)     NOT NULL,
  admin_id   INT UNSIGNED NOT NULL,
  expires_at DATETIME     NOT NULL,
  PRIMARY KEY (token_hash),
  KEY admin_id (admin_id),
  CONSTRAINT nordur_sessions_admin FOREIGN KEY (admin_id) REFERENCES nordur_admins (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A few sign-ups or sign-in attempts per address per hour, against scripts.
CREATE TABLE IF NOT EXISTS nordur_limits (
  k     VARCHAR(80)  NOT NULL,
  hour  INT UNSIGNED NOT NULL,
  n     INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (k, hour)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
