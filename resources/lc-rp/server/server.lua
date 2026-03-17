-- server.lua
-- Main server entry point.
-- Handles DB lifecycle, runs migrations, and wires up core player events.

-- Helper: checks whether a column exists in a table (works with both SQLite and MySQL).
local function hasColumn(tableName, columnName, callback)
    local colQuery = (DB.type == 1)
        and ("PRAGMA table_info(" .. tableName .. ")")
        or ("SHOW COLUMNS FROM `" .. tableName .. "`")
    DB.select(colQuery, {}, function(rows)
        if not rows then callback(false) return end
        for _, r in ipairs(rows) do
            local colName = r.name or r.Field or r.field
            if colName == columnName then callback(true) return end
        end
        callback(false)
    end)
end

-- Register migrations (run in order after table sync).
Migrations.register("add_account_last_logout_date", function(done)
    hasColumn("accounts", "account_last_logout_date", function(exists)
        if exists then done() return end
        local colType = (DB.type == 1) and "TEXT" or "VARCHAR(191)"
        DB.execute("ALTER TABLE `accounts` ADD COLUMN `account_last_logout_date` " .. colType, {}, done)
    end)
end)

Migrations.register("add_character_appearance", function(done)
    hasColumn("characters", "character_appearance", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_appearance` TEXT", {}, done)
    end)
end)

Migrations.register("add_character_cash", function(done)
    hasColumn("characters", "character_cash", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_cash` REAL NOT NULL DEFAULT 1500.00", {}, done)
    end)
end)

-- M3: Cast character_cash from REAL to INTEGER — use INTEGER for SQLite, SIGNED for MySQL.
Migrations.register("cast_character_cash_to_integer", function(done)
    local castType = (DB.type == 1) and "INTEGER" or "SIGNED"
    DB.execute("UPDATE `characters` SET `character_cash` = CAST(`character_cash` AS " .. castType .. ")", {}, done)
end)

Migrations.register("cast_bank_balances_to_integer", function(done)
    local castType = (DB.type == 1) and "INTEGER" or "SIGNED"
    DB.execute("UPDATE `bank_accounts` SET `bank_account_balance` = CAST(`bank_account_balance` AS " .. castType .. ")", {}, function()
        DB.execute(
            "UPDATE `bank_transactions` SET `bank_transaction_amount` = CAST(`bank_transaction_amount` AS " .. castType .. "), `bank_transaction_balance_after` = CAST(`bank_transaction_balance_after` AS " .. castType .. ")",
            {}, done
        )
    end)
end)

-- L13: Add composite unique constraint for (account_id, slot_id) on characters.
Migrations.register("add_character_account_slot_unique", function(done)
    if DB.type == 1 then
        -- SQLite: CREATE UNIQUE INDEX IF NOT EXISTS
        DB.execute("CREATE UNIQUE INDEX IF NOT EXISTS `idx_char_account_slot` ON `characters` (`character_account_id`, `character_slot_id`)", {}, done)
    else
        -- MySQL: check if index exists first, then create if not.
        DB.select("SHOW INDEX FROM `characters` WHERE Key_name = 'idx_char_account_slot'", {}, function(rows)
            if rows and #rows > 0 then
                done()
            else
                DB.execute("ALTER TABLE `characters` ADD UNIQUE INDEX `idx_char_account_slot` (`character_account_id`, `character_slot_id`)", {}, done)
            end
        end)
    end
end)

Migrations.register("add_dropped_item_account_id", function(done)
    hasColumn("dropped_items", "dropped_item_account_id", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `dropped_items` ADD COLUMN `dropped_item_account_id` INTEGER NOT NULL DEFAULT 0", {}, done)
    end)
end)

