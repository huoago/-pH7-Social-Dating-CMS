<?php
/**
 * @title          Messenger Model
 *
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 * @package        PH7/ App / System / Module / IM / Model
 */

namespace PH7;

use PDO;
use PH7\Framework\Mvc\Model\Engine\Db;
use PH7\Framework\Mvc\Model\Engine\Model;

class MessengerModel extends Model
{
    public function select($sTo)
    {
        $sSqlQuery = 'SELECT * FROM' . Db::prefix(DbTableName::MESSENGER) .
            'WHERE (toUser = :to AND recd = 0) ORDER BY messengerId ASC';

        $rStmt = Db::getInstance()->prepare($sSqlQuery);
        $rStmt->bindValue(':to', $sTo, PDO::PARAM_STR);
        $rStmt->execute();

        return $rStmt->fetchAll(PDO::FETCH_OBJ);
    }

    public function update($sFrom, $sTo)
    {
        $sSqlQuery = 'UPDATE' . Db::prefix(DbTableName::MESSENGER) .
            'SET recd = 1 WHERE (fromUser = :from OR toUser = :to) AND recd = 0';

        $rStmt = Db::getInstance()->prepare($sSqlQuery);
        $rStmt->bindValue(':from', $sFrom, PDO::PARAM_STR);
        $rStmt->bindValue(':to', $sTo, PDO::PARAM_STR);

        return $rStmt->execute();
    }

    public function markReceivedById(int $messengerId): bool
    {
        $rStmt = Db::getInstance()->prepare(
            'UPDATE' . Db::prefix(DbTableName::MESSENGER) .
            'SET recd = 1 WHERE messengerId = :messengerId LIMIT 1'
        );
        $rStmt->bindValue(':messengerId', $messengerId, PDO::PARAM_INT);
        $bResult = $rStmt->execute();
        Db::free($rStmt);

        return $bResult;
    }

    public function insert($sFrom, $sTo, $sMessage, $sDate)
    {
        $sSqlQuery = 'INSERT INTO' . Db::prefix(DbTableName::MESSENGER) .
            '(fromUser, toUser, message, sent) VALUES (:from, :to, :message, :date)';

        $rStmt = Db::getInstance()->prepare($sSqlQuery);
        $rStmt->bindValue(':from', $sFrom, PDO::PARAM_STR);
        $rStmt->bindValue(':to', $sTo, PDO::PARAM_STR);
        $rStmt->bindValue(':message', $sMessage, PDO::PARAM_STR);
        $rStmt->bindValue(':date', $sDate, PDO::PARAM_STR);

        return $rStmt->execute();
    }
}
