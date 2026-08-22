<?php
/**
 * DeseoCerca user blocking.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Model\Engine\Db;

class BlockModel
{
    private const TABLE = 'members_blocks';

    public function isBlockedBy(int $blockerId, int $blockedId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(self::TABLE) .
            'WHERE blockerId = :blockerId AND blockedId = :blockedId'
        );
        $rStmt->bindValue(':blockerId', $blockerId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockedId', $blockedId, \PDO::PARAM_INT);
        $rStmt->execute();
        $bBlocked = (int)$rStmt->fetchColumn() > 0;
        Db::free($rStmt);

        return $bBlocked;
    }

    public function hasBlockBetween(int $firstId, int $secondId): bool
    {
        return $this->isBlockedBy($firstId, $secondId) || $this->isBlockedBy($secondId, $firstId);
    }

    public function add(int $blockerId, int $blockedId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'INSERT IGNORE INTO' . Db::prefix(self::TABLE) .
            '(blockerId, blockedId, createdAt) VALUES (:blockerId, :blockedId, NOW())'
        );
        $rStmt->bindValue(':blockerId', $blockerId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockedId', $blockedId, \PDO::PARAM_INT);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function remove(int $blockerId, int $blockedId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'DELETE FROM' . Db::prefix(self::TABLE) .
            'WHERE blockerId = :blockerId AND blockedId = :blockedId LIMIT 1'
        );
        $rStmt->bindValue(':blockerId', $blockerId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockedId', $blockedId, \PDO::PARAM_INT);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function count(int $blockerId): int
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(self::TABLE) . 'WHERE blockerId = :blockerId'
        );
        $rStmt->bindValue(':blockerId', $blockerId, \PDO::PARAM_INT);
        $rStmt->execute();
        $iCount = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iCount;
    }

    public function get(int $blockerId, int $offset, int $limit): array
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT m.*, i.*, b.createdAt AS blockedDate FROM' . Db::prefix(self::TABLE) . 'AS b '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = b.blockedId '
            . 'LEFT JOIN' . Db::prefix(DbTableName::MEMBER_INFO) . 'AS i ON i.profileId = m.profileId '
            . 'WHERE b.blockerId = :blockerId ORDER BY b.createdAt DESC LIMIT :offset, :limit'
        );
        $rStmt->bindValue(':blockerId', $blockerId, \PDO::PARAM_INT);
        $rStmt->bindValue(':offset', $offset, \PDO::PARAM_INT);
        $rStmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }
}
