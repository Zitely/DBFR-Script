-- Discover only named world folders, with a bounded breadth-first queue.
-- Streaming additions use the same budget; highlights never trigger discovery.
local Markers = {}
Markers.__index = Markers
local function ballName(object)
    local name = object.Name:lower():gsub("%s", "")
    return name:find("dragonball", 1, true) or name:find("starball", 1, true)
end
function Markers.new(radar, notify)
    return setmetatable({radar = radar, notify = notify, roots = {}, records = {},
        seen = setmetatable({}, {__mode = "k"}), jobs = {}, head = 1, tail = 0, count = 0}, Markers)
end
function Markers:enqueue(object)
    if object.Name:sub(1, 6) == "DBFR__" then return end
    self.tail = self.tail + 1
    self.jobs[self.tail] = {object = object}
end
function Markers:remove(object)
    local record = self.records[object]
    if not record then return end
    self.records[object] = nil; self.count = self.count - 1
    record.highlight:Destroy()
    if record.tag then record.tag:Destroy() end
end
function Markers:setRoots(roots)
    local wanted = {}
    for _, root in ipairs(roots) do
        wanted[root] = true
        if not self.roots[root] then
            self.roots[root] = root.DescendantAdded:Connect(function(object) self:enqueue(object) end)
            self:enqueue(root)
        end
    end
    for root, connection in pairs(self.roots) do
        if not wanted[root] then connection:Disconnect(); self.roots[root] = nil end
    end
end
function Markers:within(object)
    for root in pairs(self.roots) do
        if root.Parent and (object == root or object:IsDescendantOf(root)) then return true end
    end
    return false
end
function Markers:visit(object)
    if self.records[object] or self.count >= 128 then return end
    if not object:IsA("Model") and not object:IsA("BasePart") then return end
    if self.radar then
        if not ballName(object) then return end
        local ancestor = object.Parent
        while ancestor and not self.roots[ancestor] do
            if (ancestor:IsA("Model") or ancestor:IsA("BasePart")) and ballName(ancestor) then return end
            ancestor = ancestor.Parent
        end
    elseif not object:IsA("Model") or not self.roots[object.Parent] then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "DBFR__Highlight"
    highlight.Adornee = object
    highlight.FillColor = self.radar and Color3.fromRGB(255, 132, 35) or Color3.fromRGB(94, 217, 255)
    highlight.OutlineColor = Color3.fromRGB(255, 211, 98)
    highlight.FillTransparency = 0.5
    highlight.Parent = object
    self.records[object] = {highlight = highlight}
    self.count = self.count + 1
end
function Markers:step(position)
    local work = 0
    while self.head <= self.tail and work < 64 do
        work = work + 1
        local job = self.jobs[self.head]
        if not self:within(job.object) then
            self.jobs[self.head] = nil; self.head = self.head + 1
        elseif not job.children then
            self:visit(job.object)
            job.children, job.index = job.object:GetChildren(), 1
        else
            local child = job.children[job.index]
            if child then self:enqueue(child); job.index = job.index + 1
            else self.jobs[self.head] = nil; self.head = self.head + 1 end
        end
    end
    self.lastWork = work
    if self.head > self.tail then self.jobs, self.head, self.tail = {}, 1, 0 end
    for object, record in pairs(self.records) do
        if not self:within(object) then self:remove(object)
        elseif self.radar then
            local part = object:IsA("BasePart") and object or object.PrimaryPart
                or object:FindFirstChildWhichIsA("BasePart", true)
            if part and not record.tag then
                local tag = Instance.new("BillboardGui")
                tag.Name, tag.Adornee = "DBFR__Radar", part
                tag.Size, tag.StudsOffset = UDim2.fromOffset(190, 35), Vector3.new(0, 3, 0)
                tag.AlwaysOnTop, tag.Parent = true, object
                local text = Instance.new("TextLabel")
                text.Name = "DBFR__RadarText"
                text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
                text.TextColor3, text.TextSize = Color3.fromRGB(255, 211, 98), 14
                text.Parent = tag
                record.tag, record.text = tag, text
                if not self.seen[object] then self.seen[object] = true; self.notify(object.Name) end
            end
            if part and record.text then
                record.tag.Adornee = part
                record.text.Text = object.Name .. (position and (" · " .. math.floor((part.Position - position).Magnitude) .. " studs") or "")
            end
        end
    end
end
function Markers:destroy()
    for _, connection in pairs(self.roots) do connection:Disconnect() end
    self.roots = {}
    for object in pairs(self.records) do self:remove(object) end
    self.jobs, self.head, self.tail = {}, 1, 0
end
return Markers
