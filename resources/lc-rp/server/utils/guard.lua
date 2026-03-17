-- server/utils/guard.lua
-- Server-side session guards. Call at the top of remote event handlers to
-- silently discard requests from unauthenticated or unspawned clients.
--
-- Usage:
--   if not Guard.requireAuth(source) then return end   -- account logged in
--   if not Guard.requireChar(source) then return end   -- character selected
--   if not Guard.requireStaff(source) then return end  -- staff level not "None"

Guard = {}

-- Returns true if source has a valid authenticated session (account logged in).
function Guard.requireAuth(source)
    local data = Players.get(source)
    return data ~= nil and data.accountId ~= nil
end

-- Returns true if source has a valid authenticated session AND a selected character.
function Guard.requireChar(source)
    local data = Players.get(source)
    return data ~= nil and data.accountId ~= nil and data.charId ~= nil
end

-- Returns true if source has a char-selected session AND a non-None staff level.
function Guard.requireStaff(source)
    local data = Players.get(source)
    return data ~= nil and data.accountId ~= nil and data.charId ~= nil
        and data.staffLevel ~= nil and data.staffLevel ~= "None"
end
