-- Direct low-health recovery. This intentionally uses the live Humanoid rather
-- than Roblox's overlay controls, then lets the engine wait for RespawnLocal's
-- exact readiness signals before it attempts Start again.
local Respawn = {}

function Respawn.resetIfNeeded(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local readable, health = pcall(function() return humanoid.Health end)
    if not readable or health <= 0 or health > 2 then return false end
    local reset = pcall(function() humanoid.Health = 0 end)
    if not reset then return false end
    if character then pcall(character.BreakJoints, character) end
    return true
end

return Respawn
