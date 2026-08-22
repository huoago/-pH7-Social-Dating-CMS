<?php

/**
 * @title          Chat Messenger Ajax
 *
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 *
 * @version        1.6
 */

namespace PH7;

defined('PH7') or exit('Restricted access');

use PH7\Framework\Date\CDateTime;
use PH7\Framework\Date\Various as VDate;
use PH7\Framework\File\Import;
use PH7\Framework\Http\Http;
use PH7\Framework\Module\Various as SysMod;
use PH7\Framework\Mvc\Model\DbConfig;
use PH7\Framework\Mvc\Request\Http as HttpRequest;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Parse\Emoticon;
use PH7\Framework\Security\CSRF\Token;
use PH7\Framework\Session\Session;
use PH7\JustHttp\StatusCode;

class MessengerAjax extends PermissionCore
{
    private const DATETIME_FORMAT = 'Y-m-d H:i:s';
    private const SEND_COOLDOWN_SECONDS = 2;
    private const MAX_MESSAGE_LENGTH = 1000;

    private HttpRequest $oHttpRequest;

    private MessengerModel $oMessengerModel;

    public function __construct()
    {
        parent::__construct();

        if (!(new Token())->checkUrl()) {
            Http::setHeadersByCode(StatusCode::FORBIDDEN);
            exit(jsonMsg(0, Form::errorTokenMsg()));
        }

        Import::pH7App(PH7_SYS . PH7_MOD . 'im.models.MessengerModel');
        Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.BlockModel');

        $this->oHttpRequest = new HttpRequest();
        $this->oMessengerModel = new MessengerModel();

        switch ($this->oHttpRequest->get('act')) {
            case 'heartbeat':
                $this->heartbeat();
                break;
            case 'send':
                $this->send();
                break;
            case 'close':
                $this->close();
                break;
            case 'startsession':
                $this->startSession();
                break;
            default:
                Http::setHeadersByCode(StatusCode::BAD_REQUEST);
                exit('Bad Request Error!');
        }

        if (empty($_SESSION['messenger_history'])) {
            $_SESSION['messenger_history'] = [];
        }

        if (empty($_SESSION['messenger_openBoxes'])) {
            $_SESSION['messenger_openBoxes'] = [];
        }
    }

