-- client/handlers/settings.lua
-- Manages the settings WebUI lifecycle and bridges JS events to server.
-- Toggle via "settings_toggle" local event (fired by /settings command).

local g_settingsUI = nil
local g_ready      = false
local g_pending    = nil   -- cached settings data if it arrives before webUIReady

local function pushToUI()
    if g_settingsUI and g_ready and g_pending then
        WebUI.CallEvent(g_settingsUI, "settings_load", g_pending)
        g_pending = nil
    end
end

local function createUI()
    if g_settingsUI == nil then
        g_ready = false
        g_pending = nil
        g_settingsUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/settings/index.html", true)
    end
end

local function destroyUI()
    if g_settingsUI ~= nil then
        WebUI.SetFocus(-1)
        WebUI.Destroy(g_settingsUI)
        g_settingsUI = nil
        g_ready = false
        g_pending = nil
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

Events.Subscribe("settings_toggle", function()
    if g_settingsUI then
        destroyUI()
    else
        createUI()
        Events.CallRemote("settings_request", {})
    end
end)

Events.Subscribe("webUIReady", function(id)
    if id ~= g_settingsUI then return end
    g_ready = true
    WebUI.SetFocus(g_settingsUI)
    pushToUI()
end)

-- Server sends current settings when panel opens.
Events.Subscribe("settings_data", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    g_pending = payload
    pushToUI()
end, true)

-- Server sends feedback after password change or error.
Events.Subscribe("settings_result", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    if g_settingsUI and g_ready then
        WebUI.CallEvent(g_settingsUI, "settings_feedback", payload)
    end
    -- Also show as notification for visibility.
    local ntype = payload[1] or "info"
    local msg   = payload[2] or ""
    if #msg > 0 then
        Events.Call("notify", { ntype, msg })
    end
end, true)

-- From WebUI JS: save a setting.
Events.Subscribe("ui_settings_save", function(key, value)
    if type(key) == "table" then key, value = key[1], key[2] end
    -- Apply chat prefs locally for instant feedback.
    if key == "chatFontSize" then
        local size = tonumber(value)
        if size and size >= 12 and size <= 24 then
            Chat.SetFontSize(math.floor(size))
        end
    elseif key == "chatPageSize" then
        local size = tonumber(value)
        if size and size >= 10 and size <= 30 then
            Chat.SetPageSize(math.floor(size))
        end
    end
    Events.CallRemote("settings_save", { key, value })
end)

-- From WebUI JS: change password.
Events.Subscribe("ui_settings_password", function(currentPw, newPw)
    if type(currentPw) == "table" then currentPw, newPw = currentPw[1], currentPw[2] end
    Events.CallRemote("settings_change_password", { currentPw, newPw })
end)

-- From WebUI JS: close panel.
Events.Subscribe("ui_settings_close", function()
    destroyUI()
end)

-- Cleanup on re-login.
Events.Subscribe("auth_success", function()
    destroyUI()
end)
