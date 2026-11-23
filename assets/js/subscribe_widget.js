'use strict';

(function () {
    var button = document.getElementById('subscribe');
    var form = button.form;
    var label = button.querySelector('[data-subscribe-text]');

    form.addEventListener('submit', async function (event) {
        event.preventDefault();
        if (button.disabled) return;

        var url = new URL(form.action);
        var body = new URLSearchParams(new FormData(form));
        var subscribed = button.dataset.type === 'subscribe';
        var fieldset = form.closest('[data-subscription-filter-scope]')?.querySelector('[data-subscription-filter] fieldset');
        if (fieldset?.disabled) return;

        button.disabled = true;
        if (fieldset) fieldset.disabled = true;
        feedback.clearError(form);
        try {
            await feedback.post(url, body);
            button.dataset.type = subscribed ? 'unsubscribe' : 'subscribe';
            label.textContent = subscribed ? form.dataset.unsubscribeLabel : form.dataset.subscribeLabel;
            url.searchParams.delete('redirect');
            url.searchParams.set('action', subscribed ? 'remove_subscriptions' : 'create_subscription_to_channel');
            form.action = url.href;
            form.dispatchEvent(new CustomEvent('subscription-change', {bubbles: true, detail: {subscribed: subscribed}}));
        } catch {
            feedback.showError(form, 'actionError');
        } finally {
            button.disabled = false;
            if (fieldset) fieldset.disabled = false;
        }
    });
})();
