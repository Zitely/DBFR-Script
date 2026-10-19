local Config = {}

Config.defaults = {
    timingOffsetMs = -40, holdMs = 38, spamHoldMs = 20, spamGapMs = 20,
    spamMaxPresses = 125, afkMinutes = 35, lostSeconds = 8,
    respawnWait = 8, respawnTimeout = 45, startGrace = 8,
    reconnectCooldown = 9, reconnectPoll = 2, reconnectAttempts = 3,
    loadWait = 7, loadTimeout = 150, startAttempts = 3, recoveryAttempts = 2,
    approachMs = 900, hoverMs = 180, clickHoldMs = 90,
    autoReconnect = true, autoRecover = true, autoStart = true,
    dryRun = false, resumeAfterTeleport = false,
}

Config.ranges = {
    timingOffsetMs = {-250, 250}, holdMs = {10, 150}, spamHoldMs = {10, 100},
    spamGapMs = {10, 200}, spamMaxPresses = {25, 250}, afkMinutes = {0, 119},
    lostSeconds = {3, 60}, respawnWait = {3, 30}, respawnTimeout = {30, 120},
    startGrace = {3, 30}, reconnectCooldown = {3, 60}, reconnectPoll = {0.5, 10},
    reconnectAttempts = {1, 10}, loadWait = {3, 30}, loadTimeout = {30, 300},
    startAttempts = {1, 10}, recoveryAttempts = {1, 5}, approachMs = {200, 2000},
    hoverMs = {50, 1000}, clickHoldMs = {30, 300},
}

function Config.new(saved)
    local out = {}
    for k, v in pairs(Config.defaults) do out[k] = v end
    for k, v in pairs(saved or {}) do
        if type(v) == type(out[k]) then
            local range = Config.ranges[k]
            if range and v == v and v ~= math.huge and v ~= -math.huge then
                out[k] = math.max(range[1], math.min(range[2], v))
            elseif type(v) == "boolean" then out[k] = v end
        end
    end
    return out
end

return Config
