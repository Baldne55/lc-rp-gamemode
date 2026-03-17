-- server/utils/item_registry.lua
-- Static item definitions registry. Serves as the single source of truth for
-- all item types. IDs are stable and match the item_definitions DB table.
--
-- Usage:
--   ItemRegistry.get(defId)               -> definition table or nil
--   ItemRegistry.findByName(name)         -> defId or nil (exact match, case-insensitive)
--   ItemRegistry.searchByName(partial)    -> { defId, ... } (partial match, case-insensitive)
--   ItemRegistry.allIds()                 -> { 1, 2, 3, ... }
--   ItemRegistry.generateSerial(def)      -> "WPN-A3K8M2"
--   ItemRegistry.getDefaultMetadata(defId)-> shallow copy of defaultMetadata or nil

ItemRegistry = {}

-- ── Categories ──────────────────────────────────────────────────────────────

ItemRegistry.Categories = {
    WEAPON    = "Weapon",
    AMMO      = "Ammo",
    NARCOTIC  = "Narcotic",
    FOOD      = "Food",
    DRINK     = "Drink",
    MATERIAL  = "Material",
    CONTAINER = "Container",
    CLOTHING  = "Clothing",
    TOOL      = "Tool",
    MISC      = "Miscellaneous",
}

local CAT = ItemRegistry.Categories

-- Human-readable short category names for chat display.
local CATEGORY_DISPLAY = {
    [CAT.WEAPON]    = "Weapon",
    [CAT.AMMO]      = "Ammo",
    [CAT.NARCOTIC]  = "Narcotic",
    [CAT.FOOD]      = "Food",
    [CAT.DRINK]     = "Drink",
    [CAT.MATERIAL]  = "Material",
    [CAT.CONTAINER] = "Container",
    [CAT.CLOTHING]  = "Clothing",
    [CAT.TOOL]      = "Tool",
    [CAT.MISC]      = "Misc",
}

-- Serial prefix per category for auto-generated serial numbers.
local SERIAL_PREFIX = {
    [CAT.WEAPON]   = "WPN",
    [CAT.AMMO]     = "AMM",
    [CAT.NARCOTIC] = "NRC",
    [CAT.FOOD]     = "FOD",
    [CAT.DRINK]    = "DRK",
    [CAT.MATERIAL] = "MAT",
    [CAT.CONTAINER]= "CTN",
    [CAT.CLOTHING] = "CLT",
    [CAT.TOOL]     = "TUL",
    [CAT.MISC]     = "MSC",
}

-- ── Item Definitions ────────────────────────────────────────────────────────
-- Key = item_def_id. Fields mirror the item_definitions DB schema minus the PK.

