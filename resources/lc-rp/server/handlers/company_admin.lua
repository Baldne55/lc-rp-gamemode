-- server/handlers/company_admin.lua
-- Staff-only admin commands for company management.
-- All commands gated behind Guard.requireStaff().

local _LOG_TAG = "CompanyAdmin"

-- ── /acreatecompany ────────────────────────────────────────────────────────────

ServerCmd.register("acreatecompany", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acreatecompany <name> <type>")
        Notify.player(source, "info", "Types: llc, sole_proprietorship, partnership, corporation, nonprofit")
        return
    end

    local cType = args[#args]:lower()
    if not OrgCompanyTypes[cType] then
        Notify.player(source, "error", "Invalid company type. Valid: llc, sole_proprietorship, partnership, corporation, nonprofit")
        return
    end

    local nameParts = {}
    for i = 1, #args - 1 do nameParts[#nameParts + 1] = args[i] end
    local cName = table.concat(nameParts, " ")

    if #cName < 2 or #cName > 64 then
        Notify.player(source, "error", "Company name must be between 2 and 64 characters.")
        return
    end

    CompanyModel.findOne({ company_name = cName }, function(existing)
        if existing then
            Notify.player(source, "error", "A company with that name already exists.")
            return
        end

        local adminData = Players.get(source)
        CompanyModel.create({
            company_name       = cName,
            company_type       = cType,
            company_is_active  = 1,
            company_created_by = adminData and adminData.accountId or nil,
        }, function(companyId)
            if not companyId then
                Notify.player(source, "error", "Failed to create company.")
                return
            end

            CompanyRankModel.create({
                company_rank_company_id  = companyId,
                company_rank_name        = "Owner",
                company_rank_order       = 1,
                company_rank_permissions = OrgHelpers.allPerms(),
                company_rank_is_default  = 0,
            }, function(ownerRankId)
                CompanyRankModel.create({
                    company_rank_company_id  = companyId,
                    company_rank_name        = "Employee",
                    company_rank_order       = 10,
                    company_rank_permissions = 0,
                    company_rank_is_default  = 1,
                }, function(employeeRankId)
                    OrgHelpers.generateRoutingNumber(function(routingNum)
                        if not routingNum then
                            Notify.player(source, "warn", string.format(
                                "Company '%s' (ID: %d) created [type: %s], but bank account creation failed (routing number generation failed).",
                                cName, companyId, cType))
                            return
                        end
                        BankAccountModel.create({
                            bank_account_owner_type     = "company",
                            bank_account_owner_id       = companyId,
                            bank_account_type           = "checking",
                            bank_account_balance        = 0,
                            bank_account_routing_number = routingNum,
                            bank_account_is_frozen      = 0,
                        }, function(bankId)
                            Notify.player(source, "success", string.format(
                                "Company '%s' (ID: %d) created [type: %s]. Bank account #%s created.",
                                cName, companyId, cType, routingNum))
                            Log.info(_LOG_TAG, string.format("Admin %s created company '%s' (ID: %d, type: %s)",
                                Player.GetName(source) or tostring(source), cName, companyId, cType))
                        end)
                    end)
                end)
            end)
        end)
    end)
end, "Create a company: /acreatecompany <name> <type>")

-- ── /adeletecompany ────────────────────────────────────────────────────────────

ServerCmd.register("adeletecompany", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /adeletecompany <companyId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company then
            Notify.player(source, "error", "Company not found.")
            return
        end
        if company.company_is_active == 0 then
            Notify.player(source, "error", "Company is already inactive.")
            return
        end

        CompanyModel.update({ company_is_active = 0 }, { company_id = companyId }, function()
            CompanyMemberModel.findAll({ company_member_company_id = companyId }, function(members)
                for _, m in ipairs(members) do
                    local onlineId = Org.findOnlineByCharId(m.company_member_character_id)
                    if onlineId then
                        Org.removeCachedCompany(onlineId, companyId)
                        Notify.player(onlineId, "warn", string.format("Company '%s' has been disbanded by an administrator.", company.company_name))
                    end
                end
                CompanyMemberModel.delete({ company_member_company_id = companyId }, function()
                    -- Deactivate sub-companies and departments.
                    CompanyModel.findAll({ company_parent_id = companyId }, function(subs)
                        for _, sub in ipairs(subs) do
                            CompanyModel.update({ company_is_active = 0 }, { company_id = sub.company_id }, function() end)
                            -- Clear cache for sub-company members before deleting.
                            CompanyMemberModel.findAll({ company_member_company_id = sub.company_id }, function(subMembers)
                                for _, sm in ipairs(subMembers) do
                                    local onlineId = Org.findOnlineByCharId(sm.company_member_character_id)
                                    if onlineId then
                                        Org.removeCachedCompany(onlineId, companyId)
                                        Notify.player(onlineId, "warn", string.format("Company '%s' has been disbanded by an administrator.", company.company_name))
                                    end
                                end
                                CompanyMemberModel.delete({ company_member_company_id = sub.company_id }, function() end)
                            end)
                            CompanyModel.findAll({ company_parent_id = sub.company_id }, function(depts)
                                for _, dept in ipairs(depts) do
                                    CompanyModel.update({ company_is_active = 0 }, { company_id = dept.company_id }, function() end)
                                    -- Clear cache for department members before deleting.
                                    CompanyMemberModel.findAll({ company_member_company_id = dept.company_id }, function(deptMembers)
                                        for _, dm in ipairs(deptMembers) do
                                            local onlineId = Org.findOnlineByCharId(dm.company_member_character_id)
                                            if onlineId then
                                                Org.removeCachedCompany(onlineId, companyId)
                                                Notify.player(onlineId, "warn", string.format("Company '%s' has been disbanded by an administrator.", company.company_name))
                                            end
                                        end
                                        CompanyMemberModel.delete({ company_member_company_id = dept.company_id }, function() end)
                                    end)
                                end
                            end)
                        end
                    end)
                    Notify.player(source, "success", string.format("Company '%s' (ID: %d) has been deactivated and all members removed.", company.company_name, companyId))
                    Log.info(_LOG_TAG, string.format("Admin %s deactivated company '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), company.company_name, companyId))
                end)
            end)
        end)
    end)
end, "Deactivate a company: /adeletecompany <companyId>")

-- ── /acreatesubcompany ─────────────────────────────────────────────────────────

ServerCmd.register("acreatesubcompany", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acreatesubcompany <parentId> <name>")
        return
    end

    local parentId = tonumber(args[1])
    if not parentId then
        Notify.player(source, "error", "Invalid parent ID.")
        return
    end

    local nameParts = {}
    for i = 2, #args do nameParts[#nameParts + 1] = args[i] end
    local subName = table.concat(nameParts, " ")

    if #subName < 2 or #subName > 64 then
        Notify.player(source, "error", "Name must be between 2 and 64 characters.")
        return
    end

    CompanyModel.findOne({ company_id = parentId }, function(parent)
        if not parent then
            Notify.player(source, "error", "Parent company not found.")
            return
        end
        if parent.company_is_active == 0 then
            Notify.player(source, "error", "Parent company is inactive.")
            return
        end

        OrgHelpers.getDepth(CompanyModel, "company_id", "company_parent_id", parentId, function(depth)
            if not depth or depth >= 3 then
                Notify.player(source, "error", "Maximum hierarchy depth (3 levels) reached.")
                return
            end

            CompanyModel.findOne({ company_name = subName }, function(existing)
                if existing then
                    Notify.player(source, "error", "A company with that name already exists.")
                    return
                end

                CompanyModel.create({
                    company_parent_id  = parentId,
                    company_name       = subName,
                    company_type       = parent.company_type,
                    company_is_active  = 1,
                    company_created_by = (Players.get(source) or {}).accountId,
                }, function(subId)
                    if not subId then
                        Notify.player(source, "error", "Failed to create sub-company.")
                        return
                    end
                    local levelName = depth == 1 and "Sub-company" or "Department"
                    Notify.player(source, "success", string.format(
                        "%s '%s' (ID: %d) created under '%s' (ID: %d).",
                        levelName, subName, subId, parent.company_name, parentId))
                    Log.info(_LOG_TAG, string.format("Admin %s created sub-company '%s' (ID: %d) under '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), subName, subId, parent.company_name, parentId))
                end)
            end)
        end)
    end)
end, "Create sub-company/department: /acreatesubcompany <parentId> <name>")

-- ── /asetcompanyleader ─────────────────────────────────────────────────────────

ServerCmd.register("asetcompanyleader", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /asetcompanyleader <companyId> <charNameOrId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company or company.company_is_active == 0 then
            Notify.player(source, "error", "Company not found or inactive.")
            return
        end

        OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", companyId, function(root)
            local rootCompany = root or company
            local rootId = rootCompany.company_id

            CompanyRankModel.findOne({ company_rank_company_id = rootId, company_rank_order = 1 }, function(leaderRank)
                if not leaderRank then
                    Notify.player(source, "error", "No leader rank found for this company.")
                    return
                end

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

                CompanyMemberModel.findOne({ company_member_character_id = targetData.charId, company_member_company_id = companyId }, function(existingMember)
                    if existingMember then
                        CompanyMemberModel.update(
                            { company_member_rank_id = leaderRank.company_rank_id },
                            { company_member_id = existingMember.company_member_id },
                            function()
                                Org.cacheCompanyMember(targetID, existingMember, leaderRank, rootCompany)
                                Notify.player(source, "success", string.format("Set %s as leader of '%s'.",
                                    Player.GetName(targetID) or tostring(targetID), rootCompany.company_name))
                                Notify.player(targetID, "info", string.format("You have been set as leader of '%s' by an administrator.", rootCompany.company_name))
                            end)
                    else
                        CompanyMemberModel.create({
                            company_member_company_id   = companyId,
                            company_member_character_id = targetData.charId,
                            company_member_rank_id      = leaderRank.company_rank_id,
                        }, function(memberId)
                            if not memberId then
                                Notify.player(source, "error", "Failed to add member.")
                                return
                            end
                            local newMember = { company_member_id = memberId, company_member_company_id = companyId }
                            Org.cacheCompanyMember(targetID, newMember, leaderRank, rootCompany)
                            Notify.player(source, "success", string.format("Added %s as leader of '%s'.",
                                Player.GetName(targetID) or tostring(targetID), rootCompany.company_name))
                            Notify.player(targetID, "info", string.format("You have been added as leader of '%s' by an administrator.", rootCompany.company_name))
                        end)
                    end
                end)
            end)
        end)
    end)
end, "Set company leader: /asetcompanyleader <companyId> <charNameOrId>")

-- ── /aremovecompanyleader ──────────────────────────────────────────────────────

ServerCmd.register("aremovecompanyleader", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /aremovecompanyleader <companyId> <charNameOrId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company or company.company_is_active == 0 then
            Notify.player(source, "error", "Company not found or inactive.")
            return
        end

        OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", companyId, function(root)
            local rootCompany = root or company
            local rootId = rootCompany.company_id

            CompanyRankModel.findOne({ company_rank_company_id = rootId, company_rank_is_default = 1 }, function(defaultRank)
                if not defaultRank then
                    Notify.player(source, "error", "No default rank found for this company.")
                    return
                end

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

                CompanyMemberModel.findOne({ company_member_character_id = targetData.charId, company_member_company_id = companyId }, function(member)
                    if not member then
                        Notify.player(source, "error", "Target is not a member of this company.")
                        return
                    end

                    CompanyMemberModel.update(
                        { company_member_rank_id = defaultRank.company_rank_id },
                        { company_member_id = member.company_member_id },
                        function()
                            Org.cacheCompanyMember(targetID, member, defaultRank, rootCompany)
                            Notify.player(source, "success", string.format("Demoted %s to '%s' in '%s'.",
                                Player.GetName(targetID) or tostring(targetID), defaultRank.company_rank_name, rootCompany.company_name))
                            Notify.player(targetID, "warn", string.format("You have been demoted to '%s' in '%s' by an administrator.",
                                defaultRank.company_rank_name, rootCompany.company_name))
                        end)
                end)
            end)
        end)
    end)
end, "Remove company leader: /aremovecompanyleader <companyId> <charNameOrId>")

