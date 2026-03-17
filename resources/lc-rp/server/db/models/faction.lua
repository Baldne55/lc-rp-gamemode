-- models/faction.lua
-- Faction model. Supports hierarchy via self-referential parent_id.
--
-- faction_parent_id: NULL = top-level faction. Max depth 3 (faction → sub-faction → department).
-- faction_type: 'illegal' | 'government' | 'police' | 'ems' | 'fire' | 'news' | 'legal' | 'other'
-- faction_is_active: soft-delete flag (1 = active, 0 = inactive).
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.

FactionModel = Model.define("factions", {
    { name = "faction_id",            type = "INTEGER", primary = true, autoIncrement = true },

    -- Self-referential parent: NULL = top-level faction.
    { name = "faction_parent_id",     type = "INTEGER" },

    { name = "faction_name",          type = "TEXT",    notNull = true, unique = true },
    { name = "faction_short_name",    type = "TEXT" },
    { name = "faction_type",          type = "TEXT",    notNull = true },
    { name = "faction_motd",          type = "TEXT" },
    { name = "faction_is_active",     type = "INTEGER", notNull = true, default = 1 },

    -- account_id of the admin who created this faction.
    { name = "faction_created_by",    type = "INTEGER" },

    { name = "faction_creation_date", type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
