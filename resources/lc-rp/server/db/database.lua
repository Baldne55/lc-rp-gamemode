-- database.lua
-- Central database configuration and raw async query wrappers.
--
-- Credentials are read from Config (server/config.lua), which sources
-- environment variables for production. No secrets in source code.
--
--   SQLite  (dev):        Config.DB_TYPE = 1,  Config.DB_URL = "lc-rp.db"
--   MySQL X (production): Config.DB_TYPE = 0,  Config.DB_URL = "mysqlx://user:pass@host:port/db"

DB = {}

local DB_TYPE = Config.DB_TYPE
local DB_URL  = Config.DB_URL

DB.type = DB_TYPE

function DB.connect()
    local ok, err = pcall(Database.Connect, DB_TYPE, DB_URL)
    if not ok then
        Log.error("DB", "FATAL: Failed to connect to database: " .. tostring(err))
        return false
    end
    local safeUrl = DB_URL:gsub("://(.-)@", "://*****@")
    Log.info("DB", "Connected (" .. (DB_TYPE == 0 and "MySQL X" or "SQLite") .. ") -> " .. safeUrl)
    return true
end

function DB.close()
    Database.Close()
    Log.info("DB", "Disconnected.")
end

function DB.select(sql, params, callback)
    Database.SelectAsync(sql, params or {}, callback)
end

function DB.execute(sql, params, callback)
    Database.ExecuteAsync(sql, params or {}, callback or function() end)
end

function DB.insert(sql, params, callback)
    Database.InsertAsync(sql, params or {}, callback or function() end)
end

--- Wraps a DB callback with nil-result error handling.
--- If the query returns nil, logs the error and returns early.
--- @param label string  Context label for the log message (e.g. "auth.findOne")
--- @param callback function  The actual callback to invoke on success
--- @return function  Wrapped callback safe for DB.select / DB.execute / DB.insert
function DB.safeCallback(label, callback)
    return function(result)
        if result == nil then
            Log.error("DB", label .. ": query returned nil (possible DB error)")
            if callback then callback(nil, "DB error: " .. label) end
            return
        end
        callback(result)
    end
end
