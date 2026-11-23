'use strict';

(function () {
    function showSelection(form, selected, custom) {
        var labels = [];
        form.querySelectorAll('input[data-type]').forEach(function (input) {
            input.checked = selected.includes(input.dataset.type);
            if (input.checked && input.name !== 'hide_members_only') {
                labels.push(input.labels[0].textContent.trim());
            }
        });
        form.querySelector('[value="inherit"]').hidden = !custom;

        var summary = form.closest('[data-subscription-filter-scope]').querySelector('.subscription-status');
        if (!summary) return;

        if (!labels.length) labels.push(form.dataset.empty);
        if (form.elements.hide_members_only.checked) labels.push(form.dataset.membersHidden);
        summary.textContent = custom ? labels.join(', ') : form.dataset.inherit;
        summary.classList.toggle('subscription-status-custom', custom);
    }

    document.querySelectorAll('[data-subscription-filter]').forEach(function (form) {
        var panel = form.closest('.channel-feed-filter');
        var fieldset = form.querySelector('fieldset');
        form.addEventListener('submit', async function (event) {
            event.preventDefault();
            if (fieldset.disabled) return;

            var body = new URLSearchParams(new FormData(form));
            body.set('filter_mode', event.submitter?.value || 'custom');
            feedback.clearError(form);
            fieldset.disabled = true;
            try {
                var result = await feedback.post(new URL(form.action), body);
                showSelection(form, result.selected, result.custom);
                if (panel?.open) {
                    var restoreFocus = panel.contains(document.activeElement) || document.activeElement === document.body;
                    panel.open = false;
                    if (restoreFocus) panel.querySelector('summary').focus();
                }
                feedback.toast('filterSaved');
            } catch {
                feedback.showError(form, 'filterError');
            } finally {
                fieldset.disabled = false;
            }
        });

        if (!panel) return;

        var actions = panel.closest('[data-subscription-filter-scope]');
        actions.addEventListener('subscription-change', function (event) {
            panel.hidden = !event.detail.subscribed;
            if (panel.hidden) {
                panel.open = false;
                showSelection(form, form.dataset.defaults, false);
                feedback.clearError(form);
            }
        });
    });
})();
