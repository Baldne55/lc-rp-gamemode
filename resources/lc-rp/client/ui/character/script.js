'use strict';

// ── State ──────────────────────────────────────────────────────────────────────

let selectedCharId = null;

const $panelSelect  = document.getElementById('panel-select');
const $panelCreate  = document.getElementById('panel-create');
const $slotGrid     = document.getElementById('slot-grid');
const $btnPlay      = document.getElementById('btn-play');
const $btnBack      = document.getElementById('btn-back');
const $formCreate   = document.getElementById('form-create');
const $createMsg    = document.getElementById('create-msg');
const $pending      = document.getElementById('pending-create');
const $createStep1  = document.getElementById('create-step1');
const $createStep2  = document.getElementById('create-step2');
const $createStep3  = document.getElementById('create-step3');

// ── Panel switching ────────────────────────────────────────────────────────────

function showSelect() {
    $panelCreate.classList.remove('active');
    $panelSelect.classList.add('active');
}

function showCreate() {
    $panelSelect.classList.remove('active');
    $panelCreate.classList.add('active');
    Events.Call('ui_char_create_panel_shown', []);
    hideMsg();
    $formCreate.reset();
    resetDobDropdowns();
    selectedSkin = null;
    selectedAppearance = null;
    pedPage = 1;
    showCreateStep(1);
    hidePending();
}

function resetDobDropdowns() {
    $dobYear.value = '';
    $dobMonth.querySelector('.dob-btn.selected')?.classList.remove('selected');
    $dobDay.value = '';
}

function showCreateStep(step) {
    const $card = document.getElementById('card-create');
    $card.classList.remove('step2', 'step3');

    if (step === 1) {
        $createStep1.classList.remove('hidden');
        $createStep2.classList.add('hidden');
        $createStep3.classList.add('hidden');
        Events.Call('ui_char_preview', [null]);
    } else if (step === 2) {
        $createStep1.classList.add('hidden');
        $createStep2.classList.remove('hidden');
        $createStep3.classList.add('hidden');
        $card.classList.add('step2');
        renderPedGrid();
        Events.Call('ui_char_preview', [selectedSkin, selectedAppearance]);
    } else {
        $createStep1.classList.add('hidden');
        $createStep2.classList.add('hidden');
        $createStep3.classList.remove('hidden');
        $card.classList.add('step3');
        if (!selectedAppearance || typeof selectedAppearance !== 'object') {
            selectedAppearance = {};
            for (let i = 0; i <= 10; i++) selectedAppearance[String(i)] = [0, 0];
        }
        componentBounds = null;
        Events.Call('ui_char_preview', [selectedSkin, selectedAppearance]);
        renderComponentGrid();
        requestAnimationFrame(() => Events.Call('ui_char_get_component_bounds', []));
    }
}

// ── Pending ────────────────────────────────────────────────────────────────────

function showPending() {
    $formCreate.style.display = 'none';
    $pending.classList.remove('hidden');
}

function hidePending() {
    $pending.classList.add('hidden');
    $formCreate.style.display = '';
}

// ── Messages ───────────────────────────────────────────────────────────────────

function showMsg(text) {
    $createMsg.textContent = text;
    $createMsg.classList.remove('hidden');
}

function hideMsg() {
    $createMsg.classList.add('hidden');
}

// ── Date of birth (forced format via dropdowns) ──────────────────────────────────

const $dobYear  = document.getElementById('c-dob-year');
const $dobMonth = document.getElementById('c-dob-month');
const $dobDay   = document.getElementById('c-dob-day');

function getDobValue() {
    const y = $dobYear.value.trim();
    const m = $dobMonth.querySelector('.dob-btn.selected')?.dataset.value;
    const d = $dobDay.value.trim();
    if (!y || !m || !d) return null;
    return `${y}-${m}-${String(d).padStart(2, '0')}`;
}

function updateDayOptions() {
    const year = parseInt($dobYear.value, 10);
    const month = parseInt($dobMonth.querySelector('.dob-btn.selected')?.dataset.value, 10);
    if (!year || !month) return;
    const lastDay = new Date(year, month, 0).getDate();
    $dobDay.max = lastDay;
    const currentDay = parseInt($dobDay.value, 10);
    if (currentDay > lastDay || !currentDay) $dobDay.value = Math.min(currentDay || 1, lastDay);
}

