local Config = require("src.Config")
local Engine = require("src.Engine")
local Rhythm = require("src.Rhythm")
local Bindings = require("src.Bindings")
local Input = require("src.Input")
local UI = require("src.UI")
local Main = {}

function Main.start()
    local env = type(getgenv) == "function" and getgenv() or _G
    if env.__DBFR_APP then env.__DBFR_APP.unload() end
    local player = game:GetService("Players").LocalPlayer
    assert(player, "Run Chamber from the local Roblox client")
    local http = game:GetService("HttpService")
    local storage = "DBFR_Lua/settings.json"
    local saved = {}
    if type(env.readfile) == "function" then
        local ok, data = pcall(function() return http:JSONDecode(env.readfile(storage)) end)
        if ok and type(data) == "table" then saved = data end
    end
    local config = Config.new(type(saved.config) == "table" and saved.config or {})
    local ui, engine, bindings, rhythm
    local input = Input.new(env)
    local live, bindingToken, queueRegistered = true, 0, false
    local actionRunning, nextEngine, nextUI = false, 0, 0
    local reportedBindingErrors = {}
    local connections = {}
    local function log(message)
        print("[Chamber Lua] " .. tostring(message))
        if ui then ui:log(message) end
    end
    local function save()
        if type(env.writefile) ~= "function" or type(env.makefolder) ~= "function" then return false end
        local ok, err = pcall(function()
            pcall(env.makefolder, "DBFR_Lua")
            env.writefile(storage, http:JSONEncode({version = 1, config = config, bindings = bindings.saved,
                resumeRequested = engine.active and config.resumeAfterTeleport}))
        end)
        if not ok then log("Settings could not be saved: " .. tostring(err)) end
        return ok
    end
    local function release()
        local ok, reason = pcall(rhythm.reset, rhythm)
        local released, detail = pcall(input.releaseAll, input)
        if not ok or not released then log("Input release needs attention: " .. tostring(reason or detail)) end
    end
    local function registerQueue()
        if not config.resumeAfterTeleport or queueRegistered then return end
        local queue = env.queue_on_teleport or env.queueonteleport
            or (type(env.syn) == "table" and env.syn.queue_on_teleport)
        if type(queue) ~= "function" then log("This executor has no teleport queue; reload after joining manually"); return end
        if type(env.readfile) ~= "function" then log("Teleport reload requires the loader and executor file storage"); return end
        local hasSource, source = pcall(env.readfile, "DBFR_Lua/chamber.lua")
        if not hasSource or type(source) ~= "string" or #source < 100 then
            log("Save the full loader.lua file as DBFR_Lua/chamber.lua in your executor workspace before enabling teleport reload")
            return
        end
        local ok, err = pcall(queue, [[
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    local env = type(getgenv) == "function" and getgenv() or _G
    local ok, saved = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile("DBFR_Lua/settings.json"))
    end)
    if ok and saved.resumeRequested and saved.config and saved.config.resumeAfterTeleport then
        env.__DBFR_AUTORESUME = true
        local source = readfile("DBFR_Lua/chamber.lua")
        assert(loadstring(source, "DBFR Chamber"))()
    end
end)
]])
        if ok then queueRegistered = true; log("Teleport reload queued; executor must reattach to the next client")
        else log("Teleport queue failed: " .. tostring(err)) end
    end
    local function stop()
        bindingToken = bindingToken + 1
        engine:setActive(false, os.clock())
        release()
        save()
    end
    local function toggle()
        if not live then return end
        bindingToken = bindingToken + 1
        if engine.active then stop(); ui:setVisible(true)
        else
            release()
            bindings.lastKinds, bindings.activeChallenge = {}, nil
            engine:setActive(true, os.clock())
            save(); registerQueue()
            ui:setVisible(false)
        end
    end
    local function unload()
        if not live then return end
        stop(); live = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        if ui then ui:destroy() end
        env.__DBFR_APP = nil
        log("Unloaded")
    end
    engine = Engine.new(config, log)
    rhythm = Rhythm.new(config, input)
    local parent
    if type(env.gethui) == "function" then
        local ok, result = pcall(env.gethui)
        if ok then parent = result end
    end
    parent = parent or player:WaitForChild("PlayerGui")
    ui = UI.new(parent, config, {
        toggle = toggle, close = unload,
        show = function() if engine.active then stop() end end,
        setting = function(key, value)
            -- An in-flight input retains the same backend, but all automation stops before settings change.
            stop()
            local changed = Config.new({[key] = value})
            config[key] = changed[key]
            save()
            ui:notify("Saved. Press POWER UP when ready.")
        end,
        clearBinding = function(role)
            stop(); bindings.saved[role] = nil; save(); ui:notify("Reset " .. role .. " to automatic detection")
        end,
        bind = function(role)
            stop()
            local token = bindingToken
            ui.window.Visible, ui.pill.Visible = false, false
            task.spawn(function()
                for seconds = 3, 1, -1 do
                    if not live or token ~= bindingToken then return end
                    ui:notify("Hover " .. role .. " in Roblox — capturing in " .. seconds, 1.2)
                    task.wait(1)
                end
                if not live or token ~= bindingToken then return end
                bindings.nextScan = 0
                bindings:refresh(os.clock())
                local position = game:GetService("UserInputService"):GetMouseLocation()
                local target = bindings:pick(position.X, position.Y)
                local ok, message = bindings:bind(role, target)
                if ok then save() end
                ui:setVisible(true); ui:notify(message, 5); log(message)
            end)
        end,
    })
    bindings = Bindings.new(player, saved.bindings, ui.gui)
    env.__DBFR_APP = {unload = unload, toggle = toggle, version = "1.0.0", ui = ui}
    log("Chamber 1.0.0 loaded. Start paused; map any unidentified prompt icons in Calibration.")
    log(input:description())
    if type(env.writefile) ~= "function" then log("File storage unavailable: settings last for this session only") end
    local uis = game:GetService("UserInputService")
    connections[#connections + 1] = uis.InputBegan:Connect(function(key, processed)
        -- F7 always works, including while a text field is focused.
        if key.KeyCode == Enum.KeyCode.F7 then unload(); return end
        if processed or uis:GetFocusedTextBox() then return end
        if key.KeyCode == Enum.KeyCode.F6 then toggle()
        elseif key.KeyCode == Enum.KeyCode.RightShift then
            if not ui.window.Visible and engine.active then stop() end
            ui:setVisible(not ui.window.Visible)
        end
    end)
    local snapshot = {notes = {}, training = false}
    connections[#connections + 1] = game:GetService("RunService").Heartbeat:Connect(function()
        if not live then return end
        local now = os.clock()
        local ok, reason = pcall(function()
            snapshot = bindings:snapshot(now)
            for _, detail in ipairs(bindings.errors) do
                if not reportedBindingErrors[detail] then log(detail); reportedBindingErrors[detail] = true end
            end
            if now >= nextEngine then
                nextEngine = now + 0.1
                local wasActive = engine.active
                local previousState = engine.state
                local action = engine:step(snapshot, now)
                if previousState == "training" and engine.state ~= "training" then
                    bindings.lastKinds, bindings.activeChallenge = {}, nil
                end
                if wasActive and not engine.active then save(); ui:setVisible(true) end
                if action and not actionRunning then
                    actionRunning = true
                    release()
                    ui:setVisible(false)
                    local target = snapshot.controls[action.kind]
                    task.spawn(function()
                        local succeeded, detail = pcall(input.click, input, target, config,
                            function() return live and engine.active and engine.generation == action.generation end,
                            action.kind == "start")
                        engine:complete(action, succeeded, os.clock(), detail)
                        actionRunning = false
                        if live then save() end
                    end)
                elseif action then
                    -- A cancelled action may still be unwinding its release; retry only after it exits.
                    engine.pending = nil
                end
            end
            if engine:canPlay(snapshot) and not actionRunning then
                rhythm:step(snapshot.notes, snapshot.challenge, now)
            elseif not actionRunning then rhythm:reset() end
            if now >= nextUI then
                nextUI = now + 0.2
                ui:update(engine, rhythm, bindings, input:description(), now)
            end
        end)
        if not ok then
            engine:halt(now, "Stopped: " .. tostring(reason))
            release(); save(); ui:setVisible(true)
        end
    end)
    if env.__DBFR_AUTORESUME then
        env.__DBFR_AUTORESUME = nil
        if config.resumeAfterTeleport then toggle() end
    end
    return env.__DBFR_APP
end
return Main
