-- Optional hub tools. Chamber and overnight remain owned by Engine/Main.
local Catalog = {}
Catalog.pages = {"Movement", "Combat", "Visuals", "QOL", "Travel"}
Catalog.controls = {
    {"Movement", "speed", "Speed Boost", "toggle"},
    {"Movement", "walkSpeed", "Walk Speed", "slider", 16, 300, 50},
    {"Movement", "jump", "Infinite Jump", "toggle"},
    {"Movement", "noclip", "Noclip", "toggle"},
    {"Movement", "flight", "Saiyan Flight · WASD / E up / Q down", "toggle"},
    {"Movement", "flightSpeed", "Flight Speed", "slider", 20, 250, 70},
    {"Combat", "punch", "Auto Fast Punch (STA)", "toggle"},
    {"Combat", "blast", "Auto Ki Blast Stream", "toggle"},
    {"Combat", "block", "Auto Block / Parry", "toggle"},
    {"Combat", "lock", "Face Nearest Player", "toggle"},
    {"Combat", "transform", "Auto Super Saiyan Transformation", "toggle"},
    {"Combat", "recharge", "Recharge Ki", "button"},
    {"Visuals", "cosmetics", "Cosmetic Unlocker · local catalog", "toggle"},
    {"Visuals", "players", "Ki Sense · Player ESP", "toggle"},
    {"Visuals", "npcs", "NPC / Mob ESP", "toggle"},
    {"Visuals", "bright", "Fullbright Lighting", "toggle"},
    {"Visuals", "sky", "Clear Sky / Remove Fog", "toggle"},
    {"Visuals", "fov", "Camera Field of View", "slider", 70, 120, 70},
    {"QOL", "meditate", "Auto Meditate · solve an active round", "toggle"},
    {"QOL", "charge", "Auto Ki Charge", "toggle"},
    {"QOL", "radar", "Dragon Ball Radar & Notifier", "toggle"},
    {"QOL", "save", "Auto Save Player Data · every 30s", "toggle"},
    {"QOL", "antiAfk", "Anti-AFK Protection", "toggle"},
    {"QOL", "shake", "Reduce Screen Shake", "toggle"},
    {"QOL", "questName", "Quest Name", "text", "MilkMission", "quest"},
    {"QOL", "questDragonStones", "Dragon Stones Amount", "text", "999", "amount"},
    {"QOL", "questZeni", "Zeni Amount", "text", "99999", "amount"},
    {"QOL", "questSuperStones", "Super Dragon Stones Reward", "text", "999", "amount"},
    {"QOL", "dragonStones", "Dragon Stones Quest · once per enable", "toggle"},
    {"QOL", "superStoneTarget", "Super Dragon Stones Local Target", "text", "999999", "amount"},
    {"QOL", "superStones", "Super Dragon Stones · local lock", "toggle"},
    {"Travel", "enterHTC", "Enter HTC · bypass costs 60,000 Zeni", "button"},
}
Catalog.destinations = {
    {"earth", "Earth Central Spawn", nil, -2460, 1242, 16825},
    {"west", "West City", "Travel Pilot (West)", -1200, 240, -2500},
    {"satan", "Satan City", "Travel Pilot (Satan)", 2800, 240, 1200},
    {"ginger", "Ginger Town", "Travel Pilot (Lucca)", -4500, 240, 3200},
    {"nams", "Nam's Village", "Travel Pilot (Nams)", 4800, 240, -1800},
    {"popo", "Mr. Popo · HTC Entrance", "Mr. Popo (HTC)", 7452, 3780, 8063},
    {"kame", "Kame House · Master Roshi", "Master Roshi [Mini-Game]", 18227, -680, 8224},
    {"gravity", "Gravity Chamber", nil, 6666, -553, 14673},
    {"dummies", "Training Dummies", nil, -98, 253, -551},
}
for _, destination in ipairs(Catalog.destinations) do
    Catalog.controls[#Catalog.controls + 1] = {"Travel", destination[1], destination[2], "button"}
end
return Catalog
