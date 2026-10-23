-- Local catalog visibility and the uploaded OutfitChange requests. Server ownership
-- and DataStore persistence are not created by cloning inventory buttons.
local Scope = require("src.EffectScope")
local Cosmetics = {}
Cosmetics.__index = Cosmetics
local LIMIT, WORK, PREVIEWS = 2048, 4, 12
local function child(parent, name) return parent and parent:FindFirstChild(name) end
local function textObject(object)
    return object and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
end
local function itemType(item, drop)
    local kind = child(item, "Type")
    kind = kind and kind:IsA("StringValue") and kind.Value or nil
    if kind == "Accessory" or kind == "Weapon" then return kind end
    if kind == "Clothing" or not drop then return "Clothing" end
    local name = item.Name:lower()
    for _, word in ipairs({"mask", "glasses", "head", "hat", "scouter", "ring", "eyepatch"}) do
        if name:find(word, 1, true) then return "Accessory" end
    end
    if name:find("sword", 1, true) or name:find("pole", 1, true) then return "Weapon" end
    return "Clothing"
end
local function roots(player)
    local storage = game:GetService("ReplicatedStorage")
    local gui = player:FindFirstChildOfClass("PlayerGui")
    local placeholder = child(gui, "PlaceHolder")
    local clothing = child(placeholder, "Clothing")
    return {
        outfits = child(storage, "Outfits"),
        drops = child(child(child(storage, "CharacterStuff"), "PlayerGui"), "UnlockStuffs"),
        clothing = clothing, template = child(child(clothing, "ClothingScript"), "Template"),
        Clothing = child(clothing, "Outfits"), Accessory = child(clothing, "Accessories"), Weapon = child(clothing, "Weapons"),
        titles = child(child(placeholder, "StylesFrame"), "ChatTitles"),
    }
end
local function same(a, b)
    if not a then return false end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end
function Cosmetics.new(hub)
    return setmetatable({hub = hub, live = true, nextRoots = 0, nextBrowser = 0,
        items = {}, records = {}, jobs = {}, previewCount = 0, previewCursor = 1}, Cosmetics)
