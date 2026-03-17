-- client/cmds.lua
-- Client-side commands registered via Cmd.Register().
-- Server-side command hints are auto-pushed after character selection
-- (see ServerCmd.sendHints in core/commands/server.lua).

-- Client commands -----------------------------------------------------------------

Cmd.Register({
    name        = "/clearchat",
    aliases     = { "/cls" },
    description = "Clear the chat window",
    run = function(_args, _full)
        Chat.Clear()
    end,
})

Cmd.Register({
    name        = "/coords",
    aliases     = { "/pos", "/mypos" },
    description = "Show your current position and heading",
    run = function(_args, _full)
        local playerId    = Game.GetPlayerId()
        local playerIndex = Game.ConvertIntToPlayerindex(playerId)
        local playerChar  = Game.GetPlayerChar(playerIndex)
        if not playerChar then
            Events.Call("notify", { "error", "No character." })
            return
        end

        local x, y, z    = Game.GetCharCoordinates(playerChar)
        local heading     = Game.GetCharHeading(playerChar)

        Events.Call("notify", { "info", string.format("Position: X=%.2f, Y=%.2f, Z=%.2f, heading=%.2f.", x, y, z, heading) })
        Events.Call("notify", { "info", string.format("Lua: { x = %.2f, y = %.2f, z = %.2f, r = %.2f }", x, y, z, heading) })
    end,
})

Cmd.Register({
    name        = "/fontsize",
    description = "Set chat font size (12-24). No args: show current.",
    run = function(args, _full)
        if #args == 0 then
            Events.Call("notify", { "info", string.format("Chat font size: %d.", Chat.GetFontSize()) })
            return
        end
        local size = tonumber(args[1])
        if not size or size < 12 or size > 24 then
            Events.Call("notify", { "error", "Font size must be between 12 and 24." })
            return
        end
        Chat.SetFontSize(math.floor(size))
        Events.CallRemote("chat_prefs_save", { Chat.GetFontSize(), Chat.GetPageSize() })
        Events.Call("notify", { "success", string.format("Chat font size set to %d.", Chat.GetFontSize()) })
    end,
})

Cmd.Register({
    name        = "/pagesize",
    description = "Set chat page size in lines (10-30). No args: show current.",
    run = function(args, _full)
        if #args == 0 then
            Events.Call("notify", { "info", string.format("Chat page size: %d lines.", Chat.GetPageSize()) })
            return
        end
        local size = tonumber(args[1])
        if not size or size < 10 or size > 30 then
            Events.Call("notify", { "error", "Page size must be between 10 and 30." })
            return
        end
        Chat.SetPageSize(math.floor(size))
        Events.CallRemote("chat_prefs_save", { Chat.GetFontSize(), Chat.GetPageSize() })
        Events.Call("notify", { "success", string.format("Chat page size set to %d lines.", Chat.GetPageSize()) })
    end,
})

Cmd.Register({
    name        = "/camcoords",
    aliases     = { "/campos" },
    description = "Show the current camera position",
    run = function(_args, _full)
        local cam = Game.GetGameCam()
        if not cam then
            Events.Call("notify", { "error", "No camera." })
            return
        end
        local ok, x, y, z = pcall(function()
            return Game.GetCamPos(cam)
        end)
        if not ok or not x then
            Events.Call("notify", { "error", "Could not get camera position." })
            return
        end
        Events.Call("notify", { "info", string.format("Camera: X=%.2f, Y=%.2f, Z=%.2f.", x, y, z) })
        Events.Call("notify", { "info", string.format("Lua: { x = %.2f, y = %.2f, z = %.2f }", x, y, z) })
    end,
})

Cmd.Register({
    name        = "/settings",
    aliases     = { "/prefs", "/preferences" },
    description = "Open the settings panel",
    run = function(_args, _full)
        Events.Call("settings_toggle")
    end,
})
