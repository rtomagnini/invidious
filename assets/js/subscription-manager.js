'use strict';

(function () {
    var list = document.getElementById('subscription-list');
    var field = document.getElementById('subscription-search');
    var noMatches = document.getElementById('subscription-no-matches');

    function normalize(text) {
        return text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();
    }

    var channels = Array.from(list.children, function (row) {
        var image = row.querySelector('.subscription-avatar img');
        if (image) {
            function hideMissingAvatar() { image.hidden = true; }
            image.addEventListener('error', hideMissingAvatar);
            if (image.complete && image.naturalWidth === 0) hideMissingAvatar();
        }
        return {row: row, name: normalize(row.querySelector('.subscription-name').textContent)};
    });

    document.getElementById('subscription-search-box').hidden = false;
    field.addEventListener('input', function () {
        var query = normalize(field.value.trim());
        var matched = false;
        channels.forEach(function (channel) {
            var visible = channel.name.includes(query);
            channel.row.hidden = !visible;
            if (visible) matched = true;
        });
        noMatches.hidden = matched;
    });
})();
