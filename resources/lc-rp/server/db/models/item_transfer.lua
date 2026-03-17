-- models/item_transfer.lua
-- Audit log for all item movements. Immutable append-only ledger.
--
-- transfer_type: 'give' | 'drop' | 'pickup' | 'store' | 'retrieve' |
--                'admin_create' | 'admin_delete'
--
-- transfer_from_type / transfer_to_type use the same owner_type vocabulary as
-- inventory_items (character, container, ground, etc.). NULL when not applicable
-- (e.g. from is NULL on admin_create, to is NULL on admin_delete).
--
-- DATE columns are stored as TEXT in ISO 8601 format.

ItemTransferModel = Model.define("item_transfers", {
    { name = "transfer_id",           type = "INTEGER", primary = true, autoIncrement = true },

    -- Transfer action type.
    { name = "transfer_type",         type = "TEXT",    notNull = true },

    -- FK to item_definitions.item_def_id (what type of item moved).
    { name = "transfer_item_def_id",  type = "INTEGER", notNull = true },

    -- How many units moved.
    { name = "transfer_amount",       type = "INTEGER", notNull = true },

    -- Source owner (NULL for creates).
    { name = "transfer_from_type",    type = "TEXT" },
    { name = "transfer_from_id",      type = "INTEGER" },

    -- Destination owner (NULL for deletes).
    { name = "transfer_to_type",      type = "TEXT" },
    { name = "transfer_to_id",        type = "INTEGER" },

    -- Character who initiated the transfer.
    { name = "transfer_character_id", type = "INTEGER", notNull = true },

    { name = "transfer_timestamp",    type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
