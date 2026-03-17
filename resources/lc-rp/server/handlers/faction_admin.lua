-- server/handlers/faction_admin.lua
-- Staff-only admin commands for faction management.
-- All commands gated behind Guard.requireStaff().

local _LOG_TAG = "FactionAdmin"

-- ── /acreatefaction ────────────────────────────────────────────────────────────

ServerCmd.register("acreatefaction", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acreatefaction <name> <type>")
        Notify.player(source, "info", "Types: illegal, government, police, ems, fire, news, legal, other")
        return
    end

    local fType = args[#args]:lower()
    if not OrgFactionTypes[fType] then
        Notify.player(source, "error", "Invalid faction type. Valid: illegal, government, police, ems, fire, news, legal, other")
        return
    end

    -- Name is everything except the last arg (type).
    local nameParts = {}
    for i = 1, #args - 1 do nameParts[#nameParts + 1] = args[i] end
    local fName = table.concat(nameParts, " ")

    if #fName < 2 or #fName > 64 then
        Notify.player(source, "error", "Faction name must be between 2 and 64 characters.")
        return
    end

    -- Check for duplicate name.
    FactionModel.findOne({ faction_name = fName }, function(existing)
        if existing then
            Notify.player(source, "error", "A faction with that name already exists.")
            return
        end

        local adminData = Players.get(source)
        FactionModel.create({
            faction_name       = fName,
            faction_type       = fType,
            faction_is_active  = 1,
            faction_created_by = adminData and adminData.accountId or nil,
        }, function(factionId)
            if not factionId then
                Notify.player(source, "error", "Failed to create faction.")
                return
            end

            -- Create "Leader" rank (order 1, all perms).
            FactionRankModel.create({
                faction_rank_faction_id  = factionId,
                faction_rank_name        = "Leader",
                faction_rank_order       = 1,
                faction_rank_permissions = OrgHelpers.allPerms(),
                faction_rank_is_default  = 0,
            }, function(leaderRankId)
                -- Create "Member" rank (order 10, default, no perms).
                FactionRankModel.create({
                    faction_rank_faction_id  = factionId,
                    faction_rank_name        = "Member",
                    faction_rank_order       = 10,
                    faction_rank_permissions = 0,
                    faction_rank_is_default  = 1,
                }, function(memberRankId)
                    -- Auto-create bank account.
                    OrgHelpers.generateRoutingNumber(function(routingNum)
                        if not routingNum then
                            Notify.player(source, "warn", string.format(
                                "Faction '%s' (ID: %d) created [type: %s], but bank account creation failed (routing number generation failed).",
                                fName, factionId, fType))
                            return
                        end
                        BankAccountModel.create({
                            bank_account_owner_type     = "faction",
                            bank_account_owner_id       = factionId,
                            bank_account_type           = "checking",
                            bank_account_balance        = 0,
                            bank_account_routing_number = routingNum,
                            bank_account_is_frozen      = 0,
                        }, function(bankId)
                            Notify.player(source, "success", string.format(
                                "Faction '%s' (ID: %d) created [type: %s]. Bank account #%s created.",
                                fName, factionId, fType, routingNum))
                            Log.info(_LOG_TAG, string.format("Admin %s created faction '%s' (ID: %d, type: %s)",
                                Player.GetName(source) or tostring(source), fName, factionId, fType))
                        end)
                    end)
                end)
            end)
        end)
    end)
end, "Create a faction: /acreatefaction <name> <type>")

-- ── /adeletefaction ────────────────────────────────────────────────────────────

ServerCmd.register("adeletefaction", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /adeletefaction <factionId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction then
            Notify.player(source, "error", "Faction not found.")
            return
        end
        if faction.faction_is_active == 0 then
            Notify.player(source, "error", "Faction is already inactive.")
            return
        end

        -- Soft-delete: set inactive.
        FactionModel.update({ faction_is_active = 0 }, { faction_id = factionId }, function()
            -- Remove all members.
            FactionMemberModel.findAll({ faction_member_faction_id = factionId }, function(members)
                for _, m in ipairs(members) do
                    -- Update online players' cache.
                    local onlineId = Org.findOnlineByCharId(m.faction_member_character_id)
                    if onlineId then
                        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
                            local rootId = root and root.faction_id or factionId
                            Org.removeCachedFaction(onlineId, rootId)
                        end)
                        Notify.player(onlineId, "warn", string.format("Faction '%s' has been disbanded by an administrator.", faction.faction_name))
                    end
                end
                FactionMemberModel.delete({ faction_member_faction_id = factionId }, function()
                    -- Also deactivate sub-factions.
                    FactionModel.findAll({ faction_parent_id = factionId }, function(subs)
                        for _, sub in ipairs(subs) do
                            FactionModel.update({ faction_is_active = 0 }, { faction_id = sub.faction_id }, function() end)
                            -- Clear cache for sub-faction members before deleting.
                            FactionMemberModel.findAll({ faction_member_faction_id = sub.faction_id }, function(subMembers)
                                for _, sm in ipairs(subMembers) do
                                    local onlineId = Org.findOnlineByCharId(sm.faction_member_character_id)
                                    if onlineId then
                                        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", sub.faction_id, function(root)
                                            Org.removeCachedFaction(onlineId, root and root.faction_id or factionId)
                                        end)
                                        Notify.player(onlineId, "warn", string.format("Faction '%s' has been disbanded by an administrator.", faction.faction_name))
                                    end
                                end
                                FactionMemberModel.delete({ faction_member_faction_id = sub.faction_id }, function() end)
                            end)
                            -- Also deactivate departments under sub-factions.
                            FactionModel.findAll({ faction_parent_id = sub.faction_id }, function(depts)
                                for _, dept in ipairs(depts) do
                                    FactionModel.update({ faction_is_active = 0 }, { faction_id = dept.faction_id }, function() end)
                                    -- Clear cache for department members before deleting.
                                    FactionMemberModel.findAll({ faction_member_faction_id = dept.faction_id }, function(deptMembers)
                                        for _, dm in ipairs(deptMembers) do
                                            local onlineId = Org.findOnlineByCharId(dm.faction_member_character_id)
                                            if onlineId then
                                                OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", dept.faction_id, function(root)
                                                    Org.removeCachedFaction(onlineId, root and root.faction_id or factionId)
                                                end)
                                                Notify.player(onlineId, "warn", string.format("Faction '%s' has been disbanded by an administrator.", faction.faction_name))
                                            end
                                        end
                                        FactionMemberModel.delete({ faction_member_faction_id = dept.faction_id }, function() end)
                                    end)
                                end
                            end)
                        end
                    end)
                    Notify.player(source, "success", string.format("Faction '%s' (ID: %d) has been deactivated and all members removed.", faction.faction_name, factionId))
                    Log.info(_LOG_TAG, string.format("Admin %s deactivated faction '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), faction.faction_name, factionId))
                end)
            end)
        end)
    end)
