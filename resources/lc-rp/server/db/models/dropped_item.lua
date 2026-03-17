-- models/dropped_item.lua
-- Position data for items dropped on the ground.
-- Each row links to an inventory_item (with owner_type = 'ground').
--
-- DATE columns are stored as TEXT in ISO 8601 format.

DroppedItemModel = Model.define("dropped_items", {
    { name = "dropped_item_id",         type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to inventory_items.inv_item_id.
    { name = "dropped_item_inv_id",     type = "INTEGER", notNull = true },

    -- World/session ID the item was dropped in.
    { name = "dropped_item_session",    type = "INTEGER", notNull = true },

    { name = "dropped_item_x",          type = "REAL",    notNull = true },
    { name = "dropped_item_y",          type = "REAL",    notNull = true },
    { name = "dropped_item_z",          type = "REAL",    notNull = true },

    -- Character who dropped the item.
    { name = "dropped_item_dropped_by", type = "INTEGER", notNull = true },

    -- Account that owns the character who dropped the item (prevents cross-char pickup on same account).
    { name = "dropped_item_account_id", type = "INTEGER", notNull = true },

    { name = "dropped_item_dropped_at", type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
