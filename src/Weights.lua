local Weights = {}

local ORDER = {
    {data = "HeavyWeights", label = "Heavy Weights", token = "heavy"},
    {data = "MediumWeights", label = "Medium Weights", token = "medium"},
    {data = "LightWeights", label = "Light Weights", token = "light"},
}

local function namedWeight(root, token)
    if not root then return nil end
    for _, item in ipairs(root:GetChildren()) do
        if item:IsA("Tool") then
            local name = item.Name:lower()
            if name:find("weight", 1, true) and name:find(token, 1, true) then return item end
        end
    end
end

-- Prefer the strongest owned weight. If the count values are unavailable, an
-- actual Tool in the backpack or character is enough to make a safe choice.
function Weights.equipBest(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then return false end
    local backpack, data = player:FindFirstChildOfClass("Backpack"), player:FindFirstChild("Data")
    for _, candidate in ipairs(ORDER) do
        local value = data and data:FindFirstChild(candidate.data)
        local owned = not value or tonumber(value.Value) == nil or value.Value > 0
        if owned then
            local equipped = namedWeight(character, candidate.token)
            if equipped then return true, candidate.label end
            local tool = namedWeight(backpack, candidate.token)
            if tool then
                humanoid:EquipTool(tool)
                return true, candidate.label
            end
        end
    end
    return false
end

return Weights
