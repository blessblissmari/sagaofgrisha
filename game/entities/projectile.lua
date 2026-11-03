-- A thrown stone: flies in an arc, hurts the first enemy it touches and
-- lands as a stone that can be picked up again.

local Entity = require("engine.entity")
local assets = require("engine.assets")
local audio = require("engine.audio")
local class = require("engine.class")
local Pickup = require("game.entities.pickup")

local Projectile = class(Entity)

local SPEED, FLIGHT = 260, 0.6

function Projectile:init(x, y, dx, dy, owner)
    Entity.init(self, x, y)
    self.owner = owner
    self.dirX, self.dirY = dx, dy
    self.time = 0
    self.w, self.h = 6, 6
    self.shadow = 4
    self.reflect = false
    self.icon = assets.image("assets/sprites/icons/stone.png", { filter = "linear" })
end

function Projectile:land()
    self:remove()
    audio.play("land")
    self.world.fx:burst(self.x, self.y, { count = 6, color = { 0.8, 0.78, 0.7 }, speed = 40, life = 0.3 })
    local col, row = self.world:tileAt(self.x, self.y)
    if not self.world:isSolidTile(col, row) then
        self.world:add(Pickup("stone", self.x, self.y, { auto = true }))
    end
end

function Projectile:update(dt)
    self.time = self.time + dt
    local k = self.time / FLIGHT
    self.z = math.sin(math.min(k, 1) * math.pi) * 18 + 6 * (1 - k)
    local hitX, hitY = self:moveBy(self.dirX * SPEED * dt, self.dirY * SPEED * dt)
    if hitX or hitY or k >= 1 then
        self:land()
        return
    end
    local x, y, w, h = self:getBox()
    for _, e in ipairs(self.world:query(x - 4, y - 8, w + 8, h + 12, function(e) return e.team == "enemy" end)) do
        if e:hurt(2, { from = self, knockback = 200, attacker = self.owner }) then
            audio.play("hit")
            self.world.fx:play("magic", e.x, e.y - 12, { scale = 0.4 })
            self.world.camera:shake(3, 0.15)
            self:land()
            return
        end
    end
end

function Projectile:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.icon, math.floor(self.x), math.floor(self.y - self.z), self.time * 12, 0.4, 0.4, 17, 17)
end

return Projectile
