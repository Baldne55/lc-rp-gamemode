-- server/config.lua
-- Centralized server-side configuration. Loaded before all other server scripts.
--
-- Database credentials: set via environment variables for production.
--   LCRP_DB_TYPE = 0 (MySQL X) or 1 (SQLite)
--   LCRP_DB_URL  = connection string

Config = {}

-- Safe getenv wrapper for environments (like MTA) without os.getenv ---------
local function getenv(name)
    if os and type(os.getenv) == "function" then
        return os.getenv(name)
    end
    return nil
end

-- Database -----------------------------------------------------------------------
Config.DB_TYPE = tonumber(getenv("LCRP_DB_TYPE")) or 0
Config.DB_URL  = getenv("LCRP_DB_URL") or "mysqlx://root@localhost:33060/lc-rp"

-- Authentication -----------------------------------------------------------------
Config.AUTH = {
    MAX_ATTEMPTS    = 5,
    LOCKOUT_SECONDS = 900,  -- 15 minutes
    USERNAME_MIN    = 3,
    USERNAME_MAX    = 20,
    PASSWORD_MIN    = 6,
    PASSWORD_MAX    = 64,
    REQUIRE_VERIFICATION = false,  -- set true once email verification is implemented
}

-- Chat ---------------------------------------------------------------------------
Config.CHAT = {
    PROXIMITY_RADIUS        = 10,
    LOW_PROXIMITY_RADIUS    = 5,
    WHISPER_PROXIMITY_RADIUS = 3,
    SHOUT_PROXIMITY_RADIUS  = 20,
    MAX_MESSAGE_LENGTH      = 255,
    COOLDOWN_MS             = 500,
    COLOURS = {
        NAME   = "{FFFFFF}",
        IC     = "{FFFFFF}",
        OOC    = "{AAAAAA}",
        ME_DO   = "{CC99FF}",
        ADMIN   = "{FF6666}",
        PM_SENT  = "{FFCC00}",
        PM_RECV  = "{FFE566}",
        TO_ALERT  = "{E866FF}",
        WHISPER   = "{FF9933}",
    },
}

-- World --------------------------------------------------------------------------
Config.SERVER_YEAR = 2008
Config.CHARACTER_AGE_MIN = 14
Config.CHARACTER_AGE_MAX = 90

-- Spawn --------------------------------------------------------------------------
Config.SPAWN_DEFAULT = { x = 2362.57, y = 377.41, z = 6.09, r = 89.33 }

-- Position sync bounds (GTA IV map limits) ---------------------------------------
Config.MAP_BOUNDS = {
    xMin = -4000, xMax = 5000,
    yMin = -4000, yMax = 5000,
    zMin = -100,  zMax = 1000,
}

-- Player payments --------------------------------------------------------
Config.PAY = {
    MAX_AMOUNT = 100000,  -- maximum single transfer
}

-- Death / injury ----------------------------------------------------------
Config.DEATH = {
    ACCEPT_DELAY_SECONDS = 120,
    HOSPITAL_SPAWN = { x = 2362.57, y = 377.41, z = 6.09, r = 89.33 },
    RESPAWN_HP = 51,
    HELPUP_RADIUS = 3,
    HELPUP_HP     = 51,
}

-- Inventory ---------------------------------------------------------------
Config.INVENTORY = {
    MAX_SLOTS        = 20,    -- default character inventory slots
    MAX_CARRY_WEIGHT = 50.0,  -- default max carry weight in kg
    GIVE_RADIUS      = 5,     -- max distance for /giveitem (units)
    PICKUP_RADIUS    = 3,     -- max distance for /pickup (units)
    DROP_OFFSET_Z    = -0.8, -- Z offset for dropped item labels (lowered from ground level)
}
