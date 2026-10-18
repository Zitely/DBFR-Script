-- Downloads and caches the self-contained bundle; alternatively paste dist/chamber.lua.
local url = "https://raw.githubusercontent.com/Zitely/DBFR-Script/main/dist/chamber.lua"
local source = game:HttpGet(url)
local chunk = assert(loadstring(source, "DBFR Chamber"))
local env = type(getgenv) == "function" and getgenv() or _G
if type(env.writefile) == "function" and type(env.makefolder) == "function" then
    pcall(function()
        pcall(env.makefolder, "DBFR_Lua")
        env.writefile("DBFR_Lua/chamber.lua", source)
    end)
end
return chunk()
