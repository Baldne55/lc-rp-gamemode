-- server/handlers/noclip.lua
-- Server-side noclip permission gate.
--
-- Client sends skynoclip:Request { enable }; server checks staffLevel and
-- replies with skynoclip:Granted { enable } or skynoclip:Denied {}.
-- Noclip state is tracked in the Players cache (noclipActive).

local LOG_TAG = "Noclip"

Events.Subscribe("skynoclip:Request", function(enable)
    local source = Events.GetSource()
    if not Guard.requireStaff(source) then
        Log.warn(LOG_TAG, "Unauthorized noclip attempt by " .. tostring(source) .. ".")
        Notify.player(source, "error", "You do not have permission to use noclip.")
        Events.CallRemote("skynoclip:Denied", source, {})
        return
    end

    local data = Players.get(source)
    enable = (enable == true or enable == 1)
    Players.set(source, { noclipActive = enable })
    -- Reset position sync baseline so the first sync after noclip isn't rejected.
    if not enable then
        Chat.clearSyncState(source)
    end
    Log.info(LOG_TAG, (data.username or tostring(source)) .. " " .. (enable and "enabled" or "disabled") .. " noclip.")
    Events.CallRemote("skynoclip:Granted", source, { enable })
end, true)
