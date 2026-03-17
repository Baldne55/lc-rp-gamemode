-- server/api/org.lua
-- Shared organization API for factions and companies.
-- Handles loading membership data into the Players cache on character login,
-- and provides helpers for updating the cache when membership changes.
--
-- Usage:
--   Org.loadMemberData(source, charId, callback)  -- load all memberships into Players cache
--   Org.cacheFactionMember(source, member, rank, faction)  -- add/update a faction in cache
--   Org.removeCachedFaction(source, factionId)             -- remove a faction from cache
--   Org.cacheCompanyMember(source, member, rank, company)  -- add/update a company in cache
--   Org.removeCachedCompany(source, companyId)             -- remove a company from cache
--   Org.getFactionMembership(source, factionId)            -- get cached faction membership
--   Org.getCompanyMembership(source, companyId)            -- get cached company membership
--   Org.getFirstFaction(source)                            -- get first cached faction (for /f commands)
--   Org.getFirstCompany(source)                            -- get first cached company (for /c commands)

Org = {}

local _LOG_TAG = "Org"

--- Loads all faction and company memberships for a character into the Players cache.
--- Called during character login/spawn.
--- callback: function() when done.
function Org.loadMemberData(source, charId, callback)
    -- Load faction memberships.
    FactionMemberModel.findAll({ faction_member_character_id = charId }, function(factionMembers)
        local factions = {}
        local fPending = #factionMembers

        if fPending == 0 then
            -- No faction memberships; proceed to companies.
            Players.set(source, { factions = factions })
            Org._loadCompanyData(source, charId, callback)
            return
        end

        for _, fm in ipairs(factionMembers) do
            -- Look up the rank and faction for each membership.
            FactionRankModel.findOne({ faction_rank_id = fm.faction_member_rank_id }, function(rank)
                FactionModel.findOne({ faction_id = fm.faction_member_faction_id }, function(faction)
                    if rank and faction then
                        -- Resolve root faction for the name/type.
                        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", fm.faction_member_faction_id, function(root)
                            local rootFaction = root or faction
                            factions[#factions + 1] = {
                                memberId    = fm.faction_member_id,
                                factionId   = fm.faction_member_faction_id,
                                rootId      = rootFaction.faction_id,
                                factionName = rootFaction.faction_name,
                                factionType = rootFaction.faction_type,
                                rankId      = rank.faction_rank_id,
                                rankOrder   = rank.faction_rank_order,
                                rankName    = rank.faction_rank_name,
                                rankPerms   = rank.faction_rank_permissions,
                            }
                            fPending = fPending - 1
                            if fPending == 0 then
                                Players.set(source, { factions = factions })
                                Org._loadCompanyData(source, charId, callback)
                            end
                        end)
                    else
                        fPending = fPending - 1
                        if fPending == 0 then
                            Players.set(source, { factions = factions })
                            Org._loadCompanyData(source, charId, callback)
                        end
                    end
                end)
            end)
        end
    end)
end

--- Internal: loads company memberships (called after faction loading).
function Org._loadCompanyData(source, charId, callback)
    CompanyMemberModel.findAll({ company_member_character_id = charId }, function(companyMembers)
        local companies = {}
        local cPending = #companyMembers

        if cPending == 0 then
            Players.set(source, { companies = companies })
            if callback then callback() end
            return
        end

        for _, cm in ipairs(companyMembers) do
            CompanyRankModel.findOne({ company_rank_id = cm.company_member_rank_id }, function(rank)
                CompanyModel.findOne({ company_id = cm.company_member_company_id }, function(company)
                    if rank and company then
                        OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", cm.company_member_company_id, function(root)
                            local rootCompany = root or company
                            companies[#companies + 1] = {
                                memberId    = cm.company_member_id,
                                companyId   = cm.company_member_company_id,
                                rootId      = rootCompany.company_id,
                                companyName = rootCompany.company_name,
                                companyType = rootCompany.company_type,
                                rankId      = rank.company_rank_id,
                                rankOrder   = rank.company_rank_order,
                                rankName    = rank.company_rank_name,
                                rankPerms   = rank.company_rank_permissions,
                            }
                            cPending = cPending - 1
                            if cPending == 0 then
                                Players.set(source, { companies = companies })
                                if callback then callback() end
                            end
                        end)
                    else
                        cPending = cPending - 1
                        if cPending == 0 then
                            Players.set(source, { companies = companies })
                            if callback then callback() end
                        end
                    end
                end)
            end)
        end
    end)
