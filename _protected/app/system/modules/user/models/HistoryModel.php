<?php
/**
 * DeseoCerca recently viewed profiles.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Model\Engine\Db;

class HistoryModel
{
    private const BLOCK_TABLE = 'members_blocks';

    public function count(int $visitorId): int
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(DbTableName::MEMBER_WHO_VIEW) . 'AS v '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = v.profileId '
            . 'LEFT JOIN' . Db::prefix(DbTableName::MEMBER_PRIVACY) . 'AS p ON p.profileId = m.profileId '
            . 'WHERE v.visitorId = :viewerId AND m.ban = 0 AND m.active = 1 '
            . 'AND (p.searchProfile = \'yes\' OR p.searchProfile IS NULL) '
            . 'AND NOT EXISTS (SELECT 1 FROM' . Db::prefix(self::BLOCK_TABLE) . 'AS b '
            . 'WHERE (b.blockerId = :blockOwnerA AND b.blockedId = m.profileId) '
            . 'OR (b.blockerId = m.profileId AND b.blockedId = :blockOwnerB))'
        );
        $rStmt->bindValue(':viewerId', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerA', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerB', $visitorId, \PDO::PARAM_INT);
        $rStmt->execute();
        $iCount = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iCount;
    }

    public function get(int $visitorId, int $offset, int $limit): array
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT m.*, i.*, v.lastVisit FROM' . Db::prefix(DbTableName::MEMBER_WHO_VIEW) . 'AS v '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = v.profileId '
            . 'LEFT JOIN' . Db::prefix(DbTableName::MEMBER_INFO) . 'AS i ON i.profileId = m.profileId '
            . 'LEFT JOIN' . Db::prefix(DbTableName::MEMBER_PRIVACY) . 'AS p ON p.profileId = m.profileId '
            . 'WHERE v.visitorId = :viewerId AND m.ban = 0 AND m.active = 1 '
            . 'AND (p.searchProfile = \'yes\' OR p.searchProfile IS NULL) '
            . 'AND NOT EXISTS (SELECT 1 FROM' . Db::prefix(self::BLOCK_TABLE) . 'AS b '
            . 'WHERE (b.blockerId = :blockOwnerA AND b.blockedId = m.profileId) '
            . 'OR (b.blockerId = m.profileId AND b.blockedId = :blockOwnerB)) '
            . 'ORDER BY v.lastVisit DESC LIMIT :offset, :limit'
        );
        $rStmt->bindValue(':viewerId', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerA', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':blockOwnerB', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':offset', $offset, \PDO::PARAM_INT);
        $rStmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }
}
