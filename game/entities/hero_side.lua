-- Гриша in side view (platformer): runs, jumps (with coyote time and a jump
-- buffer, like in Mario/Celeste), punches, throws stones, stomps enemies.
-- Abilities from game.state.abilities: double_jump, dash, wall_jump.
--
-- The numbers below are the "feel" of the platformer, change them freely.

local Entity = require("engine.entity")
local anim = require("engine.anim")
local audio = require("engine.audio")
local class = require("engine.class")
local input = require("engine.input")
local physics = require("engine.physics")
local ui = require("engine.ui")
local util = require("engine.util")

local function G()
    return require("game")
end

local Hero = class(Entity)

Hero.GRAVITY = 900       -- px/s^2
Hero.FALL_GRAVITY = 1.15 -- falling is a bit faster than rising
Hero.JUMP_CUT = 2.4      -- gravity multiplier when the jump key is released early
Hero.MAX_FALL = 420
Hero.RUN = 100           -- top speed
Hero.ACCEL = 900         -- on the ground
Hero.AIR_ACCEL = 650
Hero.FRICTION = 1200
Hero.JUMP = 320          -- ~57 px high (3.5 tiles)
Hero.DOUBLE_JUMP = 320
Hero.COYOTE = 0.1        -- you can still jump this long after leaving a ledge
Hero.BUFFER = 0.12       -- a jump pressed this long before landing still counts
Hero.DASH_SPEED = 300
Hero.DASH_TIME = 0.18
Hero.WALL_SLIDE = 60
Hero.STOMP_BOUNCE = 240

function Hero:init(x, y, opts)
    Entity.init(self, x, y)
    opts = opts or {}
    local g = G()
    self.sprite = anim.new(g.sprite(opts.sprite or g.player.side or "hero_side"))
    self.w, self.h = 10, 14
    self.height = 16
    self.team = "player"
    self.shadow = false
    self.reflect = false
    self.hp, self.maxHp = g.state.hp, g.state.maxHp
    self.iframes = 1.2
    self.facing = 1
    self.onGround, self.wasOnGround = false, false
    self.coyote, self.buffer = 0, 0
    self.usedDouble, self.usedDash = false, false
    self.dashTime, self.dashCooldown = 0, 0
    self.punchTime, self.cooldown = 0, 0
    self.controlLock = 0
    self.dropTimer = 0
    self.hurtTime = 0
    self.stepTimer = 0
    self.wall = 0
    self.safeX, self.safeY, self.safeTimer = x, y, 0
    self.controllable = true
end

function Hero:has(ability)
    return G().state.abilities[ability]
end

function Hero:jump(power)
    self.vy = -power
    self.onGround = false
    self.coyote, self.buffer = 0, 0
    audio.play("jump")
end

