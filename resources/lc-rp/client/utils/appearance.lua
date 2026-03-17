-- client/utils/appearance.lua
-- Shared appearance application utility for character clothing components.
-- Eliminates duplication across character.lua preview and spawn handlers.

Appearance = {}

--- Applies clothing component overrides to a player character.
--- @param playerChar number  The player character handle.
--- @param data table|string  Appearance data: table with keys "0"-"10" -> {drawable, texture}, or JSON string.
function Appearance.apply(playerChar, data)
    if not data or data == "" then return end

    local appearance = data
    if type(data) == "string" then
        local ok, decoded = pcall(function() return JSON.decode(data) end)
        if not ok or type(decoded) ~= "table" then return end
        appearance = decoded
    end

    if type(appearance) ~= "table" then return end

    for componentId = 0, (ClientConfig.COMPONENT_COUNT - 1) do
        local key = tostring(componentId)
        local val = appearance[key]
        if val and type(val) == "table" and #val >= 2 then
            local drawable = tonumber(val[1])
            local texture  = tonumber(val[2])
            if drawable and texture and drawable >= 0 and texture >= 0 then
                pcall(function()
                    Game.SetCharComponentVariation(playerChar, componentId, drawable, texture)
                end)
            end
        end
    end
end
