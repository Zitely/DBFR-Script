local Timer = require("src.Timer")
local UI = {}
UI.__index = UI
local C = {
    bg = Color3.fromRGB(12, 14, 23), card = Color3.fromRGB(28, 32, 47),
    orange = Color3.fromRGB(255, 132, 35), gold = Color3.fromRGB(255, 211, 98),
    blue = Color3.fromRGB(94, 217, 255), text = Color3.fromRGB(242, 243, 249),
    muted = Color3.fromRGB(148, 157, 182), line = Color3.fromRGB(48, 53, 72),
}
local function new(class, parent, props)
    local object = Instance.new(class)
    for key, value in pairs(props or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function round(parent, radius)
    new("UICorner", parent, {CornerRadius = UDim.new(0, radius)})
end
local function label(parent, text, x, y, w, h, size, color, bold)
    return new("TextLabel", parent, {BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        Text = text, TextColor3 = color, TextSize = size,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center})
end
local function set(object, key, value)
    if object[key] ~= value then object[key] = value end
end
function UI.new(parent, onClose)
    local self = setmetatable({features = {}, order = {}, connections = {}, minimized = false}, UI)
    self.gui = new("ScreenGui", parent, {Name = "DBFR_SaiyanControl", ResetOnSpawn = false,
        IgnoreGuiInset = true, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    self.window = new("Frame", self.gui, {Position = UDim2.fromOffset(22, 155),
        Size = UDim2.fromOffset(350, 80), BackgroundColor3 = C.bg, BorderSizePixel = 0})
    round(self.window, 14)
    new("UIStroke", self.window, {Color = C.orange, Transparency = 0.3, Thickness = 1})
    self.scale = new("UIScale", self.window, {Scale = 1})
    local header = new("Frame", self.window, {Size = UDim2.fromOffset(260, 65), BackgroundTransparency = 1, Active = true})
    local ball = new("Frame", header, {Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = C.orange, BorderSizePixel = 0})
    round(ball, 34)
    new("UIGradient", ball, {Color = ColorSequence.new(C.gold, C.orange), Rotation = 65})
    label(ball, "★★★★", 2, 0, 30, 34, 9, Color3.fromRGB(165, 42, 23), true).TextXAlignment = Enum.TextXAlignment.Center
    label(header, "SAIYAN HUB", 62, 13, 195, 25, 19, C.text, true)
    label(header, "RIGHT SHIFT · SHOW / HIDE", 62, 38, 195, 15, 9, C.orange, true)
    local function windowButton(text, x, color)
        local button = new("TextButton", self.window, {Position = UDim2.fromOffset(x, 14),
            Size = UDim2.fromOffset(28, 28), BackgroundColor3 = C.card, BorderSizePixel = 0,
            Text = text, TextSize = 20, Font = Enum.Font.GothamBold, TextColor3 = color,
            AutoButtonColor = true})
        round(button, 7)
        return button
    end
    self.minimizeButton = windowButton("−", 273, C.gold)
    self.closeButton = windowButton("×", 307, C.orange)
    self.connections[#self.connections + 1] = self.minimizeButton.Activated:Connect(function()
        self:setMinimized(not self.minimized)
    end)
    self.connections[#self.connections + 1] = self.closeButton.Activated:Connect(onClose)
    local uis = game:GetService("UserInputService")
    self.connections[#self.connections + 1] = uis.InputBegan:Connect(function(input, processed)
        if processed or uis:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            self.window.Visible = not self.window.Visible
            if self.window.Visible then self:setMinimized(false) end
        end
    end)
    local dragging, origin, position
    self.connections[#self.connections + 1] = header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, origin, position = true, input.Position, self.window.Position
        end
    end)
    self.connections[#self.connections + 1] = uis.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - origin
            self.window.Position = UDim2.new(position.X.Scale, position.X.Offset + delta.X, position.Y.Scale, position.Y.Offset + delta.Y)
        end
    end)
    self.connections[#self.connections + 1] = uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    return self
end
function UI:setMinimized(minimized)
    self.minimized = minimized
    for _, feature in ipairs(self.order) do feature.row.Visible = not minimized end
    self.window.Size = UDim2.fromOffset(350, minimized and 65 or (76 + #self.order * 130))
    self.minimizeButton.Text = minimized and "+" or "−"
end
-- Each future feature gets one independent row and one toggle callback.
function UI:addFeature(id, title, onToggle)
    assert(not self.features[id], "Feature already registered: " .. id)
    local row = new("Frame", self.window, {Position = UDim2.fromOffset(14, 68 + #self.order * 130),
        Size = UDim2.fromOffset(322, 122), BackgroundTransparency = 1})
    local button = new("TextButton", row, {Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(322, 43),
        Text = title .. "  ·  OFF", TextSize = 13, Font = Enum.Font.GothamBold,
        TextColor3 = C.gold, BackgroundColor3 = C.card, BorderSizePixel = 0, AutoButtonColor = true})
    round(button, 9)
    local state = label(row, "OFF", 0, 50, 98, 18, 10, C.orange, true)
    local timer = label(row, "HTC  --:--:--", 106, 50, 216, 18, 11, C.blue, true)
    timer.TextXAlignment = Enum.TextXAlignment.Right
    local status = label(row, "Click to start Chamber automation.", 0, 73, 322, 42, 12, C.muted)
    status.TextWrapped = true
    local feature = {id = id, title = title, row = row, button = button, state = state, status = status, timer = timer}
    self.features[id], self.order[#self.order + 1] = feature, feature
    self.connections[#self.connections + 1] = button.Activated:Connect(onToggle)
    self:setMinimized(self.minimized)
    return feature
end
function UI:log(message) self.lastMessage = tostring(message) end
function UI:updateFeature(id, engine, rhythm, now)
    local feature = assert(self.features[id], "Unknown feature: " .. id)
    set(feature.button, "Text", feature.title .. (engine.active and "  ·  ON" or "  ·  OFF"))
    set(feature.button, "BackgroundColor3", engine.active and C.orange or C.card)
    set(feature.button, "TextColor3", engine.active and C.bg or C.gold)
    set(feature.state, "Text", engine.state:upper())
    set(feature.status, "Text", engine.status)
    set(feature.timer, "Text", "HTC  " .. Timer.format(engine.timer:remaining(now)))
    local camera = workspace.CurrentCamera
    if camera then
        set(self.scale, "Scale", math.max(0.5, math.min(1, (camera.ViewportSize.X - 30) / 350)))
    end
end
function UI:destroy()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.gui:Destroy()
end
return UI
