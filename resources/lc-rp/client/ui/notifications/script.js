'use strict';

const MAX_TOASTS = 5;

const $toasts = document.getElementById('toasts');

const TYPE_LABELS = {
    success: 'Success',
    error:   'Error',
    warn:    'Warning',
    info:    'Info',
};

const VALID_TYPES = new Set(['success', 'error', 'warn', 'info']);

// ── Toast creation ─────────────────────────────────────────────────────────────

function push(type, message, duration) {
    type = VALID_TYPES.has(type) ? type : 'info';
    duration = Math.max(500, Number(duration) || 4000);

    // Drop the oldest toast if at the limit.
    const visible = $toasts.querySelectorAll('.toast:not(.removing)');
    if (visible.length >= MAX_TOASTS) {
        dismiss(visible[visible.length - 1]);
    }

    const el = document.createElement('div');
    el.className  = 'toast';
    el.dataset.type = type;
    el.innerHTML = `
        <span class="toast-type">${TYPE_LABELS[type]}</span>
        <span class="toast-message">${message}</span>
        <div class="toast-bar"></div>
    `;
    $toasts.prepend(el);

    // Progress bar shrinks over toast lifetime.
    el.querySelector('.toast-bar').animate(
        [{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }],
        { duration, easing: 'linear', fill: 'forwards' }
    );

    // Auto-dismiss: fade out at end, then remove. Use both animation .finished and
    // setTimeout since game WebUI may not reliably fire one or the other.
    const fadeMs = 200;
    const anim = el.animate(
        [
            { opacity: 1, offset: 0 },
            { opacity: 1, offset: (duration - fadeMs) / duration },
            { opacity: 0, offset: 1 }
        ],
        { duration, fill: 'forwards' }
    );
    const removeEl = function() {
        if (el.parentNode) el.parentNode.removeChild(el);
    };
    anim.finished.then(removeEl).catch(removeEl);
    setTimeout(removeEl, duration + 500);  // fallback
}

function dismiss(el) {
    if (el.classList.contains('removing')) return;
    el.classList.add('removing');
    const removeEl = function() {
        if (el.parentNode) el.parentNode.removeChild(el);
    };
    el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 150, fill: 'forwards' })
        .finished.then(removeEl).catch(removeEl);
    setTimeout(removeEl, 200);
}

// ── Event bridge (from Lua via WebUI.CallEvent) ────────────────────────────────

Events.Subscribe('notify', function(type, message, duration) {
    push(type, message, duration || 4000);
});

Events.Subscribe('hudToggle', function(payload) {
    var visible = (Array.isArray(payload) && payload[0] !== undefined) ? payload[0] : payload;
    document.body.style.visibility = visible ? 'visible' : 'hidden';
});