end
function Cosmetics:message(message) self.hub:status("cosmeticBrowser", message) end
function Cosmetics:job(parent, kind)
    if parent then self.jobs[#self.jobs + 1] = {parent = parent, list = parent:GetChildren(), cursor = 1, kind = kind} end
end
function Cosmetics:refresh(found)
    if self.scope then self.scope:close() end
    self.scope, self.roots, self.dirty = Scope.new(), found, false
    self.items, self.records, self.seen, self.jobs = {}, {}, {}, {}
    self.previewCount, self.previewCursor, self.failures, self.visited = 0, 1, 0, 0
    for _, name in ipairs({"outfits", "drops", "template", "titles"}) do
        local root = found[name]
        if root then
            self.scope:connect(root.DescendantAdded, function() self.dirty = true end)
            self.scope:connect(root.DescendantRemoving, function() self.dirty = true end)
        end
    end
    -- Stack order: catalog first, then copied drop controls, then chat titles.
    self:job(found.titles, "title")
    self:job(found.drops, "folder")
    self:job(found.outfits, "model")
    self.browserDirty = true
end
function Cosmetics:add(item, drop)
    if not drop and not item:IsA("Model") then return end
    if drop and not (item:IsA("GuiButton") or item:IsA("Frame")) then return end
    local kind = itemType(item, drop)
    local key = kind .. ":" .. item.Name
    if self.seen[key] then return end
    local record = {source = item, name = item.Name, kind = kind, equippable = not drop and kind ~= "Weapon"}
    self.seen[key], self.items[#self.items + 1] = true, record
    self.browserDirty = true
    local target = self.roots[kind]
    if not target or target:FindFirstChild(item.Name) then return end
    local template = drop and item or self.roots.template
    if not template or not template:IsA("GuiObject") then return end
    local entry = assert(template:Clone(), "Cosmetic template cannot be cloned")
    self.scope:own(entry)
    entry.Name, entry.Visible = item.Name, true
    local label = child(entry, "OutfitName")
    if textObject(label) then label.Text = item.Name end
    local controller = ({Clothing = "ClothingEquip", Accessory = "AccessoryEquip", Weapon = "WeaponEquip"})[kind]
    for _, name in ipairs({"ClothingEquip", "AccessoryEquip", "WeaponEquip"}) do
        local script = child(entry, name)
        if script and script:IsA("LocalScript") then script.Disabled = name ~= controller end
    end
    local rarity, rarityLabel = child(item, "Rarity"), child(entry, "Rarity")
    if rarity and rarity:IsA("StringValue") and textObject(rarityLabel) then
        rarityLabel.Text = rarity.Value
        local colors = {Uncommon = Color3.fromRGB(85, 255, 0), Rare = Color3.fromRGB(0, 170, 255),
            Legendary = Color3.fromRGB(255, 255, 0)}
        if colors[rarity.Value] then rarityLabel.TextColor3 = colors[rarity.Value] end
    end
    entry.Parent = target
    record.entry = entry
    record.viewport = not drop and child(entry, "ViewportFrame") or nil
    self.records[#self.records + 1] = record
end
local function onScreen(entry)
    if not entry.Parent then return false end
    local p, size = entry.AbsolutePosition, entry.AbsoluteSize
    local x1, y1, x2, y2 = p.X, p.Y, p.X + size.X, p.Y + size.Y
    local camera = workspace.CurrentCamera
    if camera then x1, y1 = math.max(0, x1), math.max(0, y1)
        x2, y2 = math.min(camera.ViewportSize.X, x2), math.min(camera.ViewportSize.Y, y2) end
    local parent = entry
    while parent do
        if parent:IsA("GuiObject") then
            if not parent.Visible then return false end
            if parent.ClipsDescendants or parent:IsA("ScrollingFrame") then
                local a, b = parent.AbsolutePosition, parent.AbsoluteSize
                x1, y1, x2, y2 = math.max(x1, a.X), math.max(y1, a.Y), math.min(x2, a.X + b.X), math.min(y2, a.Y + b.Y)
            end
        elseif parent:IsA("LayerCollector") and not parent.Enabled then return false end
        parent = parent.Parent
    end
    return x2 > x1 and y2 > y1
end
function Cosmetics:previews()
    local created = 0
    for _ = 1, math.min(24, #self.records) do
        if self.previewCursor > #self.records then self.previewCursor = 1 end
        local r = self.records[self.previewCursor]
        self.previewCursor = self.previewCursor + 1
        local visible = r.viewport and r.viewport:IsA("ViewportFrame") and onScreen(r.entry)
        if r.preview and not visible then
            r.preview:close(); r.preview = nil; self.previewCount = self.previewCount - 1
        elseif visible and not r.preview and not r.previewFailed and created < 2 and self.previewCount < PREVIEWS then
            created = created + 1
            local preview = Scope.new()
            local ok = pcall(function()
                local model = assert(r.source:Clone(), "Cosmetic model cannot be cloned")
                preview:own(model); model.Name, model.Parent = "Dummy", r.viewport
                local part = model.PrimaryPart
                if part then
                    local camera = preview:own(Instance.new("Camera"))
                    camera.CFrame = CFrame.new(part.Position + part.CFrame.LookVector * 4.4, part.Position)
                    camera.Parent = r.viewport
                    preview:set(r.viewport, "CurrentCamera", camera)
                end
            end)
            if ok then r.preview = preview; self.previewCount = self.previewCount + 1
            else preview:close(); r.previewFailed = true end
        end
    end
end
function Cosmetics:save()
    if not self.live then return end
    local now = os.clock()
    if now < (self.hub.cosmeticSaveAfter or 0) then
        self.saveDue = self.hub.cosmeticSaveAfter
        self:message("Save queued; server ownership is required.")
        return
    end
    self.saveDue, self.hub.cosmeticSaveAfter = nil, now + 10
    local ok, reason = pcall(self.hub.fire, self.hub, {"SaveFeature", "SaveData"})
    if not self.live then return end
    self:message(ok and "Save requested; permanent ownership is unconfirmed."
        or "Save unavailable: " .. tostring(reason))
end
function Cosmetics:equip(record)
    if not self.live then return end
    local current = false
    for _, item in ipairs(self.items) do if item == record then current = true; break end end
    if not current or not record.source.Parent then self:message("Catalog changed; select the item again."); return end
    if not record.equippable then self:message("Use this item's button in the game's " .. record.kind .. " menu."); return end
    if self.hub.blocked() or self.hub:running("meditate") then
        self:message("Turn Chamber / Auto Meditate off before equipping."); return
    end
    local now = os.clock()
    if now < (self.equipAfter or 0) then return end
    self.equipAfter = now + 0.5
    local ok, reason = pcall(function()
        local item = record.source
        if record.kind == "Accessory" then
            local weld = child(item, "Weld")
            self.hub:fire({"OutfitChange"}, "EquipAccessory", weld and weld.Value or "Head", record.name, 1)
        else
            local shirt = child(item, "Shirt1") or item:FindFirstChildOfClass("Shirt")
            local pants = child(item, "Pants1") or item:FindFirstChildOfClass("Pants")
            self.hub:fire({"OutfitChange"}, child(item, "OutfitAccessory") and "ClothingWithExtraAccessory" or "EquipClothing",
                shirt and shirt.ShirtTemplate or "", pants and pants.PantsTemplate or "", record.name)
        end
    end)
    if not self.live then return end
    if ok then self.saveDue = now + 1 end
    self:message(ok and "Equip requested; game save will be requested next."
        or "Equip unavailable: " .. tostring(reason))
end
function Cosmetics:step(now)
    if now >= self.nextRoots then
        self.nextRoots = now + 1
        local found = roots(self.hub.player)
        if self.dirty or not same(self.roots, found) then
            for _, record in ipairs(self.records) do if record.preview then record.preview:close() end end
            self:refresh(found)
        end
    end
    self.lastWork = 0
    while #self.jobs > 0 and self.lastWork < WORK and self.visited < LIMIT do
        self.lastWork = self.lastWork + 1
        local job = self.jobs[#self.jobs]
        local item = job.list[job.cursor]
        job.cursor = job.cursor + 1
        if not item then table.remove(self.jobs)
        else
            self.visited = self.visited + 1
            if item.Parent == job.parent then
                local ok = pcall(function()
                    if job.kind == "folder" then self:job(item, "drop")
                    elseif job.kind == "title" then
                        local lock = child(item, "Lock")
                        if lock and lock:IsA("GuiObject") then self.scope:set(lock, "Visible", false) end
                    else self:add(item, job.kind == "drop") end
                end)
                if not ok then self.failures = self.failures + 1 end
            end
        end
    end
    if self.visited >= LIMIT then self.jobs = {} end
    if self.browserDirty and (now >= self.nextBrowser or #self.jobs == 0) then
        self.hub.cosmeticBrowser:setItems(self.items)
        self.browserDirty, self.nextBrowser = false, now + 0.5
    end
    self:previews()
    if self.saveDue and now >= self.saveDue then self:save() end
    local state = #self.jobs > 0 and "Loading local catalog" or "Local catalog ready"
    if not self.roots.outfits and not self.roots.drops then state = "Waiting for the game's cosmetic catalog" end
    if self.visited >= LIMIT then state = "Catalog limit reached (2048)" end
    if self.failures > 0 then state = state .. "; " .. self.failures .. " entries skipped" end
    self.hub:status("cosmetics", state .. " · " .. #self.items .. " items")
end
function Cosmetics:destroy()
    self.live, self.saveDue = false, nil
    for _, record in ipairs(self.records) do if record.preview then record.preview:close() end end
    if self.scope then self.scope:close() end
    self.items, self.records, self.jobs = {}, {}, {}
    self.hub.cosmeticBrowser:setItems({})
    self:message("Enable Cosmetic Unlocker to browse.")
end
return Cosmetics
