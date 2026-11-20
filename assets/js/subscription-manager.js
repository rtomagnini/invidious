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

    list.addEventListener('submit', async function (event) {
        var form = event.target;
        if (!form.matches('[data-subscription-filter]')) return;
        event.preventDefault();
        var fieldset = form.querySelector('fieldset');
        if (fieldset.disabled) return;

        var body = new URLSearchParams(new FormData(form));
        body.set('filter_mode', event.submitter?.value || 'custom');
        feedback.clearError(form);
        fieldset.disabled = true;
        try {
            var result = await feedback.post(new URL(form.action), body);
            var labels = [];
            form.querySelectorAll('input[data-type]').forEach(function (input) {
                input.checked = result.selected.includes(input.dataset.type);
                if (input.checked) labels.push(input.labels[0].textContent.trim());
            });

            var summary = form.closest('.subscription-card').querySelector('.subscription-status');
            summary.textContent = result.custom ? (labels.join(', ') || form.dataset.empty) : form.dataset.inherit;
            summary.classList.toggle('subscription-status-custom', result.custom);
            form.querySelector('[value="inherit"]').hidden = !result.custom;
            feedback.toast('filterSaved');
        } catch {
            feedback.showError(form, 'filterError');
        } finally {
            fieldset.disabled = false;
        }
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
