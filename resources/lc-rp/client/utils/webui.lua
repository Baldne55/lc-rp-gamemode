-- client/utils/webui.lua
-- Creates a fullscreen WebUI; if the screen resolution exceeds 1920x1080, it creates
-- a 1080p WebUI and stretches it to fit, otherwise it uses the screen's native resolution.

function WebUI.CreateFullScreen(url, transparent)
    local webUI = nil

    local x, y = Game.GetScreenResolution()

    if not (x > 1920 or y > 1080) then
        webUI = WebUI.Create(url, x, y, transparent)
    else
        webUI = WebUI.Create(url, 1920, 1080, transparent)
        WebUI.SetRect(webUI, 0, 0, x, y)
    end

    return webUI
end
