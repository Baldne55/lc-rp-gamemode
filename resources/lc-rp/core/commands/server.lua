-- core/commands/server.lua
-- Server-side command dispatcher. Routes server_command events from authenticated,
-- char-selected clients to registered command handlers.
--
-- Usage (from any server handler):
--   ServerCmd.register("cmdname", handler, "description", { "alias1", "alias2" })

ServerCmd = {}
local _handlers = {}
local _meta = {}
local _aliases = {}

local function resolve(name)
    return _aliases[name] or name
end

function ServerCmd.register(name, fn, description, aliases)
    _handlers[name] = fn
    _meta[name] = { description = description, aliases = aliases }
    if aliases then
        for _, alias in ipairs(aliases) do
            _aliases[alias] = name
        end
    end
end

function ServerCmd.hasHandler(name)
    return _handlers[resolve(name)] ~= nil
end

function ServerCmd.exists(name)
    return _handlers[resolve(name)] ~= nil
end

-- Returns hint data for all registered commands so the client can show them
-- in the chat autocomplete. Called once after character selection.
function ServerCmd.getHintList()
    local list = {}
    for name, meta in pairs(_meta) do
        local entry = { name = "/" .. name, description = meta.description or "" }
        if meta.aliases then
            local prefixed = {}
            for i, a in ipairs(meta.aliases) do prefixed[i] = "/" .. a end
            entry.aliases = prefixed
        end
        list[#list + 1] = entry
    end
    return list
end

-- Pushes the server command hint list to a specific client.
function ServerCmd.sendHints(serverID)
    Events.CallRemote("server_cmd_hints", serverID, { ServerCmd.getHintList() })
end

-- Direct invocation from server-side code (e.g. chat router) where
-- Events.GetSource() is unavailable because the call is local.
-- Returns true if a handler was found (even if it errored), false otherwise.
function ServerCmd.execute(source, name, args, full)
    if not Guard.requireChar(source) then return true end
    local canonical = name and resolve(name)
    local handler = canonical and _handlers[canonical]
    if handler then
        local ok, err = pcall(handler, source, args, full or "")
        if not ok then
            Log.error("ServerCmd", "handler '" .. tostring(name) .. "' error: " .. tostring(err))
            Notify.player(source, "error", "Command failed. Check console for details.")
        end
        return true
    end
    return false
end

-- C5: Per-player command cooldown shared with Chat._lastChatTime.
local CMD_COOLDOWN_MS = 500
local _lastCmdTime = {}

function ServerCmd.clearPlayerState(serverID)
    _lastCmdTime[serverID] = nil
end

local function cmdNowMs()
    return os.time() * 1000
end

Events.Subscribe("server_command", function(payload)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end
    if type(payload) ~= "table" then return end

    -- Rate limit: one command per CMD_COOLDOWN_MS.
    local now = cmdNowMs()
    local lastMs = _lastCmdTime[source] or 0
    if (now - lastMs) < CMD_COOLDOWN_MS then return end
    _lastCmdTime[source] = now

    local name = payload.name or payload[1]
    local args = payload.args or payload[2] or {}
    local full = payload.full or payload[3] or ""

    local canonical = name and resolve(name)
    local handler = canonical and _handlers[canonical]
    if handler then
        local ok, err = pcall(handler, source, args, full)
        if not ok then
            Log.error("ServerCmd", "handler '" .. tostring(name) .. "' error: " .. tostring(err))
            Notify.player(source, "error", "Command failed. Check console for details.")
        end
    end
end, true)
