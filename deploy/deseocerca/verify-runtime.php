#!/usr/bin/env php
<?php
/**
 * Read-only DeseoCerca runtime verification for staging/production smoke tests.
 */

declare(strict_types=1);

use PH7\Framework\Mvc\Model\DbConfig;
use PH7\Framework\Mvc\Model\Engine\Db;

require __DIR__ . '/cli-bootstrap.php';

$oDb = Db::getInstance();
$aChecks = [];
$bHealthy = true;

$record = static function (string $name, bool $ok, string $detail = '') use (&$aChecks, &$bHealthy): void {
    $aChecks[$name] = [
        'ok' => $ok,
        'detail' => $detail,
    ];
    if (!$ok) {
        $bHealthy = false;
    }
};

$checkTable = static function (string $table) use ($oDb, $record): void {
    try {
        $rStmt = $oDb->query('SELECT COUNT(*) FROM' . Db::prefix($table));
        $rStmt->fetchColumn();
        Db::free($rStmt);
        $record('table:' . $table, true, 'available');
    } catch (Throwable $oException) {
        $record('table:' . $table, false, $oException->getMessage());
    }
};

foreach (['members', 'members_favorites', 'members_blocks', 'account_lifecycle', 'reports'] as $sTable) {
    $checkTable($sTable);
}

$aExpectedSettings = [
    'siteName' => 'DeseoCerca',
    'defaultLanguage' => 'es_ES',
    'defaultTemplate' => 'datelove',
    'minAgeRegistration' => '18',
    'requireRegistrationAvatar' => '1',
    'avatarManualApproval' => '1',
    'pictureManualApproval' => '1',
    'sendReportMail' => '1',
    'disclaimer' => '1',
    'cookieConsentBar' => '1',
];

foreach ($aExpectedSettings as $sSetting => $sExpected) {
    try {
        $sActual = (string)DbConfig::getSetting($sSetting);
        $record(
            'setting:' . $sSetting,
            hash_equals($sExpected, $sActual),
            'expected=' . $sExpected . '; actual=' . $sActual
        );
    } catch (Throwable $oException) {
        $record('setting:' . $sSetting, false, $oException->getMessage());
    }
}

try {
    $rStmt = $oDb->query(
        'SELECT folderName, enabled FROM' . Db::prefix('sys_mods_enabled') .
        "WHERE folderName IN ('mail','im','picture','map','related-profile','user-dashboard','affiliate','forum','note','blog','love-calculator','invite','cool-profile-page')"
    );
    $aModuleRows = $rStmt->fetchAll(PDO::FETCH_KEY_PAIR);
    Db::free($rStmt);

    $aExpectedModules = [
        'mail' => '1',
        'im' => '1',
        'picture' => '1',
        'map' => '1',
        'related-profile' => '1',
        'user-dashboard' => '1',
        'affiliate' => '0',
        'forum' => '0',
        'note' => '0',
        'blog' => '0',
        'love-calculator' => '0',
        'invite' => '0',
        'cool-profile-page' => '0',
    ];

    foreach ($aExpectedModules as $sModule => $sExpected) {
        $sActual = isset($aModuleRows[$sModule]) ? (string)$aModuleRows[$sModule] : 'missing';
        $record(
            'module:' . $sModule,
            hash_equals($sExpected, $sActual),
            'expected=' . $sExpected . '; actual=' . $sActual
        );
    }
} catch (Throwable $oException) {
    $record('modules', false, $oException->getMessage());
}

$aOutput = [
    'service' => 'DeseoCerca',
    'healthy' => $bHealthy,
    'checked_at' => gmdate('c'),
    'checks' => $aChecks,
];

echo json_encode($aOutput, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
exit($bHealthy ? 0 : 1);