end, "Deactivate a faction: /adeletefaction <factionId>")

-- ── /acreatesubfaction ─────────────────────────────────────────────────────────

ServerCmd.register("acreatesubfaction", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /acreatesubfaction <parentId> <name>")
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

    FactionModel.findOne({ faction_id = parentId }, function(parent)
        if not parent then
            Notify.player(source, "error", "Parent faction not found.")
            return
        end
        if parent.faction_is_active == 0 then
            Notify.player(source, "error", "Parent faction is inactive.")
            return
        end

        -- Check depth: max 3 levels.
        OrgHelpers.getDepth(FactionModel, "faction_id", "faction_parent_id", parentId, function(depth)
            if not depth or depth >= 3 then
                Notify.player(source, "error", "Maximum hierarchy depth (3 levels) reached. Cannot create sub-faction here.")
                return
            end

            FactionModel.findOne({ faction_name = subName }, function(existing)
                if existing then
                    Notify.player(source, "error", "A faction with that name already exists.")
                    return
                end

                FactionModel.create({
                    faction_parent_id  = parentId,
                    faction_name       = subName,
                    faction_type       = parent.faction_type, -- inherit type from parent
                    faction_is_active  = 1,
                    faction_created_by = (Players.get(source) or {}).accountId,
                }, function(subId)
                    if not subId then
                        Notify.player(source, "error", "Failed to create sub-faction.")
                        return
                    end
                    local levelName = depth == 1 and "Sub-faction" or "Department"
                    Notify.player(source, "success", string.format(
                        "%s '%s' (ID: %d) created under '%s' (ID: %d).",
                        levelName, subName, subId, parent.faction_name, parentId))
                    Log.info(_LOG_TAG, string.format("Admin %s created sub-faction '%s' (ID: %d) under '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), subName, subId, parent.faction_name, parentId))
                end)
            end)
        end)
    end)
end, "Create sub-faction/department: /acreatesubfaction <parentId> <name>")

-- ── /asetfactionleader ─────────────────────────────────────────────────────────

ServerCmd.register("asetfactionleader", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /asetfactionleader <factionId> <charNameOrId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction or faction.faction_is_active == 0 then
            Notify.player(source, "error", "Faction not found or inactive.")
            return
        end

        -- Resolve root faction for rank lookup.
        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
            local rootFaction = root or faction
            local rootId = rootFaction.faction_id

            -- Find the leader rank (order 1).
            FactionRankModel.findOne({ faction_rank_faction_id = rootId, faction_rank_order = 1 }, function(leaderRank)
                if not leaderRank then
                    Notify.player(source, "error", "No leader rank found for this faction. Create one first.")
                    return
                end

                -- Resolve target player.
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

                -- Check if already a member of this faction (any level).
                FactionMemberModel.findOne({ faction_member_character_id = targetData.charId, faction_member_faction_id = factionId }, function(existingMember)
                    if existingMember then
                        -- Update their rank to leader.
                        FactionMemberModel.update(
                            { faction_member_rank_id = leaderRank.faction_rank_id },
                            { faction_member_id = existingMember.faction_member_id },
                            function()
                                Org.cacheFactionMember(targetID, existingMember, leaderRank, rootFaction)
                                Notify.player(source, "success", string.format("Set %s as leader of '%s'.",
                                    Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name))
                                Notify.player(targetID, "info", string.format("You have been set as leader of '%s' by an administrator.", rootFaction.faction_name))
                                Log.info(_LOG_TAG, string.format("Admin %s set %s as leader of faction '%s' (ID: %d)",
                                    Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name, rootId))
                            end)
                    else
                        -- Create membership at leader rank.
                        FactionMemberModel.create({
                            faction_member_faction_id   = factionId,
                            faction_member_character_id = targetData.charId,
                            faction_member_rank_id      = leaderRank.faction_rank_id,
                        }, function(memberId)
                            if not memberId then
                                Notify.player(source, "error", "Failed to add member.")
                                return
                            end
                            local newMember = { faction_member_id = memberId, faction_member_faction_id = factionId }
                            Org.cacheFactionMember(targetID, newMember, leaderRank, rootFaction)
                            Notify.player(source, "success", string.format("Added %s as leader of '%s'.",
                                Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name))
                            Notify.player(targetID, "info", string.format("You have been added as leader of '%s' by an administrator.", rootFaction.faction_name))
                            Log.info(_LOG_TAG, string.format("Admin %s added %s as leader of faction '%s' (ID: %d)",
                                Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name, rootId))
                        end)
                    end
                end)
            end)
        end)
    end)
end, "Set faction leader: /asetfactionleader <factionId> <charNameOrId>")

