<?php
/**
 * DeseoCerca profile favorites.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Model\Engine\Db;

class FavoriteModel
{
    private const TABLE = 'members_favorites';
    private const BLOCK_TABLE = 'members_blocks';

    public function exists(int $profileId, int $favoriteId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(self::TABLE) .
            'WHERE profileId = :profileId AND favoriteId = :favoriteId'
        );
        $rStmt->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':favoriteId', $favoriteId, \PDO::PARAM_INT);
        $rStmt->execute();
        $bExists = (int)$rStmt->fetchColumn() > 0;
        Db::free($rStmt);

        return $bExists;
    }

    public function add(int $profileId, int $favoriteId): bool
    {
        if ((new BlockModel())->hasBlockBetween($profileId, $favoriteId)) {
            return false;
        }

        $rStmt = Db::getInstance()->prepare(
            'INSERT IGNORE INTO' . Db::prefix(self::TABLE) .
            '(profileId, favoriteId, createdAt) VALUES (:profileId, :favoriteId, NOW())'
        );
        $rStmt->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':favoriteId', $favoriteId, \PDO::PARAM_INT);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function remove(int $profileId, int $favoriteId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'DELETE FROM' . Db::prefix(self::TABLE) .
            'WHERE profileId = :profileId AND favoriteId = :favoriteId LIMIT 1'
        );
        $rStmt->bindValue(':profileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':favoriteId', $favoriteId, \PDO::PARAM_INT);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function count(int $profileId): int
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(self::TABLE) . 'AS f '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = f.favoriteId '
            . 'WHERE f.profileId = :ownerProfileId AND m.ban = 0 AND m.active = 1 '
            . 'AND NOT EXISTS (SELECT 1 FROM' . Db::prefix(self::BLOCK_TABLE) . 'AS b '
            . 'WHERE (b.blockerId = :blockOwnerA AND b.blockedId = m.profileId) '
            . 'OR (b.blockerId = m.profileId AND b.blockedId = :blockOwnerB))'
        );
        $rStmt->bindValue(':ownerProfileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerA', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerB', $profileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $iCount = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iCount;
    }

    public function get(int $profileId, int $offset, int $limit): array
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT m.*, i.*, f.createdAt AS favoriteDate FROM' . Db::prefix(self::TABLE) . 'AS f '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = f.favoriteId '
            . 'LEFT JOIN' . Db::prefix(DbTableName::MEMBER_INFO) . 'AS i ON i.profileId = m.profileId '
            . 'WHERE f.profileId = :ownerProfileId AND m.ban = 0 AND m.active = 1 '
            . 'AND NOT EXISTS (SELECT 1 FROM' . Db::prefix(self::BLOCK_TABLE) . 'AS b '
            . 'WHERE (b.blockerId = :blockOwnerA AND b.blockedId = m.profileId) '
            . 'OR (b.blockerId = m.profileId AND b.blockedId = :blockOwnerB)) '
            . 'ORDER BY f.createdAt DESC LIMIT :offset, :limit'
        );
        $rStmt->bindValue(':ownerProfileId', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerA', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerB', $profileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':offset', $offset, \PDO::PARAM_INT);
        $rStmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }
}
