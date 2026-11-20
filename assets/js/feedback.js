'use strict';

const feedback = (() => {
    const strings = document.getElementById('feedback-strings').dataset;
    const stack = document.getElementById('feedback-toasts');
    const status = document.getElementById('feedback-status');

    function toast(key, undo) {
        const item = document.createElement('div');
        item.className = 'feedback-toast';

        const message = document.createElement('span');
        message.textContent = strings[key];
        item.append(message);
        status.textContent = '';
        requestAnimationFrame(() => { status.textContent = strings[key]; });

        let timer;
        let pending = false;
        let failed = false;
        const timeout = undo ? 10000 : 5500;
        function stopTimer() { clearTimeout(timer); }
        function startTimer() {
            stopTimer();
            if (!pending && !failed && !item.matches(':hover, :focus-within')) {
                timer = setTimeout(() => item.remove(), timeout);
            }
        }

        if (undo) {
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = strings.undo;
            button.addEventListener('click', async () => {
                stopTimer();
                pending = true;
                button.disabled = true;
                try {
                    await undo();
                    item.remove();
                    toast('undone');
                } catch {
                    pending = false;
                    failed = true;
                    button.disabled = false;
                    message.textContent = strings.actionError;
                    message.setAttribute('role', 'alert');
                }
            });
            item.append(button);
        }

        const dismiss = document.createElement('button');
        dismiss.type = 'button';
        dismiss.textContent = '×';
        dismiss.setAttribute('aria-label', strings.close);
        dismiss.addEventListener('click', () => { stopTimer(); item.remove(); });
        item.append(dismiss);

        item.addEventListener('pointerenter', stopTimer);
        item.addEventListener('pointerleave', startTimer);
        item.addEventListener('focusin', stopTimer);
        item.addEventListener('focusout', () => requestAnimationFrame(startTimer));
        stack.append(item);
        startTimer();
    }

    function clearError(container) {
        container.querySelector(':scope > .feedback-error')?.remove();
    }

    function showError(container, key) {
        clearError(container);
        const error = document.createElement('p');
        error.className = 'feedback-error';
        error.setAttribute('role', 'alert');
        error.textContent = strings[key];
        container.append(error);
    }

    async function post(url, body) {
        url.searchParams.set('redirect', 'false');
        const response = await fetch(url, {
            method: 'POST',
            headers: {Accept: 'application/json'},
            body,
            redirect: 'error'
        });
        if (!response.ok) throw new Error('Request failed');
        return response.json();
    }

    async function submit(event) {
        const form = event.target;
        const key = form.dataset.feedbackSubmit;
        if (!key) return;
        event.preventDefault();
        if (form.dataset.pending) return;

        const tile = form.closest('.video-card-cell');
        const errorContainer = form.closest('.video-card') || form;
        const button = event.submitter || form.querySelector('button[type="submit"]');
        const url = new URL(form.action);
        const body = new URLSearchParams(new FormData(form));
        clearError(errorContainer);
        form.dataset.pending = 'true';
        if (button) button.disabled = true;

        try {
            const result = await post(url, body);
            const focused = document.activeElement === button || document.activeElement === document.body;
            if (tile) {
                // Keep the original card in place so undo preserves the feed order.
                tile.hidden = true;
                if (focused) {
                    const buttons = Array.from(document.querySelectorAll('form[data-feedback-submit] button'));
                    const position = buttons.indexOf(button);
                    const isVisible = candidate => !candidate.disabled && !candidate.closest('[hidden]');
                    const next = buttons.slice(position + 1).find(isVisible) ||
                        buttons.slice(0, position).reverse().find(isVisible) ||
                        document.getElementById('searchbox');
                    next?.focus();
                }
            }
            const undo = key === 'watched' && result.changed === true && tile ? async () => {
                url.searchParams.set('action', 'mark_unwatched');
                await post(url, body);
                tile.hidden = false;
                button?.focus();
            } : undefined;
            toast(key, undo);
        } catch {
            showError(errorContainer, 'actionError');
        } finally {
            delete form.dataset.pending;
            if (button) button.disabled = false;
        }
    }

    document.addEventListener('submit', submit);
    return {toast, post, clearError, showError};
})();
