local Resume = require("src.TeleportResume")
local HTCEntry = require("src.HTCEntry")
local Overnight = {}
Overnight.__index = Overnight
function Overnight.new(player, engine, config, session, env, halt)
    local self = setmetatable({player = player, engine = engine, config = config, session = session,
        halt = halt, token = 0, attempts = 0, live = true}, Overnight)
    self.entry = HTCEntry.new(player, function() return self:active() end,
        function(message) if self:active() then self:status(message) end end, env, {
            prepare = function() return session:prepare(Resume.HTC, "train") end,
            sent = function() self.phase, self.since = "entering", os.clock() end,
            failed = function(reason, transport)
                if self:active() then self:failed(reason, transport, "earth_loading") end
            end,
        })
    return self
end
function Overnight:active() return self.live and self.engine.active and self.phase ~= nil end
function Overnight:status(message)
    if self.engine.status ~= message then self.engine.status = message; self.engine.log(message) end
end
function Overnight:cancel()
    self.phase, self.token = nil, self.token + 1
    self.entry:cancel()
    local ok, reason = self.session:cancel()
    if not ok then self:status("Stopped locally; could not cancel teleport reload: " .. tostring(reason)) end
    return ok, reason
end
function Overnight:failed(reason, retryable, phase)
    self.entry.pendingTeleport = false
    local revoked, detail = self.session:cancel()
    if not revoked then
        retryable = false
        reason = tostring(reason) .. "; could not cancel teleport reload: " .. tostring(detail)
    end
    if retryable and self.attempts < self.config.teleportAttempts then
        self.phase, self.nextAttempt, self.fresh = phase, os.clock() + self.config.teleportRetryDelay, 0
        self.since = os.clock()
        self:status("Teleport failed; retrying in " .. self.config.teleportRetryDelay .. "s: " .. tostring(reason))
    else
        self:cancel()
        self.halt("Overnight travel stopped: " .. tostring(reason))
    end
end
function Overnight:depart()
    assert(game.PlaceId == Resume.HTC, "HTC cycling can only depart from HTC")
    self.session:check()
    self.phase, self.since, self.nextAttempt, self.attempts = "depart_ready", os.clock(), 0, 0
    self:status("HTC has one minute left; returning to Earth")
end
function Overnight:rejoin()
    self.session:check()
    assert(type(game.JobId) == "string" and game.JobId ~= "", "The current server ID is unavailable for HTC rejoin")
    self.phase, self.since, self.nextAttempt, self.attempts = "rejoin_ready", os.clock(), 0, 0
    self:status("Disconnected; returning directly to HTC")
end
function Overnight:resume(mode)
    assert((mode == "earth" and game.PlaceId == self.session.earthPlaceId)
        or ((mode == "train" or mode == "rejoin") and game.PlaceId == Resume.HTC), "Unexpected overnight destination")
    self.engine.timer:reset()
    self.engine.awaitFreshTimer = mode == "train"
    self.engine:transition("cycling", os.clock(), mode == "earth" and "Earth loaded; waiting for character and data"
        or "HTC loaded; waiting for training controls")
    self.phase, self.since, self.nextAttempt, self.attempts, self.fresh = mode == "earth" and "earth_loading" or "htc_loading",
        os.clock(), 0, 0, 0
end
function Overnight:sendTeleport(now, target, mode, phase, retryPhase, message)
    self.attempts, self.phase, self.since = self.attempts + 1, phase, now
    self.teleportTarget, self.teleportPhase, self.teleportRetryPhase = target, phase, retryPhase
    local token = self.token
    task.spawn(function()
        if not self:active() or self.token ~= token then return end
        local ok, reason = pcall(function()
            local teleport = game:GetService("TeleportService")
            if not self.failureConnection then
                self.failureConnection = teleport.TeleportInitFailed:Connect(function(player, _, detail, placeId)
                    if self:active() and self.phase == self.teleportPhase and player == self.player
                        and placeId == self.teleportTarget then self:failed(detail, true, self.teleportRetryPhase) end
                end)
            end
            self.session:prepare(target, mode)
            if not self:active() or self.token ~= token then self.session:cancel(); return end
            self:status(message)
            teleport:Teleport(target, self.player)
        end)
        if not ok and self:active() and self.token == token then self:failed(reason, true, retryPhase) end
    end)
end
function Overnight:characterReady()
    local char = self.player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if self.readyCharacter ~= char then self.readyCharacter, self.fresh = char, 0 end
    if not hum or hum.Health <= 2 or not char:FindFirstChild("HumanoidRootPart")
        or not char:FindFirstChild("AttackCheck") then return false end
    local gui = self.player:FindFirstChildOfClass("PlayerGui")
    local respawn = gui and gui:FindFirstChild("RespawnUI")
    return not (respawn and respawn:FindFirstChild("RespawnCanvas"))
end
function Overnight:step(now, snapshot)
    if not self:active() then return false end
    if now < (self.nextPoll or 0) then return true end
    self.nextPoll = now + 0.1
    if self.phase == "depart_ready" then
        if now >= self.nextAttempt then
            self:sendTeleport(now, self.session.earthPlaceId, "earth", "departing", "depart_ready", "Teleporting to Earth…")
        end
    elseif self.phase == "rejoin_ready" then
        if now >= self.nextAttempt then
            self:sendTeleport(now, Resume.HTC, "rejoin", "rejoining", "rejoin_ready", "Teleporting back into HTC…")
        end
    elseif self.phase == "departing" or self.phase == "rejoining" or self.phase == "entering" or self.phase == "checking_entry" then
        if now - self.since >= self.config.loadTimeout then
            if self.entry.busy then
                -- An InvokeServer call cannot be cancelled. Invalidate it and
                -- stop instead of creating another indefinitely yielding task.
                self:failed("Server entry request timed out", false)
            else
                self:failed("Teleport did not finish", true,
                    self.phase == "departing" and "depart_ready" or self.phase == "rejoining" and "rejoin_ready" or "earth_loading")
            end
        end
    else
        if now - self.since >= self.config.loadTimeout then
            self:failed("Character or game data did not finish loading", false)
            return true
        end
        if now < self.nextAttempt or now - self.since < self.config.loadWait then return true end
        local ready = self:characterReady()
        if self.phase == "earth_loading" then
            local data = self.player:FindFirstChild("Data")
            local storage = game:GetService("ReplicatedStorage")
            local timeCheck = storage:FindFirstChild("TimeCheck")
            ready = ready and data and data:FindFirstChild("Moneys") and timeCheck and timeCheck:IsA("RemoteFunction")
        else
            ready = ready and snapshot and snapshot.trainingKnown and snapshot.alive and snapshot.characterReady
                and snapshot.start and snapshot.startAllowed and not snapshot.respawnCanvas
        end
        self.fresh = ready and self.fresh + 1 or 0
        if self.fresh >= 3 then
            if self.phase == "earth_loading" then
                self.attempts, self.phase, self.since = self.attempts + 1, "checking_entry", now
                self.entry:request()
            else
                self.phase = nil
                self.engine:setActive(true, now)
                self.engine.mayAdopt = false
                self.engine.freshTimerSince = now
                self:status("HTC is ready; starting training again")
                return false
            end
        end
    end
    return true
end
function Overnight:destroy()
    self:cancel(); self.live = false; self.entry:destroy()
    if self.failureConnection then self.failureConnection:Disconnect(); self.failureConnection = nil end
end
return Overnight