end

-- ── Cache helpers ──────────────────────────────────────────────────────────────

--- Adds or updates a faction membership in the Players cache.
function Org.cacheFactionMember(source, member, rank, faction)
    local data = Players.get(source)
    if not data then return end
    local factions = data.factions or {}

    -- Remove existing entry for this faction if present.
    local rootId = faction.faction_id
    for i = #factions, 1, -1 do
        if factions[i].rootId == rootId then
            table.remove(factions, i)
        end
    end

    factions[#factions + 1] = {
        memberId    = member.faction_member_id,
        factionId   = member.faction_member_faction_id,
        rootId      = rootId,
        factionName = faction.faction_name,
        factionType = faction.faction_type,
        rankId      = rank.faction_rank_id,
        rankOrder   = rank.faction_rank_order,
        rankName    = rank.faction_rank_name,
        rankPerms   = rank.faction_rank_permissions,
    }
    Players.set(source, { factions = factions })
end

--- Removes a faction from the Players cache by root faction ID.
function Org.removeCachedFaction(source, rootFactionId)
    local data = Players.get(source)
    if not data or not data.factions then return end
    local factions = data.factions
    for i = #factions, 1, -1 do
        if factions[i].rootId == rootFactionId then
            table.remove(factions, i)
        end
    end
    Players.set(source, { factions = factions })
end

--- Gets a specific faction membership from cache by root faction ID.
function Org.getFactionMembership(source, rootFactionId)
    local data = Players.get(source)
    if not data or not data.factions then return nil end
    for _, f in ipairs(data.factions) do
        if f.rootId == rootFactionId then return f end
    end
    return nil
end

--- Gets the first faction membership from cache (for /f commands when no faction specified).
function Org.getFirstFaction(source)
    local data = Players.get(source)
    if not data or not data.factions or #data.factions == 0 then return nil end
    return data.factions[1]
end

--- Adds or updates a company membership in the Players cache.
function Org.cacheCompanyMember(source, member, rank, company)
    local data = Players.get(source)
    if not data then return end
    local companies = data.companies or {}

    local rootId = company.company_id
    for i = #companies, 1, -1 do
        if companies[i].rootId == rootId then
            table.remove(companies, i)
        end
    end

    companies[#companies + 1] = {
        memberId    = member.company_member_id,
        companyId   = member.company_member_company_id,
        rootId      = rootId,
        companyName = company.company_name,
        companyType = company.company_type,
        rankId      = rank.company_rank_id,
        rankOrder   = rank.company_rank_order,
        rankName    = rank.company_rank_name,
        rankPerms   = rank.company_rank_permissions,
    }
    Players.set(source, { companies = companies })
end

--- Removes a company from the Players cache by root company ID.
function Org.removeCachedCompany(source, rootCompanyId)
    local data = Players.get(source)
    if not data or not data.companies then return end
    local companies = data.companies
    for i = #companies, 1, -1 do
        if companies[i].rootId == rootCompanyId then
            table.remove(companies, i)
        end
    end
    Players.set(source, { companies = companies })
end

--- Gets a specific company membership from cache by root company ID.
function Org.getCompanyMembership(source, rootCompanyId)
    local data = Players.get(source)
    if not data or not data.companies then return nil end
    for _, c in ipairs(data.companies) do
        if c.rootId == rootCompanyId then return c end
    end
    return nil
end

--- Gets the first company membership from cache.
function Org.getFirstCompany(source)
    local data = Players.get(source)
    if not data or not data.companies or #data.companies == 0 then return nil end
    return data.companies[1]
end

--- Finds the online player (serverID) for a given character ID.
--- Returns serverID or nil.
function Org.findOnlineByCharId(charId)
    for serverID, data in Players.all() do
        if data.charId == charId then
            return serverID
        end
    end
    return nil
end
