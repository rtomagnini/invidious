'use strict';
var watchedDataElement = document.getElementById('watched_data');
var payload = watchedDataElement ? 'csrf_token=' + JSON.parse(watchedDataElement.textContent).csrf_token : '';

function mark_watched(target) {
    var tile = target.parentNode.parentNode.parentNode.parentNode.parentNode;
    tile.style.display = 'none';

    var url = '/watch_ajax?action=mark_watched&redirect=false' +
        '&id=' + target.getAttribute('data-id');

    helpers.xhr('POST', url, {payload: payload}, {
        onNon200: function (xhr) {
            tile.style.display = '';
        }
    });
}

function mark_unwatched(target) {
    var tile = target.closest('.history-card-cell');
    var form = target.form;
    if (!tile || !form) return true;

    var count = document.getElementById('history-count');
    var error = document.getElementById('history-remove-error');
    var url = new URL(form.action);
    url.searchParams.set('redirect', 'false');

    target.disabled = true;
    error.hidden = true;

    function handleError() {
        target.disabled = false;
        error.hidden = false;
    }

    helpers.xhr('POST', url.href, {payload: new URLSearchParams(new FormData(form)).toString()}, {
        on200: function () {
            var remaining = Math.max(0, Number(count.dataset.count) - 1);
            var returnFocus = document.activeElement === target || document.activeElement === document.body;
            tile.remove();
            count.dataset.count = remaining;
            count.textContent = remaining.toLocaleString();
            document.getElementById('history-clear').hidden = remaining === 0;

            var grid = document.getElementById('history-videos');
            document.getElementById('history-empty').hidden = Boolean(grid.firstElementChild);
            if (returnFocus) {
                var focusTarget = grid.querySelector('[data-onclick="mark_unwatched"]:enabled') ||
                    document.querySelector('.history-actions a');
                focusTarget.focus();
            }
        },
        onNon200: handleError,
        onTimeout: handleError,
        onError: handleError
    });

    return false;
}
