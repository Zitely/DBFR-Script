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
    if not ok or type(ticket) ~= "table" or ticket.active ~= true or ticket.target ~= game.PlaceId
        or ticket.userId ~= player.UserId or type(ticket.issued) ~= "number"
        or os.time() - ticket.issued < 0 or os.time() - ticket.issued > 600 then return end
    -- Consume before loading: duplicate queue callbacks cannot start two hubs.
    local consumed = pcall(function() env.writefile("DBFR_Lua/teleport.json", http:JSONEncode({active = false})) end)
    if not consumed then warn("Saiyan Hub: could not consume teleport ticket"); return end
    -- Some executors preserve globals across places, but consume their queue.
    env.__DBFR_RELOAD_QUEUED = nil
    env.__DBFR_TELEPORT_RESUME = ticket
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
        issued = os.time(), earthPlaceId = self.earthPlaceId}
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
    if type(self.env.writefile) == "function" then
        local ok, reason = pcall(function() self.env.writefile(PATH, self.http:JSONEncode({active = false})) end)
        return ok, reason
    end
    return true
end
return Resume
