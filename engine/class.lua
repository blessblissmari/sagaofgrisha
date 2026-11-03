-- Minimal classes.
--
--   local Mob = class()
--   function Mob:init(x, y) self.x, self.y = x, y end
--   local Boss = class(Mob)                  -- inherits everything from Mob
--   function Boss:init(x, y) Mob.init(self, x, y); self.hp = 100 end
--
--   local boss = Boss(10, 20)                -- creates an object and calls init

return function(parent)
    local c = {}
    c.__index = c
    c.super = parent
    return setmetatable(c, {
        __index = parent,
        __call = function(cls, ...)
            local object = setmetatable({}, cls)
            if object.init then
                object:init(...)
            end
            return object
        end,
    })
end