const SERVER_YEAR = 2008;
const CHARACTER_AGE_MIN = 14;
const CHARACTER_AGE_MAX = 90;

function initDobDropdowns() {
    const minYear = SERVER_YEAR - CHARACTER_AGE_MAX;
    const maxYear = SERVER_YEAR - CHARACTER_AGE_MIN;

    $dobYear.min = minYear;
    $dobYear.max = maxYear;
    $dobYear.placeholder = String(maxYear);

    const months = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12'];
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    $dobMonth.innerHTML = '';
    months.forEach((m, i) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'dob-btn';
        btn.dataset.value = m;
        btn.textContent = monthNames[i];
        btn.addEventListener('click', () => {
            $dobMonth.querySelectorAll('.dob-btn').forEach(b => b.classList.remove('selected'));
            btn.classList.add('selected');
            updateDayOptions();
        });
        $dobMonth.appendChild(btn);
    });

    $dobYear.addEventListener('input', updateDayOptions);
    $dobYear.addEventListener('change', updateDayOptions);
}

function validateDobSelected() {
    const m = $dobMonth.querySelector('.dob-btn.selected')?.dataset.value;
    if (!$dobYear.value?.trim() || !m || !$dobDay.value?.trim()) {
        return 'Please select date of birth (year, month, and day).';
    }
    const birthDate = getDobValue();
    const age = calcAge(birthDate);
    if (age < CHARACTER_AGE_MIN) return `Character must be at least ${CHARACTER_AGE_MIN} years old.`;
    if (age > CHARACTER_AGE_MAX) return `Character must be no older than ${CHARACTER_AGE_MAX} years.`;
    return null;
}

// ── Age calculation ────────────────────────────────────────────────────────────

function calcAge(birthDate) {
    if (!birthDate) return null;
    const parts = birthDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!parts) return null;
    const y = parseInt(parts[1], 10);
    const m = parseInt(parts[2], 10);
    const d = parseInt(parts[3], 10);
    if (m < 1 || m > 12) return null;
    const birth = new Date(y, m - 1, d);
    if (birth.getDate() !== d || birth.getMonth() !== m - 1) return null;
    const now = new Date();
    let age = SERVER_YEAR - y;
    const monthDiff = now.getMonth() - (m - 1);
    if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < d)) age--;
    return age;
}

// ── Relative date ──────────────────────────────────────────────────────────────

function relativeDate(isoString) {
    if (!isoString) return 'Never';
    const date = new Date(isoString.replace(' ', 'T') + 'Z');
    const diff = Math.floor((Date.now() - date.getTime()) / 1000);
    if (diff < 60)     return 'Just now';
    if (diff < 3600)   return Math.floor(diff / 60) + 'm ago';
    if (diff < 86400)  return Math.floor(diff / 3600) + 'h ago';
    if (diff < 604800) return Math.floor(diff / 86400) + 'd ago';
    return Math.floor(diff / 604800) + 'w ago';
}

// ── Slot rendering ─────────────────────────────────────────────────────────────

function buildOccupiedSlot(char, displayIndex) {
    const age    = calcAge(char.birthDate);
    const gender = char.gender === 'Male' ? 'M' : 'F';
    const last   = relativeDate(char.lastLogin);
    const locked = char.status === 'Locked';

    const el = document.createElement('div');
    el.className = 'slot' + (locked ? ' locked' : '');
    el.dataset.charId = char.id;

    el.innerHTML = `
        <div class="slot-label">Slot ${displayIndex + 1}</div>
        <div class="slot-name">${escHtml(char.firstName)} ${escHtml(char.lastName)}</div>
        <div class="slot-meta">
            ${age !== null ? `Age ${age}` : ''}
            <span class="sep">·</span>
            ${gender}
            ${locked ? '<span class="sep">·</span><span style="color:#a63d3d">Locked</span>' : ''}
        </div>
        <div class="slot-last">Last: ${last}</div>
    `;

    if (!locked) {
        el.addEventListener('click', () => selectSlot(el, char.id));
    }

    return el;
}

