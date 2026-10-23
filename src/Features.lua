local Catalog = require("src.FeatureCatalog")
local Scope = require("src.EffectScope")
local Effects = require("src.HubEffects")
local Weights = require("src.Weights")
local HTCEntry = require("src.HTCEntry")
local Stones = require("src.Stones")
local Cosmetics = require("src.Cosmetics")
local CosmeticBrowser = require("src.CosmeticBrowser")
local Features = {}
Features.__index = Features
local intervals = {speed = 0.1, jump = 0.2, noclip = 0, flight = 0,
    punch = 0.1, blast = 0.15, block = 0.3, lock = 0.2, transform = 1,
    bright = 1, sky = 1, players = 1, npcs = 0.1, radar = 0.1, fov = 0.2,
    meditate = 2, charge = 0.2, save = 30, antiAfk = 1, shake = 1, dragonStones = 0.5, superStones = 0.5,
    cosmetics = 0.05}
local conflicts = {speed = true, jump = true, noclip = true, flight = true,
    punch = true, blast = true, block = true, lock = true, transform = true,
    meditate = true, charge = true, antiAfk = true, fov = true, shake = true}
local events = {
    punch = {{"CombatSwing", "KeyAttack"}, "EffectSTA"},
    blast = {{"KiBlast", "BlastMoves"}},
    transform = {{"Transform", "Transformtion"}, true},
    save = {{"SaveFeature", "SaveData"}},
}
function Features.new(player, ui, blocked, saved, onChange, env, session)
    local self = setmetatable({player = player, ui = ui, blocked = blocked, onChange = onChange,
        enabled = {}, values = {}, contexts = {}, textFormats = {}, live = true, messages = {}, actionTimes = {}}, Features)
    for _, name in ipairs(Catalog.pages) do ui:addPage(name) end
    for _, definition in ipairs(Catalog.controls) do
        local page, id, title, kind = definition[1], definition[2], definition[3], definition[4]
        if kind == "slider" then
            local value = type(saved) == "table" and tonumber(saved[id]) or nil
            if not value or value ~= value then value = definition[7] end
            value = math.floor(math.max(definition[5], math.min(definition[6], value)))
            self.values[id] = value
            ui:addSlider(page, id, title, definition[5], definition[6], value, function(v)
                self.values[id] = v
                if id == "fov" then self.enabled.fov = true; self:sync() end
                if self.onChange then self.onChange(id, "slider") end
            end)
        elseif kind == "text" then
            self.textFormats[id] = definition[6]
            local value = type(saved) == "table" and saved[id] or nil
            value = Stones.validateText(value, definition[6]) or definition[5]
            self.values[id] = value
            ui:addTextBox(page, id, title, value, function(text) self:commitText(id, text) end)
        elseif kind == "toggle" then
            ui:addToggle(page, id, title, function() self:set(id, not self.enabled[id]) end)
        else ui:addButton(page, id, title, function() self:action(id) end) end
        if id == "cosmetics" then
            self.cosmeticBrowser = CosmeticBrowser.new(ui,
                function(item) self:cosmeticAction("equip", item) end,
                function() self:cosmeticAction("save") end)
        end
    end
    ui:addButton("Visuals", "resetFov", "Restore Game FOV", function() self:set("fov", false) end)
    self.htcEntry = HTCEntry.new(player, function()
        return self.live and not self.blocked() and not self.enabled.meditate
    end, function(message) self:status("enterHTC", message) end, env,
        session and type(env.readfile) == "function" and type(env.writefile) == "function"
            and type(env.makefolder) == "function" and {prepare = function()
                local ok = pcall(session.prepare, session, 4178935231, "manual")
                return ok
            end} or nil)
    self:status("enterHTC", "No cooldown: free entry. Active cooldown: 60,000 Zeni.")
    return self
end
function Features:cosmeticAction(action, item)
    if not self.live then return end
    local c = self.contexts.cosmetics
    if not c or not c.cosmetics then self:status("cosmeticBrowser", "Enable Cosmetic Unlocker to browse."); return end
    if action == "equip" then c.cosmetics:equip(item) else c.cosmetics:save() end
