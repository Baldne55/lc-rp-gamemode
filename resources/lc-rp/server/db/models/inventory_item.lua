-- models/inventory_item.lua
-- Item instances. Each row is a concrete item (or stack) that exists in the world.
--
-- inv_item_owner_type: 'character' | 'container' | 'ground'
--   Future: 'vehicle_trunk' | 'vehicle_glovebox' | 'property'
--
-- inv_item_owner_id: polymorphic FK
--   character  -> character_id
--   container  -> parent inv_item_id
--   ground     -> dropped_item_id
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.
-- DATE columns are stored as TEXT in ISO 8601 format.

InventoryItemModel = Model.define("inventory_items", {
    { name = "inv_item_id",          type = "INTEGER", primary = true, autoIncrement = true },

    -- FK to item_definitions.item_def_id.
    { name = "inv_item_def_id",      type = "INTEGER", notNull = true },

    -- Polymorphic owner type.
    { name = "inv_item_owner_type",  type = "TEXT",    notNull = true },

    -- ID of the owning entity (meaning depends on owner_type).
    { name = "inv_item_owner_id",    type = "INTEGER", notNull = true },

    -- Slot position within the owner's storage.
    { name = "inv_item_slot",        type = "INTEGER", notNull = true },

    -- Stack count. Always 1 for non-stackable items.
    { name = "inv_item_amount",      type = "INTEGER", notNull = true, default = 1 },

    -- Player-assigned custom name. NULL = use definition default.
    { name = "inv_item_custom_name", type = "TEXT" },

    -- Quality rating 0-100. NULL when the item type doesn't track quality.
    { name = "inv_item_quality",     type = "INTEGER" },

    -- Purity rating 0-100. NULL when the item type doesn't track purity.
    { name = "inv_item_purity",      type = "INTEGER" },

    -- Unique serial string (e.g. "WPN-A8K3M2"). NULL when not applicable.
    { name = "inv_item_serial",      type = "TEXT" },

    -- JSON blob for extensible per-instance data (attachments, expiry, etc.).
    { name = "inv_item_metadata",    type = "TEXT" },

    { name = "inv_item_created_at",  type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
    { name = "inv_item_updated_at",  type = "TEXT",    notNull = true, defaultRaw = "CURRENT_TIMESTAMP" },
})