function Hero:update(dt)
    -- Entity.update would apply knockback friction to vx/vy, the hero
    -- has his own physics, so only the timers are used
    self.flash = math.max(0, self.flash - dt)
    self.invulnerable = math.max(0, self.invulnerable - dt)
    self.cooldown = math.max(0, self.cooldown - dt)
    self.punchTime = math.max(0, self.punchTime - dt)
    self.controlLock = math.max(0, self.controlLock - dt)
    self.dashCooldown = math.max(0, self.dashCooldown - dt)
    self.dropTimer = math.max(0, self.dropTimer - dt)
    self.hurtTime = math.max(0, self.hurtTime - dt)

    local world = self.world
    local level = world.scene
    local active = self.controllable and not self.dying and not world.frozen
    local dir = 0
    if active then
        if input.down("left") then dir = dir - 1 end
        if input.down("right") then dir = dir + 1 end
    end
    if self.controlLock > 0 or self.hurtTime > 0 then
        dir = 0
    end
    if dir ~= 0 and self.dashTime <= 0 then
        self.facing = dir
    end

    -- buttons
    if active and input.pressed("jump") then
        self.buffer = Hero.BUFFER
    else
        self.buffer = math.max(0, self.buffer - dt)
    end
    self.coyote = self.onGround and Hero.COYOTE or math.max(0, self.coyote - dt)
    self.wall = 0
    if not self.onGround then
        if physics.touchingWall(world, self, -1) then self.wall = -1 end
        if physics.touchingWall(world, self, 1) then self.wall = 1 end
    end

    if self.buffer > 0 and active then
        if self.onGround and input.down("down") and self.onOneway then
            self.dropTimer = 0.25 -- down + jump: fall through the platform
            self.buffer = 0
        elseif self.coyote > 0 then
            self:jump(Hero.JUMP)
        elseif self.wall ~= 0 and self:has("wall_jump") then
            self.vy = -Hero.JUMP * 0.95
            self.vx = -self.wall * 170
            self.facing = -self.wall
            self.controlLock = 0.16
            self.buffer = 0
            self.usedDouble = false
            audio.play("jump")
            level.fx:burst(self.x + self.wall * 5, self.y - 6, { count = 6, color = { 1, 1, 1 }, speed = 40, life = 0.3, size = 1 })
        elseif self:has("double_jump") and not self.usedDouble then
            self.usedDouble = true
            self:jump(Hero.DOUBLE_JUMP)
            level.fx:play("puff", self.x, self.y - 2, { scale = 0.5 })
            level.fx:burst(self.x, self.y, { count = 8, color = { 0.8, 0.9, 1 }, speed = 50, life = 0.35, size = 1 })
        end
    end
    if active and input.pressed("dash") and self:has("dash") and self.dashCooldown <= 0 and not self.usedDash then
        self.dashTime, self.dashCooldown = Hero.DASH_TIME, 0.45
        self.usedDash = not self.onGround
        self.vy = 0
        audio.play("dash")
    end
    if active and input.pressed("punch") and self.cooldown <= 0 then
        self:punch()
    elseif active and input.pressed("throw") and self.cooldown <= 0 then
        self:throw()
    end

    -- horizontal movement
    if self.dashTime > 0 then
        self.dashTime = self.dashTime - dt
        self.vx = self.facing * Hero.DASH_SPEED
        if love.math.random() < 0.6 then
            level.fx:burst(self.x - self.facing * 4, self.y - 7, { count = 1, color = { 1, 0.95, 0.7, 0.8 }, speed = 10, life = 0.25, size = 2 })
        end
    elseif self.controlLock <= 0 and self.hurtTime <= 0 then
        local target = dir * Hero.RUN
        local accel = self.onGround and Hero.ACCEL or Hero.AIR_ACCEL
        if dir == 0 then
            accel = self.onGround and Hero.FRICTION or 300
        end
        self.vx = util.approach(self.vx, target, accel * dt)
    end

    -- gravity
    if self.dashTime <= 0 then
        local gravity = Hero.GRAVITY
        if self.vy > 0 then
            gravity = gravity * Hero.FALL_GRAVITY
        elseif not input.down("jump") then
            gravity = gravity * Hero.JUMP_CUT -- short hop
        end
        self.vy = math.min(self.vy + gravity * dt, Hero.MAX_FALL)
        if self.wall ~= 0 and dir == self.wall and self.vy > Hero.WALL_SLIDE and self:has("wall_jump") then
            self.vy = Hero.WALL_SLIDE
        end
    end

    -- move
    local hitWall = physics.moveX(world, self, self.vx * dt)
    if hitWall then
        if self.dashTime > 0 then
            level:dashInto(self, self.facing)
        end
        self.vx = 0
    end
    local fallSpeed = self.vy
    local landed, hitCeiling, oneway = physics.moveY(world, self, self.vy * dt, self.dropTimer > 0)
    self.wasOnGround = self.onGround
    if landed then
        self.onGround = true
        self.onOneway = oneway
        self.vy = 0
    else
        if self.vy >= 0 then
            self.onGround = physics.onGround(world, self) and self.dropTimer <= 0
        else
            self.onGround = false
        end
        if hitCeiling then
            self.vy = 0
        end
    end
    if self.onGround then
        self.usedDouble, self.usedDash = false, false
        if not self.wasOnGround and fallSpeed > 150 then
            self:land(fallSpeed)
        end
    end

    -- footsteps
    if self.onGround and math.abs(self.vx) > 20 and self.dashTime <= 0 then
        self.stepTimer = self.stepTimer + dt * math.abs(self.vx) / Hero.RUN
        if self.stepTimer > 0.27 then
            self.stepTimer = 0
            self:footstep()
        end
    else
        self.stepTimer = 0.2
    end

    -- remember a safe place to come back to after falling into a pit
    if self.onGround and not world:hazardAt(self.x, self.y + 2) then
        self.safeTimer = self.safeTimer + dt
        if self.safeTimer > 0.3 then
            self.safeX, self.safeY = self.x, self.y
        end
    else
        self.safeTimer = 0
    end

    self:animate()
    self.sprite:update(dt)
