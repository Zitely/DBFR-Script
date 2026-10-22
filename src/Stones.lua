-- User-supplied quest requests and local display overrides, owned by hub toggles.
local Stones = {}
local dailyQuests = {"OkraDaily", "MenatoDaily", "JuneDaily", "BrolyDaily", "EijiDaily", "ElHermanoDaily",
    "HitDaily", "CopyVegetaDaily", "CopyGokuDaily", "GoldenCoolerDaily", "MaskedSaiyanDaily", "ChipDaily"}
function Stones.validateText(value, format)
    if type(value) ~= "string" and type(value) ~= "number" then return nil, "Enter a value" end
    local text = tostring(value):match("^%s*(.-)%s*$")
    if format == "quest" then
        if #text == 0 or #text > 100 or text:find("%c") then return nil, "Enter a quest name (1–100 characters)" end
        return text
    end
    local number = tonumber(text)
    if not number or number ~= number or number < 0 or number > 2147483647 or number % 1 ~= 0 then
        return nil, "Use a whole number from 0 to 2147483647"
    end
    return string.format("%.0f", number)
end
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local function rewardsFor(quest)
    local panel = quest:FindFirstChild("Quest", true)
    local controller = child(child(panel, "Main"), "LocalScript")
    local rewards = child(controller, "Rewards")
    assert(rewards, "Quest reward controls were not found")
    for _, name in ipairs({"DragonStones", "Zeni", "SuperDragon"}) do
        local value = child(rewards, name)
        assert(value and (value:IsA("IntValue") or value:IsA("NumberValue")), "Missing " .. name .. " reward")
    end
    local completed = child(controller, "QuestCompleted")
    assert(completed and completed:IsA("BoolValue"), "Missing QuestCompleted flag")
    return rewards, completed
end
function Stones.quest(c, hub)
    if c.done then return end
    local settings = hub.values
    local storage = game:GetService("ReplicatedStorage")
    local remote = child(child(storage, "Remotes"), "QuestOne")
    assert(remote and remote:IsA("RemoteEvent"), "Missing QuestOne RemoteEvent")
    local template = child(child(storage, "Quests"), settings.questName)
    assert(template, "Quest not found: " .. settings.questName)
    rewardsFor(template)
    local gui = hub.player:FindFirstChildOfClass("PlayerGui")
    assert(gui, "Waiting for PlayerGui")
    local clone = template:Clone()
    c.scope:own(clone)
    local rewards, completed = rewardsFor(clone)
    child(rewards, "DragonStones").Value = tonumber(settings.questDragonStones)
    child(rewards, "Zeni").Value = tonumber(settings.questZeni)
    child(rewards, "SuperDragon").Value = tonumber(settings.questSuperStones)
    completed.Value = true
    -- Configure before parenting, so a cloned LocalScript sees the entered values.
    clone.Parent = gui
    c.done = true -- A partial send must not automatically repeat the request.
    local ok, reason = pcall(function()
        local requests = {{"Complete", settings.questName}, {settings.questName, "Complete"}, {settings.questName}}
        for _, args in ipairs(requests) do
            if not hub:running("dragonStones") or hub.contexts.dragonStones ~= c then return end
            remote:FireServer((table.unpack or unpack)(args))
        end
    end)
    if hub:running("dragonStones") and hub.contexts.dragonStones == c then
        hub:status("dragonStones", ok and "Requests sent once; server determines rewards"
            or "Request failed; toggle off/on to retry: " .. tostring(reason))
    end
end
local function override(c, object, key, value, seen)
    seen[object] = true
    local properties = c.scope.properties[object]
    local entry = properties and properties[key]
    -- Keep the latest game-provided value for restoration when the lock is off.
    if entry and object[key] ~= entry.last then entry.original = object[key] end
    if object[key] ~= value then c.scope:set(object, key, value) end
end
local function textObject(object)
    return object and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
end
function Stones.super(c, hub)
    local stones = child(child(hub.player, "Data"), "SuperDragonStones")
    assert(stones and (stones:IsA("IntValue") or stones:IsA("NumberValue")), "SuperDragonStones value not found")
    local desired, seen = tonumber(hub.values.superStoneTarget), {}
    if c.stones ~= stones or c.target ~= desired or stones.Value < desired then
        override(c, stones, "Value", desired, seen)
    else seen[stones] = true end
    c.stones, c.target = stones, desired
    local gui = hub.player:FindFirstChildOfClass("PlayerGui")
    local shop = child(child(child(child(gui, "PlaceHolder"), "StatsFrame"), "Info"), "DragonStoneShop")
    local amount, currency = child(shop, "AmountText"), child(child(shop, "SDSCurrency"), "Amount")
    if textObject(amount) then override(c, amount, "Text", "Stones: " .. tostring(stones.Value), seen) end
    if textObject(currency) then override(c, currency, "Text", tostring(stones.Value), seen) end
    for object in pairs(c.scope.properties) do if not seen[object] then c.scope:restore(object) end end
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("GetQuest")
    c.dailyIndex = c.dailyIndex or 1
    if c.dailyIndex <= #dailyQuests then
        if not remote or not remote:IsA("RemoteEvent") then
            hub:status("superStones", "Local value locked; GetQuest unavailable")
            return
        end
        local quest = dailyQuests[c.dailyIndex]
        c.dailyIndex = c.dailyIndex + 1
        local ok, reason = pcall(remote.FireServer, remote, quest)
        if not ok then c.dailyError = tostring(reason) end
    end
    if hub:running("superStones") and hub.contexts.superStones == c then
        hub:status("superStones", c.dailyError and "Local value locked; a daily request failed"
            or "Local value locked; daily requests " .. tostring(c.dailyIndex - 1) .. "/12 sent")
    end
end
return Stones
