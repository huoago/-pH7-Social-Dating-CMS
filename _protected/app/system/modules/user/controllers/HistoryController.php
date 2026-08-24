<?php
/**
 * DeseoCerca recently viewed profiles controller.
 *
 * @license MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Navigation\Page;
use PH7\Framework\Url\Header;

class HistoryController extends Controller
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
        $oModel = new HistoryModel();
        $iTotal = $oModel->count($iProfileId);

        $this->view->total_pages = $oPage->getTotalPages($iTotal, self::MAX_PROFILES_PER_PAGE);
        $this->view->current_page = $oPage->getCurrentPage();
        $this->view->users = $oModel->get(
            $iProfileId,
            $oPage->getFirstItem(),
            $oPage->getNbItemsPerPage()
        );
        $this->view->avatarDesign = new AvatarDesignCore();
        $this->view->page_title = 'Vistos recientemente';
        $this->view->h1_title = '<span class="pH1">Vistos recientemente</span>';
        $this->view->meta_description = 'Perfiles que visitaste recientemente en DeseoCerca.';
        $this->output();
    }
}
