-- client_position_sync.lua
-- Sends local player position and heading to the server for proximity chat.
-- Health and armour are handled separately by client_health_sync.lua.
-- Only runs when the player has selected a character and is in the world (logged-in character).

local SYNC_INTERVAL_MS = ClientConfig.SYNC_INTERVAL_MS
local g_hasCharacter = false
-- L7: Track noclip state to suppress position sync while invisible.
local g_noclipActive = false

Events.Subscribe("char_selected", function()
    g_hasCharacter = true
end)

-- L9: Reset g_hasCharacter on return to character selection.
Events.Subscribe("auth_success", function()
    g_hasCharacter = false
end)

Events.Subscribe("skynoclip:Toggle", function(enable)
    g_noclipActive = (enable == true or enable == 1)
end)

Events.Subscribe("scriptInit", function()
    Thread.Create(function()
        while true do
            Thread.Pause(SYNC_INTERVAL_MS)
            if g_hasCharacter and not g_noclipActive then
                local playerId    = Game.GetPlayerId()
                local playerIndex = Game.ConvertIntToPlayerindex(playerId)
                local ped         = Game.GetPlayerChar(playerIndex)
                if ped then
                    local x, y, z = Game.GetCharCoordinates(ped)
                    if x and y and z then
                        local r = Game.GetCharHeading(ped)
                        Events.CallRemote("rp_position_sync", { x, y, z, r })
                    end
                end
            end
        end
    end)
end)
