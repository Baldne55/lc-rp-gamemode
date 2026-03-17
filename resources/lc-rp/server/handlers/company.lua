-- server/handlers/company.lua
-- Leader and member commands for companies.
-- All commands require Guard.requireChar() + active company membership.

local _LOG_TAG = "Company"

-- ── Helper: get caller's company membership from cache ─────────────────────────

local function requireCompany(source)
    if not Guard.requireChar(source) then
        Notify.player(source, "error", "You must be logged in with a character.")
        return nil
    end
    local membership = Org.getFirstCompany(source)
    if not membership then
        Notify.player(source, "error", "You are not in any company.")
        return nil
    end
    return membership
end

local function requireCompanyPerm(source, perm)
    local membership = requireCompany(source)
    if not membership then return nil end
    if not OrgHelpers.hasPermOrLeader(membership.rankOrder, membership.rankPerms, perm) then
        Notify.player(source, "error", "You do not have permission to do that.")
        return nil
    end
    return membership
end

-- ── /cinvite ───────────────────────────────────────────────────────────────────

ServerCmd.register("cinvite", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.INVITE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /cinvite <player>")
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

    local targetCompany = Org.getCompanyMembership(targetID, membership.rootId)
    if targetCompany then
        Notify.player(source, "error", "That player is already in your company.")
        return
    end

    CompanyRankModel.findOne({ company_rank_company_id = membership.rootId, company_rank_is_default = 1 }, function(defaultRank)
        if not defaultRank then
            Notify.player(source, "error", "No default rank configured for this company.")
            return
        end

        CompanyMemberModel.create({
            company_member_company_id   = membership.rootId,
            company_member_character_id = targetData.charId,
            company_member_rank_id      = defaultRank.company_rank_id,
        }, function(memberId)
            if not memberId then
                Notify.player(source, "error", "Failed to invite member.")
                return
            end

            CompanyModel.findOne({ company_id = membership.rootId }, function(company)
                local newMember = { company_member_id = memberId, company_member_company_id = membership.rootId }
                Org.cacheCompanyMember(targetID, newMember, defaultRank, company)
                Notify.player(source, "success", string.format("Invited %s to '%s'.",
                    Player.GetName(targetID) or tostring(targetID), membership.companyName))
                Notify.player(targetID, "info", string.format("You have been invited to '%s' as '%s'.",
                    membership.companyName, defaultRank.company_rank_name))
                Log.info(_LOG_TAG, string.format("%s invited %s to company '%s'",
                    Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), membership.companyName))
            end)
        end)
    end)
end, "Invite player to company: /cinvite <player>")

-- ── /ckick ─────────────────────────────────────────────────────────────────────

ServerCmd.register("ckick", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.KICK)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /ckick <player>")
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
        Notify.player(source, "error", "You cannot kick yourself. Use /cleave instead.")
        return
    end

    local targetCompany = Org.getCompanyMembership(targetID, membership.rootId)
    if not targetCompany then
        Notify.player(source, "error", "That player is not in your company.")
        return
    end

    if membership.rankOrder >= targetCompany.rankOrder then
        Notify.player(source, "error", "You cannot kick someone of equal or higher rank.")
        return
    end

    CompanyMemberModel.delete({ company_member_id = targetCompany.memberId }, function()
        Org.removeCachedCompany(targetID, membership.rootId)
        Notify.player(source, "success", string.format("Kicked %s from '%s'.",
            Player.GetName(targetID) or tostring(targetID), membership.companyName))
        Notify.player(targetID, "warn", string.format("You have been kicked from '%s'.", membership.companyName))
        Log.info(_LOG_TAG, string.format("%s kicked %s from company '%s'",
            Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), membership.companyName))
    end)
end, "Kick member from company: /ckick <player>")

-- ── /cpromote ──────────────────────────────────────────────────────────────────

