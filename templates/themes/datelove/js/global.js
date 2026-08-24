include('[$url_def_tpl_js]global.js');

/* DeseoCerca Peru-first onboarding defaults.
 * Preserve geolocation results when they are available; only fill empty fields.
 */
(function ($) {
    'use strict';

    $(function () {
        var $country = $('#str_country');
        var $city = $('#str_city');

        if ($country.length && !$country.val()) {
            $country.val('PE').trigger('change');
        }

        if ($city.length && !$.trim($city.val())) {
            $city.val('Lima');
        }
    });
})(jQuery);
