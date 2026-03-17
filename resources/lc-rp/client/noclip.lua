-- client/noclip.lua
-- Noclip mode: fly through the world with WASD, Q/E turn, Shift/Ctrl up/down.
-- Permission is server-gated: client sends skynoclip:Request and waits for
-- skynoclip:Granted or skynoclip:Denied before activating.

local g_inNoclip     = false
local g_hasCharacter = false
-- L8: Track last tick time for delta-time scaling.
local g_lastTickMs   = 0
local NOCLIP_TARGET_MS = 16   -- target frame time (60 FPS)

Events.Subscribe("char_selected", function()
    g_hasCharacter = true
end)

-- L9: Reset character state flags on re-authentication.
Events.Subscribe("auth_success", function()
    g_hasCharacter = false
    g_inNoclip = false
end)

-- ── Server responses ─────────────────────────────────────────────────────────

Events.Subscribe("skynoclip:Granted", function(enable)
    enable = (enable == true or enable == 1)
    g_inNoclip = enable

    local playerId    = Game.GetPlayerId()
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local ped         = Game.GetPlayerChar(playerIndex)
    if not ped then return end

    if g_inNoclip then
        Game.SetCharVisible(ped, false)
        Game.SetPlayerControlForNetwork(playerIndex, false, false)
        Game.SetCharCollision(ped, false)
        Game.SetPlayerInvincible(playerIndex, true)
        Game.SetCharNeverTargetted(ped, true)
        Game.FreezeCharPosition(ped, true)
        Events.Call("notify", { "success", "Noclip enabled." })
        Game.PrintHelpForever("NOCLIP_HLP")
        Game.SetTextBackground(false)
    else
        PlayerUtil.restore()
        Events.Call("notify", { "info", "Noclip disabled." })
        Game.ClearHelp()
    end

    Events.Call("skynoclip:Toggle", { g_inNoclip })
end, true)

Events.Subscribe("skynoclip:Denied", function()
    g_inNoclip = false
    -- Server already sent a notification; nothing else to do client-side.
end, true)

-- ── Toggle command ────────────────────────────────────────────────────────────

local function requestNoclipToggle()
    if not g_hasCharacter then return end
    Events.CallRemote("skynoclip:Request", { not g_inNoclip })
end

Cmd.Register({
    name        = "/noclip",
    description = "Toggle noclip mode",
    run         = function(_args, _full) requestNoclipToggle() end,
})

-- ── Noclip movement loop ──────────────────────────────────────────────────────

-- L8: Delta-time scaled noclip movement.
local function moveNoclip()
    local playerId = Game.GetPlayerId()
    local ped      = Game.GetPlayerChar(Game.ConvertIntToPlayerindex(playerId))
    if not ped then return end

    local nowMs = os.clock() * 1000
    local dtMs = (g_lastTickMs > 0) and (nowMs - g_lastTickMs) or NOCLIP_TARGET_MS
    g_lastTickMs = nowMs
    local scale = dtMs / NOCLIP_TARGET_MS
    local moveSpeed = 0.5 * scale
    local turnSpeed = 1.5 * scale

    local kShift = Game.IsGameKeyboardKeyPressed(42)
    local kCtrl  = Game.IsGameKeyboardKeyPressed(29)
    local kW     = Game.IsGameKeyboardKeyPressed(17)
    local kS     = Game.IsGameKeyboardKeyPressed(31)
    local kA     = Game.IsGameKeyboardKeyPressed(30)
    local kD     = Game.IsGameKeyboardKeyPressed(32)
    local kQ     = Game.IsGameKeyboardKeyPressed(16)
    local kE     = Game.IsGameKeyboardKeyPressed(18)

    local x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, 0, 0)

    if kShift and kW then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, moveSpeed, moveSpeed)
    elseif kCtrl and kW then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, moveSpeed, -moveSpeed)
    elseif kShift and kS then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, -moveSpeed, -moveSpeed)
    elseif kCtrl and kS then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, -moveSpeed, moveSpeed)
    elseif kShift then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, 0, moveSpeed)
    elseif kCtrl then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, 0, -moveSpeed)
    elseif kQ and kW then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r + turnSpeed) % 360)
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, moveSpeed, 0)
    elseif kE and kW then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r - turnSpeed) % 360)
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, moveSpeed, 0)
    elseif kQ and kS then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r - turnSpeed) % 360)
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, -moveSpeed, 0)
    elseif kE and kS then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r + turnSpeed) % 360)
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, -moveSpeed, 0)
    elseif kW then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, moveSpeed, 0)
    elseif kS then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, 0, -moveSpeed, 0)
    elseif kA then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, -moveSpeed, 0, 0)
    elseif kD then
        x, y, z = Game.GetOffsetFromCharInWorldCoords(ped, moveSpeed, 0, 0)
    elseif kQ then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r + turnSpeed) % 360)
        return
    elseif kE then
        local r = Game.GetCharHeading(ped)
        Game.SetCharHeading(ped, (r - turnSpeed) % 360)
        return
    else
        return
    end

    Game.SetCharCoordinatesNoOffset(ped, x, y, z)
end

Events.Subscribe("scriptInit", function()
    Text.AddEntry(
        "NOCLIP_HLP",
        "Forward/Back: ~INPUT_MOVE_UP~/~INPUT_MOVE_DOWN~ ~n~Left/Right: ~INPUT_MOVE_LEFT~/~INPUT_MOVE_RIGHT~ ~n~Up/Down: ~INPUT_SPRINT~/~INPUT_DUCK~ ~n~Turn Left/Turn Right: ~INPUT_MELEE_KICK~/~INPUT_PICKUP~"
    )

    Thread.Create(function()
        while true do
            while g_inNoclip do
                moveNoclip()
                Thread.Pause(16)
            end
            Thread.Pause(100)
        end
    end)
end)