-- ── /aremovefactionleader ──────────────────────────────────────────────────────

ServerCmd.register("aremovefactionleader", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /aremovefactionleader <factionId> <charNameOrId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction or faction.faction_is_active == 0 then
            Notify.player(source, "error", "Faction not found or inactive.")
            return
        end

        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
            local rootFaction = root or faction
            local rootId = rootFaction.faction_id

            -- Find default rank.
            FactionRankModel.findOne({ faction_rank_faction_id = rootId, faction_rank_is_default = 1 }, function(defaultRank)
                if not defaultRank then
                    Notify.player(source, "error", "No default rank found for this faction.")
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

                FactionMemberModel.findOne({ faction_member_character_id = targetData.charId, faction_member_faction_id = factionId }, function(member)
                    if not member then
                        Notify.player(source, "error", "Target is not a member of this faction.")
                        return
                    end

                    FactionMemberModel.update(
                        { faction_member_rank_id = defaultRank.faction_rank_id },
                        { faction_member_id = member.faction_member_id },
                        function()
                            Org.cacheFactionMember(targetID, member, defaultRank, rootFaction)
                            Notify.player(source, "success", string.format("Demoted %s to '%s' in '%s'.",
                                Player.GetName(targetID) or tostring(targetID), defaultRank.faction_rank_name, rootFaction.faction_name))
                            Notify.player(targetID, "warn", string.format("You have been demoted to '%s' in '%s' by an administrator.",
                                defaultRank.faction_rank_name, rootFaction.faction_name))
                        end)
                end)
            end)
        end)
    end)
