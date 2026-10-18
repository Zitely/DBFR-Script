local Timer = require("src.Timer")
local UI = {}
UI.__index = UI
local C = {
    bg = Color3.fromRGB(12, 14, 23), panel = Color3.fromRGB(21, 24, 37),
    card = Color3.fromRGB(28, 32, 47), line = Color3.fromRGB(48, 53, 72),
    orange = Color3.fromRGB(255, 132, 35), gold = Color3.fromRGB(255, 211, 98),
    blue = Color3.fromRGB(94, 217, 255), text = Color3.fromRGB(242, 243, 249),
    muted = Color3.fromRGB(148, 157, 182), red = Color3.fromRGB(255, 94, 105),
}
local function new(class, parent, props)
    local object = Instance.new(class)
    for key, value in pairs(props or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function corner(parent, radius) new("UICorner", parent, {CornerRadius = UDim.new(0, radius or 12)}) end
local function stroke(parent, color, transparency)
    return new("UIStroke", parent, {Color = color or C.line, Transparency = transparency or 0, Thickness = 1})
end
local function label(parent, text, x, y, w, h, size, color, bold)
    return new("TextLabel", parent, {BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h), Text = text, TextColor3 = color or C.text, TextSize = size or 14,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd})
end
local function card(parent, x, y, w, h, color)
    local object = new("Frame", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = color or C.card, BorderSizePixel = 0})
    corner(object); stroke(object)
    return object
end
local function button(parent, text, x, y, w, h, callback, accent)
    local object = new("TextButton", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
        Text = text, TextColor3 = accent and C.bg or C.text, TextSize = 13, Font = Enum.Font.GothamBold,
        BackgroundColor3 = accent and C.orange or C.card, BorderSizePixel = 0, AutoButtonColor = true})
    corner(object, 9)
    if not accent then stroke(object) end
    object.Activated:Connect(callback)
    return object
end
local function ball(parent, x, y, diameter, stars)
    local orb = new("Frame", parent, {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(diameter, diameter),
        BackgroundColor3 = C.orange, BorderSizePixel = 0})
    corner(orb, diameter)
    new("UIGradient", orb, {Color = ColorSequence.new(C.gold, C.orange), Rotation = 65})
    stroke(orb, C.gold, 0.3)
    local text = label(orb, string.rep("★", stars), 0, 0, diameter, diameter, stars > 3 and 8 or 11, Color3.fromRGB(165, 42, 23), true)
    text.TextXAlignment, text.TextWrapped = Enum.TextXAlignment.Center, true
    return orb
end

