-- Base class for everything that lives in a World: the player, mobs, pickups.
--
-- (x, y) is the point between the feet. The collision box (w x h) is
-- centered on x and ends at y, so tall sprites can overlap walls above them
-- like in most top-down games.
--
--   local Mob = class(Entity)
--   function Mob:init(x, y) Entity.init(self, x, y); self.hp = 3 end
--   function Mob:update(dt) Entity.update(self, dt); self:moveBy(10 * dt, 0) end

local class = require("engine.class")
local shaders = require("engine.shaders")
local util = require("engine.util")

local Entity = class()

local nextId = 0

function Entity:init(x, y)
    nextId = nextId + 1
    self.id = nextId
    self.x, self.y = x or 0, y or 0
    self.w, self.h = 12, 8       -- feet collision box
    self.height = 24             -- visual height (effects, health bars)
    self.vx, self.vy = 0, 0      -- push velocity (knockback), slows down by itself
    self.friction = 10
    self.shadow = 8              -- shadow radius, false = no shadow
    self.solid = true            -- stopped by walls
    self.reflect = true          -- mirrored in water
    self.team = nil              -- "player" / "enemy": who can hurt whom
    self.flash = 0               -- > 0: drawn white (just got hit)
    self.invulnerable = 0
    self.removed = false
end

function Entity:getBox()
    return self.x - self.w / 2, self.y - self.h, self.w, self.h
end

function Entity:center()
    return self.x, self.y - self.height / 2
end

function Entity:distanceTo(other)
    return util.distance(self.x, self.y, other.x, other.y)
end

function Entity:moveBy(dx, dy)
    if self.world then
        return self.world:move(self, dx, dy)
    end
    self.x, self.y = self.x + dx, self.y + dy
    return false, false
end

function Entity:push(dx, dy, strength)
    local nx, ny = util.normalize(dx, dy)
    self.vx, self.vy = nx * strength, ny * strength
end

function Entity:remove()
    self.removed = true
end

-- Damage with a white flash, knockback and a short invulnerability.
-- opts: from (entity or {x, y}), knockback (speed), iframes (seconds)
-- Returns true if the hit landed.
function Entity:hurt(amount, opts)
    opts = opts or {}
    if self.removed or self.dying or self.invulnerable > 0 or not self.hp then
        return false
    end
    self.hp = math.max(0, self.hp - amount)
    self.flash = 0.18
    self.invulnerable = opts.iframes or self.iframes or 0.5
    if opts.from and (opts.knockback or 0) > 0 then
        self:push(self.x - opts.from.x, self.y - opts.from.y, opts.knockback)
    end
    if self.onHurt then
        self:onHurt(amount, opts)
    end
    if self.hp <= 0 and self.onDeath then
        self:onDeath(opts)
    end
    return true
end

function Entity:update(dt)
    if self.vx ~= 0 or self.vy ~= 0 then
        self:moveBy(self.vx * dt, self.vy * dt)
        local k = math.exp(-self.friction * dt)
        self.vx, self.vy = self.vx * k, self.vy * k
        if math.abs(self.vx) + math.abs(self.vy) < 2 then
            self.vx, self.vy = 0, 0
        end
    end
    self.flash = math.max(0, self.flash - dt)
    self.invulnerable = math.max(0, self.invulnerable - dt)
end

function Entity:drawShadow()
    if not self.shadow then
        return
    end
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.ellipse("fill", math.floor(self.x + 0.5), math.floor(self.y + 0.5), self.shadow, self.shadow * 0.4)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draws self.sprite (engine.anim) with the hit flash and blinking while
-- invulnerable. opts are passed to sprite:draw().
function Entity:drawSprite(opts)
    if not self.sprite then
        return
    end
    opts = opts or {}
    if self.invulnerable > 0 and self.flash <= 0 and math.floor(self.invulnerable * 20) % 2 == 0 then
        opts.color = { 1, 1, 1, 0.45 }
    end
    local flash = self.flash > 0 and shaders.get("flash")
    if flash then
        shaders.send(flash, "amount", 1)
        shaders.send(flash, "flashColor", { 1, 1, 1 })
        love.graphics.setShader(flash)
    end
    self.sprite:draw(self.x, self.y - (self.z or 0), opts)
    if flash then
        love.graphics.setShader()
    end
end

function Entity:draw()
    self:drawSprite({ flip = self.flipX })
end

-- Mirrored copy for water reflections (see World and water.glsl).
function Entity:drawReflection()
    if self.sprite then
        self.sprite:draw(self.x, self.y + (self.z or 0), { flip = self.flipX, flipY = true })
    end
end

return Entity
