return function(test, equal, mock)
    local Main = require("src.Main")
    local function fixture()
        mock.reset()
        local calls, daily = {}, {}
        local template = mock.object("ScreenGui", "MilkMission", mock.object("Folder", "Quests", mock.replicatedStorage))
        local controller = mock.object("LocalScript", "LocalScript", mock.object("Frame", "Main",
            mock.object("Frame", "Quest", mock.object("Frame", "Nested", template))))
        local rewards = mock.object("Folder", "Rewards", controller)
        for _, name in ipairs({"DragonStones", "Zeni", "SuperDragon"}) do mock.object("IntValue", name, rewards, {Value = 1}) end
        mock.object("BoolValue", "QuestCompleted", controller, {Value = false})
        local remote = mock.object("RemoteEvent", "QuestOne", mock.object("Folder", "Remotes", mock.replicatedStorage))
        remote.FireServer = function(_, ...) calls[#calls + 1] = {...} end
        local getQuest = mock.object("RemoteEvent", "GetQuest", mock.replicatedStorage)
        getQuest.FireServer = function(_, name) daily[#daily + 1] = name end
        local stones = mock.object("IntValue", "SuperDragonStones", mock.object("Folder", "Data", mock.player), {Value = 15})
        local shop = mock.object("Frame", "DragonStoneShop", mock.object("Frame", "Info", mock.object("Frame", "StatsFrame",
            mock.object("ScreenGui", "PlaceHolder", mock.playerGui))))
        local amount = mock.object("TextLabel", "AmountText", shop, {Text = "Stones: 15"})
        local currency = mock.object("TextLabel", "Amount", mock.object("Frame", "SDSCurrency", shop), {Text = "15"})
        local app = Main.start()
        return {app = app, hub = app.features, calls = calls, daily = daily, stones = stones,
            amount = amount, currency = currency, remote = remote, getQuest = getQuest, rewards = rewards}
    end
    local function input(f, id, value)
        local control = f.app.ui.controls[id]
        control.input.Text = value
        control.input.FocusLost:Fire(true)
    end
    test("Dragon Stones text boxes send entered values once per enable and clean up their clone", function()
        local f = fixture()
        equal(f.hub.enabled.dragonStones, nil); mock.tick(30); equal(#f.calls, 0)
        input(f, "questName", "  MilkMission  "); input(f, "questDragonStones", "42")
        input(f, "questZeni", "1200"); input(f, "questSuperStones", "7")
        f.app.ui.controls.dragonStones.button.Activated:Fire(); mock.tick()
        equal(#f.calls, 3)
        equal(table.concat(f.calls[1], ","), "Complete,MilkMission")
        equal(table.concat(f.calls[2], ","), "MilkMission,Complete")
        equal(table.concat(f.calls[3], ","), "MilkMission")
        local clone = mock.playerGui:FindFirstChild("MilkMission")
        local rewards = clone:FindFirstChild("Rewards", true)
        equal(rewards:FindFirstChild("DragonStones").Value, 42)
        equal(rewards:FindFirstChild("Zeni").Value, 1200); equal(rewards:FindFirstChild("SuperDragon").Value, 7)
        equal(clone:FindFirstChild("QuestCompleted", true).Value, true)
        equal(f.rewards:FindFirstChild("DragonStones").Value, 1)
        mock.tick(120); equal(#f.calls, 3)
        f.hub:set("dragonStones", false); equal(clone.Parent, nil)
        f.hub:set("dragonStones", true); mock.tick(); equal(#f.calls, 6)
        f.app.unload(); equal(mock.playerGui:FindFirstChild("MilkMission"), nil)
    end)
    test("invalid textbox values and missing quests do not send requests", function()
        local f = fixture()
        for _, value in ipairs({"", "-1", "1.5", "nan", "inf", "1e99", "2147483648"}) do
            input(f, "questDragonStones", value)
            f.hub:set("dragonStones", true); mock.tick()
            equal(f.hub.enabled.dragonStones, nil); equal(#f.calls, 0)
        end
        input(f, "questDragonStones", "0"); input(f, "questName", "   ")
        f.hub:set("dragonStones", true); equal(f.hub.enabled.dragonStones, nil)
        input(f, "questName", "MissingQuest"); f.hub:set("dragonStones", true); mock.tick()
        equal(#f.calls, 0); assert(f.app.ui.controls.dragonStones.status.Text:find("Quest not found", 1, true))
        f.app.unload()
    end)
    test("turning off or a failed send stops the rest of a quest request batch", function()
        for _, fails in ipairs({false, true}) do
            local f = fixture()
            f.remote.FireServer = function(_, ...)
                f.calls[#f.calls + 1] = {...}
                if fails then error("Server unavailable") else f.hub:set("dragonStones", false) end
            end
            f.hub:set("dragonStones", true); mock.tick(); mock.tick(30)
            equal(#f.calls, 1)
            f.app.unload()
        end
    end)
    test("Super Dragon Stones locks local value and sends one bounded daily batch", function()
        local f = fixture()
        input(f, "superStoneTarget", "500")
        f.hub:set("superStones", true); mock.tick()
        equal(f.stones.Value, 500); equal(f.amount.Text, "Stones: 500"); equal(f.currency.Text, "500")
        equal(f.daily[1], "OkraDaily")
        for i = 1, 14 do mock.tick(0.51) end
        equal(#f.daily, 12); equal(f.daily[12], "ChipDaily")
        local seen = {}; for _, name in ipairs(f.daily) do assert(not seen[name]); seen[name] = true end
        f.stones.Value = 25; f.amount.Text = "Stones: 25"; f.currency.Text = "25"
        mock.tick(0.51); equal(f.stones.Value, 500)
        f.hub:set("superStones", false)
        equal(f.stones.Value, 25); equal(f.amount.Text, "Stones: 25"); equal(f.currency.Text, "25")
        mock.tick(30); equal(#f.daily, 12)
        f.app.unload()
    end)
    test("Super Dragon Stones handles data and UI replacement and stops on unload", function()
        local f = fixture(); f.hub:set("superStones", true); mock.tick()
        local old = f.stones; old.Parent = nil
        local replacement = mock.object("IntValue", "SuperDragonStones", mock.player:FindFirstChild("Data"), {Value = 45})
        local parent = f.currency.Parent; f.currency:Destroy()
        local label = mock.object("TextLabel", "Amount", parent, {Text = "45"})
        mock.resetMetrics(); mock.tick(0.51)
        equal(old.Value, 15); equal(replacement.Value, 999999); equal(label.Text, "999999")
        equal(mock.metrics.fullScans, 0)
        f.app.unload(); equal(replacement.Value, 45); equal(label.Text, "45")
        local count = #f.daily; mock.tick(30); equal(#f.daily, count)
    end)
    test("Super Dragon Stones can lock locally without a daily remote", function()
        local f = fixture(); f.getQuest:Destroy()
        f.hub:set("superStones", true); mock.tick()
        equal(f.stones.Value, 999999); equal(#f.daily, 0)
        assert(f.app.ui.controls.superStones.status.Text:find("GetQuest unavailable", 1, true))
        f.app.unload(); equal(f.stones.Value, 15)
    end)
    test("stone fields persist but toggles remain off after a fresh launch", function()
        local f = fixture()
        local files = {}
        mock.env.makefolder = function() end
        mock.env.readfile = function(path) return assert(files[path]) end
        mock.env.writefile = function(path, value) files[path] = value end
        input(f, "questDragonStones", "83"); input(f, "superStoneTarget", "700")
        f.hub:set("superStones", true); mock.tick(); f.app.unload()
        local app = Main.start()
        equal(app.ui.controls.questDragonStones.input.Text, "83")
        equal(app.ui.controls.superStoneTarget.input.Text, "700")
        equal(app.features.enabled.dragonStones, nil); equal(app.features.enabled.superStones, nil)
        equal(f.stones.Value, 15); app.unload()
    end)
end
