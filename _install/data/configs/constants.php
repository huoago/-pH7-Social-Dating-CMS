<?php
/**
 * @author           Pierre-Henry Soria <hello@ph7builder.com>
 * @copyright        (c) 2012-2026, Pierre-Henry Soria. All Rights Reserved.
 * @license          MIT License; See LICENSE.md and COPYRIGHT.md in the root directory.
 * @link              https://ph7builder.com
 * @package           PH7
 */

namespace PH7;

defined('PH7') or exit(header('Location: ./'));

########## VARIABLES ##########

##### URL #####
// The installer pins a safe fallback authority. A deployment-controlled
// environment override is allowed so the exact same installed runtime can be
// promoted from staging.deseocerca.com to deseocerca.com without trusting the
// request Host header or rewriting application data.
$sUrlProtocol = '%url_protocol%';
$sDomain = '%domain%';

$mRuntimeScheme = getenv('PH7_CANONICAL_SCHEME');
if (is_string($mRuntimeScheme) && trim($mRuntimeScheme) !== '') {
    $sRuntimeScheme = strtolower(trim($mRuntimeScheme));
    if (!in_array($sRuntimeScheme, ['http', 'https'], true)) {
        http_response_code(500);
        exit('Configuration error: PH7_CANONICAL_SCHEME must be http or https.');
    }
    $sUrlProtocol = $sRuntimeScheme . '://';
}

$mRuntimeHost = getenv('PH7_CANONICAL_HOST');
if (is_string($mRuntimeHost) && trim($mRuntimeHost) !== '') {
    $sRuntimeHost = trim($mRuntimeHost);
    $aRuntimeHostMatch = [];
    if (preg_match('/^(?:\\[[0-9a-f:.]+\\]|[a-z0-9.-]+)(?::([0-9]{1,5}))?$/iD', $sRuntimeHost, $aRuntimeHostMatch) !== 1 ||
        isset($aRuntimeHostMatch[1]) && ((int)$aRuntimeHostMatch[1] < 1 || (int)$aRuntimeHostMatch[1] > 65535)
    ) {
        http_response_code(500);
        exit('Configuration error: PH7_CANONICAL_HOST is invalid.');
    }
    $sDomain = $sRuntimeHost;
}

// Host-only cookies are the safe default. PH7_COOKIE_DOMAIN can explicitly opt
// into a validated parent domain when cross-subdomain cookies are required.
$sDomain_cookie = '';

// Determine the current file of the application
$sScriptName = is_string($_SERVER['SCRIPT_NAME'] ?? null) ? $_SERVER['SCRIPT_NAME'] : '/index.php';
$sPhp_self = str_replace('\\', '/', dirname($sScriptName));


########## CONSTANTS ##########

##### OTHER #####
define('PH7_DS', DIRECTORY_SEPARATOR);
define('PH7_PS', PATH_SEPARATOR);
define('PH7_SH', '/'); // SlasH
define('PH7_CANONICAL_AUTHORITY_PINNED', true);
define('PH7_SELF', (substr($sPhp_self, -1) !== PH7_SH) ? $sPhp_self . PH7_SH : $sPhp_self);
define('PH7_RELATIVE', PH7_SELF);

##### PATH #####
define('PH7_PATH_ROOT', __DIR__ . PH7_DS);
$sProtectedPath = '%path_protected%';
if (!is_dir($sProtectedPath)) {
    $aProtectedCandidates = [
        PH7_PATH_ROOT . '_protected' . PH7_DS,
        dirname(PH7_PATH_ROOT) . PH7_DS . '_protected' . PH7_DS
    ];

    foreach ($aProtectedCandidates as $sCandidatePath) {
        if (is_dir($sCandidatePath)) {
            $sProtectedPath = $sCandidatePath;
            break;
        }
    }
}

define('PH7_PATH_PROTECTED', $sProtectedPath);
define('PH7_PATH_APP', PH7_PATH_PROTECTED . 'app/');
define('PH7_PATH_FRAMEWORK', PH7_PATH_PROTECTED . 'framework/');
define('PH7_PATH_LIBRARY', PH7_PATH_PROTECTED . 'library/');

##### URL (PUBLIC) #####
define('PH7_URL_PROT', $sUrlProtocol);
define('PH7_DOMAIN', $sDomain); // URL domain
define('PH7_DOMAIN_COOKIE', $sDomain_cookie);
define('PH7_URL_ROOT', PH7_URL_PROT . PH7_DOMAIN . PH7_SELF);
