-- server/handlers/inventory_ui.lua
-- Handles remote events from the inventory WebUI.
-- Delegates actions to existing command handlers via ServerCmd.execute().
-- Toggle: /toggleinventoryui enables/disables the graphical inventory.

local _LOG_TAG = "InvUI"

-- Whitelist of commands the inventory UI is allowed to dispatch.
local ALLOWED_UI_ACTIONS = {
    useitem   = true,
    equip     = true,
    unequip   = true,
    giveitem  = true,
    moveitem  = true,
    nameitem  = true,
    removesn  = true,
    store     = true,
    retrieve  = true,
}

-- ── Helpers ───────────────────────────────────────────────────────────────

local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz
end

-- Find the nearest player within radius (for /giveitem from UI).
local function findNearestPlayer(source, radius)
    local sd = Players.get(source)
    if not sd then return nil end
    local sx, sy, sz = sd.posX, sd.posY, sd.posZ
    if not sx or not sy or not sz then return nil end
    local okS, srcSession = pcall(Player.GetSession, source)
    if not okS then return nil end

    local radiusSq = radius * radius
    local bestId, bestDist = nil, radiusSq + 1
    for serverID, _ in Players.all() do
        if serverID ~= source and Player.IsConnected(serverID) then
            local td = Players.get(serverID)
            if td and td.charId and td.posX and td.posY and td.posZ then
                local okT, tgtSession = pcall(Player.GetSession, serverID)
                if okT and tgtSession == srcSession then
                    local d = distSq(sx, sy, sz, td.posX, td.posY, td.posZ)
                    if d <= radiusSq and d < bestDist then
                        bestId = serverID
                        bestDist = d
                    end
                end
            end
        end
    end
    return bestId
end

-- ── Payload builders ──────────────────────────────────────────────────────

local function buildInventoryPayload(source, charId)
    local inv = Inventory.getInventory(charId)
    if not inv then return nil end

    local data = Players.get(source)
    local items = {}

    for slot = 1, Config.INVENTORY.MAX_SLOTS do
        if inv[slot] then
            local item = inv[slot]
            local def = ItemRegistry.get(item.inv_item_def_id)
            if def then
                -- Count container used slots and content weight
                local containerUsedSlots = 0
                local containerContentWeight = 0
                if def.isContainer then
                    local cid = item.inv_item_id
                    if inv._containers and inv._containers[cid] then
                        for _, cItem in pairs(inv._containers[cid]) do
                            containerUsedSlots = containerUsedSlots + 1
                            local cDef = ItemRegistry.get(cItem.inv_item_def_id)
                            if cDef then
                                containerContentWeight = containerContentWeight + (cDef.weight * cItem.inv_item_amount)
                            end
                        end
                    end
                end

                items[#items + 1] = {
                    slot             = item.inv_item_slot,
                    defId            = item.inv_item_def_id,
                    name             = item.inv_item_custom_name or def.name,
                    customName       = item.inv_item_custom_name,
                    category         = def.categoryName or def.category,
                    amount           = item.inv_item_amount,
                    maxStack         = def.maxStack,
                    weight           = def.weight,
                    totalWeight      = def.weight * item.inv_item_amount + containerContentWeight,
                    quality          = item.inv_item_quality,
                    purity           = item.inv_item_purity,
                    serial           = item.inv_item_serial,
                    isContainer      = def.isContainer or false,
                    containerSlots   = def.containerSlots,
                    containerMaxWeight = def.containerMaxWeight,
                    containerUsedSlots = containerUsedSlots,
                    isWeapon         = (def.category == ItemRegistry.Categories.WEAPON),
                    isAmmo           = (def.category == ItemRegistry.Categories.AMMO),
                }
            end
        end
    end

    return {
        items        = items,
        weight       = Inventory.getWeight(charId),
        maxWeight    = Config.INVENTORY.MAX_CARRY_WEIGHT,
        slotCount    = Inventory.getSlotCount(charId),
        maxSlots     = Config.INVENTORY.MAX_SLOTS,
        equippedSlot = data and data.equippedSlot or nil,
    }
end

local function buildContainerPayload(charId, containerSlot)
    local inv = Inventory.getInventory(charId)
    if not inv then return nil end
    local containerItem = inv[containerSlot]
    if not containerItem then return nil end
    local def = ItemRegistry.get(containerItem.inv_item_def_id)
    if not def or not def.isContainer then return nil end

    local contents = Inventory.getContainerContents(charId, containerSlot) or {}
    local items = {}
    for _, item in pairs(contents) do
        local cDef = ItemRegistry.get(item.inv_item_def_id)
        if cDef then
            items[#items + 1] = {
                slot        = item.inv_item_slot,
                defId       = item.inv_item_def_id,
                name        = item.inv_item_custom_name or cDef.name,
                category    = cDef.categoryName or cDef.category,
                amount      = item.inv_item_amount,
                maxStack    = cDef.maxStack,
                weight      = cDef.weight,
                totalWeight = cDef.weight * item.inv_item_amount,
                quality     = item.inv_item_quality,
                purity      = item.inv_item_purity,
                serial      = item.inv_item_serial,
            }
        end
    end

    return {
        containerSlot  = containerSlot,
        containerName  = containerItem.inv_item_custom_name or def.name,
        items          = items,
        slotCount      = #items,
        maxSlots       = def.containerSlots,
        weight         = Inventory.getContainerWeight(charId, containerSlot),
        maxWeight      = def.containerMaxWeight,
    }
