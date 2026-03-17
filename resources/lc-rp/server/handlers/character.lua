-- server/handlers/character.lua
-- Character listing, selection, and creation.
--
-- Remote events (client -> server):
--   char_list   {}                                          -> char_list_result { chars[], maxSlots }
--   char_select { characterId }                             -> char_result { true, charData } | { false, msg }
--   char_create { firstName, lastName, birthDate, gender, bloodType }
--                                                           -> char_result { true, charData } | { false, msg }

local VALID_BLOOD_TYPES = {
    ["A+"] = true, ["A-"] = true,
    ["B+"] = true, ["B-"] = true,
    ["AB+"] = true, ["AB-"] = true,
    ["O+"] = true, ["O-"] = true,
}

local function now()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

-- Generates a random N-character uppercase alphanumeric ID.
local CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local function randomId(len)
    local t = {}
    for i = 1, len do
        local idx = math.random(1, #CHARSET)
        t[i] = CHARSET:sub(idx, idx)
    end
    return table.concat(t)
end

-- Generates a random SSN in XXX-XX-XXXX format.
local function randomSSN()
    local function rdig(n)
        local t = {}
        for i = 1, n do t[i] = tostring(math.random(0, 9)) end
        return table.concat(t)
    end
    return rdig(3) .. "-" .. rdig(2) .. "-" .. rdig(4)
end

-- Generates a random 9-digit numeric routing number (e.g. "482031597").
local function randomRoutingNumber()
    local t = {}
    for i = 1, 9 do t[i] = tostring(math.random(0, 9)) end
    return table.concat(t)
end

-- Creates the default checking and savings bank accounts for a new character.
-- Retries with a new routing number on uniqueness collision (up to 5 attempts).
local function createDefaultBankAccounts(charId, callback)
    local function createAccount(ownerType, ownerId, accountType, balance, requiredLevel, attempt, cb)
        if attempt > 5 then
            Log.error("Bank", "Failed to generate unique routing number after 5 attempts for " .. ownerType .. " " .. ownerId)
            cb(nil)
            return
        end
        BankAccountModel.create({
            bank_account_owner_type     = ownerType,
            bank_account_owner_id       = ownerId,
            bank_account_type           = accountType,
            bank_account_balance        = balance,
            bank_account_routing_number = randomRoutingNumber(),
            bank_account_required_level = requiredLevel,
        }, function(accountId)
            if not accountId then
                createAccount(ownerType, ownerId, accountType, balance, requiredLevel, attempt + 1, cb)
                return
            end
            -- Record the initial deposit transaction.
            BankTransactionModel.create({
                bank_transaction_account_id    = accountId,
                bank_transaction_type          = "deposit",
                bank_transaction_amount        = balance,
                bank_transaction_balance_after = balance,
                bank_transaction_description   = "Opening balance",
            }, function()
                cb(accountId)
            end)
        end)
    end

    createAccount("character", charId, "checking", 15000, 0, 1, function(checkingId)
        createAccount("character", charId, "savings", 135000, 5, 1, function(savingsId)
            if callback then callback(checkingId, savingsId) end
        end)
    end)
end

-- Returns the age in years from a YYYY-MM-DD birth date string, or nil on bad input.
-- Age is relative to Config.SERVER_YEAR (in-universe year), not the real-world year.
-- Uses os.time round-trip to validate actual calendar dates (rejects Feb 31, etc.).
local function calcAge(birthDate)
    local y, m, d = birthDate:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    -- Validate day against month (no os.time — fails on Windows for pre-1970 dates).
    local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0) then daysInMonth[2] = 29 end
    if d > daysInMonth[m] then return nil end
    local t = os.date("*t")
    local age = Config.SERVER_YEAR - y
    if t.month < m or (t.month == m and t.day < d) then age = age - 1 end
    return age
end