-- ── /acompanyaddmember ─────────────────────────────────────────────────────────

ServerCmd.register("acompanyaddmember", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acompanyaddmember <companyId> <charNameOrId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company or company.company_is_active == 0 then
            Notify.player(source, "error", "Company not found or inactive.")
            return
        end

        OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", companyId, function(root)
            local rootCompany = root or company
            local rootId = rootCompany.company_id

            CompanyRankModel.findOne({ company_rank_company_id = rootId, company_rank_is_default = 1 }, function(defaultRank)
                if not defaultRank then
                    Notify.player(source, "error", "No default rank found. Create ranks first.")
                    return
                end

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

                CompanyMemberModel.findOne({ company_member_character_id = targetData.charId, company_member_company_id = companyId }, function(existing)
                    if existing then
                        Notify.player(source, "error", "Target is already a member of this company.")
                        return
                    end

                    CompanyMemberModel.create({
                        company_member_company_id   = companyId,
                        company_member_character_id = targetData.charId,
                        company_member_rank_id      = defaultRank.company_rank_id,
                    }, function(memberId)
                        if not memberId then
                            Notify.player(source, "error", "Failed to add member.")
                            return
                        end
                        local newMember = { company_member_id = memberId, company_member_company_id = companyId }
                        Org.cacheCompanyMember(targetID, newMember, defaultRank, rootCompany)
                        Notify.player(source, "success", string.format("Added %s to '%s' as '%s'.",
                            Player.GetName(targetID) or tostring(targetID), rootCompany.company_name, defaultRank.company_rank_name))
                        Notify.player(targetID, "info", string.format("You have been added to '%s' by an administrator.", rootCompany.company_name))
                        Log.info(_LOG_TAG, string.format("Admin %s added %s to company '%s' (ID: %d)",
                            Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootCompany.company_name, rootId))
                    end)
                end)
            end)
        end)
    end)
