-- players.lua
-- Server-side in-memory session cache.
-- Tracks every player that has successfully authenticated this session.
--
-- Access from any server script:
--   Players.get(serverID)        → data table or nil
--   Players.set(serverID, data)  → stores/merges data for serverID
--   Players.remove(serverID)     → clears entry
--   Players.all()                → iterator over all connected players

Players = {}

local _cache = {}  -- { [serverID] = { accountId, username, ... } }

-- Returns the cached data for a connected player, or nil.
function Players.get(serverID)
    return _cache[serverID]
end

-- Stores or merges data into the cache entry for serverID.
function Players.set(serverID, data)
    if not _cache[serverID] then
        _cache[serverID] = {}
    end
    for k, v in pairs(data) do
        _cache[serverID][k] = v
    end
end

-- Removes a player from the cache. Called on disconnect.
function Players.remove(serverID)
    _cache[serverID] = nil
end

-- Iterates over all cached players: for serverID, data in Players.all() do ... end
function Players.all()
    return pairs(_cache)
end
