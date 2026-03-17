'use strict';

// ── State ────────────────────────────────────────────────────────────────────

var inventoryData  = null;
var selectedSlot   = null;
var containerData  = null;
var selectedContainerSlot = null;
var mode           = 'normal';
var moveFromSlot   = null;
var activeContainerSlot = null;
var promptCallback = null;

// ── DOM refs ─────────────────────────────────────────────────────────────────

var $invGrid          = document.getElementById('inv-grid');
var $invWeightText    = document.getElementById('inv-weight-text');
var $invWeightFill    = document.getElementById('inv-weight-fill');
var $invSlotText      = document.getElementById('inv-slot-text');

var $containerPanel   = document.getElementById('container-panel');
var $containerName    = document.getElementById('container-name');
var $containerWeightText = document.getElementById('container-weight-text');
var $containerSlotText   = document.getElementById('container-slot-text');
var $containerGrid    = document.getElementById('container-grid');
var $containerPrompt  = document.getElementById('container-prompt');
var $containerPromptLabel  = document.getElementById('container-prompt-label');
var $containerPromptInput  = document.getElementById('container-prompt-input');
var $containerPromptConfirm = document.getElementById('container-prompt-confirm');
var $containerPromptCancel  = document.getElementById('container-prompt-cancel');

var NON_USABLE = { 'Weapon': true, 'Ammo': true, 'Container': true };

// ── Helpers ──────────────────────────────────────────────────────────────────

function escHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function findItem(slot) {
    if (!inventoryData || !inventoryData.items) return null;
    var s = Number(slot);
    for (var i = 0; i < inventoryData.items.length; i++) {
        if (Number(inventoryData.items[i].slot) === s) return inventoryData.items[i];
    }
    return null;
}

function findContainerItem(slot) {
    if (!containerData || !containerData.items) return null;
    var s = Number(slot);
    for (var i = 0; i < containerData.items.length; i++) {
        if (Number(containerData.items[i].slot) === s) return containerData.items[i];
    }
    return null;
}

// ── Action dispatch (single JSON-encoded event to avoid multi-arg issues) ────

function callLua(data) {
    Events.Call('ui_inv_action', [JSON.stringify(data)]);
}

function onActionClick(action) {
    var item = selectedSlot ? findItem(selectedSlot) : null;
    if (!item && action !== 'move') return;

    switch (action) {
        case 'use':
            callLua({ a: 'use', s: selectedSlot });
            break;
        case 'equip':
            if (inventoryData.equippedSlot === selectedSlot) {
                callLua({ a: 'unequip' });
            } else {
                callLua({ a: 'equip', s: selectedSlot });
            }
            break;
        case 'drop':
            if (item.maxStack > 1 && item.amount > 1) {
                showPrompt('Amount to drop', item.amount, function(amount) {
                    callLua({ a: 'drop', s: selectedSlot, n: amount });
                });
            } else {
                callLua({ a: 'drop', s: selectedSlot, n: item.amount });
            }
            break;
        case 'give':
            if (item.maxStack > 1 && item.amount > 1) {
                showPrompt('Amount to give', item.amount, function(amount) {
                    callLua({ a: 'give', s: selectedSlot, n: amount });
                });
            } else {
                callLua({ a: 'give', s: selectedSlot, n: item.amount });
            }
            break;
        case 'move':
            mode = 'move';
            moveFromSlot = selectedSlot;
            renderGrid();
            break;
        case 'container':
            activeContainerSlot = selectedSlot;
            callLua({ a: 'container', s: selectedSlot });
            break;
        case 'rename':
            showPrompt('New name (empty to reset)', '', function(val) {
                var name = String(val).trim();
                callLua({ a: 'rename', s: selectedSlot, name: name || '' });
            }, 'text');
            break;
        case 'removesn':
            callLua({ a: 'removesn', s: selectedSlot });
            break;
    }
}

// ── Render: Inventory Grid ───────────────────────────────────────────────────
// Action buttons are rendered inside the grid as additional cells.