function UI.new(parent, config, callbacks)
    local self = setmetatable({callbacks = callbacks, config = config, connections = {}, pages = {}, nav = {}, logs = {}}, UI)
    local gui = new("ScreenGui", parent, {Name = "DBFR_SaiyanControl", ResetOnSpawn = false,
        IgnoreGuiInset = true, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    self.gui = gui
    local window = new("Frame", gui, {Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 548), BackgroundColor3 = C.bg, BorderSizePixel = 0})
    self.window = window
    corner(window, 18); stroke(window, C.orange, 0.35)
    local scale = new("UIScale", window, {Scale = 1})
    self.scale = scale
    local glow = new("Frame", window, {Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 0, 3),
        BackgroundColor3 = C.orange, BorderSizePixel = 0})
    new("UIGradient", glow, {Color = ColorSequence.new(C.orange, C.gold), Rotation = 0})
    local header = new("Frame", window, {Size = UDim2.new(1, 0, 0, 85), BackgroundTransparency = 1, Active = true})
    ball(header, 22, 20, 44, 4)
    label(header, "CHAMBER", 80, 17, 220, 28, 24, C.text, true)
    label(header, "S A I Y A N   C O N T R O L", 81, 48, 260, 18, 10, C.orange, true)
    label(header, "LUA  /  1.0", 560, 26, 88, 22, 10, C.muted, true)
    button(header, "—", 658, 23, 34, 32, function() self:setVisible(false) end)
    button(header, "×", 702, 23, 34, 32, function() callbacks.close() end)
    new("Frame", window, {Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0})
    local sidebar = new("Frame", window, {Position = UDim2.fromOffset(20, 104), Size = UDim2.fromOffset(146, 388), BackgroundTransparency = 1})
    local tabs = {{"dashboard", "01  TRAINING"}, {"calibration", "02  CALIBRATION"}, {"settings", "03  SETTINGS"}, {"activity", "04  ACTIVITY"}}
    for i, tab in ipairs(tabs) do
        local key = tab[1]
        self.nav[key] = button(sidebar, tab[2], 0, (i - 1) * 48, 146, 38, function() self:showPage(key) end)
    end
    label(sidebar, "LIMITS ARE MADE\nTO BE BROKEN.", 3, 228, 140, 55, 15, C.gold, true).TextWrapped = true
    for i = 1, 7 do ball(sidebar, ((i - 1) % 4) * 34 + 4, i <= 4 and 304 or 340, 25, i) end
    label(sidebar, "F6  Run / pause\nF7  Unload\nRight Shift  Show / hide", 2, 379, 145, 57, 10, C.muted).TextWrapped = true
    local function page(name)
        local object = new("Frame", window, {Name = name, Position = UDim2.fromOffset(188, 104),
            Size = UDim2.fromOffset(548, 418), BackgroundTransparency = 1, Visible = false})
        self.pages[name] = object
        return object
    end
    local dashboard = page("dashboard")
    local hero = card(dashboard, 0, 0, 548, 98, C.panel)
    label(hero, "BREAK YOUR LIMITS.", 20, 15, 450, 30, 25, C.text, true)
    label(hero, "Your Hyperbolic Time Chamber training companion.", 20, 53, 505, 24, 12, C.muted)
    local aura = new("Frame", hero, {Position = UDim2.new(1, -7, 0, 17), Size = UDim2.fromOffset(3, 62), BackgroundColor3 = C.orange, BorderSizePixel = 0})
    corner(aura, 3)
    local status = card(dashboard, 0, 112, 548, 84)
    self.stateLabel = label(status, "STANDBY", 18, 12, 510, 18, 11, C.orange, true)
    self.statusLabel = label(status, "Ready when you are", 18, 36, 510, 33, 14, C.text, true)
    self.statusLabel.TextWrapped, self.statusLabel.TextTruncate = true, Enum.TextTruncate.None
    local timerCard = card(dashboard, 0, 210, 264, 104)
    label(timerCard, "HTC  /  TIME REMAINING", 16, 12, 230, 18, 10, C.muted, true)
    self.timerLabel = label(timerCard, "--:--:--", 16, 34, 230, 40, 33, C.blue, true)
    self.afkLabel = label(timerCard, "AFK threshold: 35 min", 16, 79, 230, 16, 10, C.muted)
    local metrics = card(dashboard, 278, 210, 270, 104)
    label(metrics, "TRAINING RECORD", 16, 12, 236, 18, 10, C.muted, true)
    self.inputsLabel = label(metrics, "0", 16, 35, 100, 30, 27, C.gold, true)
    label(metrics, "INPUTS SENT", 16, 75, 110, 14, 9, C.muted, true)
    self.cyclesLabel = label(metrics, "0", 151, 35, 98, 30, 27, C.text, true)
    label(metrics, "TRAINING RUNS", 151, 75, 105, 14, 9, C.muted, true)
    self.runButton = button(dashboard, "▶  POWER UP", 0, 331, 350, 48, callbacks.toggle, true)
    button(dashboard, "BIND CONTROLS", 364, 331, 184, 48, function() self:showPage("calibration") end)
    self.backendLabel = label(dashboard, "Checking executor input support…", 0, 391, 548, 20, 10, C.muted)

    local calibration = page("calibration")
    label(calibration, "TUNE YOUR SENSES", 0, 0, 548, 28, 23, C.text, true)
    local help = label(calibration, "Bind, then hover the game control. It is captured after 3 seconds.\nAutomation pauses while you calibrate. Prompts use their image or text.", 0, 36, 548, 46, 12, C.muted)
    help.TextWrapped, help.TextTruncate = true, Enum.TextTruncate.None
    local scroll = new("ScrollingFrame", calibration, {Position = UDim2.fromOffset(0, 94), Size = UDim2.fromOffset(548, 322),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.orange,
        CanvasSize = UDim2.fromOffset(0, 16 * 47)})
    self.bindingLabels = {}
    local roles = {{"start", "Training Start"}, {"menu", "Lines menu"}, {"respawn", "Menu → Respawn"},
        {"confirm", "Confirm Respawn"}, {"reconnect", "Reconnect"}, {"timer", "Bottom-right HTC timer"},
        {"left", "Left mouse prompt"}, {"right", "Right mouse prompt"}, {"q", "Q prompt"}, {"e", "E prompt"},
        {"targetTop", "Top hit ring"}, {"targetBottom", "Bottom hit ring"},
        {"counterTop", "Top challenge number"}, {"counterBottom", "Bottom challenge number"}}
    scroll.CanvasSize = UDim2.fromOffset(0, #roles * 47)
    for i, role in ipairs(roles) do
        local key, title = role[1], role[2]
        local row = card(scroll, 0, (i - 1) * 47, 536, 40)
        label(row, title, 12, 0, 244, 40, 12, C.text)
        self.bindingLabels[key] = label(row, "AUTO", 265, 0, 74, 40, 10, C.muted, true)
        button(row, "BIND", 353, 6, 75, 28, function() callbacks.bind(key) end, true)
        button(row, "RESET", 440, 6, 83, 28, function() callbacks.clearBinding(key) end)
    end

    local settings = page("settings")
    label(settings, "MAKE IT YOURS", 0, 0, 548, 28, 23, C.text, true)
    label(settings, "Changes save locally when the executor supports file storage.", 0, 35, 548, 22, 12, C.muted)
    local options = new("ScrollingFrame", settings, {Position = UDim2.fromOffset(0, 71), Size = UDim2.fromOffset(548, 345),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.orange,
        CanvasSize = UDim2.fromOffset(0, 13 * 49)})
    self.settingsButtons = {}
    local settingsList = {{"autoStart", "Press Start automatically"}, {"autoRecover", "Recover through the lines menu"},
        {"autoReconnect", "Reconnect whenever the button appears"}, {"resumeAfterTeleport", "Reload after teleport (executor support needed)"},
        {"dryRun", "Preview only — no inputs"}, {"afkMinutes", "AFK at minutes remaining (0 = off)"},
        {"timingOffsetMs", "Rhythm timing offset (ms)"}, {"spamHoldMs", "Spam button hold (ms)"},
        {"spamGapMs", "Spam release gap (ms)"}, {"lostSeconds", "Missing training before recovery (seconds)"},
        {"respawnWait", "Respawn minimum wait (seconds)"}, {"approachMs", "Smooth button approach (ms)"},
        {"reconnectCooldown", "Reconnect retry cooldown (seconds)"}}
    for i, setting in ipairs(settingsList) do
        local key = setting[1]
        local row = card(options, 0, (i - 1) * 49, 536, 42)
        label(row, setting[2], 12, 0, 403, 42, 11, C.text)
        if type(config[key]) == "boolean" then
            local toggle
            toggle = button(row, config[key] and "ON" or "OFF", 432, 7, 90, 28, function()
                callbacks.setting(key, not config[key])
                toggle.Text, toggle.BackgroundColor3 = config[key] and "ON" or "OFF", config[key] and C.orange or C.card
                toggle.TextColor3 = config[key] and C.bg or C.text
            end, config[key])
            self.settingsButtons[key] = toggle
        else
            local input = new("TextBox", row, {Position = UDim2.fromOffset(432, 7), Size = UDim2.fromOffset(90, 28),
                BackgroundColor3 = C.bg, BorderSizePixel = 0, TextColor3 = C.gold, Font = Enum.Font.GothamBold,
                TextSize = 13, Text = tostring(config[key]), ClearTextOnFocus = false})
            corner(input, 7); stroke(input)
            input.FocusLost:Connect(function()
                local value = tonumber(input.Text)
                if value then callbacks.setting(key, value) end
                input.Text = tostring(config[key])
            end)
        end
    end
    local activity = page("activity")
    label(activity, "THE TRAINING LOG", 0, 0, 548, 28, 23, C.text, true)
    label(activity, "Actions, detections, and anything that needs your attention.", 0, 35, 548, 22, 12, C.muted)
    local logCard = card(activity, 0, 74, 548, 342)
    local logScroll = new("ScrollingFrame", logCard, {Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(520, 318),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.orange,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y})
    self.logText = label(logScroll, "", 0, 0, 504, 0, 12, C.muted)
    self.logText.AutomaticSize, self.logText.TextWrapped = Enum.AutomaticSize.Y, true
    self.logText.TextTruncate, self.logText.TextYAlignment = Enum.TextTruncate.None, Enum.TextYAlignment.Top
    self.pill = button(gui, "★  CHAMBER  /  STANDBY", 22, 155, 250, 36, function()
        callbacks.show()
        self:setVisible(true)
    end)
    self.pill.Visible = false
    self.toast = card(gui, 0, 0, 530, 46, C.panel)
    self.toast.AnchorPoint, self.toast.Position, self.toast.Visible = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 46), false
    self.toastLabel = label(self.toast, "", 15, 0, 500, 46, 13, C.gold, true)
    self.toastLabel.TextXAlignment = Enum.TextXAlignment.Center
    local uis = game:GetService("UserInputService")
    local dragging, origin, position
    self.connections[#self.connections + 1] = header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, origin, position = true, input.Position, window.Position
        end
    end)
    self.connections[#self.connections + 1] = uis.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - origin
            window.Position = UDim2.new(position.X.Scale, position.X.Offset + delta.X, position.Y.Scale, position.Y.Offset + delta.Y)
        end
    end)
    self.connections[#self.connections + 1] = uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    self:showPage("dashboard")
    return self
end
function UI:showPage(name)
    for key, page in pairs(self.pages) do
        page.Visible = name == key
        self.nav[key].BackgroundColor3 = name == key and C.orange or C.card
        self.nav[key].TextColor3 = name == key and C.bg or C.muted
    end
end
function UI:setVisible(visible)
    self.window.Visible, self.pill.Visible = visible, not visible
end
function UI:notify(message, seconds)
    self.toastLabel.Text, self.toast.Visible = message, true
    self.toastUntil = os.clock() + (seconds or 3)
end
function UI:log(message)
    table.insert(self.logs, 1, os.date("%H:%M:%S") .. "  " .. tostring(message))
    while #self.logs > 60 do table.remove(self.logs) end
    self.logText.Text = table.concat(self.logs, "\n\n")
end
function UI:update(engine, rhythm, bindings, backend, now)
    self.stateLabel.Text = engine.state:upper()
    self.statusLabel.Text = engine.status
    self.timerLabel.Text = Timer.format(engine.timer:remaining(now))
    self.afkLabel.Text = "AFK threshold: " .. tostring(self.config.afkMinutes) .. " min"
    self.inputsLabel.Text, self.cyclesLabel.Text = tostring(rhythm.attempts), tostring(engine.sessions)
    self.runButton.Text = engine.active and "Ⅱ  PAUSE TRAINING" or "▶  POWER UP"
    self.pill.Text = "★  CHAMBER  /  " .. engine.state:upper()
    self.backendLabel.Text = backend
    for role, item in pairs(self.bindingLabels) do
        item.Text, item.TextColor3 = bindings.saved[role] and "BOUND" or "AUTO", bindings.saved[role] and C.blue or C.muted
    end
    if self.toastUntil and now >= self.toastUntil then self.toast.Visible = false end
    local camera = workspace.CurrentCamera
    if camera then self.scale.Scale = math.min(1, (camera.ViewportSize.X - 24) / 760, (camera.ViewportSize.Y - 24) / 548) end
end
function UI:destroy()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    self.gui:Destroy()
end
return UI