-- Validates appearance JSON/table. Returns validated table or nil, or error string on invalid input.
-- Valid: nil/empty (no overrides), or table with keys "0"-"10" and values {drawable, texture} (0-255).
local function validateAppearance(appearance)
    if appearance == nil then return nil end
    if type(appearance) == "string" and #appearance == 0 then return nil end
    local t = appearance
    if type(appearance) == "string" then
        local ok, decoded = pcall(function() return JSON.decode(appearance) end)
        if not ok or type(decoded) ~= "table" then return "Invalid appearance data." end
        t = decoded
    end
    if type(t) ~= "table" then return "Invalid appearance data." end
    local validated = {}
    for i = 0, 10 do
        local k = tostring(i)
        local v = t[k] or t[i]
        if v ~= nil then
            if type(v) ~= "table" then return "Invalid appearance: component " .. k .. " must be [drawable, texture]." end
            local d   = tonumber(v[1])
            local tex = tonumber(v[2])
            if d == nil or tex == nil then return "Invalid appearance: component " .. k .. " must be [drawable, texture]." end
            if d < 0 or tex < 0 or d > 255 or tex > 255 then
                return "Invalid appearance: component " .. k .. " drawable/texture must be 0-255."
            end
            validated[k] = { math.floor(d), math.floor(tex) }
        end
    end
    return validated
end

-- Validates a character name component (first or last). Returns error string or nil.
local function validateName(value, label)
    if type(value) ~= "string" then return label .. " is required." end
    local trimmed = value:match("^%s*(.-)%s*$")
    if #trimmed < 2 then return label .. " must be at least 2 characters." end
    if #trimmed > 32 then return label .. " must be at most 32 characters." end
    if not trimmed:match("^[%a][%a%s%-%']*$") then
        return label .. " may only contain letters, spaces, hyphens, and apostrophes."
    end
    return nil
end

-- Builds the minimal spawn-relevant data table sent back to the client.
-- Position and world are normalized to numbers so they are always applied on spawn.
-- Uses getCol so we read columns regardless of DB driver key casing.
local function getCol(row, colName)
    if not row or type(row) ~= "table" then return nil end
    if row[colName] ~= nil then return row[colName] end
    local lower = string.lower(colName)
    for k, v in pairs(row) do
        if type(k) == "string" and string.lower(k) == lower then return v end
    end
    return nil
end
local function charSpawnData(c)
    local sd = Config.SPAWN_DEFAULT
    local x = tonumber(getCol(c, "character_position_x")) or sd.x
    local y = tonumber(getCol(c, "character_position_y")) or sd.y
    local z = tonumber(getCol(c, "character_position_z")) or sd.z
    local r = tonumber(getCol(c, "character_position_r")) or sd.r
    local world = tonumber(getCol(c, "character_world"))
    if world == nil then world = 0 end
    local hp = tonumber(getCol(c, "character_hp")) or 100
    return {
        id          = c.character_id,
        firstName   = c.character_first_name,
        lastName    = c.character_last_name,
        gender      = c.character_gender,
        skin        = c.character_skin,
        appearance  = c.character_appearance,
        world       = world,
        x           = x,
        y           = y,
        z           = z,
        r           = r,
        hp          = hp,
    }
end

-- Sets authoritative health/armour on the server and notifies the client.
-- Stores the DB-scale values as dbHp/dbAp in Players cache as a fallback for
-- disconnect saves when no damage/heal has occurred during the session.
local function applyCharHealth(source, char)
    local hp = math.max(0, math.min(100, math.floor(tonumber(getCol(char, "character_hp")) or 100)))
    local ap = math.max(0, math.min(100, math.floor(tonumber(getCol(char, "character_ap")) or 0)))
    Players.set(source, { dbHp = hp, dbAp = ap })
    if hp > 50 then
        CharState.setHealth(source, hp)
    end
    CharState.setArmour(source, ap)
end

-- char_list -------------------------------------------------------------------

Events.Subscribe("char_list", function()
    local source = Events.GetSource()
    if not Guard.requireAuth(source) then return end

    local accountId = Players.get(source).accountId

    CharacterModel.findAll({ character_account_id = accountId }, function(chars)
        AccountModel.findOne({ account_id = accountId }, function(account)
            local maxSlots = account and account.account_max_characters or 3

            local list = {}
            for _, c in ipairs(chars) do
                list[#list + 1] = {
                    id        = c.character_id,
                    slot      = c.character_slot_id,
                    firstName = c.character_first_name,
                    lastName  = c.character_last_name,
                    gender    = c.character_gender,
                    birthDate = c.character_birth_date,
                    lastLogin = c.character_last_login_date,
                    status    = c.character_status,
                }
            end

            Events.CallRemote("char_list_result", source, { list, maxSlots })
        end)
    end)
end, true)