function renderGrid() {
    $invGrid.innerHTML = '';
    if (!inventoryData) return;

    var maxSlots = inventoryData.maxSlots || 20;
    var item = selectedSlot ? findItem(selectedSlot) : null;

    // Render inventory slots
    for (var s = 1; s <= maxSlots; s++) {
        var slotItem = findItem(s);
        var el = document.createElement('div');
        el.className = 'inv-slot';
        el.setAttribute('data-slot', String(s));

        if (slotItem) {
            var isEquipped = inventoryData.equippedSlot === s;
            var html = '';
            if (isEquipped) {
                html += '<div class="inv-slot-equipped">Equipped</div>';
            }
            html += '<div class="inv-slot-num">' + s + '</div>';
            html += '<div class="inv-slot-name">' + escHtml(slotItem.name) + '</div>';
            html += '<div class="inv-slot-meta">';
            html += '<span class="inv-slot-cat">' + escHtml(slotItem.category) + '</span>';
            if (slotItem.amount > 1) {
                html += '<span class="inv-slot-amount">x' + slotItem.amount + '</span>';
            }
            html += '</div>';
            html += '<div class="inv-slot-weight">' + slotItem.totalWeight.toFixed(2) + ' kg</div>';

            if (slotItem.quality != null) {
                html += '<div class="inv-slot-bar">Q <div class="inv-slot-bar-track"><div class="inv-slot-bar-fill quality" style="width:' + slotItem.quality + '%"></div></div> ' + slotItem.quality + '%</div>';
            }
            if (slotItem.purity != null) {
                html += '<div class="inv-slot-bar">P <div class="inv-slot-bar-track"><div class="inv-slot-bar-fill purity" style="width:' + slotItem.purity + '%"></div></div> ' + slotItem.purity + '%</div>';
            }
            if (slotItem.serial) {
                html += '<div class="inv-slot-extra">S/N: ' + escHtml(slotItem.serial) + '</div>';
            }
            if (slotItem.isContainer) {
                html += '<div class="inv-slot-extra">' + (slotItem.containerUsedSlots || 0) + '/' + (slotItem.containerSlots || 0) + ' slots</div>';
            }

            el.innerHTML = html;

            if (mode === 'move' && moveFromSlot !== s) {
                el.classList.add('move-target');
            }
            if (selectedSlot === s) {
                el.classList.add('selected');
            }
            el.addEventListener('click', onSlotClick);
        } else {
            el.classList.add('empty');
            if (mode === 'move') {
                el.classList.remove('empty');
                el.classList.add('move-target');
                el.innerHTML = '<div class="inv-slot-num">' + s + '</div><div class="inv-slot-empty-label">Move here</div>';
                el.addEventListener('click', onSlotClick);
            } else {
                el.innerHTML = '<div class="inv-slot-num">' + s + '</div><div class="inv-slot-empty-label">Empty</div>';
            }
        }

        $invGrid.appendChild(el);
    }

    // ── Render action buttons as grid cells ──
    var actions = [
        { id: 'use',       label: 'Use',       enabled: item && !NON_USABLE[item.category] },
        { id: 'equip',     label: (item && item.isWeapon && inventoryData.equippedSlot === selectedSlot) ? 'Unequip' : 'Equip', enabled: item && item.isWeapon },
        { id: 'drop',      label: 'Drop',      enabled: !!item },
        { id: 'give',      label: 'Give',      enabled: !!item },
        { id: 'move',      label: 'Move',      enabled: !!item },
        { id: 'container', label: 'Container', enabled: item && item.isContainer },
        { id: 'rename',    label: 'Rename',    enabled: !!item },
        { id: 'removesn',  label: 'Remove S/N', enabled: item && item.isWeapon && !!item.serial }
    ];

    for (var a = 0; a < actions.length; a++) {
        var act = actions[a];
        var btn = document.createElement('div');
        btn.className = 'inv-action' + (act.enabled ? '' : ' inv-disabled');
        btn.textContent = act.label;
        btn.setAttribute('data-action', act.id);
        (function(actionId) {
            btn.addEventListener('click', function() {
                if (this.classList.contains('inv-disabled')) return;
                onActionClick(actionId);
            });
        })(act.id);
        $invGrid.appendChild(btn);
    }

    // ── Render prompt row (spanning full width, hidden by default) ──
    var promptRow = document.createElement('div');
    promptRow.id = 'inv-prompt';
    promptRow.className = 'inv-prompt-row hidden';
    promptRow.innerHTML = '<span id="prompt-label">Amount</span>' +
        '<input type="number" id="prompt-input" min="1" value="1" />' +
        '<div id="prompt-actions">' +
        '<div class="inv-action" id="prompt-confirm">OK</div>' +
        '<div class="inv-action" id="prompt-cancel">Cancel</div>' +
        '</div>';
    $invGrid.appendChild(promptRow);

    // Attach prompt handlers
    var pConfirm = document.getElementById('prompt-confirm');
    var pCancel = document.getElementById('prompt-cancel');
    var pInput = document.getElementById('prompt-input');

    if (pConfirm) {
        pConfirm.addEventListener('click', function() {
            if (!promptCallback) return;
            var val;
            if (pInput.type === 'number') {
                val = Math.max(1, parseInt(pInput.value, 10) || 1);
                if (promptMaxValue) val = Math.min(val, promptMaxValue);
            } else {
                val = pInput.value;
            }
            var cb = promptCallback;
            hidePrompt();
            cb(val);
        });
    }
    if (pCancel) {
        pCancel.addEventListener('click', function() {
            hidePrompt();
        });
    }
    if (pInput) {
        pInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && pConfirm) {
                pConfirm.click();
            } else if (e.key === 'Escape') {
                hidePrompt();
            }
        });
    }

    // Update header stats
    var w = inventoryData.weight || 0;
    var mw = inventoryData.maxWeight || 50;
    var sc = inventoryData.slotCount || 0;
    var ms = inventoryData.maxSlots || 20;
    $invWeightText.textContent = w.toFixed(2) + ' / ' + mw.toFixed(2) + ' kg';
    $invWeightFill.style.width = Math.min(100, (w / mw) * 100) + '%';
    $invSlotText.textContent = sc + ' / ' + ms + ' slots';
}

