return function(test, equal, mock)
    local Main = require("src.Main")
    local function catalogItem(folder, name, kind, extra)
        local item = mock.object("Model", name, folder)
        mock.object("StringValue", "Type", item, {Value = kind or "Clothing"})
        mock.object("StringValue", "Rarity", item, {Value = "Rare"})
        if kind == "Accessory" then mock.object("StringValue", "Weld", item, {Value = "Torso"})
        else
            mock.object("Shirt", "Shirt1", item, {ShirtTemplate = "rbxassetid://123"})
            mock.object("Pants", "Pants1", item, {PantsTemplate = "rbxassetid://456"})
        end
        if extra then mock.object("Folder", "OutfitAccessory", item) end
        return item
    end
    local function nativeUI(parent)
        local clothing = mock.object("Frame", "Clothing", parent, {Visible = false})
        for _, name in ipairs({"Outfits", "Accessories", "Weapons"}) do mock.object("ScrollingFrame", name, clothing) end
        local template = mock.object("ImageButton", "Template", mock.object("LocalScript", "ClothingScript", clothing), {Visible = false})
        mock.object("TextLabel", "OutfitName", template)
        mock.object("TextLabel", "Rarity", template)
        mock.object("ViewportFrame", "ViewportFrame", template)
        for _, name in ipairs({"ClothingEquip", "AccessoryEquip", "WeaponEquip"}) do
            mock.object("LocalScript", name, template, {Disabled = true})
        end
        return clothing
    end
    local function fixture(count)
        mock.reset()
        local outfits = mock.object("Folder", "Outfits", mock.replicatedStorage)
        if count then
            for i = 1, count do catalogItem(outfits, "Outfit " .. i) end
        else
            catalogItem(outfits, "Training Gi")
            catalogItem(outfits, "Scouter", "Accessory")
            catalogItem(outfits, "Sword", "Weapon")
            catalogItem(outfits, "Cape Gi", "Clothing", true)
            catalogItem(outfits, "[Training] 100%")
        end
        local placeholder = mock.object("ScreenGui", "PlaceHolder", mock.playerGui)
        local clothing = nativeUI(placeholder)
        local owned = mock.object("ImageButton", "Training Gi", clothing:FindFirstChild("Outfits"))
        local titles = mock.object("Frame", "ChatTitles", mock.object("Frame", "StylesFrame", placeholder))
        local lock = mock.object("Frame", "Lock", mock.object("TextButton", "Champion", titles))
        local drops = mock.object("Folder", "UnlockStuffs", mock.object("Folder", "PlayerGui",
            mock.object("Folder", "CharacterStuff", mock.replicatedStorage)))
        local drop = mock.object("Frame", "Exclusive Mask", mock.object("Folder", "Drops", drops), {Visible = false})
        local remotes = mock.object("Folder", "Remotes", mock.replicatedStorage)
        local equip, save = mock.object("RemoteEvent", "OutfitChange", remotes), mock.object("RemoteEvent", "SaveData", remotes)
        local calls, saves = {}, {}
        equip.FireServer = function(_, ...) calls[#calls + 1] = {...} end
        save.FireServer = function(_, ...) saves[#saves + 1] = {...} end
        local app = Main.start()
        return {app = app, hub = app.features, clothing = clothing, placeholder = placeholder, outfits = outfits,
            owned = owned, lock = lock, drop = drop, calls = calls, saves = saves, equip = equip, save = save}
    end
    local function enable(f)
        f.hub:set("cosmetics", true)
        for _ = 1, 8 do mock.tick(0.06) end
        return f.hub.contexts.cosmetics.cosmetics
    end
    local function selectItem(f, name)
        local browser = f.hub.cosmeticBrowser
        browser.search.Text = name
        browser.rows[1].button.Activated:Fire()
    end
    test("cosmetics populate native categories and titles without altering existing inventory", function()
        local f = fixture()
        equal(f.hub.enabled.cosmetics, nil); equal(f.app.ui.minimized, true)
        local tool = enable(f)
        equal(#tool.items, 6); equal(f.lock.Visible, false)
        local accessories = f.clothing:FindFirstChild("Accessories")
        local scouter = assert(accessories:FindFirstChild("Scouter"))
        equal(scouter:FindFirstChild("AccessoryEquip").Disabled, false)
        equal(scouter:FindFirstChild("ClothingEquip").Disabled, true)
        equal(scouter:FindFirstChild("Rarity").Text, "Rare")
        assert(accessories:FindFirstChild("Exclusive Mask")); equal(f.drop.Visible, false)
        equal(f.clothing:FindFirstChild("Weapons"):FindFirstChild("Sword"):FindFirstChild("WeaponEquip").Disabled, false)
        equal(f.clothing:FindFirstChild("Outfits"):FindFirstChild("Training Gi"), f.owned)
        equal(#f.calls, 0); equal(#f.saves, 0); equal(tool.previewCount, 0)
        local scope = tool.scope
        f.hub:set("cosmetics", false)
        equal(f.lock.Visible, true); equal(scouter.Parent, nil); equal(f.owned.Parent, f.clothing:FindFirstChild("Outfits"))
        equal(#f.hub.cosmeticBrowser.items, 0); equal(#scope.cleanup, 0)
        for _, signal in ipairs({f.outfits.DescendantAdded, f.outfits.DescendantRemoving}) do
            for _, connection in ipairs(signal.listeners) do equal(connection.Connected, false) end
        end
        f.app.unload()
    end)
    test("cosmetic quick equip uses supplied request forms and coalesces best effort saves", function()
        local f = fixture(); local tool = enable(f)
        selectItem(f, "Training Gi")
        equal(table.concat(f.calls[1], ","), "EquipClothing,rbxassetid://123,rbxassetid://456,Training Gi")
        equal(#f.saves, 0)
        mock.tick(0.6); selectItem(f, "Scouter")
        equal(table.concat(f.calls[2], ","), "EquipAccessory,Torso,Scouter,1")
        mock.tick(1.1); equal(#f.saves, 1); equal(#f.saves[1], 0)
        assert(f.app.ui.controls.cosmeticBrowser.status.Text:find("unconfirmed", 1, true))
        selectItem(f, "Cape Gi")
        equal(f.calls[3][1], "ClothingWithExtraAccessory")
        mock.tick(1.1); equal(#f.saves, 1)
        f.hub.cosmeticBrowser.save.Activated:Fire(); equal(#f.saves, 1)
        mock.tick(10); equal(#f.saves, 2)
        selectItem(f, "Sword"); equal(#f.calls, 3)
        assert(f.app.ui.controls.cosmeticBrowser.status.Text:find("game's Weapon menu", 1, true))
        f.hub.cosmeticBrowser.save.Activated:Fire()
        assert(tool.saveDue)
        f.hub:set("cosmetics", false); mock.tick(30); equal(#f.saves, 2)
        f.app.unload()
    end)
    test("cosmetic search treats patterns literally and reuses six rows across pages", function()
        local f = fixture(20); enable(f)
        for _ = 1, 12 do mock.tick(0.06) end
        local browser = f.hub.cosmeticBrowser
        equal(#browser.items, 21); equal(#browser.rows, 6)
        local first = browser.rows[1].item
        browser.next.Activated:Fire(); equal(browser.page, 2); assert(browser.rows[1].item ~= first)
        browser.previous.Activated:Fire(); equal(browser.rows[1].item, first)
        browser.search.Text = "["; equal(#browser.matches, 0)
        browser.search.Text = "%"; equal(#browser.matches, 0)
        catalogItem(f.outfits, "[Training] 100%")
        mock.tick(1.1)
        for _ = 1, 12 do mock.tick(0.06) end
        equal(#browser.matches, 1); equal(browser.rows[1].item.name, "[Training] 100%")
        equal(#browser.rows, 6); f.app.unload()
    end)
    test("cosmetics follow replacement UI and late catalogs with no world scans", function()
        local f = fixture(); local tool = enable(f)
        local old = f.clothing
        old:Destroy()
        f.clothing = nativeUI(f.placeholder)
        catalogItem(f.outfits, "Late Outfit")
        mock.resetMetrics(); mock.tick(1.1)
        for _ = 1, 8 do mock.tick(0.06) end
        assert(f.clothing:FindFirstChild("Outfits"):FindFirstChild("Late Outfit"))
        equal(mock.metrics.fullScans, 0); equal(#tool.items, 7)
        f.app.unload(); equal(#f.clothing:FindFirstChild("Outfits"):GetChildren(), 0)
        mock.reset(); local app = Main.start(); app.features:set("cosmetics", true); mock.tick()
        assert(app.ui.controls.cosmetics.status.Text:find("Waiting", 1, true))
        local outfits = mock.object("Folder", "Outfits", mock.replicatedStorage)
        catalogItem(outfits, "Late catalog")
        mock.tick(1.1); equal(#app.features.cosmeticBrowser.items, 1)
        app.unload()
    end)
    test("cosmetic discovery and previews remain bounded for large inventories", function()
        local f = fixture(3000)
        f.hub:set("cosmetics", true); mock.resetMetrics(); mock.tick()
        local tool = f.hub.contexts.cosmetics.cosmetics
        assert(tool.lastWork <= 4); assert(#tool.records <= 4); equal(tool.previewCount, 0)
        f.clothing.Visible = true
        mock.tick(0.06); assert(tool.previewCount <= 2)
        for _ = 1, 14 do mock.tick(0.06); assert(tool.lastWork <= 4); assert(tool.previewCount <= 12) end
        equal(tool.previewCount, 12); equal(mock.metrics.fullScans, 0)
        f.clothing.Visible = false
        for _ = 1, 5 do mock.tick(0.06) end
        equal(tool.previewCount, 0)
        -- A huge source has a finite discovery limit and does not grow forever.
        for _ = 1, 520 do mock.tick(0.06); assert(tool.lastWork <= 4) end
        equal(tool.visited, 2048); equal(#tool.jobs, 0); equal(#tool.items, 2048)
        f.app.unload()
        equal(#f.clothing:FindFirstChild("Outfits"):GetChildren(), 1)
    end)
    test("failed cosmetic requests do not promise saves or retry and unload cancels pending work", function()
        local f = fixture(); enable(f)
        f.equip:Destroy(); selectItem(f, "Scouter"); mock.tick(2)
        equal(#f.calls, 0); equal(#f.saves, 0)
        assert(f.app.ui.controls.cosmeticBrowser.status.Text:find("Equip unavailable", 1, true))
        f.save:Destroy(); f.hub.cosmeticBrowser.save.Activated:Fire()
        assert(f.app.ui.controls.cosmeticBrowser.status.Text:find("Save unavailable", 1, true))
        f.app.unload()
        f = fixture(); enable(f)
        selectItem(f, "Scouter"); f.app.unload(); mock.tick(30)
        equal(#f.calls, 1); equal(#f.saves, 0)
        local app = Main.start(); equal(app.features.enabled.cosmetics, nil); app.unload()
    end)
    test("cosmetic quick equip pauses during Chamber and ignores stale catalog records", function()
        local f = fixture(); local tool = enable(f)
        local stale = tool.items[1]
        f.app.toggle(); selectItem(f, "Scouter"); equal(#f.calls, 0)
        f.app.toggle()
        stale.source:Destroy(); mock.tick(1.1)
        tool:equip(stale); equal(#f.calls, 0)
        assert(f.app.ui.controls.cosmeticBrowser.status.Text:find("Catalog changed", 1, true))
        f.app.unload()
    end)
end