ServerCmd.register("cpromote", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.PROMOTE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /cpromote <player>")
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

    local targetCompany = Org.getCompanyMembership(targetID, membership.rootId)
    if not targetCompany then
        Notify.player(source, "error", "That player is not in your company.")
        return
    end

    CompanyRankModel.findAll({ company_rank_company_id = membership.rootId }, function(ranks)
        table.sort(ranks, function(a, b) return a.company_rank_order < b.company_rank_order end)

        local currentIdx = nil
        for i, r in ipairs(ranks) do
            if r.company_rank_id == targetCompany.rankId then
                currentIdx = i
                break
            end
        end

        if not currentIdx or currentIdx <= 1 then
            Notify.player(source, "error", "That player is already at the highest rank.")
            return
        end

        local newRank = ranks[currentIdx - 1]

        if not OrgHelpers.isLeader(membership.rankOrder) and newRank.company_rank_order <= membership.rankOrder then
            Notify.player(source, "error", "You cannot promote someone to your rank or above.")
            return
        end

        CompanyMemberModel.update(
            { company_member_rank_id = newRank.company_rank_id },
            { company_member_id = targetCompany.memberId },
            function()
                CompanyModel.findOne({ company_id = membership.rootId }, function(company)
                    local updatedMember = { company_member_id = targetCompany.memberId, company_member_company_id = targetCompany.companyId }
                    Org.cacheCompanyMember(targetID, updatedMember, newRank, company)
                    Notify.player(source, "success", string.format("Promoted %s to '%s'.",
                        Player.GetName(targetID) or tostring(targetID), newRank.company_rank_name))
                    Notify.player(targetID, "info", string.format("You have been promoted to '%s' in '%s'.",
                        newRank.company_rank_name, membership.companyName))
                end)
            end)
    end)
end, "Promote company member: /cpromote <player>")

-- ── /cdemote ───────────────────────────────────────────────────────────────────

ServerCmd.register("cdemote", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.DEMOTE)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /cdemote <player>")
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

    local targetCompany = Org.getCompanyMembership(targetID, membership.rootId)
    if not targetCompany then
        Notify.player(source, "error", "That player is not in your company.")
        return
    end

    if membership.rankOrder >= targetCompany.rankOrder then
        Notify.player(source, "error", "You cannot demote someone of equal or higher rank.")
        return
    end

    CompanyRankModel.findAll({ company_rank_company_id = membership.rootId }, function(ranks)
        table.sort(ranks, function(a, b) return a.company_rank_order < b.company_rank_order end)

        local currentIdx = nil
        for i, r in ipairs(ranks) do
            if r.company_rank_id == targetCompany.rankId then
                currentIdx = i
                break
            end
        end

        if not currentIdx or currentIdx >= #ranks then
            Notify.player(source, "error", "That player is already at the lowest rank.")
            return
        end

        local newRank = ranks[currentIdx + 1]

        CompanyMemberModel.update(
            { company_member_rank_id = newRank.company_rank_id },
            { company_member_id = targetCompany.memberId },
            function()
                CompanyModel.findOne({ company_id = membership.rootId }, function(company)
                    local updatedMember = { company_member_id = targetCompany.memberId, company_member_company_id = targetCompany.companyId }
                    Org.cacheCompanyMember(targetID, updatedMember, newRank, company)
                    Notify.player(source, "success", string.format("Demoted %s to '%s'.",
                        Player.GetName(targetID) or tostring(targetID), newRank.company_rank_name))
                    Notify.player(targetID, "warn", string.format("You have been demoted to '%s' in '%s'.",
                        newRank.company_rank_name, membership.companyName))
                end)
            end)
    end)
end, "Demote company member: /cdemote <player>")

-- ── /ccreaterank ───────────────────────────────────────────────────────────────

