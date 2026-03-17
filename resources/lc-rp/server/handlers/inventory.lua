-- server/handlers/inventory.lua
-- Player commands: /inventory, /giveitem, /dropitem, /pickup, /nameitem,
--                  /nearbyitems, /moveitem, /useitem, /equip, /unequip

local _LOG_TAG = "InvCmd"

-- Categories that cannot be used with /useitem (require specialized commands).
local NON_USABLE = {
    [ItemRegistry.Categories.WEAPON]    = true,
    [ItemRegistry.Categories.AMMO]      = true,
    [ItemRegistry.Categories.CONTAINER] = true,
}

-- Returns the currently equipped weapon (item, slot), or nil.
-- Auto-clears stale state when the item has been moved, dropped, or given away.
local function getEquippedWeapon(source)
    local data = Players.get(source)
    if not data or not data.charId or not data.equippedSlot then return nil end
    local item = Inventory.getItemAtSlot(data.charId, data.equippedSlot)
    if not item or item.inv_item_id ~= data.equippedItemId then
        data.equippedSlot      = nil
        data.equippedItemId    = nil
        data.equippedAmmoGroup = nil
        return nil
    end
    return item, data.equippedSlot
end

local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz
end

local function isInRange(sourceID, targetID, radius)
    local sd = Players.get(sourceID)
    local td = Players.get(targetID)
    if not sd or not td then return false end
    local sx, sy, sz = sd.posX, sd.posY, sd.posZ
    local tx, ty, tz = td.posX, td.posY, td.posZ
    if not sx or not sy or not sz or not tx or not ty or not tz then return false end
    local okS, srcSession = pcall(Player.GetSession, sourceID)
    local okT, tgtSession = pcall(Player.GetSession, targetID)
    if not okS or not okT or srcSession ~= tgtSession then return false end
    return distSq(sx, sy, sz, tx, ty, tz) <= radius * radius
end

local function isNearDrop(sourceID, drop, radius)
    local sd = Players.get(sourceID)
    if not sd then return false end
    local sx, sy, sz = sd.posX, sd.posY, sd.posZ
    if not sx or not sy or not sz then return false end
    local okSession, session = pcall(Player.GetSession, sourceID)
    if not okSession then return false end
    if session ~= drop.dropped_item_session then return false end
    return distSq(sx, sy, sz, drop.dropped_item_x, drop.dropped_item_y, drop.dropped_item_z) <= radius * radius
end

-- ── /inventory (/inv) ───────────────────────────────────────────────────────

ServerCmd.register("inventory", function(source, _args, _full)
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    local playerName = Player.GetName(source) or "Unknown"
    local lines = Inventory.formatInventoryChat(data.charId, playerName)
    for _, line in ipairs(lines) do
        Chat.SendMessage(source, line)
    end
end, "View your inventory", { "inv" })

-- ── /giveitem (/gi) ─────────────────────────────────────────────────────────