end

local function refreshInventory(source, charId)
    local payload = buildInventoryPayload(source, charId)
    if payload then
        Events.CallRemote("inv_data", source, { payload })
    end
end

-- ── /toggleinventoryui ────────────────────────────────────────────────────

ServerCmd.register("toggleinventoryui", function(source)
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end
    data.useInventoryUI = not data.useInventoryUI
    CharacterModel.update({ character_use_inventory_ui = data.useInventoryUI and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("inv_ui_toggle", source, { data.useInventoryUI })
    Notify.player(source, "success", "Inventory UI " .. (data.useInventoryUI and "enabled" or "disabled") .. ".")
end, "Toggle graphical inventory UI")

-- ── inv_open ──────────────────────────────────────────────────────────────
-- Client sends {} (empty table) via Events.CallRemote("inv_open", {}).

Events.Subscribe("inv_open", function(payload)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end
    refreshInventory(source, data.charId)
end, true)

-- ── inv_drop ─────────────────────────────────────────────────────────────
-- Dedicated drop handler: client sends { slot, amount } (both strings).

Events.Subscribe("inv_drop", function(slotArg, amountArg)
    -- HappinessMP unpacks the table into separate args.
    if type(slotArg) == "table" then slotArg, amountArg = slotArg[1], slotArg[2] end
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end

    local slot   = math.floor(tonumber(slotArg) or 0)
    local amount = math.floor(tonumber(amountArg) or 0)
    if slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then
        Notify.player(source, "error", "Invalid slot number.")
        return
    end
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive number.")
        return
    end

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
        refreshInventory(source, data.charId)
    end)
end, true)

-- ── inv_action ────────────────────────────────────────────────────────────
-- Universal dispatcher: client sends { commandName, arg1, arg2, ... }.
-- HappinessMP passes the table as the first function argument.

Events.Subscribe("inv_action", function(...)
    -- HappinessMP unpacks table args into separate function params.
    local rawArgs = {...}
    -- Defensive: if first arg is a table, it might be the whole payload.
    local payload
    if #rawArgs == 1 and type(rawArgs[1]) == "table" then
        payload = rawArgs[1]
    else
        payload = rawArgs
    end

    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local cmdName = tostring(payload[1] or "")
    if cmdName == "" then return end
    if not ALLOWED_UI_ACTIONS[cmdName] then return end

    -- Special case: "giveitem" from UI sends { "giveitem", slot, amount }
    -- but the command expects { playerID, slot, amount }. Find nearest player.
    if cmdName == "giveitem" then
        local nearestId = findNearestPlayer(source, Config.INVENTORY.GIVE_RADIUS)
        if not nearestId then
            Notify.player(source, "error", "No player nearby to give items to.")
            Thread.Create(function()
                Thread.Pause(300)
                refreshInventory(source, data.charId)
            end)
            return
        end
        local slot   = payload[2] and tostring(payload[2]) or ""
        local amount = payload[3] and tostring(payload[3]) or ""
        local args = { tostring(nearestId), slot, amount }
        local full = table.concat(args, " ")
        ServerCmd.execute(source, cmdName, args, full)
        Thread.Create(function()
            Thread.Pause(300)
            refreshInventory(source, data.charId)
        end)
        return
    end

    -- Build args array (everything after the command name)
    local args = {}
    for i = 2, #payload do
        args[#args + 1] = tostring(payload[i])
    end

    -- Build the full string for commands that parse it (e.g., /nameitem)
    local full = table.concat(args, " ")

    -- Execute via existing command handler
    ServerCmd.execute(source, cmdName, args, full)

    -- Push updated inventory to UI after a short delay to allow async callbacks to complete.
    Thread.Create(function()
        Thread.Pause(300)
        refreshInventory(source, data.charId)
    end)
end, true)

-- ── inv_container_open ────────────────────────────────────────────────────

Events.Subscribe("inv_container_open", function(slotArg)
    if type(slotArg) == "table" then slotArg = slotArg[1] end
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    local data = Players.get(source)
    if not data or not data.charId then return end

    local slot = tonumber(slotArg)
    if not slot or slot <= 0 or slot > Config.INVENTORY.MAX_SLOTS then return end

    local containerPayload = buildContainerPayload(data.charId, slot)
    if containerPayload then
        Events.CallRemote("inv_container_data", source, { containerPayload })
    else
        Notify.player(source, "error", "That item is not a container.")
    end
end, true)
