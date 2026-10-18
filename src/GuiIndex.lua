-- Event-driven discovery. Neither bootstrap nor updates use GetDescendants.
local GuiIndex = {}
GuiIndex.__index = GuiIndex

function GuiIndex.new(ownGui, changed, removed, report)
    return setmetatable({ownGui = ownGui, changed = changed, removed = removed,
        report = report, records = {}, roots = {}, connections = {}, queue = {},
        queued = {}, head = 1, tail = 0, updates = {}, dirty = {}, updateHead = 1,
        updateTail = 0, maxUpdates = 32, maxWork = 96, budgetSeconds = 0.0008,
        processed = 0, lastWork = 0}, GuiIndex)
end
function GuiIndex:enqueue(object, root, expand)
    if self.ownGui and (object == self.ownGui or object:IsDescendantOf(self.ownGui)) then return end
    if not expand then
        if self.dirty[object] then return end
        local update = {object = object, root = root}
        self.updateTail = self.updateTail + 1
        self.updates[self.updateTail], self.dirty[object] = update, update
        return
    end
    local old = self.queued[object]
    if old then old.expand = old.expand or expand; return end
    local job = {object = object, root = root, expand = expand}
    self.tail = self.tail + 1
    self.queue[self.tail], self.queued[object] = job, job
end
function GuiIndex:remove(object)
    self.queued[object], self.dirty[object] = nil, nil
    local record = self.records[object]
    if record then
        for _, connection in ipairs(record.connections) do connection:Disconnect() end
        self.records[object] = nil
        self.removed(object)
    end
end
function GuiIndex:attach(name, root)
    self.roots[name] = root
    local ok, reason = pcall(function()
        self.connections[#self.connections + 1] = root.DescendantAdded:Connect(function(object)
            self:enqueue(object, name, false)
        end)
        self.connections[#self.connections + 1] = root.DescendantRemoving:Connect(function(object)
            self:remove(object)
        end)
    end)
    if not ok then self.report(name .. " cannot be observed: " .. tostring(reason)) end
    self:enqueue(root, name, true)
end
function GuiIndex:watch(object, record)
    local function changed() self:enqueue(object, record.root, false) end
    local function property(name)
        local ok, connection = pcall(function() return object:GetPropertyChangedSignal(name):Connect(changed) end)
        if ok then record.connections[#record.connections + 1] = connection end
    end
    property("Name")
    local class = object.ClassName
    if class == "TextLabel" or class == "TextButton" or class == "TextBox" then property("Text") end
    if class == "ImageLabel" or class == "ImageButton" then
        property("Image"); property("ImageRectOffset"); property("ImageRectSize")
    end
    local ok, connection = pcall(function() return object.AttributeChanged:Connect(changed) end)
    if ok then record.connections[#record.connections + 1] = connection end
end
function GuiIndex:visit(job)
    local object, root = job.object, self.roots[job.root]
    if not root or (object ~= root and not object:IsDescendantOf(root)) or object == self.ownGui then return false end
    local record = self.records[object]
    if not record and object:IsA("GuiObject") then
        record = {root = job.root, connections = {}}
        self.records[object] = record
        self:watch(object, record)
    end
    if record then self.changed(object, job.root) end
    return true
end
function GuiIndex:pump()
    local started, work = os.clock(), 0
    -- New prompts and changed counters must not wait behind a large inventory.
    -- Limit this queue as well so initial discovery can continue during updates.
    while self.updateHead <= self.updateTail and work < self.maxUpdates do
        if work > 0 and os.clock() - started >= self.budgetSeconds then break end
        local job = self.updates[self.updateHead]
        self.updates[self.updateHead], self.updateHead = nil, self.updateHead + 1
        work = work + 1
        if self.dirty[job.object] == job then
            self.dirty[job.object] = nil
            self:visit(job)
        end
    end
    if self.updateHead > self.updateTail then self.updates, self.updateHead, self.updateTail = {}, 1, 0 end
    while self.head <= self.tail and work < self.maxWork do
        if work > 0 and os.clock() - started >= self.budgetSeconds then break end
        local job = self.queue[self.head]
        work = work + 1
        if self.queued[job.object] ~= job then
            self.queue[self.head], self.head = nil, self.head + 1
        elseif job.children and job.cursor <= #job.children then
            self:enqueue(job.children[job.cursor], job.root, true)
            job.cursor = job.cursor + 1
        else
            if not job.visited then
                job.visited = true
                if self:visit(job) then
                    if job.expand then
                        local ok, children = pcall(job.object.GetChildren, job.object)
                        if ok then job.children, job.cursor = children, 1
                        else self.report(job.root .. " cannot be read by this executor") end
                    end
                end
            end
            if not job.children or job.cursor > #job.children then
                self.queue[self.head], self.queued[job.object] = nil, nil
                self.head = self.head + 1
            end
        end
    end
    if self.head > self.tail then self.queue, self.head, self.tail = {}, 1, 0 end
    self.lastWork, self.processed = work, self.processed + work
end
function GuiIndex:close()
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    for object in pairs(self.records) do self:remove(object) end
    self.roots, self.connections, self.queue, self.queued = {}, {}, {}, {}
    self.updates, self.dirty, self.updateHead, self.updateTail = {}, {}, 1, 0
    self.head, self.tail = 1, 0
end
return GuiIndex