-- char_select -----------------------------------------------------------------

Events.Subscribe("char_select", function(characterId)
    local source = Events.GetSource()
    if not Guard.requireAuth(source) then return end

    local playerData = Players.get(source)
    local accountId = playerData.accountId

    -- C3: Clear old character's login flag if switching characters.
    local oldCharId = playerData.charId
    if oldCharId then
        CharacterModel.update({ character_is_logged_in_game = 0 }, { character_id = oldCharId })
        Inventory.unloadForCharacter(oldCharId)
        Players.set(source, { charId = nil })
    end

    -- Verify ownership in the WHERE clause.
    CharacterModel.findOne({ character_id = characterId, character_account_id = accountId }, function(char)
        if not char then
            Events.CallRemote("char_result", source, { false, "Character not found." })
            return
        end

        if char.character_status == "Locked" then
            Events.CallRemote("char_result", source, { false, "This character is locked." })
            return
        end

        if char.character_is_logged_in_game == 1 then
            Events.CallRemote("char_result", source, { false, "This character is already in use." })
            return
        end

        -- Atomically set login flag; reject if already set (race condition guard).
        DB.execute(
            "UPDATE `characters` SET `character_is_logged_in_game` = 1, `character_last_login_date` = ? " ..
            "WHERE `character_id` = ? AND `character_is_logged_in_game` = 0",
            { now(), characterId },
            function(affectedRows)
                if affectedRows == 0 then
                    Events.CallRemote("char_result", source, { false, "This character is already in use." })
                    return
                end

                local spawnData = charSpawnData(char)
                local useInvUI = tonumber(char.character_use_inventory_ui) == 1
                local showMoneyHud = tonumber(char.character_show_money_hud) ~= 0
                local useUINotifications = tonumber(char.character_use_ui_notifications) == 1
                local chatFontSize = tonumber(char.character_chat_font_size) or 0
                local chatPageSize = tonumber(char.character_chat_page_size) or 0
                Players.set(source, {
                    charId = characterId, loginTime = os.time(),
                    charLevel = tonumber(char.character_level) or 1,
                    useInventoryUI = useInvUI,
                    showMoneyHud = showMoneyHud,
                    useUINotifications = useUINotifications,
                    chatFontSize = chatFontSize,
                    chatPageSize = chatPageSize,
                })
                local fullName = (char.character_first_name or "") .. " " .. (char.character_last_name or "")
                Player.SetName(source, fullName)
                local pdata = Players.get(source)
                Log.info("Char", (pdata and pdata.username or tostring(source)) .. " (" .. source .. ") selected character " .. characterId .. ".")

                -- Send char_result before changing session; a session switch can drop
                -- events in-flight when joinsolosession is enabled.
                Events.CallRemote("char_result", source, { true, spawnData })
                ServerCmd.sendHints(source)
                Player.SetSession(source, (tonumber(getCol(char, "character_world")) or 0))

                -- Set position server-authoritatively and suppress teleport detection window.
                pcall(Player.SetPosition, source, spawnData.x, spawnData.y, spawnData.z)
                Chat.setJustSpawned(source)

                -- Push authoritative health/armour to client via CharState.
                applyCharHealth(source, char)

                -- Load inventory into cache, then sync nearby dropped items to client.
                Inventory.loadForCharacter(characterId, function()
                    Inventory.syncDropsForPlayer(source)
                end)

                -- Load faction/company memberships into Players cache.
                Org.loadMemberData(source, characterId, function()
                    Log.info("Char", "Loaded org memberships for character " .. characterId)
                end)

                -- Send saved inventory UI preference to client.
                if useInvUI then
                    Events.CallRemote("inv_ui_toggle", source, { true })
                end

                -- Send saved UI notifications preference to client.
                if useUINotifications then
                    Events.CallRemote("notify_ui_toggle", source, { true })
                end

                -- Send saved chat preferences to client.
                Events.CallRemote("chat_prefs_restore", source, { chatFontSize, chatPageSize })

                -- Push money HUD preference and initial values.
                if not showMoneyHud then
                    Events.CallRemote("hud_money_toggle", source, { false })
                end
                CharState.syncMoneyHud(source)
            end
        )
    end)
end, true)