Migrations.register("seed_item_definitions", function(done)
    local allIds = ItemRegistry.allIds()
    if #allIds == 0 then done() return end

    -- M8: Track both success and failure to prevent hanging if a callback never fires.
    local seeded = 0
    local total = #allIds
    local doneCalled = false
    local function onSeeded()
        seeded = seeded + 1
        if seeded == total and not doneCalled then
            doneCalled = true
            Log.info("DB", "Seeded " .. seeded .. " item definition(s).")
            done()
        end
    end

    -- Safety timeout: if callbacks stall, force completion after 30 seconds.
    Thread.Create(function()
        Thread.Pause(30000)
        if not doneCalled then
            doneCalled = true
            Log.error("DB", "seed_item_definitions timed out after 30s (" .. seeded .. "/" .. total .. " completed). Continuing startup.")
            done()
        end
    end)

    for _, defId in ipairs(allIds) do
        local row = ItemRegistry.toDbRow(defId)
        if row then
            ItemDefinitionModel.upsert(
                { item_def_id = defId },
                {
                    item_def_category             = row.item_def_category,
                    item_def_name                 = row.item_def_name,
                    item_def_description          = row.item_def_description,
                    item_def_weight               = row.item_def_weight,
                    item_def_max_stack            = row.item_def_max_stack,
                    item_def_is_container         = row.item_def_is_container,
                    item_def_container_slots      = row.item_def_container_slots,
                    item_def_container_max_weight = row.item_def_container_max_weight,
                    item_def_has_quality          = row.item_def_has_quality,
                    item_def_has_purity           = row.item_def_has_purity,
                    item_def_has_serial           = row.item_def_has_serial,
                },
                function()
                    onSeeded()
                end
            )
        else
            onSeeded()
        end
    end
end)

Migrations.register("add_character_use_inventory_ui", function(done)
    hasColumn("characters", "character_use_inventory_ui", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_use_inventory_ui` INTEGER NOT NULL DEFAULT 0", {}, done)
    end)
end)

Migrations.register("add_character_chat_prefs", function(done)
    hasColumn("characters", "character_chat_font_size", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_chat_font_size` INTEGER NOT NULL DEFAULT 12", {}, function()
            DB.execute("ALTER TABLE `characters` ADD COLUMN `character_chat_page_size` INTEGER NOT NULL DEFAULT 20", {}, done)
        end)
    end)
end)

