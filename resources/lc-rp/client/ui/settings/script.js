// client/ui/settings/script.js
// Settings panel: tabs, sliders, toggles, password change.

// ── Tab switching ────────────────────────────────────────────────────────────

var tabs = document.querySelectorAll('.tab');
var contents = document.querySelectorAll('.tab-content');

tabs.forEach(function(tab) {
    tab.addEventListener('click', function() {
        var target = tab.getAttribute('data-tab');
        tabs.forEach(function(t) { t.classList.remove('active'); });
        contents.forEach(function(c) { c.classList.remove('active'); });
        tab.classList.add('active');
        document.getElementById('tab-' + target).classList.add('active');
    });
});

// ── Debounce utility ─────────────────────────────────────────────────────────

var _debounceTimers = {};
function debounceSave(key, value, delay) {
    clearTimeout(_debounceTimers[key]);
    _debounceTimers[key] = setTimeout(function() {
        Events.Call('ui_settings_save', [key, value]);
    }, delay || 250);
}

// ── Range sliders ────────────────────────────────────────────────────────────

var fontSlider = document.getElementById('font-size');
var fontVal    = document.getElementById('font-size-val');
var pageSlider = document.getElementById('page-size');
var pageVal    = document.getElementById('page-size-val');

fontSlider.addEventListener('input', function() {
    fontVal.textContent = fontSlider.value;
    debounceSave('chatFontSize', parseInt(fontSlider.value, 10));
});

pageSlider.addEventListener('input', function() {
    pageVal.textContent = pageSlider.value;
    debounceSave('chatPageSize', parseInt(pageSlider.value, 10));
});

// ── Toggle checkboxes ────────────────────────────────────────────────────────

var toggleMoney   = document.getElementById('toggle-money');
var toggleNotify  = document.getElementById('toggle-notifications');
var toggleInv     = document.getElementById('toggle-inventory');

toggleMoney.addEventListener('change', function() {
    Events.Call('ui_settings_save', ['showMoneyHud', toggleMoney.checked ? 1 : 0]);
});

toggleNotify.addEventListener('change', function() {
    Events.Call('ui_settings_save', ['useUINotifications', toggleNotify.checked ? 1 : 0]);
});

toggleInv.addEventListener('change', function() {
    Events.Call('ui_settings_save', ['useInventoryUI', toggleInv.checked ? 1 : 0]);
});

// ── Password change ──────────────────────────────────────────────────────────

var pwCurrent = document.getElementById('pw-current');
var pwNew     = document.getElementById('pw-new');
var pwConfirm = document.getElementById('pw-confirm');
var pwMsg     = document.getElementById('pw-msg');
var pwSubmit  = document.getElementById('pw-submit');

function showPwMsg(type, text) {
    pwMsg.textContent = text;
    pwMsg.className = 'msg ' + type;
}

function changePassword() {
    var cur  = pwCurrent.value;
    var np   = pwNew.value;
    var conf = pwConfirm.value;

    if (!cur || !np || !conf) {
        showPwMsg('error', 'All fields are required.');
        return;
    }
    if (np.length < 6) {
        showPwMsg('error', 'New password must be at least 6 characters.');
        return;
    }
    if (np !== conf) {
        showPwMsg('error', 'New passwords do not match.');
        return;
    }

    pwSubmit.disabled = true;
    showPwMsg('', 'Changing password...');
    Events.Call('ui_settings_password', [cur, np]);
}

// ── Events from Lua ──────────────────────────────────────────────────────────

// Load current settings into the UI.
// Payload arrives as separate args (framework unpacks Lua tables) or as an array.
Events.Subscribe('settings_load', function(a, b, c, d, e) {
    // Handle array/object form (single arg containing all values).
    if (Array.isArray(a)) {
        e = a[4]; d = a[3]; c = a[2]; b = a[1]; a = a[0];
    } else if (a && typeof a === 'object' && !Array.isArray(a)) {
        e = a[4] !== undefined ? a[4] : a[5];
        d = a[3] !== undefined ? a[3] : a[4];
        c = a[2] !== undefined ? a[2] : a[3];
        b = a[1] !== undefined ? a[1] : a[2];
        a = a[0] !== undefined ? a[0] : a[1];
    }

    var fontSize = parseInt(a, 10) || 12;
    var pageSize = parseInt(b, 10) || 20;
    var moneyHud = parseInt(c, 10) === 1;
    var uiNotify = parseInt(d, 10) === 1;
    var invUI    = parseInt(e, 10) === 1;

    fontSlider.value = fontSize;
    fontVal.textContent = fontSize;

    pageSlider.value = pageSize;
    pageVal.textContent = pageSize;

    toggleMoney.checked  = moneyHud;
    toggleNotify.checked = uiNotify;
    toggleInv.checked    = invUI;
});

// Feedback after password change attempt.
// Payload arrives as separate args or as an array.
Events.Subscribe('settings_feedback', function(a, b) {
    // Handle array/object form.
    if (Array.isArray(a)) {
        b = a[1]; a = a[0];
    } else if (a && typeof a === 'object' && !Array.isArray(a)) {
        b = a[1] !== undefined ? a[1] : a[2];
        a = a[0] !== undefined ? a[0] : a[1];
    }

    var type = a || 'info';
    var msg  = b || '';

    showPwMsg(type, msg);
    pwSubmit.disabled = false;

    if (type === 'success') {
        pwCurrent.value = '';
        pwNew.value     = '';
        pwConfirm.value = '';
    }
});

// ── Close panel ──────────────────────────────────────────────────────────────

function closePanel() {
    Events.Call('ui_settings_close');
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closePanel();
    }
});