    protected function heartbeat()
    {
        $sCurrentUser = $_SESSION['messenger_username'];
        $sFrom = $sCurrentUser;
        $sTo = !empty($_SESSION['messenger_username_to']) ? $_SESSION['messenger_username_to'] : 0;

        $oQuery = $this->oMessengerModel->select($sCurrentUser);
        $sItems = '';

        foreach ($oQuery as $oData) {
            $sFrom = escape($oData->fromUser, true);

            if ($this->isBlockedConversation($sCurrentUser, $sFrom)) {
                $this->oMessengerModel->markReceivedById((int)$oData->messengerId);
                unset($_SESSION['messenger_openBoxes'][$sFrom], $_SESSION['messenger_history'][$sFrom]);
                continue;
            }

            $sSent = escape($oData->sent, true);
            $sMsg = $this->sanitize($oData->message);
            $sMsg = Emoticon::init($sMsg, false);

            if (!isset($_SESSION['messenger_openBoxes'][$sFrom]) && isset($_SESSION['messenger_history'][$sFrom])) {
                $sItems = $_SESSION['messenger_history'][$sFrom];
            }

            $sItems .= $this->setJsonContent(['user' => $sFrom, 'msg' => $sMsg]);

            if (!isset($_SESSION['messenger_history'][$sFrom])) {
                $_SESSION['messenger_history'][$sFrom] = '';
            }

            $_SESSION['messenger_history'][$sFrom] .= $this->setJsonContent(['user' => $sFrom, 'msg' => $sMsg]);

            unset($_SESSION['messenger_boxes'][$sFrom]);
            $_SESSION['messenger_openBoxes'][$sFrom] = $sSent;
        }

        if (!empty($_SESSION['messenger_openBoxes'])) {
            foreach ($_SESSION['messenger_openBoxes'] as $sBox => $sTime) {
                if ($this->isBlockedConversation($sCurrentUser, $sBox)) {
                    unset($_SESSION['messenger_openBoxes'][$sBox], $_SESSION['messenger_history'][$sBox]);
                    continue;
                }

                if (!isset($_SESSION['messenger_boxes'][$sBox])) {
                    $iNow = time() - strtotime($sTime);
                    $sMsg = t('Sent %0%', VDate::textTimeStamp($sTime));
                    if ($iNow > 180) {
                        $sItems .= $this->setJsonContent(['status' => '2', 'user' => $sBox, 'msg' => $sMsg]);

                        if (!isset($_SESSION['messenger_history'][$sBox])) {
                            $_SESSION['messenger_history'][$sBox] = '';
                        }

                        $_SESSION['messenger_history'][$sBox] .= $this->setJsonContent(['status' => '2', 'user' => $sBox, 'msg' => $sMsg]);
                        $_SESSION['messenger_boxes'][$sBox] = 1;
                    }
                }
            }
        }

        if (!$this->isOnline($sCurrentUser)) {
            $sItems = t('You need the ONLINE status in order to speak instantaneous.');
        } elseif ($sTo !== 0 && $this->isBlockedConversation($sCurrentUser, (string)$sTo)) {
            $sItems = '<small><em>Conversación deshabilitada por bloqueo.</em></small>';
        } elseif ($sTo !== 0 && !$this->isOnline($sTo)) {
            if (SysMod::isEnabled('mail')) {
                $sItems = '<small><em>' . t("%0% is offline. Send a <a href='%1%'>Private Message</a> instead.", $sTo, Uri::get('mail', 'main', 'compose', $sTo)) . '</em></small>';
            } else {
                $sItems = '<small><em>' . t('%0% is currently offline. Why not to chat later on?', $sTo) . '</em></small>';
            }
        } else {
            $this->oMessengerModel->update($sCurrentUser, $sTo);
        }

        if ($sItems !== '') {
            $sItems = substr($sItems, 0, -1);
        }

        Http::setContentType('application/json');
        echo '{"items": [' . $sItems . ']}';
        exit;
    }

    protected function boxSession($sBox)
    {
        $sItems = '';

        if (isset($_SESSION['messenger_history'][$sBox])) {
            $sItems = $_SESSION['messenger_history'][$sBox];
        }

        return $sItems;
    }

