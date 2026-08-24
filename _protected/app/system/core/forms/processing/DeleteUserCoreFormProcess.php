<?php
/**
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 * @package        PH7 / App / System / Core / Form / Processing
 */

declare(strict_types=1);

namespace PH7;

defined('PH7') or exit('Restricted access');

use PH7\Framework\File\Import;
use PH7\Framework\Mail\Mail;
use PH7\Framework\Mvc\Model\DbConfig;
use PH7\Framework\Mvc\Request\Http;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Url\Header;

/** For "user" and "affiliate" modules **/
class DeleteUserCoreFormProcess extends Form
{
    private UserModel $oUserModel;

    private string $sSessPrefix;

    private string $sUsername;

    private string $sEmail;

    public function __construct()
    {
        parent::__construct();

        $this->oUserModel = new UserCoreModel;

        $this->sSessPrefix = $this->registry->module === 'user' ? 'member' : 'affiliate';
        $this->sUsername = $this->session->get($this->sSessPrefix . '_username');
        $this->sEmail = $this->session->get($this->sSessPrefix . '_email');
        $sTable = $this->registry->module === 'user' ? DbTableName::MEMBER : DbTableName::AFFILIATE;

        $mLogin = $this->oUserModel->login($this->sEmail, $this->httpRequest->post('password', Http::NO_CLEAN), $sTable);
        if ($mLogin === CredentialStatusCore::INCORRECT_PASSWORD_IN_DB) {
            \PFBC\Form::setError('form_delete_account', t('Oops! This password you entered is incorrect.'));

            return;
        }

        $this->session->regenerateId();

        if ($this->registry->module === 'user') {
            $this->scheduleMemberDeletion();

            return;
        }

        // Affiliates keep the upstream immediate-delete behavior. The 90-day
        // recovery policy applies to DeseoCerca member profiles only.
        $this->sendWarnEmail();
        $this->removeAccount();
        (new UserCore)->logout($this->session);
        $this->redirectToGoodbyePage();
    }

    /**
     * Schedule a member profile for deletion after a 90-day recovery window.
     */
    private function scheduleMemberDeletion(): void
    {
        Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.AccountLifecycleModel');

        $iProfileId = (int)$this->session->get('member_id');
        $sRecoveryToken = bin2hex(random_bytes(32));
        $sRecoveryTokenHash = hash('sha256', $sRecoveryToken);
        $oLifecycleModel = new AccountLifecycleModel();

        if (!$oLifecycleModel->scheduleDeletion($iProfileId, $sRecoveryTokenHash)) {
            \PFBC\Form::setError(
                'form_delete_account',
                t('We could not schedule your account deletion. Please try again or contact support.')
            );

            return;
        }

        // active=0 removes the profile from ordinary account access while the
        // lifecycle record keeps the recovery path available for 90 days.
        $this->oUserModel->approve($iProfileId, 0);
        $this->sendWarnEmail();
        $this->sendRecoveryEmail($sRecoveryToken);
        (new UserCore)->logout($this->session);

        Header::redirect(
            Uri::get('user', 'main', 'index'),
            t('Your account is deactivated and scheduled for deletion in 90 days. We sent you a recovery link in case you change your mind.')
        );
    }

    /**
     * Send the account owner a recovery link whose raw token is never stored.
     */
    private function sendRecoveryEmail(string $sRecoveryToken): bool
    {
        $sRecoveryLink = Uri::get('user', 'account', 'recoverdeletion') . PH7_SH . $sRecoveryToken;
        $sSafeLink = htmlspecialchars($sRecoveryLink, ENT_QUOTES, PH7_ENCODING);
        $sMessageHtml = '<p>Tu cuenta de DeseoCerca ha sido desactivada y está programada para eliminarse definitivamente en 90 días.</p>'
            . '<p>Si cambias de opinión antes de que termine ese plazo, puedes recuperar la cuenta desde este enlace:</p>'
            . '<p><a href="' . $sSafeLink . '">' . $sSafeLink . '</a></p>'
            . '<p>Si solicitaste la eliminación, no necesitas hacer nada más.</p>';

        return (new Mail())->send(
            [
                'to' => $this->sEmail,
                'subject' => 'DeseoCerca: recuperación de cuenta antes de la eliminación'
            ],
            $sMessageHtml
        );
    }

    /**
     * Send an email to the admin saying the reason why a user wanted to delete their account.
     *
     * @throws Framework\Layout\Tpl\Engine\PH7Tpl\Exception
     * @throws Framework\Mvc\Request\WrongRequestMethodException
     */
    private function sendWarnEmail(): bool
    {
        $sAdminEmail = DbConfig::getSetting('adminEmail');

        $sMembershipType = $this->registry->module === 'affiliate' ? t('Affiliate') : t('Member');

        $this->view->membership = t('User Type: %0%.', $sMembershipType);
        $this->view->message = nl2br($this->httpRequest->post('message'));
        $this->view->why_delete = t('Reason why the user wanted to leave: %0%', $this->httpRequest->post('why_delete'));
        $this->view->footer_title = t('User Information');
        $this->view->email = t('Email: %0%', $this->sEmail);
        $this->view->username = t('Username: %0%', $this->sUsername);
        $this->view->first_name = t('First Name: %0%', $this->session->get($this->sSessPrefix . '_first_name'));
        $this->view->sex = t('Sex: %0%', $this->session->get($this->sSessPrefix . '_sex'));
        $this->view->ip = t('User IP: %0%', $this->session->get($this->sSessPrefix . '_ip'));
        $this->view->browser_info = t('Browser info: %0%', $this->session->get($this->sSessPrefix . '_http_user_agent'));

        $sMessageHtml = $this->view->parseMail(
            PH7_PATH_SYS . 'global/' . PH7_VIEWS . PH7_TPL_MAIL_NAME . '/tpl/mail/sys/core/delete_account.tpl',
            $sAdminEmail
        );

        $sMembershipName = $this->registry->module === 'user' ? t('Member') : t('Affiliate');
        $sSubject = $this->registry->module === 'user'
            ? t('Scheduled deletion request - %0%: %1%', $sMembershipName, $this->sUsername)
            : t('Unsubscribe %0% - User: %1%', $sMembershipName, $this->sUsername);

        return (new Mail)->send(
            [
                'to' => $sAdminEmail,
                'subject' => $sSubject
            ],
            $sMessageHtml
        );
    }

    /**
     * Remove the affiliate account immediately using the upstream behavior.
     */
    private function removeAccount(): void
    {
        $oUser = new AffiliateCore;
        $oUser->delete($this->session->get($this->sSessPrefix . '_id'), $this->sUsername, $this->oUserModel);
        unset($oUser);
    }

    /**
     * Redirect the user to the goodbye (accountDeleted) page.
     *
     * @throws Framework\File\IOException
     */
    private function redirectToGoodbyePage(): void
    {
        Header::redirect(
            Uri::get('user', 'main', 'accountdeleted')
        );
    }
}
