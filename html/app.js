(function () {
    'use strict';

    var app = document.getElementById('app');
    var form = document.getElementById('settings-form');
    var status = document.getElementById('status');
    var statusCounter = document.getElementById('status-counter');
    var displayName = document.getElementById('display-name');
    var nameCounter = document.getElementById('name-counter');
    var achievement = document.getElementById('achievement');
    var showSelf = document.getElementById('show-self');
    var showOthers = document.getElementById('show-others');

    var defaults = {
        status: '',
        displayName: '',
        achievement: 'coming_soon',
        showSelf: false,
        showOthers: false
    };

    function resourceName() {
        return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'playernames';
    }

    function post(endpoint, body) {
        body = body || {};

        return fetch('https://' + resourceName() + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body)
        }).catch(function () {
            return undefined;
        });
    }

    function updateCounter() {
        statusCounter.textContent = status.value.length + ' / 32';
        nameCounter.textContent = displayName.value.length + ' / 32';
    }

    function applySettings(settings) {
        settings = settings || {};
        status.value = typeof settings.status === 'string' ? settings.status.slice(0, 32) : defaults.status;
        displayName.value = typeof settings.displayName === 'string' ? settings.displayName.slice(0, 32) : defaults.displayName;
        achievement.value = 'coming_soon';
        showSelf.checked = settings.showSelf === true;
        showOthers.checked = settings.showOthers === true;
        updateCounter();
    }

    function open(settings) {
        applySettings(settings);
        app.classList.add('is-open');
        app.setAttribute('aria-hidden', 'false');
        window.setTimeout(function () {
            status.focus();
        }, 0);
    }

    function close(notify) {
        if (notify === undefined) {
            notify = true;
        }

        app.classList.remove('is-open');
        app.setAttribute('aria-hidden', 'true');
        if (notify) {
            post('close');
        }
    }

    status.addEventListener('input', updateCounter);
    displayName.addEventListener('input', updateCounter);

    form.addEventListener('submit', function (event) {
        event.preventDefault();
        post('saveSettings', {
            status: status.value,
            displayName: displayName.value,
            achievement: achievement.value,
            showSelf: showSelf.checked,
            showOthers: showOthers.checked
        });
        close(false);
    });

    document.getElementById('close-button').addEventListener('click', function () { close(); });
    document.getElementById('cancel-button').addEventListener('click', function () { close(); });
    document.querySelector('.backdrop').addEventListener('click', function () { close(); });

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' && app.classList.contains('is-open')) {
            close();
        }
    });

    window.addEventListener('message', function (event) {
        var message = event.data || {};

        if (message.action === 'open') {
            open(message.settings);
        } else if (message.action === 'close') {
            close(false);
        }
    });

    // Let Lua know that the page is ready. This prevents the first open message
    // from being lost while the NUI document is loading.
    post('ready');
}());
