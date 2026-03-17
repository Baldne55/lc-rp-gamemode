-- server/handlers/pay.lua
-- /pay <ID or Name> <amount> — transfer cash from the sender to another in-game player.
-- Both sender and receiver are notified; the sender is refunded if the credit step fails.

local _LOG_TAG = "Pay"
local PAY_PROXIMITY_RADIUS = 5

-- Helper: squared distance between two players using cached positions.
local function payDistSq(sourceData, targetData)
    local sx, sy, sz = sourceData.posX, sourceData.posY, sourceData.posZ
    local tx, ty, tz = targetData.posX, targetData.posY, targetData.posZ
    if not (sx and sy and sz and tx and ty and tz) then return nil end
    local dx, dy, dz = sx - tx, sy - ty, sz - tz
    return dx * dx + dy * dy + dz * dz
end

ServerCmd.register("pay", function(source, args)
    if #args < 2 then
        Notify.player(source, "error", "Usage: /pay <ID or Name> <amount>")
        return
    end

    local amount = math.floor(tonumber(args[2]) or 0)
    if amount <= 0 then
        Notify.player(source, "error", "Amount must be a positive whole number.")
        return
    end
    if amount > Config.PAY.MAX_AMOUNT then
        Notify.player(source, "error", string.format("Maximum single payment is $%d.", Config.PAY.MAX_AMOUNT))
        return
    end

    -- M10: Use shared Resolve.player instead of duplicated local function.
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
        Notify.player(source, "error", "You cannot pay yourself.")
        return
    end

    -- H8: Proximity check — must be within PAY_PROXIMITY_RADIUS.
    local sourceData = Players.get(source)
    local targetData = Players.get(targetID)
    if sourceData and targetData then
        local dSq = payDistSq(sourceData, targetData)
        if dSq and dSq > PAY_PROXIMITY_RADIUS * PAY_PROXIMITY_RADIUS then
            Notify.player(source, "error", "You are too far away to pay this player.")
            return
        end
    end

    local senderName = Player.GetName(source)  or tostring(source)
    local targetName = Player.GetName(targetID) or tostring(targetID)
    local senderCharId = sourceData and sourceData.charId or 0
    local targetCharId = targetData and targetData.charId or 0

    -- Atomic transfer: debit sender and credit receiver in a single statement.
    -- The WHERE guard on sender's balance prevents overdraft.
    DB.execute(
        "UPDATE `characters` SET `character_cash` = CASE " ..
        "WHEN `character_id` = ? THEN `character_cash` - ? " ..
        "WHEN `character_id` = ? THEN `character_cash` + ? " ..
        "END WHERE `character_id` IN (?, ?) " ..
        "AND EXISTS (SELECT 1 FROM (SELECT `character_cash` FROM `characters` WHERE `character_id` = ?) AS t WHERE t.`character_cash` >= ?)",
        { senderCharId, amount, targetCharId, amount, senderCharId, targetCharId, senderCharId, amount },
        function(affectedRows)
            if not affectedRows or affectedRows == 0 then
                Notify.player(source, "error", "Insufficient funds.")
                return
            end

            -- Read back sender balance for display.
            DB.select(
                "SELECT `character_cash` FROM `characters` WHERE `character_id` = ?",
                { senderCharId },
                function(rows)
                    local newSenderBalance = (rows and rows[1]) and tonumber(rows[1].character_cash) or 0
                    Notify.player(source,   "success", string.format("You paid %s $%d. Balance: $%d.", targetName, amount, newSenderBalance))
                    Notify.player(targetID, "success", string.format("%s paid you $%d.", senderName, amount))
                end
            )

            -- Update money HUD for both players.
            CharState.syncMoneyHud(source)
            CharState.syncMoneyHud(targetID)

            -- H9: Audit trail for cash transfers.
            ItemTransferModel.create({
                transfer_type         = "cash_pay",
                transfer_item_def_id  = 0,
                transfer_amount       = amount,
                transfer_from_type    = "character",
                transfer_from_id      = senderCharId,
                transfer_to_type      = "character",
                transfer_to_id        = targetCharId,
                transfer_character_id = senderCharId,
            })

            Log.info(_LOG_TAG, string.format(
                "%s (%d) paid %s (%d) $%d.", senderName, source, targetName, targetID, amount
            ))
        end
    )
end, "Pay a player: /pay <ID or Name> <amount>")

-- ── /togglemoneyhud ─────────────────────────────────────────────────────────

ServerCmd.register("togglemoneyhud", function(source)
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end
    data.showMoneyHud = not data.showMoneyHud
    CharacterModel.update({ character_show_money_hud = data.showMoneyHud and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("hud_money_toggle", source, { data.showMoneyHud })
    Notify.player(source, "success", "Money HUD " .. (data.showMoneyHud and "enabled" or "disabled") .. ".")
end, "Toggle money HUD: /togglemoneyhud")

-- ── /toggleuinotifications ──────────────────────────────────────────────────

ServerCmd.register("toggleuinotifications", function(source)
    if not Guard.requireChar(source) then return end
    local data = Players.get(source)
    if not data or not data.charId then return end
    data.useUINotifications = not data.useUINotifications
    CharacterModel.update({ character_use_ui_notifications = data.useUINotifications and 1 or 0 }, { character_id = data.charId })
    Events.CallRemote("notify_ui_toggle", source, { data.useUINotifications })
    Notify.player(source, "success", "UI notifications " .. (data.useUINotifications and "enabled" or "disabled") .. ".")
end, "Toggle UI notifications: /toggleuinotifications")
