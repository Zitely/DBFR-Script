local Timer = require("src.Timer")
local Bindings = {}
Bindings.__index = Bindings
local kinds = {left = true, right = true, q = true, e = true}
local function clean(value)
    return tostring(value or ""):lower():gsub("<[^>]*>", ""):gsub("[^%w]", "")
end
local function textOf(object)
    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then return object.Text end
    return ""
end
local function visible(object)
    if not object or not object.Parent or not object:IsA("GuiObject") then return false end
    if object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then return false end
    local parent = object
    while parent and parent ~= game do
        if parent:IsA("GuiObject") and (not parent.Visible or (parent:IsA("CanvasGroup") and parent.GroupTransparency >= 1)) then return false end
        if parent:IsA("LayerCollector") and not parent.Enabled then return false end
        parent = parent.Parent
    end
    return true
end
local function buttonOf(object)
    local current = object
    while current and not current:IsA("LayerCollector") do
        if current:IsA("GuiButton") then return current end
        current = current.Parent
    end
    return nil
end
local function imageOf(object)
    if object:IsA("ImageLabel") or object:IsA("ImageButton") then
        return {image = object.Image, x = object.ImageRectOffset.X, y = object.ImageRectOffset.Y,
            w = object.ImageRectSize.X, h = object.ImageRectSize.Y}
    end
end
local function matchesImage(object, signature)
    if type(signature) ~= "table" or not signature.image or signature.image == "" then return false end
    local actual = imageOf(object)
    return actual and actual.image == signature.image and actual.x == signature.x and actual.y == signature.y
        and actual.w == signature.w and actual.h == signature.h
end

function Bindings.new(player, saved, ownGui)
    return setmetatable({player = player, saved = type(saved) == "table" and saved or {},
        ownGui = ownGui, roots = {}, objects = {}, nextScan = 0, errors = {}, votes = {}, lastKinds = {}}, Bindings)