    protected function startSession()
    {
        $sItems = '';
        if (!empty($_SESSION['messenger_openBoxes'])) {
            foreach ($_SESSION['messenger_openBoxes'] as $sBox => $sVoid) {
                if (!$this->isBlockedConversation($_SESSION['messenger_username'], $sBox)) {
                    $sItems .= $this->boxSession($sBox);
                }
            }
        }

        if ($sItems !== '') {
            $sItems = substr($sItems, 0, -1);
        }

        Http::setContentType('application/json');
        echo '{
            "user": "' . $_SESSION['messenger_username'] . '",
            "items": [' . $sItems . ']
        }';
        exit;
    }

    protected function send()
    {
        $sFrom = $_SESSION['messenger_username'];
        $sTo = $_SESSION['messenger_username_to'] = trim((string)$this->oHttpRequest->post('to'));
        $sMsg = trim((string)$this->oHttpRequest->post('message'));

        $_SESSION['messenger_openBoxes'][$sTo] = date(self::DATETIME_FORMAT, time());

        $sMsgTransform = $this->sanitize($sMsg);
        $sMsgTransform = Emoticon::init($sMsgTransform, false);

        if (!isset($_SESSION['messenger_history'][$sTo])) {
            $_SESSION['messenger_history'][$sTo] = '';
        }

        $iNow = time();
        $iLastSend = isset($_SESSION['messenger_last_send'][$sTo]) ? (int)$_SESSION['messenger_last_send'][$sTo] : 0;

        if (!$this->checkMembership() || !$this->group->instant_messaging) {
            $sMsgTransform = t("You need to <a href='%0%'>upgrade your membership</a> to be able to chat.", Uri::get('payment', 'main', 'index'));
        } elseif ($sMsg === '' || mb_strlen($sMsg) > self::MAX_MESSAGE_LENGTH) {
            $sMsgTransform = 'El mensaje debe tener entre 1 y ' . self::MAX_MESSAGE_LENGTH . ' caracteres.';
        } elseif ($iNow - $iLastSend < self::SEND_COOLDOWN_SECONDS) {
            $sMsgTransform = 'Estás enviando mensajes demasiado rápido. Espera un momento.';
        } elseif ($this->isBlockedConversation($sFrom, $sTo)) {
            $sMsgTransform = 'Conversación deshabilitada por bloqueo.';
            unset($_SESSION['messenger_openBoxes'][$sTo]);
        } elseif (!$this->isOnline($sFrom)) {
            $sMsgTransform = t('You need the ONLINE status in order to chat with other users.');
        } elseif (!$this->isOnline($sTo)) {
            if (SysMod::isEnabled('mail')) {
                $sMsgTransform = '<small><em>' . t("%0% is offline. Send a <a href='%1%'>Private Message</a> instead.", $sTo, Uri::get('mail', 'main', 'compose', $sTo)) . '</em></small>';
            } else {
                $sMsgTransform = '<small><em>' . t('%0% is currently offline. Maybe, try to chat later on? 😉', $sTo) . '</em></small>';
            }
        } else {
            $this->oMessengerModel->insert($sFrom, $sTo, $sMsg, (new CDateTime())->get()->dateTime(self::DATETIME_FORMAT));
            $_SESSION['messenger_last_send'][$sTo] = $iNow;
        }

        $_SESSION['messenger_history'][$sTo] .= $this->setJsonContent(['status' => '1', 'user' => $sTo, 'msg' => $sMsgTransform]);

        unset($_SESSION['messenger_boxes'][$sTo]);

        Http::setContentType('application/json');
        echo $this->setJsonContent(
            [
                'user' => $sFrom,
                'msg' => $sMsgTransform
            ],
            false
        );
        exit;
    }

    protected function close()
    {
        unset($_SESSION['messenger_openBoxes'][$this->oHttpRequest->post('box')]);
        exit(1);
    }

    protected function setJsonContent(array $aData, $bEndComma = true)
    {
        $aDefData = [
            'status' => '0',
            'user' => '',
            'msg' => ''
        ];

        $aData += $aDefData;

        $sJsonData = json_encode(
            $aData,
            JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
        );

        return $bEndComma ? $sJsonData . ',' : $sJsonData;
    }

    protected function isOnline($sUsername)
    {
        $oUserModel = new UserCoreModel();
        $iProfileId = $oUserModel->getId(null, $sUsername);
        $bIsOnline = $oUserModel->isOnline($iProfileId, DbConfig::getSetting('userTimeout'));
        unset($oUserModel);

        return $bIsOnline;
    }

    private function isBlockedConversation(string $sFirstUsername, string $sSecondUsername): bool
    {
        if ($sFirstUsername === '' || $sSecondUsername === '') {
            return false;
        }

        $oUserModel = new UserCoreModel();
        $iFirstId = (int)$oUserModel->getId(null, $sFirstUsername);
        $iSecondId = (int)$oUserModel->getId(null, $sSecondUsername);
        unset($oUserModel);

        if ($iFirstId <= 0 || $iSecondId <= 0) {
            return false;
        }

        return (new BlockModel())->hasBlockBetween($iFirstId, $iSecondId);
    }

    protected function sanitize($sText)
    {
        $sText = escape($sText);
        $sText = str_replace("\n\r", "\n", $sText);
        $sText = str_replace("\r\n", "\n", $sText);
        $sText = str_replace("\n", '<br>', $sText);

        return $sText;
    }
}

if (UserCore::auth()) {
    $oSession = new Session();
    if (empty($_SESSION['messenger_username'])) {
        $_SESSION['messenger_username'] = $oSession->get('member_username');
    }
    unset($oSession);

    new MessengerAjax();
}