ServerCmd.register("ccreaterank", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 2 then
        Notify.player(source, "error", "Usage: /ccreaterank <name> <order> [salary] [permissions]")
        return
    end

    local order, salary, perms, rankName
    salary = 0
    perms = 0

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

    if not OrgHelpers.isLeader(membership.rankOrder) and order <= membership.rankOrder then
        Notify.player(source, "error", "You cannot create a rank at or above your own rank level.")
        return
    end

    CompanyRankModel.findOne({ company_rank_company_id = membership.rootId, company_rank_order = order }, function(existing)
        if existing then
            Notify.player(source, "error", string.format("A rank with order %d already exists: '%s'.", order, existing.company_rank_name))
            return
        end

        CompanyRankModel.create({
            company_rank_company_id  = membership.rootId,
            company_rank_name        = rankName,
            company_rank_order       = order,
            company_rank_salary      = salary,
            company_rank_permissions = perms,
            company_rank_is_default  = 0,
        }, function(rankId)
            if not rankId then
                Notify.player(source, "error", "Failed to create rank.")
                return
            end
            Notify.player(source, "success", string.format("Created rank '%s' (ID: %d, order: %d, salary: $%d, perms: %d).",
                rankName, rankId, order, salary, perms))
        end)
    end)
end, "Create company rank: /ccreaterank <name> <order> [salary] [perms]")

-- ── /cdeleterank ───────────────────────────────────────────────────────────────

