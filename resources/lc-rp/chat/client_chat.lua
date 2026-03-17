-- client_chat.lua
-- Roleplay chat: client-side UI and input. Routes slash commands via Cmd.Execute.
-- Chat.AddMessage used for notifications; no chat channels.
--
-- Public API: Chat.Create, Chat.Destroy, Chat.AddMessage, Chat.Clear, Chat.IsInputActive

local webuiChat
local chatInput = false
local currentFontSize = ClientConfig.CHAT.DEFAULT_FONT_SIZE
local currentPageSize = ClientConfig.CHAT.DEFAULT_PAGE_SIZE
local g_inputLoopRunning = false  -- Prevents thread leak on repeated Chat.Create calls

Chat = {}

function Chat.Create()
    local screenX, screenY = Game.GetScreenResolution()
    webuiChat = WebUI.Create("file://lc-rp/chat/ui/index.html", screenX, screenY, true)

    if not g_inputLoopRunning then
        g_inputLoopRunning = true
        Thread.Create(function()
            while true do
                Thread.Pause(0)
                if webuiChat then
                    if Game.IsGameKeyboardKeyJustPressed(ClientConfig.CHAT.INPUT_KEY) then
                        WebUI.CallEvent(webuiChat, "cmdList", { Cmd.GetList() })
                        WebUI.CallEvent(webuiChat, "forceInput", {true})
                        Thread.Pause(100)
                    end
                else
                    -- If the webuiChat is destroyed, exit the loop.
                    g_inputLoopRunning = false
                    return
                end
            end
        end)
    end
end

function Chat.Destroy()
    if webuiChat then
        WebUI.Destroy(webuiChat)
        webuiChat = nil
    end
end

function Chat.AddMessage(message)
    if webuiChat then
        WebUI.CallEvent(webuiChat, "chatMessage", {message})
    end
end

function Chat.Clear()
    if webuiChat then
        WebUI.CallEvent(webuiChat, "chatClear", {})
    end
end

function Chat.IsInputActive()
    return chatInput
end

function Chat.SetFontSize(size)
    currentFontSize = size
    if webuiChat then
        WebUI.CallEvent(webuiChat, "setFontSize", { size })
    end
end

function Chat.SetPageSize(size)
    currentPageSize = size
    if webuiChat then
        WebUI.CallEvent(webuiChat, "setPageSize", { size })
    end
end

function Chat.GetFontSize()
    return currentFontSize
end

function Chat.GetPageSize()
    return currentPageSize
end

-- Incoming messages from server (formatted); support table or string payload.
Events.Subscribe("chatSendMessage", function (payload)
    local msg = payload
    if type(payload) == "table" then
        msg = payload[1] or payload.message or ""
    end
    if type(msg) == "string" and #msg > 0 then
        Chat.AddMessage(msg)
    end
end, true)

-- Chat Management ---------------------------------------------------------------------------------

Events.Subscribe("chatSettingsRestored", function(payload)
    if type(payload) == "table" then
        if payload[1] and type(payload[1]) == "number" then
            currentFontSize = payload[1]
        end
        if payload[2] and type(payload[2]) == "number" then
            currentPageSize = payload[2]
        end
    end
end)

-- Restore chat preferences from server (sent on character select).
Events.Subscribe("chat_prefs_restore", function(payload)
    if type(payload) == "table" and type(payload[1]) == "table" then payload = payload[1] end
    if type(payload) ~= "table" then return end
    local fontSize = tonumber(payload[1]) or 0
    local pageSize = tonumber(payload[2]) or 0
    if fontSize >= 12 and fontSize <= 24 then
        Chat.SetFontSize(fontSize)
    end
    if pageSize >= 10 and pageSize <= 30 then
        Chat.SetPageSize(pageSize)
    end
end, true)

Events.Subscribe("scriptInit", function()
    -- Initialize the chat input system.
    Chat.Create()
end)

-- F7 toggle: hide/show chat UI.
Events.Subscribe("hud_toggle_all", function(visible)
    if type(visible) == "table" then visible = visible[1] end
    if webuiChat then
        WebUI.CallEvent(webuiChat, "hudToggle", { visible })
    end
end)

Events.Subscribe("chatInputToggle", function (state)
    local playerId = Game.GetPlayerId()

    -- Toggle the chat input state.
    if state then
        Game.NetworkSetLocalPlayerIsTyping(playerId) -- Turn on typing indicator.
        chatInput = true
        if webuiChat then
            WebUI.SetFocus(webuiChat, false)
        end
    else
        Game.NetworkSetLocalPlayerIsTyping(playerId) -- Turn off typing indicator.
        chatInput = false
        WebUI.SetFocus(-1)
    end
end)

-- Chat input: local commands via Cmd.RunLocal; everything else goes to server as rp_chat_message.
local function routeChatSubmit(message)
    if type(message) ~= "string" then message = tostring(message or "") end
    local trimmed = message:match("^%s*(.-)%s*$") or message
    if #trimmed == 0 then return end

    if trimmed:sub(1, 1) == "/" then
        if Cmd.RunLocal(trimmed) then return end
    end
    Events.CallRemote("rp_chat_message", { trimmed })
end

-- Route only on chatInput (our custom chat UI fires this).
Events.Subscribe("chatInput", function (message)
    if type(message) == "table" then message = message[1] end
    routeChatSubmit(message or "")
end)
