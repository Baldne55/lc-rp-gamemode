-- client/handlers/notifications.lua
-- Supports two notification modes:
--   1. Chat-based (default): messages appear in game chat with colored prefixes.
--   2. UI toast (opt-in): CEF overlay with animated toast notifications.
-- Toggle via "notify_ui_toggle" remote event; preference is DB-persistent.
--
-- Usage from any CLIENT script (local event):
--   Events.Call("notify", { "success", "Your character has been saved." })
--   Events.Call("notify", { "error",   "You don't have permission." })
--
-- Usage from any SERVER script (remote event):
--   Notify.player(source, "info", "Welcome to Liberty City - Roleplay!")
--   Notify.broadcast("warn", "Server restart in 5 minutes.")
--
-- Types: "success" | "error" | "warn" | "info"

local g_useUI    = false
local g_notifyUI = nil
local g_ready    = false

-- Queued notifications that arrived before the UI was ready.
local g_queue = {}

local PREFIX = {
    success = "{7EB579}SUCCESS: {FFFFFF}",
    error   = "{A87474}ERROR: {FFFFFF}",
    warn    = "{D9CF8D}WARNING: {FFFFFF}",
    info    = "{508970}INFO: {FFFFFF}",
}

local function chatNotify(ntype, message)
    ntype = (ntype and PREFIX[ntype]) and ntype or "info"
    Chat.AddMessage(PREFIX[ntype] .. tostring(message))
end

local function uiNotify(ntype, message, duration)
    if g_notifyUI and g_ready then
        WebUI.CallEvent(g_notifyUI, "notify", { ntype, message, duration or 4000 })
    else
        g_queue[#g_queue + 1] = { ntype, message, duration or 4000 }
    end
end

local function flushQueue()
    for _, q in ipairs(g_queue) do
        WebUI.CallEvent(g_notifyUI, "notify", q)
    end
    g_queue = {}
end

local function createUI()
    if g_notifyUI == nil then
        g_ready = false
        g_notifyUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/notifications/index.html", true)
    end
end

local function destroyUI()
    if g_notifyUI ~= nil then
        WebUI.Destroy(g_notifyUI)
        g_notifyUI = nil
        g_ready = false
        g_queue = {}
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────

Events.Subscribe("char_selected", function(data)
    if type(data) == "table" then data = data[1] or data end
    local firstName = (data and data.firstName) or ""
    local lastName  = (data and data.lastName) or ""
    local name = (firstName .. " " .. lastName):match("^%s*(.-)%s*$") or "player"
    if #name == 0 then name = "player" end

    if g_useUI then
        createUI()
    end

    -- Welcome message (always chat-based so it's visible regardless of mode).
    chatNotify("info", "Welcome back to Liberty City - Roleplay, " .. name .. ".")
end)

Events.Subscribe("webUIReady", function(id)
    if id ~= g_notifyUI then return end
    g_ready = true
    flushQueue()
end)

Events.Subscribe("auth_success", function()
    destroyUI()
    g_useUI = false
end)

Events.Subscribe("notify", function(ntype, message, duration)
    if type(ntype) == "table" then
        ntype, message, duration = ntype[1], ntype[2], ntype[3]
    end
    if g_useUI then
        uiNotify(ntype, message, duration)
    else
        chatNotify(ntype, message)
    end
end, true)

-- F7 toggle: hide/show notification UI.
Events.Subscribe("hud_toggle_all", function(visible)
    if type(visible) == "table" then visible = visible[1] end
    if g_notifyUI and g_ready then
        WebUI.CallEvent(g_notifyUI, "hudToggle", { visible })
    end
end)

Events.Subscribe("notify_ui_toggle", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    g_useUI = payload[1] and true or false
    if g_useUI then
        createUI()
    else
        destroyUI()
    end
end, true)
