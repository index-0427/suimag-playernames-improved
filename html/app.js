(function () {
    'use strict';

    var app = document.getElementById('app');
    var form = document.getElementById('settings-form');
    var status = document.getElementById('status');
    var statusCounter = document.getElementById('status-counter');
    var statusColor = document.getElementById('status-color');
    var statusColorValue = document.getElementById('status-color-value');
    var displayName = document.getElementById('display-name');
    var nameCounter = document.getElementById('name-counter');
    var nameColor = document.getElementById('name-color');
    var nameColorValue = document.getElementById('name-color-value');
    var achievement = document.getElementById('achievement');
    var showSelf = document.getElementById('show-self');
    var showOthers = document.getElementById('show-others');
    var maxVisibleNames = document.getElementById('max-visible-names');
    var maxVisibleNamesValue = document.getElementById('max-visible-names-value');

    var defaults = {
        status: '',
        statusColor: 'white',
        displayName: '',
        nameColor: 'white',
        achievement: 'coming_soon',
        showSelf: false,
        showOthers: false,
        maxVisibleNames: 5
    };

    var legacyColorValues = {
        white: '#f0f0f0',
        red: '#e03232',
        green: '#72cc72',
        blue: '#5db6e5',
        yellow: '#f0c850',
        orange: '#ff8555',
        purple: '#8466e2',
        pink: '#cb3694',
        gray: '#8c8c8c'
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

    function normalizeColor(value) {
        var normalized = typeof value === 'string' ? value.toLowerCase() : '';

        if (Object.prototype.hasOwnProperty.call(legacyColorValues, normalized)) {
            return legacyColorValues[normalized];
        }

        return /^#[0-9a-f]{6}$/.test(normalized) ? normalized : '#f0f0f0';
    }

    function normalizeMaxVisibleNames(value) {
        var limit = Number(value);
        if (!Number.isFinite(limit)) {
            return 5;
        }

        limit = Math.floor(limit);
        return Math.max(1, Math.min(21, limit));
    }

    function formatMaxVisibleNames(value) {
        return value === 21 ? '無制限' : value + '人';
    }

    function updateColorValues() {
        statusColorValue.textContent = normalizeColor(statusColor.value).toUpperCase();
        nameColorValue.textContent = normalizeColor(nameColor.value).toUpperCase();
        maxVisibleNamesValue.textContent = formatMaxVisibleNames(normalizeMaxVisibleNames(maxVisibleNames.value));
    }

    function applySettings(settings) {
        settings = settings || {};
        status.value = typeof settings.status === 'string' ? settings.status.slice(0, 32) : defaults.status;
        statusColor.value = normalizeColor(settings.statusColor);
        displayName.value = typeof settings.displayName === 'string' ? settings.displayName.slice(0, 32) : defaults.displayName;
        nameColor.value = normalizeColor(settings.nameColor);
        achievement.value = 'coming_soon';
        showSelf.checked = settings.showSelf === true;
        showOthers.checked = settings.showOthers === true;
        maxVisibleNames.value = String(normalizeMaxVisibleNames(settings.maxVisibleNames));
        updateCounter();
        updateColorValues();
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
    statusColor.addEventListener('input', updateColorValues);
    nameColor.addEventListener('input', updateColorValues);
    maxVisibleNames.addEventListener('input', updateColorValues);

    form.addEventListener('submit', function (event) {
        event.preventDefault();
        post('saveSettings', {
            status: status.value,
            statusColor: normalizeColor(statusColor.value),
            displayName: displayName.value,
            nameColor: normalizeColor(nameColor.value),
            achievement: achievement.value,
            showSelf: showSelf.checked,
            showOthers: showOthers.checked,
            maxVisibleNames: normalizeMaxVisibleNames(maxVisibleNames.value)
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
