<?php
/**
 * DeseoCerca user blocking controller.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Navigation\Page;
use PH7\Framework\Security\CSRF\Token;
use PH7\Framework\Url\Header;

class BlockController extends Controller
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
        $oModel = new BlockModel();
        $iTotal = $oModel->count($iProfileId);

        $this->view->total_pages = $oPage->getTotalPages($iTotal, self::MAX_PROFILES_PER_PAGE);
        $this->view->current_page = $oPage->getCurrentPage();
        $this->view->users = $oModel->get(
            $iProfileId,
            $oPage->getFirstItem(),
            $oPage->getNbItemsPerPage()
        );
        $this->view->avatarDesign = new AvatarDesignCore();
        $this->view->block_csrf = (new Token())->generate('block');
        $this->view->page_title = 'Perfiles bloqueados';
        $this->view->h1_title = '<span class="pH1">Perfiles bloqueados</span>';
        $this->view->meta_description = 'Gestiona los perfiles bloqueados en DeseoCerca.';
        $this->output();
    }

    public function toggle(): void
    {
        if (!UserCore::auth()) {
            Header::redirect(Uri::get('user', 'main', 'login'));
            return;
        }

        $oToken = new Token();
        if (!$oToken->check('block')) {
            Header::redirect(Uri::get('user', 'browse', 'index'));
            return;
        }

        $iBlockerId = (int)$this->session->get('member_id');
        $iBlockedId = (int)$this->httpRequest->post('blocked_id', 'int');
        $oUserModel = new UserCoreModel();
        $sUsername = (string)$oUserModel->getUsername($iBlockedId);

        if ($iBlockedId <= 0 || $iBlockedId === $iBlockerId || empty($sUsername)) {
            Header::redirect(Uri::get('user', 'browse', 'index'));
            return;
        }

        $oBlockModel = new BlockModel();
        if ($oBlockModel->isBlockedBy($iBlockerId, $iBlockedId)) {
            $oBlockModel->remove($iBlockerId, $iBlockedId);
            Header::redirect((new UserCore())->getProfileLink($sUsername));
            return;
        }

        $oBlockModel->add($iBlockerId, $iBlockedId);
        (new FavoriteModel())->remove($iBlockerId, $iBlockedId);
        Header::redirect(Uri::get('user', 'block', 'index'));
    }
}
