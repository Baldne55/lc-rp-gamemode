-- server/db/migrations.lua
-- Sequential migration runner. Flattens deeply nested callback chains.
--
-- Usage:
--   Migrations.register("add_column_x", function(done) DB.execute("ALTER ...", {}, done) end)
--   Migrations.runAll(function() Log.info("DB", "All migrations complete") end)

Migrations = {}

local _migrations = {}

--- Registers a named migration. Migrations run in registration order.
--- @param name string  Human-readable name for logging.
--- @param fn function  Migration function: receives a `done` callback to call when finished.
function Migrations.register(name, fn)
    _migrations[#_migrations + 1] = { name = name, fn = fn }
end

--- Runs all registered migrations sequentially, then calls `callback`.
function Migrations.runAll(callback)
    local function runNext(i)
        if i > #_migrations then
            if callback then callback() end
            return
        end
        local m = _migrations[i]
        Log.info("DB", "Running migration: " .. m.name)
        local ok, err = pcall(m.fn, function()
            runNext(i + 1)
        end)
        if not ok then
            Log.error("DB", "Migration '" .. m.name .. "' threw error: " .. tostring(err))
            Log.error("DB", "Remaining migrations skipped. Server may be in an inconsistent state.")
            if callback then callback() end
            return
        end
    end
    runNext(1)
end
