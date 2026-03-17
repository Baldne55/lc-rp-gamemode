-- client/handlers/hud_toggle.lua
-- F7 keybind: hides/shows all HUD and UI overlays (chat, money HUD, notifications).
-- Fires local "hud_toggle_all" event with { visible } that each UI handler listens to.

local F7_SCANCODE = 65
local g_visible = true
local g_hasCharacter = false

Events.Subscribe("char_selected", function()
    g_hasCharacter = true
end)

Events.Subscribe("auth_success", function()
    g_hasCharacter = false
    g_visible = true
end)

Events.Subscribe("scriptInit", function()
    local wasPressed = false
    Thread.Create(function()
        while true do
            if g_hasCharacter then
                local ok, held = pcall(Game.IsGameKeyboardKeyPressed, F7_SCANCODE)
                if ok and held and not wasPressed then
                    g_visible = not g_visible
                    Events.Call("hud_toggle_all", { g_visible })
                end
                wasPressed = ok and held or false
            end
            Thread.Pause(50)
        end
    end)
end)
