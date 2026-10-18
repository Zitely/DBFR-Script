local Bindings = require("src.Bindings")
local Input = {}
Input.__index = Input
function Input.new(env)
    local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    local mouse = type(env.mouse1press) == "function" and type(env.mouse1release) == "function"
        and type(env.mouse2press) == "function" and type(env.mouse2release) == "function"
        and type(env.mousemoveabs) == "function"
    local keyboard = type(env.keypress) == "function" and type(env.keyrelease) == "function"
    return setmetatable({env = env, vim = ok and vim or nil, nativeMouse = mouse,
        nativeKeyboard = keyboard, held = {}, mouse = Vector2.new(0, 0)}, Input)
end
function Input:description()
    return (self.nativeMouse and "Executor mouse" or "VirtualInputManager mouse") .. " / "
        .. (self.nativeKeyboard and "executor keys" or "VirtualInputManager keys")
end
function Input:position()
    return game:GetService("UserInputService"):GetMouseLocation()
end
function Input:move(x, y)
    self.mouse = Vector2.new(x, y)
    if self.nativeMouse then self.env.mousemoveabs(x, y)
    elseif self.vim then self.vim:SendMouseMoveEvent(x, y, game)
    else error("Executor does not provide mouse movement") end
end
function Input:park(window)
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
    for _, point in ipairs({Vector2.new(size.X * 90 / 1280, size.Y * 435 / 720),
        Vector2.new(size.X * 0.5, size.Y * 0.5), Vector2.new(size.X * 0.9, size.Y * 0.5)}) do
        local p, s = window.AbsolutePosition, window.AbsoluteSize
        if not window.Visible or point.X < p.X or point.X > p.X + s.X
            or point.Y < p.Y or point.Y > p.Y + s.Y then
            self:move(point.X, point.Y)
            return
        end
    end
end
function Input:event(kind, down)
    if kind == "left" or kind == "right" then
        if self.nativeMouse then
            local fn = kind == "left" and (down and self.env.mouse1press or self.env.mouse1release)
                or (down and self.env.mouse2press or self.env.mouse2release)
            fn()
        elseif self.vim then
            local pos = self:position()
            self.vim:SendMouseButtonEvent(pos.X, pos.Y, kind == "left" and 0 or 1, down, game, 0)
        else error("Executor does not provide mouse input") end
    elseif kind == "q" or kind == "e" then
        if self.nativeKeyboard then
            (down and self.env.keypress or self.env.keyrelease)(kind == "q" and 0x51 or 0x45)
        elseif self.vim then self.vim:SendKeyEvent(down, kind == "q" and Enum.KeyCode.Q or Enum.KeyCode.E, false, game)
        else error("Executor does not provide key input") end
    else error("Unsupported input: " .. tostring(kind)) end
end
function Input:down(kind)
    self.held[kind] = true
    self:event(kind, true)
end
function Input:up(kind)
    self:event(kind, false)
    self.held[kind] = nil
end
function Input:releaseAll()
    local errors = {}
    for kind in pairs(self.held) do
        local ok, reason = pcall(self.up, self, kind)
        if not ok then errors[#errors + 1] = tostring(reason) end
    end
    if #errors > 0 then error(table.concat(errors, "; ")) end
end
local function waitUntil(duration, valid)
    local deadline = os.clock() + duration
    repeat
        if not valid() then error("Action cancelled") end
        task.wait()
    until os.clock() >= deadline
end
function Input:click(target, config, valid, park)
    if not Bindings.visible(target) then error("Target disappeared") end
    local validAction = valid
    valid = function() return validAction() and Bindings.visible(target) end
    local begin = self:position()
    local started, duration = os.clock(), config.approachMs / 1000
    repeat
        if not valid() or not target.Parent then error("Action cancelled") end
        local pos, size = target.AbsolutePosition, target.AbsoluteSize
        local goal = pos + size / 2
        -- AbsolutePosition is in the GUI's inset coordinate system.
        local root = target:FindFirstAncestorWhichIsA("ScreenGui")
        if root and not root.IgnoreGuiInset then goal = goal + game:GetService("GuiService"):GetGuiInset() end
        local t = math.min(1, (os.clock() - started) / duration)
        local smooth = t * t * (3 - 2 * t)
        local point = begin:Lerp(goal, smooth)
        self:move(math.floor(point.X + 0.5), math.floor(point.Y + 0.5))
        if t >= 1 then break end
        task.wait()
    until false
    waitUntil(config.hoverMs / 1000, valid)
    if not valid() then error("Target disappeared before the click") end
    valid = validAction -- A successful click may hide its target during the hold.
    local ok, reason = pcall(function()
        self:down("left")
        waitUntil(config.clickHoldMs / 1000, valid)
    end)
    local released, releaseReason = pcall(self.up, self, "left")
    if not released then error(releaseReason) end
    if not ok then error(reason) end
    if park then
        waitUntil(0.5, valid)
        local camera = workspace.CurrentCamera
        local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local from = self:position()
        for step = 1, 30 do
            if not valid() then error("Action cancelled") end
            local point = from:Lerp(Vector2.new(size.X * 90 / 1280, size.Y * 435 / 720), step / 30)
            self:move(point.X, point.Y)
            task.wait(1 / 30)
        end
    end
end
return Input
