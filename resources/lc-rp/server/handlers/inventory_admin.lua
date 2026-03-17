-- server/handlers/inventory_admin.lua
-- Staff commands: /agiveitem, /deleteitem, /inspectitem
-- All gated behind Guard.requireStaff().

local _LOG_TAG = "InvAdmin"

-- ── /agiveitem (/agi) ────────────────────────────────────────────────────────

ServerCmd.register("agiveitem", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /agiveitem <ItemID/Name> [Amount] [PlayerID]")
        return
    end

    local defId, defErr = Resolve.itemDef(args[1])
    if not defId then
        if defErr == "ambiguous" then
            local matches = ItemRegistry.searchByName(args[1])
            local names = {}
            for _, mid in ipairs(matches) do
                local d = ItemRegistry.get(mid)
                names[#names + 1] = string.format("[%d] %s", mid, d.name)
            end
            Notify.player(source, "error", "Multiple items match. Be more specific: " .. table.concat(names, ", "))
        else
            Notify.player(source, "error", "Item not found: " .. args[1])
        end
        return
    end

    local amount = math.floor(tonumber(args[2]) or 1)
    if amount <= 0 then amount = 1 end

    local def = ItemRegistry.get(defId)
    if amount > def.maxStack then
        Notify.player(source, "error", string.format("Max stack for %s is %d.", def.name, def.maxStack))
        return
    end

    -- Determine target (self or specified player).
    local targetID = source
    if args[3] then
        local resolved, resolveErr = Resolve.player(args[3])
        if not resolved then
            if resolveErr == "ambiguous" then
                Notify.player(source, "error", "Multiple players match '" .. args[3] .. "'. Use their ID.")
            else
                Notify.player(source, "error", "Player not found: " .. args[3])
            end
            return
        end
        targetID = resolved
    end

    local targetData = Players.get(targetID)
    if not targetData or not targetData.charId then
        Notify.player(source, "error", "Target has no active character.")
        return
    end

    Inventory.addItem(targetData.charId, defId, amount, {}, function(item, err)
        if not item then
            Notify.player(source, "error", err or "Failed to give item.")
            return
        end
        local adminData = Players.get(source)
        local adminCharId = (adminData and adminData.charId) or -1
        Inventory.logTransfer("admin_create", defId, amount, nil, nil, "character", targetData.charId, adminCharId)

        local targetName = Player.GetName(targetID) or tostring(targetID)
        local serialInfo = item.inv_item_serial and (" (S/N: " .. item.inv_item_serial .. ")") or ""
        if targetID == source then
            Notify.player(source, "success", string.format("Gave yourself x%d %s%s (slot %d).", amount, def.name, serialInfo, item.inv_item_slot))
        else
            Notify.player(source, "success", string.format("Gave x%d %s%s to %s (slot %d).", amount, def.name, serialInfo, targetName, item.inv_item_slot))
            Notify.player(targetID, "info", string.format("An admin gave you x%d %s.", amount, def.name))
        end
        Log.info(_LOG_TAG, string.format("Admin %s (%d) gave x%d %s (def=%d) to %s (%d)",
            Player.GetName(source) or tostring(source), source, amount, def.name, defId, targetName, targetID))
    end)
end, "Admin give item: /agiveitem <ItemID/Name> [Amount] [PlayerID]", { "agi" })

-- ── /deleteitem ─────────────────────────────────────────────────────────────

-- L14: /deleteitem now accepts optional target player parameter.
ServerCmd.register("deleteitem", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /deleteitem <SlotID> [Amount] [PlayerID/Name]")
        return
    end

    local slot = math.floor(tonumber(args[1]) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end

    local targetID = source
    if args[3] then
        local resolved, resolveErr = Resolve.player(args[3])
        if not resolved then
            if resolveErr == "ambiguous" then
                Notify.player(source, "error", "Multiple players match '" .. args[3] .. "'. Use their ID.")
            else
                Notify.player(source, "error", "Player not found: " .. args[3])
            end
            return
        end
        targetID = resolved
    end

    local data = Players.get(targetID)
    if not data or not data.charId then
        Notify.player(source, "error", "Target has no active character.")
        return
    end

    local item = Inventory.getItemAtSlot(data.charId, slot)
    if not item then
        Notify.player(source, "error", "No item in slot " .. slot .. ".")
        return
    end

    local def = ItemRegistry.get(item.inv_item_def_id)
    local itemName = (item.inv_item_custom_name or (def and def.name) or "Unknown")
    local amount = math.floor(tonumber(args[2]) or item.inv_item_amount)
    if amount <= 0 then amount = item.inv_item_amount end
    if amount > item.inv_item_amount then amount = item.inv_item_amount end

    Inventory.removeItem(data.charId, slot, amount, function(result, err)
        if not result then
            Notify.player(source, "error", err or "Failed to delete item.")
            return
        end
        Inventory.logTransfer("admin_delete", item.inv_item_def_id, amount, "character", data.charId, nil, nil, data.charId)
        Notify.player(source, "success", string.format("Deleted x%d %s from slot %d.", amount, itemName, slot))
        Log.info(_LOG_TAG, string.format("Admin %s (%d) deleted x%d %s from slot %d",
            Player.GetName(source) or tostring(source), source, amount, itemName, slot))
    end)
end, "Delete item from inventory: /deleteitem <Slot> [Amount]")

-- ── /inspectitem (/ii) ──────────────────────────────────────────────────────

ServerCmd.register("inspectitem", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /inspectitem <PlayerID/Name>")
        return
    end

    local targetID, resolveErr = Resolve.player(args[1])
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match '" .. args[1] .. "'. Use their ID.")
        else
            Notify.player(source, "error", "Player not found: " .. args[1])
        end
        return
    end

    local targetData = Players.get(targetID)
    if not targetData or not targetData.charId then
        Notify.player(source, "error", "Target has no active character.")
        return
    end

    local targetName = Player.GetName(targetID) or tostring(targetID)
    Notify.player(source, "info", "--- Inspecting " .. targetName .. "'s inventory ---")

    local lines = Inventory.formatInventory(targetData.charId)
    for _, line in ipairs(lines) do
        Notify.player(source, "info", line)
    end
end, "View player inventory: /inspectitem <PlayerID/Name>", { "ii" })
