-- One queued loader per client, with a revocable, destination-specific ticket.
local Resume = {}
Resume.__index = Resume
Resume.HTC = 4178935231
Resume.EARTH = 14694717758 -- Earth destination supplied by the user.
local PATH = "DBFR_Lua/teleport.json"
local QUEUED = [[
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local env = type(getgenv) == "function" and getgenv() or _G
    local player = game:GetService("Players").LocalPlayer
    if not player or type(env.readfile) ~= "function" or type(env.writefile) ~= "function" then return end
    local http = game:GetService("HttpService")
    local ok, ticket = pcall(function() return http:JSONDecode(env.readfile("DBFR_Lua/teleport.json")) end)
    local origin = env.__DBFR_DEPARTURE
    if not ok or type(ticket) ~= "table" or ticket.active ~= true or ticket.target ~= game.PlaceId
        or (origin and origin.client == game and origin.player == player and origin.jobId == game.JobId
            and origin.issued == ticket.issued and origin.target == ticket.target and origin.mode == ticket.mode)
        or ticket.userId ~= player.UserId or type(ticket.issued) ~= "number"
        or os.time() - ticket.issued < 0 or os.time() - ticket.issued > 600 then return end
    -- Startup consumes the ticket only after the hub is constructed. A failed
    -- download can therefore be recovered by running the usual loader again.
    local compile = loadstring or env.loadstring
    assert(type(compile) == "function", "Saiyan Hub: teleport reload requires loadstring")
    local source = game:HttpGet("https://raw.githubusercontent.com/Zitely/DBFR-Script/main/http_loader.lua?t=" .. tostring(os.time()))
    assert(compile(source, "Saiyan Hub loader"))()
end)
]]
function Resume.new(env, player, earthPlaceId)
    return setmetatable({env = env, player = player, http = game:GetService("HttpService"),
        earthPlaceId = earthPlaceId or Resume.EARTH}, Resume)
end
function Resume.validPlace(id) return type(id) == "number" and id > 0 and id < math.huge and id % 1 == 0 end
function Resume:isArrival(ticket)
    local origin = self.env.__DBFR_DEPARTURE
    local stillDeparting = type(ticket) == "table" and origin and origin.client == game and origin.player == self.player
        and origin.jobId == game.JobId and origin.issued == ticket.issued
        and origin.target == ticket.target and origin.mode == ticket.mode
    return type(ticket) == "table" and ticket.active == true and ticket.target == game.PlaceId
        and not stillDeparting
        and ticket.userId == self.player.UserId
        and ((ticket.mode == "earth" and game.PlaceId == self.earthPlaceId)
            or ((ticket.mode == "train" or ticket.mode == "rejoin" or ticket.mode == "manual") and game.PlaceId == Resume.HTC))
        and type(ticket.issued) == "number" and os.time() - ticket.issued >= 0 and os.time() - ticket.issued <= 600
end
function Resume:readArrival()
    if type(self.env.readfile) == "function" then
        local ok, ticket = pcall(function() return self.http:JSONDecode(self.env.readfile(PATH)) end)
        if ok and self:isArrival(ticket) then return ticket end
    end
    -- Compatibility with an already-queued 1.6.0 loader, which consumed the
    -- file before downloading and passed this one-use global instead.
    local legacy = self.env.__DBFR_TELEPORT_RESUME
    if self:isArrival(legacy) then return legacy end
end
function Resume:consumeArrival(ticket)
    assert(self:isArrival(ticket), "Invalid teleport continuation")
    assert(type(self.env.writefile) == "function", "Teleport continuation requires executor file storage")
    self.env.writefile(PATH, self.http:JSONEncode({active = false}))
    self.env.__DBFR_TELEPORT_RESUME = nil
    self.env.__DBFR_DEPARTURE = nil
    -- Some executors preserve globals across places, but consume their queue.
    self.env.__DBFR_RELOAD_QUEUED = nil
end
function Resume:queueFunction()
    local env = self.env
    return env.queue_on_teleport or env.queueonteleport
        or (type(env.syn) == "table" and env.syn.queue_on_teleport)
        or (type(env.fluxus) == "table" and env.fluxus.queue_on_teleport)
end
function Resume:check()
    assert(type(self:queueFunction()) == "function", "Overnight travel requires executor teleport-queue support")
    assert(type(self.env.writefile) == "function" and type(self.env.readfile) == "function"
        and type(self.env.makefolder) == "function", "Overnight travel requires executor file storage")
end
function Resume:prepare(target, mode)
    self:check()
    assert(Resume.validPlace(target), "Earth destination is unknown; run the hub on Earth first")
    if mode ~= "manual" then
        assert(Resume.validPlace(self.earthPlaceId) and self.earthPlaceId ~= Resume.HTC,
            "Earth destination is unknown; run the hub on Earth first")
    end
    pcall(self.env.makefolder, "DBFR_Lua") -- Existing folders may raise an error.
    local ticket = {active = true, target = target, mode = mode, userId = self.player.UserId,
        issued = os.time(), earthPlaceId = self.earthPlaceId,
        sourceJobId = type(game.JobId) == "string" and game.JobId ~= "" and game.JobId or nil}
    -- Keep the departure identity in this client's memory. A fresh client can
    -- resume even if matchmaking sends it back to the same server/place.
    self.env.__DBFR_DEPARTURE = {client = game, player = self.player, jobId = game.JobId,
        issued = ticket.issued, target = target, mode = mode}
    self.env.writefile(PATH, self.http:JSONEncode(ticket))
    local check = self.http:JSONDecode(self.env.readfile(PATH))
    assert(type(check) == "table" and check.active and check.target == target and check.mode == mode,
        "Teleport ticket could not be saved")
    if not self.env.__DBFR_RELOAD_QUEUED then
        local ok, reason = pcall(self:queueFunction(), QUEUED)
        if not ok then self:cancel(); error("Teleport queue failed: " .. tostring(reason), 0) end
        self.env.__DBFR_RELOAD_QUEUED = true
    end
    return true
end
function Resume:cancel()
    self.env.__DBFR_TELEPORT_RESUME = nil
    self.env.__DBFR_DEPARTURE = nil
    if type(self.env.writefile) == "function" then
        local ok, reason = pcall(function() self.env.writefile(PATH, self.http:JSONEncode({active = false})) end)
        return ok, reason
    end
    return true
end
return Resume
