<?php

/**
 * @author         Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright      (c) 2012-2019, Pierre-Henry Soria. All Rights Reserved.
 * @license        MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 */

declare(strict_types=1);

namespace PH7;

defined('PH7') or exit('Restricted access');

class ReportFormProcess extends Form
{
    private const MAX_DESCRIPTION_LENGTH = 2000;

    public function __construct()
    {
        parent::__construct();

        $iReporterId = (int)$this->session->get('member_id');
        $iTargetProfileId = (int)$this->httpRequest->post('spammer');

        if ($iReporterId <= 0 || $iTargetProfileId <= 0 || $iReporterId === $iTargetProfileId) {
            \PFBC\Form::setError('form_report', t('Unable to report abuse.'));

            return;
        }

        // Never trust the hidden spammer field. A valid report must point to an
        // existing member profile even when the reported content is a message,
        // photo, comment or video belonging to that profile.
        if (!(new UserCoreModel())->readProfile($iTargetProfileId)) {
            \PFBC\Form::setError('form_report', t('Unable to report abuse.'));

            return;
        }

        $sUrl = $this->getUrl();
        $mNeedle = strstr($sUrl, '?', true);
        $mContentType = $this->httpRequest->post('type');
        if (!Report::isValidContentType($mContentType)) {
            \PFBC\Form::setError('form_report', t('Unable to report abuse.'));

            return;
        }

        $sDescription = trim((string)$this->httpRequest->post('desc'));
        if ($sDescription === '') {
            \PFBC\Form::setError('form_report', t('Please explain why you are reporting this content.'));

            return;
        }
        $sDescription = mb_substr($sDescription, 0, self::MAX_DESCRIPTION_LENGTH);

        $aData = [
            'reporter_id' => $iReporterId,
            'spammer_id' => $iTargetProfileId,
            'url' => ($mNeedle ? $mNeedle : $sUrl),
            'type' => $mContentType,
            'desc' => $sDescription,
            'date' => $this->dateTime->get()->dateTime('Y-m-d H:i:s')
        ];

        $mReport = (new Report($this->view))->add($aData)->get();

        unset($aData);

        if ($mReport === 'already_reported') {
            \PFBC\Form::setError('form_report', t('You have already reported abuse about this profile.'));
        } elseif (!$mReport) {
            \PFBC\Form::setError('form_report', t('Unable to report abuse.'));
        } else {
            \PFBC\Form::setSuccess('form_report', t('You have successfully reported abuse about this profile.'));
        }
    }

    private function getUrl(): string
    {
        return $this->httpRequest->postExists('url') ?
            $this->httpRequest->post('url') :
            $this->httpRequest->currentUrl();
    }
}
