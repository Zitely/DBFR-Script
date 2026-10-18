local Rhythm = {}
Rhythm.__index = Rhythm

function Rhythm.new(config, input)
    return setmetatable({config = config, input = input, tracks = {}, held = {},
        attempts = 0, bursts = 0, spam = nil, clear = 0, zero = 0}, Rhythm)
end
function Rhythm:release()
    local errors = {}
    for kind in pairs(self.held) do
        local ok, reason = pcall(self.input.up, self.input, kind)
        if not ok then errors[#errors + 1] = tostring(reason) else self.held[kind] = nil end
    end
    if #errors > 0 then error(table.concat(errors, "; ")) end
end
function Rhythm:reset()
    self:release()
    self.tracks, self.spam, self.done, self.clear, self.zero = {}, nil, nil, 0, 0
    self.releaseAt, self.nextPulse = nil, nil
end
function Rhythm:press(kinds, now, hold)
    for _, kind in ipairs(kinds) do
        self.held[kind] = true -- Retain for release even if a backend partially fails.
        self.input:down(kind)
        self.attempts = self.attempts + 1
    end
    self.releaseAt = now + hold / 1000
end
function Rhythm:step(notes, challenge, now)
    if self.releaseAt and now >= self.releaseAt then
        self:release()
        self.releaseAt = nil
        self.nextPulse = now + self.config.spamGapMs / 1000
    end
    local visible = challenge and challenge.visible and challenge.kind
    if self.done then
        self.clear = visible and 0 or self.clear + 1
        if self.clear >= 4 then self.done, self.clear = nil, 0 end
        return
    end
    if self.spam then
        self.clear = visible and 0 or self.clear + 1
        self.zero = visible and challenge.count == 0 and self.zero + 1 or 0
        if self.zero >= 3 or self.clear >= 4 then
            self:release()
            self.done, self.spam, self.releaseAt = self.zero >= 3, nil, nil
            self.clear, self.zero = 0, 0
            return
        end
        if not self.releaseAt and now >= (self.nextPulse or 0) and self.spam.count < self.config.spamMaxPresses then
            self:press({self.spam.kind}, now, self.config.spamHoldMs)
            self.spam.count = self.spam.count + 1
        end
        return
    end
    if visible and challenge.count == 0 then self.done = true; return end
    if visible then
        self:release()
        self.releaseAt, self.nextPulse = nil, now
        self.spam, self.tracks = {kind = challenge.kind, count = 0}, {}
        self.bursts = self.bursts + 1
        return self:step(notes, challenge, now)
    end
    local due, seen = {}, {}
    for _, n in ipairs(notes or {}) do
        seen[n.id] = true
        local t = self.tracks[n.id]
        if not t or n.x < t.x - 50 or n.kind ~= t.kind then
            t = {x = n.x, at = now, kind = n.kind, observed = 0, first = now}
            self.tracks[n.id] = t
        end
        local elapsed = now - t.at
        if elapsed > 0 then
            local speed = (n.x - t.x) / elapsed
            if speed > 60 and speed < 900 then t.speed = t.speed and t.speed * 0.3 + speed * 0.7 or speed end
            t.observed = t.observed + 1
        end
        t.x, t.at = n.x, now
        if t.speed and t.observed >= 2 and now - t.first >= 0.03 and not t.fired then
            local eta = ((n.target or 1025) - n.x) / t.speed + self.config.timingOffsetMs / 1000
            if eta <= 0 and eta > -0.15 and not self.releaseAt then
                due[n.kind], t.fired = true, true
            end
        end
    end
    for id, t in pairs(self.tracks) do if not seen[id] and now - t.at > 0.6 then self.tracks[id] = nil end end
    local kinds = {}
    for _, kind in ipairs({"left", "right", "q", "e"}) do if due[kind] then kinds[#kinds + 1] = kind end end
    if #kinds > 0 then self:press(kinds, now, self.config.holdMs) end
end
return Rhythm
