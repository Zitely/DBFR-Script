local Timer = {}
Timer.__index = Timer

function Timer.new() return setmetatable({}, Timer) end
function Timer:reset()
    self.raw, self.rawAt, self.trusted, self.trustedAt = nil, nil, nil, nil
end
function Timer.parse(text)
    if type(text) ~= "string" then return nil end
    local h, m, s = text:match("(%d+):(%d%d):(%d%d)")
    h, m, s = tonumber(h), tonumber(m), tonumber(s)
    if not h or h > 2 or m > 59 or s > 59 then return nil end
    return h * 3600 + m * 60 + s
end
function Timer:observe(value, now)
    if type(value) ~= "number" or value ~= value or value < 0 or value > 7200 then return false end
    local previous, elapsed = self.raw, now - (self.rawAt or now)
    self.raw, self.rawAt = value, now
    if not previous or previous - value < -1 or previous - value > math.max(5, elapsed + 5) then
        return false
    end
    self.trusted, self.trustedAt = value, now
    return true
end
function Timer:remaining(now)
    if self.trusted == nil then return nil end
    return math.max(0, self.trusted - (now - self.trustedAt))
end
function Timer.format(value)
    if value == nil then return "--:--:--" end
    value = math.max(0, math.floor(value))
    return string.format("%01d:%02d:%02d", math.floor(value / 3600), math.floor(value / 60) % 60, value % 60)
end
return Timer
