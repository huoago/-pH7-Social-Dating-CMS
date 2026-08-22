<?php
/**
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 * @package        PH7 / App / System / Module / Friend / Asset / Ajax
 */

namespace PH7;

defined('PH7') or exit('Restricted access');

use PH7\Framework\File\Import;
use PH7\Framework\Http\Http;
use PH7\Framework\Mail\Mail;
use PH7\Framework\Mvc\Model\DbConfig;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Security\CSRF\Token;
use PH7\JustHttp\StatusCode;

class FriendAjax extends Core
{
    /** @var FriendModel */
    private $oFriendModel;

    /** @var string */
    private $sMsg;

    /** @var bool|string */
    private $mStatus;

    public function __construct()
    {
        parent::__construct();

        if (!(new Token)->check('friend')) {
            exit(jsonMsg(0, Form::errorTokenMsg()));
        }

        Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.BlockModel');
        $this->oFriendModel = new FriendModel;

        switch ($this->httpRequest->post('type')) {
            case 'add':
                $this->add();
                break;

            case 'approval':
                $this->approval();
                break;

            case 'delete':
                $this->delete();
                break;

            default:
                Http::setHeadersByCode(StatusCode::BAD_REQUEST);
                exit('Bad Request Error!');
        }
    }

    private function add()
    {
        $iFriendId = $this->httpRequest->post('friendId', 'int');
        $iMemberId = (int)$this->session->get('member_id');

        if ($iMemberId === $iFriendId) {
            $this->sMsg = jsonMsg(0, t('You cannot be your own friend.'));
        } elseif ((new BlockModel())->hasBlockBetween($iMemberId, (int)$iFriendId)) {
            $this->sMsg = jsonMsg(0, 'No puedes añadir este perfil porque existe un bloqueo entre las cuentas.');
        } else {
            $this->mStatus = $this->oFriendModel->add(
                $iMemberId,
                $iFriendId,
                $this->dateTime->get()->dateTime('Y-m-d H:i:s')
            );

            if ($this->mStatus === FriendModel::ERROR_STATUS) {
                $this->sMsg = jsonMsg(0, t('Unable to add to friends list. Please try later.'));
            } elseif ($this->mStatus === FriendModel::EXISTS_STATUS) {
                $this->sMsg = jsonMsg(0, t('This profile already exists in your friends list.'));
            } elseif ($this->mStatus === FriendModel::UNEXISTENT_ID_STATUS) {
                $this->sMsg = jsonMsg(0, t('Profile ID does not exist.'));
            } elseif ($this->mStatus === FriendModel::SUCCESS_STATUS) {
                $this->sMsg = jsonMsg(1, t('Profile successfully added to your friends list.'));

                $oUserModel = new UserCoreModel;
                if ($this->canSendEmail($iFriendId, $oUserModel)) {
                    $this->sendMail($iFriendId, $oUserModel);
                }
                unset($oUserModel);
            }
        }

        echo $this->sMsg;
    }

    private function approval()
    {
        $iMemberId = (int)$this->session->get('member_id');
        $iFriendId = (int)$this->httpRequest->post('friendId', 'int');

        if ((new BlockModel())->hasBlockBetween($iMemberId, $iFriendId)) {
            $this->sMsg = jsonMsg(0, 'No puedes aprobar esta solicitud porque existe un bloqueo entre las cuentas.');
            echo $this->sMsg;
            return;
        }

        $this->mStatus = $this->oFriendModel->approval($iMemberId, $iFriendId);

        if (!$this->mStatus) {
            $this->sMsg = jsonMsg(0, t('Cannot approve the friend. Please try later.'));
        } else {
            $this->sMsg = jsonMsg(1, t('The friend has been approved.'));
        }

        echo $this->sMsg;
    }

    private function delete()
    {
        $this->mStatus = $this->oFriendModel->delete(
            $this->session->get('member_id'),
            $this->httpRequest->post('friendId')
        );

        if (!$this->mStatus) {
            $this->sMsg = jsonMsg(0, t('Cannot remove the friend. Please try later.'));
        } else {
            $this->sMsg = jsonMsg(1, t('The friend has been removed.'));
        }

        echo $this->sMsg;
    }

    private function sendMail($iId, UserCoreModel $oUserModel)
    {
        $sFriendEmail = $oUserModel->getEmail($iId);
        $sFriendUsername = $oUserModel->getUsername($iId);
        $sSiteName = DbConfig::getSetting('siteName');

        $this->view->content = t('Hello %0%!', $sFriendUsername) . '<br />' .
            t('<strong>%0%</strong> sent you a friendship request on %1%.', $this->session->get('member_username'), $sSiteName) . '<br />' .
            t('<a href="%0%">Click here</a> to see your friend request.', Uri::get('friend', 'main', 'index'));

        $sMessageHtml = $this->view->parseMail(
            PH7_PATH_SYS . 'global/' . PH7_VIEWS . PH7_DEFAULT_THEME . '/tpl/mail/sys/mod/friend/friend_request.tpl',
            $sFriendEmail
        );

        $aInfo = [
            'to' => $sFriendEmail,
            'subject' => t('%0% wants to be friends with you on %1%', $this->session->get('member_first_name'), $sSiteName)
        ];

        (new Mail)->send($aInfo, $sMessageHtml);
    }

    private function canSendEmail($iFriendId, UserCoreModel $oUserModel)
    {
        return $oUserModel->isNotification($iFriendId, 'friendRequest')
            && !$oUserModel->isOnline($iFriendId);
    }
}

if (UserCore::auth()) {
    new FriendAjax;
}
