// https://stackoverflow.com/a/7053197
function ready(callback)
{
    if (document.readyState !== 'loading') callback();
    else if (document.addEventListener) document.addEventListener('DOMContentLoaded', callback);
    else document.attachEvent('onreadystatechange', function() {
        if (document.readyState === 'complete') callback();
    });
}

let chatInput = false;
let cmdList = [];
let hintsVisible = false;
let hintsSelection = 0;
let filteredHints = [];
let sendInputLock = false;

const inputHistory = [];
let inputHistoryPosition = -1;
let inputCache = "";

const MAX_INPUT_LENGTH = 255;
const STORAGE_KEY_FONT = "lc_rp_chat_fontSize";
const STORAGE_KEY_PAGE = "lc_rp_chat_pageSize";

function buildHintsFlatList() {
    const flat = [];
    for (let i = 0; i < cmdList.length; i++) {
        const cmd = cmdList[i];
        flat.push({ display: cmd.name, full: cmd.name, description: cmd.description || "" });
        if (cmd.aliases) {
            for (let j = 0; j < cmd.aliases.length; j++) {
                flat.push({ display: cmd.name, full: cmd.aliases[j], description: cmd.description || "" });
            }
        }
    }
    return flat;
}

function updateHints(value) {
    const dropdown = document.getElementById("hintsDropdown");
    if (!value || value.charAt(0) !== '/') {
        dropdown.classList.add("hide");
        dropdown.innerHTML = "";
        hintsVisible = false;
        return;
    }
    const prefix = value.toLowerCase();
    const flat = buildHintsFlatList();
    filteredHints = flat.filter(function(item) {
        return item.full.toLowerCase().indexOf(prefix) === 0;
    });
    if (filteredHints.length === 0) {
        dropdown.classList.add("hide");
        dropdown.innerHTML = "";
        hintsVisible = false;
        return;
    }
    hintsVisible = true;
    hintsSelection = 0;
    dropdown.innerHTML = "";
    for (let i = 0; i < filteredHints.length; i++) {
        const item = filteredHints[i];
        const div = document.createElement("div");
        div.className = "hintItem" + (i === 0 ? " selected" : "");
        div.dataset.full = item.full;
        div.dataset.index = String(i);
        var label = item.full + (item.display !== item.full ? " (" + item.display + ")" : "");
        if (item.description) {
            var span = document.createElement("span");
            span.className = "hintDesc";
            span.textContent = "– " + item.description;
            div.textContent = label + " ";
            div.appendChild(span);
        } else {
            div.textContent = label;
        }
        div.addEventListener("click", function() {
            hintsSelection = parseInt(this.dataset.index, 10);
            applySelectedHint();
        });
        dropdown.appendChild(div);
    }
    dropdown.classList.remove("hide");
}

function applySelectedHint() {
    if (!hintsVisible || filteredHints.length === 0) return false;
    const item = filteredHints[hintsSelection];
    const input = document.getElementById("chatinput");
    input.value = item.full + " ";
    input.selectionStart = input.selectionEnd = input.value.length;
    updateHints(input.value);
    return true;
}

function updateCharCount() {
    const input = document.getElementById("chatinput");
    const countEl = document.getElementById("charCount");
    if (!input || !countEl) return;
    const len = (input.value || "").length;
    countEl.textContent = len + "/" + MAX_INPUT_LENGTH;
}

function restoreFromStorage() {
    var chatbox = document.getElementById("chatbox");
    if (!chatbox) return;
    var font = null, page = null;
    try {
        var fontVal = parseInt(localStorage.getItem(STORAGE_KEY_FONT), 10);
        if (fontVal >= 12 && fontVal <= 24) {
            chatbox.style.setProperty("--chat-font-size", fontVal + "px");
            font = fontVal;
        }
        var pageVal = parseInt(localStorage.getItem(STORAGE_KEY_PAGE), 10);
        if (pageVal >= 10 && pageVal <= 30) {
            chatbox.style.setProperty("--chat-page-height", pageVal + "em");
            page = pageVal;
        }
        if (font !== null || page !== null) {
            Events.Call("chatSettingsRestored", [font, page]);
        }
    } catch (e) {}
}

ready(function() {
    restoreFromStorage();

    const chatInputEl = document.getElementById("chatinput");
    const charCountEl = document.getElementById("charCount");

    chatInputEl.addEventListener("input", function() {
        updateHints(chatInputEl.value);
        updateCharCount();
    });

    chatInputEl.addEventListener("keyup", function() {
        updateCharCount();
    });

    document.addEventListener("keydown", function(event) {
        switch (event.keyCode) {
            case 13: // Enter
                if (chatInput) {
                    event.preventDefault();
                    event.stopPropagation();
                    if (!sendInputLock) {
                        sendInput(false);
                    }
                }
                break;
            case 9: // Tab
                if (chatInput && hintsVisible && applySelectedHint()) {
                    event.preventDefault();
                }
                break;
            case 38: // Arrow Up
                if (chatInput) {
                    if (hintsVisible) {
                        hintsSelection = (hintsSelection - 1 + filteredHints.length) % filteredHints.length;
                        const items = document.querySelectorAll("#hintsDropdown .hintItem");
                        for (let i = 0; i < items.length; i++) {
                            items[i].classList.toggle("selected", i === hintsSelection);
                        }
                        event.preventDefault();
                    } else {
                        if (inputHistoryPosition === inputHistory.length - 1) return;
                        if (inputHistoryPosition === -1) inputCache = chatInputEl.value;
                        inputHistoryPosition++;
                        chatInputEl.value = inputHistory[inputHistoryPosition];
                        chatInputEl.selectionStart = chatInputEl.selectionEnd = chatInputEl.value.length;
                        event.preventDefault();
                    }
                }
                break;
            case 40: // Arrow Down
                if (chatInput) {
                    if (hintsVisible) {
                        hintsSelection = (hintsSelection + 1) % filteredHints.length;
                        const items = document.querySelectorAll("#hintsDropdown .hintItem");
                        for (let i = 0; i < items.length; i++) {
                            items[i].classList.toggle("selected", i === hintsSelection);
                        }
                        event.preventDefault();
                    } else {
                        if (inputHistoryPosition === -1) return;
                        if (inputHistoryPosition === 0) {
                            chatInputEl.value = inputCache;
                            inputHistoryPosition = -1;
                            return;
                        }
                        inputHistoryPosition--;
                        chatInputEl.value = inputHistory[inputHistoryPosition];
                        event.preventDefault();
                    }
                }
                break;
            case 33: // Page Up
                document.getElementById("messageslist").scrollTop -= 15;
                break;
            case 34: // Page Down
                document.getElementById("messageslist").scrollTop += 15;
                break;
            case 27: // Escape
                if (chatInput) {
                    if (hintsVisible) {
                        updateHints("");
                        hintsVisible = false;
                    } else {
                        toggleInput(false);
                    }
                    event.preventDefault();
                }
                break;
        }
    });
});

