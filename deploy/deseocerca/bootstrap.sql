-- DeseoCerca V1 post-install bootstrap for pH7Builder 18.x
-- Run only AFTER the browser installer has created the production database
-- and deploy/deseocerca/install-spanish.sh has installed the Spanish files.
-- Review the database prefix before execution if you chose a prefix other than ph7_.

START TRANSACTION;

UPDATE ph7_settings SET settingValue = 'DeseoCerca' WHERE settingName = 'siteName';
UPDATE ph7_settings SET settingValue = 'es_ES' WHERE settingName = 'defaultLanguage';
UPDATE ph7_settings SET settingValue = 'datelove' WHERE settingName = 'defaultTemplate';
UPDATE ph7_settings SET settingValue = 'dark' WHERE settingName = 'navbarType';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'splashPage';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'usersBlock';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'profileWithAvatarSet';
UPDATE ph7_settings SET settingValue = '0' WHERE settingName = 'bgSplashVideo';
UPDATE ph7_settings SET settingValue = '24' WHERE settingName = 'numberProfileSplashPage';

-- Register Spanish in the application language selector.
INSERT INTO ph7_languages_info (langId, name, charset, active, direction, author, website, email) VALUES
('es_ES', 'Español', 'UTF-8', '1', 'ltr', 'pH7 Internationalization contributors', 'https://github.com/pH7Software/pH7-Internationalization', NULL)
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    charset = VALUES(charset),
    active = '1',
    direction = VALUES(direction);

-- Adult-only registration and launch-stage trust & safety defaults.
UPDATE ph7_settings SET settingValue = '18' WHERE settingName = 'minAgeRegistration';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'requireRegistrationAvatar';
UPDATE ph7_settings SET settingValue = '2' WHERE settingName = 'userActivationType';
UPDATE ph7_settings SET settingValue = '10' WHERE settingName = 'minPasswordLength';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'isCaptchaUserSignup';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'avatarManualApproval';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'pictureManualApproval';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'videoManualApproval';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'sendReportMail';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'disclaimer';
UPDATE ph7_settings SET settingValue = '1' WHERE settingName = 'cookieConsentBar';

-- Brand email identities. SMTP credentials stay in PH7_MAILER_DSN on the server.
UPDATE ph7_settings SET settingValue = 'noreply@deseocerca.com' WHERE settingName = 'returnEmail';
UPDATE ph7_settings SET settingValue = 'admin@deseocerca.com' WHERE settingName = 'adminEmail';
UPDATE ph7_settings SET settingValue = 'soporte@deseocerca.com' WHERE settingName = 'feedbackEmail';
UPDATE ph7_settings SET settingValue = 'DeseoCerca' WHERE settingName = 'emailName';
UPDATE ph7_settings SET settingValue = 'DeseoCerca.com' WHERE settingName = 'watermarkTextImage';

-- Disable unused/legacy community modules for the first production release.
-- The alternate cool-profile page is disabled so all profiles use the DeseoCerca safety/action layout.
UPDATE ph7_sys_mods_enabled SET enabled = '0' WHERE folderName IN (
    'affiliate', 'forum', 'note', 'blog', 'love-calculator', 'invite', 'cool-profile-page'
);

-- Keep the core social-discovery modules enabled.
UPDATE ph7_sys_mods_enabled SET enabled = '1' WHERE folderName IN (
    'picture', 'mail', 'im', 'friend', 'related-profile', 'user-dashboard', 'map'
);

