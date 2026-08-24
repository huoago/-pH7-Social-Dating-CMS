<?php

/**
 * @title          User Core Model Class
 *
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\CArray\ObjArr;
use PH7\Framework\Date\CDateTime;
use PH7\Framework\Error\CException\PH7InvalidArgumentException;
use PH7\Framework\Mvc\Model\DbConfig;
use PH7\Framework\Mvc\Model\Engine\Db;
use PH7\Framework\Mvc\Model\Engine\Model;
use PH7\Framework\Mvc\Model\Engine\Util\Various;
use PH7\Framework\Security\Security;
use PH7\Framework\Session\Session;
use PH7\Framework\Str\Str;
use PH7\Framework\Translate\Lang;

// Abstract Class
class UserCoreModel extends Model
{
    public const DATETIME_FORMAT = 'Y-m-d H:i:s';

    /**
     * Cache lifetime set to 1 week.
     */
    public const CACHE_TIME = 604800;

    public const CACHE_GROUP = 'db/sys/mod/user';

    public const HASH_VALIDATION_LENGTH = 40;

    public const OFFLINE_STATUS = 0;
    public const ONLINE_STATUS = 1;
    public const BUSY_STATUS = 2;
    public const AWAY_STATUS = 3;

    public const VISITOR_GROUP = 1;
    public const PENDING_GROUP = 9;

    public const QUERY_SEARCH_USER = 'SELECT %s FROM %s AS m LEFT JOIN %s AS p USING(profileId) LEFT JOIN %s AS i USING(profileId)';

    /** @var string */
    protected $sCurrentDate;

    /** @var string */
    protected $iProfileId;

    public function __construct()
    {
        parent::__construct();

        $this->sCurrentDate = (new CDateTime())->get()->dateTime(self::DATETIME_FORMAT);
        $this->iProfileId = (new Session())->get('member_id');
    }

    /**
     * Clone is set to private to stop cloning.
     */
    private function __clone()
    {
    }

    /**
     * @return \stdClass
     */
    public function checkGroup(Session $oSession)
    {
        // Set default group ID if no user is logged in (and so, 'member_group_id' session doesn't exist)
        if (!$oSession->exists('member_group_id')) {
            $oSession->regenerateId();
            $oSession->set('member_group_id', PermissionCore::VISITOR_GROUP_ID);
        }
        $iMemberGroupId = (int)$oSession->get('member_group_id');

        $this->cache->start(
            self::CACHE_GROUP,
            'membership_groups' . $iMemberGroupId,
            static::CACHE_TIME
        );

        if (!$oPermissions = $this->cache->get()) {
            $rStmt = Db::getInstance()->prepare(
                'SELECT permissions FROM' . Db::prefix(DbTableName::MEMBERSHIP) .
                'WHERE groupId = :groupId LIMIT 1'
            );
            $rStmt->bindValue(':groupId', $iMemberGroupId, \PDO::PARAM_INT);
            $rStmt->execute();
            $sPermissions = $rStmt->fetchColumn();
            Db::free($rStmt);
            $aPermissions = unserialize($sPermissions, ['allowed_classes' => false]);
            $oPermissions = ObjArr::toObject(is_array($aPermissions) ? $aPermissions : []);
            $this->cache->put($oPermissions);
        }

        return $oPermissions;
    }

    /**
     * Login method for Members and Affiliate, but not for Admins since it has another method PH7\AdminModel::adminLogin() even more secure.
     *
     * @param string $sEmail    not case sensitive since on lot of mobile devices (such as iPhone), the first letter is uppercase
     * @param string $sPassword
     * @param string $sTable
     *
     * @return bool|string (boolean "true" or string "message")
     */
    public function login($sEmail, $sPassword, $sTable = DbTableName::MEMBER)
    {
        Various::checkModelTable($sTable);

        $rStmt = Db::getInstance()->prepare(
            'SELECT email, password FROM' . Db::prefix($sTable) . 'WHERE email = :email LIMIT 1'
        );
        $rStmt->bindValue(':email', $sEmail, \PDO::PARAM_STR);
        $rStmt->execute();
        $oRow = $rStmt->fetch(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        $sDbEmail = !empty($oRow->email) ? $oRow->email : '';
        $sDbPassword = !empty($oRow->password) ? $oRow->password : '';

        if (strtolower($sEmail) !== strtolower($sDbEmail)) {
            return CredentialStatusCore::INCORRECT_EMAIL_IN_DB;
        }
        if (!Security::checkPwd($sPassword, $sDbPassword)) {
            return CredentialStatusCore::INCORRECT_PASSWORD_IN_DB;
        }

        return true;
    }

    /**
     * Retrieve the user's IP address from the log session table.
     *
     * @param int    $iProfileId
     * @param string $sTable
     *
     * @return string the latest used user's IP address
     */
    public function getLastUsedIp($iProfileId, $sTable = DbTableName::MEMBER_LOG_SESS)
    {
        Various::checkModelTable($sTable);

        $rStmt = Db::getInstance()->prepare('SELECT ip FROM' . Db::prefix($sTable) . 'WHERE profileId = :profileId ORDER BY dateTime DESC LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sLastUsedIp = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sLastUsedIp;
    }

    /**
     * Read Profile Data.
     *
     * @param int    $iProfileId The user ID
     * @param string $sTable
     *
     * @return \stdClass|bool the data of a member if exists, FALSE otherwise
     */
    public function readProfile($iProfileId, $sTable = DbTableName::MEMBER)
    {
        $this->cache->start(self::CACHE_GROUP, 'readProfile' . $iProfileId . $sTable, static::CACHE_TIME);

        if (!$oData = $this->cache->get()) {
            Various::checkModelTable($sTable);

            $rStmt = Db::getInstance()->prepare('SELECT * FROM' . Db::prefix($sTable) . 'WHERE profileId = :profileId LIMIT 1');
            $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
            $rStmt->execute();
            $oData = $rStmt->fetch(\PDO::FETCH_OBJ);
            Db::free($rStmt);
            $this->cache->put($oData);
        }

        return $oData;
    }

    /**
     * Get the total number of members.
     *
     * @param string $sGender Values ​​available 'all', 'male', 'female'. 'couple' is only available to Members.
     *
     * @return int Total Users
     */
    public function total(string $sTable = DbTableName::MEMBER, int $iDay = 0, string $sGender = 'all'): int
    {
        Various::checkModelTable($sTable);

        $bIsDay = ($iDay > 0);

        if ($sTable === DbTableName::MEMBER) {
            $bIsGender = GenderTypeUserCore::isGenderValid($sGender);
        } else {
            $bIsGender = GenderTypeUserCore::isGenderValid($sGender, GenderTypeUserCore::IGNORE_COUPLE_GENDER);
        }

        $sSqlDay = $bIsDay ? ' AND (joinDate + INTERVAL :day DAY) > NOW()' : '';
        $sSqlGender = $bIsGender ? ' AND sex = :gender ' : '';

        $rStmt = Db::getInstance()->prepare('SELECT COUNT(profileId) FROM' . Db::prefix($sTable) . 'WHERE username <> :ghostUsername' . $sSqlDay . $sSqlGender);
        $rStmt->bindValue(':ghostUsername', PH7_GHOST_USERNAME, \PDO::PARAM_STR);
        if ($bIsDay) {
            $rStmt->bindValue(':day', $iDay, \PDO::PARAM_INT);
        }
        if ($bIsGender) {
            $rStmt->bindValue(':gender', $sGender, \PDO::PARAM_STR);
        }
        $rStmt->execute();

        $iTotalUsers = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iTotalUsers;
    }

    /**
     * Update profile data.
     *
     * @param string $sSection
     * @param string $sValue
     * @param int    $iProfileId Profile ID
     * @param string $sTable
     *
     * @return void
     */
    public function updateProfile($sSection, $sValue, $iProfileId, $sTable = DbTableName::MEMBER)
    {
        Various::checkModelTable($sTable);

        $this->orm->update($sTable, $sSection, $sValue, 'profileId', $iProfileId);
    }

    /**
     * Update Privacy setting data.
     *
     * @param string $sSection
     * @param string $sValue
     * @param int    $iProfileId Profile ID
     *
     * @return void
     */
    public function updatePrivacySetting($sSection, $sValue, $iProfileId)
    {
        $this->orm->update(
            DbTableName::MEMBER_PRIVACY,
            $sSection,
            $sValue,
            'profileId',
            $iProfileId
        );
    }

    /**
     * Change password of a member.
     *
     * @param string $sEmail
     * @param string $sNewPassword
     * @param string $sTable
     *
     * @return bool
     */
    public function changePassword($sEmail, $sNewPassword, $sTable)
    {
        Various::checkModelTable($sTable);

        $rStmt = Db::getInstance()->prepare(
            'UPDATE' . Db::prefix($sTable) . 'SET password = :newPassword WHERE email = :email LIMIT 1'
        );
        $rStmt->bindValue(':email', $sEmail, \PDO::PARAM_STR);
        $rStmt->bindValue(':newPassword', Security::hashPwd($sNewPassword), \PDO::PARAM_STR);

        return $rStmt->execute();
    }

    /**
     * Set a new hash validation.
     *
     * @param int    $iProfileId
     * @param string $sHash
     * @param string $sTable
     *
     * @return bool
     */
    public function setNewHashValidation($iProfileId, $sHash, $sTable)
    {
        Various::checkModelTable($sTable);

        $rStmt = Db::getInstance()->prepare('UPDATE' . Db::prefix($sTable) . 'SET hashValidation = :hash WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->bindParam(':hash', $sHash, \PDO::PARAM_STR, self::HASH_VALIDATION_LENGTH);

        return $rStmt->execute();
    }

    /**
     * Check the hash validation.
     *
     * @param string $sEmail
     * @param string $sHash
     * @param string $sTable
     *
     * @return bool
     */
    public function checkHashValidation($sEmail, $sHash, $sTable)
    {
        Various::checkModelTable($sTable);

        $rStmt = Db::getInstance()->prepare(
            'SELECT COUNT(profileId) FROM' . Db::prefix($sTable) . 'WHERE email = :email AND hashValidation = :hash LIMIT 1'
        );
        $rStmt->bindValue(':email', $sEmail, \PDO::PARAM_STR);
        $rStmt->bindParam(':hash', $sHash, \PDO::PARAM_STR, self::HASH_VALIDATION_LENGTH);
        $rStmt->execute();

        return $rStmt->fetchColumn() === 1;
    }

    /**
     * Search users.
     *
     * @param bool $bCount
     * @param int  $iOffset
     * @param int  $iLimit
     *
     * @return array|int object for the users list returned or integer for the total number users returned
     */
    public function search(array $aParams, $bCount, $iOffset, $iLimit)
    {
        $bCount = (bool)$bCount;
        $iOffset = (int)$iOffset;
        $iLimit = (int)$iLimit;

        $bIsKeyword = !empty($aParams[SearchQueryCore::KEYWORD]) && Str::noSpaces($aParams[SearchQueryCore::KEYWORD]);
        $bIsMail = !empty($aParams[SearchQueryCore::EMAIL]) && Str::noSpaces($aParams[SearchQueryCore::EMAIL]);
        $bIsFirstName = !$bIsMail && !empty($aParams[SearchQueryCore::FIRST_NAME]) && Str::noSpaces($aParams[SearchQueryCore::FIRST_NAME]);
        $bIsMiddleName = !$bIsMail && !empty($aParams[SearchQueryCore::MIDDLE_NAME]) && Str::noSpaces($aParams[SearchQueryCore::MIDDLE_NAME]);
        $bIsLastName = !$bIsMail && !empty($aParams[SearchQueryCore::LAST_NAME]) && Str::noSpaces($aParams[SearchQueryCore::LAST_NAME]);
        $bIsSingleAge = !$bIsMail && !empty($aParams[SearchQueryCore::AGE]);
        $bIsAge = !$bIsMail && empty($aParams[SearchQueryCore::AGE]) && !empty($aParams[SearchQueryCore::MIN_AGE]) && !empty($aParams[SearchQueryCore::MAX_AGE]);
        $bIsHeight = !$bIsMail && !empty($aParams[SearchQueryCore::HEIGHT]);
        $bIsWeight = !$bIsMail && !empty($aParams[SearchQueryCore::WEIGHT]);
        $bIsCountry = !$bIsMail && !empty($aParams[SearchQueryCore::COUNTRY]) && Str::noSpaces($aParams[SearchQueryCore::COUNTRY]);
        $bIsCity = !$bIsMail && !empty($aParams[SearchQueryCore::CITY]) && Str::noSpaces($aParams[SearchQueryCore::CITY]);
        $bIsState = !$bIsMail && !empty($aParams[SearchQueryCore::STATE]) && Str::noSpaces($aParams[SearchQueryCore::STATE]);
        $bIsZipCode = !$bIsMail && !empty($aParams[SearchQueryCore::ZIP_CODE]) && Str::noSpaces($aParams[SearchQueryCore::ZIP_CODE]);
        $bIsSex = !$bIsMail && !empty($aParams[SearchQueryCore::SEX]) && is_array($aParams[SearchQueryCore::SEX]);
        $bIsMatchSex = !$bIsMail && !empty($aParams[SearchQueryCore::MATCH_SEX]);
        $bIsOnline = !$bIsMail && !empty($aParams[SearchQueryCore::ONLINE]);
        $bIsAvatar = !$bIsMail && !empty($aParams[SearchQueryCore::AVATAR]);
        $bHideUserLogged = !$bIsMail && !empty($this->iProfileId);

        $sSqlLimit = !$bCount ? 'LIMIT :offset, :limit' : '';
        $sSqlSelect = !$bCount ? '*' : 'COUNT(m.profileId)';
        $sSqlFirstName = $bIsFirstName ? ' AND LOWER(firstName) LIKE LOWER(:firstName)' : '';
        $sSqlMiddleName = $bIsMiddleName ? ' AND LOWER(middleName) LIKE LOWER(:middleName)' : '';
        $sSqlLastName = $bIsLastName ? ' AND LOWER(lastName) LIKE LOWER(:lastName)' : '';
        $sSqlSingleAge = $bIsSingleAge ? ' AND birthDate LIKE :birthDate ' : '';
        $sSqlAge = $bIsAge ? ' AND birthDate BETWEEN DATE_SUB(\'' . $this->sCurrentDate . '\', INTERVAL :maxAge YEAR) AND DATE_SUB(\'' . $this->sCurrentDate . '\', INTERVAL :minAge YEAR) ' : '';
        $sSqlHeight = $bIsHeight ? ' AND height = :height ' : '';
        $sSqlWeight = $bIsWeight ? ' AND weight = :weight ' : '';
        $sSqlCountry = $bIsCountry ? ' AND country = :country ' : '';
        $sSqlCity = $bIsCity ? ' AND LOWER(city) LIKE LOWER(:city) ' : '';
        $sSqlState = $bIsState ? ' AND LOWER(state) LIKE LOWER(:state) ' : '';
        $sSqlZipCode = $bIsZipCode ? ' AND LOWER(zipCode) LIKE LOWER(:zipCode) ' : '';
        $sSqlEmail = $bIsMail ? ' AND email LIKE :email ' : '';
        $sSqlOnline = $bIsOnline ? ' AND userStatus = :userStatus AND lastActivity > DATE_SUB(\'' . $this->sCurrentDate . '\', INTERVAL ' . DbConfig::getSetting('userTimeout') . ' MINUTE) ' : '';
        $sSqlAvatar = $bIsAvatar ? $this->getUserWithAvatarOnlySql() : '';
        $sSqlHideLoggedProfile = $bHideUserLogged ? ' AND (m.profileId <> :profileId)' : '';
        $sSqlMatchSex = $bIsMatchSex ? ' AND FIND_IN_SET(:matchSex, matchSex)' : '';

        $sSqlSex = '';
        if ($bIsSex) {
            $sSqlSex = $this->getSexInClauseSql($aParams[SearchQueryCore::SEX]);
        }

        if (empty($aParams[SearchQueryCore::ORDER])) {
            $aParams[SearchQueryCore::ORDER] = SearchCoreModel::LATEST; // Default is "ORDER BY joinDate"
        }
        if (empty($aParams[SearchQueryCore::SORT])) {
            $aParams[SearchQueryCore::SORT] = SearchCoreModel::DESC; // Default is "descending"
        }
        $sSqlOrder = SearchCoreModel::order($aParams[SearchQueryCore::ORDER], $aParams[SearchQueryCore::SORT]);

        $sSqlQuery = sprintf(static::QUERY_SEARCH_USER, $sSqlSelect, Db::prefix(DbTableName::MEMBER), Db::prefix(DbTableName::MEMBER_PRIVACY), Db::prefix(DbTableName::MEMBER_INFO));
        $sSqlQuery .= ' WHERE username <> :ghostUsername AND m.active = :activeStatus AND searchProfile = \'yes\' AND (groupId <> :visitorGroup) AND (groupId <> :pendingGroup) AND (ban = 0)';

        if ($bIsKeyword) {
            $sSqlQuery .= ' AND (
                LOWER(username) LIKE LOWER(:keyword) OR LOWER(firstName) LIKE LOWER(:keyword) OR LOWER(lastName) LIKE LOWER(:keyword)
                OR LOWER(city) LIKE LOWER(:keyword) OR LOWER(state) LIKE LOWER(:keyword) OR LOWER(zipCode) LIKE LOWER(:keyword)
                OR sex LIKE :keyword OR LOWER(punchline) LIKE LOWER(:keyword) OR email LIKE :keyword
            )';
        } else {
            $sSqlQuery .= $sSqlHideLoggedProfile . $sSqlFirstName . $sSqlMiddleName . $sSqlLastName . $sSqlMatchSex . $sSqlSex . $sSqlSingleAge . $sSqlAge . $sSqlCountry . $sSqlCity . $sSqlState .
            $sSqlZipCode . $sSqlHeight . $sSqlWeight . $sSqlEmail . $sSqlOnline . $sSqlAvatar;
        }

        $rStmt = Db::getInstance()->prepare($sSqlQuery . $sSqlOrder . $sSqlLimit);

        $rStmt->bindValue(':ghostUsername', PH7_GHOST_USERNAME, \PDO::PARAM_STR);
        $rStmt->bindValue(':activeStatus', RegistrationCore::NO_ACTIVATION, \PDO::PARAM_INT);
        $rStmt->bindValue(':visitorGroup', self::VISITOR_GROUP, \PDO::PARAM_INT);
        $rStmt->bindValue(':pendingGroup', self::PENDING_GROUP, \PDO::PARAM_INT);

        if ($bIsKeyword) {
            $rStmt->bindValue(':keyword', '%' . $aParams[SearchQueryCore::KEYWORD] . '%', \PDO::PARAM_STR);
        } else {
            if ($bIsMatchSex) {
                $rStmt->bindValue(':matchSex', $aParams[SearchQueryCore::MATCH_SEX], \PDO::PARAM_STR);
            }
            if ($bIsFirstName) {
                $rStmt->bindValue(':firstName', '%' . $aParams[SearchQueryCore::FIRST_NAME] . '%', \PDO::PARAM_STR);
            }
            if ($bIsMiddleName) {
                $rStmt->bindValue(':middleName', '%' . $aParams[SearchQueryCore::MIDDLE_NAME] . '%', \PDO::PARAM_STR);
            }
            if ($bIsLastName) {
                $rStmt->bindValue(':lastName', '%' . $aParams[SearchQueryCore::LAST_NAME] . '%', \PDO::PARAM_STR);
            }
            if ($bIsSingleAge) {
                $rStmt->bindValue(':birthDate', '%' . $aParams[SearchQueryCore::AGE] . '%', \PDO::PARAM_STR);
            }
            if ($bIsAge) {
                $rStmt->bindValue(':minAge', $aParams[SearchQueryCore::MIN_AGE], \PDO::PARAM_INT);
                $rStmt->bindValue(':maxAge', $aParams[SearchQueryCore::MAX_AGE], \PDO::PARAM_INT);
            }
            if ($bIsHeight) {
                $rStmt->bindValue(':height', $aParams[SearchQueryCore::HEIGHT], \PDO::PARAM_INT);
            }
            if ($bIsWeight) {
                $rStmt->bindValue(':weight', $aParams[SearchQueryCore::WEIGHT], \PDO::PARAM_INT);
            }
            if ($bIsCountry) {
                $rStmt->bindParam(':country', $aParams[SearchQueryCore::COUNTRY], \PDO::PARAM_STR, 2);
            }
            if ($bIsCity) {
                $rStmt->bindValue(':city', '%' . str_replace('-', ' ', $aParams[SearchQueryCore::CITY]) . '%', \PDO::PARAM_STR);
            }
            if ($bIsState) {
                $rStmt->bindValue(':state', '%' . str_replace('-', ' ', $aParams[SearchQueryCore::STATE]) . '%', \PDO::PARAM_STR);
            }
            if ($bIsZipCode) {
                $rStmt->bindValue(':zipCode', '%' . $aParams[SearchQueryCore::ZIP_CODE] . '%', \PDO::PARAM_STR);
            }
            if ($bIsMail) {
                $rStmt->bindValue(':email', '%' . $aParams[SearchQueryCore::EMAIL] . '%', \PDO::PARAM_STR);
            }
            if ($bIsOnline) {
                $rStmt->bindValue(':userStatus', self::ONLINE_STATUS, \PDO::PARAM_INT);
            }
            if ($bHideUserLogged) {
                $rStmt->bindValue(':profileId', $this->iProfileId, \PDO::PARAM_INT);
            }
        }

        if (!$bCount) {
            $rStmt->bindParam(':offset', $iOffset, \PDO::PARAM_INT);
            $rStmt->bindParam(':limit', $iLimit, \PDO::PARAM_INT);
        }

        $rStmt->execute();

        if ($bCount) {
            $iTotalUsers = (int)$rStmt->fetchColumn();
            Db::free($rStmt);

            return $iTotalUsers;
        }

        $aRow = $rStmt->fetchAll(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return (array)$aRow;
    }

    /**
     * Check online status.
     *
     * @param int $iProfileId
     * @param int $iTimeout   number of minutes when a user becomes inactive (offline)
     *
     * @return bool
     */
    public function isOnline($iProfileId, $iTimeout = 1)
    {
        $iProfileId = (int)$iProfileId;
        $iTimeout = (int)$iTimeout;

        $rStmt = Db::getInstance()->prepare('SELECT profileId FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId
            AND userStatus = :userStatus AND lastActivity >= DATE_SUB(:currentTime, INTERVAL :time MINUTE) LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':userStatus', self::ONLINE_STATUS, \PDO::PARAM_INT);
        $rStmt->bindValue(':time', $iTimeout, \PDO::PARAM_INT);
        $rStmt->bindValue(':currentTime', $this->sCurrentDate, \PDO::PARAM_STR);
        $rStmt->execute();

        return $rStmt->rowCount() === 1;
    }

    /**
     * Set the user status.
     *
     * @param int iProfileId
     * @param int $iStatus Values: 0 = Offline, 1 = Online, 2 = Busy, 3 = Away
     *
     * @return void
     */
    public function setUserStatus($iProfileId, $iStatus)
    {
        $this->orm->update(DbTableName::MEMBER, 'userStatus', $iStatus, 'profileId', $iProfileId);
    }

    /**
     * Update user's last activity.
     *
     * @param int $iProfileId
     *
     * @return void
     */
    public function setLastActivity($iProfileId)
    {
        $this->orm->update(DbTableName::MEMBER, 'lastActivity', $this->sCurrentDate, 'profileId', $iProfileId);
    }

    /**
     * Get user's avatar status.
     *
     * @param int $iProfileId
     *
     * @return int
     */
    public function getAvatarStatus($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT approved FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $iStatus = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iStatus;
    }

    /**
     * Set user's avatar status.
     *
     * @param int $iProfileId
     * @param int $iStatus
     *
     * @return void
     */
    public function setAvatarStatus($iProfileId, $iStatus)
    {
        $this->orm->update(DbTableName::MEMBER, 'approved', $iStatus, 'profileId', $iProfileId);
    }

    /**
     * Set profile's main photo (avatar).
     *
     * @param int $iProfileId
     * @param string $sPhotoName
     *
     * @return void
     */
    public function setProfilePhoto($iProfileId, $sPhotoName)
    {
        $this->orm->update(DbTableName::MEMBER, 'avatar', $sPhotoName, 'profileId', $iProfileId);
    }

    /**
     * Get profile's main photo (avatar).
     *
     * @param int $iProfileId
     *
     * @return string
     */
    public function getProfilePhoto($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT avatar FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sAvatar = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sAvatar;
    }

    /**
     * Get profile's first name.
     *
     * @param int $iProfileId
     *
     * @return string
     */
    public function getFirstName($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT firstName FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sFirstName = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sFirstName;
    }

    /**
     * Get profile's sex.
     *
     * @param int $iProfileId
     *
     * @return string
     */
    public function getSex($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT sex FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sSex = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sSex;
    }

    /**
     * Get profile's username.
     *
     * @param int $iProfileId
     *
     * @return string
     */
    public function getUsername($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT username FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sUsername = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sUsername;
    }

    /**
     * Get profile's email.
     *
     * @param int $iProfileId
     *
     * @return string
     */
    public function getEmail($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT email FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sEmail = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sEmail;
    }

    /**
     * Get user's group ID.
     *
     * @param int $iProfileId
     *
     * @return int
     */
    public function getGroupId($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT groupId FROM' . Db::prefix(DbTableName::MEMBER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $iGroupId = (int)$rStmt->fetchColumn();
        Db::free($rStmt);

        return $iGroupId;
    }

    /**
     * Get membership name.
     *
     * @param int $iGroupId
     *
     * @return string
     */
    public function getMembershipName($iGroupId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT name FROM' . Db::prefix(DbTableName::MEMBERSHIP) . 'WHERE groupId = :groupId LIMIT 1');
        $rStmt->bindValue(':groupId', $iGroupId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sName = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sName;
    }

    /**
     * Get user's membership expiration date.
     *
     * @param int $iProfileId
     *
     * @return string|null
     */
    public function getMembershipExpiration($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT expirationDate FROM' . Db::prefix(DbTableName::MEMBERSHIP_USER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sDate = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sDate;
    }

    /**
     * Get user's membership start date.
     *
     * @param int $iProfileId
     *
     * @return string|null
     */
    public function getMembershipStartDate($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT startDate FROM' . Db::prefix(DbTableName::MEMBERSHIP_USER) . 'WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $sDate = $rStmt->fetchColumn();
        Db::free($rStmt);

        return $sDate;
    }

    /**
     * Get user's membership data.
     *
     * @param int $iProfileId
     *
     * @return \stdClass|bool
     */
    public function getMembership($iProfileId)
    {
        $rStmt = Db::getInstance()->prepare('SELECT m.* FROM' . Db::prefix(DbTableName::MEMBERSHIP) . ' AS m INNER JOIN' . Db::prefix(DbTableName::MEMBERSHIP_USER) . ' AS u USING(groupId) WHERE u.profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->execute();
        $oRow = $rStmt->fetch(\PDO::FETCH_OBJ);
        Db::free($rStmt);

        return $oRow;
    }

    /**
     * Update membership group.
     *
     * @param int $iGroupId
     * @param int $iProfileId
     * @param string $sDate
     * @param string|null $sExpirationDate
     *
     * @return bool
     */
    public function updateMembership($iGroupId, $iProfileId, $sDate, $sExpirationDate = null)
    {
        $rStmt = Db::getInstance()->prepare('UPDATE' . Db::prefix(DbTableName::MEMBERSHIP_USER) . 'SET groupId = :groupId, startDate = :startDate, expirationDate = :expirationDate WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':groupId', $iGroupId, \PDO::PARAM_INT);
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':startDate', $sDate, \PDO::PARAM_STR);
        $rStmt->bindValue(':expirationDate', $sExpirationDate, \PDO::PARAM_STR);

        return $rStmt->execute();
    }

    /**
     * Update user membership.
     *
     * @param int $iGroupId
     * @param int $iProfileId
     * @param string $sDate
     *
     * @return bool
     */
    public function updateMembership($iGroupId, $iProfileId, $sDate, $sExpirationDate = null)
    {
        $rStmt = Db::getInstance()->prepare('UPDATE' . Db::prefix(DbTableName::MEMBERSHIP_USER) . 'SET groupId = :groupId, startDate = :startDate, expirationDate = :expirationDate WHERE profileId = :profileId LIMIT 1');
        $rStmt->bindValue(':groupId', $iGroupId, \PDO::PARAM_INT);
        $rStmt->bindValue(':profileId', $iProfileId, \PDO::PARAM_INT);
        $rStmt->bindValue(':startDate', $sDate, \PDO::PARAM_STR);
        $rStmt->bindValue(':expirationDate', $sExpirationDate, \PDO::PARAM_STR);

        return $rStmt->execute();
    }
}
