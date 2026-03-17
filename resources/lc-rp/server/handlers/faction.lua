-- server/handlers/faction.lua
-- Leader and member commands for factions.
-- All commands require Guard.requireChar() + active faction membership.

local _LOG_TAG = "Faction"

-- ── Helper: get caller's faction membership from cache ─────────────────────────

--- Returns the caller's first faction membership from cache, or nil + sends error.
local function requireFaction(source)
    if not Guard.requireChar(source) then
        Notify.player(source, "error", "You must be logged in with a character.")
        return nil
    end
    local membership = Org.getFirstFaction(source)
    if not membership then
        Notify.player(source, "error", "You are not in any faction.")
        return nil
    end
    return membership
end

--- Returns the caller's faction membership + checks a specific permission.
local function requireFactionPerm(source, perm)
    local membership = requireFaction(source)
    if not membership then return nil end
    if not OrgHelpers.hasPermOrLeader(membership.rankOrder, membership.rankPerms, perm) then
        Notify.player(source, "error", "You do not have permission to do that.")
        return nil
    end
    return membership
end

-- ── /finvite ───────────────────────────────────────────────────────────────────

ServerCmd.register("finvite", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.INVITE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /finvite <player>")
        return
    end

    local targetInput = table.concat(args, " ")
    local targetID, resolveErr = Resolve.player(targetInput)
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match. Use their ID.")
        else
            Notify.player(source, "error", "Player not found: " .. targetInput)
        end
        return
    end

    local targetData = Players.get(targetID)
    if not targetData or not targetData.charId then
        Notify.player(source, "error", "Target has no active character.")
        return
    end

    -- Check if already in this faction.
    local targetFaction = Org.getFactionMembership(targetID, membership.rootId)
    if targetFaction then
        Notify.player(source, "error", "That player is already in your faction.")
        return
    end

    -- Find default rank.
    FactionRankModel.findOne({ faction_rank_faction_id = membership.rootId, faction_rank_is_default = 1 }, function(defaultRank)
        if not defaultRank then
            Notify.player(source, "error", "No default rank configured for this faction.")
            return
        end

        FactionMemberModel.create({
            faction_member_faction_id   = membership.rootId,
            faction_member_character_id = targetData.charId,
            faction_member_rank_id      = defaultRank.faction_rank_id,
        }, function(memberId)
            if not memberId then
                Notify.player(source, "error", "Failed to invite member.")
                return
            end

            FactionModel.findOne({ faction_id = membership.rootId }, function(faction)
                local newMember = { faction_member_id = memberId, faction_member_faction_id = membership.rootId }
                Org.cacheFactionMember(targetID, newMember, defaultRank, faction)
                Notify.player(source, "success", string.format("Invited %s to '%s'.",
                    Player.GetName(targetID) or tostring(targetID), membership.factionName))
                Notify.player(targetID, "info", string.format("You have been invited to '%s' as '%s'.",
                    membership.factionName, defaultRank.faction_rank_name))
                Log.info(_LOG_TAG, string.format("%s invited %s to faction '%s'",
                    Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), membership.factionName))
            end)
        end)
    end)
end, "Invite player to faction: /finvite <player>")

-- ── /fkick ─────────────────────────────────────────────────────────────────────

ServerCmd.register("fkick", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.KICK)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fkick <player>")
        return
    end

    local targetInput = table.concat(args, " ")
    local targetID, resolveErr = Resolve.player(targetInput)
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match. Use their ID.")
        else
            Notify.player(source, "error", "Player not found: " .. targetInput)
        end
        return
    end

    if targetID == source then
        Notify.player(source, "error", "You cannot kick yourself. Use /fleave instead.")
        return
    end

    local targetFaction = Org.getFactionMembership(targetID, membership.rootId)
    if not targetFaction then
        Notify.player(source, "error", "That player is not in your faction.")
        return
    end

    -- Must outrank the target.
    if membership.rankOrder >= targetFaction.rankOrder then
        Notify.player(source, "error", "You cannot kick someone of equal or higher rank.")
        return
    end

    FactionMemberModel.delete({ faction_member_id = targetFaction.memberId }, function()
        Org.removeCachedFaction(targetID, membership.rootId)
        Notify.player(source, "success", string.format("Kicked %s from '%s'.",
            Player.GetName(targetID) or tostring(targetID), membership.factionName))
        Notify.player(targetID, "warn", string.format("You have been kicked from '%s'.", membership.factionName))
        Log.info(_LOG_TAG, string.format("%s kicked %s from faction '%s'",
            Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), membership.factionName))
    end)
