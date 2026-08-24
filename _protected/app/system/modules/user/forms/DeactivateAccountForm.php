<?php
/**
 * DeseoCerca recoverable manual account deactivation form.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

defined('PH7') or exit('Restricted access');

use PFBC\Element\Button;
use PFBC\Element\Hidden;
use PFBC\Element\HTMLExternal;
use PFBC\Element\Password;
use PFBC\Element\Token;
use PH7\Framework\Url\Header;

final class DeactivateAccountForm
{
    public static function display(): void
    {
        if (isset($_POST['submit_deactivate_account'])) {
            if (\PFBC\Form::isValid($_POST['submit_deactivate_account'])) {
                new DeactivateAccountFormProcess();
            }

            Header::redirect();
        }

        $oForm = new \PFBC\Form('form_deactivate_account');
        $oForm->configure(['action' => '']);
        $oForm->addElement(new Hidden('submit_deactivate_account', 'form_deactivate_account'));
        $oForm->addElement(new Token('deactivate_account'));
        $oForm->addElement(
            new HTMLExternal(
                '<p>Al desactivar temporalmente tu cuenta, tu perfil dejará de mostrarse y no podrás iniciar sesión normalmente. '
                . 'No eliminaremos tus datos. Te enviaremos un enlace seguro para reactivar la cuenta cuando quieras.</p>'
            )
        );
        $oForm->addElement(new Password('Contraseña actual:', 'password', ['required' => 1]));
        $oForm->addElement(new Button('Desactivar cuenta temporalmente', 'submit', ['icon' => 'pause']));
        $oForm->render();
    }
}
