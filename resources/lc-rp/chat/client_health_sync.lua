-- chat/client_health_sync.lua
-- Monitors health and armour changes and reports them to the server via rp_health_sync.
-- Sends { hp, ap } (native 0-200 scale) at most once per second, and only when
-- a change is detected. Server validates the update (decreases accepted; increases
-- only accepted during a server-opened heal window).
-- Only runs after the player has selected a character.

local HEALTH_SYNC_INTERVAL_MS = 1000
local g_hasCharacter = false

Events.Subscribe("char_selected", function()
    g_hasCharacter = true
end)

-- L9: Reset g_hasCharacter on return to character selection.
Events.Subscribe("auth_success", function()
    g_hasCharacter = false
end)

-- Helper: get local player ped only when the ped actually exists.
local function getLocalPed()
    local playerId = Game.GetPlayerId()
    local idx = Game.ConvertIntToPlayerindex(playerId)
    local ok, ped = pcall(Game.GetPlayerChar, idx)
    if not ok then return nil end
    return ped
end

-- Apply server-authoritative health value sent via CharState.setHealth.
Events.Subscribe("char_set_health", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local hp = tonumber(payload[1])
    if not hp then return end
    local ped = getLocalPed()
    if ped then
        -- DB scale 0-100 -> native scale 0-200.
        Game.SetCharHealth(ped, math.floor(hp * ClientConfig.HEALTH_ARMOUR_MULTIPLIER))
    end
end, true)

-- Apply server-authoritative armour value sent via CharState.setArmour.
Events.Subscribe("char_set_armour", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local ap = tonumber(payload[1])
    if not ap then return end
    local ped = getLocalPed()
    if ped then
        local target = math.floor(ap * ClientConfig.HEALTH_ARMOUR_MULTIPLIER)
        local current = Game.GetCharArmour(ped)
        Game.AddArmourToChar(ped, target - current)
    end
end, true)

Events.Subscribe("scriptInit", function()
    Thread.Create(function()
        -- Cache player ID outside the loop — it never changes for the life of this script.
        local playerId = Game.GetPlayerId()
        local playerIdx = Game.ConvertIntToPlayerindex(playerId)
        local lastHp, lastAp

        while true do
            Thread.Pause(HEALTH_SYNC_INTERVAL_MS)
            if g_hasCharacter then
                local okPed, ped = pcall(Game.GetPlayerChar, playerIdx)
                if okPed and ped then
                    local okHp, hp = pcall(Game.GetCharHealth, ped)
                    local okAp, ap = pcall(Game.GetCharArmour, ped)
                    if not okHp or not okAp then goto skipSync end
                    -- Only sync when a value has changed.
                    if hp ~= lastHp or ap ~= lastAp then
                        lastHp, lastAp = hp, ap
                        Events.CallRemote("rp_health_sync", { hp, ap })
                    end
                end
                ::skipSync::
            end
        end
    end)
end)
