-- server/api/char_state.lua
-- Server-authoritative character state mutations.
--
-- ALL health, armour, and cash changes must go through these functions.
-- Never accept raw hp/ap values from client; use these to set and track state.
--
-- Health/armour scale: DB and this API use 0-100. The game native uses 0-200.
-- Cash: stored as INTEGER in DB (character_cash column).

CharState = {}

-- Internal multiplier: DB 0-100 <-> native 0-200.
local NATIVE_MULT = 2

-- ── Health ────────────────────────────────────────────────────────────────────

-- Sets health for a connected player (0-100 scale).
-- Writes authHp to Players cache and instructs the client to apply it.
-- Opens a heal window so the next health sync increase is accepted.
function CharState.setHealth(serverID, hp)
    hp = math.max(0, math.min(100, math.floor(tonumber(hp) or 0)))
    Players.set(serverID, { authHp = hp, healTargetHp = hp * NATIVE_MULT })
    CharState.openHealWindow(serverID, 5)
    pcall(Player.SetHealth, serverID, hp * NATIVE_MULT)
    Events.CallRemote("char_set_health", serverID, { hp })
end

-- Sets armour for a connected player (0-100 scale).
function CharState.setArmour(serverID, ap)
    ap = math.max(0, math.min(100, math.floor(tonumber(ap) or 0)))
    Players.set(serverID, { authAp = ap, healTargetAp = ap * NATIVE_MULT })
    CharState.openHealWindow(serverID, 5)
    pcall(Player.SetArmour, serverID, ap * NATIVE_MULT)
    Events.CallRemote("char_set_armour", serverID, { ap })
end

-- Opens a short window during which a client-reported HP/AP *increase* is
-- accepted (e.g. immediately after setHealth/setArmour).
-- H2: Track expected target values to cap accepted increases.
-- durationSecs: how long the window stays open (default 5).
function CharState.openHealWindow(serverID, durationSecs)
    Players.set(serverID, { healWindowExpiry = os.time() + (durationSecs or 5) })
end

-- Returns true if a heal window is currently open for this player.
function CharState.isHealWindowOpen(serverID)
    local data = Players.get(serverID)
    if not data or not data.healWindowExpiry then return false end
    return os.time() <= data.healWindowExpiry
end

-- Returns the max HP the client is allowed to report during a heal window (native scale).
function CharState.getHealTargetHp(serverID)
    local data = Players.get(serverID)
    return data and data.healTargetHp
end

-- Returns the max AP the client is allowed to report during a heal window (native scale).
function CharState.getHealTargetAp(serverID)
    local data = Players.get(serverID)
    return data and data.healTargetAp
end

-- ── Cash ──────────────────────────────────────────────────────────────────────

-- Adds cash to a character. amount must be > 0.
-- Uses atomic SQL to prevent race conditions from concurrent operations.
-- cb(newBalance) on success, cb(nil, errorMsg) on failure.
function CharState.giveCash(serverID, amount, cb)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        if cb then cb(nil, "Invalid amount.") end
        return
    end
    local data = Players.get(serverID)
    if not data or not data.charId then
        if cb then cb(nil, "Player not found.") end
        return
    end
    local charId = data.charId
    DB.execute(
        "UPDATE `characters` SET `character_cash` = `character_cash` + ? WHERE `character_id` = ?",
        { amount, charId },
        function()
            DB.select(
                "SELECT `character_cash` FROM `characters` WHERE `character_id` = ?",
                { charId },
                function(rows)
                    local newBalance = (rows and rows[1]) and tonumber(rows[1].character_cash) or 0
                    if cb then cb(newBalance) end
                end
            )
        end
    )
end

-- Deducts cash from a character. amount must be > 0.
-- Fails with an error if the balance is insufficient.
-- Uses atomic SQL with a WHERE guard to prevent overdraft from concurrent operations.
-- cb(newBalance) on success, cb(nil, errorMsg) on failure.
function CharState.takeCash(serverID, amount, cb)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        if cb then cb(nil, "Invalid amount.") end
        return
    end
    local data = Players.get(serverID)
    if not data or not data.charId then
        if cb then cb(nil, "Player not found.") end
        return
    end
    local charId = data.charId
    DB.execute(
        "UPDATE `characters` SET `character_cash` = `character_cash` - ? WHERE `character_id` = ? AND `character_cash` >= ?",
        { amount, charId, amount },
        function(affectedRows)
            if affectedRows == 0 then
                if cb then cb(nil, "Insufficient funds.") end
                return
            end
            DB.select(
                "SELECT `character_cash` FROM `characters` WHERE `character_id` = ?",
                { charId },
                function(rows)
                    local newBalance = (rows and rows[1]) and tonumber(rows[1].character_cash) or 0
                    if cb then cb(newBalance) end
                end
            )
        end
    )
end

-- Sends current cash and total bank balance to the client for HUD display.
-- Queries character_cash and sums all bank_account_balance for the character.
function CharState.syncMoneyHud(serverID)
    local data = Players.get(serverID)
    if not data or not data.charId then return end
    local charId = data.charId
    DB.select(
        "SELECT `character_cash` FROM `characters` WHERE `character_id` = ?",
        { charId },
        function(rows)
            local cash = (rows and rows[1]) and tonumber(rows[1].character_cash) or 0
            BankAccountModel.findAll({
                bank_account_owner_type = "character",
                bank_account_owner_id  = charId,
            }, function(accounts)
                    local bank = 0
                    if accounts then
                        for _, acct in ipairs(accounts) do
                            bank = bank + (tonumber(acct.bank_account_balance) or 0)
                        end
                    end
                    Events.CallRemote("hud_money_update", serverID, { cash, bank })
                end
            )
        end
    )
end

-- Reads the current cash balance from DB.
-- cb(balance) on success, cb(nil, errorMsg) on failure.
function CharState.getCash(serverID, cb)
    local data = Players.get(serverID)
    if not data or not data.charId then
        if cb then cb(nil, "Player not found.") end
        return
    end
    CharacterModel.findOne({ character_id = data.charId }, function(char)
        if not char then
            if cb then cb(nil, "Character not found.") end
            return
        end
        if cb then cb(tonumber(char.character_cash) or 0) end
    end)
end