ItemRegistry.Items = {

    -- ═══════════════════════════════════════════════════════════════════════════
    -- WEAPONS (1-19)
    -- Uses GTA IV engine weapon names. weaponTypeId = engine weapon type integer.
    -- ammoGroup links ranged weapons to their generic ammo category.
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Melee — no serial numbers
    [1]  = { name = "Baseball Bat",         category = CAT.WEAPON,  weight = 0.94, maxStack = 1, isMelee = true, weaponTypeId = 1 },
    [2]  = { name = "Pool Cue",             category = CAT.WEAPON,  weight = 0.60, maxStack = 1, isMelee = true, weaponTypeId = 2 },
    [3]  = { name = "Knife",                category = CAT.WEAPON,  weight = 0.28, maxStack = 1, isMelee = true, weaponTypeId = 3 },

    -- Throwables — no serial numbers
    [4]  = { name = "Grenade",              category = CAT.WEAPON,  weight = 0.40, maxStack = 5, weaponTypeId = 4 },
    [5]  = { name = "Molotov",              category = CAT.WEAPON,  weight = 0.50, maxStack = 5, weaponTypeId = 5 },

    -- Handguns
    [6]  = { name = "Pistol",               category = CAT.WEAPON,  weight = 0.91, maxStack = 1, hasSerial = true, ammoGroup = "pistol",   weaponTypeId = 7 },
    [7]  = { name = "Silenced Pistol",      category = CAT.WEAPON,  weight = 1.10, maxStack = 1, hasSerial = true, ammoGroup = "pistol",   weaponTypeId = 8 },
    [8]  = { name = "Combat Pistol",        category = CAT.WEAPON,  weight = 2.05, maxStack = 1, hasSerial = true, ammoGroup = "pistol",   weaponTypeId = 9 },

    -- Shotguns
    [9]  = { name = "Combat Shotgun",       category = CAT.WEAPON,  weight = 3.82, maxStack = 1, hasSerial = true, ammoGroup = "shotgun",  weaponTypeId = 10 },
    [10] = { name = "Pump Shotgun",         category = CAT.WEAPON,  weight = 3.60, maxStack = 1, hasSerial = true, ammoGroup = "shotgun",  weaponTypeId = 11 },

    -- SMGs
    [11] = { name = "Micro-SMG",            category = CAT.WEAPON,  weight = 1.50, maxStack = 1, hasSerial = true, ammoGroup = "smg",      weaponTypeId = 12 },
    [12] = { name = "SMG",                  category = CAT.WEAPON,  weight = 2.54, maxStack = 1, hasSerial = true, ammoGroup = "smg",      weaponTypeId = 13 },

    -- Rifles
    [13] = { name = "Assault Rifle",        category = CAT.WEAPON,  weight = 3.47, maxStack = 1, hasSerial = true, ammoGroup = "rifle",    weaponTypeId = 14 },
    [14] = { name = "Carbine Rifle",        category = CAT.WEAPON,  weight = 3.40, maxStack = 1, hasSerial = true, ammoGroup = "rifle",    weaponTypeId = 15 },

    -- Snipers
    [15] = { name = "Combat Sniper",        category = CAT.WEAPON,  weight = 8.10, maxStack = 1, hasSerial = true, ammoGroup = "sniper",   weaponTypeId = 16 },
    [16] = { name = "Sniper Rifle",         category = CAT.WEAPON,  weight = 3.90, maxStack = 1, hasSerial = true, ammoGroup = "sniper",   weaponTypeId = 17 },

    -- Heavy
    [17] = { name = "RPG",                  category = CAT.WEAPON,  weight = 6.30, maxStack = 1, hasSerial = true, ammoGroup = "rpg",      weaponTypeId = 18 },
    [18] = { name = "Flamethrower",         category = CAT.WEAPON,  weight = 6.80, maxStack = 1, hasSerial = true, ammoGroup = "flame",    weaponTypeId = 19 },
    [19] = { name = "Minigun",              category = CAT.WEAPON,  weight = 18.0, maxStack = 1, hasSerial = true, ammoGroup = "minigun",  weaponTypeId = 20 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- AMMO (20-27)
    -- One generic ammo type per weapon category.
    -- ═══════════════════════════════════════════════════════════════════════════

    [20] = { name = "Pistol Ammo",          category = CAT.AMMO, weight = 0.008, maxStack = 50,  ammoGroup = "pistol" },
    [21] = { name = "SMG Ammo",             category = CAT.AMMO, weight = 0.008, maxStack = 50,  ammoGroup = "smg" },
    [22] = { name = "Shotgun Ammo",         category = CAT.AMMO, weight = 0.040, maxStack = 25,  ammoGroup = "shotgun" },
    [23] = { name = "Rifle Ammo",           category = CAT.AMMO, weight = 0.012, maxStack = 30,  ammoGroup = "rifle" },
    [24] = { name = "Sniper Ammo",          category = CAT.AMMO, weight = 0.025, maxStack = 20,  ammoGroup = "sniper" },
    [25] = { name = "RPG Rocket",           category = CAT.AMMO, weight = 2.60,  maxStack = 1,   ammoGroup = "rpg" },
    [26] = { name = "Flamethrower Fuel",    category = CAT.AMMO, weight = 1.50,  maxStack = 1,   ammoGroup = "flame" },
    [27] = { name = "Minigun Ammo",         category = CAT.AMMO, weight = 0.010, maxStack = 100, ammoGroup = "minigun" },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- NARCOTICS (28-61)
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Stimulants
    [28]  = { name = "Cocaine Powder",       category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },
    [29]  = { name = "Crack Rock",           category = CAT.NARCOTIC, weight = 0.00025,maxStack = 200, hasPurity = true, hasQuality = true },
    [30]  = { name = "Meth Crystal",         category = CAT.NARCOTIC, weight = 0.0005, maxStack = 200, hasPurity = true, hasQuality = true },
    [31]  = { name = "Amphetamine Powder",   category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },
    [32]  = { name = "Adderall Pill",        category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [33]  = { name = "Bath Salts",           category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },

    -- Opioids
    [34]  = { name = "Heroin Powder",        category = CAT.NARCOTIC, weight = 0.0001, maxStack = 200, hasPurity = true, hasQuality = true },
    [35]  = { name = "Black Tar Heroin",     category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },
    [36]  = { name = "Fentanyl Patch",       category = CAT.NARCOTIC, weight = 0.02,   maxStack = 50,  hasPurity = true, hasQuality = true },
    [37]  = { name = "Codeine Syrup",        category = CAT.NARCOTIC, weight = 0.50,   maxStack = 5,   hasQuality = true },
    [38]  = { name = "Oxycodone Pill",       category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [39]  = { name = "Vicodin Pill",         category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [40]  = { name = "Percocet Pill",        category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [41]  = { name = "Tramadol Pill",        category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [42]  = { name = "Morphine Vial",        category = CAT.NARCOTIC, weight = 0.05,   maxStack = 20,  hasPurity = true, hasQuality = true },

    -- Cannabis
    [43]  = { name = "Marijuana Bud",        category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasQuality = true },
    [44]  = { name = "Joint",                category = CAT.NARCOTIC, weight = 0.0005, maxStack = 100, hasQuality = true },
    [45]  = { name = "Hashish",              category = CAT.NARCOTIC, weight = 0.005,  maxStack = 50,  hasQuality = true },
    [46]  = { name = "THC Oil",              category = CAT.NARCOTIC, weight = 0.03,   maxStack = 20,  hasPurity = true, hasQuality = true },
    [47]  = { name = "Edible",               category = CAT.NARCOTIC, weight = 0.05,   maxStack = 20,  hasQuality = true },
    [48]  = { name = "Spice",                category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasQuality = true },

    -- Psychedelics
    [49]  = { name = "Ecstasy Pill",         category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [50]  = { name = "LSD Tab",              category = CAT.NARCOTIC, weight = 0.001,  maxStack = 200, hasQuality = true },
    [51]  = { name = "Psilocybin Mushrooms", category = CAT.NARCOTIC, weight = 0.0035, maxStack = 50,  hasQuality = true },
    [52]  = { name = "DMT Powder",           category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },
    [53]  = { name = "PCP",                  category = CAT.NARCOTIC, weight = 0.001,  maxStack = 100, hasPurity = true, hasQuality = true },

    -- Depressants / sedatives
    [54]  = { name = "Ketamine Vial",        category = CAT.NARCOTIC, weight = 0.05,   maxStack = 20,  hasPurity = true, hasQuality = true },
    [55]  = { name = "GHB Vial",             category = CAT.NARCOTIC, weight = 0.05,   maxStack = 20,  hasPurity = true, hasQuality = true },
    [56]  = { name = "Xanax Pill",           category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [57]  = { name = "Valium Pill",          category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [58]  = { name = "Rohypnol Pill",        category = CAT.NARCOTIC, weight = 0.0003, maxStack = 200, hasQuality = true },
    [59]  = { name = "Nitrous Canister",     category = CAT.NARCOTIC, weight = 0.08,   maxStack = 20 },

    -- Packaged Narcotics (generic narcotic containers — content unknown by name)
    [60]  = { name = "Baggie",              category = CAT.NARCOTIC, weight = 0.005,  maxStack = 20, isContainer = true, containerSlots = 5,  containerMaxWeight = 0.05 },
    [61]  = { name = "Brick",               category = CAT.NARCOTIC, weight = 0.05,   maxStack = 5,  isContainer = true, containerSlots = 1,  containerMaxWeight = 1.00 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- FOOD (62-81)
    -- ═══════════════════════════════════════════════════════════════════════════

    [62]  = { name = "Burger",               category = CAT.FOOD, weight = 0.30, maxStack = 10, hasQuality = true },
    [63]  = { name = "Pizza Slice",          category = CAT.FOOD, weight = 0.25, maxStack = 10, hasQuality = true },
    [64]  = { name = "Hot Dog",              category = CAT.FOOD, weight = 0.20, maxStack = 10, hasQuality = true },
    [65]  = { name = "Donut",                category = CAT.FOOD, weight = 0.15, maxStack = 10, hasQuality = true },
    [66]  = { name = "Candy Bar",            category = CAT.FOOD, weight = 0.10, maxStack = 20, hasQuality = true },
    [67]  = { name = "Chicken Wings",        category = CAT.FOOD, weight = 0.35, maxStack = 10, hasQuality = true },
    [68]  = { name = "French Fries",         category = CAT.FOOD, weight = 0.20, maxStack = 10, hasQuality = true },
    [69]  = { name = "Taco",                 category = CAT.FOOD, weight = 0.18, maxStack = 10, hasQuality = true },
    [70]  = { name = "Sandwich",             category = CAT.FOOD, weight = 0.25, maxStack = 10, hasQuality = true },
    [71]  = { name = "Salad",                category = CAT.FOOD, weight = 0.30, maxStack = 5,  hasQuality = true },
    [72]  = { name = "Chinese Takeout",      category = CAT.FOOD, weight = 0.40, maxStack = 5,  hasQuality = true },
    [73]  = { name = "Bagel",                category = CAT.FOOD, weight = 0.12, maxStack = 10, hasQuality = true },
    [74]  = { name = "Pretzel",              category = CAT.FOOD, weight = 0.15, maxStack = 10, hasQuality = true },
    [75]  = { name = "Chips",                category = CAT.FOOD, weight = 0.10, maxStack = 20, hasQuality = true },
    [76]  = { name = "Energy Bar",           category = CAT.FOOD, weight = 0.08, maxStack = 20, hasQuality = true },
    [77]  = { name = "Canned Food",          category = CAT.FOOD, weight = 0.35, maxStack = 10, hasQuality = true },
    [78]  = { name = "Burrito",              category = CAT.FOOD, weight = 0.30, maxStack = 10, hasQuality = true },
    [79]  = { name = "Muffin",               category = CAT.FOOD, weight = 0.12, maxStack = 10, hasQuality = true },
    [80]  = { name = "Apple",                category = CAT.FOOD, weight = 0.18, maxStack = 20, hasQuality = true },
    [81]  = { name = "Banana",               category = CAT.FOOD, weight = 0.12, maxStack = 20, hasQuality = true },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- DRINKS (82-97)
    -- ═══════════════════════════════════════════════════════════════════════════

    [82]  = { name = "Water Bottle",         category = CAT.DRINK, weight = 0.50, maxStack = 10 },
    [83]  = { name = "Soda Can",             category = CAT.DRINK, weight = 0.35, maxStack = 10 },
    [84]  = { name = "Beer Bottle",          category = CAT.DRINK, weight = 0.45, maxStack = 10, isAlcoholic = true },
    [85]  = { name = "Whiskey Bottle",       category = CAT.DRINK, weight = 0.80, maxStack = 5,  isAlcoholic = true },
    [86]  = { name = "Coffee Cup",           category = CAT.DRINK, weight = 0.30, maxStack = 5 },
    [87]  = { name = "Energy Drink",         category = CAT.DRINK, weight = 0.35, maxStack = 10 },
    [88]  = { name = "Orange Juice",         category = CAT.DRINK, weight = 0.40, maxStack = 10 },
    [89]  = { name = "Iced Tea",             category = CAT.DRINK, weight = 0.40, maxStack = 10 },
    [90]  = { name = "Wine Bottle",          category = CAT.DRINK, weight = 0.75, maxStack = 5,  isAlcoholic = true },
    [91]  = { name = "Vodka Bottle",         category = CAT.DRINK, weight = 0.75, maxStack = 5,  isAlcoholic = true },
    [92]  = { name = "Rum Bottle",           category = CAT.DRINK, weight = 0.75, maxStack = 5,  isAlcoholic = true },
    [93]  = { name = "Champagne Bottle",     category = CAT.DRINK, weight = 0.80, maxStack = 5,  isAlcoholic = true },
    [94]  = { name = "Tequila Bottle",       category = CAT.DRINK, weight = 0.75, maxStack = 5,  isAlcoholic = true },
    [95]  = { name = "Cognac Bottle",        category = CAT.DRINK, weight = 0.75, maxStack = 5,  isAlcoholic = true },
    [96]  = { name = "Six Pack",             category = CAT.DRINK, weight = 2.10, maxStack = 2,  isAlcoholic = true },
    [97]  = { name = "Milkshake",            category = CAT.DRINK, weight = 0.45, maxStack = 5 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- MATERIALS (98-122)
    -- Includes narcotic production/growing supplies.
    -- ═══════════════════════════════════════════════════════════════════════════

    -- General materials
    [98]  = { name = "Lockpick",             category = CAT.MATERIAL, weight = 0.05, maxStack = 20 },
    [99]  = { name = "Rope",                 category = CAT.MATERIAL, weight = 0.50, maxStack = 5 },
    [100] = { name = "Duct Tape",            category = CAT.MATERIAL, weight = 0.10, maxStack = 10 },
    [101] = { name = "Radio",                category = CAT.MATERIAL, weight = 0.30, maxStack = 1 },
    [102] = { name = "Screwdriver",          category = CAT.MATERIAL, weight = 0.15, maxStack = 5 },
    [103] = { name = "Bolt Cutters",         category = CAT.MATERIAL, weight = 1.20, maxStack = 1 },
    [104] = { name = "Spray Paint",          category = CAT.MATERIAL, weight = 0.35, maxStack = 5 },
    [105] = { name = "Jerry Can",            category = CAT.MATERIAL, weight = 3.50, maxStack = 1 },
    [106] = { name = "Wire",                 category = CAT.MATERIAL, weight = 0.10, maxStack = 20 },
    [107] = { name = "Padlock",              category = CAT.MATERIAL, weight = 0.25, maxStack = 5 },
    [108] = { name = "Binoculars",           category = CAT.MATERIAL, weight = 0.50, maxStack = 1 },
    [109] = { name = "Camera",               category = CAT.MATERIAL, weight = 0.35, maxStack = 1 },
    [110] = { name = "Zip Ties",             category = CAT.MATERIAL, weight = 0.02, maxStack = 50 },

    -- Narcotic production materials
    [111] = { name = "Cannabis Seeds",       category = CAT.MATERIAL, weight = 0.01, maxStack = 50 },
    [112] = { name = "Fertilizer",           category = CAT.MATERIAL, weight = 2.00, maxStack = 5 },
    [113] = { name = "Grow Light",           category = CAT.MATERIAL, weight = 1.50, maxStack = 2 },
    [114] = { name = "Baking Soda",          category = CAT.MATERIAL, weight = 0.50, maxStack = 10 },
    [115] = { name = "Chemical Precursor",   category = CAT.MATERIAL, weight = 1.00, maxStack = 5 },
    [116] = { name = "Lab Beakers",          category = CAT.MATERIAL, weight = 0.80, maxStack = 5 },
    [117] = { name = "Digital Scale",        category = CAT.MATERIAL, weight = 0.20, maxStack = 1 },
    [118] = { name = "Empty Baggies",        category = CAT.MATERIAL, weight = 0.01, maxStack = 100 },
    [119] = { name = "Rolling Papers",       category = CAT.MATERIAL, weight = 0.01, maxStack = 50 },
    [120] = { name = "Pill Press",           category = CAT.MATERIAL, weight = 3.00, maxStack = 1 },
    [121] = { name = "Acetone",              category = CAT.MATERIAL, weight = 0.80, maxStack = 5 },
    [122] = { name = "Vacuum Sealer",        category = CAT.MATERIAL, weight = 1.50, maxStack = 1 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- CONTAINERS (123-154)
    -- ═══════════════════════════════════════════════════════════════════════════

    -- Large carry containers
    [123] = { name = "Duffel Bag",           category = CAT.CONTAINER, weight = 0.80, maxStack = 1, isContainer = true, containerSlots = 15, containerMaxWeight = 25.0 },
    [124] = { name = "Backpack",             category = CAT.CONTAINER, weight = 1.00, maxStack = 1, isContainer = true, containerSlots = 10, containerMaxWeight = 15.0 },
    [125] = { name = "Suitcase",             category = CAT.CONTAINER, weight = 2.50, maxStack = 1, isContainer = true, containerSlots = 8,  containerMaxWeight = 15.0 },
    [126] = { name = "Cardboard Box",        category = CAT.CONTAINER, weight = 0.50, maxStack = 1, isContainer = true, containerSlots = 10, containerMaxWeight = 20.0 },
    [127] = { name = "Briefcase",            category = CAT.CONTAINER, weight = 1.50, maxStack = 1, isContainer = true, containerSlots = 8,  containerMaxWeight = 10.0 },

    -- Medium carry containers
    [128] = { name = "Purse",                category = CAT.CONTAINER, weight = 0.30, maxStack = 1, isContainer = true, containerSlots = 5,  containerMaxWeight = 3.0 },
    [129] = { name = "Shopping Bag",         category = CAT.CONTAINER, weight = 0.05, maxStack = 1, isContainer = true, containerSlots = 5,  containerMaxWeight = 5.0 },
    [130] = { name = "Brown Paper Bag",      category = CAT.CONTAINER, weight = 0.02, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 3.0 },
    [131] = { name = "Plastic Bag",          category = CAT.CONTAINER, weight = 0.02, maxStack = 1, isContainer = true, containerSlots = 4,  containerMaxWeight = 4.0 },
    [132] = { name = "Parcel",               category = CAT.CONTAINER, weight = 0.20, maxStack = 1, isContainer = true, containerSlots = 4,  containerMaxWeight = 5.0 },
    [133] = { name = "Wallet",               category = CAT.CONTAINER, weight = 0.10, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 0.5 },
    [134] = { name = "Document Folder",      category = CAT.CONTAINER, weight = 0.15, maxStack = 1, isContainer = true, containerSlots = 5,  containerMaxWeight = 1.0 },

    -- Ziplock bags (sized)
    [135] = { name = "Ziplock Bag S",        category = CAT.CONTAINER, weight = 0.01, maxStack = 1, isContainer = true, containerSlots = 1,  containerMaxWeight = 0.5 },
    [136] = { name = "Ziplock Bag M",        category = CAT.CONTAINER, weight = 0.02, maxStack = 1, isContainer = true, containerSlots = 2,  containerMaxWeight = 1.0 },
    [137] = { name = "Ziplock Bag L",        category = CAT.CONTAINER, weight = 0.03, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 2.0 },
    [138] = { name = "Ziplock Bag XL",       category = CAT.CONTAINER, weight = 0.04, maxStack = 1, isContainer = true, containerSlots = 4,  containerMaxWeight = 3.0 },

    -- Envelopes (sized)
    [139] = { name = "Envelope S",           category = CAT.CONTAINER, weight = 0.01, maxStack = 1, isContainer = true, containerSlots = 1,  containerMaxWeight = 0.2 },
    [140] = { name = "Envelope M",           category = CAT.CONTAINER, weight = 0.02, maxStack = 1, isContainer = true, containerSlots = 2,  containerMaxWeight = 0.5 },
    [141] = { name = "Envelope L",           category = CAT.CONTAINER, weight = 0.03, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 1.0 },

    -- Small specialty containers
    [142] = { name = "Cigarette Pack",       category = CAT.CONTAINER, weight = 0.05, maxStack = 1, isContainer = true, containerSlots = 20, containerMaxWeight = 0.30 },
    [143] = { name = "Pill Bottle",          category = CAT.CONTAINER, weight = 0.05, maxStack = 1, isContainer = true, containerSlots = 10, containerMaxWeight = 0.10 },
    [144] = { name = "Tic Tac Box",          category = CAT.CONTAINER, weight = 0.03, maxStack = 1, isContainer = true, containerSlots = 5,  containerMaxWeight = 0.05 },
    [145] = { name = "Grinder Jar",          category = CAT.CONTAINER, weight = 0.10, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 0.2 },
    [146] = { name = "Jar",                  category = CAT.CONTAINER, weight = 0.30, maxStack = 1, isContainer = true, containerSlots = 3,  containerMaxWeight = 0.5 },
    [147] = { name = "Soda Can",             category = CAT.CONTAINER, weight = 0.35, maxStack = 1, isContainer = true, containerSlots = 1,  containerMaxWeight = 0.1 },
    [148] = { name = "Foil Wrap",            category = CAT.CONTAINER, weight = 0.01, maxStack = 1, isContainer = true, containerSlots = 1,  containerMaxWeight = 0.5 },
    [149] = { name = "Plastic Wrap",         category = CAT.CONTAINER, weight = 0.01, maxStack = 1, isContainer = true, containerSlots = 1,  containerMaxWeight = 0.5 },

    -- Utility containers
    [150] = { name = "Gun Case",             category = CAT.CONTAINER, weight = 2.00, maxStack = 1, isContainer = true, containerSlots = 2,  containerMaxWeight = 8.0 },
    [151] = { name = "Toolbox",              category = CAT.CONTAINER, weight = 1.50, maxStack = 1, isContainer = true, containerSlots = 6,  containerMaxWeight = 10.0 },
    [152] = { name = "Cooler",               category = CAT.CONTAINER, weight = 1.00, maxStack = 1, isContainer = true, containerSlots = 6,  containerMaxWeight = 8.0 },
    [153] = { name = "Lockbox",              category = CAT.CONTAINER, weight = 3.00, maxStack = 1, isContainer = true, containerSlots = 4,  containerMaxWeight = 12.0 },
    [154] = { name = "Grocery Bag",          category = CAT.CONTAINER, weight = 0.02, maxStack = 1, isContainer = true, containerSlots = 4,  containerMaxWeight = 5.0 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- CLOTHING (155-157)
    -- ═══════════════════════════════════════════════════════════════════════════

    [155] = { name = "Mask",                 category = CAT.CLOTHING, weight = 0.10, maxStack = 1 },
    [156] = { name = "Gloves",               category = CAT.CLOTHING, weight = 0.15, maxStack = 1 },
    [157] = { name = "Body Armor",           category = CAT.CLOTHING, weight = 3.50, maxStack = 1, defaultMetadata = { durability = 100 } },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- TOOLS (158-182)
    -- ═══════════════════════════════════════════════════════════════════════════

    -- General tools
    [158] = { name = "Fishing Rod",          category = CAT.TOOL, weight = 1.00, maxStack = 1 },
    [159] = { name = "Toolkit",              category = CAT.TOOL, weight = 2.00, maxStack = 1 },
    [160] = { name = "Flashlight",           category = CAT.TOOL, weight = 0.30, maxStack = 1 },
    [161] = { name = "Wrench",               category = CAT.TOOL, weight = 0.50, maxStack = 1 },
    [162] = { name = "Fire Extinguisher",    category = CAT.TOOL, weight = 4.50, maxStack = 1 },
    [163] = { name = "Repair Kit",           category = CAT.TOOL, weight = 1.50, maxStack = 1, hasQuality = true },
    [164] = { name = "Walkie-Talkie",        category = CAT.TOOL, weight = 0.35, maxStack = 1 },

    -- Medical tools
    [165] = { name = "First Aid Kit",        category = CAT.TOOL, weight = 0.80, maxStack = 3, hasQuality = true },
    [166] = { name = "Medkit",               category = CAT.TOOL, weight = 1.20, maxStack = 1, hasQuality = true },
    [167] = { name = "Bandage",              category = CAT.TOOL, weight = 0.05, maxStack = 20, hasQuality = true },
    [168] = { name = "Syringe",              category = CAT.TOOL, weight = 0.01, maxStack = 20 },
    [169] = { name = "Blood Bag",            category = CAT.TOOL, weight = 0.50, maxStack = 5 },
    [170] = { name = "Morphine",             category = CAT.TOOL, weight = 0.02, maxStack = 10 },
    [171] = { name = "Adrenaline Shot",      category = CAT.TOOL, weight = 0.03, maxStack = 5 },
    [172] = { name = "Splint",               category = CAT.TOOL, weight = 0.15, maxStack = 10 },
    [173] = { name = "Surgical Kit",         category = CAT.TOOL, weight = 2.50, maxStack = 1, hasQuality = true },
    [174] = { name = "Defibrillator",        category = CAT.TOOL, weight = 4.00, maxStack = 1 },
    [175] = { name = "Oxygen Tank",          category = CAT.TOOL, weight = 5.00, maxStack = 1 },

    -- Electronics / surveillance
    [176] = { name = "Tracker Device",       category = CAT.TOOL, weight = 0.05, maxStack = 5 },
    [177] = { name = "Wire Tap",             category = CAT.TOOL, weight = 0.03, maxStack = 5 },
    [178] = { name = "GPS Tracker",          category = CAT.TOOL, weight = 0.08, maxStack = 5 },
    [179] = { name = "Signal Jammer",        category = CAT.TOOL, weight = 0.80, maxStack = 1 },

    -- Law enforcement / forensic
    [180] = { name = "Evidence Bag",         category = CAT.TOOL, weight = 0.02, maxStack = 20 },
    [181] = { name = "Drug Test Kit",        category = CAT.TOOL, weight = 0.10, maxStack = 10 },
    [182] = { name = "Breathalyzer",         category = CAT.TOOL, weight = 0.20, maxStack = 1 },

    -- ═══════════════════════════════════════════════════════════════════════════
    -- MISCELLANEOUS (183-196)
    -- ═══════════════════════════════════════════════════════════════════════════

    [183] = { name = "Phone",                category = CAT.MISC, weight = 0.20, maxStack = 1, hasSerial = true, defaultMetadata = { phoneNumber = "" } },
    [184] = { name = "GPS Device",           category = CAT.MISC, weight = 0.25, maxStack = 1 },
    [185] = { name = "Driver License",       category = CAT.MISC, weight = 0.01, maxStack = 1, defaultMetadata = { issuedBy = "", expiresAt = "" } },
    [186] = { name = "Weapon License",       category = CAT.MISC, weight = 0.01, maxStack = 1, defaultMetadata = { issuedBy = "", expiresAt = "" } },
    [187] = { name = "Cigar",                category = CAT.MISC, weight = 0.02, maxStack = 10 },
    [188] = { name = "Cigarette",            category = CAT.MISC, weight = 0.01, maxStack = 20 },
    [189] = { name = "Newspaper",            category = CAT.MISC, weight = 0.15, maxStack = 5 },
    [190] = { name = "Playing Cards",        category = CAT.MISC, weight = 0.10, maxStack = 1 },
    [191] = { name = "Dice",                 category = CAT.MISC, weight = 0.02, maxStack = 5 },
    [192] = { name = "Fake ID",              category = CAT.MISC, weight = 0.02, maxStack = 1, defaultMetadata = { fakeName = "", fakeAge = 0 } },
    [193] = { name = "Zippo Lighter",        category = CAT.MISC, weight = 0.06, maxStack = 1 },
    [194] = { name = "Plastic Lighter",      category = CAT.MISC, weight = 0.03, maxStack = 5 },
    [195] = { name = "Pen",                  category = CAT.MISC, weight = 0.01, maxStack = 5 },
    [196] = { name = "Notepad",              category = CAT.MISC, weight = 0.10, maxStack = 1 },
}

-- ── Lookup helpers ──────────────────────────────────────────────────────────

-- Pre-build a lowercase name -> defId index for fast lookups.
local _nameIndex = {}
local _allIds = {}
for id, def in pairs(ItemRegistry.Items) do
    _nameIndex[def.name:lower()] = id
    _allIds[#_allIds + 1] = id
    -- Attach display category name (Lua-only, not persisted).
    def.categoryName = CATEGORY_DISPLAY[def.category] or def.category
end
table.sort(_allIds)

-- Pre-build ammoGroup -> { defId, ... } index for ammo items.
local _ammoGroupIndex = {}
for id, def in pairs(ItemRegistry.Items) do
    if def.ammoGroup and def.category == CAT.AMMO then
        local g = def.ammoGroup
        if not _ammoGroupIndex[g] then _ammoGroupIndex[g] = {} end
        _ammoGroupIndex[g][#_ammoGroupIndex[g] + 1] = id
    end
end

function ItemRegistry.get(defId)
    return ItemRegistry.Items[defId]
end

function ItemRegistry.findByName(name)
    if not name then return nil end
    return _nameIndex[name:lower()]
end

function ItemRegistry.searchByName(partial)
    if not partial then return {} end
    local lower = partial:lower()
    local results = {}
    for id, def in pairs(ItemRegistry.Items) do
        if def.name:lower():find(lower, 1, true) then
            results[#results + 1] = id
        end
    end
    table.sort(results)
    return results
end

function ItemRegistry.allIds()
    return _allIds
end

function ItemRegistry.getAmmoGroupIds(group)
    return _ammoGroupIndex[group] or {}
end

-- ── Default metadata helper ─────────────────────────────────────────────────
-- Returns a shallow copy of the item's defaultMetadata table, or nil.

function ItemRegistry.getDefaultMetadata(defId)
    local def = ItemRegistry.Items[defId]
    if not def or not def.defaultMetadata then return nil end
    local copy = {}
    for k, v in pairs(def.defaultMetadata) do copy[k] = v end
    return copy
end

-- ── Serial generation ───────────────────────────────────────────────────────

local SERIAL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
function ItemRegistry.generateSerial(def)
    local prefix = SERIAL_PREFIX[def.category] or "ITM"
    local t = {}
    for i = 1, 10 do
        local idx = math.random(1, #SERIAL_CHARS)
        t[i] = SERIAL_CHARS:sub(idx, idx)
    end
    return prefix .. "-" .. table.concat(t)
end

-- ── DB seed helper ──────────────────────────────────────────────────────────
-- Returns a flat row table suitable for ItemDefinitionModel.create().
-- Lua-only fields (defaultMetadata, isAlcoholic, isMelee, categoryName) are
-- not included — they exist only in memory.

function ItemRegistry.toDbRow(defId)
    local def = ItemRegistry.Items[defId]
    if not def then return nil end
    return {
        item_def_id                   = defId,
        item_def_category             = def.category,
        item_def_name                 = def.name,
        item_def_description          = def.description or "",
        item_def_weight               = def.weight,
        item_def_max_stack            = def.maxStack or 1,
        item_def_is_container         = (def.isContainer and 1 or 0),
        item_def_container_slots      = def.containerSlots,
        item_def_container_max_weight = def.containerMaxWeight,
        item_def_has_quality          = (def.hasQuality and 1 or 0),
        item_def_has_purity           = (def.hasPurity and 1 or 0),
        item_def_has_serial           = (def.hasSerial and 1 or 0),
    }
end
