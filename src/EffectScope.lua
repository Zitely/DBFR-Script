-- Restore only properties this effect still owns; never destroy game objects.
local Scope = {}
Scope.__index = Scope
function Scope.new() return setmetatable({properties = {}, cleanup = {}}, Scope) end
function Scope:set(object, key, value)
    local properties = self.properties[object]
    if not properties then properties = {}; self.properties[object] = properties end
    local entry = properties[key]
    if not entry then entry = {original = object[key]}; properties[key] = entry end
    object[key] = value
    entry.last = value
end
function Scope:restore(object)
    for key, entry in pairs(self.properties[object] or {}) do
        pcall(function() if object[key] == entry.last then object[key] = entry.original end end)
    end
    self.properties[object] = nil
end
function Scope:own(object)
    self.cleanup[#self.cleanup + 1] = function() object:Destroy() end
    return object
end
function Scope:connect(signal, callback)
    local connection = signal:Connect(callback)
    self.cleanup[#self.cleanup + 1] = function() connection:Disconnect() end
    return connection
end
function Scope:close()
    for i = #self.cleanup, 1, -1 do pcall(self.cleanup[i]) end
    self.cleanup = {}
    for object in pairs(self.properties) do self:restore(object) end
end
return Scope
