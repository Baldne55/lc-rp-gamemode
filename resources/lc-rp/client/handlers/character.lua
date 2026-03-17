-- client/handlers/character.lua
-- Manages character selection and creation after authentication.
--
-- Flow:
--   auth_success -> show character UI
--   webUIReady   -> set focus, request char_list (page JS is ready to receive it)
--   User selects  -> ui_char_select  -> char_select remote
--   User creates  -> ui_char_create  -> char_create remote
--   char_result (success) -> teardown UI, unfreeze player, fire char_selected

local g_charUI   = nil
local g_cam      = nil
local g_playerId = nil
-- L2: Generation counter to cancel stale preview threads on rapid skin changes.
local g_previewGen = 0
local g_nametagsOff = false

-- Shared skin loading helper: loads a ped model and applies it to the player.
-- Must be called from within a Thread.Create context.
local function loadAndApplySkin(playerId, skinName)
    local skinToUse = (type(skinName) == "string" and skinName ~= "") and skinName or ClientConfig.AUTH.MODEL
    local skinHash = Game.GetHashKey(skinToUse)
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local playerChar  = Game.GetPlayerChar(playerIndex)

    if not Game.IsModelInCdimage(skinHash) then return playerChar, skinHash end

    if not Game.IsCharModel(playerChar, skinHash) then
        Game.RequestModel(skinHash)
        Game.LoadAllObjectsNow()
        -- L3: Timeout to prevent infinite loop on model load failure.
        local attempts = 0
        while not Game.HasModelLoaded(skinHash) do
            Game.RequestModel(skinHash)
            attempts = attempts + 1
            if attempts > 500 then return playerChar, skinHash end
            Thread.Pause(0)
        end
        Game.ChangePlayerModel(playerId, skinHash)
        Game.MarkModelAsNoLongerNeeded(skinHash)
        playerChar = Game.GetPlayerChar(playerIndex)
    end

    return playerChar, skinHash
end

-- Event: auth_success ---------------------------------------------------------

Events.Subscribe("auth_success", function(accountId, username, camHandle)
    Console.Log("[Char] auth_success received (accountId=" .. tostring(accountId) .. ", user=" .. tostring(username) .. ")")
    g_cam      = camHandle
    g_playerId = Game.GetPlayerId()
    g_charUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/character/index.html", true)
end)

-- Event: webUIReady -----------------------------------------------------------
-- Request char_list here, not in auth_success, so the page's event handlers
-- are guaranteed to be registered before the server response arrives.

Events.Subscribe("webUIReady", function(id)
    if id ~= g_charUI then return end
    Console.Log("[Char] webUIReady character UI id=" .. tostring(id) .. ", requesting char_list")
    WebUI.SetFocus(g_charUI)
    Events.CallRemote("char_list", {})
end)

-- Event: char_list_result (from server) ---------------------------------------

