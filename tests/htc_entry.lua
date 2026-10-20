return function(test, equal, mock)
    local Main = require("src.Main")
    local function fixture(remaining, balance)
        mock.reset()
        game.PlaceId = 123
        local calls, queued = {}, {}
        local timeCheck = mock.object("RemoteFunction", "TimeCheck", mock.replicatedStorage)
        timeCheck.InvokeServer = function(_, mode)
            equal(mode, 2); calls[#calls + 1] = "check"
            return remaining
        end
        local remotes = mock.object("Folder", "Remotes", mock.replicatedStorage)
        local payment = mock.object("RemoteEvent", "NPCStuff", remotes)
        payment.FireServer = function(_, action)
            equal(action, "GravityChamberReEnterFee"); calls[#calls + 1] = "pay"
        end
        local quest = mock.object("RemoteEvent", "GetQuest", mock.replicatedStorage)
        quest.FireServer = function(_, id) equal(id, 70); calls[#calls + 1] = "quest" end
        local data = mock.object("Folder", "Data", mock.player)
        local money = mock.object("IntValue", "Moneys", data, {Value = balance or 0})
        local teleports = {TeleportInitFailed = mock.signal()}
        teleports.Teleport = function(_, id, player)
            equal(id, 4178935231); equal(player, mock.player); calls[#calls + 1] = "teleport"
        end
        mock.services.TeleportService = teleports
        mock.env.queue_on_teleport = function(source) queued[#queued + 1] = source end
        local app = Main.start()
        local function click() app.ui.controls.enterHTC.button.Activated:Fire() end
        return {app = app, hub = app.features, calls = calls, queued = queued, click = click,
            timeCheck = timeCheck, payment = payment, quest = quest, money = money, teleports = teleports,
            status = function() return app.ui.controls.enterHTC.status.Text end}
    end
    test("manual HTC entry without cooldown never requests payment", function()
        local f = fixture(0, 0)
        equal(#f.calls, 0); mock.tick(30); equal(#f.calls, 0)
        f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,teleport"); equal(#f.queued, 1)
        equal(f.app.ui.features.chamber.state.Text, "PAUSED")
        assert(f.status():find("reload queued", 1, true))
        f.app.unload()
    end)
    test("manual bypass checks funds then pays and requests quest before teleport", function()
        local f = fixture(120, 60000)
        f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,pay,quest,teleport")
        assert(mock.now >= 0.2)
        f.app.unload()
    end)
    test("insufficient funds and invalid cooldowns never pay or teleport", function()
        for _, remaining in ipairs({0 / 0, math.huge, -1, "120", false, 120}) do
            local f = fixture(remaining, 59999)
            f.click(); mock.flush(); equal(table.concat(f.calls, ","), "check")
            assert(f.status():find("Entry failed", 1, true)); equal(#f.queued, 0)
            f.app.unload()
        end
        local f = fixture(nil, 60000)
        f.click(); mock.flush(); equal(table.concat(f.calls, ","), "check"); f.app.unload()
    end)
    test("missing quest or cooldown remotes fail before any fee request", function()
        local f = fixture(120, 60000)
        f.quest:Destroy(); f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check"); assert(f.status():find("Missing GetQuest", 1, true))
        f.app.unload()
        f = fixture(0, 60000)
        f.timeCheck:Destroy(); f.click(); mock.flush(); equal(#f.calls, 0)
        assert(f.status():find("Missing TimeCheck", 1, true)); f.app.unload()
    end)
    test("rapid and yielding repeat clicks issue one payment and teleport", function()
        local f = fixture(120, 60000)
        local original = f.timeCheck.InvokeServer
        f.timeCheck.InvokeServer = function(...)
            f.click(); f.click()
            return original(...)
        end
        f.click(); f.click(); mock.flush(); f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,pay,quest,teleport")
        equal(#f.queued, 1); f.app.unload()
    end)
    test("teleport failure permits manual retry without paying twice", function()
        local f = fixture(120, 60000)
        f.click(); mock.flush()
        f.teleports.TeleportInitFailed:Fire(mock.player, "Failure", "Server full", 4178935231)
        assert(f.status():find("Server full", 1, true))
        f.money.Value = 0; f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,pay,quest,teleport,check,quest,teleport")
        equal(#f.queued, 1)
        f.app.unload()
        for _, listener in ipairs(f.teleports.TeleportInitFailed.listeners) do equal(listener.Connected, false) end
    end)
    test("a payment call error cannot produce a second fee on retry", function()
        local f = fixture(120, 60000)
        f.payment.FireServer = function() f.calls[#f.calls + 1] = "pay"; error("connection lost") end
        f.click(); mock.flush(); equal(table.concat(f.calls, ","), "check,pay")
        mock.tick(2); f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,pay,check,quest,teleport")
        f.app.unload()
    end)
    test("starting Chamber or unloading during cooldown lookup cancels entry", function()
        for _, unload in ipairs({false, true}) do
            local f = fixture(120, 60000)
            f.timeCheck.InvokeServer = function()
                f.calls[#f.calls + 1] = "check"
                if unload then f.app.unload() else f.app.toggle() end
                return 120
            end
            f.click(); mock.flush(); equal(table.concat(f.calls, ","), "check"); equal(#f.queued, 0)
            f.app.unload()
        end
    end)
    test("death or cancellation during paid-entry wait prevents late teleport", function()
        local f = fixture(120, 60000)
        mock.waitHook = function() mock.humanoid.Health = 0 end
        f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,pay,quest")
        assert(f.status():find("cancelled", 1, true)); equal(#f.queued, 0)
        f.app.unload()
    end)
    test("HTC button is inert while already inside or when automation is active", function()
        local f = fixture(120, 60000)
        game.PlaceId = 4178935231; f.click(); mock.flush(); equal(#f.calls, 0)
        equal(f.status(), "Already inside HTC")
        game.PlaceId = 123; f.hub:set("meditate", true); f.click(); mock.flush(); equal(#f.calls, 0)
        f.hub:set("meditate", false); f.app.toggle(); f.click(); mock.flush(); equal(#f.calls, 0)
        f.app.unload()
    end)
    test("entry still works without teleport-queue support and explains reloading", function()
        local f = fixture(0, 0)
        mock.env.queue_on_teleport = nil
        f.click(); mock.flush()
        equal(table.concat(f.calls, ","), "check,teleport")
        assert(f.status():find("run your loader", 1, true)); f.app.unload()
    end)
    test("queued manual entry reloads the hub without enabling Chamber", function()
        local f = fixture(0, 0)
        f.click(); mock.flush()
        local compilations = 0
        local sandbox = setmetatable({game = {
            IsLoaded = function() return true end,
            HttpGet = function(_, url)
                assert(url:find("/main/http_loader.lua", 1, true)); return "loader code"
            end,
        }, loadstring = function(code)
            equal(code, "loader code"); compilations = compilations + 1
            return function() end
        end}, {__index = _G})
        local fn
        if type(setfenv) == "function" then
            fn = assert(loadstring(f.queued[1], "queued reload")); setfenv(fn, sandbox)
        else fn = assert(load(f.queued[1], "queued reload", "t", sandbox)) end
        fn(); mock.flush(); equal(compilations, 1); equal(mock.env.__DBFR_AUTORESUME, nil)
        f.app.unload()
    end)
end
