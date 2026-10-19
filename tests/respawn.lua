return function(test, equal, mock)
    local Respawn = require("src.Respawn")
    test("direct recovery resets only an alive character at health two or lower", function()
        mock.reset()
        local breaks = 0
        mock.character.BreakJoints = function() breaks = breaks + 1 end
        mock.humanoid.Health = 2
        equal(Respawn.resetIfNeeded(mock.player), true)
        equal(mock.humanoid.Health, 0); equal(breaks, 1)
        equal(Respawn.resetIfNeeded(mock.player), false)
        mock.humanoid.Health = 3
        equal(Respawn.resetIfNeeded(mock.player), false)
    end)
end
