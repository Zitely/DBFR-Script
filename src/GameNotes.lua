-- DBFR's live lanes, from the supplied Minigame module. Observe only direct
-- children: templates and the decorative clones inside mash notes are not inputs.
local GameNotes = {}
GameNotes.__index = GameNotes
local INPUTS = {MouseButton1 = "left", MouseButton2 = "right", Q = "q", E = "e"}
local function kind(object, lane, mash)
    local key = mash and object:GetAttribute("Key") or object.Name
    local result = INPUTS[key]
    if lane == 1 and (result == "left" or result == "right") then return result end
    if lane == 2 and (result == "q" or result == "e") then return result end
end
local function progress(object)
    return object.Position.X.Scale
end
function GameNotes.new()
    return setmetatable({lanes = {}, reads = 0}, GameNotes)
end
function GameNotes:close()
    for _, lane in pairs(self.lanes) do
        for _, connection in ipairs(lane.connections) do connection:Disconnect() end
    end
    self.lanes, self.challengeId, self.attack, self.block = {}, nil, nil, nil
end
function GameNotes:attach(attack, block)
    if self.attack == attack and self.block == block then return end
    self:close()
    self.attack, self.block = attack, block
    for number, root in pairs({[1] = attack, [2] = block}) do
        local lane = {root = root, objects = {}, connections = {}}
        self.lanes[number] = lane
        local function add(object)
            if object.Parent == root and object:IsA("GuiObject") then lane.objects[object] = true end
        end
        lane.connections[1] = root.DescendantAdded:Connect(add)
        lane.connections[2] = root.DescendantRemoving:Connect(function(object) lane.objects[object] = nil end)
        -- Read these two small child lists once per replacement, never the GUI tree.
        for _, object in ipairs(root:GetChildren()) do add(object) end
    end
end
function GameNotes:read(state, visible, memo)
    self:attach(state and state.attack, state and state.block)
    local notes, nearest, mashes, busy = {}, {}, {}, false
    if not state or not state.training then self.challengeId = nil; return notes end
    for number, lane in pairs(self.lanes) do
        for object in pairs(lane.objects) do
            self.reads = self.reads + 1
            if object.Parent == lane.root and visible(object, memo) then
                local x = progress(object)
                if object.Name == "mash" then
                    if x >= 1 and x <= 5.4 then
                        local old = mashes[number]
                        if not old or object == self.challengeId
                            or (old.id ~= self.challengeId and x > old.progress) then
                            mashes[number] = {id = object, kind = kind(object, number, true), progress = x}
                        end
                    end
                elseif object.Name ~= "NC" and (not nearest[number] or x > nearest[number].progress) then
                    -- Include unknown names in selection: the game's Hit takes
                    -- the rightmost note, so skipping one would hit the wrong key.
                    nearest[number] = {id = object, kind = kind(object, number), progress = x, lane = number}
                end
            end
        end
    end
    local challenge
    for number, counter in pairs({[1] = state.counterA, [2] = state.counterB}) do
        if visible(counter, memo) then
            busy = true
            local mash = mashes[number]
            local count = tonumber(counter.Text:match("^%s*(%d+)%s*$"))
            if mash and mash.kind and count and count <= 25 then
                challenge = {id = mash.id, visible = true, kind = mash.kind, count = count}
                self.challengeId = mash.id
                break
            end
        end
    end
    if not challenge then self.challengeId = nil end
    if busy then return notes, challenge end
    for number = 1, 2 do
        local note = nearest[number]
        if note and note.kind and note.progress < 1.2 then
            local link = note.id:FindFirstChild("Obj")
            if link then
                local other = link.ClassName == "ObjectValue" and link.Value
                local otherLane = self.lanes[3 - number]
                local otherKind = other and kind(other, 3 - number)
                if otherLane and other and other.Parent == otherLane.root and otherKind
                    and visible(other, memo) and progress(other) > 0.8 and progress(other) < 1.2 then
                    note.partner = {id = other, kind = otherKind}
                    notes[#notes + 1] = note
                end
            else notes[#notes + 1] = note end
        end
    end
    return notes, challenge
end
return GameNotes