end
function Bindings:refresh(now)
    if now < self.nextScan then return end
    self.nextScan, self.objects, self.roots, self.errors = now + 0.75, {}, {}, {}
    local playerGui = self.player:FindFirstChildOfClass("PlayerGui")
    if playerGui then self.roots.PlayerGui = playerGui end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok then self.roots.CoreGui = core end
    for name, root in pairs(self.roots) do
        local success, descendants = pcall(function() return root:GetDescendants() end)
        if success then
            for _, object in ipairs(descendants) do
                if object:IsA("GuiObject") and not (self.ownGui and object:IsDescendantOf(self.ownGui)) then
                    self.objects[#self.objects + 1] = object
                end
            end
        else self.errors[#self.errors + 1] = name .. " cannot be read by this executor" end
    end
end
function Bindings:path(object)
    local pieces, current = {}, object
    while current do
        for name, root in pairs(self.roots) do
            if current == root then return {root = name, path = pieces} end
        end
        table.insert(pieces, 1, current.Name)
        current = current.Parent
    end
    return nil
end
function Bindings:resolve(binding)
    if type(binding) ~= "table" or type(binding.path) ~= "table" then return nil end
    local current = self.roots[binding.root]
    for _, name in ipairs(binding.path) do
        if not current or type(name) ~= "string" then return nil end
        local found
        for _, child in ipairs(current:GetChildren()) do
            if child.Name == name then
                if found then return nil end -- Ambiguous names require a new binding.
                found = child
            end
        end
        current = found
    end
    return current
end
function Bindings:bind(role, object)
    if not object or not object:IsA("GuiObject") then return false, "Choose a visible UI object" end
    if kinds[role] then
        local signature = imageOf(object)
        if signature and signature.image ~= "" then
            self.saved[role] = {signature = signature}
        else
            local label = clean(textOf(object))
            if label == "" then return false, "Choose the prompt's image or text label" end
            self.saved[role] = {text = label}
        end
    else
        local selected = (role == "start" or role == "menu" or role == "respawn" or role == "confirm" or role == "reconnect")
            and (buttonOf(object) or object) or object
        local path = self:path(selected)
        if not path then return false, "Object must belong to PlayerGui or CoreGui" end
        self.saved[role] = path
    end
    return true, "Bound " .. role .. " to " .. object.Name
end
function Bindings:pick(x, y)
    local found, area = nil, math.huge
    for _, root in pairs(self.roots) do
        local ok, objects = pcall(function() return root:GetGuiObjectsAtPosition(x, y) end)
        if ok then
            for _, object in ipairs(objects) do
                if visible(object) and not (self.ownGui and object:IsDescendantOf(self.ownGui)) then
                    local size = object.AbsoluteSize
                    if size.X * size.Y < area then found, area = object, size.X * size.Y end
                end
            end
        end
    end
    return found
end
function Bindings:kind(object)
    local text, name = clean(textOf(object)), clean(object.Name)
    for _, kind in ipairs({"left", "right", "q", "e"}) do
        local bound = self.saved[kind]
        if type(bound) == "table" and (matchesImage(object, bound.signature) or (bound.text and bound.text ~= "" and text == bound.text)) then
            return kind
        end
    end
    local aliases = {q = "q", e = "e", lmb = "left", rmb = "right", mouse1 = "left", mouse2 = "right",
        leftclick = "left", rightclick = "right", leftmouse = "left", rightmouse = "right"}
    return aliases[text] or aliases[name]
end
function Bindings:snapshot(now)
    self:refresh(now)
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local sx, sy = 1280 / math.max(1, viewport.X), 720 / math.max(1, viewport.Y)
    local controls, notes, counters, seenKinds, respawns, nearest = {}, {}, {}, {}, {}, {}
    for _, role in ipairs({"start", "menu", "respawn", "confirm", "reconnect", "timer", "targetTop", "targetBottom", "counterTop", "counterBottom"}) do
        local object = self:resolve(self.saved[role])
        if visible(object) then controls[role] = object end
    end
    for _, object in ipairs(self.objects) do
        if visible(object) then
            local label, name = clean(textOf(object)), clean(object.Name)
            local button = buttonOf(object)
            if button then
                if label == "start" and not controls.start then controls.start = button end
                if label == "reconnect" and not controls.reconnect then controls.reconnect = button end
                if (label == "menu" or name == "menubutton" or name == "hamburgerbutton") and not controls.menu then controls.menu = button end
                if label == "respawn" then respawns[button] = true end
            end
            local pos, size = object.AbsolutePosition, object.AbsoluteSize
            local x, y = (pos.X + size.X / 2) * sx, (pos.Y + size.Y / 2) * sy
            if not controls.timer and x > 1120 and y > 650 and Timer.parse(textOf(object)) then controls.timer = object end
            if x > 280 and x < 1085 and y > 495 and y < 655 then
                local kind = self:kind(object)
                if kind then
                    seenKinds[kind] = true
                    local lane = (kind == "left" or kind == "right") and "top" or "bottom"
                    local expectedY = lane == "top" and 540 or 612
                    if math.abs(y - expectedY) < 30 then
                        local target = controls[lane == "top" and "targetTop" or "targetBottom"]
                        local targetX = target and (target.AbsolutePosition.X + target.AbsoluteSize.X / 2) * sx or 1025
                        notes[#notes + 1] = {id = object, kind = kind, x = x, target = targetX}
                        if x <= targetX + 30 and (not nearest[lane] or x > nearest[lane].x) then
                            nearest[lane] = {kind = kind, x = x}
                        end
                    end
                end
                local count = tonumber(textOf(object):match("^%s*(%d+)%s*$"))
                if count and count <= 25 and x > 960 then
                    counters[y < 575 and "top" or "bottom"] = count
                end
            end
        end
    end
    -- Default controls use the layout from the original clips; explicit bindings win.
    for button in pairs(respawns) do
        local pos, size = button.AbsolutePosition, button.AbsoluteSize
        local x = (pos.X + size.X / 2) * sx
        if x < 300 then controls.respawn = controls.respawn or button
        else controls.confirm = controls.confirm or button end
    end
    for _, lane in ipairs({"top", "bottom"}) do
        local counter = controls[lane == "top" and "counterTop" or "counterBottom"]
        if counter then
            local count = tonumber(textOf(counter):match("^%s*(%d+)%s*$"))
            if count and count <= 25 then counters[lane] = count end
        end
    end
    for lane, note in pairs(nearest) do
        local last = self.lastKinds[lane]
        self.lastKinds[lane] = {kind = note.kind, at = now, x = note.x,
            votes = last and last.kind == note.kind and last.votes + 1 or 1}
    end
    local challenge
    if self.activeChallenge then
        local count = counters[self.activeChallenge.lane]
        if count ~= nil then
            self.activeChallenge.missing = 0
            challenge = {visible = true, count = count, kind = self.activeChallenge.kind}
        else
            self.activeChallenge.missing = self.activeChallenge.missing + 1
            if self.activeChallenge.missing >= 4 then self.activeChallenge = nil end
        end
    end
    for _, lane in ipairs({"top", "bottom"}) do
        local count, last = counters[lane], self.lastKinds[lane]
        if not self.activeChallenge and count ~= nil and last and now - last.at <= 6 and last.votes >= 2 then
            challenge = {visible = true, count = count, kind = last.kind}
            self.activeChallenge = {lane = lane, kind = last.kind, missing = 0}
            break
        end
    end
    -- A nested label and its button may describe the same note. Keep one candidate.
    local filtered = {}
    for _, n in ipairs(notes) do
        local duplicate = false
        for _, previous in ipairs(filtered) do
            if previous.kind == n.kind and math.abs(previous.x - n.x) < 15 then duplicate = true end
        end
        if not duplicate then filtered[#filtered + 1] = n end
    end
    local character = self.player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    self.detectedKinds = self.detectedKinds or {}
    for kind in pairs(seenKinds) do self.detectedKinds[kind] = true end
    local ready = true
    for kind in pairs(kinds) do if not self.saved[kind] and not self.detectedKinds[kind] then ready = false end end
    self.controls = controls
    return {start = controls.start ~= nil, menu = controls.menu ~= nil,
        respawn = controls.respawn ~= nil, confirm = controls.confirm ~= nil,
        reconnect = controls.reconnect ~= nil, timer = controls.timer and Timer.parse(textOf(controls.timer)),
        alive = humanoid ~= nil and humanoid.Health > 0, bindingsReady = ready,
        training = not controls.start and ((controls.targetTop and controls.targetBottom) ~= nil or #filtered > 0 or challenge ~= nil),
        notes = filtered, challenge = challenge, controls = controls}
end
Bindings.visible = visible
return Bindings
