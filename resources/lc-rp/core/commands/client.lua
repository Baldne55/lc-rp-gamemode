-- core/commands/client.lua
-- Command registry: Cmd.Register, Cmd.GetList, Cmd.Execute.
-- Client-side commands run locally; unknown commands are sent to server.
-- Set CMD_HANDLER_ENABLED to false to temporarily disable (Cmd remains defined, no-ops).

local CMD_HANDLER_ENABLED = true  -- Enable so roleplay client commands (e.g. /coords, /fontsize) run locally

local commands = {}

Cmd = {}

function Cmd.Register(def)
    if not CMD_HANDLER_ENABLED or not def or not def.name then return end
    commands[#commands + 1] = def
end

-- Public view for UI/autocomplete: strip function fields so WebUI does not receive
-- unsupported argument types (functions cannot be marshalled across the bridge).
function Cmd.GetList()
    local public = {}
    for i, def in ipairs(commands) do
        public[i] = {
            name        = def.name,
            aliases     = def.aliases,
            description = def.description,
        }
    end
    return public
end

local function parseArgs(full)
    local cmd = full:match("^%s*(%S+)") or ""
    local rest = full:match("^%s*%S+%s+(.*)$") or ""
    local args = {}
    for word in rest:gmatch("%S+") do
        args[#args + 1] = word
    end
    return cmd, args
end

local function findCommand(cmdName)
    local lower = cmdName:lower()
    for _, def in ipairs(commands) do
        if def.name:lower() == lower then return def end
        if def.aliases then
            for _, alias in ipairs(def.aliases) do
                if alias:lower() == lower then return def end
            end
        end
    end
    return nil
end

function Cmd.Execute(full)
    if not CMD_HANDLER_ENABLED then return end
    if type(full) ~= "string" or #full == 0 then return end
    local cmdName, args = parseArgs(full)
    if #cmdName == 0 then return end

    local def = findCommand(cmdName)
    if def and def.run then
        def.run(args, full)
        return
    end

    -- Unknown or server-side command: send to server.
    Events.CallRemote("server_command", { name = cmdName, args = args, full = full })
end

-- Merge server-side command hints pushed after character selection.
-- Avoids duplicates so reconnecting or re-selecting doesn't stack entries.
Events.Subscribe("server_cmd_hints", function(payload)
    local list
    if type(payload) == "table" then
        if type(payload[1]) == "table" and payload[1].name then
            list = payload
        else
            list = payload[1] or payload
        end
    else
        return
    end
    local existing = {}
    for _, def in ipairs(commands) do
        existing[def.name:lower()] = true
        if def.aliases then
            for _, a in ipairs(def.aliases) do existing[a:lower()] = true end
        end
    end
    for _, hint in ipairs(list) do
        if type(hint) == "table" and hint.name and not existing[hint.name:lower()] then
            commands[#commands + 1] = {
                name        = hint.name,
                aliases     = hint.aliases,
                description = hint.description,
            }
            existing[hint.name:lower()] = true
            if hint.aliases then
                for _, a in ipairs(hint.aliases) do existing[a:lower()] = true end
            end
        end
    end
end, true)

-- Run only if a local command matches; does not send to server. Returns true if a local command was run.
function Cmd.RunLocal(full)
    if not CMD_HANDLER_ENABLED then return false end
    if type(full) ~= "string" or #full == 0 then return false end
    local cmdName, args = parseArgs(full)
    if #cmdName == 0 then return false end
    local def = findCommand(cmdName)
    if def and def.run then
        def.run(args, full)
        return true
    end
    return false
end
