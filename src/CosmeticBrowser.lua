-- A small, reusable list inside the hub; searching never creates hundreds of buttons.
local Browser = {}
Browser.__index = Browser
local function new(class, parent, properties)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end
function Browser.new(ui, equip, save)
    local self = setmetatable({items = {}, matches = {}, page = 1, rows = {}}, Browser)
    local c = ui:controlRow("Visuals", "cosmeticBrowser", "Cosmetic Browser", 355)
    self.control = c
    local function text(class, title, x, y, w, h)
        return new(class, c.row, {Text = title, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = Color3.fromRGB(12, 14, 23), BorderSizePixel = 0, TextSize = 11,
            TextColor3 = Color3.fromRGB(255, 211, 98), Font = Enum.Font.Gotham,
            TextTruncate = Enum.TextTruncate.AtEnd})
    end
    local function connect(signal, callback)
        ui.connections[#ui.connections + 1] = signal:Connect(callback)
    end
    self.search = text("TextBox", "", 9, 9, 296, 29)
    self.search.PlaceholderText, self.search.ClearTextOnFocus = "Search cosmetics...", false
    self.count = text("TextLabel", "Enable Cosmetic Unlocker above", 9, 40, 296, 20)
    for i = 1, 6 do
        local button = text("TextButton", "", 9, 64 + (i - 1) * 30, 296, 27)
        button.TextXAlignment = Enum.TextXAlignment.Left
        self.rows[i] = {button = button}
        connect(button.Activated, function()
            local item = self.rows[i].item
            if item then equip(item) end
        end)
    end
    self.previous = text("TextButton", "‹ Previous", 9, 247, 142, 25)
    self.next = text("TextButton", "Next ›", 163, 247, 142, 25)
    self.save = text("TextButton", "Request Game Save", 9, 278, 296, 26)
    c.status = text("TextLabel", "Enable Cosmetic Unlocker to browse.", 9, 309, 296, 40)
    c.status.TextWrapped, c.status.TextTruncate = true, Enum.TextTruncate.None
    connect(self.search:GetPropertyChangedSignal("Text"), function() self:filter() end)
    connect(self.previous.Activated, function() self.page = math.max(1, self.page - 1); self:render() end)
    connect(self.next.Activated, function() self.page = math.min(self:pages(), self.page + 1); self:render() end)
    connect(self.save.Activated, save)
    self:render()
    return self
end
function Browser:pages() return math.max(1, math.ceil(#self.matches / 6)) end
function Browser:setItems(items)
    self.items = items
    self:filter()
end
function Browser:filter()
    self.matches, self.page = {}, 1
    local query = self.search.Text:sub(1, 100):lower()
    for _, item in ipairs(self.items) do
        if item.name:lower():find(query, 1, true) then self.matches[#self.matches + 1] = item end
    end
    self:render()
end
function Browser:render()
    self.count.Text = #self.matches .. " cosmetics · page " .. self.page .. "/" .. self:pages()
    for i, row in ipairs(self.rows) do
        row.item = self.matches[(self.page - 1) * 6 + i]
        row.button.Visible = row.item ~= nil
        if row.item then
            row.button.Text = row.item.name .. " · " .. (row.item.equippable and "Equip" or "Game menu")
        end
    end
end
return Browser
