-- server_chat.lua
-- Roleplay chat: server-side routing and formatting for IC, LOOC, /me, /do, /low, /shout,
-- /melow, /dolow, /melong, /dolong, /pm, /blockpm, admin.
-- Uses Player.GetName(source) (character name set by character handler) and
-- Chat.SendMessage / Chat.BroadcastMessage for delivery.
--
-- Remote events (client -> server): rp_chat_message (single entry), rp_position_sync
-- Outgoing: Chat.SendMessage(serverID, message), Chat.BroadcastMessage(message)

-- Colours (LC-RP chat tags). Name segment uses white.
local COLOUR_NAME  = Config.CHAT.COLOURS.NAME
local COLOUR_IC    = Config.CHAT.COLOURS.IC
local COLOUR_OOC   = Config.CHAT.COLOURS.OOC
local COLOUR_ME_DO = Config.CHAT.COLOURS.ME_DO
local COLOUR_ADMIN   = Config.CHAT.COLOURS.ADMIN
local COLOUR_PM_SENT = Config.CHAT.COLOURS.PM_SENT
local COLOUR_PM_RECV = Config.CHAT.COLOURS.PM_RECV
local COLOUR_TO_ALERT  = Config.CHAT.COLOURS.TO_ALERT
local COLOUR_WHISPER   = Config.CHAT.COLOURS.WHISPER

-- M13: Wall-clock milliseconds for rate limiting. os.clock() returns CPU time
-- on Linux, making it unreliable. Use os.time() * 1000 for second-resolution
-- wall-clock (coarse but correct on all platforms).
local function nowMs()
    return os.time() * 1000
end

-- Proximity: distance in world units; only players within this radius (and same session) receive messages.
local PROXIMITY_RADIUS        = Config.CHAT.PROXIMITY_RADIUS
local LOW_PROXIMITY_RADIUS    = Config.CHAT.LOW_PROXIMITY_RADIUS
local WHISPER_PROXIMITY_RADIUS = Config.CHAT.WHISPER_PROXIMITY_RADIUS
local SHOUT_PROXIMITY_RADIUS  = Config.CHAT.SHOUT_PROXIMITY_RADIUS
local MAX_MESSAGE_LENGTH      = Config.CHAT.MAX_MESSAGE_LENGTH
local CHAT_COOLDOWN_MS    = Config.CHAT.COOLDOWN_MS
local _lastChatTime = {} -- { [serverID] = os.time() }
local _pmBlocks = {} -- { [serverID] = { [blockedID] = true } }

-- Map bounds for position validation.
local MAP_BOUNDS = Config.MAP_BOUNDS

Chat = {}
Chat._lastChatTime = _lastChatTime
Chat._pmBlocks = _pmBlocks

function Chat.clearPlayerState(serverID)
    _lastChatTime[serverID] = nil
    _pmBlocks[serverID] = nil
end

function Chat.SendMessage(serverID, message)
    if Player.IsConnected(serverID) then
        Events.CallRemote("chatSendMessage", serverID, { message })
    end
end

function Chat.BroadcastMessage(message)
    Events.BroadcastRemote("chatSendMessage", { message })
end

-- Strip colour codes ({RRGGBB}) from user input to prevent injection.
local function stripColorCodes(text)
    return text:gsub("{%x%x%x%x%x%x}", "")
end

-- Returns display name for a player (character name once set by character handler).
-- Sanitized to prevent colour code and HTML injection via character names.
local function getDisplayName(serverID)
    local name = Player.GetName(serverID) or "Unknown"
    name = stripColorCodes(name)
    return name
end

-- Returns true if player has staff level set and not "None".
local function isStaff(serverID)
    local data = Players.get(serverID)
    if not data or not data.staffLevel then return false end
    return data.staffLevel ~= "None" and data.staffLevel ~= ""
end

-- Squared distance (avoids sqrt); use for radius comparison with PROXIMITY_RADIUS^2.
local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx * dx + dy * dy + dz * dz
end

-- Highlight *action* segments in IC speech with the ME_DO colour.
local function applyInlineActions(text, restoreColour)
    return text:gsub("%*(.-)%*", COLOUR_ME_DO .. "* %1 *" .. restoreColour)
end

