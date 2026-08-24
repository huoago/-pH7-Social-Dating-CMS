<?php

/**
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2022, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

use PH7\Framework\Layout\Html\Design;
use PH7\Framework\Mvc\Router\Uri;
use PH7\Framework\Navigation\Page;
use PH7\Framework\Url\Header;

class BrowseController extends Controller
{
    private const MAX_PROFILES_PER_PAGE = 52;
    private const PERU_COUNTRY_CODE = 'PE';
    private const PERU_DEFAULT_CITY = 'Lima';

    private UserModel $oUserModel;
    private Page $oPage;
    private int $iTotalUsers;

    public function __construct()
    {
        parent::__construct();

        $this->oUserModel = new UserModel();
        $this->oPage = new Page();
    }

    public function index(): void
    {
        $this->renderBrowse($_GET, false);
    }

    /**
     * Privacy-first nearby discovery for DeseoCerca V1.
     *
     * V1 deliberately searches at city/country level instead of exposing or
     * storing precise GPS coordinates. Authenticated members use the location
     * already saved in their profile; guests fall back to Lima, Peru.
     */
    public function nearby(): void
    {
        $aParams = [
            SearchQueryCore::COUNTRY => self::PERU_COUNTRY_CODE,
            SearchQueryCore::CITY => self::PERU_DEFAULT_CITY,
            SearchQueryCore::AVATAR => '1',
            SearchQueryCore::ORDER => SearchCoreModel::LAST_ACTIVITY,
            SearchQueryCore::SORT => SearchCoreModel::DESC
        ];

        if (UserCore::auth()) {
            $iProfileId = (int)$this->session->get('member_id');
            $oInfo = $this->oUserModel->getInfoFields($iProfileId);

            if (!empty($oInfo->country)) {
                $aParams[SearchQueryCore::COUNTRY] = $oInfo->country;
            }
            if (!empty($oInfo->city)) {
                $aParams[SearchQueryCore::CITY] = $oInfo->city;
            }
        }

        $this->renderBrowse($aParams, true);
    }

    private function renderBrowse(array $aParams, bool $bNearby): void
    {
        $this->iTotalUsers = $this->oUserModel->search($aParams, true, null, null);
        $this->view->total_pages = $this->oPage->getTotalPages(
            $this->iTotalUsers,
            self::MAX_PROFILES_PER_PAGE
        );
        $this->view->current_page = $this->oPage->getCurrentPage();
        $aUsers = $this->oUserModel->search(
            $aParams,
            false,
            $this->oPage->getFirstItem(),
            $this->oPage->getNbItemsPerPage()
        );

        if (!$bNearby && $this->isSearch() && empty($aUsers)) {
            Header::redirect(
                Uri::get('user', 'browse', 'index'),
                t('No results. Please try again with wider or different search criteria.'),
                Design::ERROR_TYPE
            );
            return;
        }

        if ($bNearby) {
            $this->view->page_title = 'Personas cerca de ti';
            $this->view->h1_title = '<span class="pH1">Personas cerca de ti</span>';
            $this->view->h3_title = 'Descubrimiento por ciudad, sin publicar tu ubicación GPS exacta.';
            $this->view->meta_description = 'Descubre perfiles de adultos cerca de tu ciudad en DeseoCerca.';
            $this->view->is_nearby = true;
        } else {
            $this->view->page_title = t('Browse Members');
            $this->view->h1_title = '<span class="pH1">' . t('Browse Members') . '</span>';
            $this->view->h3_title = t('Meet new People with %0%', '<span class="pH0">' . $this->registry->site_name . '</span>');
            $this->view->meta_description = t('Meet new People and Friends near you with %site_name% - Browse Members');
            $this->view->is_nearby = false;
        }

        $this->view->avatarDesign = new AvatarDesignCore();
        $this->view->users = $aUsers;
        $this->output();
    }

    private function isSearch(): bool
    {
        return !empty($_GET) && count($_GET) > 1;
    }
}
