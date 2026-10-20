return function(test, equal, mock)
    local Main = require("src.Main")
    local Resume = require("src.TeleportResume")
    local function compileIn(source, environment)
        if type(setfenv) == "function" then
            local fn = assert(loadstring(source)); setfenv(fn, environment); return fn
        end
        return assert(load(source, "queued teleport", "t", environment))
    end
    local function fixture(place, shared, ready)
        mock.reset()
        shared = shared or {files = {}, queues = {}, teleports = {}, fees = 0, starts = 0, cooldown = 120}
        shared.http = shared.http or mock.http
        mock.http, mock.services.HttpService = shared.http, shared.http
        game.PlaceId, mock.player.UserId = place, 17
        game.IsLoaded = function() return true end
        game.HttpGet = function(_, url)
            assert(url:find("/main/http_loader.lua", 1, true)); return "hub loader"
        end
        mock.env.writefile = function(path, value) shared.files[path] = value end
        mock.env.readfile = function(path) return assert(shared.files[path], "Missing file " .. path) end
        mock.env.makefolder = function() end
        mock.env.queue_on_teleport = function(source) shared.queues[#shared.queues + 1] = source end
        local teleport = {TeleportInitFailed = mock.signal()}
        teleport.Teleport = function(_, id, player)
            equal(player, mock.player); shared.teleports[#shared.teleports + 1] = id
        end
        mock.services.TeleportService = teleport
        mock.object("Part", "HumanoidRootPart", mock.character,
            {CFrame = CFrame.new(0, 0, 0), Position = Vector3.new(0, 0, 0)})
        if ready ~= false then mock.object("BoolValue", "AttackCheck", mock.character) end
        local data = mock.object("Folder", "Data", mock.player)
        local money = mock.object("IntValue", "Moneys", data, {Value = 180000})
        local timeCheck = mock.object("RemoteFunction", "TimeCheck", mock.replicatedStorage)
        timeCheck.InvokeServer = function(_, value) equal(value, 2); return shared.cooldown end
        local payment = mock.object("RemoteEvent", "NPCStuff", mock.object("Folder", "Remotes", mock.replicatedStorage))
        payment.FireServer = function(_, name)
            equal(name, "GravityChamberReEnterFee"); shared.fees = shared.fees + 1; money.Value = money.Value - 60000
        end
        local quest = mock.object("RemoteEvent", "GetQuest", mock.replicatedStorage)
        quest.FireServer = function(_, id) equal(id, 70) end
        local difficulty = mock.object("RemoteEvent", "DifficultySet", mock.replicatedStorage)
        difficulty.FireServer = function(_, value) equal(value, "Nightmare") end
        local main = mock.object("ScreenGui", "Main", mock.playerGui, {IgnoreGuiInset = true})
        local active = mock.object("BoolValue", "Active", main, {Value = false})
        mock.object("BoolValue", "UICoolDown", main, {Value = false})
        local frame = mock.object("Frame", "Frame", main)
        mock.object("Frame", "Attack", frame)
        local block = mock.object("Frame", "Block", frame)
        mock.object("ImageLabel", "Q", block, {Position = UDim2.fromScale(0.6, 0.5)})
        mock.object("TextLabel", "CounterA", frame, {Visible = false})
        mock.object("TextLabel", "CounterB", frame, {Visible = false})
        local buttons = mock.object("Folder", "Button Thing", main)
        mock.object("TextButton", "TextButton", mock.object("ScreenGui", "Start", buttons, {IgnoreGuiInset = true}),
            {Text = "Start", AbsolutePosition = Vector2.new(590, 90), AbsoluteSize = Vector2.new(100, 30)})
        local characters = mock.object("Folder", "Characters", mock.playerGui)
        mock.object("BoolValue", "Resting", mock.object("Folder", "Interactions", characters), {Value = false})
        local timer = mock.object("TextLabel", "TimeLeft", mock.hud, {Text = "1:59:59",
            AbsolutePosition = Vector2.new(1198, 692), AbsoluteSize = Vector2.new(75, 21)})
        local send = mock.vim.SendMouseButtonEvent
        mock.vim.SendMouseButtonEvent = function(self, x, y, button, down)
            send(self, x, y, button, down)
            if down and y >= 90 and y <= 120 then shared.starts = shared.starts + 1; active.Value = true end
        end
        return {shared = shared, timer = timer, active = active, main = main, money = money,
            teleport = teleport, timeCheck = timeCheck, payment = payment}
    end
    local function executeQueue(f, source)
        local sandbox = setmetatable({loadstring = function(code)
            equal(code, "hub loader")
            return function() f.app = Main.start() end
        end}, {__index = _G})
        compileIn(source, sandbox)(); mock.flush()
    end
    local function cross(f, place, ready)
        local source = f.shared.queues[#f.shared.queues]
        local nextWorld = fixture(place, f.shared, ready)
        executeQueue(nextWorld, source)
        assert(nextWorld.app, "Queued loader did not resume in the destination")
        return nextWorld
    end
    local function departure(f)
        f.active.Value = true
        f.app = Main.start(); f.app.toggle()
        f.timer.Text = "0:01:02"; mock.tick(0.1)
        f.timer.Text = "0:01:00"; mock.tick(1.3); mock.tick(0.2)
        equal(f.shared.teleports[#f.shared.teleports], Resume.EARTH)
    end
    local function readyTicks()
        mock.tick(7.1); mock.tick(0.2); mock.tick(0.2)
    end
    test("overnight completes Earth and HTC hops then waits for a fully loaded character before Start", function()
        local f = fixture(Resume.HTC)
        departure(f); equal(f.shared.fees, 0); equal(#f.shared.queues, 1)
        f = cross(f, Resume.EARTH)
        equal(f.app.ui.features.chamber.state.Text, "CYCLING")
        readyTicks()
        equal(f.shared.teleports[2], Resume.HTC); equal(f.shared.fees, 1); equal(#f.shared.queues, 2)
        equal(f.shared.starts, 0)
        f = cross(f, Resume.HTC, false)
        local deathUI = mock.object("ScreenGui", "RespawnUI", mock.playerGui)
        mock.object("CanvasGroup", "RespawnCanvas", deathUI)
        mock.humanoid.Health = 1
        readyTicks(); equal(f.shared.starts, 0); equal(mock.humanoid.Health, 1)
        mock.humanoid.Health = 100; mock.object("BoolValue", "AttackCheck", mock.character)
        mock.tick(0.2); equal(f.shared.starts, 0)
        deathUI:Destroy()
        mock.tick(0.2); mock.tick(0.2); equal(f.shared.starts, 0)
        mock.tick(0.2); equal(f.shared.starts, 1); equal(mock.player:GetAttribute("Difficulty"), "Nightmare")
        mock.tick(0.2); mock.tick(0.2); mock.tick(0.2); mock.tick(0.4)
        equal(f.app.ui.features.chamber.state.Text, "TRAINING")
        equal(#f.shared.teleports, 2)
        f.app.unload()
    end)
    test("a second completed overnight cycle renews its timer and pays at most one new fee", function()
        local f = fixture(Resume.HTC); departure(f)
        for round = 1, 2 do
            f = cross(f, Resume.EARTH); readyTicks()
            equal(f.shared.fees, round)
            f = cross(f, Resume.HTC); readyTicks()
            mock.tick(0.2); mock.tick(1.3)
            if round == 1 then
                -- Let the verified new timer count down to one minute.
                f.timer.Text = "0:01:00"; mock.tick(7138); mock.tick(0.2); mock.tick(0.2)
                equal(f.shared.teleports[#f.shared.teleports], Resume.EARTH)
            end
        end
        equal(#f.shared.teleports, 4); equal(f.shared.starts, 2)
        f.app.unload()
    end)
    test("an unchanged low timer after re-entry cannot cause repeated paid round trips", function()
        local f = fixture(Resume.HTC); departure(f)
        f = cross(f, Resume.EARTH); readyTicks(); f = cross(f, Resume.HTC)
        f.timer.Text = "0:00:30"; readyTicks(); mock.tick(1.3); mock.tick(1.3)
        equal(#f.shared.teleports, 2); equal(f.shared.fees, 1)
        mock.tick(151)
        equal(f.app.ui.features.chamber.state.Text, "PAUSED")
        assert(f.app.ui.features.chamber.status.Text:find("timer did not renew", 1, true))
        equal(#f.shared.teleports, 2); f.app.unload()
    end)
    test("Earth entry waits for data and insufficient Zeni stops without charging", function()
        local f = fixture(Resume.HTC); departure(f)
        f = cross(f, Resume.EARTH)
        f.money.Parent = nil; readyTicks(); equal(#f.shared.teleports, 1); equal(f.shared.fees, 0)
        f.money.Value = 59999; f.money.Parent = mock.player:FindFirstChild("Data")
        mock.tick(0.2); mock.tick(0.2); mock.tick(0.2)
        equal(#f.shared.teleports, 1); equal(f.shared.fees, 0)
        equal(f.app.ui.features.chamber.state.Text, "PAUSED")
        assert(f.app.ui.features.chamber.status.Text:find("60,000 Zeni", 1, true))
        equal(mock.http:JSONDecode(f.shared.files['DBFR_Lua/teleport.json']).active, false)
        f.app.unload()
    end)
    test("failed return teleport retries are bounded and never repeat its fee", function()
        local f = fixture(Resume.HTC); departure(f)
        f = cross(f, Resume.EARTH); readyTicks()
        for attempt = 1, 3 do
            f.teleport.TeleportInitFailed:Fire(mock.player, "Full", "Server full", Resume.HTC)
            if attempt < 3 then mock.tick(10.1); mock.tick(0.2); mock.tick(0.2) end
        end
        equal(f.shared.fees, 1); equal(#f.shared.teleports, 4)
        equal(f.app.ui.features.chamber.state.Text, "PAUSED")
        mock.tick(300); equal(#f.shared.teleports, 4)
        f.app.unload()
    end)
    test("failed Earth departure retries without sending training inputs", function()
        local f = fixture(Resume.HTC); departure(f)
        local inputCount = #mock.vim.events
        f.teleport.TeleportInitFailed:Fire(mock.player, "Full", "Server full", Resume.EARTH)
        mock.tick(10.1)
        equal(#f.shared.teleports, 2); equal(f.shared.teleports[2], Resume.EARTH)
        equal(#mock.vim.events, inputCount); equal(#f.shared.queues, 1)
        f.app.unload()
    end)
    test("pause revokes a queued cycle before arriving at Earth", function()
        local f = fixture(Resume.HTC); departure(f)
        local source = f.shared.queues[1]
        f.app.toggle()
        equal(mock.http:JSONDecode(f.shared.files['DBFR_Lua/teleport.json']).active, false)
        f = fixture(Resume.EARTH, f.shared); executeQueue(f, source)
        equal(f.app, nil); equal(#f.shared.teleports, 1)
    end)
    test("arrival queues the next hop even if executor globals survive and the folder exists", function()
        local f = fixture(Resume.HTC); departure(f)
        local source = f.shared.queues[1]
        f = fixture(Resume.EARTH, f.shared)
        mock.env.__DBFR_RELOAD_QUEUED = true
        mock.env.makefolder = function() error("Folder already exists") end
        executeQueue(f, source); readyTicks()
        equal(#f.shared.queues, 2); equal(f.shared.teleports[2], Resume.HTC)
        f.app.unload()
    end)
    test("failed ticket cancellation is reported and stops automatic retries", function()
        local f = fixture(Resume.HTC); departure(f)
        mock.env.writefile = function() error("Storage unavailable") end
        f.teleport.TeleportInitFailed:Fire(mock.player, "Full", "Server full", Resume.EARTH)
        equal(f.app.ui.features.chamber.state.Text, "PAUSED")
        assert(f.app.ui.features.chamber.status.Text:find("could not cancel teleport reload", 1, true))
        mock.tick(30); equal(#f.shared.teleports, 1)
        f.app.unload()
    end)
    test("pause during ticket persistence cancels before charging the entry fee", function()
        local f = fixture(Resume.HTC); departure(f); f = cross(f, Resume.EARTH)
        local write = mock.env.writefile
        mock.env.writefile = function(path, value)
            write(path, value)
            if path == "DBFR_Lua/teleport.json" and mock.http:JSONDecode(value).active then f.app.toggle() end
        end
        readyTicks()
        equal(f.shared.fees, 0); equal(#f.shared.teleports, 1)
        equal(mock.http:JSONDecode(f.shared.files["DBFR_Lua/teleport.json"]).active, false)
        f.app.unload()
    end)
    test("entry cancelled during a yielding cooldown check sends no payment or teleport", function()
        local f = fixture(Resume.HTC); departure(f); f = cross(f, Resume.EARTH)
        f.timeCheck.InvokeServer = function() f.app.toggle(); return 120 end
        readyTicks(); equal(f.shared.fees, 0); equal(#f.shared.teleports, 1)
        equal(mock.http:JSONDecode(f.shared.files['DBFR_Lua/teleport.json']).active, false)
        f.app.unload()
    end)
    test("missing teleport queue or storage stops before leaving HTC", function()
        for _, missing in ipairs({"queue_on_teleport", "writefile"}) do
            local f = fixture(Resume.HTC); mock.env[missing] = nil
            f.active.Value = true; f.timer.Text = "0:01:00"
            f.app = Main.start(); f.app.toggle(); mock.tick(0.1); mock.tick(1.3); mock.tick(0.2)
            equal(#f.shared.teleports, 0); equal(f.app.ui.features.chamber.state.Text, "PAUSED")
            assert(f.app.ui.features.chamber.status.Text:find("requires executor", 1, true))
            f.app.unload()
        end
    end)
    test("queued tickets are consumed once and reject wrong destination, user, and expiry", function()
        for _, invalid in ipairs({"target", "user", "expired", "none"}) do
            local f = fixture(Resume.HTC); departure(f)
            local source = f.shared.queues[1]
            local ticket = mock.http:JSONDecode(f.shared.files['DBFR_Lua/teleport.json'])
            if invalid == "target" then ticket.target = 99
            elseif invalid == "user" then ticket.userId = 99
            elseif invalid == "expired" then ticket.issued = os.time() - 601 end
            f.shared.files['DBFR_Lua/teleport.json'] = mock.http:JSONEncode(ticket)
            f = fixture(Resume.EARTH, f.shared); executeQueue(f, source)
            if invalid == "none" then
                assert(f.app); local original = f.app; executeQueue(f, source); equal(f.app, original)
                f.app.unload()
            else equal(f.app, nil) end
        end
    end)
    test("normal launch stays off and enabling on Earth starts the new round trip", function()
        local f = fixture(Resume.EARTH)
        f.app = Main.start(); readyTicks(); equal(#f.shared.teleports, 0)
        f.app.toggle(); readyTicks(); equal(f.shared.teleports[1], Resume.HTC); equal(f.shared.fees, 1)
        f.app.unload()
    end)
end
