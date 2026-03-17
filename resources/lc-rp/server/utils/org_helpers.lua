-- server/utils/org_helpers.lua
-- Shared constants and helpers for the faction/company organization system.
--
-- Usage:
--   OrgPerms.INVITE                          -- permission bitmask constant
--   OrgHelpers.hasPerm(bitmask, perm)        -- check if bitmask includes perm
--   OrgHelpers.isLeader(rankOrder)           -- true if rank order == 1
--   OrgHelpers.allPerms()                    -- bitmask with all permissions set
--   OrgHelpers.getDepth(model, idCol, parentCol, entityId, cb)  -- get hierarchy depth

-- ── Permission bitmask constants ───────────────────────────────────────────────

OrgPerms = {
    INVITE       = 1,    -- 2^0
    KICK         = 2,    -- 2^1
    PROMOTE      = 4,    -- 2^2
    DEMOTE       = 8,    -- 2^3
    MANAGE_RANKS = 16,   -- 2^4
    MANAGE_BANK  = 32,   -- 2^5
    SET_MOTD     = 64,   -- 2^6
    DUTY         = 128,  -- 2^7 (police/ems/fire only)
}

-- ── Valid enum values ──────────────────────────────────────────────────────────

OrgFactionTypes = {
    illegal = true, government = true, police = true, ems = true,
    fire = true, news = true, legal = true, other = true,
}

OrgCompanyTypes = {
    llc = true, sole_proprietorship = true, partnership = true,
    corporation = true, nonprofit = true,
}

-- Faction types that support the /fduty command.
OrgDutyFactionTypes = {
    police = true, ems = true, fire = true,
}

-- ── Helper functions ───────────────────────────────────────────────────────────

OrgHelpers = {}

--- Returns true if the bitmask includes the given permission.
function OrgHelpers.hasPerm(bitmask, perm)
    return bit32.band(bitmask, perm) ~= 0
end

--- Returns true if rankOrder is 1 (leader rank).
function OrgHelpers.isLeader(rankOrder)
    return rankOrder == 1
end

--- Returns a bitmask with all permissions set.
function OrgHelpers.allPerms()
    local mask = 0
    for _, v in pairs(OrgPerms) do
        mask = bit32.bor(mask, v)
    end
    return mask
end

--- Checks if the caller has a specific permission in their faction/company.
--- Leaders (rank_order == 1) implicitly have all permissions.
--- Returns true if the caller has the permission.
function OrgHelpers.hasPermOrLeader(rankOrder, rankPermissions, perm)
    if rankOrder == 1 then return true end
    return OrgHelpers.hasPerm(rankPermissions, perm)
end

--- Resolves the root (top-level) entity by walking the parent chain.
--- model: the Model (FactionModel or CompanyModel)
--- idCol: primary key column name (e.g. "faction_id")
--- parentCol: parent FK column name (e.g. "faction_parent_id")
--- entityId: the ID to start from
--- callback: function(rootEntity) or function(nil) on error
function OrgHelpers.getRoot(model, idCol, parentCol, entityId, callback)
    local maxDepth = 3
    local function walk(currentId, depth)
        if depth > maxDepth then
            callback(nil)
            return
        end
        model.findOne({ [idCol] = currentId }, function(entity)
            if not entity then
                callback(nil)
                return
            end
            if not entity[parentCol] then
                -- This is the root.
                callback(entity)
            else
                walk(entity[parentCol], depth + 1)
            end
        end)
    end
    walk(entityId, 1)
end

--- Gets the depth of an entity in the hierarchy (1 = top-level, 2 = sub, 3 = department).
--- model, idCol, parentCol: same as getRoot.
--- callback: function(depth) or function(nil) on error.
function OrgHelpers.getDepth(model, idCol, parentCol, entityId, callback)
    local maxDepth = 3
    local function walk(currentId, depth)
        if depth > maxDepth then
            callback(nil)
            return
        end
        model.findOne({ [idCol] = currentId }, function(entity)
            if not entity then
                callback(nil)
                return
            end
            if not entity[parentCol] then
                callback(depth)
            else
                walk(entity[parentCol], depth + 1)
            end
        end)
    end
    walk(entityId, 1)
end

--- Generates a unique 9-digit routing number for bank accounts.
--- Checks for uniqueness against existing routing numbers.
--- callback: function(routingNumber)
function OrgHelpers.generateRoutingNumber(callback)
    local maxAttempts = 50
    local attempts = 0
    local function tryGenerate()
        attempts = attempts + 1
        if attempts > maxAttempts then
            Log.error("OrgHelpers", "Failed to generate unique routing number after " .. maxAttempts .. " attempts.")
            callback(nil)
            return
        end
        local num = ""
        for _ = 1, 9 do
            num = num .. tostring(math.random(0, 9))
        end
        BankAccountModel.findOne({ bank_account_routing_number = num }, function(existing)
            if existing then
                tryGenerate() -- collision, try again
            else
                callback(num)
            end
        end)
    end
    tryGenerate()
end
