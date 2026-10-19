local Timer = require("src.Timer")
local Engine = {}
Engine.__index = Engine

function Engine.new(config, log)
    return setmetatable({config = config, log = log or function() end, timer = Timer.new(),
        state = "paused", active = false, generation = 0, startCount = 0,
        recoveryCount = 0, reconnectCount = 0, sessions = 0, status = "Ready when you are",
        nextModal = 0, modalFrames = 0, fresh = 0}, Engine)
end
function Engine:transition(state, now, message)
    self.state, self.since, self.status = state, now, message
    self.log(message)
end
function Engine:setActive(enabled, now)
    self.generation = self.generation + 1
    self.active, self.pending = enabled, nil
    self.fresh, self.modalFrames, self.modalCandidate = 0, 0, false
    self.nextModal, self.nextRecovery = 0, now
    if enabled then
        self.startCount, self.recoveryCount, self.reconnectCount = 0, 0, 0
        self.requiresStart, self.nextStart = true, now
        self.mayAdopt = true
        self:transition("seeking", now, "Looking for the training Start button")
    else self:transition("paused", now, "Automation paused") end
end
function Engine:halt(now, why)
    self:setActive(false, now)
    self.status = why
    self.log(why)
end
function Engine:action(kind, now)
    if self.pending then return nil end
    local action = {kind = kind, generation = self.generation, created = now}
    self.pending = action
    return action
end
function Engine:waitForRespawn(now, message, readyAfter)
    self.requiresStart, self.fresh, self.mayAdopt = true, 0, false
    self:transition("respawning", now, message)
    self.readyAfter = readyAfter
end
function Engine:complete(action, ok, now, reason)
    if action ~= self.pending or action.generation ~= self.generation then return end
    self.pending = nil
    if not ok then
        self:halt(now, "Input stopped: " .. tostring(reason or "button unavailable"))
        return
    end
    if action.kind == "start" then
        self.startCount = self.startCount + 1
        self.requiresStart, self.fresh, self.mayAdopt = false, 0, false
        self.nextStart = now + self.config.startGrace
        self:transition("starting", now, "Start pressed; waiting for fresh training UI")
    elseif action.kind == "menu" then
        self.mayAdopt = false
        self:transition("respawn_menu", now, "Waiting for the menu's Respawn entry")
    elseif action.kind == "respawnShortcut" then
        self.mayAdopt = false
        self:transition("respawn_confirm", now, "Sent Escape then R; waiting for the Respawn confirmation")
    elseif action.kind == "respawn" then
        self:transition("respawn_confirm", now, "Waiting for the Respawn confirmation")
    elseif action.kind == "confirm" then
        self:waitForRespawn(now, "Waiting for your character to respawn", now + self.config.respawnWait)
    elseif action.kind == "reconnect" then
        self.mayAdopt = false
        self.reconnectCount = self.reconnectCount + 1
        self.timer:reset()
        self.nextReconnect = now + self.config.reconnectCooldown
        self:transition("reconnecting", now, "Reconnect pressed; waiting for the new session")
    end
