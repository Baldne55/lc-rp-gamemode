'use strict';

let activeFormId = 'form-login';

const $pending = document.getElementById('pending');

// ── Pending state ──────────────────────────────────────────────────────────────

function showPending() {
    document.querySelectorAll('.auth-form').forEach(f => f.classList.remove('active'));
    $pending.classList.remove('hidden');
}

function hidePending() {
    $pending.classList.add('hidden');
    document.getElementById(activeFormId).classList.add('active');
}

// ── Tab switching ──────────────────────────────────────────────────────────────

document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.auth-form').forEach(f => f.classList.remove('active'));

        tab.classList.add('active');
        activeFormId = 'form-' + tab.dataset.tab;
        document.getElementById(activeFormId).classList.add('active');

        hideMsg('login-msg');
        hideMsg('register-msg');
    });
});

// ── Helpers ────────────────────────────────────────────────────────────────────

function showMsg(id, message) {
    const el = document.getElementById(id);
    el.textContent = message;
    el.classList.remove('hidden');
}

function hideMsg(id) {
    document.getElementById(id).classList.add('hidden');
}

// ── Login form ─────────────────────────────────────────────────────────────────

document.getElementById('form-login').addEventListener('submit', e => {
    e.preventDefault();
    hideMsg('login-msg');

    const username = document.getElementById('login-username').value.trim();
    const password = document.getElementById('login-password').value;

    if (!username) { showMsg('login-msg', 'Please enter your username.'); return; }
    if (!password) { showMsg('login-msg', 'Please enter your password.');  return; }

    showPending();
    Events.Call('ui_login', [username, password]);
});

// ── Register form ──────────────────────────────────────────────────────────────

document.getElementById('form-register').addEventListener('submit', e => {
    e.preventDefault();
    hideMsg('register-msg');

    const username = document.getElementById('reg-username').value.trim();
    const password = document.getElementById('reg-password').value;
    const confirm  = document.getElementById('reg-confirm').value;

    if (!username) { showMsg('register-msg', 'Please enter a username.'); return; }
    if (!password) { showMsg('register-msg', 'Please enter a password.');  return; }
    if (password !== confirm) { showMsg('register-msg', 'Passwords do not match.'); return; }

    showPending();
    Events.Call('ui_register', [username, password]);
});

// ── auth_error event (from Lua client handler) ─────────────────────────────────

Events.Subscribe('auth_error', function(message) {
    hidePending();
    showMsg(activeFormId === 'form-login' ? 'login-msg' : 'register-msg', message);
});
