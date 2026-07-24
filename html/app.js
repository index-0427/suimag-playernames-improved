(() => {
    'use strict';

    const app = document.getElementById('app');
    const form = document.getElementById('settings-form');
    const displayName = document.getElementById('display-name');
    const nameCounter = document.getElementById('name-counter');
    const achievement = document.getElementById('achievement');
    const showSelf = document.getElementById('show-self');
    const showOthers = document.getElementById('show-others');

    const defaults = {
        displayName: '',
        achievement: 'coming_soon',
        showSelf: true,
        showOthers: true
    };

    function resourceName() {
        return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'playernames';
    }

    function post(endpoint, body = {}) {
        return fetch(`https://${resourceName()}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body)
        }).catch(() => undefined);
    }

    function updateCounter() {
        nameCounter.textContent = `${displayName.value.length} / 32`;
    }

    function applySettings(settings = {}) {
        const values = { ...defaults, ...settings };
        displayName.value = typeof values.displayName === 'string' ? values.displayName.slice(0, 32) : '';
        achievement.value = 'coming_soon';
        showSelf.checked = values.showSelf !== false;
        showOthers.checked = values.showOthers !== false;
        updateCounter();
    }

    function open(settings) {
        applySettings(settings);
        app.classList.add('is-open');
        app.setAttribute('aria-hidden', 'false');
        window.setTimeout(() => displayName.focus(), 0);
    }

    function close(notify = true) {
        app.classList.remove('is-open');
        app.setAttribute('aria-hidden', 'true');
        if (notify) {
            post('close');
        }
    }

    displayName.addEventListener('input', updateCounter);

    form.addEventListener('submit', (event) => {
        event.preventDefault();
        post('saveSettings', {
            displayName: displayName.value,
            achievement: achievement.value,
            showSelf: showSelf.checked,
            showOthers: showOthers.checked
        });
        close(false);
    });

    document.getElementById('close-button').addEventListener('click', () => close());
    document.getElementById('cancel-button').addEventListener('click', () => close());
    document.querySelector('.backdrop').addEventListener('click', () => close());

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && app.classList.contains('is-open')) {
            close();
        }
    });

    window.addEventListener('message', (event) => {
        const message = event.data || {};

        if (message.action === 'open') {
            open(message.settings);
        } else if (message.action === 'close') {
            close(false);
        }
    });
})();
