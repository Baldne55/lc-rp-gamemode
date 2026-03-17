-- server/handlers/inventory_containers.lua
-- Container commands: /container, /store, /retrieve

-- ── /container (/c) ─────────────────────────────────────────────────────────

ServerCmd.register("container", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /container <SlotID>")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local lines = Inventory.formatContainerContents(data.charId, slot)
    for _, line in ipairs(lines) do
        Chat.SendMessage(source, line)
    end
end, "View container contents: /container <Slot>", { "c" })

-- ── /store ──────────────────────────────────────────────────────────────────

ServerCmd.register("store", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 3 then
        Notify.player(source, "error", "Usage: /store <ContainerSlot> <ItemSlot> <Amount>")
        return
    end

    local containerSlot = math.floor(tonumber(args[1]) or 0)
    local itemSlot      = math.floor(tonumber(args[2]) or 0)
    local amount        = math.floor(tonumber(args[3]) or 0)

    if containerSlot <= 0 or containerSlot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid container slot.")
        return
    end
    if itemSlot <= 0 or itemSlot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid item slot.")
        return
    end
    if containerSlot == itemSlot then
        Notify.player(source, "error", "Cannot store a container inside itself.")
        return
    end
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    if data.equippedSlot == itemSlot then
        Notify.player(source, "error", "Unequip your weapon first (/unequip).")
        return
    end

    local item = Inventory.getItemAtSlot(data.charId, itemSlot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. itemSlot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    local itemName = (item.inv_item_custom_name or (def and def.name) or "Unknown")

    Inventory.storeInContainer(data.charId, itemSlot, containerSlot, amount, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to store item.")
            return
        end
        Notify.player(source, "success", string.format("Stored x%d %s in container (slot %d).", amount, itemName, containerSlot))
    end)
end, "Store item in container: /store <ContainerSlot> <ItemSlot> <Amount>")

-- ── /retrieve ───────────────────────────────────────────────────────────────

ServerCmd.register("retrieve", function(source, args)
    if not Guard.requireChar(source) then return end
    if #args < 3 then
        Notify.player(source, "error", "Usage: /retrieve <ContainerSlot> <ContainerItemSlot> <Amount>")
        return
    end

    local containerSlot     = math.floor(tonumber(args[1]) or 0)
    local containerItemSlot = math.floor(tonumber(args[2]) or 0)
    local amount            = math.floor(tonumber(args[3]) or 0)

    if containerSlot <= 0 or containerSlot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid container slot.")
        return
    end
    if containerItemSlot <= 0 then
        Notify.player(source, "error", "Invalid container item slot.")
        return
    end
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive number.")
        return
    end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local containerItem = Inventory.getItemAtSlot(data.charId, containerSlot)
    if not containerItem then
        Notify.player(source, "error", "No container in slot " .. containerSlot .. ".")
        return
    end
    local containerDef = ItemRegistry.get(containerItem.inv_item_def_id)
    if not containerDef or not containerDef.isContainer then
        Notify.player(source, "error", "That item is not a container.")
        return
    end
    if containerItemSlot > containerDef.containerSlots then
        Notify.player(source, "error", "Invalid container item slot (max " .. containerDef.containerSlots .. ").")
        return
    end

    local contents = Inventory.getContainerContents(data.charId, containerSlot)
    if not contents then
        Notify.player(source, "error", "No container in slot " .. containerSlot .. " or it is not a container.")
        return
    end
    local item = contents[containerItemSlot]
    if not item then
        Notify.player(source, "error", "No item in container slot " .. containerItemSlot .. ".")
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    local itemName = (item.inv_item_custom_name or (def and def.name) or "Unknown")

    Inventory.retrieveFromContainer(data.charId, containerSlot, containerItemSlot, amount, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to retrieve item.")
            return
        end
        Notify.player(source, "success", string.format("Retrieved x%d %s from container (slot %d).", amount, itemName, containerSlot))
    end)
end, "Retrieve item from container: /retrieve <ContainerSlot> <ItemSlot> <Amount>")
