-- models/company.lua
-- Company model. Supports hierarchy via self-referential parent_id.
--
-- company_parent_id: NULL = top-level company. Max depth 3 (company → sub-company → department).
-- company_type: 'llc' | 'sole_proprietorship' | 'partnership' | 'corporation' | 'nonprofit'
-- company_is_active: soft-delete flag (1 = active, 0 = inactive).
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.

CompanyModel = Model.define("companies", {
    { name = "company_id",            type = "INTEGER", primary = true, autoIncrement = true },

    -- Self-referential parent: NULL = top-level company.
    { name = "company_parent_id",     type = "INTEGER" },

    { name = "company_name",          type = "TEXT",    notNull = true, unique = true },
    { name = "company_short_name",    type = "TEXT" },
    { name = "company_type",          type = "TEXT",    notNull = true },
    { name = "company_motd",          type = "TEXT" },
    { name = "company_is_active",     type = "INTEGER", notNull = true, default = 1 },

    -- account_id of the admin who created this company.
    { name = "company_created_by",    type = "INTEGER" },

    { name = "company_creation_date", type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