end
function Features:commitText(id, text)
    if not self.live then return false end
    local value, reason = Stones.validateText(text, self.textFormats[id])
    if not value then self:status(id, reason); return false end
    self.values[id] = value
    self.ui.controls[id].input.Text = value
    self:status(id, "Saved")
    if self.onChange then self.onChange(id, "text") end
    return true
end
function Features:status(id, text)
    if not self.live or self.messages[id] == text then return end
    self.messages[id] = text
    self.ui:setControlStatus(id, text)
end
function Features:running(id)
    if not self.live or not self.enabled[id] then return false end
    if conflicts[id] and self.blocked() then return false end
    -- Manual meditation owns the same input solver; combat/flight must not add
    -- extra clicks or react to its Q/E prompts.
    if conflicts[id] and id ~= "meditate" and self.enabled.meditate then return false end
    return true
end
function Features:findRemote(names, class)
    local root = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    if root then
        for _, name in ipairs(names) do
            local remote = root:FindFirstChild(name)
            if remote and remote:IsA(class) then return remote end
        end
    end
    error("Missing " .. table.concat(names, " / "), 0)
end
function Features:fire(names, ...)
    local remote = self:findRemote(names, "RemoteEvent")
    remote:FireServer(...)
    return remote
end
function Features:driveBlock(channel)
    if channel.busy then return end
    channel.busy = true
    task.spawn(function()
        local desired = channel.desired
        local ok, reason = pcall(function()
            if channel.remote:IsA("RemoteFunction") then channel.remote:InvokeServer({"Blocking", desired})
            else channel.remote:FireServer(desired) end
        end)
        channel.busy = false
        if not ok then self:status("block", "Unavailable: " .. tostring(reason)) end
        -- A stop may arrive while InvokeServer yields. Send its release only
        -- after the original request settles, with at most one request in flight.
        if channel.desired ~= desired then self:driveBlock(channel) end
    end)
end
function Features:block(state)
    if state and self.blockChannel and not self.blockChannel.busy and not self.blockChannel.remote.Parent then
        self.blockChannel = nil
    end
    if state and not self.blockChannel then
        local ok, remote = pcall(self.findRemote, self, {"MainFunction"}, "RemoteFunction")
        if not ok then remote = self:findRemote({"Blocking"}, "RemoteEvent") end
        self.blockChannel = {remote = remote, desired = false}
    end
    local channel = self.blockChannel
    if channel then channel.desired = state; self:driveBlock(channel) end
end
function Features:stopContext(id)
    local c = self.contexts[id]
    if not c then return end
    self.contexts[id] = nil
    c.scope:close()
    if id == "block" then self:block(false) end
    if c.charging then pcall(c.charging.FireServer, c.charging, false) end
end
function Features:sync()
    if self.htcEntry and (self.blocked() or self.enabled.meditate) then self.htcEntry:cancel() end
    if self.recharge and (self.blocked() or self.enabled.meditate) then
        pcall(self.recharge.FireServer, self.recharge, false); self.recharge = nil
    end
    for id in pairs(intervals) do
        local running = self:running(id)
        if running and not self.contexts[id] then
            self.contexts[id] = {scope = Scope.new(), next = id == "save" and os.clock() + 30 or 0}
            self:status(id, id == "meditate" and "Waiting for a manually started round" or "Enabled")
        elseif not running then
            self:stopContext(id)
            if self.enabled[id] then self:status(id, self.blocked() and "Paused while Chamber runs" or "Paused while Auto Meditate runs")
            else self:status(id, "Off") end
        end
    end
end
function Features:set(id, enabled)
    if not self.live or not intervals[id] then return end
    if enabled and (id == "dragonStones" or id == "superStones") then
        local fields = id == "dragonStones" and {"questName", "questDragonStones", "questZeni", "questSuperStones"}
            or {"superStoneTarget"}
        local valid = true
        for _, field in ipairs(fields) do
            if not self:commitText(field, self.ui.controls[field].input.Text) then valid = false end
        end
        if not valid then self:status(id, "Enter valid values above before enabling"); return end
    end
    self.enabled[id] = enabled == true
    self.ui:setControlEnabled(id, self.enabled[id])
    self:sync()
    if self.onChange then self.onChange(id, "toggle") end