end, "Kick member from faction: /fkick <player>")

-- ── /fpromote ──────────────────────────────────────────────────────────────────

ServerCmd.register("fpromote", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.PROMOTE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fpromote <player>")
        return
    end

    local targetInput = table.concat(args, " ")
    local targetID, resolveErr = Resolve.player(targetInput)
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match. Use their ID.")
        else
            Notify.player(source, "error", "Player not found: " .. targetInput)
        end
        return
    end

    local targetFaction = Org.getFactionMembership(targetID, membership.rootId)
    if not targetFaction then
        Notify.player(source, "error", "That player is not in your faction.")
        return
    end

    -- Find all ranks sorted by order to find the next rank up.
    FactionRankModel.findAll({ faction_rank_faction_id = membership.rootId }, function(ranks)
        -- Sort by order ascending.
        table.sort(ranks, function(a, b) return a.faction_rank_order < b.faction_rank_order end)

        -- Find current rank index and the rank above it.
        local currentIdx = nil
        for i, r in ipairs(ranks) do
            if r.faction_rank_id == targetFaction.rankId then
                currentIdx = i
                break
            end
        end

        if not currentIdx or currentIdx <= 1 then
            Notify.player(source, "error", "That player is already at the highest rank.")
            return
        end

        local newRank = ranks[currentIdx - 1]

        -- Cannot promote above own rank (unless leader).
        if not OrgHelpers.isLeader(membership.rankOrder) and newRank.faction_rank_order <= membership.rankOrder then
            Notify.player(source, "error", "You cannot promote someone to your rank or above.")
            return
        end

        FactionMemberModel.update(
            { faction_member_rank_id = newRank.faction_rank_id },
            { faction_member_id = targetFaction.memberId },
            function()
                FactionModel.findOne({ faction_id = membership.rootId }, function(faction)
                    local updatedMember = { faction_member_id = targetFaction.memberId, faction_member_faction_id = targetFaction.factionId }
                    Org.cacheFactionMember(targetID, updatedMember, newRank, faction)
                    Notify.player(source, "success", string.format("Promoted %s to '%s'.",
                        Player.GetName(targetID) or tostring(targetID), newRank.faction_rank_name))
                    Notify.player(targetID, "info", string.format("You have been promoted to '%s' in '%s'.",
                        newRank.faction_rank_name, membership.factionName))
                end)
            end)
    end)
end, "Promote faction member: /fpromote <player>")

-- ── /fdemote ───────────────────────────────────────────────────────────────────

ServerCmd.register("fdemote", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.DEMOTE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fdemote <player>")
        return
    end

    local targetInput = table.concat(args, " ")
    local targetID, resolveErr = Resolve.player(targetInput)
    if not targetID then
        if resolveErr == "ambiguous" then
            Notify.player(source, "error", "Multiple players match. Use their ID.")
        else
            Notify.player(source, "error", "Player not found: " .. targetInput)
        end
        return
    end

    local targetFaction = Org.getFactionMembership(targetID, membership.rootId)
    if not targetFaction then
        Notify.player(source, "error", "That player is not in your faction.")
        return
    end

    -- Must outrank the target.
    if membership.rankOrder >= targetFaction.rankOrder then
        Notify.player(source, "error", "You cannot demote someone of equal or higher rank.")
        return
    end

    FactionRankModel.findAll({ faction_rank_faction_id = membership.rootId }, function(ranks)
        table.sort(ranks, function(a, b) return a.faction_rank_order < b.faction_rank_order end)

        local currentIdx = nil
        for i, r in ipairs(ranks) do
            if r.faction_rank_id == targetFaction.rankId then
                currentIdx = i
                break
            end
        end

        if not currentIdx or currentIdx >= #ranks then
            Notify.player(source, "error", "That player is already at the lowest rank.")
            return
        end

        local newRank = ranks[currentIdx + 1]

        FactionMemberModel.update(
            { faction_member_rank_id = newRank.faction_rank_id },
            { faction_member_id = targetFaction.memberId },
            function()
                FactionModel.findOne({ faction_id = membership.rootId }, function(faction)
                    local updatedMember = { faction_member_id = targetFaction.memberId, faction_member_faction_id = targetFaction.factionId }
                    Org.cacheFactionMember(targetID, updatedMember, newRank, faction)
                    Notify.player(source, "success", string.format("Demoted %s to '%s'.",
                        Player.GetName(targetID) or tostring(targetID), newRank.faction_rank_name))
                    Notify.player(targetID, "warn", string.format("You have been demoted to '%s' in '%s'.",
                        newRank.faction_rank_name, membership.factionName))
                end)
            end)
    end)
end, "Demote faction member: /fdemote <player>")

