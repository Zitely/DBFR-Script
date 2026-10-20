local Scope = require("src.EffectScope")
local Markers = require("src.WorldMarkers")
local Effects = {}
local function character(context, player)
    local char = player.Character
    if context.character ~= char then
        context.scope:close()
        context.scope = Scope.new()
        context.character, context.initialized = char, false
        context.velocity, context.gyro, context.parts = nil, nil, nil
    end
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    return char, humanoid, char and char:FindFirstChild("HumanoidRootPart")
end
local function roots(names)
    local list = {}
    for _, name in ipairs(names) do
        local root = workspace:FindFirstChild(name)
        if root then list[#list + 1] = root end
    end
    return list
end
function Effects.step(id, c, hub, now)
    local player = hub.player
    if id == "speed" or id == "jump" or id == "noclip" or id == "flight" then
        local char, hum, root = character(c, player)
        if not hum or hum.Health <= 0 then
            c.scope:close(); c.scope = Scope.new(); c.initialized = false
            c.velocity, c.gyro, c.parts = nil, nil, nil
            return
        end
        if id == "speed" then c.scope:set(hum, "WalkSpeed", hub.values.walkSpeed)
        elseif id == "jump" and not c.initialized then
            c.initialized = true
            c.scope:connect(game:GetService("UserInputService").JumpRequest, function()
                if hub:running(id) and player.Character == char and hum.Health > 0
                    and not game:GetService("UserInputService"):GetFocusedTextBox() then
                    pcall(hum.ChangeState, hum, Enum.HumanoidStateType.Jumping)
                end
            end)
        elseif id == "noclip" then
            if not c.initialized then
                c.initialized, c.parts = true, {}
                local function add(part) if part:IsA("BasePart") then c.parts[part] = true end end
                for _, part in ipairs(char:GetDescendants()) do add(part) end
                c.scope:connect(char.DescendantAdded, add)
                c.scope:connect(char.DescendantRemoving, function(part)
                    if c.parts[part] then c.parts[part] = nil; c.scope:restore(part) end
                end)
            end
            for part in pairs(c.parts) do c.scope:set(part, "CanCollide", false) end
        elseif id == "flight" and root then
            if not c.velocity or c.velocity.Parent ~= root then
                if c.velocity then c.velocity:Destroy(); c.gyro:Destroy() end
                c.velocity = c.scope:own(Instance.new("BodyVelocity"))
                c.velocity.Name, c.velocity.MaxForce = "DBFR__Flight", Vector3.new(1e9, 1e9, 1e9)
                c.velocity.Parent = root
                c.gyro = c.scope:own(Instance.new("BodyGyro"))
                c.gyro.Name, c.gyro.MaxTorque = "DBFR__FlightGyro", Vector3.new(1e9, 1e9, 1e9)
                c.gyro.Parent = root
            end
            c.scope:set(hum, "AutoRotate", false)
            local uis, camera = game:GetService("UserInputService"), workspace.CurrentCamera
            local direction = Vector3.new(0, 0, 0)
            if camera and not uis:GetFocusedTextBox() then
                local function down(key) return uis:IsKeyDown(Enum.KeyCode[key]) end
                if down("W") then direction = direction + camera.CFrame.LookVector end
                if down("S") then direction = direction - camera.CFrame.LookVector end
                if down("A") then direction = direction - camera.CFrame.RightVector end
                if down("D") then direction = direction + camera.CFrame.RightVector end
                if down("E") or down("Space") then direction = direction + Vector3.new(0, 1, 0) end
                if down("Q") then direction = direction - Vector3.new(0, 1, 0) end
                c.gyro.CFrame = camera.CFrame
            end
            c.velocity.Velocity = direction.Magnitude > 0 and direction.Unit * hub.values.flightSpeed or direction
        end
    elseif id == "bright" then
        local lighting = game:GetService("Lighting")
        c.scope:set(lighting, "Ambient", Color3.fromRGB(255, 255, 255))
        c.scope:set(lighting, "OutdoorAmbient", Color3.fromRGB(255, 255, 255))
        c.scope:set(lighting, "Brightness", 2)
    elseif id == "sky" and not c.initialized then
        local lighting = game:GetService("Lighting")
        c.scope:set(lighting, "FogEnd", 1000000)
        local function clear(effect)
            if effect:IsA("Atmosphere") then
                c.scope:set(effect, "Density", 0); c.scope:set(effect, "Haze", 0)
            elseif effect:IsA("BlurEffect") or effect:IsA("DepthOfFieldEffect") then
                c.scope:set(effect, "Enabled", false)
            end
        end
        for _, effect in ipairs(lighting:GetChildren()) do clear(effect) end
        c.scope:connect(lighting.DescendantAdded, clear)
        c.scope:connect(lighting.DescendantRemoving, function(effect) c.scope:restore(effect) end)
        c.initialized = true
    elseif id == "fov" then
        local camera = workspace.CurrentCamera
        if c.camera ~= camera then c.scope:close(); c.scope = Scope.new(); c.camera = camera end
        if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
            c.scope:set(camera, "FieldOfView", hub.values.fov)
        elseif camera then c.scope:restore(camera) end
    elseif id == "shake" and not c.initialized then
        -- Keep Roblox's camera update, discard later shake offsets. Scriptable
        -- cameras (including Chamber cutscenes) are deliberately left alone.
        local run = game:GetService("RunService")
        local cameraName, lastName = "DBFR__CameraSample", "DBFR__CameraRestore"
        c.scope.cleanup[#c.scope.cleanup + 1] = function()
            run:UnbindFromRenderStep(cameraName); run:UnbindFromRenderStep(lastName)
        end
        run:BindToRenderStep(cameraName, Enum.RenderPriority.Camera.Value + 1, function()
            local camera = workspace.CurrentCamera
            c.camera = camera
            c.frame = camera and camera.CameraType == Enum.CameraType.Custom and camera.CFrame or nil
        end)
        run:BindToRenderStep(lastName, Enum.RenderPriority.Last.Value, function()
            if c.frame and c.camera == workspace.CurrentCamera and c.camera.CameraType == Enum.CameraType.Custom then
                c.camera.CFrame = c.frame
            end
        end)
        c.initialized = true
    elseif id == "players" then
        c.highlights = c.highlights or {}
        if not c.initialized then
            c.scope.cleanup[#c.scope.cleanup + 1] = function()
                for _, item in pairs(c.highlights) do item:Destroy() end
                c.highlights = {}
            end
            c.initialized = true
        end
        local current = {}
        for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
            local char = other.Character
            if other ~= player and char and char.Parent then
                current[char] = true
                if not c.highlights[char] then
                    local highlight = Instance.new("Highlight")
                    highlight.Name, highlight.Adornee = "DBFR__PlayerESP", char
                    highlight.FillColor = Color3.fromRGB(255, 132, 35)
                    highlight.OutlineColor = Color3.fromRGB(255, 211, 98)
                    highlight.FillTransparency, highlight.Parent = 0.5, char
                    c.highlights[char] = highlight
                end
            end
        end
        for char, highlight in pairs(c.highlights) do
            if not current[char] then highlight:Destroy(); c.highlights[char] = nil end
        end
    elseif id == "npcs" or id == "radar" then
        if not c.markers then
            c.markers = Markers.new(id == "radar", function(name)
                hub:status(id, "Found " .. name)
                pcall(function() game:GetService("StarterGui"):SetCore("SendNotification",
                    {Title = "Dragon Ball Radar", Text = name .. " found", Duration = 5}) end)
            end)
            c.scope.cleanup[#c.scope.cleanup + 1] = function() c.markers:destroy() end
        end
        if now >= (c.nextRoots or 0) then
            c.nextRoots = now + 1
            c.markers:setRoots(roots(id == "radar" and {"DragonBallLocatioionsa", "DragonBallLocations", "ItemDrops"}
                or {"Quests", "QuestsInTheCity", "NPCs"}))
        end
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        c.markers:step(root and root.Position)
    elseif id == "antiAfk" and not c.initialized then
        local virtualUser = game:GetService("VirtualUser")
        c.scope:connect(player.Idled, function()
            if not hub:running(id) then return end
            local ok, err = pcall(function()
                virtualUser:CaptureController()
                virtualUser:ClickButton2(Vector2.new(0, 0))
            end)
            if not ok then hub:status(id, "Unavailable: " .. tostring(err)) end
        end)
        c.initialized = true
    end
end
return Effects
