-- models/faction_rank.lua
-- Faction rank model. Ranks belong to the root (top-level) faction and are shared
-- across all sub-factions and departments.
--
-- faction_rank_order: 1 = highest (leader). Higher number = lower authority.
-- faction_rank_permissions: bitmask (see OrgPerms in org_helpers.lua).
-- faction_rank_is_default: 1 = this rank is assigned to new members on invite.
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.

FactionRankModel = Model.define("faction_ranks", {
    { name = "faction_rank_id",            type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to factions.faction_id (always the root/top-level faction).
    { name = "faction_rank_faction_id",    type = "INTEGER", notNull = true },

    { name = "faction_rank_name",          type = "TEXT",    notNull = true },
    { name = "faction_rank_order",         type = "INTEGER", notNull = true },
    { name = "faction_rank_salary",        type = "INTEGER", notNull = true, default = 0 },
    { name = "faction_rank_permissions",   type = "INTEGER", notNull = true, default = 0 },
    { name = "faction_rank_is_default",    type = "INTEGER", notNull = true, default = 0 },

    { name = "faction_rank_creation_date", type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