-- ── /fcreaterank ───────────────────────────────────────────────────────────────

ServerCmd.register("fcreaterank", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 2 then
        Notify.player(source, "error", "Usage: /fcreaterank <name> <order> [salary] [permissions]")
        return
    end

    local order, salary, perms, rankName
    salary = 0
    perms = 0

    -- Parse: /fcreaterank <name> <order> [salary] [perms]
    -- Name can be multi-word, so we parse from the end.
    if #args >= 4 then
        perms = math.floor(tonumber(args[#args]) or 0)
        salary = math.floor(tonumber(args[#args - 1]) or 0)
        order = math.floor(tonumber(args[#args - 2]) or 0)
        local nameParts = {}
        for i = 1, #args - 3 do nameParts[#nameParts + 1] = args[i] end
        rankName = table.concat(nameParts, " ")
    elseif #args == 3 then
        salary = math.floor(tonumber(args[3]) or 0)
        order = math.floor(tonumber(args[2]) or 0)
        rankName = args[1]
    else
        order = math.floor(tonumber(args[2]) or 0)
        rankName = args[1]
    end

    if not rankName or #rankName < 1 or #rankName > 32 then
        Notify.player(source, "error", "Rank name must be between 1 and 32 characters.")
        return
    end
    if not order or order < 1 then
        Notify.player(source, "error", "Order must be a positive integer (1 = highest).")
        return
    end

    -- Validate permissions bitmask.
    local maxPerms = OrgHelpers.allPerms()
    if perms < 0 or perms > maxPerms then
        Notify.player(source, "error", string.format("Permissions must be between 0 and %d.", maxPerms))
        return
    end

    -- Non-leaders cannot create ranks at or above their own order.
    if not OrgHelpers.isLeader(membership.rankOrder) and order <= membership.rankOrder then
        Notify.player(source, "error", "You cannot create a rank at or above your own rank level.")
        return
    end

    -- Check for duplicate order.
    FactionRankModel.findOne({ faction_rank_faction_id = membership.rootId, faction_rank_order = order }, function(existing)
        if existing then
            Notify.player(source, "error", string.format("A rank with order %d already exists: '%s'.", order, existing.faction_rank_name))
            return
        end

        FactionRankModel.create({
            faction_rank_faction_id  = membership.rootId,
            faction_rank_name        = rankName,
            faction_rank_order       = order,
            faction_rank_salary      = salary,
            faction_rank_permissions = perms,
            faction_rank_is_default  = 0,
        }, function(rankId)
            if not rankId then
                Notify.player(source, "error", "Failed to create rank.")
                return
            end
            Notify.player(source, "success", string.format("Created rank '%s' (ID: %d, order: %d, salary: $%d, perms: %d).",
                rankName, rankId, order, salary, perms))
        end)
    end)
end, "Create faction rank: /fcreaterank <name> <order> [salary] [perms]")

-- ── /fdeleterank ───────────────────────────────────────────────────────────────

ServerCmd.register("fdeleterank", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fdeleterank <rankId>")
        return
    end

    local rankId = tonumber(args[1])
    if not rankId then
        Notify.player(source, "error", "Invalid rank ID.")
        return
    end

    FactionRankModel.findOne({ faction_rank_id = rankId }, function(rank)
        if not rank or rank.faction_rank_faction_id ~= membership.rootId then
            Notify.player(source, "error", "Rank not found in your faction.")
            return
        end

        if rank.faction_rank_order == 1 then
            Notify.player(source, "error", "Cannot delete the leader rank.")
            return
        end

        if rank.faction_rank_is_default == 1 then
            Notify.player(source, "error", "Cannot delete the default rank. Set another rank as default first.")
            return
        end

        -- Find default rank to reassign members.
        FactionRankModel.findOne({ faction_rank_faction_id = membership.rootId, faction_rank_is_default = 1 }, function(defaultRank)
            if not defaultRank then
                Notify.player(source, "error", "No default rank to reassign members to.")
                return
            end

            -- Reassign members who have this rank.
            FactionMemberModel.findAll({ faction_member_rank_id = rankId }, function(members)
                local pending = #members
                local function afterReassign()
                    FactionRankModel.delete({ faction_rank_id = rankId }, function()
                        Notify.player(source, "success", string.format("Deleted rank '%s'. %d member(s) reassigned to '%s'.",
                            rank.faction_rank_name, #members, defaultRank.faction_rank_name))
                    end)
                end

                if pending == 0 then
                    afterReassign()
                    return
                end

                for _, m in ipairs(members) do
                    FactionMemberModel.update(
                        { faction_member_rank_id = defaultRank.faction_rank_id },
                        { faction_member_id = m.faction_member_id },
                        function()
                            -- Update cache for online players.
                            local onlineId = Org.findOnlineByCharId(m.faction_member_character_id)
                            if onlineId then
                                FactionModel.findOne({ faction_id = membership.rootId }, function(faction)
                                    if faction then
                                        local updatedMember = { faction_member_id = m.faction_member_id, faction_member_faction_id = m.faction_member_faction_id }
                                        Org.cacheFactionMember(onlineId, updatedMember, defaultRank, faction)
                                    end
                                end)
                            end
                            pending = pending - 1
                            if pending == 0 then afterReassign() end
                        end)
                end
            end)
        end)
    end)
end, "Delete faction rank: /fdeleterank <rankId>")

-- ── /feditrank ─────────────────────────────────────────────────────────────────

ServerCmd.register("feditrank", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 3 then
        Notify.player(source, "error", "Usage: /feditrank <rankId> <field> <value>")
        Notify.player(source, "info", "Fields: name, order, salary, perms, default")
        return
    end

    local rankId = tonumber(args[1])
    local field = args[2]:lower()
    local value = table.concat(args, " ", 3)

    if not rankId then
        Notify.player(source, "error", "Invalid rank ID.")
        return
    end

    FactionRankModel.findOne({ faction_rank_id = rankId }, function(rank)
        if not rank or rank.faction_rank_faction_id ~= membership.rootId then
            Notify.player(source, "error", "Rank not found in your faction.")
            return
        end

        -- Non-leaders cannot edit ranks at or above their own order.
        if not OrgHelpers.isLeader(membership.rankOrder) and rank.faction_rank_order <= membership.rankOrder then
            Notify.player(source, "error", "You cannot edit a rank at or above your own rank level.")
            return
        end

        local updateData = {}
        if field == "name" then
            if #value < 1 or #value > 32 then
                Notify.player(source, "error", "Rank name must be between 1 and 32 characters.")
                return
            end
            updateData.faction_rank_name = value
        elseif field == "order" then
            local newOrder = tonumber(value)
            if not newOrder or newOrder < 1 then
                Notify.player(source, "error", "Order must be a positive integer.")
                return
            end
            local flooredOrder = math.floor(newOrder)
            -- Check for duplicate order before updating.
            FactionRankModel.findOne({ faction_rank_faction_id = membership.rootId, faction_rank_order = flooredOrder }, function(existing)
                if existing and existing.faction_rank_id ~= rankId then
                    Notify.player(source, "error", string.format("A rank with order %d already exists: '%s'.", flooredOrder, existing.faction_rank_name))
                    return
                end
                FactionRankModel.update({ faction_rank_order = flooredOrder }, { faction_rank_id = rankId }, function()
                    Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                        rank.faction_rank_name, field, value))
                end)
            end)
            return
        elseif field == "salary" then
            local newSalary = tonumber(value)
            if not newSalary or newSalary < 0 then
                Notify.player(source, "error", "Salary must be a non-negative integer.")
                return
            end
            updateData.faction_rank_salary = math.floor(newSalary)
        elseif field == "perms" then
            local newPerms = tonumber(value)
            local maxPerms = OrgHelpers.allPerms()
            if not newPerms or newPerms < 0 or newPerms > maxPerms then
                Notify.player(source, "error", string.format("Permissions must be a numeric bitmask between 0 and %d.", maxPerms))
                return
            end
            updateData.faction_rank_permissions = math.floor(newPerms)
        elseif field == "default" then
            local isDefault = (value == "1" or value:lower() == "true" or value:lower() == "yes") and 1 or 0
            updateData.faction_rank_is_default = isDefault
            if isDefault == 1 then
                -- Clear existing default before setting the new one.
                FactionRankModel.findOne({ faction_rank_faction_id = membership.rootId, faction_rank_is_default = 1 }, function(oldDefault)
                    if oldDefault and oldDefault.faction_rank_id ~= rankId then
                        FactionRankModel.update({ faction_rank_is_default = 0 }, { faction_rank_id = oldDefault.faction_rank_id }, function()
                            FactionRankModel.update(updateData, { faction_rank_id = rankId }, function()
                                Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                                    rank.faction_rank_name, field, value))
                            end)
                        end)
                    else
                        FactionRankModel.update(updateData, { faction_rank_id = rankId }, function()
                            Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                                rank.faction_rank_name, field, value))
                        end)
                    end
                end)
                return
            end
        else
            Notify.player(source, "error", "Unknown field. Valid: name, order, salary, perms, default")
            return
        end

        FactionRankModel.update(updateData, { faction_rank_id = rankId }, function()
            Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                rank.faction_rank_name, field, value))
        end)
    end)
end, "Edit faction rank: /feditrank <rankId> <field> <value>")

-- ── /franks ────────────────────────────────────────────────────────────────────

ServerCmd.register("franks", function(source, args)
    local membership = requireFaction(source)
    if not membership then return end

    FactionRankModel.findAll({ faction_rank_faction_id = membership.rootId }, function(ranks)
        if #ranks == 0 then
            Notify.player(source, "info", "No ranks found.")
            return
        end

        table.sort(ranks, function(a, b) return a.faction_rank_order < b.faction_rank_order end)

        Notify.player(source, "info", "--- " .. membership.factionName .. " Ranks ---")
        for _, r in ipairs(ranks) do
            Notify.player(source, "info", string.format("[%d] %s (order: %d, salary: $%d%s)",
                r.faction_rank_id, r.faction_rank_name, r.faction_rank_order,
                r.faction_rank_salary,
                r.faction_rank_is_default == 1 and ", DEFAULT" or ""))
        end
    end)
end, "List faction ranks: /franks")

-- ── /fmembers ──────────────────────────────────────────────────────────────────

ServerCmd.register("fmembers", function(source, args)
    local membership = requireFaction(source)
    if not membership then return end

    -- Find all members across the root faction and its sub-factions.
    FactionMemberModel.findAll({ faction_member_faction_id = membership.rootId }, function(rootMembers)
        -- Also check sub-factions.
        FactionModel.findAll({ faction_parent_id = membership.rootId }, function(subs)
            local allMembers = {}
            for _, m in ipairs(rootMembers) do allMembers[#allMembers + 1] = m end

            local subsPending = #subs
            local function showMembers()
                if #allMembers == 0 then
                    Notify.player(source, "info", "No members found.")
                    return
                end

                -- Fetch all ranks for name lookup.
                FactionRankModel.findAll({ faction_rank_faction_id = membership.rootId }, function(ranks)
                    local rankMap = {}
                    for _, r in ipairs(ranks) do rankMap[r.faction_rank_id] = r.faction_rank_name end

                    Notify.player(source, "info", "--- " .. membership.factionName .. " Members (" .. #allMembers .. ") ---")
                    for _, m in ipairs(allMembers) do
                        local rankName = rankMap[m.faction_member_rank_id] or "Unknown"
                        local onlineId = Org.findOnlineByCharId(m.faction_member_character_id)
                        local status = onlineId and " [ONLINE]" or ""
                        local name = onlineId and (Player.GetName(onlineId) or tostring(onlineId)) or ("CharID:" .. m.faction_member_character_id)
                        Notify.player(source, "info", string.format("  %s - %s%s", name, rankName, status))
                    end
                end)
            end

            if subsPending == 0 then
                showMembers()
                return
            end

            for _, sub in ipairs(subs) do
                FactionMemberModel.findAll({ faction_member_faction_id = sub.faction_id }, function(subMembers)
                    for _, m in ipairs(subMembers) do allMembers[#allMembers + 1] = m end
                    -- Also check departments.
                    FactionModel.findAll({ faction_parent_id = sub.faction_id }, function(depts)
                        local deptsPending = #depts
                        if deptsPending == 0 then
                            subsPending = subsPending - 1
                            if subsPending == 0 then showMembers() end
                            return
                        end
                        for _, dept in ipairs(depts) do
                            FactionMemberModel.findAll({ faction_member_faction_id = dept.faction_id }, function(deptMembers)
                                for _, m in ipairs(deptMembers) do allMembers[#allMembers + 1] = m end
                                deptsPending = deptsPending - 1
                                if deptsPending == 0 then
                                    subsPending = subsPending - 1
                                    if subsPending == 0 then showMembers() end
                                end
                            end)
                        end
                    end)
                end)
            end
        end)
    end)
end, "List faction members: /fmembers")

-- ── /finfo ─────────────────────────────────────────────────────────────────────

ServerCmd.register("finfo", function(source, args)
    local membership = requireFaction(source)
    if not membership then return end

    FactionModel.findOne({ faction_id = membership.rootId }, function(faction)
        if not faction then
            Notify.player(source, "error", "Faction data not found.")
            return
        end

        Notify.player(source, "info", "--- " .. faction.faction_name .. " ---")
        Notify.player(source, "info", string.format("Type: %s | Your rank: %s", faction.faction_type, membership.rankName))
        if faction.faction_short_name then
            Notify.player(source, "info", "Short name: " .. faction.faction_short_name)
        end
        if faction.faction_motd and #faction.faction_motd > 0 then
            Notify.player(source, "info", "MOTD: " .. faction.faction_motd)
        end
    end)
end, "View faction info: /finfo")

-- ── /fsetmotd ──────────────────────────────────────────────────────────────────

ServerCmd.register("fsetmotd", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.SET_MOTD)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fsetmotd <text>")
        return
    end

    local motd = table.concat(args, " ")
    if #motd > 256 then
        Notify.player(source, "error", "MOTD must be 256 characters or less.")
        return
    end

    FactionModel.update({ faction_motd = motd }, { faction_id = membership.rootId }, function()
        Notify.player(source, "success", "Faction MOTD updated.")
    end)
end, "Set faction MOTD: /fsetmotd <text>")

-- ── /fleave ────────────────────────────────────────────────────────────────────

ServerCmd.register("fleave", function(source, args)
    local membership = requireFaction(source)
    if not membership then return end

    if OrgHelpers.isLeader(membership.rankOrder) then
        Notify.player(source, "error", "Leaders cannot leave. Transfer leadership first or ask an admin to remove you.")
        return
    end

    FactionMemberModel.delete({ faction_member_id = membership.memberId }, function()
        Org.removeCachedFaction(source, membership.rootId)
        Notify.player(source, "success", string.format("You have left '%s'.", membership.factionName))
        Log.info(_LOG_TAG, string.format("%s left faction '%s'",
            Player.GetName(source) or tostring(source), membership.factionName))
    end)
end, "Leave your faction: /fleave")

-- ── /fduty ─────────────────────────────────────────────────────────────────────

ServerCmd.register("fduty", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.DUTY)
    if not membership then return end

    if not OrgDutyFactionTypes[membership.factionType] then
        Notify.player(source, "error", "Your faction type does not support the duty system.")
        return
    end

    local data = Players.get(source)
    local currentDuty = data and data.dutyFactionId
    if currentDuty == membership.rootId then
        -- Going off duty.
        Players.set(source, { dutyFactionId = nil })
        Notify.player(source, "info", string.format("You are now OFF duty in '%s'.", membership.factionName))
    else
        -- Going on duty.
        Players.set(source, { dutyFactionId = membership.rootId })
        Notify.player(source, "success", string.format("You are now ON duty in '%s'.", membership.factionName))
    end
end, "Toggle faction duty status: /fduty")

-- ── /f (faction chat) ──────────────────────────────────────────────────────────

ServerCmd.register("f", function(source, args)
    local membership = requireFaction(source)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /f <message>")
        return
    end

    local message = table.concat(args, " ")
    local senderName = Player.GetName(source) or "Unknown"

    -- Send to all online members of this faction (root + sub-factions + departments).
    for serverID, pData in Players.all() do
        if pData.charId and pData.factions then
            for _, f in ipairs(pData.factions) do
                if f.rootId == membership.rootId then
                    Notify.player(serverID, "info", string.format("[%s] %s (%s): %s",
                        membership.factionName, senderName, membership.rankName, message))
                    break
                end
            end
        end
    end
end, "Faction chat: /f <message>")

-- ── /fokick (offline kick by character ID) ───────────────────────────────────

ServerCmd.register("fokick", function(source, args)
    local membership = requireFactionPerm(source, OrgPerms.KICK)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /fokick <characterId>")
        return
    end

    local charId = tonumber(args[1])
    if not charId then
        Notify.player(source, "error", "Invalid character ID.")
        return
    end

    -- Prevent self-kick.
    local callerData = Players.get(source)
    if callerData and callerData.charId == charId then
        Notify.player(source, "error", "You cannot kick yourself. Use /fleave instead.")
        return
    end

    -- Helper: perform the kick once a member record is found.
    local function doKick(member)
        FactionRankModel.findOne({ faction_rank_id = member.faction_member_rank_id }, function(targetRank)
            if targetRank and membership.rankOrder >= targetRank.faction_rank_order then
                Notify.player(source, "error", "You cannot kick someone of equal or higher rank.")
                return
            end
            FactionMemberModel.delete({ faction_member_id = member.faction_member_id }, function()
                local onlineId = Org.findOnlineByCharId(charId)
                if onlineId then
                    Org.removeCachedFaction(onlineId, membership.rootId)
                    Notify.player(onlineId, "warn", string.format("You have been kicked from '%s'.", membership.factionName))
                end
                Notify.player(source, "success", string.format("Kicked character ID %d from '%s'.", charId, membership.factionName))
                Log.info(_LOG_TAG, string.format("%s offline-kicked charId %d from faction '%s'",
                    Player.GetName(source) or tostring(source), charId, membership.factionName))
            end)
        end)
    end

    -- Collect all faction IDs (root + subs + departments) then search each.
    local unitIds = { membership.rootId }
    FactionModel.findAll({ faction_parent_id = membership.rootId }, function(subs)
        for _, sub in ipairs(subs) do
            unitIds[#unitIds + 1] = sub.faction_id
        end

        local subsPending = #subs
        local function searchUnits()
            local found = false
            local pending = #unitIds
            for _, unitId in ipairs(unitIds) do
                FactionMemberModel.findOne({ faction_member_character_id = charId, faction_member_faction_id = unitId }, function(member)
                    if member and not found then
                        found = true
                        doKick(member)
                    end
                    pending = pending - 1
                    if pending == 0 and not found then
                        Notify.player(source, "error", "No member with that character ID found in your faction.")
                    end
                end)
            end
        end

        if subsPending == 0 then
            searchUnits()
            return
        end

        -- Also collect department IDs under each sub-faction.
        for _, sub in ipairs(subs) do
            FactionModel.findAll({ faction_parent_id = sub.faction_id }, function(depts)
                for _, dept in ipairs(depts) do
                    unitIds[#unitIds + 1] = dept.faction_id
                end
                subsPending = subsPending - 1
                if subsPending == 0 then
                    searchUnits()
                end
            end)
        end
    end)
end, "Kick member by character ID: /fokick <characterId>")
