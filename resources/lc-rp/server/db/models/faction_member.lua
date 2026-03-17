-- models/faction_member.lua
-- Faction membership model. Links a character to a faction with a rank.
--
-- faction_member_faction_id can point to a top-level faction, sub-faction, or department.
-- faction_member_rank_id always points to a rank in the root faction's rank table.
-- A character can be in multiple factions simultaneously (unlimited membership).

FactionMemberModel = Model.define("faction_members", {
    { name = "faction_member_id",           type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to factions.faction_id (can be any level: faction, sub-faction, or department).
    { name = "faction_member_faction_id",   type = "INTEGER", notNull = true },

    -- FK to characters.character_id.
    { name = "faction_member_character_id", type = "INTEGER", notNull = true },

    -- FK to faction_ranks.faction_rank_id.
    { name = "faction_member_rank_id",      type = "INTEGER", notNull = true },

    { name = "faction_member_joined_date",  type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