ServerCmd.register("cdeleterank", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /cdeleterank <rankId>")
        return
    end

    local rankId = tonumber(args[1])
    if not rankId then
        Notify.player(source, "error", "Invalid rank ID.")
        return
    end

    CompanyRankModel.findOne({ company_rank_id = rankId }, function(rank)
        if not rank or rank.company_rank_company_id ~= membership.rootId then
            Notify.player(source, "error", "Rank not found in your company.")
            return
        end

        if rank.company_rank_order == 1 then
            Notify.player(source, "error", "Cannot delete the leader rank.")
            return
        end

        if rank.company_rank_is_default == 1 then
            Notify.player(source, "error", "Cannot delete the default rank. Set another rank as default first.")
            return
        end

        CompanyRankModel.findOne({ company_rank_company_id = membership.rootId, company_rank_is_default = 1 }, function(defaultRank)
            if not defaultRank then
                Notify.player(source, "error", "No default rank to reassign members to.")
                return
            end

            CompanyMemberModel.findAll({ company_member_rank_id = rankId }, function(members)
                local pending = #members
                local function afterReassign()
                    CompanyRankModel.delete({ company_rank_id = rankId }, function()
                        Notify.player(source, "success", string.format("Deleted rank '%s'. %d member(s) reassigned to '%s'.",
                            rank.company_rank_name, #members, defaultRank.company_rank_name))
                    end)
                end

                if pending == 0 then
                    afterReassign()
                    return
                end

                for _, m in ipairs(members) do
                    CompanyMemberModel.update(
                        { company_member_rank_id = defaultRank.company_rank_id },
                        { company_member_id = m.company_member_id },
                        function()
                            local onlineId = Org.findOnlineByCharId(m.company_member_character_id)
                            if onlineId then
                                CompanyModel.findOne({ company_id = membership.rootId }, function(company)
                                    if company then
                                        local updatedMember = { company_member_id = m.company_member_id, company_member_company_id = m.company_member_company_id }
                                        Org.cacheCompanyMember(onlineId, updatedMember, defaultRank, company)
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
end, "Delete company rank: /cdeleterank <rankId>")

-- ── /ceditrank ─────────────────────────────────────────────────────────────────

ServerCmd.register("ceditrank", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.MANAGE_RANKS)
    if not membership then return end

    if #args < 3 then
        Notify.player(source, "error", "Usage: /ceditrank <rankId> <field> <value>")
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

    CompanyRankModel.findOne({ company_rank_id = rankId }, function(rank)
        if not rank or rank.company_rank_company_id ~= membership.rootId then
            Notify.player(source, "error", "Rank not found in your company.")
            return
        end

        if not OrgHelpers.isLeader(membership.rankOrder) and rank.company_rank_order <= membership.rankOrder then
            Notify.player(source, "error", "You cannot edit a rank at or above your own rank level.")
            return
        end

        local updateData = {}
        if field == "name" then
            if #value < 1 or #value > 32 then
                Notify.player(source, "error", "Rank name must be between 1 and 32 characters.")
                return
            end
            updateData.company_rank_name = value
        elseif field == "order" then
            local newOrder = tonumber(value)
            if not newOrder or newOrder < 1 then
                Notify.player(source, "error", "Order must be a positive integer.")
                return
            end
            local flooredOrder = math.floor(newOrder)
            -- Check for duplicate order before updating.
            CompanyRankModel.findOne({ company_rank_company_id = membership.rootId, company_rank_order = flooredOrder }, function(existing)
                if existing and existing.company_rank_id ~= rankId then
                    Notify.player(source, "error", string.format("A rank with order %d already exists: '%s'.", flooredOrder, existing.company_rank_name))
                    return
                end
                CompanyRankModel.update({ company_rank_order = flooredOrder }, { company_rank_id = rankId }, function()
                    Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                        rank.company_rank_name, field, value))
                end)
            end)
            return
        elseif field == "salary" then
            local newSalary = tonumber(value)
            if not newSalary or newSalary < 0 then
                Notify.player(source, "error", "Salary must be a non-negative integer.")
                return
            end
            updateData.company_rank_salary = math.floor(newSalary)
        elseif field == "perms" then
            local newPerms = tonumber(value)
            local maxPerms = OrgHelpers.allPerms()
            if not newPerms or newPerms < 0 or newPerms > maxPerms then
                Notify.player(source, "error", string.format("Permissions must be a numeric bitmask between 0 and %d.", maxPerms))
                return
            end
            updateData.company_rank_permissions = math.floor(newPerms)
        elseif field == "default" then
            local isDefault = (value == "1" or value:lower() == "true" or value:lower() == "yes") and 1 or 0
            updateData.company_rank_is_default = isDefault
            if isDefault == 1 then
                -- Clear existing default before setting the new one.
                CompanyRankModel.findOne({ company_rank_company_id = membership.rootId, company_rank_is_default = 1 }, function(oldDefault)
                    if oldDefault and oldDefault.company_rank_id ~= rankId then
                        CompanyRankModel.update({ company_rank_is_default = 0 }, { company_rank_id = oldDefault.company_rank_id }, function()
                            CompanyRankModel.update(updateData, { company_rank_id = rankId }, function()
                                Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                                    rank.company_rank_name, field, value))
                            end)
                        end)
                    else
                        CompanyRankModel.update(updateData, { company_rank_id = rankId }, function()
                            Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                                rank.company_rank_name, field, value))
                        end)
                    end
                end)
                return
            end
        else
            Notify.player(source, "error", "Unknown field. Valid: name, order, salary, perms, default")
            return
        end

        CompanyRankModel.update(updateData, { company_rank_id = rankId }, function()
            Notify.player(source, "success", string.format("Updated rank '%s' field '%s' to '%s'.",
                rank.company_rank_name, field, value))
        end)
    end)
end, "Edit company rank: /ceditrank <rankId> <field> <value>")

-- ── /cranks ────────────────────────────────────────────────────────────────────

ServerCmd.register("cranks", function(source, args)
    local membership = requireCompany(source)
    if not membership then return end

    CompanyRankModel.findAll({ company_rank_company_id = membership.rootId }, function(ranks)
        if #ranks == 0 then
            Notify.player(source, "info", "No ranks found.")
            return
        end

        table.sort(ranks, function(a, b) return a.company_rank_order < b.company_rank_order end)

        Notify.player(source, "info", "--- " .. membership.companyName .. " Ranks ---")
        for _, r in ipairs(ranks) do
            Notify.player(source, "info", string.format("[%d] %s (order: %d, salary: $%d%s)",
                r.company_rank_id, r.company_rank_name, r.company_rank_order,
                r.company_rank_salary,
                r.company_rank_is_default == 1 and ", DEFAULT" or ""))
        end
    end)
end, "List company ranks: /cranks")