function sendInput() {
    if (sendInputLock) return;
    sendInputLock = true;

    let message = document.getElementById("chatinput").value.trim();
    message = message.replace(/\{[0-9a-fA-F]{6}\}/g, "");

    if (message.length < 1) {
        sendInputLock = false;
        toggleInput(false);
        return;
    }

    Events.Call("chatInput", [message]);

    inputHistory.unshift(message);
    if (inputHistory.length > 100) inputHistory.pop();
    inputHistoryPosition = -1;

    document.getElementById("chatinput").value = "";
    updateCharCount();
    toggleInput(false);

    setTimeout(function() { sendInputLock = false; }, 200);
}

function toggleInput(toggle) {
    if (toggle === chatInput) return;

    if (toggle) {
        chatInput = true;
        document.getElementById("chatinput").className = "inputBar";
        document.getElementById("chatinput").focus();
        document.getElementById("charCount").classList.remove("hide");
        updateCharCount();
    } else {
        chatInput = false;
        document.getElementById("chatinput").className = "hide";
        document.getElementById("charCount").classList.add("hide");
        updateHints("");
    }

    Events.Call("chatInputToggle", [chatInput]);
}

Events.Subscribe("forceInput", function(toggle) {
    toggleInput(toggle);
});

function escapeHtml(text) {
    if (typeof text !== "string") return "";
    var map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" };
    return text.replace(/[&<>"']/g, function(c) { return map[c]; });
}

function processColors(text) {
    if (typeof text !== "string") text = "";
    const regex = /{([A-Fa-f0-9]{6})}([^{}]*)/g;
    var result = "<div>";
    var lastIndex = 0;
    var match;
    while ((match = regex.exec(text)) !== null) {
        result += escapeHtml(text.substring(lastIndex, match.index));
        result += "<span style=\"color: #" + match[1] + "\">" + escapeHtml(match[2]) + "</span>";
        lastIndex = match.index + match[0].length;
    }
    result += escapeHtml(text.substring(lastIndex));
    result += "</div>";
    return result;
}

Events.Subscribe("chatMessage", function(message) {
    var text = (Array.isArray(message) && message[0] !== undefined) ? message[0] : (typeof message === "string" ? message : "");
    if (text.length < 1) return;

    var msgDiv = document.createElement("div");
    msgDiv.className = "message stroke";
    msgDiv.innerHTML = processColors(text);
    var messagesList = document.getElementById("messageslist");
    messagesList.appendChild(msgDiv);
    if (messagesList.childElementCount > 100) {
        messagesList.firstElementChild.remove();
    }
    messagesList.scrollTop = messagesList.scrollHeight;
});

Events.Subscribe("chatClear", function() {
    document.getElementById("messageslist").innerHTML = "";
    document.getElementById("messageslist").scrollTop = document.getElementById("messageslist").scrollHeight;
});

Events.Subscribe("cmdList", function(list) {
    if (Array.isArray(list)) {
        cmdList = list.filter(function(c) { return c && c.name; });
    } else if (list && typeof list === "object") {
        var keys = Object.keys(list).filter(function(k) { return /^\d+$/.test(k); }).sort(function(a, b) { return parseInt(a, 10) - parseInt(b, 10); });
        cmdList = keys.map(function(k) { return list[k]; }).filter(function(c) { return c && c.name; });
    } else {
        cmdList = [];
    }
});

Events.Subscribe("setFontSize", function(payload) {
    var size = (Array.isArray(payload) && payload[0] !== undefined) ? payload[0] : (payload || 14);
    var chatbox = document.getElementById("chatbox");
    if (chatbox) {
        chatbox.style.setProperty("--chat-font-size", size + "px");
        try { localStorage.setItem(STORAGE_KEY_FONT, String(size)); } catch (e) {}
    }
});

Events.Subscribe("setPageSize", function(payload) {
    var size = (Array.isArray(payload) && payload[0] !== undefined) ? payload[0] : (payload || 18);
    var chatbox = document.getElementById("chatbox");
    if (chatbox) {
        chatbox.style.setProperty("--chat-page-height", size + "em");
        try { localStorage.setItem(STORAGE_KEY_PAGE, String(size)); } catch (e) {}
    }
});

Events.Subscribe("hudToggle", function(payload) {
    var visible = (Array.isArray(payload) && payload[0] !== undefined) ? payload[0] : payload;
    document.body.style.visibility = visible ? "visible" : "hidden";
});

