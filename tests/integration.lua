return function(test, equal, mock)
    local Bindings = require("src.Bindings")
    local Input = require("src.Input")
    local Config = require("src.Config")
    local function at(x, y, w, h)
        return {AbsolutePosition = Vector2.new(x, y), AbsoluteSize = Vector2.new(w or 40, h or 28)}
    end
    test("GUI scanner finds Start, timer, lines menu, and both Respawn buttons", function()
        mock.reset()
        local start = mock.object("TextButton", "Training", mock.hud, at(585, 97, 115, 24)); start.Text = "Start"
        mock.object("ImageButton", "MenuButton", mock.hud, at(40, 5, 50, 35))
        local entry = mock.object("TextButton", "Entry", mock.hud, at(20, 380)); entry.Text = "Respawn"
        local confirm = mock.object("TextButton", "Confirmation", mock.hud, at(550, 310)); confirm.Text = "Respawn"
        local timer = mock.object("TextLabel", "Clock", mock.hud, at(1198, 692, 75, 21)); timer.Text = "1:36:22"
        local b = Bindings.new(mock.player)
        local s = b:snapshot(0)
        assert(s.start and s.menu and s.respawn and s.confirm)
        equal(s.timer, 5782); equal(s.controls.respawn, entry); equal(s.controls.confirm, confirm)
    end)
    test("GUI scanner recognizes the native CoreGui hamburger menu", function()
        mock.reset()
        local hamburger = mock.object("ImageButton", "TopLeftIcon", mock.coreGui, at(40, 5, 50, 35))
        local b = Bindings.new(mock.player)
        equal(b:snapshot(0).controls.menu, hamburger)
    end)
    test("CoreGui menu detection uses the fixed-pixel Roblox top bar", function()
        mock.reset()
        workspace.CurrentCamera.ViewportSize = Vector2.new(2560, 1440)
        local hamburger = mock.object("ImageButton", "TopBarMenu", mock.coreGui, at(8, 8, 48, 48))
        local b = Bindings.new(mock.player)
        equal(b:snapshot(0).controls.menu, hamburger)
    end)
    test("known Roblox overlay path takes priority for its Respawn button", function()
        mock.reset()
        local current = mock.coreGui
        for _, name in ipairs({"TopBarApp", "TopBarApp", "UnibarLeftFrame", "UnibarMenu", "SubMenuHost", "nine_dot", "ScrollingFrame", "MainCanvas"}) do
            current = mock.object("Frame", name, current)
        end
        local respawn = mock.object("TextButton", "respawn", current, at(640, 360))
        local b = Bindings.new(mock.player)
        local sample
        for index = 0, 100 do sample = b:snapshot(index * 0.1) end
        equal(sample.controls.respawn, respawn)
    end)
    test("hidden controls and our own UI never trigger detection", function()
        mock.reset()
        local hidden = mock.object("Frame", "Hidden", mock.hud, {Visible = false})
        mock.object("TextButton", "Start", hidden, {Text = "Start"})
        local own = mock.object("ScreenGui", "Own", mock.playerGui)
        mock.object("TextButton", "Reconnect", own, {Text = "Reconnect"})
        local b = Bindings.new(mock.player, {}, own)
        local s = b:snapshot(0)
        equal(s.start, false); equal(s.reconnect, false)
    end)
    test("automatic image signatures distinguish sprites within a shared atlas", function()
        mock.reset()
        local icon = mock.object("ImageLabel", "MouseButton1", mock.hud, at(600, 526))
        icon.Image, icon.ImageRectOffset, icon.ImageRectSize = "rbxassetid://123", Vector2.new(5, 10), Vector2.new(20, 20)
        local b = Bindings.new(mock.player); b:refresh(0)
        equal(b:kind(icon), "left")
        local other = mock.object("ImageLabel", "Other", mock.hud, at(700, 526))
        other.Image, other.ImageRectOffset, other.ImageRectSize = icon.Image, Vector2.new(25, 10), icon.ImageRectSize
        equal(b:kind(other), nil)
    end)
    test("saved GUI paths resolve after GUI recreation and reject duplicate siblings", function()
        mock.reset()
        local button = mock.object("ImageButton", "Lines", mock.hud)
        local b = Bindings.new(mock.player, {menu = {root = "PlayerGui", path = {"HUD", "Lines"}}}); b:refresh(0)
        button:Destroy()
        local replacement = mock.object("ImageButton", "Lines", mock.hud)
        equal(b:resolve(b.saved.menu), replacement)
        mock.object("ImageButton", "Lines", mock.hud)
        equal(b:resolve(b.saved.menu), nil)
    end)
    test("counter 20 remains active and zero is parsed as exact zero", function()
        mock.reset()
        local note = mock.object("TextLabel", "Note", mock.hud, at(750, 526)); note.Text = "Q"
        note.AbsolutePosition = Vector2.new(750, 598)
        local count = mock.object("TextLabel", "Count", mock.hud, at(985, 598)); count.Text = "20"
        local b = Bindings.new(mock.player)
        b:snapshot(0)
        local s = b:snapshot(0.1)
        equal(s.challenge.kind, "q"); equal(s.challenge.count, 20)
        count.Text = "0"; s = b:snapshot(0.2); equal(s.challenge.count, 0)
    end)
    test("CoreGui access failure is recorded without breaking PlayerGui detection", function()
        mock.reset(); mock.coreGui.denyRead = true
        mock.object("TextButton", "Start", mock.hud, {Text = "Start"})
        local b = Bindings.new(mock.player)
        equal(b:snapshot(0).start, true); equal(#b.errors, 1)
    end)
    test("challenge remembers the nearest prompt while later icons change", function()
        mock.reset()
        local near = mock.object("TextLabel", "Near", mock.hud, at(900, 526)); near.Text = "LMB"
        local far = mock.object("TextLabel", "Far", mock.hud, at(600, 526)); far.Text = "RMB"
        local count = mock.object("TextLabel", "Count", mock.hud, at(985, 526)); count.Text = "25"
        local b = Bindings.new(mock.player)
        equal(b:snapshot(0).challenge, nil)
        equal(b:snapshot(0.1).challenge.kind, "left")
        near:Destroy(); count.Text = "15"
        equal(b:snapshot(8).challenge.kind, "left")
        count.Text = "0"; equal(b:snapshot(9).challenge.count, 0)
    end)
    test("smooth UI input moves before pressing and releases after holding", function()
        mock.reset()
        local input = Input.new({})
        local target = mock.object("TextButton", "Start", mock.hud, at(600, 100, 80, 30))
        input:click(target, Config.new(), function() return true end, false)
        local events = mock.vim.events
        equal(events[1][1], "move")
        equal(events[#events - 1][1], "mouse"); equal(events[#events - 1][3], true)
        equal(events[#events][3], false)
        equal(events[#events][4], 640); equal(events[#events][5], 115)
        assert(mock.now >= 1.17); equal(next(input.held), nil)
    end)
    test("click adds GUI inset exactly once when the screen uses it", function()
        mock.reset(); mock.hud.IgnoreGuiInset = false
        local input = Input.new({})
        local target = mock.object("TextButton", "Start", mock.hud, at(600, 100, 80, 30))
        input:click(target, Config.new(), function() return true end, false)
        equal(mock.uis.cursor.Y, 151)
    end)
    test("cancelling during a click hold releases the mouse", function()
        mock.reset()
        local input = Input.new({})
        local target = mock.object("TextButton", "Start", mock.hud, at(600, 100))
        local ok = pcall(input.click, input, target, Config.new(), function() return mock.now < 1.13 end, false)
        equal(ok, false); equal(next(input.held), nil)
        local events = mock.vim.events
        equal(events[#events][1], "mouse"); equal(events[#events][3], false)
    end)
    test("a button disappearing during approach cancels before mouse-down", function()
        mock.reset()
        local input = Input.new({})
        local target = mock.object("TextButton", "Start", mock.hud, at(600, 100))
        mock.waitHook = function() if mock.now > 0.3 then target.Visible = false end end
        equal(pcall(input.click, input, target, Config.new(), function() return true end, false), false)
        for _, event in ipairs(mock.vim.events) do assert(event[1] ~= "mouse") end
    end)
    test("a successful Start may hide its button during the mouse hold", function()
        mock.reset()
        local input = Input.new({})
        local target = mock.object("TextButton", "Start", mock.hud, at(600, 100))
        mock.waitHook = function() if mock.now > 1.12 then target.Visible = false end end
        input:click(target, Config.new(), function() return true end, true)
        equal(next(input.held), nil)
        assert(mock.now >= 2.6)
    end)
    test("Chamber button controls automation independently of window shortcuts", function()
        mock.reset()
        local app = require("src.Main").start()
        equal(app.version, "1.2.6"); equal(#app.ui.order, 1)
        local row = app.ui.features.chamber
        equal(row.state.Text, "PAUSED")
        mock.uis.InputBegan:Fire({KeyCode = Enum.KeyCode.F6}, false)
        mock.tick(); equal(row.state.Text, "PAUSED")
        row.button.Activated:Fire()
        mock.tick(0.25); equal(row.state.Text, "SEEKING")
        mock.uis.InputBegan:Fire({KeyCode = Enum.KeyCode.F7}, false)
        mock.tick(0.25); equal(row.state.Text, "SEEKING")
        app.ui.minimizeButton.Activated:Fire()
        equal(row.row.Visible, false); equal(app.ui.window.Size.Y.Offset, 65)
        mock.tick(0.4); equal(row.state.Text, "SEEKING")
        equal(row.row.Visible, false)
        mock.uis.InputBegan:Fire({KeyCode = Enum.KeyCode.RightShift}, false)
        equal(app.ui.window.Visible, false)
        mock.tick(0.4); equal(row.state.Text, "SEEKING")
        mock.uis.InputBegan:Fire({KeyCode = Enum.KeyCode.RightShift}, false)
        equal(app.ui.window.Visible, true); equal(row.row.Visible, true)
        equal(app.ui.minimized, false)
        row.button.Activated:Fire(); equal(row.state.Text, "PAUSED")
        equal(app.ui.window.Visible, true)
        app.unload(); equal(mock.env.__DBFR_APP, nil); equal(app.ui.gui.Parent, nil)
        for _, connection in ipairs(mock.runService.Heartbeat.listeners) do equal(connection.Connected, false) end
    end)
    test("visibility shortcut ignores processed input and focused text fields", function()
        mock.reset()
        local app = require("src.Main").start()
        local key = {KeyCode = Enum.KeyCode.RightShift}
        mock.uis.InputBegan:Fire(key, true); equal(app.ui.window.Visible, true)
        mock.uis.GetFocusedTextBox = function() return {} end
        mock.uis.InputBegan:Fire(key, false); equal(app.ui.window.Visible, true)
        mock.uis.GetFocusedTextBox = function() return nil end
        mock.uis.InputBegan:Fire(key, false); equal(app.ui.window.Visible, false)
        equal(app.ui.features.chamber.state.Text, "PAUSED")
        app.unload()
    end)
    test("exit during a held click releases input and disconnects the application", function()
        mock.reset()
        mock.object("TextButton", "Start", mock.hud, {Text = "Start",
            AbsolutePosition = Vector2.new(600, 100), AbsoluteSize = Vector2.new(80, 30)})
        local app = require("src.Main").start()
        app.toggle()
        mock.waitHook = function()
            if mock.now > 1.12 and app.ui.gui.Parent then app.ui.closeButton.Activated:Fire() end
        end
        mock.tick(0.01)
        equal(mock.env.__DBFR_APP, nil); equal(app.ui.gui.Parent, nil)
        local down, lastMouse = false, nil
        for _, event in ipairs(mock.vim.events) do
            if event[1] == "mouse" then down = down or event[3]; lastMouse = event end
        end
        assert(down, "Exit should interrupt an actual held click")
        equal(lastMouse[3], false)
        for _, signal in ipairs({mock.runService.Heartbeat, mock.uis.InputBegan,
            mock.uis.InputChanged, mock.uis.InputEnded, mock.playerGui.DescendantAdded}) do
            for _, c in ipairs(signal.listeners) do equal(c.Connected, false) end
        end
        mock.resetMetrics()
        mock.tick(); equal(mock.metrics.typeChecks, 0); equal(mock.metrics.childrenReads, 0)
    end)
    test("running the bundle twice replaces the previous UI without duplicate loops", function()
        mock.reset()
        local first = assert(loadfile("dist/chamber.lua"))()
        local second = assert(loadfile("dist/chamber.lua"))()
        equal(first.ui.gui.Parent, nil); assert(second.ui.gui.Parent)
        local connected = 0
        for _, c in ipairs(mock.runService.Heartbeat.listeners) do if c.Connected then connected = connected + 1 end end
        equal(connected, 1)
        connected = 0
        for _, c in ipairs(mock.uis.InputBegan.listeners) do if c.Connected then connected = connected + 1 end end
        equal(connected, 1); second.unload()
    end)
    test("root loader starts the dashboard without HTTP or loadstring", function()
        mock.reset()
        local downloads = 0
        game.HttpGet = function()
            downloads = downloads + 1
            error("404: Not Found")
        end
        local compile = loadstring
        loadstring = nil
        local ok, app = pcall(function() return assert(loadfile("loader.lua"))() end)
        loadstring = compile
        assert(ok, app)
        equal(app.version, "1.2.6"); equal(app.ui.window.Visible, true)
        equal(downloads, 0)
        mock.tick(); equal(app.ui.features.chamber.state.Text, "PAUSED")
        app.unload()
    end)
    test("the hub supports adding an independent feature without extra key binds", function()
        mock.reset()
        local app = require("src.Main").start()
        local called = 0
        app.ui.minimizeButton.Activated:Fire()
        local extra = app.ui:addFeature("example", "EXAMPLE", function() called = called + 1 end)
        equal(extra.row.Visible, false); equal(app.ui.window.Size.Y.Offset, 65)
        app.ui.minimizeButton.Activated:Fire()
        equal(extra.row.Visible, true); equal(app.ui.features.chamber.row.Visible, true)
        equal(app.ui.window.Size.Y.Offset, 336)
        extra.button.Activated:Fire(); equal(called, 1)
        equal(app.ui.features.chamber.state.Text, "PAUSED")
        equal(#app.ui.order, 2); equal(#mock.uis.InputBegan.listeners, 1)
        app.unload()
    end)
    test("teleport reload queues once and pause revokes the saved resume request", function()
        mock.reset()
        local files = {['DBFR_Lua/chamber.lua'] = string.rep("-", 200)}
        local queued = {}
        mock.env.writefile = function(path, value) files[path] = value end
        mock.env.readfile = function(path) return assert(files[path], "No cached file") end
        mock.env.makefolder = function() end
        mock.env.queue_on_teleport = function(source) queued[#queued + 1] = source end
        files['DBFR_Lua/settings.json'] = mock.http:JSONEncode({config = {resumeAfterTeleport = true}})
        local app = require("src.Main").start()
        app.toggle()
        equal(#queued, 1)
        equal(mock.http:JSONDecode(files['DBFR_Lua/settings.json']).resumeRequested, true)
        app.toggle()
        equal(mock.http:JSONDecode(files['DBFR_Lua/settings.json']).resumeRequested, false)
        app.toggle(); equal(#queued, 1)
        app.unload()
        equal(mock.http:JSONDecode(files['DBFR_Lua/settings.json']).resumeRequested, false)
    end)
    test("automatic attributes identify prompts without calibration", function()
        mock.reset()
        local prompt = mock.object("ImageLabel", "Icon", mock.hud, at(700, 598))
        prompt:SetAttribute("KeyCode", "Enum.KeyCode.Q")
        local b = Bindings.new(mock.player)
        local sample = b:snapshot(0)
        equal(#sample.notes, 1); equal(sample.notes[1].kind, "q")
        prompt:SetAttribute("KeyCode", "Enum.KeyCode.E")
        sample = b:snapshot(0.1)
        equal(sample.notes[1].kind, "e")
        b:pause()
    end)
    test("recovery can open the menu before all four prompt types have appeared", function()
        mock.reset()
        local note = mock.object("TextLabel", "Note", mock.hud, at(750, 598)); note.Text = "Q"
        mock.object("ImageButton", "MenuButton", mock.hud, at(40, 5, 50, 35))
        local b = Bindings.new(mock.player)
        local s = b:snapshot(0)
        equal(s.bindingsReady, true)
        local e = require("src.Engine").new(Config.new())
        e:setActive(true, 0)
        local start = e:step({start = true}, 0); e:complete(start, true, 1)
        for i = 1, 3 do e:step(s, 1 + i * 0.1) end
        note:Destroy()
        e:step(b:snapshot(4), 4)
        local action = e:step(b:snapshot(10), 10)
        equal(action.kind, "menu")
        b:pause()
    end)
end
