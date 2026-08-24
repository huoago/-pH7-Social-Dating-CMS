<?php
/**
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 * @package        PH7 / App / System / Module / User / Controller
 */

namespace PH7;

use DateTimeImmutable;
use PH7\Framework\File\Import;
use PH7\Framework\Module\Various as SysMod;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Url\Header;

class AccountController extends Controller
{
    public function index()
    {
        Header::redirect($this->getHomepageUrl());
    }

    /**
     * @param string $sMail
     * @param string $sHash
     *
     * @return void
     */
    public function activate($sMail, $sHash)
    {
        (new UserCore)->activateAccount(
            $sMail,
            $sHash,
            $this->config,
            $this->registry
        );
    }

    /**
     * Restore an account that is inside the DeseoCerca recovery window.
     */
    public function recoverDeletion(string $sToken = ''): void
    {
        if (!preg_match('/^[a-f0-9]{64}$/', $sToken)) {
            Header::redirect(
                Uri::get('user', 'main', 'login'),
                t('This account recovery link is invalid or has expired.')
            );

            return;
        }

        Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.AccountLifecycleModel');
        $oLifecycleModel = new AccountLifecycleModel();
        $oLifecycle = $oLifecycleModel->findRecoverableByTokenHash(hash('sha256', $sToken));

        if ($oLifecycle === null) {
            Header::redirect(
                Uri::get('user', 'main', 'login'),
                t('This account recovery link is invalid or has expired.')
            );

            return;
        }

        if (
            $oLifecycle->state === AccountLifecycleModel::STATE_DELETION_PENDING
            && !empty($oLifecycle->deleteScheduledAt)
            && new DateTimeImmutable((string)$oLifecycle->deleteScheduledAt) <= new DateTimeImmutable('now')
        ) {
            Header::redirect(
                Uri::get('user', 'main', 'login'),
                t('The 90-day recovery period for this account has expired.')
            );

            return;
        }

        if (!$oLifecycleModel->recover((int)$oLifecycle->profileId)) {
            Header::redirect(
                Uri::get('user', 'main', 'login'),
                t('We could not recover this account. Please contact support.')
            );

            return;
        }

        Header::redirect(
            Uri::get('user', 'main', 'login'),
            t('Your DeseoCerca account has been reactivated. You can sign in again now.')
        );
    }

    /**
     * Redirect this page to the user homepage.
     *
     * @return string
     */
    private function getHomepageUrl()
    {
        if (SysMod::isEnabled('user-dashboard')) {
            return Uri::get('user-dashboard', 'main', 'index');
        }

        return Uri::get('user', 'main', 'index');
    }
}
