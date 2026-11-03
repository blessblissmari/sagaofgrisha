-- An enemy of the platformer. Everything comes from game/data/mobs.lua:
--   ai            "walker" (turns at walls and ledges), "hopper" (jumps),
--                 "flyer" (floats, ignores walls), "hazard" (can't be killed)
--   platformSpeed walking speed
--   stomp         false = jumping on it hurts (default true)
--   invulnerable  true = punches and stones don't work
--   sideScale     sprite size in side view (default 1)
--   touch         "battle" = touching it starts a turn-based battle

local Entity = require("engine.entity")
local anim = require("engine.anim")
local audio = require("engine.audio")
local class = require("engine.class")
local physics = require("engine.physics")
local util = require("engine.util")

local function G()
    return require("game")
end

local SideMob = class(Entity)

function SideMob:init(kind, x, y, objectId)
    Entity.init(self, x, y)
    local def = assert(G().mobs[kind], "unknown mob: " .. tostring(kind))
    self.kind, self.def = kind, def
    self.objectId = objectId
    local sprite = G().sprite(def.sprite or kind)
    self.sprite = anim.new(sprite)
    self.scale = def.sideScale or 1
    self.facesLeft = def.facesLeft or sprite.facesLeft
    local fw, fh = self.sprite.frameWidth * self.scale, self.sprite.frameHeight * self.scale
    self.w = def.box and def.box[1] or math.min(14, math.floor(fw * 0.75))
    self.h = def.box and def.box[2] or math.min(16, math.floor(fh * 0.7))
    self.height = self.h
    self.hp = def.hp or 2
    self.damage = def.damage or 1
    self.ai = def.ai or "walker"
    self.speed = def.platformSpeed or 30
    self.team = "enemy"
    self.shadow = false
    self.reflect = false
    self.iframes = 0.3
    self.dir = -1
    self.homeX, self.homeY = x, y
    self.time = love.math.random() * 4
    self.hopTimer = 0.8 + love.math.random()
    self.knockTime = 0
    self.stompable = def.stomp ~= false and not def.invulnerable
    self.flying = self.ai == "flyer"
    self.onGround = false
end

function SideMob:update(dt)
    self.flash = math.max(0, self.flash - dt)
    self.invulnerable = math.max(0, self.invulnerable - dt)
    self.time = self.time + dt
    self.sprite:update(dt)
    if self.dying then
        self.dying = self.dying - dt
        if self.dying <= 0 then
            self:remove()
        end
        return
    end
    if self.world.frozen then
        return
    end
    local world = self.world
    local player = world.player
    self.knockTime = math.max(0, self.knockTime - dt)

    if self.flying then
        -- floats around home, slowly follows the hero when he is close
        local tx = self.homeX + math.sin(self.time * 0.7) * 40
        local ty = self.homeY + math.sin(self.time * 2.1) * 6
        if player and not player.dying and util.distance(self.x, self.y, player.x, player.y) < 110 then
            tx, ty = player.x, player.y - 4
            self.homeX = util.approach(self.homeX, player.x, 10 * dt)
        end
        local nx, ny = util.normalize(tx - self.x, ty - self.y)
        local d = util.distance(self.x, self.y, tx, ty)
        local speed = math.min(self.speed, d * 3)
        if self.knockTime <= 0 then
            self.vx, self.vy = nx * speed, ny * speed
        end
        self.x, self.y = self.x + self.vx * dt, self.y + self.vy * dt
        if math.abs(self.vx) > 1 then
            self.dir = self.vx > 0 and 1 or -1
        end
        self.sprite:play("walk")
        return
    end

    -- ground creatures
    if self.knockTime <= 0 then
        if self.ai == "hopper" then
            if self.onGround then
                self.vx = 0
                self.hopTimer = self.hopTimer - dt
                if self.hopTimer <= 0 then
                    self.hopTimer = 1 + love.math.random() * 0.8
                    if player and math.abs(player.x - self.x) < 140 then
                        self.dir = player.x < self.x and -1 or 1
                    end
                    self.vy = -230
                    self.vx = self.dir * self.speed * 1.6
                    self.onGround = false
                end
            end
        else
            self.vx = self.dir * self.speed
        end
    end
    self.vy = math.min(self.vy + 900 * dt, 400)
    if physics.moveX(world, self, self.vx * dt) then
        self.dir = -self.dir
        if self.ai == "hopper" then
            self.vx = -self.vx
        end
    end
    local landed = physics.moveY(world, self, self.vy * dt)
    if landed then
        self.vy = 0
        self.onGround = true
    else
        self.onGround = self.vy >= 0 and physics.onGround(world, self)
    end
    -- walkers turn around at the edge of a platform
    if self.onGround and self.ai ~= "hopper" and self.knockTime <= 0 and not physics.groundAhead(world, self, self.dir) then
        self.dir = -self.dir
    end
    if self.y > world.height + 40 then
        self:remove()
    end
    if not self.onGround and self.sprite:has("jump") then
        self.sprite:play("jump")
    elseif math.abs(self.vx) > 1 then
        self.sprite:play("walk")
    else
        self.sprite:play("idle")
    end
end

-- punches and stones
function SideMob:hurt(amount, opts)
    if self.def.invulnerable then
        if opts and opts.from then
            audio.play("zap")
        end
        return false
    end
    local ok = Entity.hurt(self, amount, opts)
    return ok
end

function SideMob:push(dx, dy, strength)
    self.vx = util.sign(dx) * strength
    if not self.flying then
        self.vy = -120
    else
        self.vy = util.sign(dy) * strength * 0.5
    end
    self.knockTime = 0.25
end

function SideMob:onHurt(amount)
    audio.play("hit")
    if self.sprite:has("hurt") then
        self.sprite:play("hurt", nil, true)
    end
end

function SideMob:onDeath()
    self:die(false)
end

-- squashed = killed by a stomp
function SideMob:die(squashed)
    if self.dying then
        return
    end
    self.dying = 0.45
    self.team = nil
    local level = self.world.scene
    if squashed and self.sprite:has("dead") then
        self.sprite:play("dead")
    else
        self.squash = true
    end
    audio.play(squashed and "stomp" or "pop")
    level.fx:play("puff", self.x, self.y - self.h / 2, { scale = 1 })
    level.fx:burst(self.x, self.y - self.h / 2, { count = 10, color = { 1, 1, 1 }, speed = 60, life = 0.35, size = 1 })
    if level.onMobKilled then
        level:onMobKilled(self)
    end
end

function SideMob:stomped()
    self.hp = 0
    self:die(true)
end

function SideMob:draw()
    local flip = (self.dir > 0) == (self.facesLeft == true)
    local opts = { flip = flip, scale = self.scale }
    if self.def.ai == "hazard" then
        -- saws spin
        opts.rotation = self.time * 12
        opts.oy = self.sprite.frameHeight / 2
        local s = self.scale
        self.sprite:draw(self.x, self.y - self.sprite.frameHeight * s / 2, opts)
        return
    end
    if self.dying and self.squash then
        local t = math.max(0, self.dying / 0.45)
        love.graphics.push()
        love.graphics.translate(self.x, self.y)
        love.graphics.scale(1 + (1 - t) * 0.6, t)
        love.graphics.translate(-self.x, -self.y)
        self:drawSprite(opts)
        love.graphics.pop()
        return
    end
    self:drawSprite(opts)
end

return SideMob