end, "Remove faction leader: /aremovefactionleader <factionId> <charNameOrId>")

-- ── /afactionaddmember ─────────────────────────────────────────────────────────

ServerCmd.register("afactionaddmember", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /afactionaddmember <factionId> <charNameOrId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction or faction.faction_is_active == 0 then
            Notify.player(source, "error", "Faction not found or inactive.")
            return
        end

        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
            local rootFaction = root or faction
            local rootId = rootFaction.faction_id

            FactionRankModel.findOne({ faction_rank_faction_id = rootId, faction_rank_is_default = 1 }, function(defaultRank)
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

                -- Check if already a member.
                FactionMemberModel.findOne({ faction_member_character_id = targetData.charId, faction_member_faction_id = factionId }, function(existing)
                    if existing then
                        Notify.player(source, "error", "Target is already a member of this faction.")
                        return
                    end

                    FactionMemberModel.create({
                        faction_member_faction_id   = factionId,
                        faction_member_character_id = targetData.charId,
                        faction_member_rank_id      = defaultRank.faction_rank_id,
                    }, function(memberId)
                        if not memberId then
                            Notify.player(source, "error", "Failed to add member.")
                            return
                        end
                        local newMember = { faction_member_id = memberId, faction_member_faction_id = factionId }
                        Org.cacheFactionMember(targetID, newMember, defaultRank, rootFaction)
                        Notify.player(source, "success", string.format("Added %s to '%s' as '%s'.",
                            Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name, defaultRank.faction_rank_name))
                        Notify.player(targetID, "info", string.format("You have been added to '%s' by an administrator.", rootFaction.faction_name))
                        Log.info(_LOG_TAG, string.format("Admin %s added %s to faction '%s' (ID: %d)",
                            Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name, rootId))
                    end)
                end)
            end)
        end)
    end)
end, "Add member to faction: /afactionaddmember <factionId> <charNameOrId>")

-- ── /afactionremovemember ──────────────────────────────────────────────────────

