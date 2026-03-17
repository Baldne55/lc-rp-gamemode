-- chat/client_ammo_sync.lua
-- Monitors ammo changes for equipped weapons and reports decreases to the server.
-- Server consumes ammo items from inventory and responds with the authoritative
-- ammo count. Only runs when a ranged weapon (has ammoGroup) is equipped.

local AMMO_SYNC_INTERVAL_MS = 500
local g_hasCharacter    = false
local g_equippedWeapon  = nil   -- weaponTypeId from char_equip_weapon
local g_lastAmmo        = nil   -- last known native ammo count (baseline)

Events.Subscribe("char_selected", function()
    g_hasCharacter   = true
    g_equippedWeapon = nil
    g_lastAmmo       = nil
end)

Events.Subscribe("auth_success", function()
    g_hasCharacter   = false
    g_equippedWeapon = nil
    g_lastAmmo       = nil
end)

-- Track equip/unequip to know which weapon to poll.
Events.Subscribe("char_equip_weapon", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local weaponType = tonumber(payload[1])
    local ammo       = tonumber(payload[2]) or 0
    if not weaponType then return end
    g_equippedWeapon = weaponType
    g_lastAmmo       = ammo
end, true)

Events.Subscribe("char_unequip_weapon", function()
    g_equippedWeapon = nil
    g_lastAmmo       = nil
end, true)

-- Server sends authoritative ammo count after consuming inventory ammo.
Events.Subscribe("char_ammo_updated", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local weaponType = tonumber(payload[1])
    local newAmmo    = tonumber(payload[2]) or 0

    if not weaponType or weaponType ~= g_equippedWeapon then return end

    g_lastAmmo = newAmmo

    local playerId  = Game.GetPlayerId()
    local playerIdx = Game.ConvertIntToPlayerindex(playerId)
    local ok, ped   = pcall(Game.GetPlayerChar, playerIdx)
    if ok and ped then
        Game.SetCharAmmo(ped, weaponType, newAmmo)
    end
end, true)

-- Helper: get local player ped.
local function getLocalPed()
    local playerId = Game.GetPlayerId()
    local idx = Game.ConvertIntToPlayerindex(playerId)
    local ok, ped = pcall(Game.GetPlayerChar, idx)
    if not ok then return nil end
    return ped
end

Events.Subscribe("scriptInit", function()
    Thread.Create(function()
        while true do
            Thread.Pause(AMMO_SYNC_INTERVAL_MS)
            if not g_hasCharacter then goto continue end
            if not g_equippedWeapon or not g_lastAmmo then goto continue end

            local ped = getLocalPed()
            if not ped then goto continue end

            local ok, currentAmmo = pcall(Game.GetAmmoInCharWeapon, ped, g_equippedWeapon)
            if not ok then goto continue end

            if currentAmmo < g_lastAmmo then
                -- Ammo decreased — report to server for inventory consumption.
                Events.CallRemote("rp_ammo_sync", { g_equippedWeapon, currentAmmo })
                g_lastAmmo = currentAmmo
            end

            ::continue::
        end
    end)
end)