end, "Add member to company: /acompanyaddmember <companyId> <charNameOrId>")

-- ── /acompanyremovemember ──────────────────────────────────────────────────────

ServerCmd.register("acompanyremovemember", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acompanyremovemember <companyId> <charNameOrId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company then
            Notify.player(source, "error", "Company not found.")
            return
        end

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

        CompanyMemberModel.findOne({ company_member_character_id = targetData.charId, company_member_company_id = companyId }, function(member)
            if not member then
                Notify.player(source, "error", "Target is not a member of this company.")
                return
            end

            CompanyMemberModel.delete({ company_member_id = member.company_member_id }, function()
                OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", companyId, function(root)
                    local rootCompany = root or company
                    Org.removeCachedCompany(targetID, rootCompany.company_id)
                    Notify.player(source, "success", string.format("Removed %s from '%s'.",
                        Player.GetName(targetID) or tostring(targetID), rootCompany.company_name))
                    Notify.player(targetID, "warn", string.format("You have been removed from '%s' by an administrator.", rootCompany.company_name))
                    Log.info(_LOG_TAG, string.format("Admin %s removed %s from company '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootCompany.company_name, rootCompany.company_id))
                end)
            end)
        end)
    end)
end, "Remove member from company: /acompanyremovemember <companyId> <charNameOrId>")

