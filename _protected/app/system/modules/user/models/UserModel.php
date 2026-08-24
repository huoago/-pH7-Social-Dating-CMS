<?php

/**
 * @title          User Model
 *
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

namespace PH7;

use PH7\Framework\Mvc\Model\Engine\Db;

class UserModel extends UserCoreModel
{
    /** @var string */
    private $sQueryPath;

    public function __construct()
    {
        parent::__construct();

        $this->sQueryPath = __DIR__ . PH7_DS . PH7_QUERY;
    }

    /**
     * Public member profiles must be in the normal active state. This keeps
     * deletion-pending and inactivity-deactivated accounts out of direct URLs
     * while admin tooling can still use the core model when necessary.
     */
    public function readProfile($iProfileId, $sTable = DbTableName::MEMBER)
    {
        $mProfile = parent::readProfile($iProfileId, $sTable);

        if (
            $sTable === DbTableName::MEMBER
            && $mProfile
            && (int)$mProfile->active !== RegistrationCore::NO_ACTIVATION
        ) {
            return false;
        }

        return $mProfile;
    }

    /**
     * Keep profiles involved in a user block, or profiles that are not in the
     * normal active state, out of discovery results. The upstream count is
     * preserved so we do not fork the large core SQL query.
     */
    public function search(array $aParams, $bCount, $iOffset, $iLimit)
    {
        $mResult = parent::search($aParams, $bCount, $iOffset, $iLimit);

        if ($bCount || empty($this->iProfileId) || !is_array($mResult) || empty($mResult)) {
            return $mResult;
        }

        $aExcludedIds = array_flip((new BlockModel())->getExcludedIds((int)$this->iProfileId));

        return array_values(
            array_filter(
                $mResult,
                static function ($oUser) use ($aExcludedIds): bool {
                    if ((int)$oUser->active !== RegistrationCore::NO_ACTIVATION) {
                        return false;
                    }

                    return !isset($aExcludedIds[(int)$oUser->profileId]);
                }
            )
        );
    }

    /**
     * Join Step 1.
     *
     * @return int Returns the user's ID
     */
    public function join(array $aData)
    {
        return $this->runRegistrationTransaction(
            function (Db $oDb) use ($aData): int {
                $rStmt = $oDb->prepare($this->getQuery('join', $this->sQueryPath));
                $rStmt->bindValue(':email', $aData['email'], \PDO::PARAM_STR);
                $rStmt->bindValue(':username', $aData['username'], \PDO::PARAM_STR);
                $rStmt->bindValue(':password', $aData['password'], \PDO::PARAM_STR);
                $rStmt->bindValue(':first_name', $aData['first_name'], \PDO::PARAM_STR);
                $rStmt->bindValue(':reference', $aData['reference'], \PDO::PARAM_STR);
                $rStmt->bindValue(':is_active', $aData['is_active'], \PDO::PARAM_INT);
                $rStmt->bindValue(':ip', $aData['ip'], \PDO::PARAM_STR);
                $rStmt->bindParam(':hash_validation', $aData['hash_validation'], \PDO::PARAM_STR, self::HASH_VALIDATION_LENGTH);
                $rStmt->bindValue(':current_date', $aData['current_date'], \PDO::PARAM_STR);
                $rStmt->bindValue(':affiliated_id', $aData['affiliated_id'], \PDO::PARAM_INT);
                if (!$rStmt->execute()) {
                    throw new \RuntimeException('The member account could not be created.');
                }
                $this->setKeyId($oDb->lastInsertId()); // Set the user's ID
                Db::free($rStmt);

                if (
                    !$this->setInfoFields([])
                    || !$this->setDefaultPrivacySetting()
                    || !$this->setDefaultNotification()
                    || !$this->updateMembership($aData['group_id'], $this->getKeyId(), $this->sCurrentDate)
                ) {
                    throw new \RuntimeException('The complete member profile could not be created.');
                }

                return $this->getKeyId();
            }
        );
    }

    /**
     * Execute SQL Join files.
     *
     * @param string $sJoinStep step of the "Join" file ('2_1', '2_2' or '3')
     *
     * @return bool
     */
    public function exe(array $aData, $sJoinStep)
    {
        return $this->exec('join' . $sJoinStep, $this->sQueryPath, $aData);
    }
}