-- DeseoCerca-specific lightweight account relationships.
CREATE TABLE IF NOT EXISTS ph7_members_favorites (
    profileId int(10) unsigned NOT NULL,
    favoriteId int(10) unsigned NOT NULL,
    createdAt datetime NOT NULL,
    PRIMARY KEY (profileId, favoriteId),
    KEY favoriteId (favoriteId),
    KEY favoriteCreatedAt (profileId, createdAt),
    CONSTRAINT fk_dc_favorite_owner FOREIGN KEY (profileId) REFERENCES ph7_members(profileId) ON DELETE CASCADE,
    CONSTRAINT fk_dc_favorite_target FOREIGN KEY (favoriteId) REFERENCES ph7_members(profileId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ph7_members_blocks (
    blockerId int(10) unsigned NOT NULL,
    blockedId int(10) unsigned NOT NULL,
    createdAt datetime NOT NULL,
    PRIMARY KEY (blockerId, blockedId),
    KEY blockedId (blockedId),
    KEY blockCreatedAt (blockerId, createdAt),
    CONSTRAINT fk_dc_block_owner FOREIGN KEY (blockerId) REFERENCES ph7_members(profileId) ON DELETE CASCADE,
    CONSTRAINT fk_dc_block_target FOREIGN KEY (blockedId) REFERENCES ph7_members(profileId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Recoverable deletion and inactivity lifecycle. Explicit deletion requests are
-- physically removed only after the 90-day recovery window has expired.
CREATE TABLE IF NOT EXISTS ph7_account_lifecycle (
    profileId int(10) unsigned NOT NULL,
    state enum('active','deletion_pending','inactive_deactivated') NOT NULL DEFAULT 'active',
    deleteRequestedAt datetime DEFAULT NULL,
    deleteScheduledAt datetime DEFAULT NULL,
    recoveryTokenHash char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
    inactiveDeactivatedAt datetime DEFAULT NULL,
    createdAt datetime NOT NULL,
    updatedAt datetime NOT NULL,
    PRIMARY KEY (profileId),
    UNIQUE KEY recoveryTokenHash (recoveryTokenHash),
    KEY lifecycleStateDue (state, deleteScheduledAt),
    CONSTRAINT fk_dc_lifecycle_member FOREIGN KEY (profileId) REFERENCES ph7_members(profileId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Auditable inactivity reminders. activityAnchor is the member's last successful
-- login timestamp for that inactivity cycle. A new login creates a new cycle
-- automatically while preserving the previous reminder audit trail.
CREATE TABLE IF NOT EXISTS ph7_account_lifecycle_reminders (
    profileId int(10) unsigned NOT NULL,
    reminderCode varchar(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    activityAnchor datetime NOT NULL,
    sentAt datetime NOT NULL,
    PRIMARY KEY (profileId, reminderCode, activityAnchor),
    KEY reminderSentAt (sentAt),
    CONSTRAINT fk_dc_lifecycle_reminder_member FOREIGN KEY (profileId) REFERENCES ph7_members(profileId) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Spanish-first SEO copy for the initial Peru landing page.
INSERT INTO ph7_meta_main (
    langId, pageTitle, metaDescription, metaKeywords, headline, slogan, promoText,
    metaRobots, metaAuthor, metaCopyright, metaRating, metaDistribution, metaCategory
) VALUES (
    'es_ES',
    'Personas cerca de ti',
    'Descubre perfiles de adultos en Perú, conecta de forma privada y utiliza herramientas de seguridad, bloqueo y denuncia.',
    'personas cerca, adultos peru, perfiles, comunidad, citas, lima, peru',
    'Descubre personas cerca de ti',
    'Conecta con adultos reales, con más control y privacidad.',
    'Crea tu perfil, explora personas por ubicación y empieza una conversación. Solo para mayores de 18 años.',
    'index, follow, all',
    'DeseoCerca',
    'DeseoCerca',
    'mature',
    'global',
    'dating'
) ON DUPLICATE KEY UPDATE
    pageTitle = VALUES(pageTitle),
    metaDescription = VALUES(metaDescription),
    metaKeywords = VALUES(metaKeywords),
    headline = VALUES(headline),
    slogan = VALUES(slogan),
    promoText = VALUES(promoText),
    metaAuthor = VALUES(metaAuthor),
    metaCopyright = VALUES(metaCopyright),
    metaRating = VALUES(metaRating),
    metaDistribution = VALUES(metaDistribution),
    metaCategory = VALUES(metaCategory);

COMMIT;