-- Recipients for proximity channels: same session + within given radius.
-- Position comes from rp_position_sync (stored in Players cache as posX, posY, posZ).
-- Sender is always included so they see their own message.
local function getProximityRecipients(source, radius)
    radius = radius or PROXIMITY_RADIUS
    local list = {}
    local sourceSession = Player.GetSession(source)
    local srcData = Players.get(source)
    local sx = srcData and srcData.posX
    local sy = srcData and srcData.posY
    local sz = srcData and srcData.posZ
    local haveSenderPos = (sx ~= nil and sy ~= nil and sz ~= nil)
    local radiusSq = radius * radius

    for serverID, _ in Players.all() do
        if not Player.IsConnected(serverID) then goto continue end
        if Player.GetSession(serverID) ~= sourceSession then goto continue end
        if not Player.IsSessionActive(serverID) then goto continue end

        if serverID == source then
            list[#list + 1] = serverID
            goto continue
        end

        if not haveSenderPos then goto continue end

        local data = Players.get(serverID)
        local px, py, pz = data and data.posX, data and data.posY, data and data.posZ
        if px == nil or py == nil or pz == nil then goto continue end
        if distSq(sx, sy, sz, px, py, pz) > radiusSq then goto continue end

        list[#list + 1] = serverID
        ::continue::
    end
    return list
end

-- Recipients for admin channel: only staff.
local function getStaffRecipients()
    local list = {}
    for serverID, _ in Players.all() do
        if Player.IsConnected(serverID) and isStaff(serverID) then
            list[#list + 1] = serverID
        end
    end
    return list
end

-- IC: in-character speech (proximity + same session).
function Chat.SendIC(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_NAME .. name .. " says: " .. COLOUR_IC .. applyInlineActions(text or "", COLOUR_IC)
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- LOOC: local out-of-character (proximity + same session).
function Chat.SendOOC(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_OOC .. "(( " .. name .. " (ID: " .. source .. ") says: " .. (text or "") .. " ))"
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /me: third-person emote (proximity + same session).
function Chat.SendMe(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. name .. " " .. (text or "")
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /my: possessive third-person emote (proximity + same session).
function Chat.SendMy(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. name .. "'s " .. (text or "")
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /ame: overhead third-person emote (proximity + same session).
-- Also sends to chat like /me, plus an ame_show event for overhead rendering.
function Chat.SendAme(source, text)
    local name = getDisplayName(source)
    local formatted = "* " .. name .. " " .. (text or "")
    local chatMsg = COLOUR_ME_DO .. formatted
    local overhead = formatted:gsub("~", "")
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, chatMsg)
        Events.CallRemote("ame_show", serverID, { source, overhead })
    end
end

-- /amy: overhead possessive third-person emote (proximity + same session).
function Chat.SendAmy(source, text)
    local name = getDisplayName(source)
    local formatted = "* " .. name .. "'s " .. (text or "")
    local chatMsg = COLOUR_ME_DO .. formatted
    local overhead = formatted:gsub("~", "")
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, chatMsg)
        Events.CallRemote("ame_show", serverID, { source, overhead })
    end
end

-- /mylow: possessive third-person emote (low proximity + same session).
function Chat.SendMyLow(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. name .. "'s " .. (text or "")
    for _, serverID in ipairs(getProximityRecipients(source, LOW_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /do: scene description (proximity + same session).
function Chat.SendDo(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. (text or "") .. " (( " .. name .. " ))"
    for _, serverID in ipairs(getProximityRecipients(source)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /low: low-voice IC speech (low proximity + same session).
function Chat.SendLow(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_NAME .. name .. " says (low): " .. COLOUR_IC .. applyInlineActions(text or "", COLOUR_IC)
    for _, serverID in ipairs(getProximityRecipients(source, LOW_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /melow: low-voice third-person emote (low proximity + same session).
function Chat.SendMeLow(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. name .. " " .. (text or "")
    for _, serverID in ipairs(getProximityRecipients(source, LOW_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /dolow: low-voice scene description (low proximity + same session).
function Chat.SendDoLow(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. (text or "") .. " (( " .. name .. " ))"
    for _, serverID in ipairs(getProximityRecipients(source, LOW_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /shout: shouted IC speech (shout proximity + same session).
function Chat.SendShout(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_NAME .. name .. " shouts: " .. COLOUR_IC .. applyInlineActions(text or "", COLOUR_IC) .. "!"
    for _, serverID in ipairs(getProximityRecipients(source, SHOUT_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /melong: long-range third-person emote (shout proximity + same session).
function Chat.SendMeLong(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. name .. " " .. (text or "")
    for _, serverID in ipairs(getProximityRecipients(source, SHOUT_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /dolong: long-range scene description (shout proximity + same session).
function Chat.SendDoLong(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ME_DO .. "* " .. (text or "") .. " (( " .. name .. " ))"
    for _, serverID in ipairs(getProximityRecipients(source, SHOUT_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- Find all connected players matching a partial/full name or exact ID.
-- Returns a list of { id, name } tables.
local function findPlayers(input)
    local results = {}
    local id = tonumber(input)
    if id then
        if Player.IsConnected(id) then
            results[#results + 1] = { id = id, name = getDisplayName(id) }
        end
        return results
    end
    local lower = input:lower()
    for serverID, _ in Players.all() do
        if not Player.IsConnected(serverID) then goto continue end
        local name = getDisplayName(serverID)
        if name:lower():find(lower, 1, true) then
            results[#results + 1] = { id = serverID, name = name }
        end
        ::continue::
    end
    return results
end

-- Find a connected player by server ID (numeric) or partial/full character name.
-- Exact matches are returned immediately. For partial matches, prefers the
-- shortest name; returns nil if multiple partial matches share the same length.
-- Returns serverID, displayName or nil, nil.
local function findPlayer(input)
    local id = tonumber(input)
    if id then
        if Player.IsConnected(id) then
            return id, getDisplayName(id)
        end
        return nil, nil
    end
    local lower = input:lower()
    local bestID, bestName, bestLen, ambiguous
    for serverID, _ in Players.all() do
        if not Player.IsConnected(serverID) then goto continue end
        local name = getDisplayName(serverID)
        local nameLower = name:lower()
        if nameLower == lower then return serverID, name end
        if nameLower:find(lower, 1, true) then
            local len = #name
            if not bestID or len < bestLen then
                bestID, bestName, bestLen = serverID, name, len
                ambiguous = false
            elseif len == bestLen then
                ambiguous = true
            end
        end
        ::continue::
    end
    if ambiguous then return nil, nil end
    return bestID, bestName
end

-- /pm: private message (not proximity-based).
function Chat.SendPM(source, targetID, text)
    local senderName = getDisplayName(source)
    local targetName = getDisplayName(targetID)
    if _pmBlocks[targetID] and _pmBlocks[targetID][source] then
        Notify.player(source, "error", "This player has blocked private messages from you.")
        return
    end
    local sentMsg = COLOUR_PM_SENT .. "(( PM sent to " .. targetName .. " (" .. targetID .. "): " .. (text or "") .. " ))"
    local recvMsg = COLOUR_PM_RECV .. "(( PM from " .. senderName .. " (" .. source .. "): " .. (text or "") .. " ))"
    Chat.SendMessage(source, sentMsg)
    Chat.SendMessage(targetID, recvMsg)
end

-- /blockpm: toggle PM block for a specific player (in-memory).
function Chat.BlockPM(source, targetID)
    if not _pmBlocks[source] then _pmBlocks[source] = {} end
    local targetName = getDisplayName(targetID)
    if _pmBlocks[source][targetID] then
        _pmBlocks[source][targetID] = nil
        Notify.player(source, "info", "Unblocked PMs from " .. targetName .. " (" .. targetID .. ").")
    else
        _pmBlocks[source][targetID] = true
        Notify.player(source, "info", "Blocked PMs from " .. targetName .. " (" .. targetID .. ").")
    end
end

-- /to: directed speech to a specific player (proximity + same session).
-- Target receives a highlighted alert prefix; others see the plain message.
function Chat.SendTo(source, targetID, text, radius, low)
    radius = radius or PROXIMITY_RADIUS
    local senderName = getDisplayName(source)
    local targetName = getDisplayName(targetID)
    local saysTo = low and " says to " .. targetName .. " (low): " or " says to " .. targetName .. ": "
    local base = COLOUR_NAME .. senderName .. saysTo .. COLOUR_IC .. applyInlineActions(text or "", COLOUR_IC)
    local alertMsg = COLOUR_TO_ALERT .. "[ ! ] " .. base
    for _, serverID in ipairs(getProximityRecipients(source, radius)) do
        if serverID == targetID then
            Chat.SendMessage(serverID, alertMsg)
        else
            Chat.SendMessage(serverID, base)
        end
    end
end

-- /sto: directed shout to a specific player (shout proximity + same session).
function Chat.SendShoutTo(source, targetID, text)
    local senderName = getDisplayName(source)
    local targetName = getDisplayName(targetID)
    local base = COLOUR_NAME .. senderName .. " shouts to " .. targetName .. ": " .. COLOUR_IC .. applyInlineActions(text or "", COLOUR_IC) .. "!"
    local alertMsg = COLOUR_TO_ALERT .. "[ ! ] " .. base
    for _, serverID in ipairs(getProximityRecipients(source, SHOUT_PROXIMITY_RADIUS)) do
        if serverID == targetID then
            Chat.SendMessage(serverID, alertMsg)
        else
            Chat.SendMessage(serverID, base)
        end
    end
end

-- /whisper: whispered IC speech (whisper proximity + same session).
function Chat.SendWhisper(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_WHISPER .. name .. " whispers: " .. applyInlineActions(text or "", COLOUR_WHISPER)
    for _, serverID in ipairs(getProximityRecipients(source, WHISPER_PROXIMITY_RADIUS)) do
        Chat.SendMessage(serverID, msg)
    end
end

-- /wto: directed whisper to a specific player (sender + target only, within whisper proximity).
function Chat.SendWhisperTo(source, targetID, text)
    local senderName = getDisplayName(source)
    local targetName = getDisplayName(targetID)
    local base = COLOUR_WHISPER .. senderName .. " whispers to " .. targetName .. ": " .. applyInlineActions(text or "", COLOUR_WHISPER)
    local alertMsg = COLOUR_TO_ALERT .. "[ ! ] " .. base

    -- Verify target is within whisper proximity before sending.
    local recipients = getProximityRecipients(source, WHISPER_PROXIMITY_RADIUS)
    local targetInRange = false
    for _, serverID in ipairs(recipients) do
        if serverID == targetID then targetInRange = true; break end
    end

    if not targetInRange then
        Notify.player(source, "error", "That player is not close enough to whisper to.")
        return
    end

    -- Only sender and target see the whisper.
    Chat.SendMessage(source, base)
    Chat.SendMessage(targetID, alertMsg)
end

-- Admin: staff-only broadcast.
function Chat.SendAdmin(source, text)
    local name = getDisplayName(source)
    local msg = COLOUR_ADMIN .. "[A] " .. COLOUR_NAME .. name .. COLOUR_ADMIN .. ": " .. (text or "")
    for _, serverID in ipairs(getStaffRecipients()) do
        Chat.SendMessage(serverID, msg)
    end
end

-- Remote handlers: accept { text } or raw text from client.
local function getText(payload)
    if type(payload) == "table" and payload[1] ~= nil then
        return tostring(payload[1])
    end
    if type(payload) == "string" then return payload end
    return ""
end

-- Helper: parse target + text from "full" arg string for targeted commands.
-- Returns targetID, targetName, text  or  nil (with error already sent).
local function parseTargetText(source, full, usage, selfErr)
    local target = full:match("^(%S+)")
    local text = full:match("^%S+%s+(.+)$")
    if not target or not text then
        Notify.player(source, "error", usage)
        return nil
    end
    text = text:match("^%s*(.-)%s*$") or text
    if #text == 0 then
        Notify.player(source, "error", usage)
        return nil
    end
    local targetID, targetName = findPlayer(target)
    if not targetID then
        Notify.player(source, "error", "Player not found: " .. target)
        return nil
    end
    if targetID == source then
        Notify.player(source, "error", selfErr)
        return nil
    end
    return targetID, targetName, text
end

-- Helper: parse target only (no text) from "full" arg string.
local function parseTarget(source, full, usage, selfErr)
    local input = full:match("^%s*(.-)%s*$") or full
    if #input == 0 then
        Notify.player(source, "error", usage)
        return nil
    end
    local targetID = findPlayer(input)
    if not targetID then
        Notify.player(source, "error", "Player not found: " .. input)
        return nil
    end
    if targetID == source then
        Notify.player(source, "error", selfErr)
        return nil
    end
    return targetID
end

-- Register chat commands via ServerCmd so hints are auto-pushed to clients. ----

ServerCmd.register("me", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendMe(source, full)
end, "Third-person emote (10 units)")

ServerCmd.register("my", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendMy(source, full)
end, "Possessive emote (10 units)")

ServerCmd.register("ame", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendAme(source, full)
end, "Overhead emote (10 units)")

ServerCmd.register("amy", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendAmy(source, full)
end, "Overhead possessive emote (10 units)")

ServerCmd.register("mylow", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendMyLow(source, full)
end, "Possessive emote (low, 5 units)")

ServerCmd.register("do", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendDo(source, full)
end, "Scene description (10 units)")

ServerCmd.register("low", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendLow(source, full)
end, "Low-voice speech (5 units)")

ServerCmd.register("melow", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendMeLow(source, full)
end, "Low-voice emote (5 units)")

ServerCmd.register("dolow", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendDoLow(source, full)
end, "Low-voice scene description (5 units)")

ServerCmd.register("melong", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendMeLong(source, full)
end, "Long-range emote (20 units)")

ServerCmd.register("dolong", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendDoLong(source, full)
end, "Long-range scene description (20 units)")

ServerCmd.register("whisper", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendWhisper(source, full)
end, "Whisper (3 units)", { "w" })

ServerCmd.register("shout", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendShout(source, full)
end, "Shout (20 units)", { "s" })

ServerCmd.register("b", function(source, _args, full)
    if #full == 0 then return end
    Chat.SendOOC(source, full)
end, "Local OOC (10 units)", { "looc" })

ServerCmd.register("a", function(source, _args, full)
    if not isStaff(source) then
        Notify.player(source, "error", "You do not have permission to use this command.")
        return
    end
    if #full == 0 then return end
    Chat.SendAdmin(source, full)
end, "Admin chat (staff only)")

ServerCmd.register("wto", function(source, _args, full)
    local targetID, _, text = parseTargetText(
        source, full,
        "Usage: /wto <ID or Name> <message>",
        "You cannot whisper to yourself.")
    if not targetID then return end
    Chat.SendWhisperTo(source, targetID, text)
end, "Whisper to player (3 units)", { "whisperto" })

ServerCmd.register("sto", function(source, _args, full)
    local targetID, _, text = parseTargetText(
        source, full,
        "Usage: /sto <ID or Name> <message>",
        "You cannot shout to yourself.")
    if not targetID then return end
    Chat.SendShoutTo(source, targetID, text)
end, "Shout to player (20 units)", { "shoutto" })

ServerCmd.register("to", function(source, _args, full)
    local targetID, _, text = parseTargetText(
        source, full,
        "Usage: /to <ID or Name> <message>",
        "You cannot say to yourself.")
    if not targetID then return end
    Chat.SendTo(source, targetID, text)
end, "Say to player (10 units)", { "sayto" })

ServerCmd.register("tolow", function(source, _args, full)
    local targetID, _, text = parseTargetText(
        source, full,
        "Usage: /tolow <ID or Name> <message>",
        "You cannot say to yourself.")
    if not targetID then return end
    Chat.SendTo(source, targetID, text, LOW_PROXIMITY_RADIUS, true)
end, "Say to player (low, 5 units)", { "saytolow" })

ServerCmd.register("pm", function(source, _args, full)
    local targetID, _, text = parseTargetText(
        source, full,
        "Usage: /pm <ID or Name> <message>",
        "You cannot PM yourself.")
    if not targetID then return end
    Chat.SendPM(source, targetID, text)
end, "Private message", { "dm" })

ServerCmd.register("blockpm", function(source, _args, full)
    local targetID = parseTarget(
        source, full,
        "Usage: /blockpm <ID or Name>",
        "You cannot block yourself.")
    if not targetID then return end
    Chat.BlockPM(source, targetID)
end, "Toggle PM block", { "blockdm" })

ServerCmd.register("id", function(source, _args, full)
    local input = full:match("^%s*(.-)%s*$") or full
    if #input == 0 then
        Notify.player(source, "error", "Usage: /id <ID or Name>")
        return
    end
    local results = findPlayers(input)
    if #results == 0 then
        Notify.player(source, "error", "Player not found: " .. input)
        return
    end
    for _, p in ipairs(results) do
        local data = Players.get(p.id)
        local level = (data and data.charLevel) or 1
        Notify.player(source, "info", "ID of " .. p.name .. " is " .. p.id .. ". They are level " .. level .. ".")
    end
end, "Look up player ID and level")

-- Single entry point: rate-limit, sanitize, then delegate to ServerCmd or IC.
Events.Subscribe("rp_chat_message", function(payload)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    -- Rate limit: one message per CHAT_COOLDOWN_MS.
    local now = nowMs()
    local lastMs = _lastChatTime[source] or 0
    if (now - lastMs) < CHAT_COOLDOWN_MS then return end
    _lastChatTime[source] = now

    local raw = getText(payload)
    local trimmed = raw:match("^%s*(.-)%s*$") or raw
    if #trimmed == 0 then return end

    -- Server-side length cap (client enforces 255 in JS, but modified clients can bypass).
    if #trimmed > MAX_MESSAGE_LENGTH then
        trimmed = trimmed:sub(1, MAX_MESSAGE_LENGTH)
    end

    -- Strip colour code injection ({RRGGBB} sequences) from user input.
    trimmed = stripColorCodes(trimmed)
    if #trimmed == 0 then return end

    if trimmed:sub(1, 1) == "/" then
        local cmdName = trimmed:match("^/(%S+)")
        if cmdName then
            local argsStr = trimmed:match("^/%S+%s+(.+)$") or ""
            local cmdArgs = {}
            for arg in argsStr:gmatch("%S+") do cmdArgs[#cmdArgs + 1] = arg end
            if not ServerCmd.execute(source, cmdName, cmdArgs, argsStr) then
                Notify.player(source, "error", "Unknown command: /" .. cmdName)
            end
            return
        end
        Notify.player(source, "error", "Unknown command: " .. trimmed)
        return
    end
    Chat.SendIC(source, trimmed)
end, true)

-- Position sync constants (proximity chat use only — not used for saves).
local MIN_SYNC_INTERVAL_MS  = 200        -- reject syncs arriving faster than this (ms)
local MAX_POSITION_DELTA_SQ = 50 * 50   -- max movement per sync interval (units²)
local JUST_SPAWNED_WINDOW_MS = 2000     -- suppress teleport detection after spawn (ms)

local _lastSyncTime    = {}  -- { [serverID] = os.time() * 1000 }
local _lastAcceptedPos = {}  -- { [serverID] = { x, y, z } }
local _justSpawnedTime = {}  -- { [serverID] = os.time() * 1000 }
local _teleportStrikes = {}  -- { [serverID] = count } — tracks repeated violations

-- Call after teleporting a player (spawn, respawn) to suppress false teleport
-- detections for JUST_SPAWNED_WINDOW_MS.
function Chat.setJustSpawned(serverID)
    _justSpawnedTime[serverID] = nowMs()
end

-- Position sync: client sends { x, y, z [, r] }; stored in Players cache for
-- proximity chat only. Health/armour are handled via rp_health_sync.
-- Validates map bounds, server-side rate limit, and teleport detection.
Events.Subscribe("rp_position_sync", function(...)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    -- Server-side rate limit: ignore bursts faster than MIN_SYNC_INTERVAL_MS.
    local now = nowMs()
    if (now - (_lastSyncTime[source] or 0)) < MIN_SYNC_INTERVAL_MS then return end

    local a, b, c, d = ...
    local payload = (type(a) == "table" and a) or { a, b, c, d }
    if type(payload) ~= "table" then return end

    local x = tonumber(payload[1] or payload.x)
    local y = tonumber(payload[2] or payload.y)
    local z = tonumber(payload[3] or payload.z)
    local r = tonumber(payload[4] or payload.r)
    if not (x and y and z) then return end

    -- Reject positions outside map bounds.
    if x < MAP_BOUNDS.xMin or x > MAP_BOUNDS.xMax
        or y < MAP_BOUNDS.yMin or y > MAP_BOUNDS.yMax
        or z < MAP_BOUNDS.zMin or z > MAP_BOUNDS.zMax then
        return
    end

    -- Teleport detection: reject implausible jumps unless just spawned or in noclip.
    local playerData = Players.get(source)
    local noclipActive = playerData and playerData.noclipActive
    local justSpawned  = (now - (_justSpawnedTime[source] or 0)) < JUST_SPAWNED_WINDOW_MS
    if not noclipActive and not justSpawned then
        local last = _lastAcceptedPos[source]
        if last then
            local dx, dy, dz = x - last[1], y - last[2], z - last[3]
            local distSqVal = dx * dx + dy * dy + dz * dz
            if distSqVal > MAX_POSITION_DELTA_SQ then
                _teleportStrikes[source] = (_teleportStrikes[source] or 0) + 1
                local strikes = _teleportStrikes[source]
                local playerName = Player.GetName(source) or tostring(source)
                local pData = Players.get(source)
                local dist = math.floor(math.sqrt(distSqVal))
                Log.warn("AntiCheat", string.format(
                    "TELEPORT: %s (%d) [char=%d, account=%s] moved %dm in one sync (from %.1f,%.1f,%.1f to %.1f,%.1f,%.1f) — strike %d",
                    playerName, source,
                    pData and pData.charId or 0, tostring(pData and pData.accountId or "?"),
                    dist, last[1], last[2], last[3], x, y, z, strikes
                ))
                return
            end
        end
    end

    _lastSyncTime[source]    = now
    _lastAcceptedPos[source] = { x, y, z }

    local set = { posX = x, posY = y, posZ = z }
    -- Clamp heading to [0, 360].
    if r then set.posR = math.max(0, math.min(360, r)) end
    Players.set(source, set)
end, true)

-- Health sync constants.
local MIN_HEALTH_SYNC_INTERVAL_MS = 1000  -- max 1 update/sec from client
local _lastHealthSyncTime = {}  -- { [serverID] = os.time() * 1000 }

-- Anti-cheat strike counters (declared here so clearSyncState can reference them).
local HEALTH_TOLERANCE     = 20   -- native scale units (10 HP in DB scale)
local POS_DESYNC_THRESHOLD = 100  -- units² — flag if server pos diverges from client pos
local _healthStrikes = {}  -- { [serverID] = count }
local _posDesyncStrikes = {} -- { [serverID] = count }

function Chat.clearSyncState(serverID)
    _lastSyncTime[serverID] = nil
    _lastAcceptedPos[serverID] = nil
    _justSpawnedTime[serverID] = nil
    _lastHealthSyncTime[serverID] = nil
    _teleportStrikes[serverID] = nil
    _healthStrikes[serverID] = nil
    _posDesyncStrikes[serverID] = nil
end

-- Health/armour sync: client sends { hp, ap } (native 0-200 scale).
-- Decreases are always accepted (damage is hard to fake upwards).
-- Increases are only accepted during a server-opened heal window.
Events.Subscribe("rp_health_sync", function(payload)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    local now = nowMs()
    if (now - (_lastHealthSyncTime[source] or 0)) < MIN_HEALTH_SYNC_INTERVAL_MS then return end
    _lastHealthSyncTime[source] = now

    local hp, ap
    if type(payload) == "table" then
        hp = tonumber(payload[1] or payload.hp)
        ap = tonumber(payload[2] or payload.ap)
    end
    if not hp and not ap then return end

    local data = Players.get(source)
    if not data then return end
    local healOpen = CharState.isHealWindowOpen(source)
    local set = {}

    if hp then
        hp = math.max(0, math.min(200, hp))
        -- Derive baseline from authoritative/db value; default to 200 (full health)
        -- if none exists, so clients cannot report an arbitrary increase on first sync.
        local prev = data.syncHp or (data.authHp and data.authHp * 2) or (data.dbHp and data.dbHp * 2) or 200
        if hp <= prev then
            set.syncHp = hp
        elseif healOpen then
            -- H2: Cap increase to the server-set target, not arbitrary values.
            local targetHp = CharState.getHealTargetHp(source) or prev
            set.syncHp = math.min(hp, targetHp)
        end
    end

    if ap then
        ap = math.max(0, math.min(200, ap))
        -- Default to 0 for armour (players typically spawn without armour).
        local prev = data.syncAp or (data.authAp and data.authAp * 2) or (data.dbAp and data.dbAp * 2) or 0
        if ap <= prev then
            set.syncAp = ap
        elseif healOpen then
            local targetAp = CharState.getHealTargetAp(source) or prev
            set.syncAp = math.min(ap, targetAp)
        end
    end

    if next(set) then
        Players.set(source, set)
    end

end, true)

-- ── Ammo sync ─────────────────────────────────────────────────────────────
-- Client reports current native ammo after firing. Ammo is already removed
-- from inventory on equip, so the server just tracks the count here and
-- auto-unequips when it reaches 0.

Events.Subscribe("rp_ammo_sync", function(...)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    local a, b = ...
    local payload = (type(a) == "table" and a) or { a, b }
    local weaponType = tonumber(payload[1])
    local clientAmmo = tonumber(payload[2])
    if not weaponType or not clientAmmo then return end
    clientAmmo = math.max(0, clientAmmo)

    local data = Players.get(source)
    if not data or not data.charId then return end
    if not data.equippedSlot or not data.equippedItemId then return end

    -- Validate equipped weapon matches reported weaponType.
    local item = Inventory.getItemAtSlot(data.charId, data.equippedSlot)
    if not item or item.inv_item_id ~= data.equippedItemId then
        data.equippedSlot      = nil
        data.equippedItemId    = nil
        data.equippedAmmoGroup = nil
        return
    end
    local def = ItemRegistry.get(item.inv_item_def_id)
    if not def or not def.ammoGroup or def.weaponTypeId ~= weaponType then return end

    -- Update tracked ammo count.
    local baseline = data.serverLastAmmo or 0
    if clientAmmo >= baseline then return end
    data.serverLastAmmo = clientAmmo

    if clientAmmo <= 0 then
        -- Auto-unequip: no ammo remaining.
        data.equippedSlot      = nil
        data.equippedItemId    = nil
        data.equippedAmmoGroup = nil
        data.serverLastAmmo    = nil
        Events.CallRemote("char_unequip_weapon", source, { weaponType })
        Notify.player(source, "error", "Out of ammo — weapon unequipped.")
        Log.info("AmmoSync", string.format("%s (%d) auto-unequipped (no ammo, group=%s)",
            Player.GetName(source) or tostring(source), source, def.ammoGroup))
    end
end, true)

-- ── Ammo return ──────────────────────────────────────────────────────────
-- Client reports remaining ammo when a weapon is unequipped. The server
-- now returns ammo authoritatively on unequip/swap using data.serverLastAmmo,
-- so this handler is intentionally a no-op. The client still sends it (for
-- backwards compatibility) but the server ignores the reported amount.
-- This prevents exploits where a modified client reports inflated ammo counts.

Events.Subscribe("rp_ammo_return", function(...)
    -- Ammo is now returned server-side in the unequip/swap handlers.
    -- Ignoring client-reported ammo to prevent exploitation.
end, true)

-- ── Weapon audit ────────────────────────────────────────────────────────
-- Client-side scanner reports unauthorized weapons (trainer-spawned).
-- Server logs for admin review. Heartbeat detects suppressed scanners.

local HEARTBEAT_TIMEOUT_SEC = 45  -- flag if no heartbeat for this long
local _lastHeartbeat = {}         -- { [source] = os.time() }

Events.Subscribe("rp_weapon_violation", function(...)
    local source = Events.GetSource()
    if not Guard.requireChar(source) then return end

    local a, b, c = ...
    local payload = (type(a) == "table" and a) or { a, b, c }
    local weaponType = tonumber(payload[1])
    local ammo       = tonumber(payload[2]) or 0
    local weaponName = tostring(payload[3] or "Unknown")

    if not weaponType then return end

    local data = Players.get(source)
    if not data then return end

    local playerName = Player.GetName(source) or tostring(source)
    local equippedInfo = data.equippedSlot and ("equipped slot " .. data.equippedSlot) or "no weapon equipped"

    Log.warn("WeaponAudit", string.format(
        "VIOLATION: %s (%d) [char=%d, account=%s] had unauthorized %s (type=%d, ammo=%d) — %s. Weapon removed.",
        playerName, source,
        data.charId or 0, tostring(data.accountId or "?"),
        weaponName, weaponType, ammo,
        equippedInfo
    ))
end, true)

Events.Subscribe("rp_weapon_audit_heartbeat", function(...)
    local source = Events.GetSource()
    _lastHeartbeat[source] = os.time()
end, true)

-- Check for missing heartbeats periodically.
-- Runs on a background thread started from server init.
function CheckWeaponAuditHeartbeats()
    local now = os.time()
    for serverID, _ in Players.all() do
        if Player.IsConnected(serverID) then
            local data = Players.get(serverID)
            if data and data.charId then
                local lastBeat = _lastHeartbeat[serverID]
                if lastBeat and (now - lastBeat) > HEARTBEAT_TIMEOUT_SEC then
                    local playerName = Player.GetName(serverID) or tostring(serverID)
                    Log.warn("WeaponAudit", string.format(
                        "HEARTBEAT MISSING: %s (%d) [char=%d, account=%s] — no weapon audit heartbeat for %ds. Possible script suppression.",
                        playerName, serverID,
                        data.charId or 0, tostring(data.accountId or "?"),
                        now - lastBeat
                    ))
                end
            end
        else
            _lastHeartbeat[serverID] = nil
        end
    end
end

-- ── Server-side anti-cheat checks ──────────────────────────────────────
-- Periodic cross-checks using server-side Player API to detect:
--   1. Health hacking (god mode): server reads native HP > syncHp by a large margin
--   2. Position desync (airbreak/teleport): server-side position diverges from client-reported

function RunAntiCheatChecks()
    for serverID, _ in Players.all() do
        if not Player.IsConnected(serverID) then
            _healthStrikes[serverID] = nil
            _posDesyncStrikes[serverID] = nil
            goto nextPlayer
        end

        local data = Players.get(serverID)
        if not data or not data.charId then goto nextPlayer end
        if data.noclipActive then goto nextPlayer end

        local playerName = Player.GetName(serverID) or tostring(serverID)

        -- Health check: compare server-side native HP against client-reported syncHp.
        local okHp, nativeHp = pcall(Player.GetHealth, serverID)
        if okHp and nativeHp then
            local syncHp = data.syncHp or (data.authHp and data.authHp * 2) or (data.dbHp and data.dbHp * 2)
            if syncHp then
                -- If native health is significantly higher than what the client reported,
                -- the client may be suppressing health sync to hide god mode.
                -- Also flag if health is at max (200) but syncHp shows damage taken.
                if nativeHp > syncHp + HEALTH_TOLERANCE and not CharState.isHealWindowOpen(serverID) then
                    _healthStrikes[serverID] = (_healthStrikes[serverID] or 0) + 1
                    Log.warn("AntiCheat", string.format(
                        "HEALTH SUSPECT: %s (%d) [char=%d, account=%s] native HP=%d but syncHp=%d (diff=%d) — strike %d",
                        playerName, serverID,
                        data.charId or 0, tostring(data.accountId or "?"),
                        nativeHp, syncHp, nativeHp - syncHp,
                        _healthStrikes[serverID]
                    ))
                else
                    -- Reset strikes on clean check.
                    _healthStrikes[serverID] = nil
                end
            end
        end

        -- Position cross-check: compare server-side Player.GetPosition against
        -- client-reported posX/posY/posZ. Large divergence suggests airbreak or
        -- position spoofing.
        local okPos, sx, sy, sz = pcall(Player.GetPosition, serverID)
        if okPos and sx and data.posX and data.posY and data.posZ then
            local dx, dy, dz = sx - data.posX, sy - data.posY, sz - data.posZ
            local dSq = dx * dx + dy * dy + dz * dz
            if dSq > POS_DESYNC_THRESHOLD then
                _posDesyncStrikes[serverID] = (_posDesyncStrikes[serverID] or 0) + 1
                local dist = math.floor(math.sqrt(dSq))
                Log.warn("AntiCheat", string.format(
                    "POS DESYNC: %s (%d) [char=%d, account=%s] server pos (%.1f,%.1f,%.1f) vs client (%.1f,%.1f,%.1f) — %dm apart — strike %d",
                    playerName, serverID,
                    data.charId or 0, tostring(data.accountId or "?"),
                    sx, sy, sz, data.posX, data.posY, data.posZ,
                    dist, _posDesyncStrikes[serverID]
                ))
            else
                _posDesyncStrikes[serverID] = nil
            end
        end

        ::nextPlayer::
    end
end
