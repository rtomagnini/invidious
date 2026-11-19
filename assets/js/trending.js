'use strict';

(function () {
    var region = document.getElementById('trending-region');
    if (!region || !window.Intl || !Intl.DisplayNames) return;

    try {
        var locale = document.documentElement.lang || undefined;
        var names = new Intl.DisplayNames(locale, {type: 'region'});
        var selected = region.value;
        var options = Array.from(region.options);
        options.forEach(function (option) {
            option.textContent = names.of(option.value) || option.value;
        });
        options.sort(function (a, b) { return a.textContent.localeCompare(b.textContent, locale); });
        region.append.apply(region, options);
        region.value = selected;
    } catch {
        // Region codes remain usable when localized names are unavailable.
    }
})();