// ── Slot click ───────────────────────────────────────────────────────────────

function onSlotClick(e) {
    var slotEl = e.currentTarget;
    var slot = parseInt(slotEl.getAttribute('data-slot'), 10);

    if (mode === 'move' && moveFromSlot != null) {
        if (slot !== moveFromSlot) {
            callLua({ a: 'move', s: moveFromSlot, t: slot });
        }
        exitMode();
        return;
    }

    selectedSlot = slot;
    hidePrompt();
    renderGrid();
}

// ── Prompt ────────────────────────────────────────────────────────────────────

var promptMaxValue = null;

function showPrompt(label, defaultValue, callback, inputType) {
    var promptEl = document.getElementById('inv-prompt');
    var labelEl = document.getElementById('prompt-label');
    var inputEl = document.getElementById('prompt-input');
    if (!promptEl || !labelEl || !inputEl) return;

    promptEl.classList.remove('hidden');
    labelEl.textContent = label;
    promptCallback = callback;

    if (inputType === 'text') {
        inputEl.type = 'text';
        inputEl.min = '';
        inputEl.max = '';
        inputEl.value = defaultValue || '';
        inputEl.placeholder = 'Leave empty to reset';
        promptMaxValue = null;
    } else {
        inputEl.type = 'number';
        inputEl.min = '1';
        inputEl.max = String(defaultValue || 1);
        inputEl.value = defaultValue || 1;
        inputEl.placeholder = '';
        promptMaxValue = defaultValue || 1;
    }

    inputEl.focus();
    inputEl.select();
}

function hidePrompt() {
    var promptEl = document.getElementById('inv-prompt');
    if (promptEl) promptEl.classList.add('hidden');
    promptCallback = null;
}

function exitMode() {
    mode = 'normal';
    moveFromSlot = null;
    renderGrid();
}

// ── Container panel ──────────────────────────────────────────────────────────

