<?php
/**
 * Minimal pH7Builder bootstrap for DeseoCerca maintenance CLI scripts.
 *
 * This intentionally initializes the framework and application loaders without
 * invoking the HTTP front controller.
 */

declare(strict_types=1);

use PH7\App\Includes\Classes\Loader\Autoloader as AppLoader;
use PH7\Framework\Config\Config;
use PH7\Framework\File\Import;
use PH7\Framework\Loader\Autoloader as FrameworkLoader;
use PH7\Framework\Server\Environment as Env;

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "DeseoCerca maintenance bootstrap is CLI-only.\n");
    exit(1);
}

if (!defined('PH7')) {
    define('PH7', 1);
}

$sProjectRoot = dirname(__DIR__, 2) . DIRECTORY_SEPARATOR;
$sConstantsFile = $sProjectRoot . '_constants.php';
if (!is_file($sConstantsFile)) {
    fwrite(STDERR, "Missing _constants.php. Complete the pH7Builder installation before running maintenance.\n");
    exit(1);
}

require_once $sConstantsFile;
require_once PH7_PATH_APP . 'configs/constants.php';
require_once PH7_PATH_APP . 'includes/helpers/misc.php';
require_once PH7_PATH_FRAMEWORK . 'Loader/Autoloader.php';

FrameworkLoader::getInstance()->init();

Import::file(PH7_PATH_APP . 'configs/environment/all.env');
Import::file(
    PH7_PATH_APP . 'configs/environment/' . Env::getFileName(
        Config::getInstance()->values['mode']['environment']
    )
);
Import::pH7App('includes.classes.Loader.Autoloader');
AppLoader::getInstance()->init();
Import::pH7FwkClass('Error.Debug');
Import::pH7FwkClass('Str.Str');

if (!ini_get('date.timezone')) {
    ini_set('date.timezone', PH7_DEFAULT_TIMEZONE);
}
