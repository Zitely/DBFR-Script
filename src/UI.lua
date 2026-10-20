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
function UI.new(parent, onClose, version)
    local self = setmetatable({features = {}, order = {}, connections = {}, minimized = false,
        pages = {}, pageOrder = {}, controls = {}}, UI)
    self.gui = new("ScreenGui", parent, {Name = "DBFR_SaiyanControl", ResetOnSpawn = false,
        IgnoreGuiInset = true, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    local camera = workspace.CurrentCamera
    local top = camera and math.max(12, math.min(155, camera.ViewportSize.Y - 500)) or 22
    self.window = new("Frame", self.gui, {Position = UDim2.fromOffset(22, top),
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
    self.versionLabel = label(self.window, "v" .. tostring(version or "?"), 0, 0, 70, 14, 9, C.muted, true)
    self.versionLabel.AnchorPoint = Vector2.new(1, 1)
    self.versionLabel.Position = UDim2.new(1, -13, 1, -8)
    self.versionLabel.TextXAlignment = Enum.TextXAlignment.Right
    self.tabs = new("Frame", self.window, {Position = UDim2.fromOffset(14, 66),
        Size = UDim2.fromOffset(322, 62), BackgroundTransparency = 1})
    self.help = label(self.window, "", 14, 429, 322, 30, 10, C.muted)
    self.help.TextWrapped = true
    self:addPage("Chamber")
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
        if self.dragSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
            self.dragSlider(input.Position.X)
        end
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - origin
            self.window.Position = UDim2.new(position.X.Scale, position.X.Offset + delta.X, position.Y.Scale, position.Y.Offset + delta.Y)
        end
    end)
    self.connections[#self.connections + 1] = uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false; self.dragSlider = nil end
    end)
    return self
end
function UI:setMinimized(minimized)
    self.minimized = minimized
    for _, feature in ipairs(self.order) do feature.row.Visible = not minimized end
    self.tabs.Visible, self.help.Visible = not minimized, not minimized
    for name, page in pairs(self.pages) do page.frame.Visible = not minimized and name == self.selectedPage end
    self.window.Size = UDim2.fromOffset(350, minimized and 65 or 480)
    self.minimizeButton.Text = minimized and "+" or "−"
end
function UI:addPage(name)
    if self.pages[name] then return self.pages[name] end
    local index = #self.pageOrder
    local tab = new("TextButton", self.tabs, {Position = UDim2.fromOffset(index % 3 * 109, math.floor(index / 3) * 31),
        Size = UDim2.fromOffset(104, 26), BackgroundColor3 = C.card, BorderSizePixel = 0,
        Text = name, TextColor3 = C.muted, TextSize = 11, Font = Enum.Font.GothamBold})
    round(tab, 6)
    local frame = new("ScrollingFrame", self.window, {Position = UDim2.fromOffset(14, 138),
        Size = UDim2.fromOffset(322, 284), CanvasSize = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.orange, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false})
    local page = {frame = frame, tab = tab, height = 0}
    self.pages[name], self.pageOrder[#self.pageOrder + 1] = page, name
    self.connections[#self.connections + 1] = tab.Activated:Connect(function() self:selectPage(name) end)
    if not self.selectedPage then self:selectPage(name) end
    return page
end
function UI:selectPage(name)
    if not self.pages[name] then return end
    self.selectedPage, self.dragSlider = name, nil
    for key, page in pairs(self.pages) do
        page.frame.Visible = not self.minimized and key == name
        page.tab.TextColor3 = key == name and C.bg or C.muted
        page.tab.BackgroundColor3 = key == name and C.orange or C.card
    end
    self.help.Text = name == "Chamber" and "Your existing training, recovery and overnight cycle."
        or name == "Travel" and "Manual travel. Turn Chamber off before using these controls."
        or "Optional tools start OFF. Conflicting tools pause while Chamber runs."
end
function UI:controlRow(pageName, id, title, height)
    local page = self:addPage(pageName)
    local row = new("Frame", page.frame, {Position = UDim2.fromOffset(0, page.height),
        Size = UDim2.fromOffset(314, height), BackgroundColor3 = C.card, BorderSizePixel = 0})
    round(row, 7)
    page.height = page.height + height + 7
    page.frame.CanvasSize = UDim2.fromOffset(0, page.height)
    local control = {row = row, title = title}
    self.controls[id] = control
    return control
end
function UI:addToggle(page, id, title, callback)
    local c = self:controlRow(page, id, title, 64)
    c.button = new("TextButton", c.row, {Size = UDim2.fromOffset(314, 35), BackgroundTransparency = 1,
        Text = title .. "  ·  OFF", TextColor3 = C.gold, TextSize = 11, Font = Enum.Font.GothamBold})
    c.status = label(c.row, "Off", 9, 35, 296, 26, 10, C.muted)
    c.status.TextWrapped = true
    self.connections[#self.connections + 1] = c.button.Activated:Connect(callback)
end
function UI:addButton(page, id, title, callback)
    self:addToggle(page, id, title, callback)
    self.controls[id].button.Text, self.controls[id].status.Text = title, "Click to use"
end
function UI:addSlider(page, id, title, minimum, maximum, value, callback)
    local c = self:controlRow(page, id, title, 69)
    c.label = label(c.row, "", 9, 2, 290, 26, 11, C.gold, true)
    c.track = new("Frame", c.row, {Position = UDim2.fromOffset(16, 33), Size = UDim2.fromOffset(282, 12),
        BackgroundColor3 = C.line, BorderSizePixel = 0, Active = true})
    round(c.track, 6)
    c.fill = new("Frame", c.track, {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.orange, BorderSizePixel = 0})
    round(c.fill, 6)
    c.status = label(c.row, "Drag to adjust", 9, 46, 296, 21, 9, C.muted)
    local function update(v, send)
        c.value = math.floor(math.max(minimum, math.min(maximum, v)) + 0.5)
        c.label.Text = title .. "  ·  " .. c.value
        c.fill.Size = UDim2.fromScale((c.value - minimum) / (maximum - minimum), 1)
        if send then callback(c.value) end
    end
    local function drag(x)
        local width = c.track.AbsoluteSize.X
        if width > 0 then update(minimum + (maximum - minimum) * (x - c.track.AbsolutePosition.X) / width, true) end
    end
    self.connections[#self.connections + 1] = c.track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then self.dragSlider = drag; drag(input.Position.X) end
    end)
    update(value, false)
end
function UI:setControlEnabled(id, enabled)
    local c = self.controls[id]
    if c and c.button then
        set(c.button, "Text", c.title .. (enabled and "  ·  ON" or "  ·  OFF"))
        set(c.button, "TextColor3", enabled and C.orange or C.gold)
    end
end
function UI:setControlStatus(id, text)
    local c = self.controls[id]
    if c and c.status then set(c.status, "Text", text) end
end
-- Each future feature gets one independent row and one toggle callback.
function UI:addFeature(id, title, onToggle)
    assert(not self.features[id], "Feature already registered: " .. id)
    local page = self.pages.Chamber
    local row = new("Frame", page.frame, {Position = UDim2.fromOffset(0, page.height),
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
    page.height = page.height + 130
    page.frame.CanvasSize = UDim2.fromOffset(0, page.height)
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
        set(self.scale, "Scale", math.max(0.5, math.min(1, (camera.ViewportSize.X - 30) / 350,
            (camera.ViewportSize.Y - 40) / 480)))
    end
end
function UI:destroy()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.gui:Destroy()
end
return UI