end
function Features:equipMeditationWeights()
    local equipped, label = Weights.equipBest(self.player)
    local data = self.player:FindFirstChild("Data")
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("hahahahaswno3")
    if not data or not remote or not remote:IsA("RemoteEvent") then return end
    for _, weight in ipairs({"Heavy", "Medium", "Light"}) do
        local owned = data:FindFirstChild(weight .. "Weights")
        if owned and tonumber(owned.Value) and tonumber(owned.Value) >= 1 then
            if not equipped or label ~= weight .. " Weights" then remote:FireServer("WeightOwned", weight) end
            return
        end
    end
end
function Features:lockNearest()
    local char = self.player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local nearest, distance
    for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
        local otherChar = other.Character
        local part = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
        local hum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
        if other ~= self.player and part and hum and hum.Health > 0 then
            local d = (part.Position - root.Position).Magnitude
            if not distance or d < distance then nearest, distance = part, d end
        end
    end
    if nearest then
        local target = Vector3.new(nearest.Position.X, root.Position.Y, nearest.Position.Z)
        if (target - root.Position).Magnitude > 0.01 then root.CFrame = CFrame.new(root.Position, target) end
    end
end
function Features:step(now)
    if not self.live then return end
    self:sync()
    for id, c in pairs(self.contexts) do
        if now >= c.next then
            c.next = now + intervals[id]
            local ok, reason = pcall(function()
                if events[id] then
                    local event = events[id]
                    if event[2] == nil then self:fire(event[1]) else self:fire(event[1], event[2]) end
                elseif id == "block" then self:block(true)
                elseif id == "charge" then c.charging = self:fire({"Charging"}, true)
                elseif id == "meditate" then self:equipMeditationWeights()
                elseif id == "lock" then self:lockNearest()
                elseif id == "dragonStones" then Stones.quest(c, self)
                elseif id == "superStones" then Stones.super(c, self)
                elseif id == "cosmetics" then
                    if not c.cosmetics then
                        c.cosmetics = Cosmetics.new(self)
                        c.scope.cleanup[#c.scope.cleanup + 1] = function() c.cosmetics:destroy() end
                        c.cosmetics:message("Local entries only; the server decides what you own.")
                    end
                    c.cosmetics:step(now)
                else Effects.step(id, c, self, now) end
            end)
            if not ok then
                self:status(id, "Unavailable: " .. tostring(reason))
                c.next = now + 3 -- Missing game-specific controls never become a hot loop.
            elseif self.messages[id] and self.messages[id]:sub(1, 12) == "Unavailable:" then
                self:status(id, "Enabled")
            end
        end
    end
end
function Features:action(id)
    if not self.live then return end
    if id == "enterHTC" then self.htcEntry:request(); return end
    if self.blocked() or self:running("meditate") then
        self:status(id, "Turn Chamber / Auto Meditate off first")
        return
    end
    local now = os.clock()
    if now < (self.actionTimes[id] or 0) then return end
    self.actionTimes[id] = now + 1
    local ok, reason = pcall(function()
        if id == "recharge" then
            local remote = self:fire({"Charging"}, true)
            self.recharge = remote
            task.spawn(function()
                task.wait(1)
                if self.recharge == remote then
                    self.recharge = nil
                    if not self:running("charge") then pcall(remote.FireServer, remote, false) end
                end
            end)
        else
            local destination
            for _, candidate in ipairs(Catalog.destinations) do if candidate[1] == id then destination = candidate end end
            assert(destination, "Unknown destination")
            local char = self.player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            assert(root and hum and hum.Health > 0, "Wait for your character to respawn")
            local target = CFrame.new(destination[4], destination[5], destination[6])
            if destination[3] then
                for _, name in ipairs({"Quests", "QuestsInTheCity", "NPCs"}) do
                    local folder = workspace:FindFirstChild(name)
                    local npc = folder and folder:FindFirstChild(destination[3])
                    if npc and npc:IsA("Model") then target = npc:GetPivot() + Vector3.new(0, 5, 0); break end
                end
            end
            root.CFrame = target
        end
    end)
    self:status(id, ok and "Requested" or "Unavailable: " .. tostring(reason))
end
function Features:destroy()
    self.live = false
    self.htcEntry:destroy()
    for id in pairs(self.contexts) do self:stopContext(id) end
    if self.recharge then pcall(self.recharge.FireServer, self.recharge, false); self.recharge = nil end
end
return Features
