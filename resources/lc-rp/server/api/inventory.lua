-- server/api/inventory.lua
-- Server-authoritative inventory API. All inventory mutations go through here.
--
-- In-memory caches:
--   _invCache[charId]  = { [slot] = itemRow, ... }   -- loaded on char select
--   _dropCache[dropId] = { invItem = ..., drop = ... } -- loaded on server start
--
-- All public functions follow the async callback pattern:
--   cb(result)           on success
--   cb(nil, errorMsg)    on failure

Inventory = {}

local _LOG_TAG = "Inventory"
local _invCache  = {}   -- { [charId] = { [slot] = row, ... } }
local _dropCache = {}   -- { [droppedItemId] = { invItem = row, drop = row } }

-- M7: Track drop timestamps for periodic cleanup.
local _dropTimestamps = {} -- { [droppedItemId] = os.time() }
local DROP_EXPIRY_SECONDS = 3600  -- 1 hour

-- Per-item operation lock to prevent race conditions during partial transfers.
-- While an item is being modified (split, give, drop, store, retrieve), concurrent
-- operations on the same item are rejected.
local _itemLocks = {} -- { [inv_item_id] = true }

local function lockItem(itemId)
    if _itemLocks[itemId] then return false end
    _itemLocks[itemId] = true
    return true
end

local function unlockItem(itemId)
    _itemLocks[itemId] = nil
end

local function now()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

-- ── Drop label helpers ──────────────────────────────────────────────────────

local function formatDropLabel(dropId, invItem)
    local def = ItemRegistry.get(invItem.inv_item_def_id)
    local name = invItem.inv_item_custom_name or (def and def.name) or "Unknown"
    return "Item (ID: " .. dropId .. "): " .. name .. " (x" .. invItem.inv_item_amount .. ")"
end

local function broadcastDropToSession(session, dropId, x, y, z, text)
    for serverID, _ in Players.all() do
        if Player.IsConnected(serverID) then
            local ok, s = pcall(Player.GetSession, serverID)
            if ok and s == session then
                Events.CallRemote("inv_drop_add", serverID, { dropId, x, y, z, text })
            end
        end
    end
end

local function broadcastDropRemoveToSession(session, dropId)
    for serverID, _ in Players.all() do
        if Player.IsConnected(serverID) then
            local ok, s = pcall(Player.GetSession, serverID)
            if ok and s == session then
                Events.CallRemote("inv_drop_remove", serverID, { dropId })
            end
        end
    end
end

