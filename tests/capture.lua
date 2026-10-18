return function(test, equal, mock)
    local Capture = require("src.Capture")
    test("standalone capture records incoming arguments and game GUI without sending inputs", function()
        mock.reset()
        local remote = mock.object("RemoteEvent", "Minigame", mock.replicatedStorage)
        remote.FireServer = function() error("Capture must not send to server") end
        local gui = mock.object("ScreenGui", "MainFrame", mock.playerGui, {IgnoreGuiInset = true})
        local note = mock.object("ImageLabel", "Prompt", gui, {Image = "rbxassetid://42",
            AbsolutePosition = Vector2.new(500, 600), AbsoluteSize = Vector2.new(30, 30)})
        note:SetAttribute("Key", "Q")
        local files, clipboard = {}, nil
        mock.env.makefolder = function() end
        mock.env.writefile = function(path, value) files[path] = value end
        mock.env.setclipboard = function(value) clipboard = value end
        local capture = assert(loadfile("dist/capture_minigame.lua"))()
        remote.OnClientEvent:Fire({{2, 0.3}, {2, 0.3}}, nil, "test")
        mock.tick(0.01)
        note.AbsolutePosition = Vector2.new(560, 600)
        mock.tick(0.2)
        mock.tick(30)
        equal(mock.env.__DBFR_CAPTURE, nil)
        equal(files["DBFR_Lua/minigame_capture.json"], clipboard)
        local report = mock.http:JSONDecode(clipboard)
        equal(report.remoteFound, true); equal(#report.events, 1)
        equal(report.events[1].argumentCount, 3)
        equal(report.events[1].arguments[2].type, "nil")
        equal(report.events[1].arguments[3], "test")
        local values = report.events[1].arguments[1].entries[1].value.entries
        equal(values[1].value, 2); equal(values[2].value, 0.3)
        local object = report.objects[1]
        equal(object.path, "Players.LocalPlayer.PlayerGui.MainFrame.Prompt")
        equal(object.samples[1].image, "rbxassetid://42"); equal(object.samples[1].attributes.Key, "Q")
        equal(object.samples[2].position[1], 560)
        equal(object.removedAt, nil)
        equal(#mock.vim.events, 0)
        for _, signal in ipairs({remote.OnClientEvent, mock.runService.Heartbeat, gui.DescendantAdded}) do
            for _, c in ipairs(signal.listeners) do equal(c.Connected, false) end
        end
        remote.OnClientEvent:Fire("late"); equal(#report.events, 1)
        equal(next(capture.index.records), nil)
    end)
    test("capture handles missing or later-created UI and remote and bounds discovery", function()
        mock.reset()
        local capture = Capture.start()
        equal(capture.report.remoteFound, false)
        local gui = mock.object("ScreenGui", "MainFrame", mock.playerGui)
        for i = 1, 3000 do mock.object("TextLabel", "Item" .. i, gui, {Text = "inventory"}) end
        local remote = mock.object("RemoteEvent", "Minigame", mock.replicatedStorage)
        mock.resetMetrics(); mock.tick(1.1)
        equal(capture.report.remoteFound, true)
        assert(capture.index.lastWork <= 96); equal(mock.metrics.fullScans, 0)
        gui:Destroy()
        local replacement = mock.object("ScreenGui", "MainFrame", mock.playerGui)
        mock.object("TextButton", "Respawn", replacement, {Text = "Respawn"})
        mock.tick(1.1)
        -- Cancelled discovery jobs also obey the per-frame work budget.
        for i = 1, 5 do mock.tick(0.1) end
        local found = false
        for _, object in ipairs(capture.report.objects) do
            if object.path == "Players.LocalPlayer.PlayerGui.MainFrame.Respawn" then found = true end
        end
        assert(found, "Replacement GUI was not captured")
        capture.stop(false)
    end)
    test("capture replaces an older listener and bounds cyclic or excessive event payloads", function()
        mock.reset()
        local remote = mock.object("RemoteEvent", "Minigame", mock.replicatedStorage)
        local old = Capture.start()
        local capture = Capture.start()
        local payload = {}; payload.self = payload
        for i = 1, 30 do remote.OnClientEvent:Fire(payload) end
        equal(#old.report.events, 0); equal(#capture.report.events, 24)
        equal(capture.report.truncated.events, true)
        equal(capture.report.events[1].arguments[1].entries[1].value.type, "cycle")
        capture.stop(false)
        for _, c in ipairs(remote.OnClientEvent.listeners) do equal(c.Connected, false) end
    end)
end
