local Timer = require("src.Timer")
local GuiIndex = require("src.GuiIndex")
local Bindings = {}
Bindings.__index = Bindings
local KINDS = {"left", "right", "q", "e"}
local ROLES = {"start", "menu", "respawn", "confirm", "reconnect", "timer", "targetTop", "targetBottom", "counterTop", "counterBottom"}
local ALIASES = {
    q = "q", e = "e", keyq = "q", keye = "e", qkey = "q", ekey = "e",
    lmb = "left", rmb = "right", mouse1 = "left", mouse2 = "right",
    mousebutton1 = "left", mousebutton2 = "right", leftclick = "left", rightclick = "right",
    leftmouse = "left", rightmouse = "right", leftmousebutton = "left", rightmousebutton = "right",
}
local INPUT_ATTRIBUTES = {"Key", "KeyCode", "Input", "InputType", "Action", "Button"}
local function clean(value)
    return tostring(value or ""):lower():gsub("<[^>]*>", ""):gsub("[^%w]", "")
end
local function alias(value)
    return ALIASES[clean(tostring(value or ""):match("([^%.]+)$"))]
end
local function textOf(object)
    local class = object.ClassName
    if class == "TextLabel" or class == "TextButton" or class == "TextBox" then return object.Text end
    return ""
end
local function visible(object, memo)
    if not object or not object.Parent or not object:IsA("GuiObject") then return false end
    if object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then return false end
    local chain, current, result = {}, object, true
    while current and current ~= game do
        if memo and memo[current] ~= nil then result = memo[current]; break end
        chain[#chain + 1] = current
        if current:IsA("GuiObject") and (not current.Visible or (current.ClassName == "CanvasGroup" and current.GroupTransparency >= 1)) then result = false; break end
        if current:IsA("LayerCollector") and not current.Enabled then result = false; break end
        current = current.Parent
    end
    if memo then for _, node in ipairs(chain) do memo[node] = result end end
    return result
end
local function buttonOf(object)
    local current = object
    while current and not current:IsA("LayerCollector") do
        if current:IsA("GuiButton") then return current end
        current = current.Parent
    end
end
local function imageOf(object)
    if object and (object.ClassName == "ImageLabel" or object.ClassName == "ImageButton") then
        return {image = object.Image, x = object.ImageRectOffset.X, y = object.ImageRectOffset.Y,
            w = object.ImageRectSize.X, h = object.ImageRectSize.Y}
    end
end
local function signature(image)
    if type(image) ~= "table" or not image.image or image.image == "" then return nil end
    return table.concat({image.image, image.x or 0, image.y or 0, image.w or 0, image.h or 0}, "|")
end
local function group() return {items = {}, positions = {}} end
local function insert(set, object)
    if set.positions[object] then return end
    set.items[#set.items + 1], set.positions[object] = object, #set.items + 1
end
local function remove(set, object)
    local position = set.positions[object]
    if not position then return end
    local last = set.items[#set.items]
    set.items[position], set.positions[last] = last, position
    set.items[#set.items], set.positions[object] = nil, nil
end

function Bindings.new(player, saved, ownGui)
    local self = setmetatable({player = player, saved = type(saved) == "table" and saved or {},
        ownGui = ownGui, roots = {}, errors = {}, reported = {}, lastKinds = {}, detectedKinds = {},
        records = {}, learned = {}, imageObjects = {}, controls = {}, nextRoots = 0,
        nextControls = 0, nextLegacy = 0, groups = {}, running = false, candidateReads = 0}, Bindings)
    for _, name in ipairs({"controls", "timers", "targets", "notes", "counters", "unknown"}) do self.groups[name] = group() end
    for _, kind in ipairs(KINDS) do
        local old = self.saved[kind]
        local key = type(old) == "table" and signature(old.signature)
        if key then self.learned[key] = kind end
    end
    self.index = GuiIndex.new(ownGui,
        function(object, root) self:classify(object, root) end,
        function(object) self:drop(object) end,
        function(reason)
            if not self.reported[reason] then self.reported[reason] = true; self.errors[#self.errors + 1] = reason end
        end)
    return self
end
function Bindings:drop(object)
    for _, set in pairs(self.groups) do remove(set, object) end
    local old = self.records[object]
    if old and old.image and self.imageObjects[old.image] then self.imageObjects[old.image][object] = nil end
    self.records[object] = nil
end
function Bindings:scale()
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
    return 1280 / math.max(1, size.X), 720 / math.max(1, size.Y)
end
function Bindings:point(object, sx, sy)
    local p, size = object.AbsolutePosition, object.AbsoluteSize
    return (p.X + size.X / 2) * sx, (p.Y + size.Y / 2) * sy, size.X * sx, size.Y * sy
end
function Bindings:kind(object)
    local explicit = alias(textOf(object)) or alias(object.Name)
    if not explicit then
        for _, name in ipairs(INPUT_ATTRIBUTES) do
            explicit = alias(object:GetAttribute(name))
            if explicit then break end
        end
    end
    if not explicit and object.Parent then explicit = alias(object.Parent.Name) end
    local text = clean(textOf(object))
    for _, kind in ipairs(KINDS) do
        local old = self.saved[kind]
        if type(old) == "table" and old.text and old.text ~= "" and old.text == text then explicit = explicit or kind end
    end
    local key = signature(imageOf(object))
    if explicit and key then
        local previous = self.learned[key]
        local learned = previous == nil and explicit or (previous == explicit and explicit or false)
        if previous ~= learned then
            self.learned[key] = learned
            for image in pairs(self.imageObjects[key] or {}) do
                if image ~= object then self.index:enqueue(image, "PlayerGui", false) end
            end
        end
    end
    return explicit or (key and self.learned[key]) or nil
end
function Bindings:classify(object, root)
    local previous = self.records[object]
    local controlsChanged = previous and (previous.role or previous.timer or previous.target)
    self:drop(object)
    local raw, name = textOf(object), clean(object.Name)
    local label, button = clean(raw), buttonOf(object)
    local r = {root = root, image = signature(imageOf(object))}
    self.records[object] = r
    if r.image then
        self.imageObjects[r.image] = self.imageObjects[r.image] or {}
        self.imageObjects[r.image][object] = true
    end
    if button then
        if label == "start" then r.role = "start"
        elseif label == "reconnect" then r.role = "reconnect"
        elseif label == "respawn" then r.role = "respawn"
        elseif root == "PlayerGui" and (label == "menu" or name == "menubutton" or name == "hamburgerbutton" or name == "linesmenu") then r.role = "menu" end
    end
    local sx, sy = self:scale()
    local x, y, w, h = self:point(object, sx, sy)
    if root == "PlayerGui" and button and not r.role and object.ClassName == "ImageButton"
        and math.abs(x - 63) < 22 and math.abs(y - 22) < 18 and w < 65 and h < 65 then r.role = "menu" end
    if r.role then r.button = button; insert(self.groups.controls, object) end
    if root ~= "PlayerGui" then
        if r.role or controlsChanged then self.nextControls = 0 end
        return
    end -- CoreGui is only needed for disconnect controls.
    r.timer = Timer.parse(raw)
    if r.timer then insert(self.groups.timers, object) end
    r.kind = self:kind(object)
    if r.kind then insert(self.groups.notes, object) end
    r.count = tonumber(raw:match("^%s*(%d+)%s*$"))
    if r.count and r.count <= 25 and ((x > 960 and x < 1085 and y > 495 and y < 655)
        or name:find("counter", 1, true) or name:find("countdown", 1, true)) then insert(self.groups.counters, object) end
    if math.abs(x - 1025) < 35 and w >= 45 and w <= 110 and h >= 45 and h <= 110 and math.abs(w - h) < 20 then
        if math.abs(y - 535) < 30 then r.target = "targetTop"
        elseif math.abs(y - 620) < 30 then r.target = "targetBottom" end
    end
    if r.target then insert(self.groups.targets, object) end
    if r.image and not r.kind and x > 280 and x < 1085 and y > 495 and y < 655 and w < 100 and h < 100 then
        insert(self.groups.unknown, object)
    end
    if r.role or r.timer or r.target or controlsChanged then self.nextControls = 0 end
end
function Bindings:resolve(binding)
    if type(binding) ~= "table" or type(binding.path) ~= "table" then return nil end
    local current = self.roots[binding.root]
    for _, name in ipairs(binding.path) do
        if not current or type(name) ~= "string" then return nil end
        local found
        for _, child in ipairs(current:GetChildren()) do
            if child.Name == name then
                if found then return nil end
                found = child
            end
        end
        current = found
    end
    return current
end
function Bindings:refresh(now)
    if now >= self.nextRoots then
        self.nextRoots = now + 2
        local roots = {PlayerGui = self.player:FindFirstChildOfClass("PlayerGui")}
        local ok, core = pcall(function() return game:GetService("CoreGui") end)
        if ok then roots.CoreGui = core end
        if roots.PlayerGui ~= self.roots.PlayerGui or roots.CoreGui ~= self.roots.CoreGui then
            self.index:close()
            self.roots, self.controls, self.nextControls, self.nextLegacy = roots, {}, 0, 0
            for _, name in ipairs({"PlayerGui", "CoreGui"}) do
                if roots[name] then self.index:attach(name, roots[name]) end
            end
        end
    end
    self.running = true
    self.index:pump()
end
function Bindings:pause()
    if not self.running then return end
    self.index:close()
    self.running, self.roots, self.controls, self.lastKinds, self.activeChallenge = false, {}, {}, {}, nil
    self.nextRoots, self.nextControls, self.nextLegacy = 0, 0, 0
end
function Bindings:each(name, callback, limit)
    local set = self.groups[name]
    for i = 1, math.min(#set.items, limit or 128) do
        local object = set.items[i]
        local record = self.records[object]
        self.candidateReads = self.candidateReads + 1
        if record then callback(object, record) end
    end
end
function Bindings:snapshot(now)
    self:refresh(now)
    local sx, sy = self:scale()
    local memo = {}
    if now >= self.nextControls then
        self.nextControls = now + 0.15
        local controls = {}
        self:each("controls", function(object, r)
            if visible(object, memo) and visible(r.button, memo) then
                local role = r.role
                local x = self:point(r.button, sx, sy)
                if role == "respawn" and x >= 300 then role = "confirm" end
                controls[role] = controls[role] or r.button
            end
        end)
        self:each("timers", function(object)
            local x, y = self:point(object, sx, sy)
            if x > 1120 and y > 650 and visible(object, memo) then controls.timer = object end
        end)
        self:each("targets", function(object, r)
            if visible(object, memo) then controls[r.target] = object end
        end)
        if now >= self.nextLegacy then
            self.nextLegacy, self.legacy = now + 1, {}
            for _, role in ipairs(ROLES) do self.legacy[role] = self:resolve(self.saved[role]) end
        end
        for role, object in pairs(self.legacy or {}) do if visible(object, memo) then controls[role] = object end end
        self.controls = controls
    end
    local controls = {}
    for role, object in pairs(self.controls) do if visible(object, memo) then controls[role] = object end end
    local notes, counters, nearest, filtered = {}, {}, {}, {}
    self:each("notes", function(object, r)
        if visible(object, memo) then
            local x, y = self:point(object, sx, sy)
            local lane = (r.kind == "left" or r.kind == "right") and "top" or "bottom"
            if x > 280 and x < 1085 and math.abs(y - (lane == "top" and 540 or 612)) < 30 then
                self.detectedKinds[r.kind] = true
                local target = controls[lane == "top" and "targetTop" or "targetBottom"]
                local targetX = target and self:point(target, sx, sy) or 1025
                notes[#notes + 1] = {id = object, kind = r.kind, x = x, target = targetX}
                if x <= targetX + 30 and (not nearest[lane] or x > nearest[lane].x) then nearest[lane] = {kind = r.kind, x = x} end
            end
        end
    end)
    self:each("counters", function(object, r)
        if visible(object, memo) then
            local x, y = self:point(object, sx, sy)
            if x > 960 and x < 1085 and y > 495 and y < 655 then counters[y < 575 and "top" or "bottom"] = r.count end
        end
    end)
    for _, lane in ipairs({"top", "bottom"}) do
        local counter = controls[lane == "top" and "counterTop" or "counterBottom"]
        if counter then
            local count = tonumber(textOf(counter):match("^%s*(%d+)%s*$"))
            if count and count <= 25 then counters[lane] = count end
        end
    end
    for lane, note in pairs(nearest) do
        local previous = self.lastKinds[lane]
        self.lastKinds[lane] = {kind = note.kind, at = now, votes = previous and previous.kind == note.kind and previous.votes + 1 or 1}
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
        local count, previous = counters[lane], self.lastKinds[lane]
        if not self.activeChallenge and count ~= nil and previous and now - previous.at <= 6 and previous.votes >= 2 then
            challenge = {visible = true, count = count, kind = previous.kind}
            self.activeChallenge = {lane = lane, kind = previous.kind, missing = 0}
            break
        end
    end
    for _, note in ipairs(notes) do
        local duplicate = false
        for _, old in ipairs(filtered) do if old.kind == note.kind and math.abs(old.x - note.x) < 15 then duplicate = true; break end end
        if not duplicate then filtered[#filtered + 1] = note end
    end
    local character = self.player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local ready = true
    for _, kind in ipairs(KINDS) do
        if not self.detectedKinds[kind] and not self.saved[kind] then ready = false end
    end
    return {start = controls.start ~= nil, menu = controls.menu ~= nil, respawn = controls.respawn ~= nil,
        confirm = controls.confirm ~= nil, reconnect = controls.reconnect ~= nil,
        timer = controls.timer and Timer.parse(textOf(controls.timer)),
        alive = humanoid ~= nil and humanoid.Health > 0, bindingsReady = ready,
        training = not controls.start and ((controls.targetTop and controls.targetBottom) ~= nil or #filtered > 0 or challenge ~= nil),
        notes = filtered, challenge = challenge, controls = controls}
end
Bindings.visible = visible
return Bindings
