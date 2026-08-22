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
    public function count(int $visitorId): int
    {
        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(*) FROM' . Db::prefix(DbTableName::MEMBER_WHO_VIEW) . 'AS v '
            . 'INNER JOIN' . Db::prefix(DbTableName::MEMBER) . 'AS m ON m.profileId = v.profileId '
            . 'WHERE v.visitorId = :visitorId AND m.ban = 0 AND m.active = 1'
        );
        $rStmt->bindValue(':visitorId', $visitorId, \PDO::PARAM_INT);
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
            . 'WHERE v.visitorId = :visitorId AND m.ban = 0 AND m.active = 1 '
            . 'AND (p.searchProfile = \'yes\' OR p.searchProfile IS NULL) '
            . 'ORDER BY v.lastVisit DESC LIMIT :offset, :limit'
        );
        $rStmt->bindValue(':visitorId', $visitorId, \PDO::PARAM_INT);
        $rStmt->bindValue(':offset', $offset, \PDO::PARAM_INT);
        $rStmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $rStmt->execute();
        $aRows = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRows;
    }
}