Migrations.register("add_character_use_ui_notifications", function(done)
    hasColumn("characters", "character_use_ui_notifications", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_use_ui_notifications` INTEGER NOT NULL DEFAULT 0", {}, done)
    end)
end)

Migrations.register("add_character_show_money_hud", function(done)
    hasColumn("characters", "character_show_money_hud", function(exists)
        if exists then done() return end
        DB.execute("ALTER TABLE `characters` ADD COLUMN `character_show_money_hud` INTEGER NOT NULL DEFAULT 1", {}, done)
    end)
end)

Events.Subscribe("resourceStart", function(resource)
    if resource ~= Resource.GetCurrentName() then return end

    DB.connect()

    -- H5: Sequential sync with error handling. If any step fails, log and abort.
    local models = {
        AccountModel, CharacterModel, BankAccountModel, BankTransactionModel,
        ItemDefinitionModel, InventoryItemModel, DroppedItemModel, ItemTransferModel,
        FactionModel, FactionRankModel, FactionMemberModel,
        CompanyModel, CompanyRankModel, CompanyMemberModel,
    }
    local function syncNext(i)
        if i > #models then
            Migrations.runAll(function()
                AccountModel.update({ account_is_logged_in_game = 0, account_is_logged_in_ucp = 0 }, {}, function()
                    CharacterModel.update({ character_is_logged_in_game = 0 }, {}, function()
                        Log.info("Server", "Cleared all account and character login flags.")
                        Inventory.loadDroppedItems(function()
                            Thread.Create(function()
                                while true do
                                    Thread.Pause(300000) -- 5 minutes
                                    Inventory.cleanupExpiredDrops()
                                end
                            end)
                            -- Weapon audit heartbeat check (every 30 seconds).
                            Thread.Create(function()
                                while true do
                                    Thread.Pause(30000)
                                    if CheckWeaponAuditHeartbeats then
                                        CheckWeaponAuditHeartbeats()
                                    end
                                end
                            end)
                            -- Anti-cheat: health & position cross-checks (every 15 seconds).
                            Thread.Create(function()
                                while true do
                                    Thread.Pause(15000)
                                    if RunAntiCheatChecks then
                                        RunAntiCheatChecks()
                                    end
                                end
                            end)
                        end)
                    end)
                end)
            end)
            return
        end
        models[i].sync(function(_, err)
            if err then
                Log.error("Server", "FATAL: Table sync failed at step " .. i .. ": " .. tostring(err))
            end
            syncNext(i + 1)
        end)
    end
    syncNext(1)
end)

Events.Subscribe("resourceStop", function(resource)
    if resource ~= Resource.GetCurrentName() then return end

    DB.close()
end)

Events.Subscribe("playerDisconnect", function(serverID, name, reason)
    local reasonStr = reason == 0 and "Timed Out" or reason == 1 and "Quit" or "Kicked"
    Log.info("Server", name .. " (" .. serverID .. ") disconnected: " .. reasonStr)

    -- Snapshot character data from cache and player API before the player is torn down.
    local data = Players.get(serverID)
    local snapshot = nil
    if data and data.charId then
        local okSession, session = pcall(function() return Player.GetSession(serverID) end)

        -- Read position natively from the server — not from the client-reported cache.
        local nativeX, nativeY, nativeZ = data.posX, data.posY, data.posZ
        local okPos, px, py, pz = pcall(function() return Player.GetPosition(serverID) end)
        if okPos and px and py and pz then
            nativeX, nativeY, nativeZ = px, py, pz
        end

        snapshot = {
            charId    = data.charId,
            posX      = nativeX,
            posY      = nativeY,
            posZ      = nativeZ,
            posR      = data.posR,    -- heading is client-reported; clamped in Char_OnDisconnect
            -- Health/armour fallback chain (all three stored by char handler):
            authHp    = data.authHp,  -- set by CharState.setHealth (most trusted)
            authAp    = data.authAp,  -- set by CharState.setArmour (most trusted)
            syncHp    = data.syncHp,  -- validated client delta via rp_health_sync
            syncAp    = data.syncAp,  -- validated client delta via rp_health_sync
            dbHp      = data.dbHp,    -- value loaded from DB at spawn (safe fallback)
            dbAp      = data.dbAp,    -- value loaded from DB at spawn
            loginTime = data.loginTime,
            session   = (okSession and session ~= nil) and session or 0,
        }
    end

    -- Return equipped ammo to inventory before unloading (ammo was removed on equip).
    if data and data.charId and data.equippedAmmoGroup and data.serverLastAmmo and data.serverLastAmmo > 0 then
        Inventory.returnAmmoByGroup(data.charId, data.equippedAmmoGroup, data.serverLastAmmo, function(result, err)
            if result then
                Log.info("AmmoReturn", string.format("Disconnect: returned %d rounds of %s for char %d",
                    data.serverLastAmmo, data.equippedAmmoGroup, data.charId))
            else
                Log.warn("AmmoReturn", string.format("Disconnect: failed to return ammo for char %d: %s",
                    data.charId, err or "unknown"))
            end
        end)
    end

    -- Unload inventory cache for this character.
    if data and data.charId then
        Inventory.unloadForCharacter(data.charId)
    end

    -- H7: Clear character creation lock on disconnect.
    if Char_ClearCreatingFlag then Char_ClearCreatingFlag(serverID) end
    -- Clear command rate-limit state.
    if ServerCmd and ServerCmd.clearPlayerState then ServerCmd.clearPlayerState(serverID) end

    -- Clear player from cache immediately so we don't depend on it after this.
    if Chat then
        if Chat.clearPlayerState then Chat.clearPlayerState(serverID) end
        if Chat.clearSyncState then Chat.clearSyncState(serverID) end
    end
    Auth_OnDisconnect(serverID)

    -- Persist character from snapshot only (no player API from here on).
    if snapshot then
        Char_OnDisconnect(snapshot)
    end
end)
