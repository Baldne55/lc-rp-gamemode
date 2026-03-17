-- server/handlers/settings.lua
-- Handles the settings panel: fetching current preferences, saving changes,
-- and account password changes.

local _LOG_TAG = "Settings"

-- ── settings_request ─────────────────────────────────────────────────────────
-- Client opens the settings panel and needs current values.

Events.Subscribe("settings_request", function()
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end

    Events.CallRemote("settings_data", source, {
        data.chatFontSize or 0,
        data.chatPageSize or 0,
        data.showMoneyHud and 1 or 0,
        data.useUINotifications and 1 or 0,
        data.useInventoryUI and 1 or 0,
    })
end, true)

-- ── settings_save ────────────────────────────────────────────────────────────
-- Client sends { key, value } when a setting is changed in the panel.

local SAVE_HANDLERS = {}

SAVE_HANDLERS["chatFontSize"] = function(source, data, value)
    local size = tonumber(value)
    if not size or size < 12 or size > 24 then return end
    size = math.floor(size)
    data.chatFontSize = size
    CharacterModel.update({
        character_chat_font_size = size,
        character_chat_page_size = data.chatPageSize or 0,
    }, { character_id = data.charId })
end

SAVE_HANDLERS["chatPageSize"] = function(source, data, value)
    local size = tonumber(value)
    if not size or size < 10 or size > 30 then return end
    size = math.floor(size)
    data.chatPageSize = size
    CharacterModel.update({
        character_chat_font_size = data.chatFontSize or 0,
        character_chat_page_size = size,
    }, { character_id = data.charId })
end

SAVE_HANDLERS["showMoneyHud"] = function(source, data, value)
    local enabled = tonumber(value) == 1
    data.showMoneyHud = enabled
    CharacterModel.update({ character_show_money_hud = enabled and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("hud_money_toggle", source, { enabled })
end

SAVE_HANDLERS["useUINotifications"] = function(source, data, value)
    local enabled = tonumber(value) == 1
    data.useUINotifications = enabled
    CharacterModel.update({ character_use_ui_notifications = enabled and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("notify_ui_toggle", source, { enabled })
end

SAVE_HANDLERS["useInventoryUI"] = function(source, data, value)
    local enabled = tonumber(value) == 1
    data.useInventoryUI = enabled
    CharacterModel.update({ character_use_inventory_ui = enabled and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("inv_ui_toggle", source, { enabled })
end

Events.Subscribe("settings_save", function(arg1, arg2)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end

    -- Framework may pass args as (table) or (key, value) depending on unwrapping.
    local key, value
    if type(arg1) == "table" then
        if type(arg1[1]) == "table" then arg1 = arg1[1] end
        key   = tostring(arg1[1] or "")
        value = arg1[2]
    else
        key   = tostring(arg1 or "")
        value = arg2
    end

    local handler = SAVE_HANDLERS[key]
    if not handler then return end
    handler(source, data, value)
end, true)

-- ── settings_change_password ─────────────────────────────────────────────────
-- Client sends { currentPassword, newPassword }.

Events.Subscribe("settings_change_password", function(arg1, arg2)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.accountId then return end

    local currentPassword, newPassword
    if type(arg1) == "table" then
        if type(arg1[1]) == "table" then arg1 = arg1[1] end
        currentPassword = tostring(arg1[1] or "")
        newPassword     = tostring(arg1[2] or "")
    else
        currentPassword = tostring(arg1 or "")
        newPassword     = tostring(arg2 or "")
    end

    -- Validate new password length.
    if #newPassword < Config.AUTH.PASSWORD_MIN then
        Events.CallRemote("settings_result", source, { "error", "New password must be at least " .. Config.AUTH.PASSWORD_MIN .. " characters." })
        return
    end
    if #newPassword > Config.AUTH.PASSWORD_MAX then
        Events.CallRemote("settings_result", source, { "error", "New password is too long." })
        return
    end

    AccountModel.findOne({ account_id = data.accountId }, function(account)
        if not account then
            Events.CallRemote("settings_result", source, { "error", "Account not found." })
            return
        end

        if not Hash.verifyPassword(currentPassword, account.account_password_salt, account.account_password) then
            Events.CallRemote("settings_result", source, { "error", "Current password is incorrect." })
            return
        end

        local newSalt = Hash.generateSalt()
        local newHash = Hash.hashPassword(newPassword, newSalt)

        AccountModel.update(
            { account_password = newHash, account_password_salt = newSalt },
            { account_id = data.accountId },
            function(affectedRows)
                if not affectedRows or affectedRows == 0 then
                    Events.CallRemote("settings_result", source, { "error", "Failed to update password. Try again." })
                    return
                end
                Log.info(_LOG_TAG, (data.username or tostring(source)) .. " changed their password.")
                Events.CallRemote("settings_result", source, { "success", "Password changed successfully." })
            end
        )
    end)
end, true)