end
function Engine:step(s, now)
    if not self.active then return nil end
    local c = self.config
    if s.timer ~= nil and now >= (self.nextTimer or 0) then
        self.timer:observe(s.timer, now)
        self.nextTimer = now + 1.2
    end
    -- Disconnects have priority in every active state, including respawn and AFK.
    if now >= self.nextModal then
        self.nextModal = now + c.reconnectPoll
        self.modalFrames = s.reconnect and self.modalFrames + 1 or 0
        self.modalCandidate = s.reconnect == true
    end
    if self.modalCandidate then
        if self.modalFrames >= 2 and self.state ~= "reconnecting" then
            self.generation = self.generation + 1
            self.pending, self.fresh = nil, 0
            self.reconnectCount, self.nextReconnect = 0, now
            self:transition("reconnecting", now, "Reconnect button confirmed")
        end
        if self.modalFrames >= 2 and not self.pending and c.autoReconnect and not c.dryRun then
            if now >= (self.nextReconnect or 0) then
                if self.reconnectCount >= c.reconnectAttempts then
                    self:halt(now, "Reconnect retry limit reached; check Roblox")
                else return self:action("reconnect", now) end
            end
        end
        return nil
    end
    if self.pending then return nil end
    if self.state == "reconnecting" then
        if now - self.since > c.loadTimeout then
            self:halt(now, "Reconnect loading timed out")
        elseif s.start then
            self.startCount, self.requiresStart, self.fresh = 0, true, 0
            self.nextStart = now + c.loadWait
            self:transition("loading", now, "Hub returned; allowing the character to load")
        end
        return nil
    end
    if self.state == "loading" and now - self.since > c.loadTimeout then
        self:halt(now, "The hub did not become ready")
        return nil
    end
    if self.state == "afk" then return nil end
    -- RespawnLocal creates PlayerGui.RespawnUI.RespawnCanvas on Humanoid.Died
    -- and removes it only after the new character has AttackCheck. It is an
    -- exact signal, so never keep clicking recovery controls through it.
    if s.respawnCanvas and self.state ~= "respawning" then
        self:waitForRespawn(now, "Respawn screen detected; waiting for your character", now)
        return nil
    end
    local remaining = self.timer:remaining(now)
    if remaining and remaining <= c.afkMinutes * 60 and c.afkMinutes > 0 then
        self:transition("afk", now, "HTC threshold reached; waiting for the Reconnect button")
        return nil
    end
    if self.state == "respawn_menu" then
        if s.respawn and not c.dryRun then return self:action("respawn", now) end
        if now - self.since > c.recoveryMenuWait then
            self.nextRecovery = now + c.recoveryRetryDelay
            self:transition("lost", now, "Respawn entry not visible; reopening the menu")
        end
        return nil
    elseif self.state == "respawn_confirm" then
        if s.confirm and not c.dryRun then return self:action("confirm", now) end
        if now - self.since > 4 then self:halt(now, "Respawn confirmation was not found") end
        return nil
    elseif self.state == "respawning" then
        if now - self.since > c.respawnTimeout then
            self:halt(now, "Respawn loading timed out")
        elseif not s.respawnCanvas and s.characterReady == false then
            self.fresh = 0
            self.status = "Waiting for the new character to finish loading"
        elseif not s.respawnCanvas and now >= self.readyAfter and s.alive and s.start
            and not s.confirm and s.startAllowed ~= false then
            self.fresh = self.fresh + 1
            if self.fresh >= 3 then
                self.startCount, self.nextStart, self.fresh = 0, now, 0
                self:transition("seeking", now, "Respawn finished; starting training again")
            end
        else self.fresh = 0 end
        return nil
    end
    -- The game's health gate is independent of whether icon names are known.
    -- Handle it before a still-visible Start can consume the retry budget.
    if s.trainingKnown and s.needsRecovery then
        self.fresh = 0
        if not c.autoRecover or c.dryRun then self.status = s.startBlocked; return nil end
        if self.recoveryCount >= c.recoveryAttempts then
            self:halt(now, "Recovery retry limit reached")
        elseif now >= (self.nextRecovery or 0) then
            self.recoveryCount = self.recoveryCount + 1
            self.requiresStart = true
            return self:action("respawnShortcut", now)
        end
        return nil
    end
    if s.trainingKnown and (s.alive == false or (not s.gameActive and s.startAllowed == false)) then
        self.status = s.startBlocked or "Waiting for the game to allow training"
        self.fresh = 0
        return nil
    end
    -- Start is authoritative even when scenery or old targets resemble training.
    if s.start then
        self.fresh, self.mayAdopt = 0, false
        if c.autoStart and not c.dryRun and now >= (self.nextStart or 0) then
            if self.startCount >= c.startAttempts then
                self:halt(now, "Start retry limit reached; check the game screen")
            else return self:action("start", now) end
        end
        return nil
    end
    -- A fresh toggle can join an existing minigame. Recovery/reconnect still
    -- require a new Start; stationary hit rings alone cannot authorize adoption.
    local adopt = self.mayAdopt and self.state == "seeking" and s.alive
        and (s.trainingKnown or #(s.notes or {}) > 0)
    if s.training and (not self.requiresStart or adopt) then
        self.fresh = self.fresh + 1
        if self.fresh >= 3 then
            self.requiresStart, self.mayAdopt = false, false
            self.lastTraining = now
            local message = s.trainingKnown and not s.bindingsReady
                and "Training detected; waiting for prompt recognition" or "Training active — ki flowing"
            if self.state ~= "training" then
                self.sessions = self.sessions + 1
                self.startCount, self.reconnectCount = 0, 0
                if not s.trainingKnown or s.bindingsReady then self.recoveryCount = 0 end
                self:transition("training", now, message)
            else self.status = message end
        end
    else self.fresh = 0 end
    if self.state == "training" and not s.training and now - (self.lastTraining or now) >= 2 then
        self:transition("lost", now, "Training UI disappeared; checking recovery")
    end
    local grace = self.state == "starting" and c.startGrace or 15
    local missing = self.state == "lost" and now - (self.lastTraining or now) >= c.lostSeconds
    local stalled = (self.state == "seeking" or self.state == "starting") and now - self.since >= grace
    if (missing or stalled) and c.autoRecover and not c.dryRun then
        if not s.bindingsReady and not s.trainingKnown then
            self:halt(now, "Chamber prompts were not recognized automatically; game compatibility needs an update")
        elseif self.recoveryCount >= c.recoveryAttempts then
            self:halt(now, "Recovery retry limit reached")
        elseif s.menu then
            self.recoveryCount = self.recoveryCount + 1
            self.requiresStart = true
            return self:action("menu", now)
        else self:halt(now, "Lines menu was not recognized; Chamber paused") end
    end
    return nil
end
function Engine:canPlay(snapshot)
    return self.active and self.state == "training" and not self.pending and not self.modalCandidate
        and not snapshot.start and not self.config.dryRun
        and (not snapshot.trainingKnown or snapshot.training)
end
return Engine
