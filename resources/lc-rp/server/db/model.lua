-- model.lua
-- Lightweight ORM factory built on top of DB wrappers.
--
-- Usage:
--   local MyModel = Model.define("table_name", { ... schema ... })
--   MyModel.sync()                              -- CREATE TABLE IF NOT EXISTS
--   MyModel.findOne({ id = 1 }, callback)       -- SELECT ... LIMIT 1
--   MyModel.findAll({ admin = 1 }, callback)    -- SELECT ...
--   MyModel.create({ name = "x" }, callback)    -- INSERT
--   MyModel.update({ money = 0 }, { id = 1 }, callback) -- UPDATE
--   MyModel.delete({ id = 1 }, callback)        -- DELETE
--   MyModel.upsert({ id = 1 }, { money = 500 }, callback)

Model = {}

--- Escapes a string for use in SQL single-quoted literals (doubles single quotes).
local function escapeSqlString(s)
    return s:gsub("'", "''")
end

-- Builds a WHERE clause and its params from a key/value table.
-- validCols: set of allowed column names (required for injection prevention).
local function buildWhere(where, validCols)
    if not where or next(where) == nil then return "", {} end
    local clauses, params = {}, {}
    for col, val in pairs(where) do
        if not validCols[col] then
            Log.error("DB", "buildWhere: rejected unknown column '" .. tostring(col) .. "'")
            error("Invalid column name: " .. tostring(col))
        end
        clauses[#clauses + 1] = "`" .. col .. "` = ?"
        params[#params + 1] = val
    end
    return " WHERE " .. table.concat(clauses, " AND "), params
end

-- Builds a SET clause and its params from a key/value table.
-- validCols: set of allowed column names (required for injection prevention).
local function buildSet(data, validCols)
    local clauses, params = {}, {}
    for col, val in pairs(data) do
        if not validCols[col] then
            Log.error("DB", "buildSet: rejected unknown column '" .. tostring(col) .. "'")
            error("Invalid column name: " .. tostring(col))
        end
        clauses[#clauses + 1] = "`" .. col .. "` = ?"
        params[#params + 1] = val
    end
    return table.concat(clauses, ", "), params
end

-- Merges two sequential param lists into one.
local function mergeParams(a, b)
    local merged = {}
    for _, v in ipairs(a) do merged[#merged + 1] = v end
    for _, v in ipairs(b) do merged[#merged + 1] = v end
    return merged
end

-- Builds a CREATE TABLE IF NOT EXISTS statement from a schema definition.
-- Schema column options: name, type, primary, autoIncrement, notNull, unique, default, defaultRaw
-- Use `defaultRaw` for SQL expressions like CURRENT_TIMESTAMP (not quoted).
--
-- MySQL: TEXT/BLOB columns cannot have DEFAULT values; TEXT+UNIQUE needs a key length.
-- utf8mb4 uses 4 bytes/char; max key ~1000 bytes => use VARCHAR(191) for indexed columns.
local function buildCreateTable(tableName, schema)
    local cols = {}
    for _, col in ipairs(schema) do
        local def
        if col.primary and col.autoIncrement then
            if DB.type == 1 then
                -- SQLite: the canonical auto-increment primary key form
                def = "`" .. col.name .. "` INTEGER PRIMARY KEY AUTOINCREMENT"
            else
                -- MySQL X
                def = "`" .. col.name .. "` INT NOT NULL AUTO_INCREMENT PRIMARY KEY"
            end
        else
            local colType = col.type
            local hasDefault = (col.defaultRaw ~= nil) or (col.default ~= nil)
            -- MySQL: TEXT with DEFAULT is invalid; TEXT with UNIQUE/INDEX needs a key length.
            -- CURRENT_TIMESTAMP requires DATETIME/TIMESTAMP, not VARCHAR.
            if DB.type == 0 then
                if col.defaultRaw == "CURRENT_TIMESTAMP" then
                    colType = "DATETIME"
                elseif colType == "TEXT" and (hasDefault or col.unique) then
                    colType = "VARCHAR(191)"
                end
            end
            def = "`" .. col.name .. "` " .. colType
            if col.notNull    then def = def .. " NOT NULL" end
            if col.unique     then def = def .. " UNIQUE"   end
            if col.defaultRaw ~= nil then
                def = def .. " DEFAULT " .. col.defaultRaw
            elseif col.default ~= nil then
                if type(col.default) == "string" then
                    def = def .. " DEFAULT '" .. escapeSqlString(col.default) .. "'"
                else
                    def = def .. " DEFAULT " .. tostring(col.default)
                end
            end
        end
        cols[#cols + 1] = def
    end
    return "CREATE TABLE IF NOT EXISTS `" .. tableName .. "` (" .. table.concat(cols, ", ") .. ")"
end

function Model.define(tableName, schema)
    local m = {}

    -- Build column whitelist from schema for injection prevention.
    local validCols = {}
    for _, col in ipairs(schema) do
        validCols[col.name] = true
    end

    -- Create the table if it does not yet exist.
    function m.sync(callback)
        local sql = buildCreateTable(tableName, schema)
        DB.execute(sql, {}, DB.safeCallback("sync:" .. tableName, function()
            Log.info("DB", "Synced table `" .. tableName .. "`")
            if callback then callback() end
        end))
    end

    -- Returns the first matching row, or nil.
    function m.findOne(where, callback)
        local whereClause, params = buildWhere(where, validCols)
        DB.select(
            "SELECT * FROM `" .. tableName .. "`" .. whereClause .. " LIMIT 1",
            params,
            function(rows)
                callback(rows and rows[1] or nil)
            end
        )
    end

    -- Returns all matching rows as a list (empty list if none).
    function m.findAll(where, callback)
        local whereClause, params = buildWhere(where, validCols)
        DB.select(
            "SELECT * FROM `" .. tableName .. "`" .. whereClause,
            params,
            function(rows)
                callback(rows or {})
            end
        )
    end

    -- Inserts a new row. Callback receives the new auto-increment ID.
    function m.create(data, callback)
        if not data or next(data) == nil then
            Log.error("DB", "create: called with empty data on table " .. tableName)
            if callback then callback(nil) end
            return
        end
        local cols, placeholders, params = {}, {}, {}
        for col, val in pairs(data) do
            if not validCols[col] then
                Log.error("DB", "create: rejected unknown column '" .. tostring(col) .. "' on table " .. tableName)
                error("Invalid column name: " .. tostring(col))
            end
            cols[#cols + 1]         = "`" .. col .. "`"
            placeholders[#placeholders + 1] = "?"
            params[#params + 1]     = val
        end
        DB.insert(
            "INSERT INTO `" .. tableName .. "` (" ..
                table.concat(cols, ", ") .. ") VALUES (" ..
                table.concat(placeholders, ", ") .. ")",
            params,
            callback
        )
    end

    -- Updates rows matching where with data. Callback receives affected row count.
    function m.update(data, where, callback)
        if not data or next(data) == nil then
            Log.error("DB", "update: called with empty data on table " .. tableName)
            if callback then callback(0) end
            return
        end
        local setClause,   setParams   = buildSet(data, validCols)
        local whereClause, whereParams = buildWhere(where, validCols)
        DB.execute(
            "UPDATE `" .. tableName .. "` SET " .. setClause .. whereClause,
            mergeParams(setParams, whereParams),
            callback
        )
    end

    -- Deletes rows matching where. Callback receives affected row count.
    -- M9: Require at least one WHERE condition to prevent accidental full-table deletes.
    function m.delete(where, callback)
        if not where or next(where) == nil then
            Log.error("DB", "delete: called with empty WHERE on table " .. tableName .. " — refusing to delete all rows")
            if callback then callback(0) end
            return
        end
        local whereClause, params = buildWhere(where, validCols)
        DB.execute(
            "DELETE FROM `" .. tableName .. "`" .. whereClause,
            params,
            callback
        )
    end

    -- Explicit full-table delete for intentional bulk operations.
    function m.deleteAll(callback)
        DB.execute("DELETE FROM `" .. tableName .. "`", {}, callback)
    end

    -- Atomic upsert: inserts if the row doesn't exist, updates if it does.
    -- Uses INSERT ... ON CONFLICT (SQLite) or INSERT ... ON DUPLICATE KEY UPDATE (MySQL).
    -- `where` keys identify the conflict target; `data` keys are the values to set/update.
    function m.upsert(where, data, callback)
        local allData = {}
        for k, v in pairs(where) do allData[k] = v end
        for k, v in pairs(data)  do allData[k] = v end

        local cols, placeholders, insertParams = {}, {}, {}
        for col, val in pairs(allData) do
            if not validCols[col] then
                Log.error("DB", "upsert: rejected unknown column '" .. tostring(col) .. "' on table " .. tableName)
                error("Invalid column name: " .. tostring(col))
            end
            cols[#cols + 1] = "`" .. col .. "`"
            placeholders[#placeholders + 1] = "?"
            insertParams[#insertParams + 1] = val
        end

        local setClauses, updateParams = {}, {}
        for col, val in pairs(data) do
            setClauses[#setClauses + 1] = "`" .. col .. "` = ?"
            updateParams[#updateParams + 1] = val
        end

        local params = {}
        for _, v in ipairs(insertParams) do params[#params + 1] = v end
        for _, v in ipairs(updateParams) do params[#params + 1] = v end

        local sql
        if DB.type == 1 then
            -- SQLite: ON CONFLICT uses the columns from `where` as the conflict target.
            local conflictCols = {}
            for col, _ in pairs(where) do conflictCols[#conflictCols + 1] = "`" .. col .. "`" end
            sql = "INSERT INTO `" .. tableName .. "` (" .. table.concat(cols, ", ") .. ") VALUES (" ..
                  table.concat(placeholders, ", ") .. ") ON CONFLICT(" .. table.concat(conflictCols, ", ") ..
                  ") DO UPDATE SET " .. table.concat(setClauses, ", ")
        else
            -- MySQL: ON DUPLICATE KEY UPDATE.
            sql = "INSERT INTO `" .. tableName .. "` (" .. table.concat(cols, ", ") .. ") VALUES (" ..
                  table.concat(placeholders, ", ") .. ") ON DUPLICATE KEY UPDATE " ..
                  table.concat(setClauses, ", ")
        end

        DB.execute(sql, params, callback)
    end

    return m
end
