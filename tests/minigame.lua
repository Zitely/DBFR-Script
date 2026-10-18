return function(test, equal, mock)
    local Bindings = require("src.Bindings")
    local Rhythm = require("src.Rhythm")
    local Config = require("src.Config")
    local Main = require("src.Main")
    local function fixture()
        mock.reset()
        local main = mock.object("ScreenGui", "Main", mock.playerGui)
        local active = mock.object("BoolValue", "Active", main, {Value = true})
        mock.object("BoolValue", "UICoolDown", main, {Value = false})
        local frame = mock.object("Frame", "Frame", main)
        local buttons = mock.object("Folder", "Button Thing", main)
        mock.object("TextButton", "TextButton", mock.object("ScreenGui", "Start", buttons), {Text = "Start"})
        local characters = mock.object("Folder", "Characters", mock.playerGui)
        mock.object("BoolValue", "Resting", mock.object("Folder", "Interactions", characters), {Value = false})
        local attack = mock.object("Frame", "Attack", frame)
        local block = mock.object("Frame", "Block", frame)
        local ca = mock.object("TextLabel", "CounterA", frame, {Visible = false, Text = "25"})
        local cb = mock.object("TextLabel", "CounterB", frame, {Visible = false, Text = "25"})
        local input = {events = {}, down = function(self, key) self.events[#self.events + 1] = key end,
            up = function() end}
        return {main = main, active = active, frame = frame, attack = attack, block = block,
            ca = ca, cb = cb, b = Bindings.new(mock.player), input = input, r = Rhythm.new(Config.new(), input)}
    end
    local function note(parent, name, x)
        return mock.object("ImageLabel", name, parent, {Position = UDim2.fromScale(x, 0.5),
            AbsolutePosition = Vector2.new(1800, 900), Image = "rbxassetid://opaque"})
    end
    local function step(f, now)
        local s = f.b:snapshot(now)
        f.r:step(s.notes, s.challenge, now)
        return s
    end
    test("actual live lane names work at any resolution without templates or saved signatures", function()
        local f = fixture()
        workspace.CurrentCamera.ViewportSize = Vector2.new(2560, 1440)
        local keys = mock.object("Frame", "Keys", f.frame)
        note(mock.object("Frame", "A", keys), "MouseButton1", 1)
        note(mock.object("Frame", "B", keys), "Q", 1)
        note(mock.hud, "E", 1)
        equal(#f.b:snapshot(0).notes, 0)
        local a, b = note(f.attack, "MouseButton2", 0.7), note(f.block, "E", 0.7)
        step(f, 0.1); equal(f.r.attempts, 0)
        a.Position, b.Position = UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.97, 0.5)
        step(f, 0.2); equal(table.concat(f.input.events, ","), "right,e")
        a.Name, b.Name = "NC", "NC"
        equal(#step(f, 0.3).notes, 0); equal(f.r.attempts, 2)
        equal(next(f.r.held), nil); f.b:pause()
    end)
    test("normal notes use the game hit window immediately at every difficulty speed", function()
        for _, speed in ipairs({1.05, 1.1, 1.2, 1.4}) do
            local f = fixture()
            local n = note(f.block, "Q", 0.79)
            step(f, 0); equal(f.r.attempts, 0)
            for i = 1, 30 do
                n.Position = UDim2.fromScale(0.79 + speed * i / 60, 0.5)
                step(f, i / 60)
            end
            equal(f.r.attempts, 1); equal(f.input.events[1], "q")
            f.b:pause()
        end
        local f = fixture()
        note(f.attack, "MouseButton1", 1.19)
        step(f, 0); equal(f.r.attempts, 1) -- Joining late still has a valid window.
        f.b:pause()
        f = fixture(); note(f.attack, "MouseButton1", 1.2)
        step(f, 0); equal(f.r.attempts, 0); f.b:pause()
    end)
    test("only the rightmost unconsumed note in a lane may receive an input", function()
        local f = fixture()
        local early = note(f.attack, "MouseButton1", 0.97)
        local closest = note(f.attack, "MouseButton2", 1.05)
        step(f, 0); equal(table.concat(f.input.events, ","), "right")
        closest.Name = "NC"
        step(f, 0.05); equal(table.concat(f.input.events, ","), "right,left")
        early.Name = "NC"
        note(f.attack, "UnknownInput", 1.1)
        note(f.attack, "MouseButton2", 1)
        step(f, 0.1); equal(f.r.attempts, 2)
        f.b:pause()
    end)
    test("linked doubles capture both keys before the first input renames both objects NC", function()
        local f = fixture()
        local a, b = note(f.attack, "MouseButton1", 0.97), note(f.block, "E", 0.97)
        mock.object("ObjectValue", "Obj", a, {Value = b})
        mock.object("ObjectValue", "Obj", b, {Value = a})
        local waiting, success, firstAt
        f.input.down = function(self, key)
            self.events[#self.events + 1] = key
            if not waiting then
                equal(key, "left"); waiting, firstAt = "e", mock.now
                a.Name, b.Name = "NC", "NC"
            else
                equal(key, waiting); assert(mock.now - firstAt < 0.2); success = true
            end
        end
        step(f, 0); equal(success, true); equal(f.r.attempts, 2)
        step(f, 0.1); equal(f.r.attempts, 2); equal(next(f.r.held), nil)
        f.b:pause()
    end)
    test("a linked pair is sent together before unrelated simultaneous notes", function()
        local f = fixture()
        local partner, b = note(f.attack, "MouseButton1", 0.99), note(f.block, "Q", 0.99)
        local nearest = note(f.attack, "MouseButton2", 1.03)
        mock.object("ObjectValue", "Obj", partner, {Value = b})
        mock.object("ObjectValue", "Obj", b, {Value = partner})
        step(f, 0); equal(table.concat(f.input.events, ","), "q,left")
        -- Delayed GUI feedback must not cause the pair to be pressed twice.
        step(f, 0.05); equal(table.concat(f.input.events, ","), "q,left,right")
        partner.Name, b.Name, nearest.Name = "NC", "NC", "NC"
        step(f, 0.1); equal(f.r.attempts, 3); f.b:pause()
    end)
    test("invalid or consumed double partners cannot cause a lone half-hit", function()
        local f = fixture()
        local a = note(f.attack, "MouseButton1", 1)
        local link = mock.object("ObjectValue", "Obj", a)
        step(f, 0); equal(f.r.attempts, 0)
        local b = note(f.block, "NC", 1); link.Value = b
        step(f, 0.1); equal(f.r.attempts, 0)
        b.Name, b.Parent = "Q", mock.hud
        step(f, 0.2); equal(f.r.attempts, 0); f.b:pause()
    end)
    test("mash waits for its visible lane counter then completes 25 accepted inputs at 30 and 60 Hz", function()
        for _, fps in ipairs({30, 60}) do
            for _, data in ipairs({{"MouseButton2", "right", "attack", "ca"}, {"E", "e", "block", "cb"}}) do
                local f = fixture()
                local mash = note(f[data[3]], "mash", 0.9); mash:SetAttribute("Key", data[1])
                local decoration = note(mash, "mash", 1); decoration:SetAttribute("Key", "MouseButton1")
                step(f, 0); equal(f.r.attempts, 0)
                local counter, remaining = f[data[4]], 25
                f.input.down = function(_, key)
                    equal(key, data[2]); remaining = math.max(0, remaining - 1)
                    counter.Text = tostring(remaining)
                end
                counter.Visible = true; mash.Position = UDim2.fromScale(1, 0.5)
                step(f, 1); equal(remaining, 24) -- No previous-note or two-vote delay.
                for i = 1, math.floor(4.3 * fps) do
                    mash.Position = UDim2.fromScale(1 + i / fps, 0.5)
                    step(f, 1 + i / fps)
                end
                equal(remaining, 0); equal(f.r.done, true); equal(next(f.r.held), nil)
                assert(f.r.attempts >= 25 and f.r.attempts <= 27)
                f.b:pause()
            end
        end
    end)
    test("mash identity ignores nested clones and future notes and can change without four empty frames", function()
        local f = fixture()
        local mash = note(f.attack, "mash", 1); mash:SetAttribute("Key", "MouseButton2")
        local nested = note(mash, "mash", 5); nested:SetAttribute("Key", "MouseButton1")
        f.ca.Visible = true
        equal(step(f, 1).challenge.kind, "right")
        local future = note(f.attack, "mash", -1); future:SetAttribute("Key", "MouseButton1")
        mash.Position = UDim2.fromScale(4.9, 0.5)
        equal(step(f, 2).challenge.id, mash)
        f.ca.Text = "0"
        for i = 1, 3 do step(f, 2 + i * 0.1) end
        equal(f.r.done, true)
        mash:Destroy(); future.Position, f.ca.Text = UDim2.fromScale(1, 0.5), "25"
        local s = step(f, 2.4)
        equal(s.challenge.id, future); equal(f.r.spam.kind, "left"); equal(f.r.bursts, 2)
        f.b:pause()
    end)
    test("known inactive game never plays stale notes or hidden counters", function()
        local f = fixture()
        note(f.block, "Q", 1)
        local mash = note(f.attack, "mash", 2); mash:SetAttribute("Key", "MouseButton1")
        f.ca.Visible, f.active.Value = true, false
        local s = step(f, 0)
        equal(s.training, false); equal(#s.notes, 0); equal(s.challenge, nil); equal(f.r.attempts, 0)
        f.active.Value, f.frame.Visible = true, false
        s = step(f, 0.1); equal(s.training, false); equal(f.r.attempts, 0)
        f.b:pause()
    end)
    test("lane observers survive replacements and detach when Chamber is paused", function()
        local f = fixture()
        note(f.attack, "MouseButton1", 0.9)
        step(f, 0)
        local old = f.attack
        old:Destroy()
        f.attack = mock.object("Frame", "Attack", f.frame)
        local new = note(f.attack, "MouseButton2", 0.97)
        equal(step(f, 0.1).notes[1].id, new)
        for _, c in ipairs(old.DescendantAdded.listeners) do equal(c.Connected, false) end
        f.b:pause()
        for _, root in ipairs({f.attack, f.block}) do
            for _, signal in ipairs({root.DescendantAdded, root.DescendantRemoving}) do
                for _, c in ipairs(signal.listeners) do equal(c.Connected, false) end
            end
        end
        equal(next(f.b.gameNotes.lanes), nil)
        equal(f.b:snapshot(0.2).notes[1].id, new); f.b:pause()
    end)
    test("live lane reads bypass a 3000-label discovery backlog and never rescan it", function()
        local f = fixture()
        for i = 1, 3000 do mock.object("TextLabel", "Item" .. i, mock.hud, {Text = "inventory"}) end
        local n = note(f.block, "Q", 0.97)
        equal(step(f, 0).notes[1].id, n); equal(f.r.attempts, 1)
        for i = 1, 240 do f.b:snapshot(i / 60) end
        mock.resetMetrics(); f.b.gameNotes.reads = 0
        for i = 1, 120 do f.b:snapshot(4 + i / 60) end
        equal(mock.metrics.fullScans, 0); equal(mock.metrics.childrenReads, 0)
        equal(f.b.gameNotes.reads, 120)
        f.b:pause()
    end)
    test("enabling during a live round moves away from the hub before mouse input and unload releases it", function()
        local f = fixture()
        note(f.attack, "MouseButton1", 0.97)
        local app = Main.start()
        app.ui.window.AbsolutePosition, app.ui.window.AbsoluteSize = Vector2.new(20, 155), Vector2.new(350, 206)
        mock.uis.cursor = Vector2.new(100, 240)
        app.toggle()
        for i = 1, 20 do mock.tick(1 / 60) end
        equal(mock.vim.events[1][1], "move")
        assert(mock.uis.cursor.Y > 361)
        local found = false
        for _, e in ipairs(mock.vim.events) do if e[1] == "mouse" and e[3] then found = true end end
        equal(found, true)
        app.unload()
        for _, c in ipairs(f.attack.DescendantAdded.listeners) do equal(c.Connected, false) end
    end)
end
