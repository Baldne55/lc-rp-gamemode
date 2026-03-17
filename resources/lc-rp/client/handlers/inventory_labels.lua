-- client/handlers/inventory_labels.lua
-- Renders 3D text labels for dropped items in the world.
-- Server sends drop data via remote events; client draws them each frame.

local LABEL_DRAW_RADIUS = 3
local LABEL_MODEL_HASH  = 0x7CC1EA0B

local _drops   = {}  -- { [dropId] = { x, y, z, text } }
local _tempObj = 0

-- ── WorldToScreen ───────────────────────────────────────────────────────────

local function worldToScreen(x, y, z)
    if not Game.DoesObjectExist(_tempObj) then
        -- L3: Add timeout to prevent infinite loop on model load failure.
        local attempts = 0
        while not Game.HasModelLoaded(LABEL_MODEL_HASH) do
            Game.RequestModel(LABEL_MODEL_HASH)
            attempts = attempts + 1
            if attempts > 500 then return false, 0, 0 end
            Thread.Pause(0)
        end
        _tempObj = Game.CreateObjectNoOffset(LABEL_MODEL_HASH, x, y, z, true)
        Game.SetObjectVisible(_tempObj, false)
    end
    Game.SetObjectCoordinates(_tempObj, x, y, z)

    if not Game.IsObjectOnScreen(_tempObj) then
        return false, 0, 0
    end

    local _, cx, cy = Game.GetViewportPositionOfCoord(x, y, z, 2)
    local sx, sy = Game.GetScreenResolution()

    if cx <= 0 or cx >= sx then return false, 0, 0 end
    if cy <= 0 or cy >= sy then return false, 0, 0 end

    return true, cx / sx, cy / sy
end

-- ── DrawTextAtCoord ─────────────────────────────────────────────────────────

-- L6: Accept pre-computed player position to avoid redundant API calls per drop.
local function drawTextAtCoord(x, y, z, text, px, py, pz)
    local dist = Game.GetDistanceBetweenCoords3d(x, y, z, px, py, pz)
    if dist >= LABEL_DRAW_RADIUS then return end

    local visible, cx, cy = worldToScreen(x, y, z)
    if not visible then return end

    local scale = LABEL_DRAW_RADIUS - dist
    Game.SetTextColour(200, 170, 110, 220)
    Game.SetTextScale(0.13 / LABEL_DRAW_RADIUS * scale, 0.26 / LABEL_DRAW_RADIUS * scale)
    Game.SetTextDropshadow(0, 0, 0, 0, 0)
    Game.SetTextEdge(1, 0, 0, 0, 255)
    Game.SetTextWrap(0.0, 1.0)
    Game.SetTextCentre(true)
    Game.DisplayTextWithLiteralString(cx, cy, "STRING", text)
end

-- ── Remote events ───────────────────────────────────────────────────────────

Events.Subscribe("inv_drop_add", function(dropId, x, y, z, text)
    if type(dropId) == "table" then
        dropId, x, y, z, text = dropId[1], dropId[2], dropId[3], dropId[4], dropId[5]
    end
    if not dropId or not x or not y or not z or not text then return end
    _drops[dropId] = { x = x, y = y, z = z, text = text }
end, true)

Events.Subscribe("inv_drop_remove", function(dropId)
    if type(dropId) == "table" then
        dropId = dropId[1]
    end
    if dropId then _drops[dropId] = nil end
end, true)

Events.Subscribe("inv_drop_sync", function(...)
    local args = {...}
    local items
    if type(args[1]) == "table" and type(args[1][1]) == "table" then
        items = args[1]  -- framework passed the array as a single table arg
    elseif type(args[1]) == "table" then
        items = args      -- framework unpacked into multiple table args
    else
        return
    end
    _drops = {}
    for _, entry in ipairs(items) do
        if type(entry) == "table" then
            local id = entry[1]
            if id then
                _drops[id] = { x = entry[2], y = entry[3], z = entry[4], text = entry[5] }
            end
        end
    end
end, true)

-- ── Render loop ─────────────────────────────────────────────────────────────

-- L4: Cleanup _tempObj on resource stop.
Events.Subscribe("resourceStop", function(resource)
    if resource ~= Resource.GetCurrentName() then return end
    if _tempObj ~= 0 and Game.DoesObjectExist(_tempObj) then
        Game.DeleteObject(_tempObj)
        _tempObj = 0
    end
end)

Events.Subscribe("scriptInit", function()
    Thread.Create(function()
        while true do
            local hasDrops = false
            for _ in pairs(_drops) do hasDrops = true; break end

            if hasDrops then
                -- L6: Compute player position once per frame.
                local playerId  = Game.GetPlayerId()
                local playerIdx = Game.ConvertIntToPlayerindex(playerId)
                local ped       = Game.GetPlayerChar(playerIdx)
                if ped then
                    local px, py, pz = Game.GetCharCoordinates(ped)
                    if px and py and pz then
                        for _, drop in pairs(_drops) do
                            drawTextAtCoord(drop.x, drop.y, drop.z, drop.text, px, py, pz)
                        end
                    end
                end
                Thread.Pause(0)
            else
                Thread.Pause(500)
            end
        end
    end)
end)