end

function Hero:animate()
    local s = self.sprite
    if self.dying then
        s:play("hurt")
    elseif self.hurtTime > 0 then
        s:play("hurt")
    elseif self.punchTime > 0 then
        s:play("punch")
    elseif self.dashTime > 0 then
        s:play("run")
    elseif not self.onGround then
        s:play(self.vy < 0 and "jump" or "fall")
    elseif math.abs(self.vx) > 85 then
        s:play("run")
    elseif math.abs(self.vx) > 8 then
        s:play("walk")
    else
        s:play("idle")
    end
end

function Hero:surface()
    return self.world:surfaceAt(self.x, self.y + 2) or G().surfaces.default
end

function Hero:footstep()
    local surfaces = G().surfaces
    local s = surfaces[self:surface()] or surfaces[surfaces.default]
    audio.step(s.folder, { volume = s.volume })
end

function Hero:land(speed)
    audio.play("land", { volume = math.min(1, speed / 400) })
    self:footstep()
    self.world.scene.fx:burst(self.x, self.y, { count = 6, color = { 0.9, 0.85, 0.75, 0.8 }, speed = 35,
        life = 0.3, size = 1, angle = -math.pi / 2, spread = 2.4 })
end

function Hero:punch()
    self.punchTime, self.cooldown = 0.22, 0.3
    self.sprite:play("punch", nil, true)
    audio.play("swing")
    local level = self.world.scene
    local x = self.x + self.facing * 10
    local hits = self.world:query(x - 8, self.y - 14, 16, 12, function(e)
        return e.team == "enemy"
    end)
    local any = false
    for _, e in ipairs(hits) do
        if e:hurt(1, { from = self, knockback = 160 }) then
            any = true
            level.fx:play("slash", e.x, e.y - 8, { scale = 0.25 })
        end
    end
    if any then
        audio.play("punch")
        level.camera:shake(2, 0.12)
    end
end

function Hero:throw()
    local level = self.world.scene
    if not G().state.inventory:remove("stone") then
        ui.toast("Нет камней", { icon = "stone" })
        audio.play("error")
        self.cooldown = 0.3
        return
    end
    self.cooldown, self.punchTime = 0.4, 0.12
    audio.play("throw")
    level:throwStone(self.x + self.facing * 6, self.y - 9, self.facing)
end

function Hero:onHurt(amount, opts)
    local level = self.world.scene
    G().state.hp = self.hp
    audio.play("hurt")
    level.camera:shake(4, 0.25)
    level.fx:popup(self.x, self.y - 24, "-" .. amount, { color = { 1, 0.35, 0.3 } })
    self.dashTime = 0
    if opts.from then
        local side = self.x < opts.from.x and -1 or 1
        self.vx, self.vy = side * 140, -170
        self.hurtTime = 0.25
    end
    if self.hp > 0 and self.hp <= 2 then
        audio.play("lowhp")
    end
end

function Hero:onDeath()
    self.dying = true
    self.controllable = false
    audio.play("death")
end

function Hero:heal(amount)
    self.hp = math.min(self.maxHp, self.hp + amount)
    G().state.hp = self.hp
end

function Hero:draw()
    self:drawSprite({ flip = self.facing < 0 })
end

return Hero
