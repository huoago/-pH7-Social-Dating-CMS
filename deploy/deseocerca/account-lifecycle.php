#!/usr/bin/env php
<?php
/**
 * DeseoCerca daily account lifecycle maintenance.
 *
 * Policy:
 * - 60..83 inactive days: first reminder.
 * - 83..90 inactive days: final reminder.
 * - 90+ inactive days: deactivate, but do not delete; email a recovery link.
 * - Explicit user deletion requests: hard-delete only after the 90-day grace period.
 */

declare(strict_types=1);

use PH7\AccountLifecycleModel;
use PH7\Framework\File\Import;
use PH7\Framework\Mail\Mail;
use PH7\Framework\Mvc\Router\Uri;
use PH7\UserCore;
use PH7\UserCoreModel;

require __DIR__ . '/cli-bootstrap.php';

Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.AccountLifecycleModel');

$oLifecycleModel = new AccountLifecycleModel();
$iWarning60 = 0;
$iWarning83 = 0;
$iDeactivated = 0;
$iDeleted = 0;
$iErrors = 0;

/**
 * Send one operational lifecycle email.
 */
function sendLifecycleEmail(string $email, string $subject, string $messageHtml): bool
{
    return (new Mail())->send(
        [
            'to' => $email,
            'subject' => $subject,
        ],
        $messageHtml
    );
}

/**
 * Escape user-controlled strings before inserting them into HTML email.
 */
function lifecycleHtml(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, PH7_ENCODING);
}

try {
    $oLifecycleModel->resetWarningsForRecentlyActiveMembers();
} catch (Throwable $oException) {
    ++$iErrors;
    fwrite(STDERR, 'Unable to reset lifecycle warnings: ' . $oException->getMessage() . PHP_EOL);
}

foreach ($oLifecycleModel->getWarningCandidates(60, 83, 'warning60SentAt') as $oMember) {
    try {
        $sFirstName = lifecycleHtml((string)$oMember->firstName);
        $sLoginLink = lifecycleHtml(Uri::get('user', 'main', 'login'));
        $sMessage = '<p>Hola ' . $sFirstName . ',</p>'
            . '<p>Tu cuenta de DeseoCerca lleva al menos 60 días sin actividad.</p>'
            . '<p>Si quieres mantenerla activa, inicia sesión antes de llegar a 90 días de inactividad.</p>'
            . '<p><a href="' . $sLoginLink . '">Volver a DeseoCerca</a></p>';

        if (sendLifecycleEmail((string)$oMember->email, 'DeseoCerca: recordatorio de actividad', $sMessage)) {
            $oLifecycleModel->markWarningSent((int)$oMember->profileId, 'warning60SentAt');
            ++$iWarning60;
        } else {
            ++$iErrors;
            fwrite(STDERR, '60-day reminder mail failed for profile ' . (int)$oMember->profileId . PHP_EOL);
        }
    } catch (Throwable $oException) {
        ++$iErrors;
        fwrite(STDERR, '60-day reminder failed for profile ' . (int)$oMember->profileId . ': ' . $oException->getMessage() . PHP_EOL);
    }
}

foreach ($oLifecycleModel->getWarningCandidates(83, 90, 'warning83SentAt') as $oMember) {
    try {
        $sFirstName = lifecycleHtml((string)$oMember->firstName);
        $sLoginLink = lifecycleHtml(Uri::get('user', 'main', 'login'));
        $sMessage = '<p>Hola ' . $sFirstName . ',</p>'
            . '<p>Tu cuenta de DeseoCerca está cerca de alcanzar 90 días sin actividad.</p>'
            . '<p>Inicia sesión ahora si quieres mantenerla activa. Si llega a 90 días sin actividad, la cuenta se desactivará, pero podrás recuperarla mediante un enlace seguro.</p>'
            . '<p><a href="' . $sLoginLink . '">Iniciar sesión</a></p>';

        if (sendLifecycleEmail((string)$oMember->email, 'DeseoCerca: aviso final de inactividad', $sMessage)) {
            $oLifecycleModel->markWarningSent((int)$oMember->profileId, 'warning83SentAt');
            ++$iWarning83;
        } else {
            ++$iErrors;
            fwrite(STDERR, '83-day reminder mail failed for profile ' . (int)$oMember->profileId . PHP_EOL);
        }
    } catch (Throwable $oException) {
        ++$iErrors;
        fwrite(STDERR, '83-day reminder failed for profile ' . (int)$oMember->profileId . ': ' . $oException->getMessage() . PHP_EOL);
    }
}

foreach ($oLifecycleModel->getInactivityDeactivationCandidates() as $oMember) {
    try {
        $sRecoveryToken = bin2hex(random_bytes(32));
        $sRecoveryTokenHash = hash('sha256', $sRecoveryToken);
        $sRecoveryLink = Uri::get('user', 'account', 'recoverdeletion') . PH7_SH . $sRecoveryToken;
        $sFirstName = lifecycleHtml((string)$oMember->firstName);
        $sSafeRecoveryLink = lifecycleHtml($sRecoveryLink);
        $sMessage = '<p>Hola ' . $sFirstName . ',</p>'
            . '<p>Tu cuenta de DeseoCerca ha alcanzado 90 días sin actividad y será desactivada.</p>'
            . '<p>No eliminaremos automáticamente tus datos por inactividad. Puedes reactivar la cuenta desde este enlace seguro:</p>'
            . '<p><a href="' . $sSafeRecoveryLink . '">' . $sSafeRecoveryLink . '</a></p>';

        // Fail safe: do not lock a member out unless the recovery channel works.
        if (!sendLifecycleEmail((string)$oMember->email, 'DeseoCerca: cuenta desactivada por inactividad', $sMessage)) {
            ++$iErrors;
            fwrite(STDERR, '90-day recovery mail failed for profile ' . (int)$oMember->profileId . '; account left active.' . PHP_EOL);
            continue;
        }

        if ($oLifecycleModel->deactivateForInactivity((int)$oMember->profileId, $sRecoveryTokenHash)) {
            ++$iDeactivated;
        } else {
            ++$iErrors;
            fwrite(STDERR, '90-day deactivation failed for profile ' . (int)$oMember->profileId . PHP_EOL);
        }
    } catch (Throwable $oException) {
        ++$iErrors;
        fwrite(STDERR, '90-day deactivation failed for profile ' . (int)$oMember->profileId . ': ' . $oException->getMessage() . PHP_EOL);
    }
}

foreach ($oLifecycleModel->getDueDeletions() as $oMember) {
    try {
        // Use the framework's canonical deletion path so media, messages,
        // relationships, privacy rows and related records are cleaned as well.
        (new UserCore())->delete(
            (int)$oMember->profileId,
            (string)$oMember->username,
            new UserCoreModel()
        );
        ++$iDeleted;
    } catch (Throwable $oException) {
        ++$iErrors;
        fwrite(STDERR, 'Scheduled hard deletion failed for profile ' . (int)$oMember->profileId . ': ' . $oException->getMessage() . PHP_EOL);
    }
}

printf(
    "DeseoCerca lifecycle: warning60=%d warning83=%d deactivated=%d deleted=%d errors=%d\n",
    $iWarning60,
    $iWarning83,
    $iDeactivated,
    $iDeleted,
    $iErrors
);

exit($iErrors === 0 ? 0 : 1);
