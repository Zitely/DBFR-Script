-- Downloads and caches the self-contained bundle; alternatively paste dist/chamber.lua.
local url = "https://raw.githubusercontent.com/Zitely/DBFR-Script/main/dist/chamber.lua"
local env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then env = result end
end
env = type(env) == "table" and env or {}
local compile = type(loadstring) == "function" and loadstring or env.loadstring
if type(compile) ~= "function" then
    error("Chamber loader: loadstring is unavailable. Paste the complete dist/chamber.lua file directly into your executor instead of the loader.", 0)
end
local fetched, source = pcall(function() return game:HttpGet(url) end)
if not fetched then
    error("Chamber download failed: " .. tostring(source) .. ". You can paste the complete dist/chamber.lua file directly instead.", 0)
end
if type(source) ~= "string" or source:match("^%s*$") then
    error("Chamber download failed: the response was not a nonempty script.", 0)
end
local compiled, chunk, compileError = pcall(compile, source, "DBFR Chamber")
if not compiled then
    error("Chamber compilation failed: " .. tostring(chunk), 0)
end
if type(chunk) ~= "function" then
    error("Chamber compilation failed: " .. tostring(compileError or "loadstring did not return a function"), 0)
end
if type(env.writefile) == "function" and type(env.makefolder) == "function" then
    pcall(function()
        pcall(env.makefolder, "DBFR_Lua")
        env.writefile("DBFR_Lua/chamber.lua", source)
    end)
end
local started, app = xpcall(chunk, function(reason)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        return debug.traceback(tostring(reason), 2)
    end
    return tostring(reason)
end)
if not started then error("Chamber startup failed: " .. tostring(app), 0) end
return app