-- ── /acompanyinfo ──────────────────────────────────────────────────────────────

ServerCmd.register("acompanyinfo", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /acompanyinfo <companyId>")
        return
    end

    local companyId = tonumber(args[1])
    if not companyId then
        Notify.player(source, "error", "Invalid company ID.")
        return
    end

    CompanyModel.findOne({ company_id = companyId }, function(company)
        if not company then
            Notify.player(source, "error", "Company not found.")
            return
        end

        Notify.player(source, "info", "--- Company Info ---")
        Notify.player(source, "info", string.format("ID: %d | Name: %s | Type: %s | Active: %s",
            company.company_id, company.company_name, company.company_type,
            company.company_is_active == 1 and "Yes" or "No"))
        if company.company_short_name then
            Notify.player(source, "info", "Short name: " .. company.company_short_name)
        end
        if company.company_motd then
            Notify.player(source, "info", "MOTD: " .. company.company_motd)
        end
        if company.company_parent_id then
            Notify.player(source, "info", "Parent ID: " .. tostring(company.company_parent_id))
        end

        OrgHelpers.getRoot(CompanyModel, "company_id", "company_parent_id", companyId, function(root)
            local rootId = root and root.company_id or companyId

            CompanyRankModel.findAll({ company_rank_company_id = rootId }, function(ranks)
                Notify.player(source, "info", "Ranks (" .. #ranks .. "):")
                for _, r in ipairs(ranks) do
                    Notify.player(source, "info", string.format("  [%d] %s (order: %d, salary: $%d, perms: %d%s)",
                        r.company_rank_id, r.company_rank_name, r.company_rank_order,
                        r.company_rank_salary, r.company_rank_permissions,
                        r.company_rank_is_default == 1 and ", DEFAULT" or ""))
                end

                CompanyMemberModel.findAll({ company_member_company_id = companyId }, function(members)
                    Notify.player(source, "info", "Members in this unit: " .. #members)
                end)
            end)
        end)
    end)
end, "View company info: /acompanyinfo <companyId>")

-- ── /acompanies ────────────────────────────────────────────────────────────────

ServerCmd.register("acompanies", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end

    CompanyModel.findAll({ company_is_active = 1 }, function(companies)
        if #companies == 0 then
            Notify.player(source, "info", "No active companies.")
            return
        end

        Notify.player(source, "info", "--- Active Companies ---")
        for _, c in ipairs(companies) do
            local parentInfo = c.company_parent_id and string.format(" (parent: %d)", c.company_parent_id) or ""
            Notify.player(source, "info", string.format("[%d] %s - %s%s",
                c.company_id, c.company_name, c.company_type, parentInfo))
        end
    end)
end, "List all active companies: /acompanies")