function buildEmptySlot(slotIndex) {
    const el = document.createElement('div');
    el.className = 'slot empty';
    el.innerHTML = `
        <div class="plus">+</div>
        <div class="empty-label">Create New</div>
    `;
    el.addEventListener('click', showCreate);
    return el;
}

function selectSlot(el, charId) {
    document.querySelectorAll('.slot').forEach(s => s.classList.remove('selected'));
    el.classList.add('selected');
    selectedCharId = charId;
    $btnPlay.disabled = false;
}

function escHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// ── char_list event (from Lua) ─────────────────────────────────────────────────

Events.Subscribe('char_list', function(chars, maxSlots) {
    $slotGrid.innerHTML = '';
    selectedCharId = null;
    $btnPlay.disabled = true;

    // Defensive: ensure chars is iterable and maxSlots is valid (bridge may pass different formats)
    if (!chars || typeof chars !== 'object') chars = [];
    else if (!Array.isArray(chars)) chars = Object.values(chars).filter(c => c && typeof c === 'object');
    maxSlots = (typeof maxSlots === 'number' && maxSlots > 0) ? maxSlots : 3;

    // Sort by slot so characters fill positions sequentially (resilient to gaps).
    const sorted = chars.slice().sort((a, b) => (a.slot ?? 0) - (b.slot ?? 0));

    for (let i = 0; i < maxSlots; i++) {
        if (sorted[i]) {
            $slotGrid.appendChild(buildOccupiedSlot(sorted[i], i));
        } else {
            $slotGrid.appendChild(buildEmptySlot(i));
        }
    }
});

// ── char_error event (from Lua) ────────────────────────────────────────────────

Events.Subscribe('char_error', function(message) {
    hidePending();
    showMsg(message);
});

// ── Play button ────────────────────────────────────────────────────────────────

$btnPlay.addEventListener('click', () => {
    if (!selectedCharId) return;
    $btnPlay.disabled = true;
    Events.Call('ui_char_select', [selectedCharId]);
});

// ── Back button ────────────────────────────────────────────────────────────────

$btnBack.addEventListener('click', showSelect);

// ── Create step navigation ──────────────────────────────────────────────────────

document.getElementById('btn-next').addEventListener('click', () => {
    hideMsg();
    const firstName = document.getElementById('c-first').value.trim();
    const lastName = document.getElementById('c-last').value.trim();
    const birthDate = getDobValue();
    const gender = document.querySelector('input[name="gender"]:checked')?.value;
    const bloodType = document.querySelector('input[name="blood"]:checked')?.value;

    if (!firstName) { showMsg('Please enter a first name.'); return; }
    if (!lastName) { showMsg('Please enter a last name.'); return; }
    const dateErr = validateDobSelected();
    if (dateErr) { showMsg(dateErr); return; }
    if (!gender) { showMsg('Please select a gender.'); return; }
    if (!bloodType) { showMsg('Please select a blood type.'); return; }

    showCreateStep(2);
});

document.getElementById('btn-step2-back').addEventListener('click', () => {
    showCreateStep(1);
});

document.getElementById('btn-step2-next').addEventListener('click', () => {
    hideMsg();
    if (!selectedSkin) { showMsg('Please select an appearance.'); return; }

    // Step 3 (clothing customization) is temporarily disabled — submit directly.
    const firstName = document.getElementById('c-first').value.trim();
    const lastName  = document.getElementById('c-last').value.trim();
    const birthDate = getDobValue();
    const gender    = document.querySelector('input[name="gender"]:checked')?.value;
    const bloodType = document.querySelector('input[name="blood"]:checked')?.value;

    showPending();
    Events.Call('ui_char_create', [firstName, lastName, birthDate, gender, bloodType, selectedSkin, null]);
});

// Step 3 temporarily disabled — btn-step3-back does not exist.
// document.getElementById('btn-step3-back').addEventListener('click', () => {
//     showCreateStep(2);
// });

// ── Ped skin selection ─────────────────────────────────────────────────────────

