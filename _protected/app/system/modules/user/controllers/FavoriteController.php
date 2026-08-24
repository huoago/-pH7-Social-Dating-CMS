<?php
/**
 * DeseoCerca profile favorites controller.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Navigation\Page;
use PH7\Framework\Security\CSRF\Token;
use PH7\Framework\Url\Header;

class FavoriteController extends Controller
{
    private const MAX_PROFILES_PER_PAGE = 24;

    public function index(): void
    {
        if (!UserCore::auth()) {
            Header::redirect(Uri::get('user', 'main', 'login'));
            return;
        }

        $iProfileId = (int)$this->session->get('member_id');
        $oPage = new Page();
        $oModel = new FavoriteModel();
        $iTotal = $oModel->count($iProfileId);

        $this->view->total_pages = $oPage->getTotalPages($iTotal, self::MAX_PROFILES_PER_PAGE);
        $this->view->current_page = $oPage->getCurrentPage();
        $this->view->users = $oModel->get(
            $iProfileId,
            $oPage->getFirstItem(),
            $oPage->getNbItemsPerPage()
        );
        $this->view->avatarDesign = new AvatarDesignCore();
        $this->view->page_title = 'Mis favoritos';
        $this->view->h1_title = '<span class="pH1">Mis favoritos</span>';
        $this->view->meta_description = 'Perfiles guardados en tu cuenta de DeseoCerca.';
        $this->output();
    }

    public function toggle(): void
    {
        if (!UserCore::auth()) {
            Header::redirect(Uri::get('user', 'main', 'login'));
            return;
        }

        $oToken = new Token();
        if (!$oToken->check('favorite')) {
            Header::redirect(Uri::get('user', 'browse', 'index'));
            return;
        }

        $iProfileId = (int)$this->session->get('member_id');
        $iFavoriteId = (int)$this->httpRequest->post('favorite_id', 'int');
        $oUserModel = new UserCoreModel();
        $sUsername = (string)$oUserModel->getUsername($iFavoriteId);

        if ($iFavoriteId <= 0 || $iFavoriteId === $iProfileId || empty($sUsername)) {
            Header::redirect(Uri::get('user', 'browse', 'index'));
            return;
        }

        $oModel = new FavoriteModel();
        if ($oModel->exists($iProfileId, $iFavoriteId)) {
            $oModel->remove($iProfileId, $iFavoriteId);
        } else {
            $oModel->add($iProfileId, $iFavoriteId);
        }

        Header::redirect((new UserCore())->getProfileLink($sUsername));
    }
}
