-- server/utils/notify.lua
-- Server-side helpers for pushing toast notifications to clients.
-- Requires client/handlers/notifications.lua (isRemoteAllowed = true).
--
-- Usage:
--   Notify.player(source, "success", "Your character has been saved.")
--   Notify.player(source, "error",   "You don't have permission.", 6000)
--   Notify.broadcast("warn", "Server restart in 5 minutes.")
--   Notify.broadcast("info", "Welcome to Liberty City - Roleplay!", 8000)
--
-- Types:    "success" | "error" | "warn" | "info"
-- Duration: optional ms, default 4000.

Notify = {}

-- Sends a toast to a single player.
function Notify.player(source, ntype, message, duration)
    Events.CallRemote("notify", source, { ntype, message, duration or 4000 })
end

-- Sends a toast to every connected, authenticated player.
function Notify.broadcast(ntype, message, duration)
    for serverID, _ in Players.all() do
        Events.CallRemote("notify", serverID, { ntype, message, duration or 4000 })
    end
end
