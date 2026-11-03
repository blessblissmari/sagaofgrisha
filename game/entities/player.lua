-- Гриша in the world: walks, swings a stick (attack), throws stones and
-- plays footsteps that depend on the surface under his feet.

local Entity = require("engine.entity")
local anim = require("engine.anim")
local audio = require("engine.audio")
local class = require("engine.class")
local input = require("engine.input")
local ui = require("engine.ui")
local util = require("engine.util")

local function G()
    return require("game")
end

local Player = class(Entity)

Player.DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- opts: sprite (name in game.sprites, default game.player.sprite)
function Player:init(x, y, opts)
    Entity.init(self, x, y)
    opts = opts or {}
    self.sprite = anim.new(G().sprite(opts.sprite or G().player.sprite))
    self.w, self.h = 14, 8
    self.height = 30
    self.speed = 105
    self.facing = "down"
    self.team = "player"
    self.hp, self.maxHp = G().state.hp, G().state.maxHp
    self.iframes = 1.2
    self.attackTime, self.cooldown = 0, 0
    self.stepTimer = 0.2
    self.lastDx, self.lastDy = 0, 1
    self.controllable = true
    self.isMoving = false
    self.shadow = 9
end

function Player:update(dt)
    Entity.update(self, dt)
    self.cooldown = math.max(0, self.cooldown - dt)
    self.attackTime = math.max(0, self.attackTime - dt)
    local dx, dy = 0, 0
    if self.controllable and not self.dying and not (self.world and self.world.frozen) then
        dx, dy = input.direction()
        if input.pressed("attack") and self.cooldown <= 0 then
            self:attack()
        elseif input.pressed("throw") and self.cooldown <= 0 then
            self:throw()
        end
    end
    if self.attackTime > 0 then
        dx, dy = 0, 0
    end
    self.isMoving = dx ~= 0 or dy ~= 0
    if self.isMoving then
        local nx, ny = util.normalize(dx, dy)
        self:moveBy(nx * self.speed * dt, ny * self.speed * dt)
        self.lastDx, self.lastDy = dx, dy
        if math.abs(dx) > math.abs(dy) then
            self.facing = dx > 0 and "right" or "left"
        else
            self.facing = dy > 0 and "down" or "up"
        end
        self.stepTimer = self.stepTimer + dt
        if self.stepTimer >= 0.3 then
            self.stepTimer = 0
            self:footstep()
        end
    else
        self.stepTimer = 0.2 -- the first step sounds right away
    end
    if self.attackTime > 0 then
        self.sprite:play("hit", self.facing)
    elseif self.isMoving then
        self.sprite:play("walk", self.facing)
    else
        self.sprite:play("idle", self.facing)
    end
    self.sprite:update(dt)
end

function Player:surface()
    local surfaces = G().surfaces
    return self.world and self.world:surfaceAt(self.x, self.y - 2) or surfaces.default
end

local DUST = {
    water = { 0.65, 0.8, 1, 0.9 },
    wood = { 0.5, 0.36, 0.22, 0.7 },
    stone = { 0.8, 0.78, 0.72, 0.6 },
    grass = { 0.45, 0.62, 0.25, 0.7 },
}

function Player:footstep()
    local surfaces = G().surfaces
    local name = self:surface() or surfaces.default
    local s = surfaces[name] or surfaces[surfaces.default]
    audio.step(s.folder, { volume = s.volume })
    if self.world and self.world.fx then
        self.world.fx:burst(self.x, self.y - 1, {
            count = 3, color = DUST[name] or DUST.grass, speed = 22, life = 0.35,
            size = 2, up = 12, gravity = 70, angle = -math.pi / 2, spread = 1.2,
        })
    end
end

function Player:attack()
    self.attackTime = 0.2
    self.cooldown = 0.32
    self.sprite:play("hit", self.facing, true)
    audio.play("swing")
    local d = Player.DIRECTIONS[self.facing]
    local cx, cy = self.x + d[1] * 18, self.y - 10 + d[2] * 16
    local w, h = 30, 28
    local hit = false
    local targets = self.world:query(cx - w / 2, cy - h / 2, w, h, function(e)
        return e.team == "enemy"
    end)
    for _, e in ipairs(targets) do
        if e:hurt(1, { from = self, knockback = 240, attacker = self }) then
            hit = true
            self.world.fx:play("slash", e.x, e.y - 12, { scale = 0.45 })
        end
    end
    if hit then
        audio.play("hit")
        self.world.camera:shake(3, 0.15)
    end
end

function Player:throw()
    if not G().state.inventory:remove("stone") then
        ui.toast("Нет камней. Поищи на острове!", { icon = "stone" })
        audio.play("error")
        self.cooldown = 0.3
        return
    end
    self.cooldown = 0.45
    self.attackTime = 0.15
    self.sprite:play("hit", self.facing, true)
    audio.play("throw")
    audio.play("viu", { volume = 0.4 })
    local Projectile = require("game.entities.projectile")
    local d = Player.DIRECTIONS[self.facing]
    self.world:add(Projectile(self.x + d[1] * 10, self.y - 1 + d[2] * 4, d[1], d[2], self))
end

function Player:onHurt(amount)
    G().state.hp = self.hp
    audio.play("hurt")
    if self.world then
        self.world.camera:shake(5, 0.25)
        self.world.fx:popup(self.x, self.y - 40, "-" .. amount, { color = { 1, 0.35, 0.3 } })
    end
    if self.hp > 0 and self.hp <= 2 then
        audio.play("lowhp")
        audio.play("sos", { volume = 0.6 })
    end
end

function Player:onDeath()
    self.dying = true
    self.controllable = false
    audio.play("death")
end

function Player:heal(amount)
    self.hp = math.min(self.maxHp, self.hp + amount)
    G().state.hp = self.hp
end

function Player:draw()
    self:drawSprite()
end

return Player