function renderContainerPanel() {
    if (!containerData) {
        $containerPanel.classList.add('hidden');
        return;
    }

    $containerPanel.classList.remove('hidden');
    $containerName.textContent = containerData.containerName || '--';
    $containerWeightText.textContent = (containerData.weight || 0).toFixed(2) + ' / ' + (containerData.maxWeight || 0).toFixed(2) + ' kg';
    $containerSlotText.textContent = (containerData.slotCount || 0) + ' / ' + (containerData.maxSlots || 0) + ' slots';

    $containerGrid.innerHTML = '';
    var maxSlots = containerData.maxSlots || 0;

    for (var s = 1; s <= maxSlots; s++) {
        var cItem = findContainerItem(s);
        var el = document.createElement('div');
        el.className = 'inv-slot';
        el.setAttribute('data-container-slot', String(s));

        if (cItem) {
            var html = '<div class="inv-slot-num">' + s + '</div>';
            html += '<div class="inv-slot-name">' + escHtml(cItem.name) + '</div>';
            html += '<div class="inv-slot-meta">';
            html += '<span class="inv-slot-cat">' + escHtml(cItem.category) + '</span>';
            if (cItem.amount > 1) {
                html += '<span class="inv-slot-amount">x' + cItem.amount + '</span>';
            }
            html += '</div>';
            html += '<div class="inv-slot-weight">' + cItem.totalWeight.toFixed(2) + ' kg</div>';
            if (cItem.quality != null) {
                html += '<div class="inv-slot-bar">Q <div class="inv-slot-bar-track"><div class="inv-slot-bar-fill quality" style="width:' + cItem.quality + '%"></div></div> ' + cItem.quality + '%</div>';
            }
            if (cItem.purity != null) {
                html += '<div class="inv-slot-bar">P <div class="inv-slot-bar-track"><div class="inv-slot-bar-fill purity" style="width:' + cItem.purity + '%"></div></div> ' + cItem.purity + '%</div>';
            }
            if (cItem.serial) {
                html += '<div class="inv-slot-extra">S/N: ' + escHtml(cItem.serial) + '</div>';
            }

            el.innerHTML = html;
            if (selectedContainerSlot === s) {
                el.classList.add('selected');
            }
            el.addEventListener('click', onContainerSlotClick);
        } else {
            el.classList.add('empty');
            el.innerHTML = '<div class="inv-slot-num">' + s + '</div><div class="inv-slot-empty-label">Empty</div>';
        }

        $containerGrid.appendChild(el);
    }

    // Render container action buttons inside the grid
    var invItem = selectedSlot ? findItem(selectedSlot) : null;
    var selCItem = selectedContainerSlot ? findContainerItem(selectedContainerSlot) : null;

    var storeEnabled = !!(invItem && !invItem.isContainer && activeContainerSlot && selectedSlot !== activeContainerSlot);
    var retrieveEnabled = !!selCItem;

    var storeBtn = document.createElement('div');
    storeBtn.className = 'inv-action' + (storeEnabled ? '' : ' inv-disabled');
    storeBtn.textContent = 'Store';
    storeBtn.addEventListener('click', function() {
        if (this.classList.contains('inv-disabled')) return;
        var ii = selectedSlot ? findItem(selectedSlot) : null;
        if (!ii || !activeContainerSlot) return;
        if (ii.maxStack > 1 && ii.amount > 1) {
            showContainerPrompt('Amount to store', ii.amount, function(amount) {
                callLua({ a: 'store', cs: activeContainerSlot, is: selectedSlot, n: amount });
            });
        } else {
            callLua({ a: 'store', cs: activeContainerSlot, is: selectedSlot, n: ii.amount });
        }
    });
    $containerGrid.appendChild(storeBtn);

    var retrieveBtn = document.createElement('div');
    retrieveBtn.className = 'inv-action' + (retrieveEnabled ? '' : ' inv-disabled');
    retrieveBtn.textContent = 'Retrieve';
    retrieveBtn.addEventListener('click', function() {
        if (this.classList.contains('inv-disabled')) return;
        var ci = selectedContainerSlot ? findContainerItem(selectedContainerSlot) : null;
        if (!ci || !activeContainerSlot) return;
        if (ci.maxStack > 1 && ci.amount > 1) {
            showContainerPrompt('Amount to retrieve', ci.amount, function(amount) {
                callLua({ a: 'retrieve', cs: activeContainerSlot, cis: selectedContainerSlot, n: amount });
            });
        } else {
            callLua({ a: 'retrieve', cs: activeContainerSlot, cis: selectedContainerSlot, n: ci.amount });
        }
    });
    $containerGrid.appendChild(retrieveBtn);
}