-- chat_prefs_save -------------------------------------------------------------
-- Client sends { fontSize, pageSize } when the player changes chat settings.

Events.Subscribe("chat_prefs_save", function(payload)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end

    if type(payload) == "table" and type(payload[1]) == "table" then payload = payload[1] end
    if type(payload) ~= "table" then return end

    local fontSize = tonumber(payload[1]) or 0
    local pageSize = tonumber(payload[2]) or 0

    -- Clamp to valid ranges (0 = default/unchanged)
    if fontSize ~= 0 and (fontSize < 12 or fontSize > 24) then return end
    if pageSize ~= 0 and (pageSize < 10 or pageSize > 30) then return end

    data.chatFontSize = fontSize
    data.chatPageSize = pageSize
    CharacterModel.update({
        character_chat_font_size = fontSize,
        character_chat_page_size = pageSize,
    }, { character_id = data.charId })
end, true)

-- Char_OnDisconnect -----------------------------------------------------------
-- Persists character from a snapshot only. Called with data copied before the
-- player was removed from cache; does not use Players or Player API.

function Char_OnDisconnect(snapshot)
    if not snapshot or not snapshot.charId then return end

    local function doUpdate(char)
        local update = {
            character_is_logged_in_game = 0,
            character_last_logout_date = now(),
            character_world = snapshot.session or 0,
        }
        if snapshot.posX ~= nil and snapshot.posY ~= nil and snapshot.posZ ~= nil then
            update.character_position_x = snapshot.posX
            update.character_position_y = snapshot.posY
            update.character_position_z = snapshot.posZ
        end
        if snapshot.posR ~= nil then
            -- Heading is client-reported; clamp to valid range.
            update.character_position_r = math.max(0, math.min(360, snapshot.posR))
        end
        -- Health/armour priority: authHp (server-set, 0-100) > syncHp (validated client delta, native 0-200) > dbHp (loaded at spawn).
        local hp = snapshot.authHp
        if hp == nil and snapshot.syncHp ~= nil then
            hp = math.floor(snapshot.syncHp / 2)
        end
        if hp ~= nil then
            hp = math.max(0, math.min(100, math.floor(hp)))
            update.character_hp = hp
        elseif snapshot.dbHp ~= nil then
            -- No hp changes during session; keep the value that was loaded at spawn.
            local fallbackHp = math.max(0, math.min(100, math.floor(snapshot.dbHp)))
            update.character_hp = fallbackHp
        end
        local ap = snapshot.authAp
        if ap == nil and snapshot.syncAp ~= nil then
            ap = math.floor(snapshot.syncAp / 2)
        end
        if ap ~= nil then
            update.character_ap = math.max(0, math.min(100, math.floor(ap)))
        elseif snapshot.dbAp ~= nil then
            update.character_ap = math.max(0, math.min(100, math.floor(snapshot.dbAp)))
        end
        if snapshot.loginTime then
            local sessionMinutes = math.floor((os.time() - snapshot.loginTime) / 60)
            local totalMinutes = (char.character_playtime_minutes or 0) + sessionMinutes
            local hoursToAdd = math.floor(totalMinutes / 60)
            update.character_playtime_minutes = totalMinutes % 60
            update.character_playtime_hours = (char.character_playtime_hours or 0) + hoursToAdd
        end

        CharacterModel.update(update, { character_id = snapshot.charId })
    end

    CharacterModel.findOne({ character_id = snapshot.charId }, function(char)
        if char then
            doUpdate(char)
        else
            doUpdate({
                character_playtime_minutes = 0,
                character_playtime_hours = 0,
            })
        end
    end)
end

-- char_create -----------------------------------------------------------------

local _creatingChar = {}

-- H7: Clear creation lock on disconnect so reused serverIDs aren't blocked.
function Char_ClearCreatingFlag(serverID)
    _creatingChar[serverID] = nil
