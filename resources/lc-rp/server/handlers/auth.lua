-- handlers/auth.lua
-- Server-side authentication: login and registration.
--
-- Events (isRemoteAllowed = true, fired by client):
--   auth_login    { username, password, rgscId }
--   auth_register { username, password, rgscId }
--
-- Events fired back to specific client:
--   auth_result   { success (bool), message (string) }

-- In-memory brute-force protection: { [ip] = { count, resetAt } }
local failedAttempts = {}

local MAX_ATTEMPTS    = Config.AUTH.MAX_ATTEMPTS
local LOCKOUT_SECONDS = Config.AUTH.LOCKOUT_SECONDS
local USERNAME_MIN    = Config.AUTH.USERNAME_MIN
local USERNAME_MAX    = Config.AUTH.USERNAME_MAX
local PASSWORD_MIN    = Config.AUTH.PASSWORD_MIN
local PASSWORD_MAX    = Config.AUTH.PASSWORD_MAX

-- Returns true if the IP is under the rate limit.
local function checkRateLimit(ip)
    local entry = failedAttempts[ip]
    if not entry then return true end
    if os.time() > entry.resetAt then
        failedAttempts[ip] = nil
        return true
    end
    return entry.count < MAX_ATTEMPTS
end

local function recordFailedAttempt(ip)
    if not failedAttempts[ip] then
        failedAttempts[ip] = { count = 0, resetAt = os.time() + LOCKOUT_SECONDS }
    end
    failedAttempts[ip].count = failedAttempts[ip].count + 1
end

local function clearFailedAttempts(ip)
    failedAttempts[ip] = nil
end

-- Periodic sweep: remove expired entries every 5 minutes to prevent unbounded growth.
local SWEEP_INTERVAL_SEC = 300
local _lastSweepTime = os.time()

local function sweepExpiredAttempts()
    local now = os.time()
    if (now - _lastSweepTime) < SWEEP_INTERVAL_SEC then return end
    _lastSweepTime = now
    for ip, entry in pairs(failedAttempts) do
        if now > entry.resetAt then
            failedAttempts[ip] = nil
        end
    end
end

-- Validates a username string. Returns nil on success, error string on failure.
local function validateUsername(username)
    if type(username) ~= "string" then return "Invalid username." end
    if #username < USERNAME_MIN then return "Username must be at least " .. USERNAME_MIN .. " characters." end
    if #username > USERNAME_MAX then return "Username must be at most " .. USERNAME_MAX .. " characters." end
    if not username:match("^[%w_%-]+$") then return "Username may only contain letters, numbers, underscores, and hyphens." end
    return nil
end

-- Validates a password string. Returns nil on success, error string on failure.
local function validatePassword(password)
    if type(password) ~= "string" then return "Invalid password." end
    if #password < PASSWORD_MIN then return "Password must be at least " .. PASSWORD_MIN .. " characters." end
    if #password > PASSWORD_MAX then return "Password is too long." end
    return nil
end

local function now()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

-- LOGIN -----------------------------------------------------------------------

