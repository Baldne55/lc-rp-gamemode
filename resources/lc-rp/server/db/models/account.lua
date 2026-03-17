-- models/account.lua
-- Master account model. Tied to the player's Rockstar/Social Club identity.
--
-- account_status values:   'Unverified' | 'Active' | 'Locked'
-- account_staff_level:     'None' | 'Support' | 'Senior Support'
--                          | 'Trial Administrator' | 'Game Administrator Level 1'
--                          | 'Game Administrator Level 2' | 'Senior Administrator'
--                          | 'Lead Administrator' | 'Management'
--                          | 'Game Developer' | 'Senior Game Developer' | 'Lead Game Developer'
--                          | 'Senior Web Developer' | 'Lead Web Developer'
-- account_premium_level:   'None' | 'Bronze' | 'Silver' | 'Gold' | 'Platinum'
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.
-- DATE columns are stored as TEXT in ISO 8601 format (CURRENT_TIMESTAMP on insert).

AccountModel = Model.define("accounts", {
    -- Primary key.
    { name = "account_id",                           type = "INTEGER", primary = true, autoIncrement = true },

    -- Unique username chosen at registration (3–20 alphanumeric/underscore/hyphen).
    { name = "account_username",                     type = "TEXT",    notNull = true, unique = true },

    -- SHA-256(salt + password) stored as 64-char hex. See server/utils/hash.lua.
    -- Node.js equivalent: crypto.createHash('sha256').update(salt + password).digest('hex')
    { name = "account_password",                     type = "TEXT",    notNull = true },

    -- 32-char random hex salt generated at registration. Never changes.
    { name = "account_password_salt",                type = "TEXT",    notNull = true },

    -- Rockstar Games Social Club identifier. Null until first RGSC-authenticated login.
    { name = "account_rgsc_id",                      type = "TEXT",    unique = true },

    -- Discord snowflake ID. Null until the player links their Discord account.
    { name = "account_discord_id",                   type = "TEXT",    unique = true },

    -- Discord username at time of linking. Refreshed on each OAuth login.
    -- Not marked UNIQUE: Discord usernames are not globally unique.
    { name = "account_discord_username",             type = "TEXT" },

    -- Lifecycle state. Unverified accounts cannot log in until verified. Locked = suspended.
    { name = "account_status",                       type = "TEXT",    notNull = true, default = "Unverified" },

    -- Staff rank. Determines moderation commands and admin panel access.
    { name = "account_staff_level",                  type = "TEXT",    notNull = true, default = "None" },

    -- Premium membership tier. Governs extra character slots, furniture slots, cosmetics.
    { name = "account_premium_level",                type = "TEXT",    notNull = true, default = "None" },

    -- UTC expiry of the current premium tier. Null when no subscription is active.
    { name = "account_premium_level_expiration_date", type = "TEXT" },

    -- UTC timestamp of the player's very first successful login. Set once, never updated.
    { name = "account_first_login_date",             type = "TEXT" },

    -- UTC timestamp of the most recent successful login.
    { name = "account_last_login_date",              type = "TEXT" },

    -- UTC timestamp of the most recent logout/disconnect.
    { name = "account_last_logout_date",             type = "TEXT" },

    -- IP address recorded at last login. Supports IPv4 (max 15) and IPv6 (max 45).
    { name = "account_last_ip",                      type = "TEXT" },

    -- UTC timestamp until which the account is locked. Null when not under a timed lock.
    { name = "account_locked_until_date",            type = "TEXT" },

    -- Whether the player has an active UCP session.
    { name = "account_is_logged_in_ucp",             type = "INTEGER", notNull = true, default = 0 },

    -- Whether the player is currently connected in-game.
    { name = "account_is_logged_in_game",            type = "INTEGER", notNull = true, default = 0 },

    -- UTC timestamp when the account was created.
    { name = "account_registration_date",            type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },

    -- IP address used at registration. Stored for audit and anti-abuse. Never updated.
    { name = "account_registration_ip",              type = "TEXT" },

    -- Number of characters currently owned by this account.
    { name = "account_total_characters",             type = "INTEGER", notNull = true, default = 0 },

    -- Maximum characters this account may own. Raised by premium or staff grants.
    { name = "account_max_characters",               type = "INTEGER", notNull = true, default = 3 },

    -- Cumulative in-game playtime across all characters, in hours.
    { name = "account_total_playtime",               type = "INTEGER", notNull = true, default = 0 },

    -- Spendable premium currency balance.
    { name = "account_premium_coins",                type = "INTEGER", notNull = true, default = 0 },

    -- Remaining character name changes.
    { name = "account_name_changes",                 type = "INTEGER", notNull = true, default = 0 },

    -- Remaining character phone number changes.
    { name = "account_number_changes",               type = "INTEGER", notNull = true, default = 0 },

    -- Remaining vehicle license plate changes.
    { name = "account_plate_changes",                type = "INTEGER", notNull = true, default = 0 },

    -- Total furniture slots available across all properties. Raised by premium tiers.
    { name = "account_premium_furniture_slots",      type = "INTEGER", notNull = true, default = 100 },
})
