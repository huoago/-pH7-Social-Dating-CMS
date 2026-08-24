<?php
/**
 * DeseoCerca recoverable manual account deactivation processing.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

defined('PH7') or exit('Restricted access');

use PH7\Framework\File\Import;
use PH7\Framework\Mail\Mail;
use PH7\Framework\Mvc\Request\Http;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Url\Header;

final class DeactivateAccountFormProcess extends Form
{
    public function __construct()
    {
        parent::__construct();

        $iProfileId = (int)$this->session->get('member_id');
        $sEmail = (string)$this->session->get('member_email');
        $oUserModel = new UserCoreModel();
        $mLogin = $oUserModel->login(
            $sEmail,
            $this->httpRequest->post('password', Http::NO_CLEAN),
            DbTableName::MEMBER
        );

        if ($mLogin !== true) {
            \PFBC\Form::setError('form_deactivate_account', 'La contraseña actual no es correcta.');

            return;
        }

        $this->session->regenerateId();
        Import::pH7App(PH7_SYS . PH7_MOD . 'user.models.AccountLifecycleModel');

        $sRecoveryToken = bin2hex(random_bytes(32));
        $sRecoveryTokenHash = hash('sha256', $sRecoveryToken);
        $oLifecycleModel = new AccountLifecycleModel();

        if (!$oLifecycleModel->deactivateManually($iProfileId, $sRecoveryTokenHash)) {
            \PFBC\Form::setError(
                'form_deactivate_account',
                'No pudimos desactivar la cuenta. Inténtalo de nuevo o contacta con soporte.'
            );

            return;
        }

        try {
            if (!$this->sendRecoveryEmail($sEmail, $sRecoveryToken)) {
                throw new \RuntimeException('Recovery email was not accepted by the mail transport.');
            }
        } catch (\Throwable $oException) {
            try {
                $oLifecycleModel->recover($iProfileId);
            } catch (\Throwable $oRecoveryException) {
                error_log('DeseoCerca manual-deactivation rollback failed: ' . $oRecoveryException->getMessage());
            }

            error_log('DeseoCerca manual-deactivation mail failed: ' . $oException->getMessage());
            \PFBC\Form::setError(
                'form_deactivate_account',
                'No pudimos enviar el enlace de recuperación. La cuenta permanece activa; inténtalo de nuevo más tarde.'
            );

            return;
        }

        (new UserCore())->logout($this->session);
        Header::redirect(
            Uri::get('user', 'main', 'index'),
            'Tu cuenta se ha desactivado temporalmente. Revisa tu correo para conservar el enlace de reactivación.'
        );
    }

    private function sendRecoveryEmail(string $sEmail, string $sRecoveryToken): bool
    {
        $sRecoveryLink = Uri::get('user', 'account', 'recoverdeletion') . PH7_SH . $sRecoveryToken;
        $sSafeLink = htmlspecialchars($sRecoveryLink, ENT_QUOTES, PH7_ENCODING);
        $sMessageHtml = '<p>Tu cuenta de DeseoCerca ha sido desactivada temporalmente.</p>'
            . '<p>Tu perfil deja de estar disponible, pero no hemos eliminado tus datos.</p>'
            . '<p>Cuando quieras volver, reactiva tu cuenta desde este enlace seguro:</p>'
            . '<p><a href="' . $sSafeLink . '">' . $sSafeLink . '</a></p>';

        return (new Mail())->send(
            [
                'to' => $sEmail,
                'subject' => 'DeseoCerca: enlace para reactivar tu cuenta',
            ],
            $sMessageHtml
        );
    }
}
