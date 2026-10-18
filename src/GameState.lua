-- Read-only contract from the game's training controller supplied by the user.
-- Exact child lookups avoid repeated traversal of unrelated GUI objects.
local GameState = {}
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local function boolean(object)
    if object and object.ClassName == "BoolValue" then return object.Value end
end
function GameState.read(playerGui, health, visible, memo)
    local main = child(playerGui, "Main")
    if not main then return nil end
    local active = boolean(child(main, "Active"))
    local cooldown = boolean(child(main, "UICoolDown"))
    local frame = child(main, "Frame")
    local start = child(child(child(main, "Button Thing"), "Start"), "TextButton")
    if type(active) ~= "boolean" or type(cooldown) ~= "boolean" or not frame
        or not frame:IsA("GuiObject") or not start or not start:IsA("GuiButton") then return nil end
    local resting = boolean(child(child(child(playerGui, "Characters"), "Interactions"), "Resting"))
    local training = active and visible(frame, memo) and health ~= nil and health > 1
    local canStart = not active and not cooldown and resting == false and health ~= nil and health > 2
    local needsRecovery = health ~= nil and health > 0 and (health <= 1 or (not active and health <= 2))
    local blocked
    if health == nil or health <= 0 then blocked = "Waiting for your character to respawn"
    elseif needsRecovery then blocked = "Health too low to train; recovery needed"
    elseif active and not training then blocked = "Waiting for the training screen"
    elseif resting == nil then blocked = "Waiting for the game's resting state"
    elseif resting then blocked = "Waiting for resting to finish"
    elseif cooldown then blocked = "Waiting for the training cooldown" end
    return {training = training, active = active, canStart = canStart, needsRecovery = needsRecovery,
        attack = child(frame, "Attack"), block = child(frame, "Block"),
        counterA = child(frame, "CounterA"), counterB = child(frame, "CounterB"),
        blocked = blocked, start = not active and visible(start, memo) and start or nil}
end
return GameState