end

Events.Subscribe("char_create", function(firstName, lastName, birthDate, gender, bloodType, skin, appearance)
    -- Defensive: remote may pass table as first arg (framework-dependent)
    if type(firstName) == "table" then
        local t = firstName
        firstName = t[1]
        lastName  = t[2]
        birthDate = t[3]
        gender    = t[4]
        bloodType = t[5]
        skin      = t[6]
        appearance = t[7]
    end

    local source = Events.GetSource()
    if not Guard.requireAuth(source) then return end

    -- Prevent concurrent character creation for the same player.
    if _creatingChar[source] then
        Events.CallRemote("char_result", source, { false, "Character creation already in progress." })
        return
    end
    _creatingChar[source] = true

    local playerData = Players.get(source)
    local accountId  = playerData.accountId
    local ip         = Player.GetIP(source)

    -- C3: Clear old character's login flag if switching during creation.
    local oldCharId = playerData.charId
    if oldCharId then
        CharacterModel.update({ character_is_logged_in_game = 0 }, { character_id = oldCharId })
        Inventory.unloadForCharacter(oldCharId)
        Players.set(source, { charId = nil })
    end

    local function rejectCreate(msg)
        _creatingChar[source] = nil
        Events.CallRemote("char_result", source, { false, msg })
    end

    -- Field validation.
    local err = validateName(firstName, "First name") or validateName(lastName, "Last name")
    if err then rejectCreate(err) return end

    if gender ~= "Male" and gender ~= "Female" then
        rejectCreate("Invalid gender.") return
    end

    if not VALID_BLOOD_TYPES[bloodType] then
        rejectCreate("Invalid blood type.") return
    end

    local skinToUse
    skin = (skin and type(skin) == "string") and skin or nil
    if skin and #skin > 0 then
        if not Peds.isValidSkin(skin, gender) then
            rejectCreate("Invalid appearance. Please select a valid skin.") return
        end
        skinToUse = skin
    else
        skinToUse = gender == "Male" and "M_Y_MULTIPLAYER" or "F_Y_MULTIPLAYER"
    end

    local age = calcAge(birthDate)
    if not age then
        rejectCreate("Invalid date of birth. Use YYYY-MM-DD format.") return
    end
    if age < Config.CHARACTER_AGE_MIN then
        rejectCreate("Character must be at least " .. Config.CHARACTER_AGE_MIN .. " years old.") return
    end
    if age > Config.CHARACTER_AGE_MAX then
        rejectCreate("Character must be no older than " .. Config.CHARACTER_AGE_MAX .. " years.") return
    end

    local appearanceToStore = nil
    if appearance ~= nil and (type(appearance) == "table" or (type(appearance) == "string" and #appearance > 0)) then
        local validated = validateAppearance(appearance)
        if type(validated) == "string" then
            rejectCreate(validated) return
        end
        if validated and next(validated) then
            appearanceToStore = JSON.encode(validated)
        end
    end

    -- Check for duplicate character name (case-insensitive, global).
    local trimFirst = firstName:match("^%s*(.-)%s*$"):lower()
    local trimLast  = lastName:match("^%s*(.-)%s*$"):lower()

    DB.select(
        "SELECT `character_id` FROM `characters` " ..
        "WHERE LOWER(`character_first_name`) = ? AND LOWER(`character_last_name`) = ? LIMIT 1",
        { trimFirst, trimLast },
        function(rows)
            if rows and #rows > 0 then
                rejectCreate("A character with this name already exists.")
                return
            end

    -- Check account character limit.
    CharacterModel.findAll({ character_account_id = accountId }, function(chars)
        AccountModel.findOne({ account_id = accountId }, function(account)
            local maxSlots = account and account.account_max_characters or 3

            if #chars >= maxSlots then
                rejectCreate("You have reached your character slot limit.")
                return
            end

            -- Find first available 0-based slot (gap-filling; resilient to deletions).
            local usedSlots = {}
            for _, c in ipairs(chars) do
                usedSlots[c.character_slot_id] = true
            end
            local slot = 0
            while usedSlots[slot] do
                slot = slot + 1
            end

            local sd = Config.SPAWN_DEFAULT

            local newChar = {
                character_account_id          = accountId,
                character_slot_id             = slot,
                character_mask_id             = randomId(10),
                character_dna_id              = randomId(10),
                character_fingerprint_id      = randomId(10),
                character_ssn_id              = randomSSN(),
                character_status              = "Active",
                character_is_logged_in_game   = 1,
                character_first_name          = firstName:match("^%s*(.-)%s*$"),
                character_last_name           = lastName:match("^%s*(.-)%s*$"),
                character_birth_date          = birthDate,
                character_gender              = gender,
                character_blood_type          = bloodType,
                character_skin                = skinToUse,
                character_appearance          = appearanceToStore,
                character_creation_ip         = ip,
                character_last_login_date     = now(),
                character_position_x          = sd.x,
                character_position_y          = sd.y,
                character_position_z          = sd.z,
                character_position_r          = sd.r,
            }

            -- M14: Retry character creation on uniqueness collision (random ID clash).
            local MAX_CREATE_RETRIES = 5
            local function onCreateSuccess(charId)
                Players.set(source, { charId = charId, loginTime = os.time(), charLevel = 1, showMoneyHud = true, useUINotifications = false })
                Log.info("Char", playerData.username .. " (" .. source .. ") created character " .. charId .. " (" .. firstName .. " " .. lastName .. ").")

                -- Create default bank accounts (checking + savings).
                createDefaultBankAccounts(charId, function(checkingId, savingsId)
                    if checkingId then Log.info("Bank", "Checking account created (id=" .. checkingId .. ") for character " .. charId) end
                    if savingsId  then Log.info("Bank", "Savings account created (id=" .. savingsId .. ") for character " .. charId) end

                    -- Query the created row to get all defaults populated.
                    CharacterModel.findOne({ character_id = charId }, function(char)
                        _creatingChar[source] = nil
                        if not char then
                            Log.error("Char", "Failed to read back character " .. charId .. " after creation.")
                            Events.CallRemote("char_result", source, { false, "Character creation failed. Please try again." })
                            return
                        end

                        local fullName = (char.character_first_name or "") .. " " .. (char.character_last_name or "")
                        Player.SetName(source, fullName)

                        local spawnData = charSpawnData(char)
                        -- Send char_result before changing session; a session switch can drop
                        -- events in-flight when joinsolosession is enabled.
                        Events.CallRemote("char_result", source, { true, spawnData })
                        ServerCmd.sendHints(source)
                        Player.SetSession(source, (tonumber(getCol(char, "character_world")) or 0))

                        -- Set position server-authoritatively and suppress teleport detection window.
                        pcall(Player.SetPosition, source, spawnData.x, spawnData.y, spawnData.z)
                        Chat.setJustSpawned(source)

                        -- Push authoritative health/armour to client via CharState.
                        applyCharHealth(source, char)

                        -- Load inventory into cache, then sync drops to client.
                        Inventory.loadForCharacter(charId, function()
                            Inventory.syncDropsForPlayer(source)
                        end)

                        -- Initialize empty org memberships for new character.
                        Players.set(source, { factions = {}, companies = {} })

                        -- Push initial cash + bank balance to HUD.
                        CharState.syncMoneyHud(source)
                    end)
                end)
            end

            local function attemptCreate(attempt)
                if attempt > 1 then
                    newChar.character_mask_id        = randomId(10)
                    newChar.character_dna_id         = randomId(10)
                    newChar.character_fingerprint_id = randomId(10)
                    newChar.character_ssn_id         = randomSSN()
                end
                CharacterModel.create(newChar, function(charId)
                    if not charId then
                        if attempt < MAX_CREATE_RETRIES then
                            attemptCreate(attempt + 1)
                            return
                        end
                        Log.error("Char", "Failed to create character for account " .. accountId .. " after " .. MAX_CREATE_RETRIES .. " attempts")
                        rejectCreate("Character creation failed. Please try again.")
                        return
                    end
                    onCreateSuccess(charId)
                end)
            end
            attemptCreate(1)
        end)
    end)

    end) -- DB.select (duplicate name check)
end, true)