Events.Subscribe("auth_login", function(username, password, rgscId)
    local source = Events.GetSource()
    local ip     = Player.GetIP(source)

    sweepExpiredAttempts()

    -- Rate limit check.
    if not checkRateLimit(ip) then
        Events.CallRemote("auth_result", source, { false, "Too many failed attempts. Try again in 15 minutes." })
        return
    end

    local usernameErr = validateUsername(username)
    if usernameErr then
        Events.CallRemote("auth_result", source, { false, usernameErr })
        return
    end

    -- H1: Validate password type before DB lookup (prevents crash on nil password).
    local passwordErr = validatePassword(password)
    if passwordErr then
        Events.CallRemote("auth_result", source, { false, "Invalid username or password." })
        return
    end

    AccountModel.findOne({ account_username = username }, function(account)
        if not account then
            recordFailedAttempt(ip)
            Events.CallRemote("auth_result", source, { false, "Invalid username or password." })
            return
        end

        -- Verify password.
        if not Hash.verifyPassword(password, account.account_password_salt, account.account_password) then
            recordFailedAttempt(ip)
            Events.CallRemote("auth_result", source, { false, "Invalid username or password." })
            return
        end

        -- Check account status.
        if Config.AUTH.REQUIRE_VERIFICATION and account.account_status == "Unverified" then
            Events.CallRemote("auth_result", source, { false, "Your account is not yet verified." })
            return
        end

        if account.account_status == "Locked" then
            local until_date = account.account_locked_until_date or "indefinitely"
            Events.CallRemote("auth_result", source, { false, "Your account is locked until " .. until_date .. "." })
            return
        end

        -- C1: Atomic compare-and-swap to prevent duplicate login race condition.
        -- Only sets the flag if it's currently 0; check affectedRows to detect race.
        local updateData = {
            account_last_login_date    = now(),
            account_last_ip            = ip,
            account_is_logged_in_game  = 1,
        }
        if rgscId and rgscId ~= 0 then
            updateData.account_rgsc_id = tostring(rgscId)
        end
        if not account.account_first_login_date then
            updateData.account_first_login_date = now()
        end

        local setClause = ""
        local setParams = {}
        for col, val in pairs(updateData) do
            if #setClause > 0 then setClause = setClause .. ", " end
            setClause = setClause .. "`" .. col .. "` = ?"
            setParams[#setParams + 1] = val
        end
        setParams[#setParams + 1] = account.account_id

        DB.execute(
            "UPDATE `accounts` SET " .. setClause .. " WHERE `account_id` = ? AND `account_is_logged_in_game` = 0",
            setParams,
            function(affectedRows)
                if affectedRows == 0 then
                    Events.CallRemote("auth_result", source, { false, "This account is already logged in." })
                    return
                end

                clearFailedAttempts(ip)

                Players.set(source, {
                    accountId  = account.account_id,
                    username   = username,
                    staffLevel = account.account_staff_level or "None",
                })

                Log.info("Auth", username .. " (" .. source .. ") logged in.")
                Events.CallRemote("auth_result", source, { true, tostring(account.account_id) })
            end
        )
    end)
end, true)

-- REGISTER --------------------------------------------------------------------

Events.Subscribe("auth_register", function(username, password, rgscId)
    local source = Events.GetSource()
    local ip     = Player.GetIP(source)

    sweepExpiredAttempts()

    -- Rate limit check.
    if not checkRateLimit(ip) then
        Events.CallRemote("auth_result", source, { false, "Too many failed attempts. Try again in 15 minutes." })
        return
    end

    local usernameErr = validateUsername(username)
    if usernameErr then
        Events.CallRemote("auth_result", source, { false, usernameErr })
        return
    end

    local passwordErr = validatePassword(password)
    if passwordErr then
        Events.CallRemote("auth_result", source, { false, passwordErr })
        return
    end

    -- Pre-check username availability before doing any crypto work.
    AccountModel.findOne({ account_username = username }, function(existingUser)
        if existingUser then
            Events.CallRemote("auth_result", source, { false, "Username is already taken." })
            return
        end

        -- Pre-check RGSC ID uniqueness if one was provided.
        local function afterRgscCheck()
            local salt = Hash.generateSalt()
            local hash = Hash.hashPassword(password, salt)
            local ts   = now()

            local initialStatus = Config.AUTH.REQUIRE_VERIFICATION and "Unverified" or "Active"

            -- H3: Don't auto-log in if verification is required.
            local autoLogin = not Config.AUTH.REQUIRE_VERIFICATION

            local newAccount = {
                account_username             = username,
                account_password             = hash,
                account_password_salt        = salt,
                account_status               = initialStatus,
                account_registration_date    = ts,
                account_registration_ip      = ip,
                account_last_ip              = ip,
                account_is_logged_in_game    = autoLogin and 1 or 0,
                account_first_login_date     = ts,
                account_last_login_date      = ts,
            }

            if rgscId and rgscId ~= 0 then
                newAccount.account_rgsc_id = tostring(rgscId)
            end

            -- DB UNIQUE constraints remain as a safety net for race conditions.
            AccountModel.create(newAccount, function(accountId)
                if not accountId then
                    Events.CallRemote("auth_result", source, { false, "Registration failed. Please try again." })
                    return
                end

                if not autoLogin then
                    Log.info("Auth", "New account registered (unverified): " .. username .. " (id=" .. accountId .. ", ip=" .. ip .. ")")
                    Events.CallRemote("auth_result", source, { false, "Account created. Please verify your account before logging in." })
                    return
                end

                Log.info("Auth", "New account registered and auto-logged in: " .. username .. " (id=" .. accountId .. ", ip=" .. ip .. ")")

                Players.set(source, { accountId = accountId, username = username, staffLevel = "None" })

                Events.CallRemote("auth_result", source, { true, tostring(accountId) })
            end)
        end

        if rgscId and rgscId ~= 0 then
            AccountModel.findOne({ account_rgsc_id = tostring(rgscId) }, function(existingRgsc)
                if existingRgsc then
                    Events.CallRemote("auth_result", source, { false, "This Rockstar ID is already linked to an account." })
                    return
                end
                afterRgscCheck()
            end)
        else
            afterRgscCheck()
        end
    end)
end, true)

-- LOGOUT ----------------------------------------------------------------------
-- Called internally when a player disconnects to clear the in-game login flag.

function Auth_OnDisconnect(serverID)
    local data = Players.get(serverID)
    if not data then return end

    -- L16: Add callback to detect failed login flag clear.
    AccountModel.update(
        { account_is_logged_in_game = 0, account_last_logout_date = now() },
        { account_id = data.accountId },
        function(affectedRows)
            if affectedRows == 0 then
                Log.error("Auth", "Failed to clear login flag for account " .. tostring(data.accountId))
            end
        end
    )

    Events.BroadcastRemote("char_name_sync", { serverID, "" })
    Players.remove(serverID)
    Log.info("Auth", data.username .. " (" .. serverID .. ") session cleared.")
end
