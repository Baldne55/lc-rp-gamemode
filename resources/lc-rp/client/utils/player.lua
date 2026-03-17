-- client/utils/player.lua
-- Shared player state utilities (freeze/unfreeze, visibility).
-- Eliminates duplication across auth.lua, character.lua, and noclip.lua.

PlayerUtil = {}

--- Freezes or unfreezes the local player (controls, visibility, invincibility, collision).
function PlayerUtil.setFrozen(freeze)
    local playerId    = Game.GetPlayerId()
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local playerChar  = Game.GetPlayerChar(playerIndex)
    if not playerChar then return end

    Game.SetPlayerControlForNetwork(playerIndex, not freeze, false)
    Game.SetCharVisible(playerChar, not freeze)
    Game.SetPlayerInvincible(playerIndex, freeze)
    Game.FreezeCharPosition(playerChar, freeze)
    Game.SetCharNeverTargetted(playerChar, freeze)
    Game.SetCharCollision(playerChar, not freeze)
end

--- Restores player to normal playable state (unfreeze + enable controls + visible).
function PlayerUtil.restore()
    local playerId    = Game.GetPlayerId()
    local playerIndex = Game.ConvertIntToPlayerindex(playerId)
    local playerChar  = Game.GetPlayerChar(playerIndex)
    if not playerChar then return end

    Game.SetPlayerControlForNetwork(playerIndex, true, false)
    Game.SetCharVisible(playerChar, true)
    Game.SetPlayerInvincible(playerIndex, false)
    Game.FreezeCharPosition(playerChar, false)
    Game.SetCharNeverTargetted(playerChar, false)
    Game.SetCharCollision(playerChar, true)
end
