<?php
/**
 * DeseoCerca account lifecycle state.
 *
 * Keeps recoverable account-deletion requests and inactivity notices separate
 * from the legacy member active/activation field.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use DateTimeImmutable;
use PH7\Framework\Mvc\Model\Engine\Db;

final class AccountLifecycleModel
{
    public const STATE_ACTIVE = 'active';
    public const STATE_DELETION_PENDING = 'deletion_pending';
    public const STATE_INACTIVE_DEACTIVATED = 'inactive_deactivated';

    private const TABLE = 'account_lifecycle';
    private const REMINDER_TABLE = 'account_lifecycle_reminders';
    private const REMINDER_CODES = ['d60', 'd83', 'd85', 'd86', 'd87', 'd88', 'd89'];

    public function scheduleDeletion(int $profileId, string $recoveryTokenHash): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'INSERT INTO' . Db::prefix(self::TABLE) .
            '(profileId, state, deleteRequestedAt, deleteScheduledAt, recoveryTokenHash, createdAt, updatedAt) '
            . "VALUES (:profileId, 'deletion_pending', NOW(), DATE_ADD(NOW(), INTERVAL 90 DAY), :recoveryTokenHash, NOW(), NOW()) "
            . 'ON DUPLICATE KEY UPDATE state = VALUES(state), deleteRequestedAt = VALUES(deleteRequestedAt), '
            . 'deleteScheduledAt = VALUES(deleteScheduledAt), recoveryTokenHash = VALUES(recoveryTokenHash), '
            . 'inactiveDeactivatedAt = NULL, updatedAt = NOW()'
        );
        $rStmt->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':recoveryTokenHash', $recoveryTokenHash, \PDO::PARAM_STR);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function findRecoverableByTokenHash(string $recoveryTokenHash): ?\stdClass
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT l.profileId, l.state, l.deleteScheduledAt, m.email, m.username, m.firstName '
            . 'FROM' . Db::prefix(self::TABLE) . 'AS l '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = l.profileId '
            . 'WHERE l.recoveryTokenHash = :recoveryTokenHash '
            . "AND l.state IN ('deletion_pending', 'inactive_deactivated') LIMIT 1"
        );
        $rStmt->bindValue(':recoveryTokenHash', $recoveryTokenHash, \PDO::PARAM_STR);
        $rStmt->execute();
        $oRow = $rStmt->fetch(\PDO::FETCH_OBJ) ?: null;
        Db::free($rStmt);

        return $oRow;
    }

    public function recover(int $profileId): bool
    {
        $oDb = Db::getInstance();
        $oDb->beginTransaction();

        try {
            $rMember = $oDb->prepare(
                'UPDATE' . Db::prefix(DbTableName::MEMBER) .
                'SET active = :active, lastActivity = NOW() WHERE profileId = :profileId LIMIT 1'
            );
            $rMember->bindValue(':active', RegistrationCore::NO_ACTIVATION, \PDO::PARAM_INT);
            $rMember->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
            $rMember->execute();
            Db::free($rMember);

            $rLifecycle = $oDb->prepare(
                'UPDATE' . Db::prefix(self::TABLE) .
                "SET state = 'active', deleteRequestedAt = NULL, deleteScheduledAt = NULL, recoveryTokenHash = NULL, "
                . 'inactiveDeactivatedAt = NULL, updatedAt = NOW() '
                . 'WHERE profileId = :profileId LIMIT 1'
            );
            $rLifecycle->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
            $rLifecycle->execute();
            Db::free($rLifecycle);

            return $oDb->commit();
        } catch (\Throwable $oException) {
            if ($oDb->inTransaction()) {
                $oDb->rollBack();
            }
            throw $oException;
        }
    }

    /**
     * Return active accounts inside one exact inactivity reminder window.
     *
     * Reminder idempotency is keyed by profile + reminder code + the account's
     * current lastActivity value. A later successful login changes lastActivity,
     * automatically starting a new inactivity cycle without deleting audit rows.
     */
    public function getReminderCandidates(int $minimumDays, int $maximumDays, string $reminderCode): array
    {
        $this->validateReminderWindow($minimumDays, $maximumDays, $reminderCode);

        $oNow = new DateTimeImmutable('now');
        $sWindowStart = $oNow->modify(sprintf('-%d days', $minimumDays))->format(UserCoreModel::DATETIME_FORMAT);
        $sWindowEnd = $oNow->modify(sprintf('-%d days', $maximumDays))->format(UserCoreModel::DATETIME_FORMAT);
        $rStmt = Db::getInstance()->prepare(
            'SELECT m.profileId, m.email, m.username, m.firstName, m.lastActivity '
            . 'FROM' . Db::prefix(DbTableName::MEMBER) . 'AS m '
            . 'LEFT JOIN' . Db::prefix(self::TABLE) . 'AS l ON l.profileId = m.profileId '
            . 'LEFT JOIN' . Db::prefix(self::REMINDER_TABLE) . 'AS r '
            . 'ON r.profileId = m.profileId AND r.reminderCode = :reminderCode AND r.activityAnchor = m.lastActivity '
            . 'WHERE m.active = :active AND m.username <> :ghostUsername '
            . 'AND m.lastActivity <= :windowStart AND m.lastActivity > :windowEnd '
            . "AND (l.state IS NULL OR l.state = 'active') AND r.profileId IS NULL"
        );
        $rStmt->bindValue(':reminderCode', $reminderCode, \PDO::PARAM_STR);
        $rStmt->bindValue(':active', RegistrationCore::NO_ACTIVATION, \PDO::PARAM_INT);
        $rStmt->bindValue(':ghostUsername', PH7_GHOST_USERNAME, \PDO::PARAM_STR);
        $rStmt->bindValue(':windowStart', $sWindowStart, \PDO::PARAM_STR);
        $rStmt->bindValue(':windowEnd', $sWindowEnd, \PDO::PARAM_STR);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }

    public function markReminderSent(int $profileId, string $reminderCode, string $activityAnchor): bool
    {
        if (!in_array($reminderCode, self::REMINDER_CODES, true)) {
            throw new \InvalidArgumentException('Unsupported inactivity reminder code.');
        }

        $rStmt = Db::getInstance()->prepare(
            'INSERT IGNORE INTO' . Db::prefix(self::REMINDER_TABLE) .
            '(profileId, reminderCode, activityAnchor, sentAt) VALUES (:profileId, :reminderCode, :activityAnchor, NOW())'
        );
        $rStmt->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':reminderCode', $reminderCode, \PDO::PARAM_STR);
        $rStmt->bindValue(':activityAnchor', $activityAnchor, \PDO::PARAM_STR);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function getInactivityDeactivationCandidates(): array
    {
        $sCutoff = (new DateTimeImmutable('now'))->modify('-90 days')->format(UserCoreModel::DATETIME_FORMAT);
        $rStmt = Db::getInstance()->prepare(
            'SELECT m.profileId, m.email, m.username, m.firstName, m.lastActivity '
            . 'FROM' . Db::prefix(DbTableName::MEMBER) . 'AS m '
            . 'LEFT JOIN' . Db::prefix(self::TABLE) . 'AS l ON l.profileId = m.profileId '
            . 'WHERE m.active = :active AND m.username <> :ghostUsername AND m.lastActivity <= :cutoff '
            . "AND (l.state IS NULL OR l.state = 'active')"
        );
        $rStmt->bindValue(':active', RegistrationCore::NO_ACTIVATION, \PDO::PARAM_INT);
        $rStmt->bindValue(':ghostUsername', PH7_GHOST_USERNAME, \PDO::PARAM_STR);
        $rStmt->bindValue(':cutoff', $sCutoff, \PDO::PARAM_STR);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }

    public function deactivateForInactivity(int $profileId, string $recoveryTokenHash): bool
    {
        $oDb = Db::getInstance();
        $oDb->beginTransaction();

        try {
            $rLifecycle = $oDb->prepare(
                'INSERT INTO' . Db::prefix(self::TABLE) .
                '(profileId, state, recoveryTokenHash, inactiveDeactivatedAt, createdAt, updatedAt) '
                . "VALUES (:profileId, 'inactive_deactivated', :recoveryTokenHash, NOW(), NOW(), NOW()) "
                . "ON DUPLICATE KEY UPDATE state = 'inactive_deactivated', recoveryTokenHash = VALUES(recoveryTokenHash), "
                . 'inactiveDeactivatedAt = NOW(), updatedAt = NOW()'
            );
            $rLifecycle->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
            $rLifecycle->bindValue(':recoveryTokenHash', $recoveryTokenHash, \PDO::PARAM_STR);
            $rLifecycle->execute();
            Db::free($rLifecycle);

            $rMember = $oDb->prepare(
                'UPDATE' . Db::prefix(DbTableName::MEMBER) .
                'SET active = 0 WHERE profileId = :profileId LIMIT 1'
            );
            $rMember->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
            $rMember->execute();
            Db::free($rMember);

            return $oDb->commit();
        } catch (\Throwable $oException) {
            if ($oDb->inTransaction()) {
                $oDb->rollBack();
            }
            throw $oException;
        }
    }

    public function getDueDeletions(): array
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT l.profileId, m.username, m.email FROM' . Db::prefix(self::TABLE) . 'AS l '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = l.profileId '
            . "WHERE l.state = 'deletion_pending' AND l.deleteScheduledAt IS NOT NULL AND l.deleteScheduledAt <= NOW()"
        );
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }

    private function validateReminderWindow(int $minimumDays, int $maximumDays, string $reminderCode): void
    {
        if ($minimumDays < 1 || $maximumDays <= $minimumDays) {
            throw new \InvalidArgumentException('Invalid inactivity reminder window.');
        }
        if (!in_array($reminderCode, self::REMINDER_CODES, true)) {
            throw new \InvalidArgumentException('Unsupported inactivity reminder code.');
        }
    }
}