ServerCmd.register("giveitem", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 3 then
        Notify.player(source, "error", "Usage: /giveitem <ID/Name> <SlotID> <Amount>")
        return
    end

    local targetID, resolveErr = Resolve.player(args[1])
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match '" .. args[1] .. "'. Use their ID instead.")
        else
            Notify.player(source, "error", "Player not found: " .. args[1])
        end
        return
    end
    if targetID == source then
        Notify.player(source, "error", "You cannot give items to yourself.")
        return
    end

    if not isInRange(source, targetID, Config.INVENTORY.GIVE_RADIUS) then
        Notify.player(source, "error", "That player is too far away.")
        return
    end

    local slot = math.floor(tonumber(args[2]) or 0)
    local amount = math.floor(tonumber(args[3]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive number.")
        return
    end

    local senderData = Players.get(source)
    local targetData = Players.get(targetID)
    if not targetData or not targetData.charId then
        Notify.player(source, "error", "Target player has no active character.")
        return
    end

    if senderData.equippedSlot == slot then
        Notify.player(source, "error", "Unequip your weapon first (/unequip).")
        return
    end

    local item = Inventory.getItemAtSlot(senderData.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    local itemName = (item.inv_item_custom_name or (def and def.name) or "Unknown")

    Inventory.giveItem(senderData.charId, targetData.charId, slot, amount, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to give item.")
            return
        end
        local senderName = Player.GetName(source)  or tostring(source)
        local targetName = Player.GetName(targetID) or tostring(targetID)
        Notify.player(source,   "success", string.format("You gave %s x%d %s.", targetName, amount, itemName))
        Notify.player(targetID, "success", string.format("%s gave you x%d %s.", senderName, amount, itemName))
        Log.info(_LOG_TAG, string.format("%s (%d) gave %s (%d) x%d %s",
            senderName, source, targetName, targetID, amount, itemName))
    end)
end, "Give item to player: /giveitem <ID/Name> <Slot> <Amount>", { "gi" })

-- ── /dropitem (/di) ─────────────────────────────────────────────────────────

ServerCmd.register("dropitem", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /dropitem <SlotID> <Amount>")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    local amount = math.floor(tonumber(args[2]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    if data.equippedSlot == slot then
        Notify.player(source, "error", "Unequip your weapon first (/unequip).")
        return
    end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    local itemName = (item.inv_item_custom_name or (def and def.name) or "Unknown")

    local px, py, pz = data.posX, data.posY, data.posZ
    if not px or not py or not pz then
        local ok, x, y, z = pcall(Player.GetPosition, source)
        if ok and x then px, py, pz = x, y, z end
    end
    if not px or not py or not pz then
        Notify.player(source, "error", "Could not determine your position.")
        return
    end

    local okSession, session = pcall(Player.GetSession, source)
    session = (okSession and session) or 0

    Inventory.dropItem(data.charId, slot, amount, { x = px, y = py, z = pz }, session, data.accountId, function(dropId, err)
        if not dropId then
            Notify.player(source, "error", err or "Failed to drop item.")
            return
        end
        Notify.player(source, "success", string.format("Dropped x%d %s (Drop ID: %d).", amount, itemName, dropId))
        Log.info(_LOG_TAG, string.format("%s (%d) dropped x%d %s (dropId=%d)",
            Player.GetName(source) or tostring(source), source, amount, itemName, dropId))
    end)
end, "Drop item on the ground: /dropitem <Slot> <Amount>", { "di" })

-- ── /pickup (/pu) ───────────────────────────────────────────────────────────

ServerCmd.register("pickup", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /pickup <DroppedItemID>")
        return
    end

    local dropId = math.floor(tonumber(args[1]) or 0)
    if dropId <= 0 then
        Notify.player(source, "error", "Invalid dropped item ID.")
        return
    end

    local cached = Inventory.getDroppedItem(dropId)
    if not cached then
        Notify.player(source, "error", "Dropped item not found (ID: " .. dropId .. ").")
        return
    end

    if not isNearDrop(source, cached.drop, Config.INVENTORY.PICKUP_RADIUS) then
        Notify.player(source, "error", "You are too far from that item.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local dropperAccountId = cached.drop.dropped_item_account_id
    local dropperCharId    = cached.drop.dropped_item_dropped_by
    if dropperAccountId and data.accountId == dropperAccountId and data.charId ~= dropperCharId then
        Notify.player(source, "error", "You cannot pick up items dropped by another character on your account.")
        return
    end

    local def = ItemRegistry.get(cached.invItem.inv_item_def_id)
    local itemName = (cached.invItem.inv_item_custom_name or (def and def.name) or "Unknown")

    Inventory.pickupItem(data.charId, dropId, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to pick up item.")
            return
        end
        Notify.player(source, "success", string.format("Picked up x%d %s.", cached.invItem.inv_item_amount, itemName))
        Log.info(_LOG_TAG, string.format("%s (%d) picked up x%d %s (dropId=%d)",
            Player.GetName(source) or tostring(source), source, cached.invItem.inv_item_amount, itemName, dropId))

        -- If picked-up ammo matches the currently equipped weapon, consume it from
        -- inventory and add it to the player's native ammo (ammo lives on ped while equipped).
        if def and def.ammoGroup then
            local equipped = getEquippedWeapon(source)
            if equipped then
                local eqDef = ItemRegistry.get(equipped.inv_item_def_id)
                if eqDef and eqDef.ammoGroup == def.ammoGroup then
                    local pickedUpAmount = cached.invItem.inv_item_amount
                    Inventory.consumeAmmoByGroup(data.charId, def.ammoGroup, pickedUpAmount, function(newTotal)
                        local currentAmmo = data.serverLastAmmo or 0
                        local updatedAmmo = currentAmmo + pickedUpAmount
                        data.serverLastAmmo = updatedAmmo
                        Events.CallRemote("char_ammo_updated", source, { eqDef.weaponTypeId, updatedAmmo })
                    end)
                end
            end
        end
    end)
end, "Pick up a dropped item: /pickup <DroppedItemID>", { "pu" })

-- ── /nameitem ───────────────────────────────────────────────────────────────

ServerCmd.register("nameitem", function(source, args, full)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /nameitem <SlotID> [NewName] (omit name to reset)")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end

    -- Extract everything after the first arg as the name (preserves spaces).
    local newName = nil
    if #args >= 2 then
        local slotStr = tostring(args[1])
        local nameStart = full:find(slotStr, 1, true)
        if nameStart then
            newName = full:sub(nameStart + #slotStr):match("^%s*(.-)%s*$")
            if #newName == 0 then newName = nil end
        end
    end

    local def = ItemRegistry.get(item.inv_item_def_id)
    local defaultName = def and def.name or "Unknown"

    Inventory.renameItem(data.charId, slot, newName, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to rename item.")
            return
        end
        if newName then
            Notify.player(source, "success", string.format("Renamed item in slot %d to \"%s\".", slot, newName))
        else
            Notify.player(source, "success", string.format("Reset item name in slot %d to default (%s).", slot, defaultName))
        end
    end)
end, "Rename item: /nameitem <Slot> [Name] (omit to reset)")

-- ── /nearbyitems (/ni) ─────────────────────────────────────────────────────

ServerCmd.register("nearbyitems", function(source)
    if not Guard.requireChar(source) then return end

    local sd = Players.get(source)
    if not sd then return end
    local sx, sy, sz = sd.posX, sd.posY, sd.posZ
    if not sx or not sy or not sz then
        Notify.player(source, "error", "Could not determine your position.")
        return
    end
    local okSession, session = pcall(Player.GetSession, source)
    if not okSession then return end

    local radius = Config.INVENTORY.PICKUP_RADIUS
    local radiusSq = radius * radius
    local found = {}

    for dropId, cached in pairs(Inventory.getDroppedItems()) do
        local drop = cached.drop
        if drop.dropped_item_session == session then
            local d = distSq(sx, sy, sz, drop.dropped_item_x, drop.dropped_item_y, drop.dropped_item_z)
            if d <= radiusSq then
                found[#found + 1] = { dropId = dropId, dist = math.sqrt(d), cached = cached }
            end
        end
    end

    if #found == 0 then
        Notify.player(source, "info", "No dropped items nearby.")
        return
    end

    table.sort(found, function(a, b) return a.dist < b.dist end)

    Notify.player(source, "info", string.format("=== Nearby Items (%d found) ===", #found))
    for _, entry in ipairs(found) do
        local invItem = entry.cached.invItem
        local def = ItemRegistry.get(invItem.inv_item_def_id)
        local displayName = invItem.inv_item_custom_name or (def and def.name) or "Unknown"
        local serialInfo = invItem.inv_item_serial and (" (S/N: " .. invItem.inv_item_serial .. ")") or ""
        Notify.player(source, "info", string.format(
            "  [Drop ID: %d] %s%s x%d — %.1fm away",
            entry.dropId, displayName, serialInfo, invItem.inv_item_amount, entry.dist
        ))
    end
end, "Show nearby dropped items: /nearbyitems", { "ni" })

-- ── /moveitem ───────────────────────────────────────────────────────────────

ServerCmd.register("moveitem", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /moveitem <FromSlot> <ToSlot>")
        return
    end

    local fromSlot = math.floor(tonumber(args[1]) or 0)
    local toSlot   = math.floor(tonumber(args[2]) or 0)
    if fromSlot <= 0 or fromSlot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid source slot.")
        return
    end
    if toSlot <= 0 or toSlot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid destination slot.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    if data.equippedSlot and (data.equippedSlot == fromSlot or data.equippedSlot == toSlot) then
        Notify.player(source, "error", "Unequip your weapon first (/unequip).")
        return
    end

    Inventory.moveItem(data.charId, fromSlot, toSlot, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to move item.")
            return
        end
        if data.equippedSlot == fromSlot then
            data.equippedSlot = toSlot
        elseif data.equippedSlot == toSlot then
            data.equippedSlot = fromSlot
        end
        local inv = Inventory.getInventory(data.charId)
        local toItem = inv and inv[toSlot]
        local fromItem = inv and inv[fromSlot]
        if fromItem then
            local fDef = ItemRegistry.get(fromItem.inv_item_def_id)
            local tDef = ItemRegistry.get(toItem.inv_item_def_id)
            Notify.player(source, "success", string.format("Swapped slot %d (%s) with slot %d (%s).",
                fromSlot, (fDef and fDef.name or "?"), toSlot, (tDef and tDef.name or "?")))
        else
            local tDef = toItem and ItemRegistry.get(toItem.inv_item_def_id)
            Notify.player(source, "success", string.format("Moved %s to slot %d.",
                (tDef and tDef.name or "item"), toSlot))
        end
    end)
end, "Move/swap inventory slots: /moveitem <FromSlot> <ToSlot>")

-- ── /useitem (/use) ─────────────────────────────────────────────────────────

ServerCmd.register("useitem", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /useitem <SlotID>")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def then
        Notify.player(source, "error", "Unknown item.")
        return
    end

    if NON_USABLE[def.category] then
        if def.category == ItemRegistry.Categories.WEAPON then
            Notify.player(source, "error", "Use /equip to equip weapons.")
        elseif def.category == ItemRegistry.Categories.AMMO then
            Notify.player(source, "error", "Ammo is consumed automatically with equipped weapons.")
        else
            Notify.player(source, "error", "This item cannot be used directly.")
        end
        return
    end

    local itemName = item.inv_item_custom_name or def.name

    -- TODO: Apply item-specific effects based on def.category / item_def_id.
    -- e.g. Food/Drink -> restore health, Narcotic -> apply drug effect,
    --      First Aid Kit -> heal, Flashlight -> toggle light, etc.

    Inventory.removeItem(data.charId, slot, 1, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to use item.")
            return
        end
        Notify.player(source, "success", string.format("Used %s.", itemName))
        Log.info(_LOG_TAG, string.format("%s (%d) used %s (def=%d)",
            Player.GetName(source) or tostring(source), source, itemName, item.inv_item_def_id))
    end)
end, "Use an item: /useitem <Slot>", { "use" })

-- ── /equip (/eq) ────────────────────────────────────────────────────────────

ServerCmd.register("equip", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /equip <SlotID>")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def or def.category ~= ItemRegistry.Categories.WEAPON then
        Notify.player(source, "error", "That item is not a weapon.")
        return
    end

    local currentEquipped = getEquippedWeapon(source)
    if currentEquipped and currentEquipped.inv_item_id == item.inv_item_id then
        Notify.player(source, "error", "This weapon is already equipped.")
        return
    end
    if currentEquipped then
        -- Auto-unequip the previous weapon. Return ammo server-side using the
        -- server-tracked count instead of waiting for the client to report it.
        local prevDef = ItemRegistry.get(currentEquipped.inv_item_def_id)
        if prevDef and prevDef.weaponTypeId then
            Events.CallRemote("char_unequip_weapon", source, { prevDef.weaponTypeId })
        end
        local prevAmmoGroup = data.equippedAmmoGroup
        local prevAmmo      = data.serverLastAmmo or 0
        data.equippedSlot      = nil
        data.equippedItemId    = nil
        data.equippedAmmoGroup = nil
        data.serverLastAmmo    = nil
        if prevAmmoGroup and prevAmmo > 0 then
            Inventory.returnAmmoByGroup(data.charId, prevAmmoGroup, prevAmmo, function(result, err)
                if result then
                    Log.info(_LOG_TAG, string.format("%s (%d) auto-returned %d rounds of %s on weapon swap",
                        Player.GetName(source) or tostring(source), source, prevAmmo, prevAmmoGroup))
                else
                    Log.warn(_LOG_TAG, string.format("Failed to auto-return ammo on swap for %s (%d): %s",
                        Player.GetName(source) or tostring(source), source, err or "unknown"))
                end
            end)
        end
    end

    local itemName = item.inv_item_custom_name or def.name
    local serialInfo = item.inv_item_serial and (" (S/N: " .. item.inv_item_serial .. ")") or ""

    -- For ranged weapons, consume all ammo from inventory and give it to the player.
    if def.ammoGroup then
        local _, _, totalAmmo = Inventory.findAmmoByGroup(data.charId, def.ammoGroup)
        if not totalAmmo or totalAmmo <= 0 then
            Notify.player(source, "error", string.format("You don't have any %s ammo to use with this weapon.", def.ammoGroup))
            return
        end

        Inventory.consumeAmmoByGroup(data.charId, def.ammoGroup, totalAmmo, function(newTotal, err)
            if not newTotal and err then
                Notify.player(source, "error", err or "Failed to consume ammo.")
                return
            end

            data.equippedSlot      = slot
            data.equippedItemId    = item.inv_item_id
            data.equippedAmmoGroup = def.ammoGroup
            data.serverLastAmmo    = totalAmmo
            Events.CallRemote("char_equip_weapon", source, { def.weaponTypeId, totalAmmo })

            Notify.player(source, "success", string.format("Equipped %s%s.", itemName, serialInfo))
            Log.info(_LOG_TAG, string.format("%s (%d) equipped %s (slot=%d, ammo=%d)",
                Player.GetName(source) or tostring(source), source, itemName, slot, totalAmmo))
        end)
    else
        -- Melee weapons: no ammo to consume.
        local ammoAmount = def.isMelee and 1 or 0
        data.equippedSlot      = slot
        data.equippedItemId    = item.inv_item_id
        data.equippedAmmoGroup = nil
        data.serverLastAmmo    = ammoAmount
        Events.CallRemote("char_equip_weapon", source, { def.weaponTypeId, ammoAmount })

        Notify.player(source, "success", string.format("Equipped %s%s.", itemName, serialInfo))
        Log.info(_LOG_TAG, string.format("%s (%d) equipped %s (slot=%d)",
            Player.GetName(source) or tostring(source), source, itemName, slot))
    end
end, "Equip a weapon: /equip <Slot>", { "eq" })

-- ── /unequip (/uneq) ───────────────────────────────────────────────────────

ServerCmd.register("unequip", function(source)
    if not Guard.requireChar(source) then return end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local equipped = getEquippedWeapon(source)
    if not equipped then
        Notify.player(source, "error", "You don't have a weapon equipped.")
        return
    end

    local def = ItemRegistry.get(equipped.inv_item_def_id)
    local itemName = equipped.inv_item_custom_name or (def and def.name) or "weapon"

    -- Capture ammo state before clearing — server returns ammo authoritatively.
    local ammoGroup = data.equippedAmmoGroup
    local ammoCount = data.serverLastAmmo or 0

    data.equippedSlot      = nil
    data.equippedItemId    = nil
    data.equippedAmmoGroup = nil
    data.serverLastAmmo    = nil

    -- Remove the weapon from the player ped on the client.
    if def and def.weaponTypeId then
        Events.CallRemote("char_unequip_weapon", source, { def.weaponTypeId })
    end

    -- Return ammo server-side using the server-tracked count.
    if ammoGroup and ammoCount > 0 then
        Inventory.returnAmmoByGroup(data.charId, ammoGroup, ammoCount, function(result, err)
            if result then
                Log.info(_LOG_TAG, string.format("%s (%d) returned %d rounds of %s on unequip",
                    Player.GetName(source) or tostring(source), source, ammoCount, ammoGroup))
            else
                Log.warn(_LOG_TAG, string.format("Failed to return ammo on unequip for %s (%d): %s",
                    Player.GetName(source) or tostring(source), source, err or "unknown"))
            end
        end)
    end

    Notify.player(source, "success", string.format("Unequipped %s.", itemName))
    Log.info(_LOG_TAG, string.format("%s (%d) unequipped %s",
        Player.GetName(source) or tostring(source), source, itemName))
end, "Unequip current weapon: /unequip", { "uneq" })

-- ── /removesn ─────────────────────────────────────────────────────────────

ServerCmd.register("removesn", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /removesn <SlotID>")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end

    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def or def.category ~= ItemRegistry.Categories.WEAPON then
        Notify.player(source, "error", "That item is not a weapon.")
        return
    end

    if not item.inv_item_serial then
        Notify.player(source, "error", "This weapon does not have a serial number.")
        return
    end

    local itemName = item.inv_item_custom_name or def.name
    local oldSerial = item.inv_item_serial

    Inventory.removeSerial(data.charId, slot, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to remove serial number.")
            return
        end
        Notify.player(source, "success", string.format("You scratched off the serial number from %s.", itemName))
        Log.info(_LOG_TAG, string.format("%s (%d) removed serial number %s from %s (slot=%d)",
            Player.GetName(source) or tostring(source), source, oldSerial, itemName, slot))
    end)
end, "Scratch off a weapon's serial number: /removesn <Slot>")
