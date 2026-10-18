-- Deterministic Roblox API double. Tests exercise our code, never a live game.
local M = {now = 0}
local function signal()
    local s = {listeners = {}}
    function s:Connect(fn)
        local c = {Connected = true, fn = fn}
        function c:Disconnect() self.Connected = false end
        self.listeners[#self.listeners + 1] = c
        return c
    end
    function s:Fire(...)
        for _, listener in ipairs(self.listeners) do if listener.Connected then listener.fn(...) end end
    end
    return s
end
local vec = {}
vec.__index = vec
function M.vector(x, y) return setmetatable({X = x or 0, Y = y or 0}, vec) end
function vec.__add(a, b) return M.vector(a.X + b.X, a.Y + b.Y) end
function vec.__sub(a, b) return M.vector(a.X - b.X, a.Y - b.Y) end
function vec.__div(a, b) return M.vector(a.X / b, a.Y / b) end
function vec:Lerp(b, alpha) return M.vector(self.X + (b.X - self.X) * alpha, self.Y + (b.Y - self.Y) * alpha) end
local methods, instance = {}, {}
local guiTypes = {Frame = true, ScrollingFrame = true, TextLabel = true, TextButton = true,
    TextBox = true, ImageLabel = true, ImageButton = true, CanvasGroup = true}
function instance:__index(key) return methods[key] or self.props[key] end
function instance:__newindex(key, value)
    if key == "Parent" then
        local old = self.props.Parent
        if old then
            for i, child in ipairs(old.children) do if child == self then table.remove(old.children, i); break end end
        end
        if value then value.children[#value.children + 1] = self end
    end
    self.props[key] = value
end
function methods:IsA(class)
    return self.ClassName == class or (class == "GuiObject" and guiTypes[self.ClassName] == true)
        or (class == "GuiButton" and (self.ClassName == "TextButton" or self.ClassName == "ImageButton"))
        or (class == "LayerCollector" and self.ClassName == "ScreenGui")
end
function methods:GetChildren() return self.children end
function methods:GetDescendants()
    if self.denyRead then error("Permission denied") end
    local result = {}
    local function collect(node)
        for _, child in ipairs(node.children) do result[#result + 1] = child; collect(child) end
    end
    collect(self)
    return result
end
function methods:FindFirstChild(name)
    for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name), "Missing mock child " .. name) end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
end
function methods:FindFirstAncestorWhichIsA(class)
    local parent = self.Parent
    while parent do if parent:IsA(class) then return parent end; parent = parent.Parent end
end
function methods:IsDescendantOf(ancestor)
    local parent = self.Parent
    while parent do if parent == ancestor then return true end; parent = parent.Parent end
    return false
end
function methods:Destroy()
    local children = {}
    for _, child in ipairs(self.children) do children[#children + 1] = child end
    for _, child in ipairs(children) do child:Destroy() end
    self.Parent = nil
end
function methods:GetGuiObjectsAtPosition(x, y)
    local result = {}
    for _, item in ipairs(self:GetDescendants()) do
        if item:IsA("GuiObject") and item.Visible then
            local p, s = item.AbsolutePosition, item.AbsoluteSize
            if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then result[#result + 1] = item end
        end
    end
    return result
end
function M.object(class, name, parent, props)
    local object = setmetatable({children = {}, props = {ClassName = class, Name = name or class,
        Visible = true, Enabled = true, AbsolutePosition = M.vector(0, 0), AbsoluteSize = M.vector(100, 30),
        ImageRectOffset = M.vector(0, 0), ImageRectSize = M.vector(0, 0), Image = "", Text = "",
        Activated = signal(), InputBegan = signal(), InputEnded = signal(), FocusLost = signal()}}, instance)
    for key, value in pairs(props or {}) do object[key] = value end
    object.Parent = parent
    return object
end
function M.install()
    M.realClock = os.clock
    os.clock = function() return M.now end
    Vector2 = {new = M.vector}
    Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
    ColorSequence = {new = function(a, b) return {a, b} end}
    UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
    UDim2 = {
        new = function(xs, xo, ys, yo) return {X = UDim.new(xs, xo), Y = UDim.new(ys, yo)} end,
        fromOffset = function(x, y) return {X = UDim.new(0, x), Y = UDim.new(0, y)} end,
        fromScale = function(x, y) return {X = UDim.new(x, 0), Y = UDim.new(y, 0)} end,
    }
    Enum = setmetatable({}, {__index = function(self, group)
        local values = setmetatable({}, {__index = function(t, key) local value = group .. "." .. key; rawset(t, key, value); return value end})
        rawset(self, group, values); return values
    end})
    Instance = {new = function(class) return M.object(class) end}
    M.reset()
end
function M.reset()
    M.now, M.pendingTasks, M.waitHook = 0, {}, nil
    M.root = M.object("DataModel", "game")
    game = M.root
    workspace = M.object("Workspace", "Workspace", game)
    workspace.CurrentCamera = {ViewportSize = M.vector(1280, 720)}
    M.player = M.object("Player", "LocalPlayer")
    M.playerGui = M.object("PlayerGui", "PlayerGui", M.player)
    M.character = M.object("Model", "Character", workspace)
    M.humanoid = M.object("Humanoid", "Humanoid", M.character, {Health = 100})
    M.player.Character = M.character
    M.coreGui = M.object("CoreGui", "CoreGui", game)
    M.hud = M.object("ScreenGui", "HUD", M.playerGui, {IgnoreGuiInset = true})
    M.uis = {InputBegan = signal(), InputChanged = signal(), InputEnded = signal(), cursor = M.vector(80, 200)}
    function M.uis:GetMouseLocation() return self.cursor end
    function M.uis:GetFocusedTextBox() return nil end
    M.runService = {Heartbeat = signal()}
    M.vim = {events = {}}
    function M.vim:SendMouseMoveEvent(x, y) M.uis.cursor = M.vector(x, y); self.events[#self.events + 1] = {"move", x, y} end
    function M.vim:SendMouseButtonEvent(x, y, button, down) self.events[#self.events + 1] = {"mouse", button, down, x, y} end
    function M.vim:SendKeyEvent(down, key) self.events[#self.events + 1] = {"key", key, down} end
    local encoded = {}
    M.http = {}
    function M.http:JSONEncode(value) encoded[#encoded + 1] = value; return "JSON" .. #encoded end
    function M.http:JSONDecode(value) return assert(encoded[tonumber(tostring(value):match("JSON(%d+)"))]) end
    M.services = {Players = {LocalPlayer = M.player}, CoreGui = M.coreGui, UserInputService = M.uis,
        RunService = M.runService, VirtualInputManager = M.vim, HttpService = M.http,
        GuiService = {GetGuiInset = function() return M.vector(0, 36) end}}
    game.GetService = function(_, name) return assert(M.services[name], "Missing mock service " .. name) end
    task = {wait = function(seconds)
        M.now = M.now + (seconds or 1 / 60)
        if M.waitHook then M.waitHook() end
    end, spawn = function(fn) M.pendingTasks[#M.pendingTasks + 1] = fn end}
    M.env = {}
    getgenv = function() return M.env end
end
function M.flush()
    local pending = M.pendingTasks
    M.pendingTasks = {}
    for _, fn in ipairs(pending) do fn() end
end
function M.tick(dt)
    M.now = M.now + (dt or 0.1)
    M.runService.Heartbeat:Fire(dt or 0.1)
    M.flush()
end
return M