const PEDS_PER_PAGE = 4;
let pedPage = 1;
let selectedSkin = null;
let selectedAppearance = null;  // Component overrides {"0":[d,t], ...}; null = ped defaults

const $pedGrid     = document.getElementById('ped-grid');
const $pedPrev     = document.getElementById('ped-prev');
const $pedNext     = document.getElementById('ped-next');
const $pedPageInfo = document.getElementById('ped-page-info');

function getFilteredPeds() {
    const gender = document.querySelector('input[name="gender"]:checked')?.value || 'Male';
    return getPedsForGender(gender);
}

function renderPedGrid() {
    const peds = getFilteredPeds();
    const totalPages = Math.max(1, Math.ceil(peds.length / PEDS_PER_PAGE));
    pedPage = Math.min(pedPage, totalPages);
    const start = (pedPage - 1) * PEDS_PER_PAGE;
    const pagePeds = peds.slice(start, start + PEDS_PER_PAGE);

    $pedGrid.innerHTML = '';
    pagePeds.forEach(model => {
        const card = document.createElement('div');
        card.className = 'ped-card' + (selectedSkin === model ? ' selected' : '');
        card.dataset.model = model;
        card.innerHTML = `
            <img src="${getPedImageUrl(model)}" alt="${model}" onerror="this.style.display='none';this.nextElementSibling.style.display='flex';" />
            <div class="ped-placeholder" style="display:none">—</div>
        `;
        card.addEventListener('click', () => {
            selectedSkin = model;
            document.querySelectorAll('.ped-card').forEach(c => c.classList.remove('selected'));
            card.classList.add('selected');
            Events.Call('ui_char_preview', [model, selectedAppearance]);
        });
        $pedGrid.appendChild(card);
    });

    $pedPrev.disabled = pedPage <= 1;
    $pedNext.disabled = pedPage >= totalPages;
    $pedPageInfo.textContent = `Page ${pedPage} of ${totalPages}`;

    if (!selectedSkin || !peds.includes(selectedSkin)) {
        selectedSkin = peds[0] || null;
    }
}

$pedPrev.addEventListener('click', () => { pedPage--; renderPedGrid(); });
$pedNext.addEventListener('click', () => { pedPage++; renderPedGrid(); });

// ── Component customization (step 3) ────────────────────────────────────────────

let componentBounds = null;

Events.Subscribe('char_component_bounds', function(payload) {
    // Lua passes { bounds }; we receive bounds as first arg. Do NOT use payload[0]
    // when payload is the full bounds object (payload[0] would be component-0 only).
    const b = (Array.isArray(payload) && payload.length === 1) ? payload[0] : payload;
    // Accept full bounds (has per-component keys like "0","1",...) not single-component (has drawableMax at top)
    if (b && typeof b === 'object' && !('drawableMax' in b && !('0' in b))) {
        componentBounds = b;
        renderComponentGrid();
    }
});

const COMPONENT_LABELS = {
    0: 'Head', 1: 'Torso', 2: 'Legs', 3: 'Suse', 4: 'Hands', 5: 'Shoes',
    6: 'Jacket', 7: 'Hair', 8: 'Sus2', 9: 'Teeth', 10: 'Face'
};

