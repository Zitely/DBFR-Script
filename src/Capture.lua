-- Optional, read-only diagnostic. Not loaded by the Chamber application.
local GuiIndex = require("src.GuiIndex")
local Capture = {}
local ROOTS = {"Main", "MainFrame", "Menu", "Timer"}
local ATTRIBUTES = {"Key", "KeyCode", "Input", "InputType", "Action", "Button", "Type"}
local function trim(value) return tostring(value):sub(1, 300) end
local function vector(value) return {value.X, value.Y} end
local function encode(value, depth, seen, budget)
    local kind = type(value)
    if kind == "nil" then return {type = "nil"} end
    if kind == "boolean" then return value end
    if kind == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then return value end
        return {type = "number", value = tostring(value)}
    end
    if kind == "string" then return trim(value) end
    if kind ~= "table" then return {type = kind, value = trim(value)} end
    if seen[value] then return {type = "cycle"} end
    if depth >= 6 or budget.left <= 0 then return {type = "truncated"} end
    seen[value] = true
    local entries = {}
    for key, item in pairs(value) do
        if #entries >= 64 or budget.left <= 0 then entries[#entries + 1] = {truncated = true}; break end
        budget.left = budget.left - 1
        entries[#entries + 1] = {key = encode(key, depth + 1, seen, budget), value = encode(item, depth + 1, seen, budget)}
    end
    seen[value] = nil
    return {type = "table", entries = entries}
end
local function pathOf(object, root)
    local parts, current = {}, object
    while current and current ~= root do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return "Players.LocalPlayer.PlayerGui." .. table.concat(parts, ".")
end
local function visible(object)
    local current = object
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and not current.Enabled then return false end
        current = current.Parent
    end
    return object.Parent ~= nil and object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

function Capture.start()
    local env = type(getgenv) == "function" and getgenv() or _G
    if env.__DBFR_CAPTURE then env.__DBFR_CAPTURE.stop(false) end
    local player = game:GetService("Players").LocalPlayer
    local playerGui = assert(player and player:FindFirstChildOfClass("PlayerGui"), "PlayerGui is not ready")
    local http = game:GetService("HttpService")
    local started, duration = os.clock(), 30
    local report = {format = 1, duration = duration, roots = {}, availableRoots = {}, events = {},
        objects = {}, errors = {}, truncated = {}, remoteFound = false,
        remote = "ReplicatedStorage.Minigame.OnClientEvent"}
    local camera = workspace.CurrentCamera
    if camera then report.viewport = vector(camera.ViewportSize) end
    local ids, settled, connections, count, snapshots = {}, {}, {}, 0, 0
    local running, index, remote = true, nil, nil
    local handle = {report = report}
    local function record(object)
        if not running or not object.Parent then return end
        local id = ids[object]
        if not id then
            if count >= 1500 then report.truncated.objects = true; return end
            count = count + 1; id = count; ids[object] = id
            report.objects[id] = {path = pathOf(object, playerGui), class = object.ClassName, samples = {}}
        end
        local entry = report.objects[id]
        if #entry.samples >= 6 or snapshots >= 4500 then report.truncated.samples = true; return end
        local sample = {at = os.clock() - started, name = object.Name, position = vector(object.AbsolutePosition),
            size = vector(object.AbsoluteSize), visible = visible(object), attributes = {}}
        local class = object.ClassName
        if class == "TextLabel" or class == "TextButton" or class == "TextBox" then sample.text = trim(object.Text) end
        if class == "ImageLabel" or class == "ImageButton" then
            sample.image = trim(object.Image)
            sample.imageRectOffset, sample.imageRectSize = vector(object.ImageRectOffset), vector(object.ImageRectSize)
        end
        for _, name in ipairs(ATTRIBUTES) do
            local value = object:GetAttribute(name)
            if value ~= nil then sample.attributes[name] = encode(value, 0, {}, {left = 64}) end
        end
        local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
        if screen then sample.ignoreGuiInset = screen.IgnoreGuiInset end
        entry.samples[#entry.samples + 1] = sample
        snapshots = snapshots + 1
    end
    index = GuiIndex.new(nil, function(object)
        record(object)
        if ids[object] then settled[object] = os.clock() + 0.15 end
    end, function(object)
        if ids[object] then report.objects[ids[object]].removedAt = os.clock() - started end
        settled[object] = nil
    end, function(reason) report.errors[#report.errors + 1] = reason end)
    handle.index = index
    local function attach()
        for _, name in ipairs(ROOTS) do
            local root = playerGui:FindFirstChild(name)
            if root and root ~= index.roots[name] then
                report.roots[#report.roots + 1] = name
                index:attach(name, root)
            end
        end
        if not remote then
            local candidate = game:GetService("ReplicatedStorage"):FindFirstChild("Minigame")
            if candidate and candidate:IsA("RemoteEvent") then
                remote = candidate
                report.remoteFound = true
                connections[#connections + 1] = remote.OnClientEvent:Connect(function(...)
                    if not running then return end
                    if #report.events >= 24 then report.truncated.events = true; return end
                    local args, values, budget = {...}, {}, {left = 256}
                    if select("#", ...) > 16 then report.truncated.arguments = true end
                    for i = 1, math.min(select("#", ...), 16) do values[i] = encode(args[i], 0, {}, budget) end
                    report.events[#report.events + 1] = {at = os.clock() - started,
                        argumentCount = select("#", ...), arguments = values}
                end)
            end
        end
    end
    function handle.stop(export)
        if not running then return report end
        running = false
        -- Capture removal times only from the game, not from our own cleanup.
        index.removed = function() end
        index:close()
        settled, ids = {}, {}
        for _, connection in ipairs(connections) do connection:Disconnect() end
        report.elapsed = os.clock() - started
        if env.__DBFR_CAPTURE == handle then env.__DBFR_CAPTURE = nil end
        if export == false then return report end
        local ok, result = pcall(http.JSONEncode, http, report)
        if not ok then print("[Chamber Capture] Report encoding failed: " .. tostring(result)); return report end
        env.__DBFR_CAPTURE_RESULT = result
        local saved, copied = false, false
        if type(env.writefile) == "function" and type(env.makefolder) == "function" then
            saved = pcall(function()
                pcall(env.makefolder, "DBFR_Lua")
                env.writefile("DBFR_Lua/minigame_capture.json", result)
            end)
        end
        if type(env.setclipboard) == "function" then copied = pcall(env.setclipboard, result) end
        print(string.format("[Chamber Capture] Done: %d incoming events, %d GUI objects. File saved: %s; copied to clipboard: %s.",
            #report.events, count, tostring(saved), tostring(copied)))
        if saved then print("[Chamber Capture] File: DBFR_Lua/minigame_capture.json") end
        if not saved and not copied then print("[Chamber Capture] " .. result) end
        return report
    end
    for _, child in ipairs(playerGui:GetChildren()) do report.availableRoots[#report.availableRoots + 1] = child.Name end
    env.__DBFR_CAPTURE = handle
    local nextAttach = 0
    connections[#connections + 1] = game:GetService("RunService").Heartbeat:Connect(function()
        if not running then return end
        if os.clock() - started >= duration then handle.stop(); return end
        local ok, reason = pcall(function()
            if os.clock() >= nextAttach then nextAttach = os.clock() + 1; attach() end
            index:pump()
            local processed = 0
            for object, at in pairs(settled) do
                if os.clock() >= at then
                    settled[object] = nil; record(object)
                    processed = processed + 1
                    if processed >= 24 then break end
                end
            end
        end)
        if not ok then report.errors[#report.errors + 1] = tostring(reason); handle.stop() end
    end)
    local ok, reason = pcall(attach)
    if not ok then report.errors[#report.errors + 1] = tostring(reason); handle.stop(); return handle end
    print("[Chamber Capture] Recording for 30 seconds. With Chamber OFF, manually start a minigame, then open Menu and Respawn. This capture sends no inputs.")
    return handle
end
return Capture
