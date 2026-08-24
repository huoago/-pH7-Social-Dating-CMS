#!/usr/bin/env php
<?php
/**
 * DeseoCerca daily account lifecycle maintenance.
 *
 * Inactivity policy:
 * - day 60: reminder (30 days remaining)
 * - day 83: reminder (7 days remaining)
 * - days 85, 86, 87, 88, 89: daily reminders (5..1 days remaining)
 * - day 90+: deactivate, but do not delete; email a recovery link
 * - explicit user deletion requests: hard-delete only after the 90-day grace period
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
$iDeactivated = 0;
$iDeleted = 0;
$iErrors = 0;
$aReminderCounts = [];

/**
 * Exact 24-hour reminder windows. If the worker is offline for an entire
 * window, that reminder is intentionally not sent late with the wrong
 * "days remaining" claim.
 */
$aReminderSchedule = [
    ['min' => 60, 'max' => 61, 'code' => 'd60', 'remaining' => 30],
    ['min' => 83, 'max' => 84, 'code' => 'd83', 'remaining' => 7],
    ['min' => 85, 'max' => 86, 'code' => 'd85', 'remaining' => 5],
    ['min' => 86, 'max' => 87, 'code' => 'd86', 'remaining' => 4],
    ['min' => 87, 'max' => 88, 'code' => 'd87', 'remaining' => 3],
    ['min' => 88, 'max' => 89, 'code' => 'd88', 'remaining' => 2],
    ['min' => 89, 'max' => 90, 'code' => 'd89', 'remaining' => 1],
];

/** Send one operational lifecycle email. */
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

/** Escape user-controlled strings before inserting them into HTML email. */
function lifecycleHtml(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, PH7_ENCODING);
}

foreach ($aReminderSchedule as $aReminder) {
    $sCode = $aReminder['code'];
    $iRemaining = $aReminder['remaining'];
    $aReminderCounts[$sCode] = 0;

    foreach (
        $oLifecycleModel->getReminderCandidates(
            $aReminder['min'],
            $aReminder['max'],
            $sCode
        ) as $oMember
    ) {
        try {
            $sFirstName = lifecycleHtml((string)$oMember->firstName);
            $sLoginLink = lifecycleHtml(Uri::get('user', 'main', 'login'));
            $sDayWord = $iRemaining === 1 ? 'día' : 'días';
            $sSubject = sprintf('DeseoCerca: quedan %d %s para mantener tu cuenta activa', $iRemaining, $sDayWord);
            $sMessage = '<p>Hola ' . $sFirstName . ',</p>'
                . '<p>Tu cuenta de DeseoCerca lleva un periodo prolongado sin iniciar sesión.</p>'
                . '<p>Quedan <strong>' . $iRemaining . ' ' . $sDayWord . '</strong> antes de alcanzar 90 días sin inicio de sesión.</p>'
                . '<p>Si quieres mantener la cuenta activa, inicia sesión antes de ese plazo. Si llega a 90 días, la cuenta se desactivará, pero no eliminaremos automáticamente tus datos por inactividad.</p>'
                . '<p><a href="' . $sLoginLink . '">Iniciar sesión en DeseoCerca</a></p>';

            if (!sendLifecycleEmail((string)$oMember->email, $sSubject, $sMessage)) {
                ++$iErrors;
                fwrite(STDERR, $sCode . ' reminder mail failed for profile ' . (int)$oMember->profileId . PHP_EOL);
                continue;
            }

            if (
                !$oLifecycleModel->markReminderSent(
                    (int)$oMember->profileId,
                    $sCode,
                    (string)$oMember->lastActivity
                )
            ) {
                ++$iErrors;
                fwrite(STDERR, $sCode . ' reminder audit write failed for profile ' . (int)$oMember->profileId . PHP_EOL);
                continue;
            }

            ++$aReminderCounts[$sCode];
        } catch (Throwable $oException) {
            ++$iErrors;
            fwrite(
                STDERR,
                $sCode . ' reminder failed for profile ' . (int)$oMember->profileId . ': ' . $oException->getMessage() . PHP_EOL
            );
        }
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
            . '<p>Tu cuenta de DeseoCerca ha alcanzado 90 días sin iniciar sesión y será desactivada.</p>'
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

$aCounterParts = [];
foreach ($aReminderSchedule as $aReminder) {
    $aCounterParts[] = $aReminder['code'] . '=' . ($aReminderCounts[$aReminder['code']] ?? 0);
}

printf(
    "DeseoCerca lifecycle: reminders[%s] deactivated=%d deleted=%d errors=%d\n",
    implode(' ', $aCounterParts),
    $iDeactivated,
    $iDeleted,
    $iErrors
);

exit($iErrors === 0 ? 0 : 1);