function renderComponentGrid() {
    const $grid = document.getElementById('component-grid');
    $grid.innerHTML = '';
    const bounds = componentBounds;
    for (let i = 0; i <= 10; i++) {
        const key = String(i);
        let [d, t] = selectedAppearance[key] || [0, 0];
        const b = bounds && bounds[key];
        const drawableMax = (b && typeof b.drawableMax === 'number') ? b.drawableMax : 0;
        const textureMaxes = (b && (Array.isArray(b.textureMaxes) || b.textureMaxes)) ? b.textureMaxes : [0];
        const textureMax = (textureMaxes[d] ?? textureMaxes[d + 1] ?? textureMaxes[0] ?? 0);
        d = Math.max(0, Math.min(drawableMax, d));
        t = Math.max(0, Math.min(textureMax, t));
        selectedAppearance[key] = [d, t];

        const row = document.createElement('div');
        row.className = 'component-row';
        row.dataset.component = key;
        row.innerHTML = `
            <span class="component-label">${COMPONENT_LABELS[i]}</span>
            <div class="component-sliders">
                <div class="component-slider-group">
                    <label class="component-slider-label">Drawable</label>
                    <input type="range" min="0" max="${drawableMax}" value="${d}" data-component="${key}" data-type="drawable" class="component-slider" />
                    <span class="component-slider-value">${d}</span>
                </div>
                <div class="component-slider-group">
                    <label class="component-slider-label">Texture</label>
                    <input type="range" min="0" max="${textureMax}" value="${t}" data-component="${key}" data-type="texture" class="component-slider" />
                    <span class="component-slider-value">${t}</span>
                </div>
            </div>
        `;
        const sliders = row.querySelectorAll('.component-slider');
        sliders.forEach(slider => {
            slider.addEventListener('input', () => {
                onComponentSliderChange(key, row);
                updateAppearanceFromInputs();
            });
        });
        $grid.appendChild(row);
    }
}

function onComponentSliderChange(key, row) {
    const drawableSlider = row.querySelector('input[data-type="drawable"]');
    const textureSlider = row.querySelector('input[data-type="texture"]');
    const textureValueSpan = textureSlider?.closest('.component-slider-group')?.querySelector('.component-slider-value');
    const drawableValueSpan = drawableSlider?.closest('.component-slider-group')?.querySelector('.component-slider-value');
    if (drawableValueSpan) drawableValueSpan.textContent = drawableSlider?.value ?? 0;
    const d = parseInt(drawableSlider?.value ?? 0, 10);
    const b = componentBounds && componentBounds[key];
    const textureMaxes = (b && (Array.isArray(b.textureMaxes) || b.textureMaxes)) ? b.textureMaxes : [0];
    const textureMax = (textureMaxes[d] ?? textureMaxes[d + 1] ?? textureMaxes[0] ?? 0);
    if (textureSlider) {
        textureSlider.max = textureMax;
        const t = Math.min(parseInt(textureSlider.value ?? 0, 10), textureMax);
        textureSlider.value = t;
        if (textureValueSpan) textureValueSpan.textContent = t;
    }
}

function updateAppearanceFromInputs() {
    selectedAppearance = selectedAppearance || {};
    document.querySelectorAll('.component-row').forEach(row => {
        const key = row.dataset.component;
        if (!key) return;
        const drawableSlider = row.querySelector('input[data-type="drawable"]');
        const textureSlider = row.querySelector('input[data-type="texture"]');
        const d = parseInt(drawableSlider?.value ?? 0, 10);
        const t = parseInt(textureSlider?.value ?? 0, 10);
        selectedAppearance[key] = [d, t];
    });
    Events.Call('ui_char_preview', [selectedSkin, selectedAppearance]);
}

// ── Creation form ──────────────────────────────────────────────────────────────

initDobDropdowns();

$formCreate.addEventListener('submit', e => {
    e.preventDefault();
    if ($createStep3.classList.contains('hidden')) return; /* only submit from step 3 */
    hideMsg();

    const firstName = document.getElementById('c-first').value.trim();
    const lastName  = document.getElementById('c-last').value.trim();
    const birthDate = getDobValue();
    const gender    = document.querySelector('input[name="gender"]:checked')?.value;
    const bloodType = document.querySelector('input[name="blood"]:checked')?.value;

    if (!firstName) { showMsg('Please enter a first name.'); return; }
    if (!lastName)  { showMsg('Please enter a last name.');  return; }

    const dateErr = validateDobSelected();
    if (dateErr) { showMsg(dateErr); return; }

    if (!gender)    { showMsg('Please select a gender.'); return; }
    if (!bloodType) { showMsg('Please select a blood type.'); return; }
    if (!selectedSkin) { showMsg('Please select an appearance.'); return; }
    updateAppearanceFromInputs();

    const appearanceJson = JSON.stringify(selectedAppearance);
    showPending();
    Events.Call('ui_char_create', [firstName, lastName, birthDate, gender, bloodType, selectedSkin, appearanceJson]);
});
