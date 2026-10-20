local Config = require("src.Config")
local Engine = require("src.Engine")
local Rhythm = require("src.Rhythm")
local Bindings = require("src.Bindings")
local Input = require("src.Input")
local UI = require("src.UI")
local Weights = require("src.Weights")
local Respawn = require("src.Respawn")
local Features = require("src.Features")
local TeleportResume = require("src.TeleportResume")
local Overnight = require("src.Overnight")
local Main = {}
local VERSION = "1.6.0"

function Main.start()
    local env = type(getgenv) == "function" and getgenv() or _G
    local arrival = env.__DBFR_TELEPORT_RESUME
    env.__DBFR_TELEPORT_RESUME, env.__DBFR_AUTORESUME = nil, nil
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
    local savedConfig = type(saved.config) == "table" and saved.config or {}
    -- Removed AFK/resume flags are intentionally ignored by Config.new.
    local config = Config.new(savedConfig)
    local ui, engine, bindings, rhythm, features, cycle
    local session = TeleportResume.new(env, player)
    local input = Input.new(env)
    local live = true
    local actionRunning, nextEngine, nextUI, nextHealthCheck, lastTick = false, 0, 0, 0, -math.huge
    local hubSettingsDirty, nextSettingsSave = false, 0
    local wasPlaying = false
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
            env.writefile(storage, http:JSONEncode({version = 3, config = config, bindings = bindings.saved,
                hub = features and features.values or {}}))
        end)
        if not ok then log("Settings could not be saved: " .. tostring(err)) end
        return ok
    end
    local function release()
        local ok, reason = pcall(rhythm.reset, rhythm)
        local released, detail = pcall(input.releaseAll, input)
        if not ok or not released then log("Input release needs attention: " .. tostring(reason or detail)) end
    end
    local function ensureNightmare(quiet)
        if player:GetAttribute("Difficulty") == "Nightmare" then
            if not quiet then log("Nightmare difficulty already selected") end
            return true
        end
        local remote = game:GetService("ReplicatedStorage"):FindFirstChild("DifficultySet")
        if not remote or type(remote.FireServer) ~= "function" then
            log("Nightmare difficulty could not be selected: DifficultySet is unavailable")
            return false
        end
        local previous = player:GetAttribute("Difficulty")
        local ok, reason = pcall(function()
            player:SetAttribute("Difficulty", "Nightmare")
            remote:FireServer("Nightmare")
        end)
        if ok then
            log("Nightmare difficulty selected")
            return true
        end
        pcall(player.SetAttribute, player, "Difficulty", previous)
        log("Nightmare difficulty could not be selected: " .. tostring(reason))
        return false
    end
    local function stop()
        engine:setActive(false, os.clock())
        if cycle then cycle:cancel() end
        if features then features:sync() end
        release()
        bindings:pause()
        wasPlaying = false
        save()
        if live and ui then ui:updateFeature("chamber", engine, rhythm, os.clock()) end
    end
    local function toggle()
        if not live then return end
        if engine.active then stop()
        else
            release()
            bindings.lastKinds, bindings.activeChallenge = {}, nil
            engine:setActive(true, os.clock())
            if features then features:sync() end
            if game.PlaceId == session.earthPlaceId and not config.dryRun then cycle:resume("earth")
            else ensureNightmare() end
            save()
            ui:updateFeature("chamber", engine, rhythm, os.clock())
        end
    end
    local function unload()
        if not live then return end
        stop(); live = false
        if cycle then cycle:destroy() end
        if features then features:destroy() end
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
    ui = UI.new(parent, unload, VERSION)
    ui:addFeature("chamber", "CHAMBER AUTO TRAIN", toggle)
    bindings = Bindings.new(player, saved.bindings, ui.gui)
    features = Features.new(player, ui, function() return engine.active or actionRunning end, saved.hub, function(id, kind)
        if id == "meditate" and not engine.active then release(); bindings:pause(); wasPlaying = false end
        if kind == "slider" then hubSettingsDirty = true end
    end, env, session)
    cycle = Overnight.new(player, engine, config, session, env, function(reason)
        engine:halt(os.clock(), reason)
        release(); bindings:pause(); wasPlaying = false
        save(); ui:updateFeature("chamber", engine, rhythm, os.clock())
    end)
    env.__DBFR_APP = {unload = unload, toggle = toggle, version = VERSION, ui = ui, scanner = bindings, features = features}
    log("Chamber " .. VERSION .. " loaded. Use the Chamber toggle to start or stop; Right Shift shows or hides the hub.")
    log(input:description())
    if type(env.writefile) ~= "function" then log("File storage unavailable: settings last for this session only") end
    ui:updateFeature("chamber", engine, rhythm, os.clock())
    connections[#connections + 1] = player.CharacterAdded:Connect(function()
        task.spawn(function()
            task.wait(1)
            if live and engine.active and not cycle:active() then ensureNightmare() end
        end)
    end)
    local snapshot = {notes = {}, training = false}
    connections[#connections + 1] = game:GetService("RunService").Heartbeat:Connect(function()
        if not live then return end
        local now = os.clock()
        if now - lastTick < 1 / 60 - 0.001 then return end
        lastTick = now
        if hubSettingsDirty and now >= nextSettingsSave then
            hubSettingsDirty, nextSettingsSave = false, now + 0.5
            save()
        end
        features:step(now)
        if not engine.active then
            if features:running("meditate") and not actionRunning then
                local ok, reason = pcall(function()
                    local sample = bindings:snapshot(now)
                    if sample.training and sample.alive and not sample.needsRecovery and not sample.respawnCanvas then
                        if not wasPlaying then input:park(ui.window)
                        else rhythm:step(sample.notes, sample.challenge, now) end
                        wasPlaying = true
                    elseif wasPlaying then release(); wasPlaying = false end
                end)
                if not ok then
                    features:set("meditate", false)
                    features:status("meditate", "Stopped: " .. tostring(reason))
                end
            end
            return
        end
        local ok, reason = pcall(function()
            if cycle:active() then
                if cycle.phase == "htc_loading" then snapshot = bindings:snapshot(now) end
                if cycle:step(now, snapshot) then
                    if now >= nextUI then nextUI = now + 0.4; ui:updateFeature("chamber", engine, rhythm, now) end
                    return
                end
            end
            -- Monitor at the requested 50 ms interval. A direct reset is much
            -- faster and more reliable than navigating Roblox's respawn menu.
            if config.autoRecover and not config.dryRun and now >= nextHealthCheck then
                nextHealthCheck = now + 0.05
                if Respawn.resetIfNeeded(player) then
                    log("Health <= 2 detected; resetting character")
                end
            end
            snapshot = bindings:snapshot(now)
            snapshot.inHTC = game.PlaceId == TeleportResume.HTC
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
                if wasActive and not engine.active then
                    cycle:cancel()
                    release(); bindings:pause(); wasPlaying = false
                    save(); ui:updateFeature("chamber", engine, rhythm, now)
                end
                if action and not actionRunning then
                    actionRunning = true
                    release()
                    task.spawn(function()
                        local valid = function() return live and engine.active and engine.generation == action.generation end
                        local succeeded, detail
                        local ready = true
                        if action.kind == "cycle" then
                            bindings:pause(); wasPlaying = false
                            if valid() then succeeded, detail = pcall(cycle.depart, cycle) end
                            engine:complete(action, succeeded, os.clock(), detail)
                            actionRunning = false
                            if live then save(); ui:updateFeature("chamber", engine, rhythm, os.clock()) end
                            return
                        end
                        if action.kind == "start" then
                            ready = ensureNightmare(true)
                            if ready then
                                local found, equipped, name = pcall(Weights.equipBest, player)
                                if found and equipped then log("Equipped " .. name .. " before training")
                                elseif not found then log("Weight check failed: " .. tostring(equipped)) end
                            else detail = "Nightmare difficulty was not selected" end
                        end
                        if ready then
                            local target = snapshot.controls[action.kind]
                            succeeded, detail = pcall(input.click, input, target, config, valid, action.kind == "start")
                        else
                            succeeded = false
                        end
                        engine:complete(action, succeeded, os.clock(), detail)
                        actionRunning = false
                        if live then
                            if not engine.active then bindings:pause(); release(); wasPlaying = false end
                            save(); ui:updateFeature("chamber", engine, rhythm, os.clock())
                        end
                    end)
                elseif action then
                    -- A cancelled action may still be unwinding its release; retry only after it exits.
                    engine.pending = nil
                end
            end
            if engine:canPlay(snapshot) and not actionRunning then
                -- Joining a running minigame leaves the pointer over our toggle.
                -- Move away before sending mouse notes, which UI can consume.
                if not wasPlaying then input:park(ui.window)
                else rhythm:step(snapshot.notes, snapshot.challenge, now) end
                wasPlaying = true
            elseif wasPlaying and not actionRunning then
                rhythm:reset()
                wasPlaying = false
            end
            if now >= nextUI then
                nextUI = now + 0.4
                ui:updateFeature("chamber", engine, rhythm, now)
            end
        end)
        if not ok then
            cycle:cancel()
            engine:halt(now, "Stopped: " .. tostring(reason))
            release(); bindings:pause(); wasPlaying = false
            save(); ui:updateFeature("chamber", engine, rhythm, now)
        end
    end)
    if type(arrival) == "table" and arrival.target == game.PlaceId and arrival.userId == player.UserId
        and ((arrival.mode == "earth" and game.PlaceId == session.earthPlaceId)
            or (arrival.mode == "train" and game.PlaceId == TeleportResume.HTC))
        and type(arrival.issued) == "number" and os.time() - arrival.issued >= 0 and os.time() - arrival.issued <= 600 then
        engine:setActive(true, os.clock())
        cycle:resume(arrival.mode)
        features:sync(); save(); ui:updateFeature("chamber", engine, rhythm, os.clock())
    end
    return env.__DBFR_APP
end
return Main