Events.Subscribe("char_list_result", function(chars, maxSlots)
    Console.Log("[Char] char_list_result received (chars=" .. (chars and #chars or 0) .. ", maxSlots=" .. tostring(maxSlots) .. ")")
    if g_charUI == nil then return end
    WebUI.CallEvent(g_charUI, "char_list", { chars, maxSlots })
end, true)

-- Events from character UI JS -------------------------------------------------

Events.Subscribe("ui_char_select", function(characterId)
    if type(characterId) == "table" then
        characterId = characterId[1]
    end
    Events.CallRemote("char_select", { characterId })
end)

-- Event: ui_char_preview (from character UI) ----------------------------------
-- Live preview during character creation step 2: show player with selected skin/appearance.

Events.Subscribe("ui_char_preview", function(skin, appearance)
    if g_playerId == nil then return end
    if type(skin) == "table" then
        skin, appearance = skin[1], skin[2]
    end

    -- L2: Increment generation to cancel any previous preview thread.
    g_previewGen = g_previewGen + 1
    local myGen = g_previewGen

    Thread.Create(function()
        local playerIndex = Game.ConvertIntToPlayerindex(g_playerId)
        local playerChar  = Game.GetPlayerChar(playerIndex)
        if skin == nil then return end

        -- Load the skin model so it's ready for spawn, but keep the ped invisible.
        -- ChangePlayerModel resets visibility, so re-hide immediately after.
        -- The character only becomes visible after char_result via PlayerUtil.restore().
        loadAndApplySkin(g_playerId, skin)
        if myGen ~= g_previewGen then return end

        -- ChangePlayerModel resets all ped state, so re-apply frozen + invisible.
        local playerIndex2 = Game.ConvertIntToPlayerindex(g_playerId)
        playerChar = Game.GetPlayerChar(playerIndex2)
        PlayerUtil.setFrozen(true)

        if appearance and type(appearance) == "table" then
            Appearance.apply(playerChar, appearance)
        end
    end)
end)

-- Event: ui_char_get_component_bounds (from character UI) ---------------------

Events.Subscribe("ui_char_get_component_bounds", function()
    if g_charUI == nil or g_playerId == nil then return end
    local playerIndex = Game.ConvertIntToPlayerindex(g_playerId)
    local playerChar  = Game.GetPlayerChar(playerIndex)
    local bounds = {}
    for componentId = 0, (ClientConfig.COMPONENT_COUNT - 1) do
        local key = tostring(componentId)
        local ok, drawableCount = pcall(function()
            return Game.GetNumberOfCharDrawableVariations(playerChar, componentId) or 0
        end)
        if not ok or not drawableCount or drawableCount < 1 then
            bounds[key] = { drawableMax = 0, textureMaxes = { 0 } }
        else
            local drawableMax = math.max(0, drawableCount - 1)
            local textureMaxes = {}
            for d = 0, drawableMax do
                local ok2, texCount = pcall(function()
                    return Game.GetNumberOfCharTextureVariations(playerChar, componentId, d) or 0
                end)
                textureMaxes[d + 1] = math.max(0, (ok2 and texCount and texCount > 0) and (texCount - 1) or 0)
            end
            bounds[key] = { drawableMax = drawableMax, textureMaxes = textureMaxes }
        end
    end
    WebUI.CallEvent(g_charUI, "char_component_bounds", { bounds })
end)

Events.Subscribe("ui_char_create", function(firstName, lastName, birthDate, gender, bloodType, skin, appearance)
    if type(firstName) == "table" then
        local t = firstName
        firstName  = t[1]
        lastName   = t[2]
        birthDate  = t[3]
        gender     = t[4]
        bloodType  = t[5]
        skin       = t[6]
        appearance = t[7]
    end
    Events.CallRemote("char_create", { firstName, lastName, birthDate, gender, bloodType, skin, appearance })
end)

-- Event: char_result (from server) --------------------------------------------

Events.Subscribe("char_result", function(success, data)
    if not success then
        if g_charUI ~= nil then
            WebUI.CallEvent(g_charUI, "char_error", { data })
        end
        return
    end

    -- Teardown character UI (guard against double-fire).
    if g_charUI ~= nil then
        WebUI.SetFocus(-1)
        WebUI.Destroy(g_charUI)
        g_charUI = nil
    end

    -- Stop cinematic camera.
    if g_cam ~= nil then
        Game.SetCamActive(g_cam, false)
        Game.DestroyCam(g_cam)
        g_cam = nil
    end
    Game.CamRestoreJumpcut()

    -- Spawn, skin loading, and appearance all use Thread.Pause(0) so must run in a thread.
    Thread.Create(function()
        local playerIndex = Game.ConvertIntToPlayerindex(g_playerId)

        -- L5: Skip pre-resurrect skin load since ResurrectNetworkPlayer resets the model.
        local skinToUse = (data.skin and data.skin ~= "") and data.skin or (data.gender == "Female" and "F_Y_MULTIPLAYER" or "M_Y_MULTIPLAYER")

        local sd = ClientConfig.SPAWN_DEFAULT
        local x = tonumber(data.x) or sd.x
        local y = tonumber(data.y) or sd.y
        local z = tonumber(data.z) or sd.z
        local r = tonumber(data.r) or sd.r
        Game.RequestCollisionAtPosn(x, y, z)
        Game.ResurrectNetworkPlayer(g_playerId, x, y, z, r)
        local playerChar = Game.GetPlayerChar(playerIndex)

        -- Apply skin after resurrect.
        local _, skinHash = loadAndApplySkin(g_playerId, skinToUse)
        playerChar = Game.GetPlayerChar(playerIndex)

        -- Apply clothing components from appearance data.
        Appearance.apply(playerChar, data.appearance)

        -- Health and armour are applied by char_set_health / char_set_armour events
        -- fired by the server via CharState.setHealth / CharState.setArmour.

        PlayerUtil.restore()

        -- Enable per-frame nametag and walk-mode suppression (see scriptInit loop below).
        g_nametagsOff = true

        -- Make all player names white (HUD_COLOUR_NET_PLAYER1-32).
        local hudMin, hudMax = ClientConfig.HUD_COLOUR_RANGE[1], ClientConfig.HUD_COLOUR_RANGE[2]
        for i = hudMin, hudMax do
            Game.ReplaceHudColourWithRgba(i, 255, 255, 255, 255)
        end

        Events.Call("char_selected", { data })
    end)
end, true)

-- ── Weapon equip/unequip (from server inventory commands) ──────────────────

Events.Subscribe("char_equip_weapon", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local weaponType = tonumber(payload[1])
    local ammo       = tonumber(payload[2]) or 1
    if not weaponType then return end

    local playerId    = Game.GetPlayerId()
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local ped         = Game.GetPlayerChar(playerIndex)
    if not ped then return end

    Game.GiveWeaponToChar(ped, weaponType, ammo, true)
end, true)

Events.Subscribe("char_unequip_weapon", function(...)
    local args = {...}
    local payload = type(args[1]) == "table" and args[1] or args
    local weaponType = tonumber(payload[1])
    if not weaponType then return end

    local playerId    = Game.GetPlayerId()
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local ped         = Game.GetPlayerChar(playerIndex)
    if not ped then return end

    -- Read remaining ammo before removing the weapon so the server can return it to inventory.
    local ok, currentAmmo = pcall(Game.GetAmmoInCharWeapon, ped, weaponType)
    local ammo = (ok and currentAmmo) or 0

    Game.RemoveWeaponFromChar(ped, weaponType)

    Events.CallRemote("rp_ammo_return", { weaponType, ammo })
end, true)

-- ── Nametag & walk-mode suppression loop ────────────────────────────────────
-- GTA IV re-enables nametags and network walk mode when players stream in,
-- so we must suppress them every frame to keep them off.

Events.Subscribe("auth_success", function()
    g_nametagsOff = false
end)

Events.Subscribe("scriptInit", function()
    -- Prevent dead players from dropping weapons or money on death.
    Game.SetDeadPedsDropWeapons(false)
    Game.SetPlayersDropMoneyInNetworkGame(false)

    Thread.Create(function()
        while true do
            if g_nametagsOff then
                Game.DisplayPlayerNames(false)
                Game.DisableNetworkWalkMode(true, true)
                for i = 0, 31 do
                    Game.SetDisplayPlayerNameAndIcon(i, false)
                end
                Thread.Pause(0)
            else
                Thread.Pause(200)
            end
        end
    end)
end)
