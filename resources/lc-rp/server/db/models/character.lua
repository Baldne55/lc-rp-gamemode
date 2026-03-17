-- models/character.lua
-- Character model. One account can own multiple characters up to the slot limit.
--
-- character_status:        'Active' | 'Locked'
-- character_gender:        'Male' | 'Female'
-- character_blood_type:    'A+' | 'A-' | 'B+' | 'B-' | 'AB+' | 'AB-' | 'O+' | 'O-'
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.
-- DATE columns are stored as TEXT in ISO 8601 format.
-- Currency columns use INTEGER (whole units; no fractional amounts).
-- JSON appearance data is replaced by character_skin (ped model string).

CharacterModel = Model.define("characters", {
    -- Primary key.
    { name = "character_id",                                    type = "INTEGER", primary = true, autoIncrement = true },

    -- Foreign key to accounts.account_id.
    { name = "character_account_id",                            type = "INTEGER", notNull = true },

    -- Zero-based slot index within the account (0 = first slot, 1 = second, …).
    { name = "character_slot_id",                               type = "INTEGER", notNull = true },

    -- Unique 10-char mask identifier. Shown to others when the character is masked.
    { name = "character_mask_id",                               type = "TEXT",    notNull = true, unique = true },

    -- Unique 10-char DNA identifier. Used by forensic systems.
    { name = "character_dna_id",                                type = "TEXT",    notNull = true, unique = true },

    -- Unique 10-char fingerprint identifier. Used by forensic systems.
    { name = "character_fingerprint_id",                        type = "TEXT",    notNull = true, unique = true },

    -- Unique SSN in XXX-XX-XXXX format. Assigned at creation, never changed.
    { name = "character_ssn_id",                                type = "TEXT",    notNull = true, unique = true },

    -- Lifecycle state. Locked characters cannot be selected.
    { name = "character_status",                                type = "TEXT",    notNull = true, default = "Active" },

    -- Whether the character is currently logged in. Reset to 0 on disconnect.
    { name = "character_is_logged_in_game",                     type = "INTEGER", notNull = true, default = 0 },

    -- Character's given name (max 32 chars).
    { name = "character_first_name",                            type = "TEXT",    notNull = true },

    -- Character's middle name. Null when not provided.
    { name = "character_middle_name",                           type = "TEXT" },

    -- Character's family name (max 32 chars).
    { name = "character_last_name",                             type = "TEXT",    notNull = true },

    -- In-universe date of birth. Used to calculate in-game age.
    { name = "character_birth_date",                            type = "TEXT",    notNull = true },

    -- Biological sex. Determines available clothing categories and default animations.
    { name = "character_gender",                                type = "TEXT",    notNull = true },

    -- ABO blood group. Referenced by medical systems.
    { name = "character_blood_type",                            type = "TEXT",    notNull = true },

    -- Height in centimetres (100–250). Null until set during creation.
    { name = "character_height",                                type = "INTEGER" },

    -- Weight in kilograms (30–200). Null until set during creation.
    { name = "character_weight",                                type = "INTEGER" },

    -- Free-text physical appearance description for roleplay.
    { name = "character_physical_description",                  type = "TEXT" },

    -- Free-text visible tattoos description for roleplay.
    { name = "character_tattoos_description",                   type = "TEXT" },

    -- Free-text typical clothing description for roleplay.
    { name = "character_clothing_description",                  type = "TEXT" },

    -- Character level, starting at 1.
    { name = "character_level",                                 type = "INTEGER", notNull = true, default = 1 },

    -- Total lifetime experience points earned.
    { name = "character_experience_points",                     type = "INTEGER", notNull = true, default = 0 },

    -- XP earned today. Capped by the daily anti-grind limit.
    { name = "character_daily_experience_points_earned",        type = "INTEGER", notNull = true, default = 0 },

    -- UTC timestamp at which the daily XP cap resets.
    { name = "character_daily_experience_points_cap_reset_date", type = "TEXT" },

    -- XP earned this week. Capped by the weekly anti-grind limit.
    { name = "character_weekly_experience_points_earned",       type = "INTEGER", notNull = true, default = 0 },

    -- UTC timestamp at which the weekly XP cap resets.
    { name = "character_weekly_experience_points_cap_reset_date", type = "TEXT" },

    -- XP earned this month. Capped by the monthly anti-grind limit.
    { name = "character_monthly_experience_points_earned",      type = "INTEGER", notNull = true, default = 0 },

    -- UTC timestamp at which the monthly XP cap resets.
    { name = "character_monthly_experience_points_cap_reset_date", type = "TEXT" },

    -- Playtime in the current session (minutes). Flushed to character_playtime_hours periodically.
    { name = "character_playtime_minutes",                      type = "INTEGER", notNull = true, default = 0 },

    -- Total lifetime playtime in hours.
    { name = "character_playtime_hours",                        type = "INTEGER", notNull = true, default = 0 },

    -- Current health points (0 = dead, 100 = full).
    { name = "character_hp",                                    type = "INTEGER", notNull = true, default = 100 },

    -- Current armour points (0 = none, 100 = full).
    { name = "character_ap",                                    type = "INTEGER", notNull = true, default = 0 },

    -- World/dimension ID. 0 = main world.
    { name = "character_world",                                 type = "INTEGER", notNull = true, default = 0 },

    -- Last saved position and heading.
    { name = "character_position_x",                            type = "REAL",    notNull = true, default = 2362.57 },
    { name = "character_position_y",                            type = "REAL",    notNull = true, default = 377.41 },
    { name = "character_position_z",                            type = "REAL",    notNull = true, default = 6.09 },
    { name = "character_position_r",                            type = "REAL",    notNull = true, default = 89.33 },

    -- Whether the character is currently wearing a mask.
    { name = "character_is_masked",                             type = "INTEGER", notNull = true, default = 0 },

    -- Whether the character is currently serving a prison sentence.
    { name = "character_is_prisoned",                           type = "INTEGER", notNull = true, default = 0 },

    -- UTC expiry of the prison sentence. Null when not imprisoned.
    { name = "character_prison_expiration_date",                type = "TEXT" },

    -- Cash on hand (money in pocket).
    { name = "character_cash",                                  type = "INTEGER", notNull = true, default = 1500 },

    -- Ped model string defining the character's appearance (e.g. "M_Y_MULTIPLAYER").
    { name = "character_skin",                                  type = "TEXT",    notNull = true, default = "M_Y_MULTIPLAYER" },

    -- JSON object of clothing component overrides: {"0":[drawable,texture], "1":[...], ...} for slots 0-10. Null = ped defaults.
    { name = "character_appearance",                            type = "TEXT" },

    -- IP address used when the character was created. Stored for audit/anti-abuse.
    { name = "character_creation_ip",                           type = "TEXT" },

    -- UTC timestamp when the character was created.
    { name = "character_creation_date",                         type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },

    -- UTC timestamp of the most recent login with this character.
    { name = "character_last_login_date",                       type = "TEXT" },

    -- UTC timestamp of the most recent logout with this character.
    { name = "character_last_logout_date",                      type = "TEXT" },

    -- Whether the player prefers the graphical inventory UI over chat-based.
    { name = "character_use_inventory_ui",                      type = "INTEGER", notNull = true, default = 0 },

    -- Whether the player prefers to see the money HUD overlay.
    { name = "character_show_money_hud",                        type = "INTEGER", notNull = true, default = 1 },

    -- Whether the player prefers UI toast notifications over chat-based.
    { name = "character_use_ui_notifications",                  type = "INTEGER", notNull = true, default = 0 },

    -- Chat font size in pixels (12-24).
    { name = "character_chat_font_size",                        type = "INTEGER", notNull = true, default = 12 },

    -- Chat page height in em (10-30).
    { name = "character_chat_page_size",                        type = "INTEGER", notNull = true, default = 20 },
})
