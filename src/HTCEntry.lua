-- Shared HTC cooldown/fee entry operation; callers own the training cycle.
local HTCEntry = {}
HTCEntry.__index = HTCEntry
local PLACE_ID, FEE = 4178935231, 60000
local RELOAD = [[
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local env = type(getgenv) == "function" and getgenv() or _G
    local compile = loadstring or env.loadstring
    if type(compile) ~= "function" then warn("Saiyan Hub: reload requires loadstring"); return end
    local source = game:HttpGet("https://raw.githubusercontent.com/Zitely/DBFR-Script/main/http_loader.lua?t=" .. tostring(os.time()))
    assert(compile(source, "Saiyan Hub loader"))()
end)
]]
local function remote(parent, name, class)
    local object = parent and parent:FindFirstChild(name)
    assert(object and object:IsA(class), "Missing " .. name .. " " .. class)
    return object
end
function HTCEntry.new(player, allowed, status, env, options)
    return setmetatable({player = player, allowed = allowed, status = status, env = env or {},
        options = options or {}, live = true, generation = 0, nextAttempt = 0}, HTCEntry)
end
function HTCEntry:valid(generation, character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return self.live and generation == self.generation and self.allowed()
        and self.player.Character == character and hum and hum.Health > 0
end
function HTCEntry:cancel()
    if self.busy and not self.cancelled then
        self.cancelled = true
        self.generation = self.generation + 1
        self.status(self.feeRequested and "Entry cancelled; fee may already be charged" or "Entry cancelled")
    end
end
function HTCEntry:queueReload()
    if self.options.prepare then return self.options.prepare() end
    if self.reloadQueued then return true end
    local env = self.env
    local queue = env.queue_on_teleport or env.queueonteleport
        or (type(env.syn) == "table" and env.syn.queue_on_teleport)
        or (type(env.fluxus) == "table" and env.fluxus.queue_on_teleport)
    if type(queue) ~= "function" then return false end
    local ok = pcall(queue, RELOAD)
    self.reloadQueued = ok
    return ok
end
function HTCEntry:request()
    if not self.live then return end
    if game.PlaceId == PLACE_ID then self.status("Already inside HTC"); return end
    if not self.allowed() then self.status("Turn Chamber / Auto Meditate off first"); return end
    if self.busy or os.clock() < self.nextAttempt then self.status("Entry already pending; please wait"); return end
    local character = self.player.Character
    self.generation = self.generation + 1
    local generation = self.generation
    if not self:valid(generation, character) then self.status("Wait for your character to respawn"); return end
    self.busy, self.cancelled, self.pendingTeleport = true, false, false
    self.status("Checking HTC cooldown…")
    task.spawn(function()
        local ok, reason = pcall(function()
            if not self:valid(generation, character) then return end
            local storage = game:GetService("ReplicatedStorage")
            local teleport = game:GetService("TeleportService")
            assert(type(teleport.Teleport) == "function", "TeleportService is unavailable")
            if not self.failureConnection then
                self.failureConnection = teleport.TeleportInitFailed:Connect(function(player, _, detail, placeId)
                    if self.live and self.pendingTeleport and player == self.player and placeId == PLACE_ID then
                        self.pendingTeleport, self.nextAttempt = false, 0
                        self.status("Teleport failed: " .. tostring(detail) .. (self.feeRequested and "; retry will not resend fee" or ""))
                        if self.options.failed then self.options.failed(detail, true) end
                    end
                end)
            end
            local timeCheck = remote(storage, "TimeCheck", "RemoteFunction")
            local remaining = timeCheck:InvokeServer(2)
            if not self:valid(generation, character) then return end
            assert(type(remaining) == "number" and remaining == remaining and remaining >= 0
                and remaining < math.huge, "HTC cooldown could not be read")
            -- Automatic travel must persist its next hop before any fee is sent.
            local reload
            if self.options.prepare then reload = self:queueReload() end
            if not self:valid(generation, character) then return end
            if remaining > 0 then
                -- Validate both controls before sending a payment. A failed or
                -- cancelled request may still reach the server, so never repeat
                -- that fee automatically or on retries in this hub instance.
                local payment = remote(storage:FindFirstChild("Remotes"), "NPCStuff", "RemoteEvent")
                local quest = remote(storage, "GetQuest", "RemoteEvent")
                if not self.feeRequested then
                    local data = self.player:FindFirstChild("Data")
                    local moneys = data and data:FindFirstChild("Moneys")
                    local balance = moneys and tonumber(moneys.Value)
                    assert(balance and balance == balance and balance >= FEE and balance < math.huge,
                        "Cooldown active; requires 60,000 Zeni")
                    self.status("Requesting 60,000-Zeni re-entry fee…")
                    self.feeRequested = true
                    payment:FireServer("GravityChamberReEnterFee")
                end
                if not self:valid(generation, character) then return end
                quest:FireServer(70)
                task.wait(0.2)
                if not self:valid(generation, character) then return end
            end
            if reload == nil then reload = self:queueReload() end
            if not self:valid(generation, character) then return end
            self.pendingTeleport, self.nextAttempt = true, os.clock() + 10
            self.status(reload and "Entering HTC; hub reload queued" or "Entering HTC; run your loader after joining")
            if self.options.sent then self.options.sent() end
            teleport:Teleport(PLACE_ID, self.player)
        end)
        self.busy = false
        if not self.live then return end
        if not ok and not self.cancelled then
            local transportFailure = self.pendingTeleport == true
            self.pendingTeleport = false
            self.nextAttempt = os.clock() + 1
            self.status("Entry failed: " .. tostring(reason) .. (self.feeRequested and "; fee will not be resent" or ""))
            if self.options.failed then self.options.failed(reason, transportFailure) end
        elseif not self.pendingTeleport and not self:valid(generation, character) then
            self.status(self.feeRequested and "Entry cancelled; fee may already be charged" or "Entry cancelled")
            if self.options.failed then self.options.failed("Character changed or entry was cancelled", false) end
        end
    end)
end
function HTCEntry:destroy()
    self:cancel()
    self.live = false
    if self.failureConnection then self.failureConnection:Disconnect(); self.failureConnection = nil end
end
return HTCEntry
