return function(test, equal, mock)
    local Bindings = require("src.Bindings")
    local Engine = require("src.Engine")
    local Config = require("src.Config")
    local function fixture()
        mock.reset()
        local main = mock.object("ScreenGui", "Main", mock.playerGui)
        local active = mock.object("BoolValue", "Active", main, {Value = false})
        local cooldown = mock.object("BoolValue", "UICoolDown", main, {Value = false})
        local frame = mock.object("Frame", "Frame", main, {Visible = false})
        local buttons = mock.object("Folder", "Button Thing", main)
        local startGui = mock.object("ScreenGui", "Start", buttons)
        local start = mock.object("TextButton", "TextButton", startGui, {Text = "Train"})
        local characters = mock.object("Folder", "Characters", mock.playerGui)
        local interactions = mock.object("Folder", "Interactions", characters)
        local resting = mock.object("BoolValue", "Resting", interactions, {Value = false})
        local menu = mock.object("ScreenGui", "Menu", mock.playerGui)
        mock.object("ImageButton", "MenuButton", menu)
        local b = Bindings.new(mock.player)
        local e = Engine.new(Config.new()); e:setActive(true, 0)
        return {main = main, active = active, cooldown = cooldown, frame = frame,
            start = start, startGui = startGui, resting = resting, b = b, e = e}
    end
    test("DBFR flags and exact Start path override generic labels and legacy scenery", function()
        local f = fixture()
        local s = f.b:snapshot(0)
        equal(s.trainingKnown, true); equal(s.start, true); equal(s.controls.start, f.start)
        equal(s.training, false); equal(s.startAllowed, true)
        f.active.Value, f.frame.Visible = true, true
        s = f.b:snapshot(0.01)
        equal(s.start, false); equal(s.training, true); equal(s.bindingsReady, false)
        for i = 1, 3 do f.e:step(s, i * 0.1) end
        equal(f.e.state, "training"); equal(f.e:canPlay(s), true)
        assert(f.e.status:find("waiting for prompt recognition"))
        f.active.Value = false
        s = f.b:snapshot(0.04)
        equal(s.training, false); equal(f.e:canPlay(s), false)
        equal(f.e:step(s, 0.4).kind, "start")
        f.b:pause()
    end)
    test("low health opens recovery before Start even when no prompt icons were recognized", function()
        for _, health in ipairs({1, 2}) do
            local f = fixture()
            mock.humanoid.Health = health
            local s = f.b:snapshot(0)
            equal(s.alive, true); equal(s.start, true); equal(s.startAllowed, false)
            equal(s.bindingsReady, false); equal(s.needsRecovery, true)
            local action = f.e:step(s, 0)
            equal(action.kind, "menu"); equal(f.e.startCount, 0); equal(f.e.recoveryCount, 1)
            equal(f.e:canPlay(s), false)
            f.b:pause()
        end
    end)
    test("a running minigame remains valid at health 2 but stops at the controller's health 1 threshold", function()
        local f = fixture()
        f.active.Value, f.frame.Visible = true, true
        mock.humanoid.Health = 2
        local s = f.b:snapshot(0)
        equal(s.training, true); equal(s.needsRecovery, false)
        for i = 1, 3 do f.e:step(s, i * 0.1) end
        mock.humanoid.Health = 1
        s = f.b:snapshot(0.4)
        equal(s.training, false); equal(f.e:canPlay(s), false)
        equal(f.e:step(s, 0.4).kind, "menu")
        f.b:pause()
    end)
    test("cooldown resting and missing character state wait without spending Start or recovery attempts", function()
        for _, condition in ipairs({"cooldown", "resting", "missing", "dead"}) do
            local f = fixture()
            if condition == "cooldown" then f.cooldown.Value = true
            elseif condition == "resting" then f.resting.Value = true
            elseif condition == "missing" then f.resting:Destroy()
            else mock.humanoid.Health = 0; f.active.Value = true end
            for i = 0, 20 do equal(f.e:step(f.b:snapshot(i), i), nil) end
            equal(f.e.active, true); equal(f.e.startCount, 0); equal(f.e.recoveryCount, 0)
            assert(f.e.status:find("Waiting"))
            if condition == "missing" then
                f.resting = mock.object("BoolValue", "Resting", mock.playerGui:FindFirstChild("Characters"):FindFirstChild("Interactions"), {Value = false})
            end
            f.cooldown.Value, f.resting.Value, f.active.Value, mock.humanoid.Health = false, false, false, 100
            equal(f.e:step(f.b:snapshot(21), 21).kind, "start")
            f.b:pause()
        end
    end)
    test("respawn readiness needs health above 2 and cleared cooldown before a fresh Start", function()
        local f = fixture()
        mock.humanoid.Health = 1
        local a = f.e:step(f.b:snapshot(0), 0); equal(a.kind, "menu"); f.e:complete(a, true, 1)
        a = f.e:step({respawn = true}, 2); f.e:complete(a, true, 3)
        a = f.e:step({confirm = true}, 4); f.e:complete(a, true, 5)
        mock.humanoid.Health = 2
        for i = 13, 16 do equal(f.e:step(f.b:snapshot(i), i), nil) end
        equal(f.e.state, "respawning")
        mock.humanoid.Health, f.cooldown.Value = 100, true
        for i = 17, 20 do equal(f.e:step(f.b:snapshot(i), i), nil) end
        equal(f.e.state, "respawning")
        f.cooldown.Value = false
        for i = 21, 23 do f.e:step(f.b:snapshot(i), i) end
        equal(f.e.state, "seeking"); equal(f.e.requiresStart, true)
        equal(f.e:step(f.b:snapshot(24), 24).kind, "start")
        f.b:pause()
    end)
    test("recognized game state without known prompts cannot reset the recovery limit", function()
        local f = fixture()
        for attempt = 1, 3 do
            f.active.Value, f.frame.Visible, mock.humanoid.Health = false, false, 100
            local at = (attempt - 1) * 20
            local action = f.e:step(f.b:snapshot(at), at)
            equal(action.kind, "start"); f.e:complete(action, true, at + 1)
            f.active.Value, f.frame.Visible = true, true
            for i = 1, 3 do f.e:step(f.b:snapshot(at + 1 + i), at + 1 + i) end
            equal(f.e.recoveryCount, attempt - 1)
            mock.humanoid.Health, f.active.Value, f.frame.Visible = 1, false, false
            action = f.e:step(f.b:snapshot(at + 5), at + 5)
            if attempt < 3 then
                equal(action.kind, "menu"); f.e:complete(action, true, at + 6)
                action = f.e:step({respawn = true}, at + 7); f.e:complete(action, true, at + 8)
                action = f.e:step({confirm = true}, at + 9); f.e:complete(action, true, at + 10)
                mock.humanoid.Health = 100
                for i = 1, 3 do f.e:step(f.b:snapshot(at + 18 + i * 0.1), at + 18 + i * 0.1) end
            else
                equal(action, nil); equal(f.e.active, false)
                equal(f.e.status, "Recovery retry limit reached")
            end
        end
        f.b:pause()
    end)
    test("recreated character and Main flags are read without holding stale references", function()
        local f = fixture()
        equal(f.b:snapshot(0).startAllowed, true)
        f.active:Destroy()
        local replacement = mock.object("BoolValue", "Active", f.main, {Value = true})
        f.frame.Visible = true
        equal(f.b:snapshot(0.01).training, true)
        mock.player.Character = mock.object("Model", "NewCharacter", workspace)
        mock.object("Humanoid", "Humanoid", mock.player.Character, {Health = 1})
        replacement.Value = false
        equal(f.b:snapshot(0.02).needsRecovery, true)
        f.b:pause()
    end)
end
