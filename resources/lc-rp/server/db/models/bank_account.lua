-- models/bank_account.lua
-- Shared bank account model. Supports character, business, faction, and company owners.
--
-- bank_account_owner_type: 'character' | 'business' | 'faction' | 'company'
-- bank_account_type:       'checking' | 'savings'
--
-- Each owner can have multiple accounts (e.g. one checking + one savings).
-- Routing numbers are unique 9-digit numeric strings.
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.
-- Currency columns use INTEGER (whole units; no fractional amounts).

BankAccountModel = Model.define("bank_accounts", {
    { name = "bank_account_id",              type = "INTEGER", primary = true, autoIncrement = true },

    -- Polymorphic owner: type + id together identify the owner entity.
    { name = "bank_account_owner_type",      type = "TEXT",    notNull = true },
    { name = "bank_account_owner_id",        type = "INTEGER", notNull = true },

    -- Account type: checking (everyday use) or savings (restricted, higher balance).
    { name = "bank_account_type",            type = "TEXT",    notNull = true },

    { name = "bank_account_balance",         type = "INTEGER", notNull = true, default = 0 },

    -- Unique 9-digit routing number (e.g. "482031597").
    { name = "bank_account_routing_number",  type = "TEXT",    notNull = true, unique = true },

    -- Minimum character level required to access this account. 0 = no restriction.
    { name = "bank_account_required_level",  type = "INTEGER", notNull = true, default = 0 },

    -- Whether the account is frozen (by staff or in-game bank). Frozen accounts cannot transact.
    { name = "bank_account_is_frozen",       type = "INTEGER", notNull = true, default = 0 },

    { name = "bank_account_creation_date",   type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
