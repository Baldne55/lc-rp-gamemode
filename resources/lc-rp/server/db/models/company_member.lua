-- models/company_member.lua
-- Company membership model. Links a character to a company with a rank.
--
-- company_member_company_id can point to a top-level company, sub-company, or department.
-- company_member_rank_id always points to a rank in the root company's rank table.
-- A character can be in multiple companies simultaneously (unlimited membership).

CompanyMemberModel = Model.define("company_members", {
    { name = "company_member_id",           type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to companies.company_id (can be any level: company, sub-company, or department).
    { name = "company_member_company_id",   type = "INTEGER", notNull = true },

    -- FK to characters.character_id.
    { name = "company_member_character_id", type = "INTEGER", notNull = true },

    -- FK to company_ranks.company_rank_id.
    { name = "company_member_rank_id",      type = "INTEGER", notNull = true },

    { name = "company_member_joined_date",  type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
