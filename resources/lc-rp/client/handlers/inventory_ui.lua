-- client/handlers/inventory_ui.lua
-- Manages the inventory WebUI lifecycle and bridges JS events to server.
--
-- Toggle: server sends "inv_ui_toggle" to enable/disable.
-- When enabled, pressing I or typing /inventory opens the graphical UI.
-- When disabled, /inventory routes through chat to server (chat-based).

local g_invUI     = nil
local g_isOpen    = false
local g_uiEnabled = false
local g_charSelected = false

-- ── Open / Close ──────────────────────────────────────────────────────────

local function openInventory()
    if g_isOpen then return end
    if not g_charSelected then return end
    g_isOpen = true
    g_invUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/inventory/index.html", true)
end

local function closeInventory()
    if not g_isOpen then return end
    g_isOpen = false
    if g_invUI then
        WebUI.SetFocus(-1)
        WebUI.Destroy(g_invUI)
        g_invUI = nil
    end
end

-- ── Track character selection ─────────────────────────────────────────────

Events.Subscribe("char_selected", function()
    g_charSelected = true
end)

-- ── Toggle event from server ──────────────────────────────────────────────

Events.Subscribe("inv_ui_toggle", function(enabled)
    if type(enabled) == "table" then enabled = enabled[1] end
    g_uiEnabled = enabled and true or false
end, true)

-- ── WebUI ready ───────────────────────────────────────────────────────────

Events.Subscribe("webUIReady", function(id)
    if id ~= g_invUI then return end
    WebUI.SetFocus(g_invUI)
    Events.CallRemote("inv_open", {})
end)

-- ── Server → Client → WebUI forwarding ───────────────────────────────────

Events.Subscribe("inv_data", function(payload)
    if type(payload) == "table" and payload[1] and type(payload[1]) == "table" then
        payload = payload[1]
    end
    if not g_invUI then return end
    WebUI.CallEvent(g_invUI, "inv_data", { payload })
end, true)

Events.Subscribe("inv_container_data", function(payload)
    if type(payload) == "table" and payload[1] and type(payload[1]) == "table" then
        payload = payload[1]
    end
    if not g_invUI then return end
    WebUI.CallEvent(g_invUI, "inv_container_data", { payload })
end, true)

-- ── JS → Client → Server forwarding ──────────────────────────────────────
-- Close uses its own no-args event (proven to work).

Events.Subscribe("ui_inv_close", function()
    closeInventory()
end)

-- All other actions arrive as a single JSON-encoded string via "ui_inv_action".
-- This avoids multi-argument Events.Call issues between JS and Lua.

Events.Subscribe("ui_inv_action", function(jsonStr)
    if type(jsonStr) == "table" then jsonStr = jsonStr[1] end
    local ok, data = pcall(JSON.decode, tostring(jsonStr))
    if not ok or type(data) ~= "table" then return end

    local action = data.a
    if action == "use" then
        Events.CallRemote("inv_action", { "useitem", tostring(data.s) })
    elseif action == "equip" then
        Events.CallRemote("inv_action", { "equip", tostring(data.s) })
    elseif action == "unequip" then
        Events.CallRemote("inv_action", { "unequip" })
    elseif action == "drop" then
        Events.CallRemote("inv_drop", { tostring(data.s), tostring(data.n) })
    elseif action == "give" then
        Events.CallRemote("inv_action", { "giveitem", tostring(data.s), tostring(data.n) })
    elseif action == "move" then
        Events.CallRemote("inv_action", { "moveitem", tostring(data.s), tostring(data.t) })
    elseif action == "container" then
        Events.CallRemote("inv_container_open", { tostring(data.s) })
    elseif action == "store" then
        Events.CallRemote("inv_action", { "store", tostring(data.cs), tostring(data.is), tostring(data.n) })
    elseif action == "retrieve" then
        Events.CallRemote("inv_action", { "retrieve", tostring(data.cs), tostring(data.cis), tostring(data.n) })
    elseif action == "rename" then
        Events.CallRemote("inv_action", { "nameitem", tostring(data.s), tostring(data.name) })
    elseif action == "removesn" then
        Events.CallRemote("inv_action", { "removesn", tostring(data.s) })
    end
end)

-- ── Client command: /inventory and /inv ───────────────────────────────────
-- When UI mode is enabled, intercept locally and open the WebUI.
-- When disabled, route through rp_chat_message so the server handles it
-- via the normal chat command flow (strips "/" and calls ServerCmd.execute).

Cmd.Register({
    name        = "/inventory",
    aliases     = { "/inv" },
    description = "Open your inventory",
    run = function(_args, _full)
        if g_uiEnabled then
            if g_isOpen then
                closeInventory()
            else
                openInventory()
            end
        else
            -- UI mode disabled: send through normal chat command path.
            Events.CallRemote("rp_chat_message", { "/inventory" })
        end
    end,
})

-- ── Keybind: I key (scan code 23) ────────────────────────────────────────
-- Uses Game.IsGameKeyboardKeyPressed with manual edge detection.

Events.Subscribe("scriptInit", function()
    local wasPressed = false
    Thread.Create(function()
        while true do
            if g_uiEnabled and g_charSelected then
                local ok, held = pcall(Game.IsGameKeyboardKeyPressed, 23)
                if ok and held and not wasPressed then
                    if g_isOpen then
                        closeInventory()
                    else
                        openInventory()
                    end
                end
                wasPressed = ok and held or false
            end
            Thread.Pause(50)
        end
    end)
end)
