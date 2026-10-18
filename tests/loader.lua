return function(test, equal)
    local function compileIn(source, name, environment)
        if type(setfenv) == "function" then
            local chunk, reason = loadstring(source, name)
            if chunk then setfenv(chunk, environment) end
            return chunk, reason
        end
        return load(source, name, "t", environment)
    end
    local function run(options)
        options = options or {}
        local sandbox, capabilities, saved, requests, compiledSources = {}, {}, {}, {}, {}
        sandbox._G = sandbox
        sandbox.getgenv = options.getgenv or function() return capabilities end
        sandbox.game = {HttpGet = function(_, url)
            requests[#requests + 1] = url
            if options.httpError then error(options.httpError) end
            return options.source or "return {loaded = true}"
        end}
        capabilities.makefolder = function() end
        capabilities.writefile = function(path, contents) saved[path] = contents end
        local compiler = function(source, name)
            compiledSources[#compiledSources + 1] = source
            return compileIn(source, name, sandbox)
        end
        if options.envCompiler then capabilities.loadstring = compiler end
        setmetatable(sandbox, {__index = function(_, name)
            if name == "loadstring" then
                if options.noCompiler or options.envCompiler then return nil end
                return compiler
            end
            return _G[name]
        end})
        local file = assert(io.open("loader.lua", "r"))
        local source = file:read("*a")
        file:close()
        local loader = assert(compileIn(source, "@loader.lua", sandbox))
        local ok, result = pcall(loader)
        return ok, result, requests, saved, compiledSources
    end
    test("loader reports absent loadstring before downloading", function()
        local ok, reason, requests = run({noCompiler = true})
        equal(ok, false); assert(reason:find("loadstring is unavailable", 1, true))
        equal(#requests, 0)
    end)
    test("loader uses the executor environment's compiler when available", function()
        local ok, result = run({envCompiler = true})
        equal(ok, true); equal(result.loaded, true)
    end)
    test("loader identifies HTTP failure separately from compilation", function()
        local ok, reason = run({httpError = "HTTP unavailable"})
        equal(ok, false); assert(reason:find("Chamber download failed:", 1, true))
        assert(reason:find("HTTP unavailable", 1, true))
    end)
    test("loader reports compilation errors instead of calling nil", function()
        local ok, reason, _, saved = run({source = "local = broken Lua"})
        equal(ok, false); assert(reason:find("Chamber compilation failed:", 1, true))
        equal(next(saved), nil)
    end)
    test("loader explains GitHub 404 without compiling or caching its body", function()
        local ok, reason, _, saved, compiled = run({source = "  404: Not Found\n"})
        equal(ok, false); assert(reason:find("GitHub returned 404", 1, true))
        assert(reason:find("private repository", 1, true))
        equal(#compiled, 0); equal(next(saved), nil)
    end)
    test("loader rejects an HTML login or error page before compilation", function()
        local ok, reason, _, saved, compiled = run({source = "\n<!DOCTYPE html><html>Sign in</html>"})
        equal(ok, false); assert(reason:find("HTML page instead of Lua", 1, true))
        equal(#compiled, 0); equal(next(saved), nil)
    end)
    test("loader rejects empty or non-string HTTP responses", function()
        for _, source in ipairs({"   ", {Body = "wrong HTTP API"}}) do
            local ok, reason = run({source = source})
            equal(ok, false); assert(reason:find("not a nonempty script", 1, true))
        end
    end)
    test("loader retains named startup errors and traceback", function()
        local ok, reason = run({source = "error('UI initialization example')"})
        equal(ok, false); assert(reason:find("Chamber startup failed:", 1, true))
        assert(reason:find("UI initialization example", 1, true))
        assert(reason:find("DBFR Chamber", 1, true))
    end)
    test("loader returns the app and caches the fetched bundle", function()
        local ok, result, requests, saved = run()
        equal(ok, true); equal(result.loaded, true)
        equal(requests[1], "https://raw.githubusercontent.com/Zitely/DBFR-Script/main/dist/chamber.lua")
        equal(saved["DBFR_Lua/chamber.lua"], "return {loaded = true}")
    end)
    test("loader tolerates a failing optional getgenv function", function()
        local ok, result = run({getgenv = function() error("unsupported") end})
        equal(ok, true); equal(result.loaded, true)
    end)
end
