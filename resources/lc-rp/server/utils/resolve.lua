-- server/utils/resolve.lua
-- Shared player/item resolution helpers used by inventory handlers.

Resolve = {}

-- Resolves a player by numeric ID or partial/full character name.
-- Returns targetID on success, or nil + reason ("not_found" | "ambiguous").
function Resolve.player(input)
    local id = tonumber(input)
    if id then
        local d = Players.get(id)
        if d and d.charId and Player.IsConnected(id) then
            return id
        end
        return nil, "not_found"
    end
    local lower = input:lower()
    local matches = {}
    for serverID, _ in Players.all() do
        local d = Players.get(serverID)
        if d and d.charId and Player.IsConnected(serverID) then
            local name = (Player.GetName(serverID) or ""):lower()
            if name:find(lower, 1, true) then
                matches[#matches + 1] = serverID
            end
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches > 1  then return nil, "ambiguous" end
    return nil, "not_found"
end

-- Resolves an item definition by numeric ID or partial/full name.
-- Returns defId on success, or nil + reason ("not_found" | "ambiguous").
function Resolve.itemDef(input)
    local id = tonumber(input)
    if id then
        if ItemRegistry.get(id) then return id end
        return nil, "not_found"
    end
    local results = ItemRegistry.searchByName(input)
    if #results == 1 then return results[1] end
    if #results > 1  then return nil, "ambiguous" end
    return nil, "not_found"
end
