-- client/handlers/auth.lua
-- Manages the pre-login state: freeze player, cinematic camera, login WebUI.
--
-- Flow:
--   scriptInit  -> freeze player, hide HUD, start camera
--   sessionInit -> silent spawn (frozen/invisible), create login UI, wait for ready,
--                 then ForceLoadingScreen(false) / fade in
--   User submits form -> WebUI JS fires ui_login / ui_register
--   Client forwards to server via CallRemote
--   Server responds with auth_result { success, message }
--   On success -> destroy UI, restore camera, unfreeze player, fire local "auth_success"
--   On failure -> pass error message back to WebUI

local g_loginUI       = nil
local g_loginUIReady  = false   -- set true by webUIReady; sessionInit waits on this
local g_cam           = nil
local g_loggedIn      = false
local g_pendingUser   = nil   -- stored on submit, forwarded with auth_success

-- Auth (login): camera and player position when connecting.
local CAM_COORDS   = ClientConfig.AUTH.CAM_COORDS
local AUTH_COORDS  = ClientConfig.AUTH.SPAWN_COORDS
local AUTH_MODEL   = ClientConfig.AUTH.MODEL

-- Creates the scripted cinematic camera at the fixed position.
local function startCamera()
    g_cam = Game.CreateCam(14)  -- 14 = DEFAULT_SCRIPTED_CAMERA
    Game.SetCamActive(g_cam, true)

    local x, y, z = CAM_COORDS[1], CAM_COORDS[2], CAM_COORDS[3]
    Game.SetCamPos(g_cam, x, y, z)
end

-- Tears down the entire login state on successful authentication.
local function onLoginSuccess(accountId)
    g_loggedIn = true

    if g_loginUI ~= nil then
        WebUI.SetFocus(-1)
        WebUI.Destroy(g_loginUI)
        g_loginUI = nil
    end

    -- Hand the camera handle to the character handler; it owns teardown from here.
    local cam = g_cam
    g_cam = nil
    Console.Log("[Auth] auth_success firing (accountId=" .. tostring(accountId) .. ", user=" .. tostring(g_pendingUser) .. ")")
    Events.Call("auth_success", { tonumber(accountId), g_pendingUser, cam })
end

-- Event: scriptInit -----------------------------------------------------------
-- Freeze and hide the player immediately.
-- Camera is deferred to sessionInit when the world is loaded.

Events.Subscribe("scriptInit", function()
    PlayerUtil.setFrozen(true)
    Game.DisplayHud(false)
    Game.DisplayRadar(false)
end)

-- Event: sessionInit ----------------------------------------------------------
-- The engine won't dismiss the loading screen until the player model is loaded
-- and placed in the world. We do a silent spawn (player stays frozen + invisible)
-- so ForceLoadingScreen(false) actually takes effect.

Events.Subscribe("sessionInit", function()
    if g_loggedIn then return end

    -- Start camera from main context (Thread.Create cannot be nested).
    startCamera()

    Thread.Create(function()
        -- Create the login UI first so HTML loads while the spawn model is requested.
        g_loginUI = WebUI.CreateFullScreen("file://lc-rp/client/ui/login/index.html", true)

        local playerId   = Game.GetPlayerId()
        local spawnModel = Game.GetHashKey(AUTH_MODEL)

        Game.RequestModel(spawnModel)
        Game.LoadAllObjectsNow()
        local loadAttempts = 0
        while not Game.HasModelLoaded(spawnModel) do
            Game.RequestModel(spawnModel)
            loadAttempts = loadAttempts + 1
            if loadAttempts > 500 then break end
            Thread.Pause(0)
        end

        Game.ChangePlayerModel(playerId, spawnModel)
        Game.MarkModelAsNoLongerNeeded(spawnModel)

        Game.RequestCollisionAtPosn(AUTH_COORDS[1], AUTH_COORDS[2], AUTH_COORDS[3])
        Game.ResurrectNetworkPlayer(playerId, AUTH_COORDS[1], AUTH_COORDS[2], AUTH_COORDS[3], AUTH_COORDS[4])

        local playerChar = Game.GetPlayerChar(Game.ConvertIntToPlayerindex(playerId))
        Game.ClearCharTasksImmediately(playerChar)
        Game.SetCharHealth(playerChar, ClientConfig.AUTH.INITIAL_HEALTH)
        Game.RemoveAllCharWeapons(playerChar)
        Game.ClearWantedLevel(playerId)

        -- Re-apply frozen/invisible state since resurrection resets it.
        PlayerUtil.setFrozen(true)

        -- Wait for login UI HTML to finish loading before revealing the screen.
        while not g_loginUIReady do
            Thread.Pause(0)
        end

        Game.ForceLoadingScreen(false)
        Game.DoScreenFadeIn(500)
    end)
end)

-- Event: webUIReady -----------------------------------------------------------

Events.Subscribe("webUIReady", function(id)
    if id ~= g_loginUI then return end
    Console.Log("[Auth] webUIReady login UI id=" .. tostring(id))
    g_loginUIReady = true
    WebUI.SetFocus(g_loginUI)
end)

-- Events from login UI JS ----------------------------------------------------

Events.Subscribe("ui_login", function(username, password)
    -- Defensive: JS may pass [username, password] as unpacked or as single table
    if type(username) == "table" then
        username, password = username[1], username[2]
    end
    g_pendingUser = username
    local rgscId = Player.GetRockstarID()
    Events.CallRemote("auth_login", { username, password, rgscId })
end)

Events.Subscribe("ui_register", function(username, password)
    if type(username) == "table" then
        username, password = username[1], username[2]
    end
    g_pendingUser = username
    local rgscId = Player.GetRockstarID()
    Events.CallRemote("auth_register", { username, password, rgscId })
end)

-- Event: auth_result (from server) --------------------------------------------

Events.Subscribe("auth_result", function(success, message)
    if success then
        onLoginSuccess(message)  -- message carries the account_id on success
    else
        if g_loginUI ~= nil then
            WebUI.CallEvent(g_loginUI, "auth_error", { message })
        end
    end
end, true)  -- isRemoteAllowed: receive from server via Events.CallRemote
