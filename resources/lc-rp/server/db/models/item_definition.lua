-- models/item_definition.lua
-- Master item catalog. Each row defines a type of item that can exist in the game.
--
-- item_def_category: 'Weapon' | 'Ammo' | 'Narcotic' | 'Food' | 'Drink' |
--                    'Material' | 'Container' | 'Clothing' | 'Tool' | 'Miscellaneous'
--
-- BOOLEAN columns are stored as INTEGER (0 = false, 1 = true) for SQLite compatibility.

ItemDefinitionModel = Model.define("item_definitions", {
    { name = "item_def_id",                   type = "INTEGER", primary = true, autoIncrement = true },

    { name = "item_def_category",             type = "TEXT",    notNull = true },

    { name = "item_def_name",                 type = "TEXT",    notNull = true },

    { name = "item_def_description",          type = "TEXT" },

    -- Weight per unit in kg.
    { name = "item_def_weight",               type = "REAL",    notNull = true },

    -- Max stack size. 1 = non-stackable (e.g. weapons).
    { name = "item_def_max_stack",            type = "INTEGER", notNull = true, default = 1 },

    -- Whether this item type acts as a container (backpack, bag, etc.).
    { name = "item_def_is_container",         type = "INTEGER", notNull = true, default = 0 },

    -- Number of slots inside the container. NULL for non-containers.
    { name = "item_def_container_slots",      type = "INTEGER" },

    -- Max weight capacity of the container in kg. NULL for non-containers.
    { name = "item_def_container_max_weight", type = "REAL" },

    -- Whether instances of this item track quality (0-100).
    { name = "item_def_has_quality",          type = "INTEGER", notNull = true, default = 0 },

    -- Whether instances of this item track purity (0-100).
    { name = "item_def_has_purity",           type = "INTEGER", notNull = true, default = 0 },

    -- Whether instances of this item receive auto-generated serial numbers.
    { name = "item_def_has_serial",           type = "INTEGER", notNull = true, default = 0 },
})
