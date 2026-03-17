-- models/bank_transaction.lua
-- Ledger of all bank account transactions. Immutable audit trail.
--
-- bank_transaction_type: 'deposit' | 'withdrawal' | 'transfer' | 'payment' | 'salary' | 'refund' | 'adjustment'
--
-- For transfers between accounts, both sender and receiver are recorded.
-- For deposits/withdrawals, only the relevant account is set (the other is null).
-- Staff adjustments use type 'adjustment' with an optional description.

BankTransactionModel = Model.define("bank_transactions", {
    { name = "bank_transaction_id",                  type = "INTEGER", primary = true, autoIncrement = true },

    -- The account this transaction belongs to (always set).
    { name = "bank_transaction_account_id",          type = "INTEGER", notNull = true },

    -- For transfers: the other party's account. Null for deposits/withdrawals.
    { name = "bank_transaction_other_account_id",    type = "INTEGER" },

    { name = "bank_transaction_type",                type = "TEXT",    notNull = true },

    -- Positive = credit, negative = debit (from this account's perspective).
    { name = "bank_transaction_amount",              type = "INTEGER", notNull = true },

    -- Balance after this transaction was applied.
    { name = "bank_transaction_balance_after",       type = "INTEGER", notNull = true },

    -- Human-readable description (e.g. "ATM Deposit", "Transfer to #482031597", "Salary: LSPD").
    { name = "bank_transaction_description",         type = "TEXT" },

    -- Who initiated: character ID, or null for system/staff actions.
    { name = "bank_transaction_initiated_by",        type = "INTEGER" },

    { name = "bank_transaction_date",                type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