ServerCmd.register("afactionremovemember", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 2 then
        Notify.player(source, "error", "Usage: /afactionremovemember <factionId> <charNameOrId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    local targetInput = table.concat(args, " ", 2)

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction then
            Notify.player(source, "error", "Faction not found.")
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

        FactionMemberModel.findOne({ faction_member_character_id = targetData.charId, faction_member_faction_id = factionId }, function(member)
            if not member then
                Notify.player(source, "error", "Target is not a member of this faction.")
                return
            end

            FactionMemberModel.delete({ faction_member_id = member.faction_member_id }, function()
                OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
                    local rootFaction = root or faction
                    Org.removeCachedFaction(targetID, rootFaction.faction_id)
                    Notify.player(source, "success", string.format("Removed %s from '%s'.",
                        Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name))
                    Notify.player(targetID, "warn", string.format("You have been removed from '%s' by an administrator.", rootFaction.faction_name))
                    Log.info(_LOG_TAG, string.format("Admin %s removed %s from faction '%s' (ID: %d)",
                        Player.GetName(source) or tostring(source), Player.GetName(targetID) or tostring(targetID), rootFaction.faction_name, rootFaction.faction_id))
                end)
            end)
        end)
    end)
end, "Remove member from faction: /afactionremovemember <factionId> <charNameOrId>")

-- ── /afactioninfo ──────────────────────────────────────────────────────────────

ServerCmd.register("afactioninfo", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #args < 1 then
        Notify.player(source, "error", "Usage: /afactioninfo <factionId>")
        return
    end

    local factionId = tonumber(args[1])
    if not factionId then
        Notify.player(source, "error", "Invalid faction ID.")
        return
    end

    FactionModel.findOne({ faction_id = factionId }, function(faction)
        if not faction then
            Notify.player(source, "error", "Faction not found.")
            return
        end

        Notify.player(source, "info", "--- Faction Info ---")
        Notify.player(source, "info", string.format("ID: %d | Name: %s | Type: %s | Active: %s",
            faction.faction_id, faction.faction_name, faction.faction_type,
            faction.faction_is_active == 1 and "Yes" or "No"))
        if faction.faction_short_name then
            Notify.player(source, "info", "Short name: " .. faction.faction_short_name)
        end
        if faction.faction_motd then
            Notify.player(source, "info", "MOTD: " .. faction.faction_motd)
        end
        if faction.faction_parent_id then
            Notify.player(source, "info", "Parent ID: " .. tostring(faction.faction_parent_id))
        end

        -- Resolve root for rank/member counts.
        OrgHelpers.getRoot(FactionModel, "faction_id", "faction_parent_id", factionId, function(root)
            local rootId = root and root.faction_id or factionId

            FactionRankModel.findAll({ faction_rank_faction_id = rootId }, function(ranks)
                Notify.player(source, "info", "Ranks (" .. #ranks .. "):")
                for _, r in ipairs(ranks) do
                    Notify.player(source, "info", string.format("  [%d] %s (order: %d, salary: $%d, perms: %d%s)",
                        r.faction_rank_id, r.faction_rank_name, r.faction_rank_order,
                        r.faction_rank_salary, r.faction_rank_permissions,
                        r.faction_rank_is_default == 1 and ", DEFAULT" or ""))
                end

                FactionMemberModel.findAll({ faction_member_faction_id = factionId }, function(members)
                    Notify.player(source, "info", "Members in this unit: " .. #members)
                end)
            end)
        end)
    end)
end, "View faction info: /afactioninfo <factionId>")

-- ── /afactions ─────────────────────────────────────────────────────────────────

ServerCmd.register("afactions", function(source, args)
    if not Guard.requireStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end

    FactionModel.findAll({ faction_is_active = 1 }, function(factions)
        if #factions == 0 then
            Notify.player(source, "info", "No active factions.")
            return
        end

        Notify.player(source, "info", "--- Active Factions ---")
        for _, f in ipairs(factions) do
            local parentInfo = f.faction_parent_id and string.format(" (parent: %d)", f.faction_parent_id) or ""
            Notify.player(source, "info", string.format("[%d] %s - %s%s",
                f.faction_id, f.faction_name, f.faction_type, parentInfo))
        end
    end)
end, "List all active factions: /afactions")
