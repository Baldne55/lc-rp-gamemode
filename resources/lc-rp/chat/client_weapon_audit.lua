-- chat/client_weapon_audit.lua
-- Periodically scans for weapons the server didn't authorize (e.g. trainer-spawned).
-- If an unauthorized weapon is found, it is removed and reported to the server.
-- Also sends a periodic heartbeat so the server can detect if this script is suppressed.

local AUDIT_INTERVAL_MS   = 3000  -- scan every 3 seconds
local HEARTBEAT_INTERVAL  = 5     -- send heartbeat every N audit cycles (15s)

local g_hasCharacter    = false
local g_equippedWeapon  = nil   -- weaponTypeId authorized by server

-- All GTA IV weapon type IDs from the item registry.
local ALL_WEAPON_TYPES = { 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }

-- Weapon type ID to name mapping for violation reports.
local WEAPON_NAMES = {
    [1]  = "Baseball Bat",    [2]  = "Pool Cue",       [3]  = "Knife",
    [4]  = "Grenade",         [5]  = "Molotov",
    [7]  = "Pistol",          [8]  = "Silenced Pistol", [9]  = "Combat Pistol",
    [10] = "Combat Shotgun",  [11] = "Pump Shotgun",
    [12] = "Micro-SMG",       [13] = "SMG",
    [14] = "Assault Rifle",   [15] = "Carbine Rifle",
    [16] = "Combat Sniper",   [17] = "Sniper Rifle",
    [18] = "RPG",             [19] = "Flamethrower",   [20] = "Minigun",
}

Events.Subscribe("char_selected", function()
    g_hasCharacter  = true
    g_equippedWeapon = nil
end)

Events.Subscribe("auth_success", function()
    g_hasCharacter  = false
    g_equippedWeapon = nil
end)

Events.Subscribe("char_equip_weapon", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    g_equippedWeapon = tonumber(payload[1])
end, true)

Events.Subscribe("char_unequip_weapon", function()
    g_equippedWeapon = nil
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
        local cycleCount = 0
        while true do
            Thread.Pause(AUDIT_INTERVAL_MS)
            if not g_hasCharacter then goto continue end

            local ped = getLocalPed()
            if not ped then goto continue end

            -- Check all known weapon types for unauthorized possession.
            for _, weaponType in ipairs(ALL_WEAPON_TYPES) do
                if weaponType ~= g_equippedWeapon then
                    local ok, ammo = pcall(Game.GetAmmoInCharWeapon, ped, weaponType)
                    if ok and ammo and ammo > 0 then
                        -- Unauthorized weapon found — remove it and report.
                        pcall(Game.RemoveWeaponFromChar, ped, weaponType)
                        local name = WEAPON_NAMES[weaponType] or ("Type " .. weaponType)
                        Events.CallRemote("rp_weapon_violation", { weaponType, ammo, name })
                    end
                end
            end

            -- Periodic heartbeat so server can detect suppressed scanner.
            cycleCount = cycleCount + 1
            if cycleCount >= HEARTBEAT_INTERVAL then
                cycleCount = 0
                Events.CallRemote("rp_weapon_audit_heartbeat", {})
            end

            ::continue::
        end
    end)
end)