-- ── /cmembers ──────────────────────────────────────────────────────────────────

ServerCmd.register("cmembers", function(source, args)
    local membership = requireCompany(source)
    if not membership then return end

    CompanyMemberModel.findAll({ company_member_company_id = membership.rootId }, function(rootMembers)
        CompanyModel.findAll({ company_parent_id = membership.rootId }, function(subs)
            local allMembers = {}
            for _, m in ipairs(rootMembers) do allMembers[#allMembers + 1] = m end

            local subsPending = #subs
            local function showMembers()
                if #allMembers == 0 then
                    Notify.player(source, "info", "No members found.")
                    return
                end

                CompanyRankModel.findAll({ company_rank_company_id = membership.rootId }, function(ranks)
                    local rankMap = {}
                    for _, r in ipairs(ranks) do rankMap[r.company_rank_id] = r.company_rank_name end

                    Notify.player(source, "info", "--- " .. membership.companyName .. " Members (" .. #allMembers .. ") ---")
                    for _, m in ipairs(allMembers) do
                        local rankName = rankMap[m.company_member_rank_id] or "Unknown"
                        local onlineId = Org.findOnlineByCharId(m.company_member_character_id)
                        local status = onlineId and " [ONLINE]" or ""
                        local name = onlineId and (Player.GetName(onlineId) or tostring(onlineId)) or ("CharID:" .. m.company_member_character_id)
                        Notify.player(source, "info", string.format("  %s - %s%s", name, rankName, status))
                    end
                end)
            end

            if subsPending == 0 then
                showMembers()
                return
            end

            for _, sub in ipairs(subs) do
                CompanyMemberModel.findAll({ company_member_company_id = sub.company_id }, function(subMembers)
                    for _, m in ipairs(subMembers) do allMembers[#allMembers + 1] = m end
                    CompanyModel.findAll({ company_parent_id = sub.company_id }, function(depts)
                        local deptsPending = #depts
                        if deptsPending == 0 then
                            subsPending = subsPending - 1
                            if subsPending == 0 then showMembers() end
                            return
                        end
                        for _, dept in ipairs(depts) do
                            CompanyMemberModel.findAll({ company_member_company_id = dept.company_id }, function(deptMembers)
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
end, "List company members: /cmembers")

-- ── /cinfo ─────────────────────────────────────────────────────────────────────

ServerCmd.register("cinfo", function(source, args)
    local membership = requireCompany(source)
    if not membership then return end

    CompanyModel.findOne({ company_id = membership.rootId }, function(company)
        if not company then
            Notify.player(source, "error", "Company data not found.")
            return
        end

        Notify.player(source, "info", "--- " .. company.company_name .. " ---")
        Notify.player(source, "info", string.format("Type: %s | Your rank: %s", company.company_type, membership.rankName))
        if company.company_short_name then
            Notify.player(source, "info", "Short name: " .. company.company_short_name)
        end
        if company.company_motd and #company.company_motd > 0 then
            Notify.player(source, "info", "MOTD: " .. company.company_motd)
        end
    end)
end, "View company info: /cinfo")

-- ── /csetmotd ──────────────────────────────────────────────────────────────────

ServerCmd.register("csetmotd", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.SET_MOTD)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /csetmotd <text>")
        return
    end

    local motd = table.concat(args, " ")
    if #motd > 256 then
        Notify.player(source, "error", "MOTD must be 256 characters or less.")
        return
    end

    CompanyModel.update({ company_motd = motd }, { company_id = membership.rootId }, function()
        Notify.player(source, "success", "Company MOTD updated.")
    end)
end, "Set company MOTD: /csetmotd <text>")

-- ── /cleave ────────────────────────────────────────────────────────────────────

ServerCmd.register("cleave", function(source, args)
    local membership = requireCompany(source)
    if not membership then return end

    if OrgHelpers.isLeader(membership.rankOrder) then
        Notify.player(source, "error", "Leaders cannot leave. Transfer leadership first or ask an admin to remove you.")
        return
    end

    CompanyMemberModel.delete({ company_member_id = membership.memberId }, function()
        Org.removeCachedCompany(source, membership.rootId)
        Notify.player(source, "success", string.format("You have left '%s'.", membership.companyName))
        Log.info(_LOG_TAG, string.format("%s left company '%s'",
            Player.GetName(source) or tostring(source), membership.companyName))
    end)
end, "Leave your company: /cleave")

-- ── /c (company chat) ──────────────────────────────────────────────────────────

ServerCmd.register("c", function(source, args)
    local membership = requireCompany(source)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /c <message>")
        return
    end

    local message = table.concat(args, " ")
    local senderName = Player.GetName(source) or "Unknown"

    for serverID, pData in Players.all() do
        if pData.charId and pData.companies then
            for _, co in ipairs(pData.companies) do
                if co.rootId == membership.rootId then
                    Notify.player(serverID, "info", string.format("[%s] %s (%s): %s",
                        membership.companyName, senderName, membership.rankName, message))
                    break
                end
            end
        end
    end
end, "Company chat: /c <message>")

-- ── /cokick (offline kick by character ID) ───────────────────────────────────

ServerCmd.register("cokick", function(source, args)
    local membership = requireCompanyPerm(source, OrgPerms.KICK)
    if not membership then return end

    if #args < 1 then
        Notify.player(source, "error", "Usage: /cokick <characterId>")
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
        Notify.player(source, "error", "You cannot kick yourself. Use /cleave instead.")
        return
    end

    -- Helper: perform the kick once a member record is found.
    local function doKick(member)
        CompanyRankModel.findOne({ company_rank_id = member.company_member_rank_id }, function(targetRank)
            if targetRank and membership.rankOrder >= targetRank.company_rank_order then
                Notify.player(source, "error", "You cannot kick someone of equal or higher rank.")
                return
            end
            CompanyMemberModel.delete({ company_member_id = member.company_member_id }, function()
                local onlineId = Org.findOnlineByCharId(charId)
                if onlineId then
                    Org.removeCachedCompany(onlineId, membership.rootId)
                    Notify.player(onlineId, "warn", string.format("You have been kicked from '%s'.", membership.companyName))
                end
                Notify.player(source, "success", string.format("Kicked character ID %d from '%s'.", charId, membership.companyName))
                Log.info(_LOG_TAG, string.format("%s offline-kicked charId %d from company '%s'",
                    Player.GetName(source) or tostring(source), charId, membership.companyName))
            end)
        end)
    end

    -- Collect all company IDs (root + subs + departments) then search each.
    local unitIds = { membership.rootId }
    CompanyModel.findAll({ company_parent_id = membership.rootId }, function(subs)
        for _, sub in ipairs(subs) do
            unitIds[#unitIds + 1] = sub.company_id
        end

        local subsPending = #subs
        local function searchUnits()
            local found = false
            local pending = #unitIds
            for _, unitId in ipairs(unitIds) do
                CompanyMemberModel.findOne({ company_member_character_id = charId, company_member_company_id = unitId }, function(member)
                    if member and not found then
                        found = true
                        doKick(member)
                    end
                    pending = pending - 1
                    if pending == 0 and not found then
                        Notify.player(source, "error", "No member with that character ID found in your company.")
                    end
                end)
            end
        end

        if subsPending == 0 then
            searchUnits()
            return
        end

        -- Also collect department IDs under each sub-company.
        for _, sub in ipairs(subs) do
            CompanyModel.findAll({ company_parent_id = sub.company_id }, function(depts)
                for _, dept in ipairs(depts) do
                    unitIds[#unitIds + 1] = dept.company_id
                end
                subsPending = subsPending - 1
                if subsPending == 0 then
                    searchUnits()
                end
            end)
        end
    end)
end, "Kick member by character ID: /cokick <characterId>")