function onContainerSlotClick(e) {
    var slot = parseInt(e.currentTarget.getAttribute('data-container-slot'), 10);
    selectedContainerSlot = slot;
    renderContainerPanel();
}

// ── Container prompt ─────────────────────────────────────────────────────────

var containerPromptCallback = null;
var containerPromptMaxValue = null;

function showContainerPrompt(label, defaultValue, callback) {
    $containerPrompt.classList.remove('hidden');
    $containerPromptLabel.textContent = label;
    $containerPromptInput.type = 'number';
    $containerPromptInput.min = '1';
    $containerPromptInput.max = String(defaultValue || 1);
    $containerPromptInput.value = defaultValue || 1;
    containerPromptCallback = callback;
    containerPromptMaxValue = defaultValue || 1;
    $containerPromptInput.focus();
    $containerPromptInput.select();
}

function hideContainerPrompt() {
    $containerPrompt.classList.add('hidden');
    containerPromptCallback = null;
}

$containerPromptConfirm.addEventListener('click', function() {
    if (!containerPromptCallback) return;
    var val = Math.max(1, parseInt($containerPromptInput.value, 10) || 1);
    if (containerPromptMaxValue) val = Math.min(val, containerPromptMaxValue);
    var cb = containerPromptCallback;
    hideContainerPrompt();
    cb(val);
});

$containerPromptCancel.addEventListener('click', function() {
    hideContainerPrompt();
});

$containerPromptInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {
        $containerPromptConfirm.click();
    } else if (e.key === 'Escape') {
        hideContainerPrompt();
    }
});

// ── Close buttons ────────────────────────────────────────────────────────────

document.getElementById('btn-close').addEventListener('click', function() {
    Events.Call('ui_inv_close', []);
});

document.getElementById('btn-container-close').addEventListener('click', function() {
    containerData = null;
    selectedContainerSlot = null;
    activeContainerSlot = null;
    $containerPanel.classList.add('hidden');
    renderGrid();
});

// ── Keyboard: Escape to close ────────────────────────────────────────────────

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        if (mode !== 'normal') {
            exitMode();
        } else if (document.getElementById('inv-prompt') && !document.getElementById('inv-prompt').classList.contains('hidden')) {
            hidePrompt();
        } else if (!$containerPrompt.classList.contains('hidden')) {
            hideContainerPrompt();
        } else if (containerData) {
            containerData = null;
            selectedContainerSlot = null;
            activeContainerSlot = null;
            $containerPanel.classList.add('hidden');
        } else {
            Events.Call('ui_inv_close', []);
        }
    }
});

// ── Event bridge (from Lua via WebUI.CallEvent) ──────────────────────────────

Events.Subscribe('inv_data', function(payload) {
    if (payload && typeof payload === 'object' && !Array.isArray(payload) && payload.items === undefined && payload[0]) {
        payload = payload[0];
    }
    if (Array.isArray(payload) && payload.length === 1 && typeof payload[0] === 'object') {
        payload = payload[0];
    }

    inventoryData = payload;

    if (inventoryData && inventoryData.items && !Array.isArray(inventoryData.items)) {
        inventoryData.items = Object.values(inventoryData.items);
    }

    if (selectedSlot && !findItem(selectedSlot)) {
        selectedSlot = null;
    }

    renderGrid();

    if (containerData && activeContainerSlot) {
        callLua({ a: 'container', s: activeContainerSlot });
    }
});

Events.Subscribe('inv_container_data', function(payload) {
    if (payload && typeof payload === 'object' && !Array.isArray(payload) && payload.containerSlot === undefined && payload[0]) {
        payload = payload[0];
    }
    if (Array.isArray(payload) && payload.length === 1 && typeof payload[0] === 'object') {
        payload = payload[0];
    }

    containerData = payload;

    if (containerData && containerData.items && !Array.isArray(containerData.items)) {
        containerData.items = Object.values(containerData.items);
    }

    if (containerData) {
        activeContainerSlot = containerData.containerSlot;
    }

    if (selectedContainerSlot && !findContainerItem(selectedContainerSlot)) {
        selectedContainerSlot = null;
    }

    renderContainerPanel();
});

Events.Subscribe('inv_close', function() {
    Events.Call('ui_inv_close', []);
});
