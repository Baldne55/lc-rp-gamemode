-- models/company_rank.lua
-- Company rank model. Ranks belong to the root (top-level) company and are shared
-- across all sub-companies and departments.
--
-- company_rank_order: 1 = highest (leader). Higher number = lower authority.
-- company_rank_permissions: bitmask (see OrgPerms in org_helpers.lua).
-- company_rank_is_default: 1 = this rank is assigned to new members on invite.
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.

CompanyRankModel = Model.define("company_ranks", {
    { name = "company_rank_id",            type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to companies.company_id (always the root/top-level company).
    { name = "company_rank_company_id",    type = "INTEGER", notNull = true },

    { name = "company_rank_name",          type = "TEXT",    notNull = true },
    { name = "company_rank_order",         type = "INTEGER", notNull = true },
    { name = "company_rank_salary",        type = "INTEGER", notNull = true, default = 0 },
    { name = "company_rank_permissions",   type = "INTEGER", notNull = true, default = 0 },
    { name = "company_rank_is_default",    type = "INTEGER", notNull = true, default = 0 },

    { name = "company_rank_creation_date", type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
