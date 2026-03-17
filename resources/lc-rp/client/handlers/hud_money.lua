-- client/handlers/hud_money.lua
-- CEF-based money HUD. Shows cash and total bank balance in the top-right corner.
-- Server pushes updates via "hud_money_update" remote event with { cash, bank }.
-- Toggle via "hud_money_toggle" remote event; preference is DB-persistent.
-- Values are cached so the UI can be updated when it finishes loading.

local g_moneyUI = nil
local g_ready   = false
local g_enabled = true
local g_cash    = 0
local g_bank    = 0

local function createUI()
    if g_moneyUI == nil then
        g_ready = false
        g_moneyUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/hud/money/index.html", true)
    end
end

local function destroyUI()
    if g_moneyUI ~= nil then
        WebUI.Destroy(g_moneyUI)
        g_moneyUI = nil
        g_ready = false
    end
end

local function pushToUI()
    if g_moneyUI and g_ready then
        WebUI.CallEvent(g_moneyUI, "hud_money", { g_cash, g_bank })
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────

Events.Subscribe("char_selected", function()
    if g_enabled then
        createUI()
    end
end)

Events.Subscribe("webUIReady", function(id)
    if id ~= g_moneyUI then return end
    g_ready = true
    pushToUI()
end)

Events.Subscribe("auth_success", function()
    destroyUI()
    g_enabled = true
    g_cash = 0
    g_bank = 0
end)

Events.Subscribe("hud_money_update", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    g_cash = tonumber(payload[1]) or 0
    g_bank = tonumber(payload[2]) or 0
    pushToUI()
end, true)

-- F7 toggle: hide/show money HUD.
Events.Subscribe("hud_toggle_all", function(visible)
    if type(visible) == "table" then visible = visible[1] end
    if g_moneyUI and g_ready then
        WebUI.CallEvent(g_moneyUI, "hudToggle", { visible })
    end
end)

Events.Subscribe("hud_money_toggle", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    g_enabled = payload[1] and true or false
    if g_enabled then
        createUI()
        pushToUI()
    else
        destroyUI()
    end
end, true)
