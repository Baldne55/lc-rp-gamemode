-- server/utils/log.lua
-- Structured logging module. Replaces scattered Console.Log("[Module] ...") calls.

Log = {}

function Log.info(module, msg)
    Console.Log("[" .. tostring(module) .. "] " .. tostring(msg))
end

function Log.warn(module, msg)
    Console.Log("[" .. tostring(module) .. "] WARN: " .. tostring(msg))
end

function Log.error(module, msg)
    Console.Log("[" .. tostring(module) .. "] ERROR: " .. tostring(msg))
end
