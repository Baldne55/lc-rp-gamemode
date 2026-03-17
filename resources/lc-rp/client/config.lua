-- client/config.lua
-- Centralized client-side configuration. Loaded before all other client scripts.

ClientConfig = {}

-- Authentication camera and spawn position.
ClientConfig.AUTH = {
    CAM_COORDS  = { -222.98, 430.16, 32.41 },
    SPAWN_COORDS = { -222.98, 430.16, 32.41, 0.0 },
    MODEL       = "M_Y_MULTIPLAYER",
    INITIAL_HEALTH = 300,
}

-- Character spawn defaults (must match server Config.SPAWN_DEFAULT).
ClientConfig.SPAWN_DEFAULT = { x = 2362.57, y = 377.41, z = 6.09, r = 89.33 }

-- Component slot count (GTA IV ped components 0-10).
ClientConfig.COMPONENT_COUNT = 11

-- Health/armour: DB stores 0-100, GTA IV uses 0-200.
ClientConfig.HEALTH_ARMOUR_MULTIPLIER = 2

-- HUD colour indices for player name plates (GTA IV HUD_COLOUR_NET_PLAYER1-32).
ClientConfig.HUD_COLOUR_RANGE = { 26, 57 }

-- Chat settings.
ClientConfig.CHAT = {
    INPUT_KEY      = 20,    -- T key code
    DEFAULT_FONT_SIZE = 12,
    DEFAULT_PAGE_SIZE = 20,
}

-- Death / injury.
ClientConfig.DEATH = {
    ACCEPT_DELAY_SECONDS = 120,
}

-- Position sync interval in milliseconds.
ClientConfig.SYNC_INTERVAL_MS = 800