-- M7: Remove expired drops from cache and DB.
function Inventory.cleanupExpiredDrops()
    local now = os.time()
    local expired = {}
    for dropId, ts in pairs(_dropTimestamps) do
        if (now - ts) > DROP_EXPIRY_SECONDS then
            expired[#expired + 1] = dropId
        end
    end
    for _, dropId in ipairs(expired) do
        local cached = _dropCache[dropId]
        if cached then
            local session = cached.drop.dropped_item_session
            local invItemId = cached.invItem.inv_item_id
            _dropCache[dropId] = nil
            _dropTimestamps[dropId] = nil
            -- Delete container contents before deleting the container itself.
            local expDef = ItemRegistry.get(cached.invItem.inv_item_def_id)
            if expDef and expDef.isContainer then
                InventoryItemModel.delete({ inv_item_owner_type = "container", inv_item_owner_id = invItemId })
            end
            InventoryItemModel.delete({ inv_item_id = invItemId })
            DroppedItemModel.delete({ dropped_item_id = dropId })
            broadcastDropRemoveToSession(session, dropId)
        else
            _dropTimestamps[dropId] = nil
        end
    end
    if #expired > 0 then
        Log.info(_LOG_TAG, "Cleaned up " .. #expired .. " expired drop(s).")
    end
end

function Inventory.syncDropsForPlayer(serverID)
    local ok, session = pcall(Player.GetSession, serverID)
    if not ok then return end
    local items = {}
    for dropId, cached in pairs(_dropCache) do
        if cached.drop.dropped_item_session == session then
            local text = formatDropLabel(dropId, cached.invItem)
            items[#items + 1] = { dropId, cached.drop.dropped_item_x, cached.drop.dropped_item_y, cached.drop.dropped_item_z, text }
        end
    end
    Events.CallRemote("inv_drop_sync", serverID, items)
end

-- ── Cache accessors ─────────────────────────────────────────────────────────

function Inventory.getInventory(charId)
    return _invCache[charId]
end

function Inventory.getDroppedItems()
    return _dropCache
end

function Inventory.getDroppedItem(dropId)
    return _dropCache[dropId]
end

-- ── Weight & slot helpers ───────────────────────────────────────────────────

function Inventory.getWeight(charId)
    local inv = _invCache[charId]
    if not inv then return 0 end
    local total = 0
    for slot, item in pairs(inv) do
        if type(slot) == "number" then
            local def = ItemRegistry.get(item.inv_item_def_id)
            if def then
                total = total + (def.weight * item.inv_item_amount)
                if def.isContainer then
                    total = total + Inventory.getContainerContentWeight(charId, item.inv_item_id)
                end
            end
        end
    end
    return total
end

function Inventory.getContainerContentWeight(charId, containerInvId)
    local inv = _invCache[charId]
    if not inv or not inv._containers then return 0 end
    local contents = inv._containers[containerInvId]
    if not contents then return 0 end
    local total = 0
    for _, item in pairs(contents) do
        local def = ItemRegistry.get(item.inv_item_def_id)
        if def then total = total + (def.weight * item.inv_item_amount) end
    end
    return total
end

function Inventory.getSlotCount(charId)
    local inv = _invCache[charId]
    if not inv then return 0 end
    local count = 0
    for slot in pairs(inv) do
        if type(slot) == "number" then count = count + 1 end
    end
    return count
end

function Inventory.findFreeSlot(charId)
    local inv = _invCache[charId]
    if not inv then return 1 end
    local maxSlots = Config.INVENTORY.MAX_SLOTS
    for slot = 1, maxSlots do
        if not inv[slot] then return slot end
    end
    return nil
end

function Inventory.getItemAtSlot(charId, slot)
    local inv = _invCache[charId]
    if not inv then return nil end
    return inv[slot]
end

-- Returns (slot, item) for the first inventory item matching defId, or nil.
function Inventory.findItemByDefId(charId, defId)
    local inv = _invCache[charId]
    if not inv then return nil end
    for slot, item in pairs(inv) do
        if type(slot) == "number" and item.inv_item_def_id == defId then
            return slot, item
        end
    end
    return nil
end

-- Returns (firstSlot, firstItem, totalAmmo) for all ammo matching the group, or nil.
function Inventory.findAmmoByGroup(charId, ammoGroup)
    local ids = ItemRegistry.getAmmoGroupIds(ammoGroup)
    if #ids == 0 then return nil end
    local idSet = {}
    for _, id in ipairs(ids) do idSet[id] = true end

    local inv = _invCache[charId]
    if not inv then return nil end

    local firstSlot, firstItem, total = nil, nil, 0
    for slot, item in pairs(inv) do
        if type(slot) == "number" and idSet[item.inv_item_def_id] then
            total = total + (item.inv_item_amount or 1)
            if not firstSlot then
                firstSlot = slot
                firstItem = item
            end
        end
    end
    if total == 0 then return nil end
    return firstSlot, firstItem, total
end

-- Consumes `amount` rounds of ammo matching `ammoGroup` from the character's
-- inventory (FIFO across slots). Calls callback(newTotal) on success, or
-- callback(nil, err) on failure.
function Inventory.consumeAmmoByGroup(charId, ammoGroup, amount, callback)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end

    local ids = ItemRegistry.getAmmoGroupIds(ammoGroup)
    if #ids == 0 then
        if callback then callback(nil, "Unknown ammo group.") end
        return
    end
    local idSet = {}
    for _, id in ipairs(ids) do idSet[id] = true end

    local inv = _invCache[charId]
    if not inv then
        if callback then callback(nil, "No inventory loaded.") end
        return
    end

    -- Collect all matching ammo slots sorted by slot number (FIFO).
    local ammoSlots = {}
    local totalAvailable = 0
    for slot, item in pairs(inv) do
        if type(slot) == "number" and idSet[item.inv_item_def_id] then
            ammoSlots[#ammoSlots + 1] = { slot = slot, item = item }
            totalAvailable = totalAvailable + (item.inv_item_amount or 1)
        end
    end
    table.sort(ammoSlots, function(a, b) return a.slot < b.slot end)

    if totalAvailable < amount then
        if callback then callback(nil, "Not enough ammo (have " .. totalAvailable .. ", need " .. amount .. ").") end
        return
    end

    -- Consume FIFO: remove from first slot, then next, until `amount` is satisfied.
    local remaining = amount
    local idx = 1
    local ts = now()

    local function consumeNext()
        if remaining <= 0 then
            -- Done. Calculate new total.
            local newTotal = totalAvailable - amount
            if callback then callback(newTotal) end
            return
        end
        if idx > #ammoSlots then
            -- Should not happen (we checked totalAvailable), but guard anyway.
            if callback then callback(nil, "Ammo slots exhausted unexpectedly.") end
            return
        end

        local entry = ammoSlots[idx]
        local item = entry.item
        local slot = entry.slot
        local have = item.inv_item_amount or 1
        idx = idx + 1

        if remaining >= have then
            -- Full removal of this slot.
            remaining = remaining - have
            Inventory.logTransfer("ammo_consume", item.inv_item_def_id, have, "character", charId, nil, nil, charId)
            InventoryItemModel.delete({ inv_item_id = item.inv_item_id }, function()
                inv[slot] = nil
                consumeNext()
            end)
        else
            -- Partial removal from this slot.
            local newAmount = have - remaining
            Inventory.logTransfer("ammo_consume", item.inv_item_def_id, remaining, "character", charId, nil, nil, charId)
            remaining = 0
            InventoryItemModel.update(
                { inv_item_amount = newAmount, inv_item_updated_at = ts },
                { inv_item_id = item.inv_item_id },
                function()
                    item.inv_item_amount = newAmount
                    item.inv_item_updated_at = ts
                    consumeNext()
                end
            )
        end
    end

    consumeNext()
end

-- Adds ammo back to inventory in maxStack-sized batches. Uses the first
-- definition in the ammo group. Calls callback(true) on success, or
-- callback(nil, err) on first failure.
function Inventory.returnAmmoByGroup(charId, ammoGroup, amount, callback)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(true) end
        return
    end

    local ammoDefIds = ItemRegistry.getAmmoGroupIds(ammoGroup)
    if #ammoDefIds == 0 then
        if callback then callback(nil, "Unknown ammo group.") end
        return
    end
    local defId = ammoDefIds[1]
    local def = ItemRegistry.get(defId)
    local maxStack = (def and def.maxStack > 1 and def.maxStack) or amount

    local function addBatch(remaining)
        if remaining <= 0 then
            if callback then callback(true) end
            return
        end
        local batch = math.min(remaining, maxStack)
        Inventory.addItem(charId, defId, batch, {}, function(result, err)
            if not result then
                if callback then callback(nil, err) end
                return
            end
            addBatch(remaining - batch)
        end)
    end

    addBatch(amount)
end

-- Find a stackable slot for the given item def and return it, or nil.
-- quality/purity must match exactly (including nil) to prevent data loss.
function Inventory.findStackableSlot(charId, defId, amount, quality, purity)
    local inv = _invCache[charId]
    if not inv then return nil end
    local def = ItemRegistry.get(defId)
    if not def or def.maxStack <= 1 then return nil end
    for slot, item in pairs(inv) do
        if type(slot) == "number"
            and item.inv_item_def_id == defId
            and item.inv_item_owner_type == "character"
            and (item.inv_item_amount + amount) <= def.maxStack
            and item.inv_item_quality == quality
            and item.inv_item_purity == purity then
            return slot
        end
    end
    return nil
end

-- ── Transfer logging ────────────────────────────────────────────────────────

-- L12: Add error logging to transfer audit writes.
function Inventory.logTransfer(transferType, defId, amount, fromType, fromId, toType, toId, charId)
    ItemTransferModel.create({
        transfer_type         = transferType,
        transfer_item_def_id  = defId,
        transfer_amount       = amount,
        transfer_from_type    = fromType,
        transfer_from_id      = fromId,
        transfer_to_type      = toType,
        transfer_to_id        = toId,
        transfer_character_id = charId,
    }, function(id)
        if not id then
            Log.error(_LOG_TAG, "Failed to write transfer log: " .. tostring(transferType) .. " defId=" .. tostring(defId) .. " amount=" .. tostring(amount))
        end
    end)
end

-- ── Load / Save ─────────────────────────────────────────────────────────────

function Inventory.loadForCharacter(charId, callback)
    InventoryItemModel.findAll({ inv_item_owner_type = "character", inv_item_owner_id = charId }, function(rows)
        _invCache[charId] = {}
        for _, row in ipairs(rows) do
            _invCache[charId][row.inv_item_slot] = row
        end
        -- Also load items inside containers owned by this character.
        Inventory._loadContainerContents(charId, function()
            Log.info(_LOG_TAG, "Loaded inventory for character " .. charId .. " (" .. Inventory.getSlotCount(charId) .. " items)")
            if callback then callback() end
        end)
    end)
end

function Inventory._loadContainerContents(charId, callback)
    local inv = _invCache[charId]
    if not inv then
        if callback then callback() end
        return
    end
    -- Find all container items in this character's inventory.
    local containerIds = {}
    for slot, item in pairs(inv) do
        if type(slot) == "number" then
            local def = ItemRegistry.get(item.inv_item_def_id)
            if def and def.isContainer then
                containerIds[#containerIds + 1] = item.inv_item_id
            end
        end
    end
    if #containerIds == 0 then
        if callback then callback() end
        return
    end
    -- Load container contents one by one (async chain).
    local loaded = 0
    for _, cid in ipairs(containerIds) do
        InventoryItemModel.findAll({ inv_item_owner_type = "container", inv_item_owner_id = cid }, function(rows)
            -- M12: Guard against disconnected player during async load.
            if not _invCache[charId] then
                loaded = loaded + 1
                if loaded == #containerIds and callback then callback() end
                return
            end
            if not _invCache[charId]._containers then
                _invCache[charId]._containers = {}
            end
            _invCache[charId]._containers[cid] = {}
            for _, row in ipairs(rows) do
                _invCache[charId]._containers[cid][row.inv_item_slot] = row
            end
            loaded = loaded + 1
            if loaded == #containerIds and callback then callback() end
        end)
    end
end

function Inventory.unloadForCharacter(charId)
    _invCache[charId] = nil
end

function Inventory.loadDroppedItems(callback)
    DroppedItemModel.findAll({}, function(drops)
        _dropCache = {}
        if not drops or #drops == 0 then
            Log.info(_LOG_TAG, "No dropped items to load.")
            if callback then callback() end
            return
        end
        local loaded = 0
        local orphans = 0
        for _, drop in ipairs(drops) do
            InventoryItemModel.findOne({ inv_item_id = drop.dropped_item_inv_id }, function(invItem)
                if invItem then
                    _dropCache[drop.dropped_item_id] = { invItem = invItem, drop = drop }
                    _dropTimestamps[drop.dropped_item_id] = os.time()
                else
                    orphans = orphans + 1
                    DroppedItemModel.delete({ dropped_item_id = drop.dropped_item_id })
                end
                loaded = loaded + 1
                if loaded == #drops then
                    if orphans > 0 then
                        Log.info(_LOG_TAG, "Cleaned up " .. orphans .. " orphaned drop record(s).")
                    end
                    Log.info(_LOG_TAG, "Loaded " .. (#drops - orphans) .. " dropped item(s).")
                    if callback then callback() end
                end
            end)
        end
    end)
end

-- ── Add item ────────────────────────────────────────────────────────────────
-- opts: { customName, quality, purity, serial, metadata }

function Inventory.addItem(charId, defId, amount, opts, callback)
    local def = ItemRegistry.get(defId)
    if not def then
        if callback then callback(nil, "Unknown item definition.") end
        return
    end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    opts = opts or {}

    local addWeight = def.weight * amount
    local currentWeight = Inventory.getWeight(charId)
    if currentWeight + addWeight > Config.INVENTORY.MAX_CARRY_WEIGHT then
        if callback then callback(nil, "Too heavy. You cannot carry that much.") end
        return
    end

    -- Try stacking first (only if no special opts like serial/custom name).
    local canStack = def.maxStack > 1 and not opts.serial and not opts.customName
    if canStack then
        local stackQuality = (def.hasQuality and opts.quality) or nil
        local stackPurity  = (def.hasPurity and opts.purity) or nil
        local stackSlot = Inventory.findStackableSlot(charId, defId, amount, stackQuality, stackPurity)
        if stackSlot then
            local existing = _invCache[charId][stackSlot]
            local newAmount = existing.inv_item_amount + amount
            local stackTs = now()
            InventoryItemModel.update(
                { inv_item_amount = newAmount, inv_item_updated_at = stackTs },
                { inv_item_id = existing.inv_item_id },
                function()
                    existing.inv_item_amount = newAmount
                    existing.inv_item_updated_at = stackTs
                    if callback then callback(existing) end
                end
            )
            return
        end
    end

    local slot = Inventory.findFreeSlot(charId)
    if not slot then
        if callback then callback(nil, "Inventory is full.") end
        return
    end

    local serial = opts.serial
    if not serial and def.hasSerial then
        serial = ItemRegistry.generateSerial(def)
    end

    local ts = now()
    local row = {
        inv_item_def_id      = defId,
        inv_item_owner_type  = "character",
        inv_item_owner_id    = charId,
        inv_item_slot        = slot,
        inv_item_amount      = amount,
        inv_item_custom_name = opts.customName,
        inv_item_quality     = (def.hasQuality and opts.quality) or nil,
        inv_item_purity      = (def.hasPurity and opts.purity) or nil,
        inv_item_serial      = serial,
        inv_item_metadata    = opts.metadata,
        inv_item_created_at  = ts,
        inv_item_updated_at  = ts,
    }

    InventoryItemModel.create(row, function(newId)
        if not newId then
            if callback then callback(nil, "Failed to create item.") end
            return
        end
        row.inv_item_id = newId
        -- M11: Only populate cache if the character is still loaded.
        if _invCache[charId] then
            _invCache[charId][slot] = row
        end
        if callback then callback(row) end
    end)
end

-- ── Remove item ─────────────────────────────────────────────────────────────

function Inventory.removeItem(charId, slot, amount, callback)
    local inv = _invCache[charId]
    if not inv or not inv[slot] then
        if callback then callback(nil, "No item in that slot.") end
        return
    end
    local item = inv[slot]
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    if amount > item.inv_item_amount then
        if callback then callback(nil, "Not enough items (have " .. item.inv_item_amount .. ").") end
        return
    end

    if amount == item.inv_item_amount then
        -- Full removal: clean up container children first, then DB delete, then cache.
        local def = ItemRegistry.get(item.inv_item_def_id)
        local containerId = item.inv_item_id
        local function doDelete()
            InventoryItemModel.delete({ inv_item_id = item.inv_item_id }, function()
                inv[slot] = nil
                if callback then callback(true) end
            end)
        end
        if def and def.isContainer then
            InventoryItemModel.delete({ inv_item_owner_type = "container", inv_item_owner_id = containerId }, function()
                if inv._containers then inv._containers[containerId] = nil end
                doDelete()
            end)
        else
            doDelete()
        end
    else
        local ts = now()
        local newAmount = item.inv_item_amount - amount
        InventoryItemModel.update(
            { inv_item_amount = newAmount, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_amount = newAmount
                item.inv_item_updated_at = ts
                if callback then callback(true) end
            end
        )
    end
end

-- ── Give item (player to player) ────────────────────────────────────────────

function Inventory.giveItem(fromCharId, toCharId, slot, amount, callback)
    local fromInv = _invCache[fromCharId]
    if not fromInv or not fromInv[slot] then
        if callback then callback(nil, "No item in that slot.") end
        return
    end
    local item = fromInv[slot]
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    if amount > item.inv_item_amount then
        if callback then callback(nil, "Not enough items (have " .. item.inv_item_amount .. ").") end
        return
    end

    -- Prevent concurrent modifications on the same item.
    if not lockItem(item.inv_item_id) then
        if callback then callback(nil, "This item is being modified, please wait.") end
        return
    end

    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def then
        unlockItem(item.inv_item_id)
        if callback then callback(nil, "Unknown item.") end
        return
    end

    -- Check receiver capacity (include container contents weight).
    local addWeight = def.weight * amount
    if def.isContainer and amount == item.inv_item_amount then
        addWeight = addWeight + Inventory.getContainerContentWeight(fromCharId, item.inv_item_id)
    end
    local recvWeight = Inventory.getWeight(toCharId)
    if recvWeight + addWeight > Config.INVENTORY.MAX_CARRY_WEIGHT then
        unlockItem(item.inv_item_id)
        if callback then callback(nil, "Receiver cannot carry that much weight.") end
        return
    end

    -- If giving entire stack, transfer the row directly.
    local ts = now()
    if amount == item.inv_item_amount then
        local toSlot = Inventory.findFreeSlot(toCharId)
        if not toSlot then
            unlockItem(item.inv_item_id)
            if callback then callback(nil, "Receiver's inventory is full.") end
            return
        end
        InventoryItemModel.update(
            { inv_item_owner_id = toCharId, inv_item_slot = toSlot, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                fromInv[slot] = nil
                item.inv_item_owner_id = toCharId
                item.inv_item_slot = toSlot
                item.inv_item_updated_at = ts
                if not _invCache[toCharId] then _invCache[toCharId] = {} end
                _invCache[toCharId][toSlot] = item
                -- Transfer container contents cache if the item is a container.
                local def = ItemRegistry.get(item.inv_item_def_id)
                if def and def.isContainer then
                    local cid = item.inv_item_id
                    if fromInv._containers and fromInv._containers[cid] then
                        if not _invCache[toCharId]._containers then _invCache[toCharId]._containers = {} end
                        _invCache[toCharId]._containers[cid] = fromInv._containers[cid]
                        fromInv._containers[cid] = nil
                    end
                end
                unlockItem(item.inv_item_id)
                Inventory.logTransfer("give", item.inv_item_def_id, amount, "character", fromCharId, "character", toCharId, fromCharId)
                if callback then callback(true) end
            end
        )
    else
        -- Partial stack: reduce sender in DB first, then update cache on success.
        local newSenderAmount = item.inv_item_amount - amount
        InventoryItemModel.update(
            { inv_item_amount = newSenderAmount, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_amount = newSenderAmount
                item.inv_item_updated_at = ts
                Inventory.addItem(toCharId, item.inv_item_def_id, amount, {
                    customName = item.inv_item_custom_name,
                    quality    = item.inv_item_quality,
                    purity     = item.inv_item_purity,
                    metadata   = item.inv_item_metadata,
                }, function(newItem, err)
                    if not newItem then
                        -- Rollback: restore DB first, then update cache to stay consistent.
                        local restoredAmount = item.inv_item_amount + amount
                        InventoryItemModel.update(
                            { inv_item_amount = restoredAmount },
                            { inv_item_id = item.inv_item_id },
                            function()
                                item.inv_item_amount = restoredAmount
                                unlockItem(item.inv_item_id)
                                if callback then callback(nil, err or "Failed to give item.") end
                            end
                        )
                        return
                    end
                    unlockItem(item.inv_item_id)
                    Inventory.logTransfer("give", item.inv_item_def_id, amount, "character", fromCharId, "character", toCharId, fromCharId)
                    if callback then callback(true) end
                end)
            end
        )
    end
end

-- ── Drop item ───────────────────────────────────────────────────────────────

function Inventory.dropItem(charId, slot, amount, position, session, accountId, callback)
    local inv = _invCache[charId]
    if not inv or not inv[slot] then
        if callback then callback(nil, "No item in that slot.") end
        return
    end
    local item = inv[slot]
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    if amount > item.inv_item_amount then
        if callback then callback(nil, "Not enough items (have " .. item.inv_item_amount .. ").") end
        return
    end

    -- Prevent concurrent modifications on the same item.
    if not lockItem(item.inv_item_id) then
        if callback then callback(nil, "This item is being modified, please wait.") end
        return
    end

    local defId = item.inv_item_def_id
    local ts = now()

    local function finalizeDrop(droppedInvItem, removeFromSlot)
        DroppedItemModel.create({
            dropped_item_inv_id     = droppedInvItem.inv_item_id,
            dropped_item_session    = session,
            dropped_item_x          = position.x,
            dropped_item_y          = position.y,
            dropped_item_z          = position.z + (Config.INVENTORY.DROP_OFFSET_Z or 0),
            dropped_item_dropped_by = charId,
            dropped_item_account_id = accountId,
        }, function(dropId)
            if not dropId then
                unlockItem(item.inv_item_id)
                if callback then callback(nil, "Failed to create drop record.") end
                return
            end
            InventoryItemModel.update(
                { inv_item_owner_type = "ground", inv_item_owner_id = dropId, inv_item_updated_at = ts },
                { inv_item_id = droppedInvItem.inv_item_id },
                function()
                    droppedInvItem.inv_item_owner_type = "ground"
                    droppedInvItem.inv_item_owner_id   = dropId
                    droppedInvItem.inv_item_updated_at = ts
                    if removeFromSlot then
                        inv[removeFromSlot] = nil
                        -- Clean container contents from dropper's cache.
                        if inv._containers then
                            local dropDef = ItemRegistry.get(droppedInvItem.inv_item_def_id)
                            if dropDef and dropDef.isContainer then
                                inv._containers[droppedInvItem.inv_item_id] = nil
                            end
                        end
                    end
                    _dropTimestamps[dropId] = os.time()
                    _dropCache[dropId] = {
                        invItem = droppedInvItem,
                        drop = {
                            dropped_item_id         = dropId,
                            dropped_item_inv_id     = droppedInvItem.inv_item_id,
                            dropped_item_session    = session,
                            dropped_item_x          = position.x,
                            dropped_item_y          = position.y,
                            dropped_item_z          = position.z + (Config.INVENTORY.DROP_OFFSET_Z or 0),
                            dropped_item_dropped_by = charId,
                            dropped_item_account_id = accountId,
                            dropped_item_dropped_at = ts,
                        },
                    }
                    unlockItem(item.inv_item_id)
                    Inventory.logTransfer("drop", defId, amount, "character", charId, "ground", dropId, charId)
                    broadcastDropToSession(session, dropId,
                        position.x, position.y, position.z + (Config.INVENTORY.DROP_OFFSET_Z or 0),
                        formatDropLabel(dropId, droppedInvItem))
                    if callback then callback(dropId) end
                end
            )
        end)
    end

    if amount == item.inv_item_amount then
        finalizeDrop(item, slot)
    else
        -- Partial drop: decrement source in DB, then create split row inside callback.
        local newAmount = item.inv_item_amount - amount
        InventoryItemModel.update(
            { inv_item_amount = newAmount, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_amount = newAmount
                item.inv_item_updated_at = ts
                InventoryItemModel.create({
                    inv_item_def_id      = defId,
                    inv_item_owner_type  = "ground",
                    inv_item_owner_id    = 0,
                    inv_item_slot        = 0,
                    inv_item_amount      = amount,
                    inv_item_custom_name = item.inv_item_custom_name,
                    inv_item_quality     = item.inv_item_quality,
                    inv_item_purity      = item.inv_item_purity,
                    inv_item_metadata    = item.inv_item_metadata,
                    inv_item_created_at  = ts,
                    inv_item_updated_at  = ts,
                }, function(newId)
                    if not newId then
                        -- Rollback: restore DB first, then update cache.
                        local restoredAmount = item.inv_item_amount + amount
                        InventoryItemModel.update(
                            { inv_item_amount = restoredAmount },
                            { inv_item_id = item.inv_item_id },
                            function()
                                item.inv_item_amount = restoredAmount
                                unlockItem(item.inv_item_id)
                                if callback then callback(nil, "Failed to split stack for drop.") end
                            end
                        )
                        return
                    end
                    local newRow = {
                        inv_item_id          = newId,
                        inv_item_def_id      = defId,
                        inv_item_owner_type  = "ground",
                        inv_item_owner_id    = 0,
                        inv_item_slot        = 0,
                        inv_item_amount      = amount,
                        inv_item_custom_name = item.inv_item_custom_name,
                        inv_item_quality     = item.inv_item_quality,
                        inv_item_purity      = item.inv_item_purity,
                        inv_item_metadata    = item.inv_item_metadata,
                        inv_item_created_at  = ts,
                        inv_item_updated_at  = ts,
                    }
                    finalizeDrop(newRow)
                end)
            end
        )
    end
end

-- ── Pickup item ─────────────────────────────────────────────────────────────

function Inventory.pickupItem(charId, droppedItemId, callback)
    local cached = _dropCache[droppedItemId]
    if not cached then
        if callback then callback(nil, "Dropped item not found.") end
        return
    end
    local invItem = cached.invItem
    local def = ItemRegistry.get(invItem.inv_item_def_id)
    if not def then
        if callback then callback(nil, "Unknown item.") end
        return
    end

    -- Prevent concurrent pickups of the same item.
    if not lockItem(invItem.inv_item_id) then
        if callback then callback(nil, "This item is being picked up by someone else.") end
        return
    end

    -- Calculate weight including container contents for dropped containers.
    local function continuePickup(totalAddWeight)
        local currentWeight = Inventory.getWeight(charId)
        if currentWeight + totalAddWeight > Config.INVENTORY.MAX_CARRY_WEIGHT then
            unlockItem(invItem.inv_item_id)
            if callback then callback(nil, "Too heavy. You cannot carry that much.") end
            return
        end

        -- Try stacking.
        local ts = now()
        Inventory._doPickupTransfer(charId, droppedItemId, cached, invItem, def, callback, ts)
    end

    local baseWeight = def.weight * invItem.inv_item_amount
    if def.isContainer then
        -- Container contents are not in memory cache for ground items; query DB.
        InventoryItemModel.findAll({ inv_item_owner_type = "container", inv_item_owner_id = invItem.inv_item_id }, function(rows)
            local contentWeight = 0
            if rows then
                for _, row in ipairs(rows) do
                    local cDef = ItemRegistry.get(row.inv_item_def_id)
                    if cDef then contentWeight = contentWeight + (cDef.weight * row.inv_item_amount) end
                end
            end
            continuePickup(baseWeight + contentWeight)
        end)
    else
        continuePickup(baseWeight)
    end
end

function Inventory._doPickupTransfer(charId, droppedItemId, cached, invItem, def, callback, ts)
    local canStack = def.maxStack > 1 and not invItem.inv_item_serial and not invItem.inv_item_custom_name
    if canStack then
        local stackSlot = Inventory.findStackableSlot(charId, invItem.inv_item_def_id, invItem.inv_item_amount, invItem.inv_item_quality, invItem.inv_item_purity)
        if stackSlot then
            local existing = _invCache[charId][stackSlot]
            local newAmount = existing.inv_item_amount + invItem.inv_item_amount
            local stackDropSession = cached.drop.dropped_item_session
            InventoryItemModel.update(
                { inv_item_amount = newAmount, inv_item_updated_at = ts },
                { inv_item_id = existing.inv_item_id },
                function()
                    existing.inv_item_amount = newAmount
                    existing.inv_item_updated_at = ts
                    InventoryItemModel.delete({ inv_item_id = invItem.inv_item_id }, function()
                        DroppedItemModel.delete({ dropped_item_id = droppedItemId }, function()
                            _dropCache[droppedItemId] = nil
                            _dropTimestamps[droppedItemId] = nil
                            unlockItem(invItem.inv_item_id)
                            Inventory.logTransfer("pickup", invItem.inv_item_def_id, invItem.inv_item_amount, "ground", droppedItemId, "character", charId, charId)
                            broadcastDropRemoveToSession(stackDropSession, droppedItemId)
                            if callback then callback(existing) end
                        end)
                    end)
                end
            )
            return
        end
    end

    local slot = Inventory.findFreeSlot(charId)
    if not slot then
        unlockItem(invItem.inv_item_id)
        if callback then callback(nil, "Inventory is full.") end
        return
    end

    InventoryItemModel.update(
        { inv_item_owner_type = "character", inv_item_owner_id = charId, inv_item_slot = slot, inv_item_updated_at = ts },
        { inv_item_id = invItem.inv_item_id },
        function()
            invItem.inv_item_owner_type = "character"
            invItem.inv_item_owner_id   = charId
            invItem.inv_item_slot       = slot
            invItem.inv_item_updated_at = ts
            if not _invCache[charId] then _invCache[charId] = {} end
            _invCache[charId][slot] = invItem
            _dropCache[droppedItemId] = nil
            _dropTimestamps[droppedItemId] = nil
            local dropSession = cached.drop.dropped_item_session
            DroppedItemModel.delete({ dropped_item_id = droppedItemId }, function(ok)
                if not ok then
                    Log.warn(_LOG_TAG, "Failed to delete dropped_items row " .. droppedItemId .. " during pickup.")
                end
            end)
            unlockItem(invItem.inv_item_id)
            Inventory.logTransfer("pickup", invItem.inv_item_def_id, invItem.inv_item_amount, "ground", droppedItemId, "character", charId, charId)
            broadcastDropRemoveToSession(dropSession, droppedItemId)
            -- Load container contents if the picked-up item is a container.
            local pickupDef = ItemRegistry.get(invItem.inv_item_def_id)
            if pickupDef and pickupDef.isContainer then
                Inventory._loadContainerContents(charId, function()
                    if callback then callback(invItem) end
                end)
            else
                if callback then callback(invItem) end
            end
        end
    )
end

-- ── Container operations ────────────────────────────────────────────────────

function Inventory.getContainerContents(charId, containerSlot)
    local inv = _invCache[charId]
    if not inv then return nil end
    local containerItem = inv[containerSlot]
    if not containerItem then return nil end
    local def = ItemRegistry.get(containerItem.inv_item_def_id)
    if not def or not def.isContainer then return nil end
    local containers = inv._containers
    if not containers then return {} end
    return containers[containerItem.inv_item_id] or {}
end

function Inventory.getContainerWeight(charId, containerSlot)
    local contents = Inventory.getContainerContents(charId, containerSlot)
    if not contents then return 0 end
    local total = 0
    for _, item in pairs(contents) do
        local def = ItemRegistry.get(item.inv_item_def_id)
        if def then total = total + (def.weight * item.inv_item_amount) end
    end
    return total
end

function Inventory.getContainerSlotCount(charId, containerSlot)
    local contents = Inventory.getContainerContents(charId, containerSlot)
    if not contents then return 0 end
    local count = 0
    for _ in pairs(contents) do count = count + 1 end
    return count
end

function Inventory.findFreeContainerSlot(charId, containerSlot)
    local inv = _invCache[charId]
    if not inv then return nil end
    local containerItem = inv[containerSlot]
    if not containerItem then return nil end
    local def = ItemRegistry.get(containerItem.inv_item_def_id)
    if not def or not def.isContainer then return nil end
    local contents = Inventory.getContainerContents(charId, containerSlot) or {}
    for slot = 1, def.containerSlots do
        if not contents[slot] then return slot end
    end
    return nil
end

function Inventory.storeInContainer(charId, itemSlot, containerSlot, amount, callback)
    local inv = _invCache[charId]
    if not inv then
        if callback then callback(nil, "Inventory not loaded.") end
        return
    end
    local item = inv[itemSlot]
    if not item then
        if callback then callback(nil, "No item in slot " .. itemSlot .. ".") end
        return
    end
    local containerItem = inv[containerSlot]
    if not containerItem then
        if callback then callback(nil, "No container in slot " .. containerSlot .. ".") end
        return
    end
    local containerDef = ItemRegistry.get(containerItem.inv_item_def_id)
    if not containerDef or not containerDef.isContainer then
        if callback then callback(nil, "That item is not a container.") end
        return
    end
    local itemDef = ItemRegistry.get(item.inv_item_def_id)
    if not itemDef then
        if callback then callback(nil, "Unknown item.") end
        return
    end
    if itemDef.isContainer then
        if callback then callback(nil, "Containers cannot be stored inside other containers.") end
        return
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    if amount > item.inv_item_amount then
        if callback then callback(nil, "Not enough items (have " .. item.inv_item_amount .. ").") end
        return
    end

    -- Prevent concurrent modifications on the same item.
    if not lockItem(item.inv_item_id) then
        if callback then callback(nil, "This item is being modified, please wait.") end
        return
    end

    -- Weight check.
    local addWeight = itemDef.weight * amount
    local containerWeight = Inventory.getContainerWeight(charId, containerSlot)
    if containerWeight + addWeight > containerDef.containerMaxWeight then
        unlockItem(item.inv_item_id)
        if callback then callback(nil, "Container is too full (weight limit).") end
        return
    end

    -- Slot check.
    local cSlot = Inventory.findFreeContainerSlot(charId, containerSlot)
    if not cSlot then
        unlockItem(item.inv_item_id)
        if callback then callback(nil, "Container is full (no free slots).") end
        return
    end

    local containerId = containerItem.inv_item_id
    local ts = now()

    if amount == item.inv_item_amount then
        -- Move entire stack into container: DB first, then cache.
        InventoryItemModel.update(
            { inv_item_owner_type = "container", inv_item_owner_id = containerId, inv_item_slot = cSlot, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                inv[itemSlot] = nil
                item.inv_item_owner_type = "container"
                item.inv_item_owner_id   = containerId
                item.inv_item_slot       = cSlot
                item.inv_item_updated_at = ts
                if not inv._containers then inv._containers = {} end
                if not inv._containers[containerId] then inv._containers[containerId] = {} end
                inv._containers[containerId][cSlot] = item
                unlockItem(item.inv_item_id)
                Inventory.logTransfer("store", item.inv_item_def_id, amount, "character", charId, "container", containerId, charId)
                if callback then callback(true) end
            end
        )
    else
        -- Partial: decrement source in DB, then create split row inside callback.
        local newAmount = item.inv_item_amount - amount
        InventoryItemModel.update(
            { inv_item_amount = newAmount, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_amount = newAmount
                item.inv_item_updated_at = ts
                InventoryItemModel.create({
                    inv_item_def_id      = item.inv_item_def_id,
                    inv_item_owner_type  = "container",
                    inv_item_owner_id    = containerId,
                    inv_item_slot        = cSlot,
                    inv_item_amount      = amount,
                    inv_item_custom_name = item.inv_item_custom_name,
                    inv_item_quality     = item.inv_item_quality,
                    inv_item_purity      = item.inv_item_purity,
                    inv_item_metadata    = item.inv_item_metadata,
                    inv_item_created_at  = ts,
                    inv_item_updated_at  = ts,
                }, function(newId)
                    if not newId then
                        -- Rollback: restore DB first, then update cache.
                        local restoredAmount = item.inv_item_amount + amount
                        InventoryItemModel.update(
                            { inv_item_amount = restoredAmount },
                            { inv_item_id = item.inv_item_id },
                            function()
                                item.inv_item_amount = restoredAmount
                                unlockItem(item.inv_item_id)
                                if callback then callback(nil, "Failed to store item.") end
                            end
                        )
                        return
                    end
                    local newRow = {
                        inv_item_id          = newId,
                        inv_item_def_id      = item.inv_item_def_id,
                        inv_item_owner_type  = "container",
                        inv_item_owner_id    = containerId,
                        inv_item_slot        = cSlot,
                        inv_item_amount      = amount,
                        inv_item_custom_name = item.inv_item_custom_name,
                        inv_item_quality     = item.inv_item_quality,
                        inv_item_purity      = item.inv_item_purity,
                        inv_item_metadata    = item.inv_item_metadata,
                        inv_item_created_at  = ts,
                        inv_item_updated_at  = ts,
                    }
                    if not inv._containers then inv._containers = {} end
                    if not inv._containers[containerId] then inv._containers[containerId] = {} end
                    inv._containers[containerId][cSlot] = newRow
                    unlockItem(item.inv_item_id)
                    Inventory.logTransfer("store", item.inv_item_def_id, amount, "character", charId, "container", containerId, charId)
                    if callback then callback(true) end
                end)
            end
        )
    end
end

function Inventory.retrieveFromContainer(charId, containerSlot, containerItemSlot, amount, callback)
    local inv = _invCache[charId]
    if not inv then
        if callback then callback(nil, "Inventory not loaded.") end
        return
    end
    local containerItem = inv[containerSlot]
    if not containerItem then
        if callback then callback(nil, "No container in slot " .. containerSlot .. ".") end
        return
    end
    local containerDef = ItemRegistry.get(containerItem.inv_item_def_id)
    if not containerDef or not containerDef.isContainer then
        if callback then callback(nil, "That item is not a container.") end
        return
    end
    local contents = Inventory.getContainerContents(charId, containerSlot) or {}
    local item = contents[containerItemSlot]
    if not item then
        if callback then callback(nil, "No item in container slot " .. containerItemSlot .. ".") end
        return
    end
    local itemDef = ItemRegistry.get(item.inv_item_def_id)
    if not itemDef then
        if callback then callback(nil, "Unknown item.") end
        return
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        if callback then callback(nil, "Invalid amount.") end
        return
    end
    if amount > item.inv_item_amount then
        if callback then callback(nil, "Not enough items (have " .. item.inv_item_amount .. ").") end
        return
    end

    -- Prevent concurrent modifications on the same item.
    if not lockItem(item.inv_item_id) then
        if callback then callback(nil, "This item is being modified, please wait.") end
        return
    end

    -- No carry-weight check needed: the item is already inside a container the
    -- character is carrying, so getWeight() already accounts for it. Moving it
    -- from container to inventory is a net-zero weight change.

    local invSlot = Inventory.findFreeSlot(charId)
    if not invSlot then
        unlockItem(item.inv_item_id)
        if callback then callback(nil, "Inventory is full.") end
        return
    end

    local containerId = containerItem.inv_item_id
    local ts = now()

    if amount == item.inv_item_amount then
        -- Move entire stack out of container: DB first, then cache.
        InventoryItemModel.update(
            { inv_item_owner_type = "character", inv_item_owner_id = charId, inv_item_slot = invSlot, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                contents[containerItemSlot] = nil
                item.inv_item_owner_type = "character"
                item.inv_item_owner_id   = charId
                item.inv_item_slot       = invSlot
                item.inv_item_updated_at = ts
                inv[invSlot] = item
                unlockItem(item.inv_item_id)
                Inventory.logTransfer("retrieve", item.inv_item_def_id, amount, "container", containerId, "character", charId, charId)
                if callback then callback(true) end
            end
        )
    else
        -- Partial: decrement source in DB, then create split row inside callback.
        local newAmount = item.inv_item_amount - amount
        InventoryItemModel.update(
            { inv_item_amount = newAmount, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_amount = newAmount
                item.inv_item_updated_at = ts
                InventoryItemModel.create({
                    inv_item_def_id      = item.inv_item_def_id,
                    inv_item_owner_type  = "character",
                    inv_item_owner_id    = charId,
                    inv_item_slot        = invSlot,
                    inv_item_amount      = amount,
                    inv_item_custom_name = item.inv_item_custom_name,
                    inv_item_quality     = item.inv_item_quality,
                    inv_item_purity      = item.inv_item_purity,
                    inv_item_metadata    = item.inv_item_metadata,
                    inv_item_created_at  = ts,
                    inv_item_updated_at  = ts,
                }, function(newId)
                    if not newId then
                        -- Rollback: restore DB first, then update cache.
                        local restoredAmount = item.inv_item_amount + amount
                        InventoryItemModel.update(
                            { inv_item_amount = restoredAmount },
                            { inv_item_id = item.inv_item_id },
                            function()
                                item.inv_item_amount = restoredAmount
                                unlockItem(item.inv_item_id)
                                if callback then callback(nil, "Failed to retrieve item.") end
                            end
                        )
                        return
                    end
                    local newRow = {
                        inv_item_id          = newId,
                        inv_item_def_id      = item.inv_item_def_id,
                        inv_item_owner_type  = "character",
                        inv_item_owner_id    = charId,
                        inv_item_slot        = invSlot,
                        inv_item_amount      = amount,
                        inv_item_custom_name = item.inv_item_custom_name,
                        inv_item_quality     = item.inv_item_quality,
                        inv_item_purity      = item.inv_item_purity,
                        inv_item_metadata    = item.inv_item_metadata,
                        inv_item_created_at  = ts,
                        inv_item_updated_at  = ts,
                    }
                    inv[invSlot] = newRow
                    unlockItem(item.inv_item_id)
                    Inventory.logTransfer("retrieve", item.inv_item_def_id, amount, "container", containerId, "character", charId, charId)
                    if callback then callback(true) end
                end)
            end
        )
    end
end

-- ── Rename item ─────────────────────────────────────────────────────────────

function Inventory.renameItem(charId, slot, newName, callback)
    local inv = _invCache[charId]
    if not inv or not inv[slot] then
        if callback then callback(nil, "No item in that slot.") end
        return
    end
    local item = inv[slot]
    local sanitized = newName and newName:match("^%s*(.-)%s*$") or nil
    if sanitized and #sanitized == 0 then sanitized = nil end
    if sanitized and #sanitized > 64 then
        if callback then callback(nil, "Name too long (max 64 characters).") end
        return
    end

    -- M16: Sanitize custom item names — allow only alphanumeric + basic punctuation.
    if sanitized and not sanitized:match("^[%w%s%-%_%.%,%!%?%'%#%(%)]+$") then
        if callback then callback(nil, "Name contains invalid characters.") end
        return
    end

    local ts = now()
    if sanitized then
        InventoryItemModel.update(
            { inv_item_custom_name = sanitized, inv_item_updated_at = ts },
            { inv_item_id = item.inv_item_id },
            function()
                item.inv_item_custom_name = sanitized
                item.inv_item_updated_at = ts
                if callback then callback(true) end
            end
        )
    else
        DB.execute(
            "UPDATE `inventory_items` SET `inv_item_custom_name` = NULL, `inv_item_updated_at` = ? WHERE `inv_item_id` = ?",
            { ts, item.inv_item_id },
            DB.safeCallback("renameItem.clearName", function()
                item.inv_item_custom_name = nil
                item.inv_item_updated_at = ts
                if callback then callback(true) end
            end)
        )
    end
end

-- ── Remove serial number ─────────────────────────────────────────────────────

function Inventory.removeSerial(charId, slot, callback)
    local inv = _invCache[charId]
    if not inv or not inv[slot] then
        if callback then callback(nil, "No item in that slot.") end
        return
    end
    local item = inv[slot]
    if not item.inv_item_serial then
        if callback then callback(nil, "This item does not have a serial number.") end
        return
    end

    local ts = now()
    DB.execute(
        "UPDATE `inventory_items` SET `inv_item_serial` = NULL, `inv_item_updated_at` = ? WHERE `inv_item_id` = ?",
        { ts, item.inv_item_id },
        DB.safeCallback("removeSerial", function()
            item.inv_item_serial = nil
            item.inv_item_updated_at = ts
            if callback then callback(true) end
        end)
    )
end

-- ── Move item (reorder slots) ───────────────────────────────────────────────

function Inventory.moveItem(charId, fromSlot, toSlot, callback)
    local inv = _invCache[charId]
    if not inv then
        if callback then callback(nil, "Inventory not loaded.") end
        return
    end
    if fromSlot == toSlot then
        if callback then callback(nil, "Source and destination are the same slot.") end
        return
    end

    local fromItem = inv[fromSlot]
    if not fromItem then
        if callback then callback(nil, "No item in slot " .. fromSlot .. ".") end
        return
    end

    local toItem = inv[toSlot]
    local ts = now()

    if toItem then
        -- Swap both items: update DB first, then cache.
        InventoryItemModel.update(
            { inv_item_slot = toSlot, inv_item_updated_at = ts },
            { inv_item_id = fromItem.inv_item_id },
            function()
                InventoryItemModel.update(
                    { inv_item_slot = fromSlot, inv_item_updated_at = ts },
                    { inv_item_id = toItem.inv_item_id },
                    function()
                        inv[fromSlot] = toItem
                        inv[toSlot]   = fromItem
                        fromItem.inv_item_slot = toSlot
                        fromItem.inv_item_updated_at = ts
                        toItem.inv_item_slot = fromSlot
                        toItem.inv_item_updated_at = ts
                        if callback then callback(true) end
                    end
                )
            end
        )
    else
        -- Move to empty slot: update DB first, then cache.
        InventoryItemModel.update(
            { inv_item_slot = toSlot, inv_item_updated_at = ts },
            { inv_item_id = fromItem.inv_item_id },
            function()
                inv[toSlot]   = fromItem
                inv[fromSlot] = nil
                fromItem.inv_item_slot = toSlot
                fromItem.inv_item_updated_at = ts
                if callback then callback(true) end
            end
        )
    end
end

-- ── Formatting ──────────────────────────────────────────────────────────────

function Inventory.formatItemLine(item, charId)
    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def then return "[?] Unknown Item" end

    local displayName = item.inv_item_custom_name or def.name
    local parts = { "[" .. item.inv_item_slot .. "] " .. displayName }

    if item.inv_item_serial then
        parts[#parts + 1] = "(S/N: " .. item.inv_item_serial .. ")"
    end
    if def.isContainer and charId then
        local inv = _invCache[charId]
        local cid = item.inv_item_id
        local slotCount = 0
        if inv and inv._containers and inv._containers[cid] then
            for _ in pairs(inv._containers[cid]) do slotCount = slotCount + 1 end
        end
        parts[#parts + 1] = "[Container: " .. slotCount .. "/" .. def.containerSlots .. "]"
    end
    if item.inv_item_quality then
        parts[#parts + 1] = "(Quality: " .. item.inv_item_quality .. "%)"
    end
    if item.inv_item_purity then
        parts[#parts + 1] = "(Purity: " .. item.inv_item_purity .. "%)"
    end

    local weight = def.weight * item.inv_item_amount
    parts[#parts + 1] = "x" .. item.inv_item_amount
    parts[#parts + 1] = "— " .. string.format("%.2f", weight) .. " kg"

    return table.concat(parts, " ")
end

function Inventory.formatInventory(charId)
    local inv = _invCache[charId]
    if not inv then return { "Inventory not loaded." } end

    local lines = {}
    local slotCount = Inventory.getSlotCount(charId)
    local weight = Inventory.getWeight(charId)
    local maxSlots = Config.INVENTORY.MAX_SLOTS
    local maxWeight = Config.INVENTORY.MAX_CARRY_WEIGHT

    lines[#lines + 1] = string.format("=== Inventory (%d/%d slots | %.1f / %.1f kg) ===",
        slotCount, maxSlots, weight, maxWeight)

    if slotCount == 0 then
        lines[#lines + 1] = "  (empty)"
    else
        local sortedSlots = {}
        for slot in pairs(inv) do
            if type(slot) == "number" then
                sortedSlots[#sortedSlots + 1] = slot
            end
        end
        table.sort(sortedSlots)
        for _, slot in ipairs(sortedSlots) do
            lines[#lines + 1] = "  " .. Inventory.formatItemLine(inv[slot], charId)
        end
    end

    return lines
end

local _C = {
    GOLD  = "{C8AA6E}",
    WHITE = "{FFFFFF}",
    GRAY  = "{AAAAAA}",
    BLUE  = "{66CCFF}",
}

function Inventory.formatContainerContents(charId, containerSlot)
    local inv = _invCache[charId]
    if not inv then return { _C.GRAY .. "Inventory not loaded." } end
    local containerItem = inv[containerSlot]
    if not containerItem then return { _C.GRAY .. "No container in that slot." } end
    local def = ItemRegistry.get(containerItem.inv_item_def_id)
    if not def or not def.isContainer then return { _C.GRAY .. "That item is not a container." } end

    local displayName = containerItem.inv_item_custom_name or def.name
    local contents = Inventory.getContainerContents(charId, containerSlot) or {}
    local slotCount = 0
    for _ in pairs(contents) do slotCount = slotCount + 1 end
    local weight = Inventory.getContainerWeight(charId, containerSlot)

    local lines = {}
    lines[#lines + 1] = _C.GOLD .. "=====[ "
        .. _C.WHITE .. displayName .. " "
        .. _C.GOLD .. "| "
        .. _C.WHITE .. slotCount .. _C.GRAY .. "/" .. _C.WHITE .. def.containerSlots .. " slots "
        .. _C.GOLD .. "| "
        .. _C.WHITE .. string.format("%.2f", weight) .. _C.GRAY .. "/" .. _C.WHITE .. string.format("%.2f", def.containerMaxWeight) .. " kg "
        .. _C.GOLD .. "]====="

    if slotCount == 0 then
        lines[#lines + 1] = _C.GRAY .. "  Container is empty."
    else
        local sortedSlots = {}
        for slot in pairs(contents) do
            sortedSlots[#sortedSlots + 1] = slot
        end
        table.sort(sortedSlots)
        for _, slot in ipairs(sortedSlots) do
            lines[#lines + 1] = Inventory.formatItemLineChat(contents[slot], charId)
        end
    end

    lines[#lines + 1] = _C.GOLD .. "=====[ " .. _C.GRAY .. "Use /store and /retrieve to manage contents. " .. _C.GOLD .. "]====="

    return lines
end

-- ── Chat-formatted inventory (colored output) ─────────────────────────────

function Inventory.formatItemLineChat(item, charId)
    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def then return _C.GRAY .. "[?] Unknown Item" end

    local displayName = item.inv_item_custom_name or def.name
    local parts = { _C.GOLD .. item.inv_item_slot .. ". " .. _C.WHITE .. displayName }

    if def.categoryName then
        parts[#parts + 1] = _C.GRAY .. "(" .. def.categoryName .. ")"
    end
    if item.inv_item_serial then
        parts[#parts + 1] = _C.GRAY .. "(S/N: " .. item.inv_item_serial .. ")"
    end
    if def.isContainer and charId then
        local inv = _invCache[charId]
        local cid = item.inv_item_id
        local slotCount = 0
        if inv and inv._containers and inv._containers[cid] then
            for _ in pairs(inv._containers[cid]) do slotCount = slotCount + 1 end
        end
        parts[#parts + 1] = _C.BLUE .. "[" .. slotCount .. "/" .. def.containerSlots .. " slots]"
    end
    if item.inv_item_quality then
        parts[#parts + 1] = _C.GRAY .. "(Quality: " .. item.inv_item_quality .. "%)"
    end
    if item.inv_item_purity then
        parts[#parts + 1] = _C.GRAY .. "(Purity: " .. item.inv_item_purity .. "%)"
    end

    parts[#parts + 1] = _C.GOLD .. "x" .. item.inv_item_amount
    parts[#parts + 1] = _C.GRAY .. "- " .. string.format("%.2f", def.weight * item.inv_item_amount) .. " kg"

    return table.concat(parts, " ")
end

function Inventory.formatInventoryChat(charId, playerName)
    local inv = _invCache[charId]
    if not inv then return { _C.GRAY .. "Inventory not loaded." } end

    local slotCount = Inventory.getSlotCount(charId)
    local weight = Inventory.getWeight(charId)
    local maxSlots = Config.INVENTORY.MAX_SLOTS
    local maxWeight = Config.INVENTORY.MAX_CARRY_WEIGHT
    local timeStr = os.date("!%H:%M - %d/%m/%Y")

    local lines = {}
    lines[#lines + 1] = _C.GOLD .. "=====[ " .. _C.WHITE .. "Inventory of " .. playerName .. " " .. _C.GOLD .. "| " .. _C.GRAY .. timeStr .. " " .. _C.GOLD .. "]====="

    if slotCount == 0 then
        lines[#lines + 1] = _C.GRAY .. "  Your inventory is empty."
    else
        local sortedSlots = {}
        for slot in pairs(inv) do
            if type(slot) == "number" then
                sortedSlots[#sortedSlots + 1] = slot
            end
        end
        table.sort(sortedSlots)
        local hasContainer = false
        for _, slot in ipairs(sortedSlots) do
            lines[#lines + 1] = Inventory.formatItemLineChat(inv[slot], charId)
            if not hasContainer then
                local cDef = ItemRegistry.get(inv[slot].inv_item_def_id)
                if cDef and cDef.isContainer then hasContainer = true end
            end
        end
        if hasContainer then
            lines[#lines + 1] = _C.GRAY .. "  Use /container <slot> to view container contents."
        end
    end

    lines[#lines + 1] = _C.GOLD .. "=====[ "
        .. _C.WHITE .. string.format("%.2f", weight) .. _C.GRAY .. "/" .. _C.WHITE .. string.format("%.2f", maxWeight) .. " kg "
        .. _C.GOLD .. "| "
        .. _C.WHITE .. slotCount .. _C.GRAY .. "/" .. _C.WHITE .. maxSlots .. " slots "
        .. _C.GOLD .. "]====="

    return lines
end
